# ADR-0008: Privacy policy in code — no network in core flows, redacted logging

| | |
|---|---|
| **Status** | Accepted, **amended by [ADR-0012](0012-180pay-licence-server.md)** (2026-10-06) |
| **Date** | 2026-09-24 |

## Context
Our main differentiator is "No account. No upload." It has to be verifiable, not a promise.

## Decision
1. No HTTP client dependency in `core`, `domain`, `engines/*`, `data` or `features/*`, **with one
   exception since ADR-0012: the licence client in `engine_billing`** (and the pure token codec
   `engine_license`). `google_fonts` and analytics/crash SDKs are excluded.
2. ~~The Android `INTERNET` permission is only present in debug builds.~~ **Amended:** release
   builds request `INTERNET`, used only by the licence client to register the device, check the
   licence and start a 180 Pay checkout. HTTPS only (network security config, no cleartext).
   `ACCESS_NETWORK_STATE` stays removed.
3. `RedactedLogger` is the only logger. It drops path-like or long strings. `AppFailure`
   never prints its cause.
4. Scoped pickers (Android Photo Picker, iOS PHPicker). No broad storage permission.
5. Sharing is always user-initiated, and the copy tells users the target app may upload the file.
6. Any future network feature needs a new ADR, explicit consent, and an offline alternative.
   (ADR-0012 is that ADR for licensing: once a licence is issued, the app works fully offline.)

## The privacy statement (use these words everywhere)
"Your documents never leave this phone. IDSnap connects to the internet only to check your
licence and for payments."

It replaces the earlier "no internet permission" / "enforced by the OS" claims (privacy banner,
Privacy screen, About, paywall terms). What the licence server receives is listed in
[docs/release/data-safety.md](../release/data-safety.md).

## Validation
- `apps/scanner/test/architecture_test.dart` fails if any shipped package other than
  `engine_billing` / `engine_license` gains HTTP, socket or WebSocket code or a network
  dependency.
- Release gate: run the airplane-mode checklist ([Testing](../guides/testing.md)) with a valid
  licence; with a proxy, confirm the only requests go to the licence server
  (`/v1/devices/register`, `/v1/entitlement`, `/v1/config`, `/v1/checkout`, `/v1/portal`) and
  contain no document data.
