# IDSnap — data safety and privacy disclosures

Source of truth for the Google Play **Data safety** form, the App Store **App Privacy** labels
and the privacy policy. Keep it in sync with ADR-0008 (amended) and
[ADR-0012](../adr/0012-180pay-licence-server.md). Everything below was checked against the code
in `packages/engines/billing` (the app's only network code) and `apps/license_server`.

## One-sentence summary
Your documents never leave this phone. IDSnap connects to the internet only to check your
licence and for payments.

## What leaves the phone, and where it goes

### 1. To the IDSnap licence server (operated by the IDSnap owner)
| Data | Example | Why | Kept |
|---|---|---|---|
| **Hashed device ID** | 64 hex characters: `sha256("idsnap.device.v1:" + ANDROID_ID or Keychain ID)`. The raw device ID is never sent. | One free day per phone; tie a payment to the phone. | While the service runs (it is what prevents a second free day). |
| Platform and app version | `android`, `1.0.0` | Support, compatibility. | Latest value only. |
| Plan and expiry | `day`, paid until 2026-10-09 12:00 UTC | Issue the signed licence. | Account lifetime. |
| Payment sessions / orders | session id `cs_…`, product, days, amount, currency, status | Match the 180 Pay confirmation to the right phone and amount. | Kept as a payment record. |
| IP address | — | Rate limiting only, in memory; **not stored** in the database, **not logged**. | Minutes (in-memory window). |

Requests: `POST /v1/devices/register`, `GET /v1/entitlement`, `GET /v1/config`,
`POST /v1/checkout`, `POST /v1/portal`. No document, image, recognised text, file name,
contact, location, or account identifier is ever sent.

### 2. From 180 Pay to the licence server (server to server, signed webhooks)
| Data | Why | Kept |
|---|---|---|
| Session id, transaction id, amount, currency | Confirm the payment before unlocking. | Payment record. |
| Subscription id, plan code, period end, status | Monthly plan renewals/cancellation. | While the subscription exists. |
| Customer e-mail (only if the customer gave one to 180 Pay) | Open the 180 Pay billing portal for this customer. | With the subscription. |

### 3. To 180 Pay (in the browser, not through the app)
The customer pays on the 180 Pay checkout page in their browser. **Card, UPI and bank details
are entered on 180 Pay's page and stay with 180 Pay**; IDSnap (app and server) never sees them.
The checkout URL contains the order id, amount, currency and product title — no device ID.
180 Pay's own privacy policy applies to that page.

## Google Play Data safety form — suggested answers
- **Does your app collect or share any of the required user data types?** Yes.
- **Device or other IDs** → *Collected* (hashed device ID). Not shared. Processed ephemerally: no.
  Required. Purposes: *App functionality* (licensing), *Fraud prevention, security, and
  compliance* (one free day per device).
- **Financial info → Purchase history** → *Collected* (plan, orders, amounts). Not shared.
  Required for paying users. Purpose: *App functionality*.
- **Personal info → Email address** → *Collected* only for monthly subscribers who give an
  e-mail to 180 Pay, received from 180 Pay. Purpose: *Account management* (billing portal).
  Optional.
- **Financial info → Payment info (card/UPI/bank)** → *Not collected by the app*: handled by
  180 Pay in the browser (declare per Play's guidance on third-party payment processors).
- **Files and docs, Photos, Contacts, Location, App activity, Diagnostics** → Not collected.
- **Data is encrypted in transit** → Yes (HTTPS only; cleartext refused by the network security
  config).
- **Users can request data deletion** → Provide a contact address. Deleting a device row would
  allow a new free day, so on request delete the e-mail address and payment records beyond
  legal retention, and keep only the hashed device ID with its trial date.

## App Store App Privacy — suggested labels
- **Identifiers → Device ID**: collected, not linked to identity, not used for tracking;
  purpose *App Functionality*.
- **Purchases → Purchase History**: collected, not linked to identity (no account), not used
  for tracking; purpose *App Functionality*.
- **Contact Info → Email Address**: only via 180 Pay for subscribers; *App Functionality*.
- No tracking. No data used for advertising.

## Owner checklist before submitting
- Host the licence server; put its privacy-relevant facts (operator, location of the server,
  retention) in the public privacy policy.
- Confirm with 180 Pay which fields its webhooks actually send (e-mail, metadata) and update
  section 2.
- Store distribution: selling digital features with 180 Pay inside a Play/App Store app may be
  against store payment policies (ADR-0012, "Store distribution"). Decide before submitting.
