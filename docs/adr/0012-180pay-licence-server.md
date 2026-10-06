# ADR-0012: Sell IDSnap Pro through 180 Pay with a licence server and offline-verified signed licences

| | |
|---|---|
| **Status** | Accepted; **switched off by default since [ADR-0013](0013-free-with-ads.md)** (2026-10-07): the app is free with ads, and everything below applies only to builds made with `--dart-define=IDSNAP_MONETIZATION=licence` |
| **Date** | 2026-10-06 |
| **Supersedes** | [ADR-0009](0009-offline-billing-entitlements.md) |
| **Amends** | [ADR-0008](0008-privacy-no-network.md) (the app now uses the internet, for licensing only) |
| **Deciders** | Product owner, Principal Architect, owners of `engine_billing`, `engine_license`, `feature_paywall`, `contracts`, `apps/license_server` |

## Context
The product owner changed the business model and the payment provider:

- Payments go through **180 Pay** (the owner's gateway), not Google Play Billing / StoreKit.
- **Free day:** 24 hours with every feature, starting when the device first registers.
- Then **Monthly** (US$2.50/month) or a **Day pass** (US$0.10 × N days, N chosen by the user, 1–24 by default). Access ends automatically when paid time ends. **No lifetime plan.**
- **Reinstalling must not give a new free day** → the device must be known to a server.
- **Fully offline once licensed;** internet only to register, pay and refresh.

ADR-0009 (store billing, local trial, no server) can't meet any of these: it has no server, so it can't remember a device across reinstalls, can't take 180 Pay webhooks and can't sell day passes.

## Decision
A small **licence server** of our own takes 180 Pay webhooks and issues **Ed25519-signed licence tokens**; the app verifies them **offline** with a public key built into the app.

```
 app (Flutter)                          licence server (Dart, shelf + SQLite)           180 Pay
 ─────────────                          ─────────────────────────────────────           ───────
 register(deviceHash) ───────────────▶  device row, trial_ends_at = now + 24 h (once)
                      ◀─────────────── signed token {plan, exp, did, …} + serverTime
 checkout(day, 3)     ───────────────▶  order cs_…, amount = 3 × 10¢ (server side) ──▶ session
                      ◀─────────────── checkoutUrl
 browser → 180 Pay page ───────────────────────────────────────────────────────────▶ customer pays
                                         POST /webhooks/180-pay (HMAC) ◀──────────── payment.captured
                                         amount/currency/session must match → paid_until += 72 h
 poll entitlement     ───────────────▶  new signed token (plan: day, exp)
 offline: verify signature + device + exp + clock rollback on every read
```

### Components
| Component | Role |
|---|---|
| `packages/engines/license` (`engine_license`, pure Dart) | Token codec shared by app and server: `LicencePayload`, `LicenceSigner` (server), `LicenceVerifier` (app), `checkLicence`/`evaluateLicence` (device, expiry, clock rollback), `hashDeviceId`, the **dev-only** key pair. |
| `apps/license_server` | `shelf` + `sqlite3` service. Config only from env vars. `PayGateway` interface isolates every 180 Pay detail (`lib/src/gateway.dart`). See its README for API, env vars, deploy, and "VERIFY WITH 180 PAY". |
| `packages/engines/billing` (`engine_billing`) | `LicenceEngine` (storage, refresh, purchase + polling, rollback), `HttpLicenceClient` (**the only network code in the app**), `PlatformDeviceIdentity`, build config checks. The ADR-0009 store engine stays, compiling but unused. |
| `packages/contracts` | `EntitlementState` = `TrialEntitlement(endsAt)` / `DayPassEntitlement(expiresAt)` / `MonthlyEntitlement(renewsAt, expiresAt, willRenew, inGracePeriod)` / `ExpiredEntitlement(reason)`; `ProPricing`, `ProPurchase`, `EntitlementService`. **`featurePolicy`, `ensurePro`, `proRedirect` are unchanged.** |
| `packages/features/paywall` | Paywall (Monthly — recommended — and Day pass with presets 1/3/7 and a stepper up to MAX_DAYS, total shown, nudge to monthly when days × price ≥ monthly price), Settings › Subscription (plan, expiry, Refresh licence, Manage/cancel monthly), terms. |
| `apps/scanner/lib/billing.dart` | Composition: picks licence (default) or store mode, maps engine status → contracts. |

### Licence token
`base64url(payloadJson).base64url(Ed25519 signature)`; payload `{v:1, did, plan: trial|day|monthly, iat, exp, tid, grace?, rn?}` (seconds, server clock). `did` is `sha256("idsnap.device.v1:" + rawDeviceId)` in hex — the raw ID never leaves the phone. An ended licence is still a signed token with `exp` in the past, so "expired" is as trustworthy as "valid". Monthly tokens carry `exp = period end + 3 days grace` (`grace` says how much of that is grace) while the plan renews, so a late renewal check doesn't lock a paying user out.

The app verifies on every start (signature, version, device) and on every entitlement read (device, `exp`, clock). Signature checks use the pure-Dart Ed25519 from `package:cryptography`, so the same code runs on the server and in tests.

### Device identity (no second free day)
- **Android:** `Settings.Secure.ANDROID_ID` via the `idsnap/device_id` method channel in `MainActivity`. Survives uninstall/reinstall; scoped per signing key + user; changes on factory reset.
- **iOS:** a random ID stored in the Keychain through `flutter_secure_storage` (`PlatformDeviceIdentity` fallback). Keychain items survive uninstall, so this survives reinstall. `identifierForVendor` is not used (it resets when the last app of the vendor is removed).
- If the platform can't answer, a random ID in secure storage is used (does not survive an Android reinstall; logged).
- The server's registration is **idempotent** (`INSERT OR IGNORE`): a known device keeps its original `trial_ends_at` forever.

### Clock rollback
`max-time-seen` is kept in secure storage and only moves forward with the phone's clock. Every successful server response **resets it to the server's time**, so: setting the date back offline is detected (licence paused, honest message, restored when the date is fixed); setting it back while online is caught at the next refresh; a phone whose clock was ahead is healed by the next refresh. Tolerance: 10 minutes.

### Network behaviour of the app
- First launch online: register in the background → free day. **Offline with no token: `notActivated`** — paywall and Home say "Connect to the internet once to start your free day"; nothing is unlocked.
- Refresh at start (always) and on resume when useful (no valid licence, expiry within 3 days, or last refresh > 6 h). Server unreachable → the stored licence keeps working.
- Purchase: `POST /v1/checkout` → open `checkoutUrl` in the **external browser** (`url_launcher`, external application) → poll `GET /v1/entitlement` with backoff for ~2 minutes → unlock only when a **new signed token** shows the paid time. The client-side 180 Pay success message is never used.
- `HttpLicenceClient`: 10 s timeout, 2 retries with exponential backoff + jitter for idempotent calls (never for checkout), typed failures (offline, server, invalidResponse, notRegistered, rateLimited, rejected).

### Server rules (summary; details in the server README)
- Prices, currency and day limits come from env vars and are served to the app (`pricing`, `/v1/config`); the app's fallback is labelled "approximate".
- **Amount computed server-side.** A webhook fulfils only when its `sessionId` (or `metadata.orderRef`) matches a pending order **and** amount and currency equal what the server computed. The hosted checkout URL carries the amount in the query string, so an edited URL → underpayment → nothing granted.
- Webhook HMAC exactly as documented (`X-180-Signature`, `X-180-Timestamp`, 300 s window, `HMAC_SHA256(secret, "${ts}.${rawBody}")` over raw bytes, constant-time compare). Idempotent: processed event keys stored; a paid order can't be paid twice.
- Day pass: `paid_until = max(now, paid_until) + N × 24 h`. Monthly: `currentPeriodEnd` when sent, else +1 month; renewals extend; cancellation keeps access to period end without grace; PAST_DUE keeps the 3-day grace; EXPIRED ends access. Unknown events are logged and acknowledged.
- Per-IP, per-device, per-device-checkout and new-trial-per-IP rate limits (in memory: run one instance).

### Build configuration (release agent: wire these as secrets)
| `--dart-define` | Needed for | Value |
|---|---|---|
| `IDSNAP_LICENSE_URL` | every `licence`-mode release build | `https://<licence server>` (https required) |
| `IDSNAP_LICENSE_PUBLIC_KEY` | every `licence`-mode release build | public key printed by `apps/license_server/tool/keygen.dart` (base64url, 32 bytes). Public, but keep it as a CI variable so it matches the server's `LICENSE_SIGNING_KEY`. |
| `IDSNAP_MONETIZATION` | **required for this ADR to apply** | `licence` selects this licence-server model; `store` the Play Billing/StoreKit path (ADR-0009); the default `ads` is the free build (ADR-0013), which reads none of the licence defines. Replaces `IDSNAP_BILLING`. |
| `IDSNAP_SIMULATE_ENTITLEMENT` | debug only | `trial`, `dayPass`, `monthly`, `expired`, `offlineNeverRegistered` (ignored in release). |

`flutter build apk --release --dart-define=IDSNAP_MONETIZATION=licence --dart-define=IDSNAP_LICENSE_URL=https://licence.example.com --dart-define=IDSNAP_LICENSE_PUBLIC_KEY=<key>`

**Fail fast:** a release build started without an https URL, without a key, with a malformed key, or with the published **dev key** throws `LicenceConfigError` at startup (`resolveLicenceSettings`). Debug/profile builds default to `http://localhost:8080` and the dev key (`DevLicenceKeys`, clearly marked; the server refuses the dev private key unless `ALLOW_DEV_KEY=true`). A Gradle-time check of the defines (in `build.gradle.kts`, owned by the release pipeline) is recommended in addition.

### Android network configuration
- `INTERNET` is no longer removed. `ACCESS_NETWORK_STATE` stays removed.
- `res/xml/network_security_config.xml`: no cleartext, system CAs only (no user CAs). The file documents how to restrict TLS to the licence host (edit per deployment). A debug-only override allows cleartext to `localhost`, `127.0.0.1`, `10.0.2.2`.
- `<queries>` includes `VIEW https` so the browser hand-off works on Android 11+.

### Architecture guard
`apps/scanner/test/architecture_test.dart` fails if any shipped package other than `engine_billing` / `engine_license` imports `package:http`/`dio`/`web_socket_channel`/`grpc`, uses `HttpClient`, `HttpServer`, sockets or `WebSocket`, or depends on a network package (incl. Firebase, Sentry, google_fonts). `url_launcher` hand-offs stay allowed.

### Store distribution
Selling digital features inside an app distributed through Google Play or the App Store **may require the store's own billing** (Play Payments policy; App Store Review Guideline 3.1.1). Using 180 Pay is the owner's decision; distribution outside the stores, or an approved alternative-billing programme, may be needed. The ADR-0009 store path is kept compiling (`IDSNAP_MONETIZATION=store`, monthly only) as a fallback.

## Consequences
- Positive: one free day per device, enforced server-side; any payment amount the owner chooses (day passes); full offline use after licensing; access is only ever granted by a verified webhook; prices change without an app release.
- Negative / accepted risks:
  - IDSnap now runs a server (hosting, backups, uptime, key custody) and the app requests `INTERNET`. Documents still never leave the phone (architecture test).
  - A patched or re-signed APK can bypass the check entirely (no client-side scheme prevents that). The dev key in the source is public by design and refused in release.
  - Factory reset (Android) or a new Apple ID / wiped Keychain gives a new device ID → a new free day. Accepted.
  - Several 180 Pay behaviours are undocumented; see "VERIFY WITH 180 PAY" in `apps/license_server/README.md` and the header of `gateway.dart`.
  - Refunds/chargebacks have no documented webhook → not revoked automatically.
  - The in-memory rate limiter limits the server to one instance.

## Validation
- `engine_license`: tamper (every claim), flipped signature bit, signature transplant, wrong key, malformed input, unsupported version, expiry edges, wrong device, rollback and tolerance.
- `license_server`: registration idempotency (no second trial), checkout pricing/validation, webhook (valid, bad signature, tampered body, stale timestamp ±300 s, replay, duplicate, underpayment, wrong currency, missing amount, unknown session), stacking day passes, monthly renew/cancel/past-due/expired, rate limits, config validation, `tool/create_plan.dart` with a fake HTTP client.
- `engine_billing`: first launch online/offline, trial → expiry, day-pass purchase with polling, pending, monthly with grace, offline token use, server unreachable, rollback (offline and via server time), wrong-device and edited tokens, wrong key, pricing fallback, HTTP client retries/mapping, release config checks.
- `feature_paywall`: stepper/presets totals, server limits, nudge to monthly, purchase/pending/offline, not-activated card, subscription screen per plan.
- `apps/scanner/test/licence_e2e_test.dart`: real server in-process + fake 180 Pay: register → checkout → signed webhook → entitlement → app unlocked → offline cold start; underpayment never unlocks.
- **Must be verified with 180 Pay before launch:** a real US$0.10 payment end to end, a monthly subscription with renewal and cancellation via the portal, the webhook payload fields (sessionId, amount unit, metadata echo, subscription status).
