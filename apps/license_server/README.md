# IDSnap licence server

Small Dart (`shelf` + `sqlite3`) service that:

1. registers a device (by a salted SHA-256 of its device ID) and starts its **free day**, once per device ever;
2. creates checkout orders for the **day pass** (US$0.10 × N days) and the **monthly plan** (US$2.50), with the amount computed here;
3. takes **180 Pay webhooks** (HMAC-verified) and is the only thing that grants paid time;
4. issues **Ed25519-signed licence tokens** that the app verifies offline until they expire.

Design and rationale: [ADR-0012](../../docs/adr/0012-180pay-licence-server.md).

## API (JSON, `/v1`)

| Method & path | Body / query | Answer |
|---|---|---|
| `POST /v1/devices/register` | `{deviceId, platform: "android"\|"ios", appVersion}` | `{token, serverTime, entitlement, pricing}`. Idempotent: a known device never gets a new trial. |
| `GET /v1/entitlement?deviceId=…` | | Same shape. An ended licence is still a signed token with `exp` in the past. |
| `GET /v1/config` | | Prices, currency, `minDays`/`maxDays`, `serverTime`. |
| `POST /v1/checkout` | `{deviceId, product: "day"\|"monthly", days?}` | `{sessionId, orderRef, checkoutUrl, amount, amountCents, currency}` |
| `POST /v1/portal` | `{deviceId}` | `{portalUrl}`: 180 Pay customer portal (cancel monthly). |
| `GET /v1/checkout/return` | | Static "go back to IDSnap" page (gateway `returnUrl`). |
| `POST /webhooks/180-pay` | raw 180 Pay event | `{received: true}` |
| `GET /healthz` | | `{ok: true}` |

`deviceId` is always 64 lowercase hex characters. Unknown body fields are rejected. Errors are `{error: {code, message}}`. Limits: per IP, per device, checkouts per device, new trials per IP, webhooks per IP (in memory, single instance).

## Run locally

```sh
cd apps/license_server
dart pub get                       # or `flutter pub get` from the repo root
cp .env.example .env               # fill in; .env is git-ignored
dart run tool/keygen.dart          # paste LICENSE_SIGNING_KEY into .env (or use the dev key, below)
set -a; . ./.env; set +a
dart run bin/server.dart
```

Dev shortcut: `LICENSE_SIGNING_KEY` = `DevLicenceKeys.privateKey` from `packages/engines/license/lib/src/keys.dart` with `ALLOW_DEV_KEY=true`. Debug builds of the app trust that key by default, so

```sh
flutter run --dart-define=IDSNAP_LICENSE_URL=http://10.0.2.2:8080   # Android emulator → host
```

works out of the box (debug builds allow cleartext to `10.0.2.2`/`localhost` only). To test webhooks from 180 Pay, expose the port with a tunnel (`ngrok http 8080`) and use **Send Test Webhook** in the 180 console.

Tests (in-memory DB, fake clock, fake 180 Pay HTTP): `dart test`.

## Environment variables

| Name | Default | Notes |
|---|---|---|
| `ONE_EIGHTY_CLIENT_ID` | — required | `180_client_…` |
| `ONE_EIGHTY_CLIENT_SECRET` | — required, secret | `180_secret_…` |
| `ONE_EIGHTY_WEBHOOK_SECRET` | — required, secret | `whsec_…` |
| `LICENSE_SIGNING_KEY` | — required, secret | Ed25519 seed, base64url (`tool/keygen.dart`). The dev key is refused unless `ALLOW_DEV_KEY=true`. |
| `ONE_EIGHTY_CORE_URL` | `https://services.180workspace.com` | |
| `ONE_EIGHTY_PAY_URL` | `https://pay.180workspace.com` | |
| `PUBLIC_BASE_URL` | none | This server's public https URL (checkout `returnUrl`/`cancelUrl`). |
| `TRIAL_HOURS` | `24` | |
| `DAY_PRICE_CENTS` | `10` | |
| `MONTH_PRICE_CENTS` | `250` | Must equal the plan's price at 180 Pay. |
| `CURRENCY` | `USD` | |
| `MIN_DAYS` / `MAX_DAYS` | `1` / `24` | Day-pass range. |
| `MONTHLY_PLAN_CODE` | `idsnap-monthly` | |
| `MONTHLY_GRACE_DAYS` | `3` | Added to a renewing monthly token's `exp`. |
| `ONE_EIGHTY_CHECKOUT_MODE` | `api` | `api` = documented `POST /api/v1/checkout/sessions`; `hosted_url` = build the SDK-style URL with our own session id (experimental, see A9). |
| `ONE_EIGHTY_WEBHOOK_AMOUNT_UNIT` | `major` | `major` (2.50) or `minor` (250). |
| `ONE_EIGHTY_CHECKOUT_HOST_SUFFIX` | `180workspace.com` | Checkout/portal URLs from the gateway must be https on this domain. |
| `PORT` | `8080` | |
| `DATABASE_PATH` | `license.db` | SQLite file (WAL). Back it up: it's the record of who paid. |
| `TRUST_PROXY` | `false` | `true` only behind exactly one proxy that sets `X-Forwarded-For`. |

Nothing secret is ever logged. Logs are one JSON object per line; device hashes are truncated to 8 characters.

## Deploy

1. **Keys.** `dart run tool/keygen.dart`. Put `LICENSE_SIGNING_KEY` in the host's secret store. Keep an offline backup: losing it means every app build must be re-released with a new public key. Put `IDSNAP_LICENSE_PUBLIC_KEY` in the app's release build.
2. **Image.** From the repository root: `docker build -f apps/license_server/Dockerfile -t idsnap-license .` (runs the tests, then `dart build cli`, which bundles SQLite).
3. **Run.** Any container host with a persistent volume and TLS in front (Fly.io, Render, Cloud Run with a volume-backed instance, a VPS with Caddy):
   `docker run -d -p 8080:8080 -v idsnap-data:/data --env-file .env idsnap-license`.
   Run ONE instance: the rate limiter is in memory and SQLite is a single file.
4. **HTTPS.** Terminate TLS at the proxy/platform; set `PUBLIC_BASE_URL` and (behind one proxy) `TRUST_PROXY=true`.
5. **180 console.** Webhook URL = `https://<server>/webhooks/180-pay`; copy the webhook secret into `ONE_EIGHTY_WEBHOOK_SECRET`.
6. **Plan.** `dart run tool/create_plan.dart` (asks before calling the live API), or create `idsnap-monthly` at US$2.50/month in the console.
7. **App.** `flutter build apk --release --dart-define=IDSNAP_LICENSE_URL=https://<server> --dart-define=IDSNAP_LICENSE_PUBLIC_KEY=<public key>`, and add the server's host to `android/app/src/main/res/xml/network_security_config.xml`.
8. **Smoke test** with a real 180 Pay test payment: register → buy 1 day → the app unlocks within a minute → `GET /v1/entitlement` shows `day`.

Key rotation: ship an app build that trusts the new public key (the app accepts one key), then switch the server's `LICENSE_SIGNING_KEY`; old tokens stop verifying and the app simply fetches a fresh one when online.

## VERIFY WITH 180 PAY

Everything gateway-specific is in [`lib/src/gateway.dart`](lib/src/gateway.dart) behind the `PayGateway` interface; that file's header lists the sources. Confirm these before taking real money:

- **A1** Session API auth: docs put `clientId` + `clientSecret` in the JSON body, the developer-portal sample uses `Authorization: Bearer <client_secret>`. We send both.
- **A2** Session API response: `sessionId` (docs) or `id` (sample)? We accept either.
- **A3** Amounts are in major units (2.50) in requests, the checkout URL and webhooks.
- **A4** `metadata` passed when creating a session is echoed in `payment.captured` / `subscription.created`.
- **A5** `subscription.*` events can be tied to our order (sessionId or `metadata.orderRef`); otherwise a subscription can't be matched to a device.
- **A6** Date format of `currentPeriodEnd` / `nextBillingDate`.
- **A7** How PAST_DUE / EXPIRED are signalled (a `status` field? which event?). Only `subscription.cancelled` after dunning is documented.
- **A8** Is there a unique event id for de-duplication? (We fall back to the body hash.)
- **A9** In `hosted_url` mode, how a self-generated session id is bound to our merchant account (the SDK URL carries no client id). Prefer `api` mode.
- **A10** Minimum charge (can US$0.10 be charged at all?), fees (docs: 1.5% platform fee) and whether `data.amount` is gross.
- **A11** `returnUrl`/`cancelUrl` and `mode: "subscription"` + `planCode` behave as documented.
- **A12** Portal sessions with `externalCustomerId` (+ e-mail when we have it).
- **A13** No refund/chargeback event is documented, so refunds don't revoke access.
- Is a server-side "retrieve session/payment" API available? It would let the server confirm a payment without waiting for the webhook.
