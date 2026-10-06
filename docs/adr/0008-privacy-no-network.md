# ADR-0008: Privacy policy in code — documents never leave the phone, redacted logging

| | |
|---|---|
| **Status** | Accepted, **amended by [ADR-0012](0012-180pay-licence-server.md)** (2026-10-06) and **[ADR-0013](0013-free-with-ads.md)** (2026-10-07) |
| **Date** | 2026-09-24 |

## Context
Our main differentiator is "No account. No upload." It has to be verifiable, not a promise.

Since ADR-0013 the default build is **free with ads**. Ads need the internet and an advertising
SDK, so the promise is now stated precisely: it is about the user's **documents, IDs and
codes**, not about the app being offline or free of third-party code.

## Decision
1. No HTTP client dependency in `core`, `domain`, `engines/*`, `data` or `features/*`, with two
   exceptions:
   - **`engine_ads`** (ADR-0013) is the only package that may depend on an ads SDK
     (`google_mobile_ads`). It contains no HTTP or socket code of its own; only the SDK talks to
     the network. In the default build this is the app's **only** network traffic.
   - **`engine_billing`** (and the pure token codec `engine_license`) holds the licence client
     (ADR-0012). It is never constructed in the default build; it is used only when the app is
     built with `IDSNAP_MONETIZATION=licence`.

   `google_fonts` and analytics/crash SDKs of our own remain excluded.
2. ~~The Android `INTERNET` permission is only present in debug builds.~~ **Amended:** release
   builds request `INTERNET`. HTTPS only (network security config, no cleartext, system CAs).
   ~~`ACCESS_NETWORK_STATE` stays removed.~~ **Amended by ADR-0013:** `ACCESS_NETWORK_STATE` and
   `com.google.android.gms.permission.AD_ID` are declared because the ads SDK needs them.
   IDSnap's own code uses neither.
3. `RedactedLogger` is the only logger. It drops path-like or long strings. `AppFailure`
   never prints its cause.
4. Scoped pickers (Android Photo Picker, iOS PHPicker). No broad storage permission.
5. Sharing is always user-initiated, and the copy tells users the target app may upload the file.
6. Any future network feature needs a new ADR, explicit consent, and an offline alternative.
   (ADR-0012 is that ADR for licensing; ADR-0013 for ads: consent is gathered before any ad is
   requested, and every feature works offline with no ads.)
7. **The ads SDK never sees vault data.** No ad is placed on a screen that shows documents,
   IDs, codes, notes, passwords or signatures (the placement allowlist in
   `packages/contracts/lib/src/ad_placement.dart`), and nothing from the vault is passed to the
   SDK (no content URLs, keywords or custom targeting).

## The privacy statement (use these words everywhere)
Default build, free with ads (`adsPrivacyLine` in `docscan_contracts`):

> Your documents, IDs and codes never leave this phone. IDSnap is free and shows ads on a few
> screens; the ads are provided by Google, which may use your device's advertising ID.

Paid builds (`paidPrivacyLine`; `licence` / `store` modes, no ads):

> Your documents never leave this phone. IDSnap connects to the internet only to check your
> licence and for payments.

Claims that are **no longer made** in the free build: "no ads", "no tracking", "zero trackers",
"no internet permission", "works fully offline" as a statement about the whole app (the tools do
work offline; say that about the tools). What the ads SDK collects is listed in
[docs/release/data-safety.md](../release/data-safety.md).

## Validation
- `apps/scanner/test/architecture_test.dart` fails if any shipped package other than
  `engine_billing` / `engine_license` gains HTTP, socket or WebSocket code or a network
  dependency; if any package other than `engine_ads` depends on an ads SDK; or if an ad widget
  is used outside the allowlisted screens.
- `apps/scanner/test/billing_wiring_test.dart`: in the default build no licence client is
  constructed.
- Release gate (free build): with a proxy, confirm the only requests go to Google's ads and
  consent hosts and that none is made before the consent step on a first launch; run the
  airplane-mode checklist ([Testing](../guides/testing.md)): every feature works with no
  network.
- Release gate (licence build): the only requests go to the licence server
  (`/v1/devices/register`, `/v1/entitlement`, `/v1/config`, `/v1/checkout`, `/v1/portal`) and
  contain no document data.
