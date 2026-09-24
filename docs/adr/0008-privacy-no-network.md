# ADR-0008: Privacy policy in code — no network in core flows, redacted logging

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-09-24 |

## Context
Our main differentiator is "No account. No upload." It has to be verifiable, not a promise.

## Decision
1. No HTTP client dependency in `core`, `domain`, `engines/*`, `data` or `features/*`.
   `google_fonts` and analytics/crash SDKs are excluded.
2. The Android `INTERNET` permission is only present in debug builds (for Flutter tooling).
   The release manifest doesn't request it.
3. `RedactedLogger` is the only logger. It drops path-like or long strings. `AppFailure`
   never prints its cause.
4. Scoped pickers (Android Photo Picker, iOS PHPicker). No broad storage permission.
5. Sharing is always user-initiated, and the copy tells users the target app may upload the file.
6. Any future network feature needs a new ADR, explicit consent, and an offline alternative.

## Validation
Release gate: run the airplane-mode checklist ([Testing](../guides/testing.md)), and confirm
with a proxy that core flows make no network requests.
