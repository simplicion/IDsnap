# ADR-0009: Sell IDSnap Pro through store billing, with offline entitlements and no server

> **Superseded.** The owner moved payments to 180 Pay with a 1-day free trial,
> monthly and day-pass plans and no lifetime plan: see
> [ADR-0012](0012-180pay-licence-server.md). The store-billing code described
> here still compiles and is selectable with `--dart-define=IDSNAP_BILLING=store`.

| | |
|---|---|
| **Status** | Superseded by [ADR-0012](0012-180pay-licence-server.md) (2026-10-06) |
| **Date** | 2026-10-06 |
| **Deciders** | Product owner, Principal Architect, owners of `engine_billing`, `feature_paywall`, `contracts` |

## Context
IDSnap needs revenue without breaking its promise: no account, no upload, no network
(ADR-0008 removes `INTERNET` from release builds). Business rules from the product owner:

- 30-day free trial with every feature, from first launch. No account, no card.
- Afterwards **IDSnap Pro**: monthly subscription (US$2/month) or lifetime (US$50, one-time).
- No backend of our own.

## Options considered
| Option | Pros | Cons |
|---|---|---|
| A. Store billing (`in_app_purchase`), entitlement decided on-device | No server, no account, stores handle payment/refunds/tax; works with `INTERNET` removed (Play Billing is IPC to the Play Store app) | No server-side receipt validation; subscription expiry is estimated on-device; a patched APK can bypass it |
| B. RevenueCat / own receipt server | Exact expiry, strong validation, cross-platform entitlements | Needs network + third-party SDK + user identifier: violates ADR-0008 |
| C. Paid app up front | Simplest | No trial, no monthly option |

## Decision
**Option A.** Store billing through the official `in_app_purchase` plugin, with the trial,
entitlement cache and purchase verification all on the device. Nothing is sent to any
server by IDSnap.

### Packages
| Package | Role |
|---|---|
| `packages/engines/billing` (`engine_billing`) | `BillingEngine`: trial, purchase stream, verification, cache, resolution. `BillingStore` port + `InAppPurchaseStore` adapter. Depends on `core` only (no contracts). |
| `packages/contracts` | `ProFeature`, `featurePolicy`, `EntitlementState`, `EntitlementService` port, `entitlementProvider`, `ensurePro`, `ProBadge`, `proRedirect`, `Routes.paywall/subscription`. |
| `packages/features/paywall` (`feature_paywall`) | Paywall, Settings › Subscription, subscription terms (local screens). |
| `apps/scanner/lib/billing.dart` | Adapter `BillingEntitlementService` (engine → contracts port); wired in `bootstrap.dart`. |

The entitlement *types and policy* live in `contracts` (product-owner direction; they are a
composition/navigation concern shared by every feature). To keep the rule "engines never
depend on contracts", the engine has its own small status model and the app maps it.

### Products (constants in `BillingProducts`)
| ID | Type |
|---|---|
| `idsnap_pro_monthly` | Auto-renewing subscription, one monthly base plan |
| `idsnap_pro_lifetime` | Non-consumable one-time product |

Prices are never hardcoded: the UI shows the store's localized `ProductDetails.price`.
Only when the store is unavailable (tests, sideloaded build) it shows "$2/month" and
"$50 once", with a visible note that these are US guide prices.

### Entitlement
`entitled = owned lifetime OR active monthly OR active trial` (`resolveEntitlement`, a pure
function). Lifetime beats monthly beats trial.

- **Cache.** The last store-confirmed, verified purchase is stored in
  `flutter_secure_storage` (own namespace `idsnap_billing`), so Pro works offline and at
  cold start before the store answers.
- **Refresh.** At startup and on every resume the engine asks the store what the account
  owns (Android `queryPurchasesAsync`, answered from the Play Store app's cache; iOS
  StoreKit 2 `Transaction.currentEntitlements`). The store is the authority: a plan it no
  longer lists has ended or was refunded.
- **Subscription expiry** is not exposed on-device by the plugin. We cache an estimate: the
  first monthly anniversary of the purchase time after "now" (`nextRenewal`).
- **Grace period.** If the store can't be reached, a cached monthly plan is honoured for
  **3 days** past that date (`subscriptionGracePeriod`), then lapses until the store confirms it.
- **Acknowledgement.** Every verified purchase is completed/acknowledged immediately, and
  again on each refresh if still unacknowledged (Play refunds unacknowledged purchases
  after 3 days). Pending purchases are neither granted nor acknowledged until paid.
- **Monthly → lifetime.** Lifetime is a separate one-time purchase; stores cannot convert a
  subscription into it. The UI tells the user to cancel the monthly plan and links to the
  store's subscription page.

### Local signature verification (Android)
When `IDSNAP_PLAY_LICENSE_KEY` is set, each purchase's `originalJson` is verified against its
RSA-SHA1 signature with the app's Play license public key, in pure Dart
(`PlaySignatureVerifier`), and the signed product ID must match. A failing purchase is not
granted and **not acknowledged**.

```
flutter build appbundle --release --dart-define=IDSNAP_PLAY_LICENSE_KEY=<base64 key from
  Play Console › Monetize › Monetization setup › Licensing>
```

The key is public, so embedding it is fine. If it is empty, verification is skipped. A
**wrong** key makes every real purchase fail verification and get auto-refunded, so the
release checklist must include a real test purchase. iOS: StoreKit 2 verifies its signed
transactions on-device before the plugin reports them.

### Trial
- First-launch time and a "max time seen" are stored in secure storage.
- **Clock rollback:** if `now < maxSeen − 10 min`, the trial (and a cached plan not confirmed
  by the store this session) counts as expired, with an honest message asking the user to fix
  the date. Fixing the clock restores it; lifetime is never affected.
- **Existing installs** upgrading to this version have no record, so they start a fresh 30 days.
- **Reinstall (Android)** resets the trial — accepted limitation without a server/account.
  Android Auto Backup may copy the encrypted file, but its Keystore key never leaves the
  device, so a restored copy is unreadable; the engine deletes it and starts a fresh trial.
  No backup-exclusion rule is therefore needed.
- **Reinstall (iOS)** does not reset the trial: Keychain items survive uninstall.

### Free vs Pro policy
One const map, `featurePolicy` in `packages/contracts/lib/src/entitlements.dart`.
Free forever: opening, viewing, sharing, exporting existing documents; browsing folders;
adding files; the Authenticator (never paywalled); App Lock / folder unlock; reading
secure notes; "Export all data". Pro after the trial: scan, ID card, passport photo, kits,
OCR, PDF/image tools, convert, signature, protect file, QR generator, new notes, batch.

### Gating
- `Future<bool> ensurePro(context, ref, ProFeature)` at entry points (Home quick actions,
  Scan hero, kit tiles, Tools tiles and convert chips). `pushIfPro` is the push shortcut.
- Router backstop: `proRedirect` (go_router `redirect`) sends any locked location to the
  paywall — covers document shortcuts in the vault and deep links. Finishing a scan already
  in progress (review/crop/save/resume) is never blocked.
- **Integration pass for new features** (protect file, QR tools, secure notes): call
  `ensurePro` at their entry points and add their `ToolId`/paths to `_toolFeatures` /
  `proFeatureForLocation` in `pro_gate.dart`. Until then they are not gated.

### Debug / QA override
`--dart-define=IDSNAP_SIMULATE_ENTITLEMENT=trial|trialEnding|expired|clockTampered|monthly|lifetime`
or Settings › Subscription › "Developer: simulate plan". Both are behind the `kReleaseMode`
constant, so they are compiled out of release builds.

### Network / permissions
- `INTERNET` stays removed (`tools:node="remove"`). The Play Billing Library talks to the
  Play Store app over IPC; the Play Store does the networking.
- `com.android.vending.BILLING` is merged by the billing library.
- "Manage subscription" opens `https://play.google.com/store/account/subscriptions?...`
  (or `https://apps.apple.com/account/subscriptions`) with `url_launcher` in
  external-application mode: an intent hand-off, no connection from IDSnap.

## Consequences
- Positive: revenue with no account, no server, no network permission; fully offline use
  after purchase; honest, cancellable subscription.
- Negative / accepted risks:
  - No server-side validation: a patched or re-signed APK can bypass Pro.
  - Subscription end date is an estimate; the store refresh corrects it.
  - Android reinstall resets the trial.
  - iOS has no INTERNET switch; StoreKit networking is done by the OS.
- Follow-ups: integration pass for the new features; store setup (below); device verification.

## Store setup (owner)
**Play Console**: subscription `idsnap_pro_monthly` with one auto-renewing monthly base plan
at US$2 (set local prices); in-app product `idsnap_pro_lifetime` at US$50 (managed,
non-consumable); copy the Licensing key into the release build's
`IDSNAP_PLAY_LICENSE_KEY`; add license testers; upload a signed build to internal testing.
**App Store Connect**: subscription group "IDSnap Pro" with auto-renewable
`idsnap_pro_monthly` (1 month); non-consumable `idsnap_pro_lifetime`; enable the In-App
Purchase capability in Xcode; sandbox testers; paid-apps agreement, tax and banking.

## Validation
- Unit/widget tests: trial math, clock rollback, upgrade from existing install, cache + grace
  + expiry, purchase stream with a fake store (success, pending, error, cancel, restore,
  acknowledge, forged signature), policy map, paywall and gating.
- Release gate: `aapt dump permissions` on the release APK shows no `INTERNET`.
- **Must be verified on a device** (not possible in CI): with `INTERNET` removed, on a
  Play-installed internal-testing build — products load with local prices; buy monthly and
  lifetime with a license tester; pending payment; cancel; restore after reinstall; purchase
  is acknowledged (not refunded after 3 days / 5 minutes for test subscriptions); "Manage
  subscription" opens the Play Store; airplane-mode cold start keeps Pro; the same on iOS
  sandbox.
