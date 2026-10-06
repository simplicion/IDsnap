# ADR-0013: IDSnap is free, supported by ads; billing is switched off, not deleted

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 2026-10-07 |
| **Amends** | [ADR-0008](0008-privacy-no-network.md) (what uses the internet), [ADR-0012](0012-180pay-licence-server.md) (licensing is now an optional mode) |
| **Deciders** | Product owner, Principal Architect, owners of `contracts`, `engine_ads`, `engine_billing`, `feature_paywall` |

## Context
The product owner decided: **every feature is free for everyone** — no trial, no paywall, no
licence server — and the app earns money from **Google AdMob ads**, placed where they don't
disturb people using the app. The goal, in the owner's words: earn as much as reasonably
possible while keeping the experience very good and the annoyance low.

The existing billing (ADR-0012 licence server, ADR-0009 store billing) must be **switched off,
not deleted**, so it can come back (for example as a "Remove ads" purchase).

## Decision

### 1. One build-time switch
`--dart-define=IDSNAP_MONETIZATION=ads|licence|store`, **default `ads`**
(`packages/contracts/lib/src/monetization.dart`). An unknown value fails the build (Gradle) and
the app start (`MonetizationConfigError`).

| | `ads` (default) | `licence` | `store` |
|---|---|---|---|
| Features | all unlocked, for good (`FreeEntitlement`) | trial, day pass, monthly (ADR-0012) | Play Billing / StoreKit (ADR-0009) |
| Licence client, device registration, licence requests | **never built, never made** | yes | no |
| Paywall, Subscription, terms | unreachable (a direct link closes itself) | as before | as before |
| PRO badges, trial banner | never drawn | as before | as before |
| Settings | "IDSnap is free" + "Ad privacy choices" | Subscription | Subscription |
| Ads | **yes**, where the placement policy allows | **none** | **none** |
| Licence defines (`IDSNAP_LICENSE_URL`, `IDSNAP_LICENSE_PUBLIC_KEY`) | not needed, not read | required for release | not needed |
| AdMob IDs | required for release (committed file) | not needed | not needed |

How it is switched off: `startBilling()` returns `FreeEntitlementService` at once in `ads` mode;
`entitlementProvider` is `FreeEntitlement` whatever a service or a debug simulation says;
`ensurePro` returns `true` without opening the paywall; the router redirect returns `null`.
`featurePolicy`, `engine_billing`, `engine_license`, `feature_paywall` and
`apps/license_server` are untouched and their tests run in `licence` mode through
`monetizationModeProvider.overrideWithValue(MonetizationMode.licence)`.

`IDSNAP_BILLING` is retired; `IDSNAP_MONETIZATION=store` replaces `IDSNAP_BILLING=store`.

### 2. Ads architecture
```
features (home, tools, qr) ── AdBannerSlot / AdNativeSlot / maybeShowResultInterstitial
        │                      (docscan_contracts: ad_widgets.dart)
        ▼
AdPlacementPolicy  ◀── THE allowlist and every number (docscan_contracts: ad_placement.dart)
        │
        ▼
AdsService port (docscan_contracts: ads.dart)  ── NoopAdsService everywhere by default
        ▲
        │ adapter: apps/scanner/lib/ads.dart (EngineAdsService)
AdsEngine (packages/engines/ads) ── consent gate, frequency cap, native preloading
        │
        ▼
AdsPlatform ── GoogleAdsPlatform (official google_mobile_ads plugin: AdMob + UMP)
```
- `engine_ads` is the **only** package that may depend on an ads SDK, and it contains no HTTP or
  socket code of its own (architecture test). Features never import it; they use the port.
- Widget tests use `FakeAdsService` (`package:docscan_contracts/testing.dart`) and engine tests a
  fake `AdsPlatform`: no test needs the plugin.
- The interface and the feature-side widgets live in `docscan_contracts` (next to
  `EntitlementService` and `ProBadge`) rather than in `design_system` or a new feature package:
  features may not import each other or an engine, and the widgets need the routes and
  Riverpod, which `design_system` deliberately doesn't have.

### 3. Consent first
1. Nothing about ads runs until an ad slot is actually on screen: not during the vault startup,
   not over the startup or recovery screens, not while the app is locked.
2. Then `AdsEngine.initialize()`:
   `ConsentInformation.requestConsentInfoUpdate` → `loadAndShowConsentFormIfRequired` (Google's
   User Messaging Platform: EEA, UK, Switzerland, and the US states that require it) →
   **only if `canRequestAds()`** → `MobileAds.initialize()` → first ad requests.
3. If consent is required and can't be gathered (first run offline, form closed), the SDK is not
   started and no ad is requested; the next visible slot tries again.
4. **Non-personalised ads when required.** Where the GDPR applies, personalised ads need the
   user's consent to IAB TCF purposes 1, 3 and 4; otherwise every request carries
   `nonPersonalizedAds`. The app reads the TCF values UMP stores (`IABTCF_gdprApplies`,
   `IABTCF_PurposeConsents`) through the `idsnap/ad_consent` channel (`MainActivity.kt`,
   `AppDelegate.swift`); anything unreadable counts as "not allowed". Regional US opt-outs are
   applied by the SDK itself.
5. **Settings › Ad privacy choices** appears when UMP says a privacy-options entry point is
   required and reopens the form; ads loaded under the old choice are dropped.
6. App measurement is delayed until the SDK starts (`DELAY_APP_MEASUREMENT_INIT` /
   `GADDelayAppMeasurementInit`).
7. **iOS:** IDSnap never requests the IDFA: there is no `NSUserTrackingUsageDescription` and no
   App Tracking Transparency prompt. Ads on iOS are therefore not based on cross-app tracking.
   `Info.plist` carries `GADApplicationIdentifier` and the SKAdNetwork IDs. *(See "iOS" below:
   ads are currently off on iOS.)*
8. **Children.** IDSnap is not directed at children. No child or teen treatment is claimed
   (`ageRestrictedTreatment: unspecified`; plugin v9 replaced
   `tagForChildDirectedTreatment` with this setting) and consent requests are sent with
   `tagForUnderAgeOfConsent: false`. Do **not** enrol the app in a "Designed for Families"
   programme without revisiting this.

### 4. Placement policy — `packages/contracts/lib/src/ad_placement.dart`
One file holds the allowlist **and every number**. A screen not named there can't show an ad.

**Forbidden (no ad of any kind):** the ID Vault and every folder and document viewer; the
Authenticator; Secure notes; the app lock and folder lock screens; the scanner / camera /
passport-photo / ID-card capture and review flows; the photo-crop tool; the signature pad and
Sign PDF; the password forms (Protect file, Remove PDF password, backup password); the QR camera
and code result; Settings; the paywall screens; the startup and recovery screens; every dialog
and bottom sheet; any tool opened *for a vault document* (`?doc=`). No app-open ads, no rewarded
ads.

**Allowed:**

| Format | Where | Rules |
|---|---|---|
| **Banner** (anchored adaptive) | Bottom of: Home tab, Tools tab, kits hub, conversion list, QR generator, and the option forms of Merge, Split, Organize, Compress PDF, Compress image, Resize image, Images to PDF, PDF to images, Extract text, and each conversion | Only while the screen is the one in front. Its own space (never covers content), reserved before the ad loads and kept if it fails, so nothing jumps. Hidden while the keyboard is open. On tool forms only while choosing options — gone before the progress appears — and `bannerButtonGap` (20 px) below the main button. Never two banners. After a failed load, banner slots stay closed for `bannerRetryAfter` (5 min) instead of showing an empty strip. Announced as "Advertisement". |
| **Native advanced** (Google native templates) | (a) Tools list, after the 2nd group, never above the first group or search, not while searching. (b) Home, above "Recent files", only if the user has ≥ `homeNativeMinRecents` (1) files. (c) The saved-file panel of a finished job, below the result and all its buttons. (d) QR scan history, after the 5th entry, never in a shorter list | One per screen at most. A tinted, outlined card headed "Ad · Advertisement" (the template adds its own "Ad" badge and the AdChoices icon): it doesn't look like a tool tile or a document row. `nativeCardGap` (20 px) of empty space above and below. **Only an ad that is already loaded is shown**; otherwise the slot is zero height with no gap, and it never changes size during a visit. Ads are preloaded in the background, thrown away after 50 minutes. |
| **Interstitial** | Only when the user **leaves the saved-file panel** of a finished tool job, kit or conversion (Done or back) | Never for the user's first completed task ever; never in the first 60 s of a session; at least 3 min between two; at most 6 per day. Never on app open, on plain back navigation, before or during work, or when leaving a forbidden area. If none is loaded it is skipped at once — the user never waits for an ad. "Start over" is not leaving. |

AdMob policy points the policy is built around: native ads are labelled and distinguishable
from content; no ad sits where a tap meant for the app is likely to land on it (the two gap
constants; no ad next to a primary button; banners close while a job runs); no screen is only
an ad plus an exit (the result stays on screen with the native card); no interstitial on app
load, on exit or unexpectedly; nothing encourages a tap.

**Interpretation to confirm with the owner — App Lock.** With App Lock on, Android's
`FLAG_SECURE` is set for the whole app window, including Home and Tools. This ADR reads "no ads
on FLAG_SECURE screens" as *the screens that are secured in their own right* (Authenticator,
locked folders, notes — all forbidden above) and still shows ads on Home and Tools for App Lock
users; nothing is shown while the lock screen is up. Reading it the other way would mean no ads
at all for everyone who turns App Lock on.

### 5. AdMob IDs
- Publisher `pub-6432767564862835`. **One committed file**,
  `apps/scanner/assets/config/admob.json`, holds the Android App ID and the banner,
  interstitial and native ad units. Gradle reads it for the manifest
  (`com.google.android.gms.ads.APPLICATION_ID` via the `admobAppId` placeholder); the app reads
  the same file as a bundled asset. AdMob IDs are not secrets (they are in every APK).
- `flutter build appbundle --release` therefore needs **no extra flags**. Overrides:
  `IDSNAP_ADMOB_APP_ID_ANDROID`, `IDSNAP_ADMOB_APP_ID_IOS`, `IDSNAP_ADMOB_BANNER_ID`,
  `IDSNAP_ADMOB_INTERSTITIAL_ID`, `IDSNAP_ADMOB_NATIVE_ID`.
- **Debug and profile builds always use Google's sample IDs** for every format, whatever is
  configured: tapping your own live ads can get the AdMob account suspended. The only way to the
  real units outside release is the explicit opt-in
  `--dart-define=IDSNAP_ADMOB_TEST_DEVICE_IDS=<hashed id>[,…]`, which registers those phones as
  test devices (they then get test ads from the real units). The same define in a release build
  makes those phones safe to test with.
- **Release fail-fast**, twice: Gradle fails the build, and the app refuses to start
  (`AdsConfigError` on the startup recovery screen), if an ID is missing, malformed, one of
  Google's sample IDs (they earn nothing), or the IDs belong to different AdMob accounts.
- `--dart-define=IDSNAP_ADS_DISABLED=true`: kill switch for screenshots and store listings. The
  no-op service is wired and the SDK never starts.

### 6. iOS
No iOS AdMob app or ad units exist yet. While the `ios` block of `admob.json` is empty, **ads are
off on iOS** (the no-op service) in every build type, and an Android release never fails for
missing iOS IDs. `ios/Flutter/AdMob.xcconfig` supplies Google's *sample* App ID for
`GADApplicationIdentifier` only so the linked SDK has a well-formed value; the SDK is never
started. To turn iOS ads on: create the iOS app and units in AdMob, fill the `ios` block, put
the real App ID in `AdMob.xcconfig`, refresh the SKAdNetwork list, and re-check App Privacy.

### 7. Android manifest and network
- `INTERNET` stays. **`ACCESS_NETWORK_STATE` is allowed again** (it was removed while nothing
  needed it): the ads SDK checks for a connection before requesting ads. IDSnap's own code still
  never reads the network state.
- `com.google.android.gms.permission.AD_ID` is declared (the SDK declares it too).
- `network_security_config.xml`: still no cleartext and system CAs only, and **not** restricted
  to one host — a domain rule for the licence server would stop every ad. (Restricting TLS to
  the licence host remains possible for `licence`-mode builds, which show no ads.)
- Paid-mode builds still link the ads SDK and declare `AD_ID`; the SDK is never started. If
  the app ever ships paid-only, remove `engine_ads` from `apps/scanner/pubspec.yaml`.

### 8. Privacy statement (use these words everywhere, `adsPrivacyLine`)
> Your documents, IDs and codes never leave this phone. IDSnap is free and shows ads on a few
> screens; the ads are provided by Google, which may use your device's advertising ID.

It replaces "IDSnap connects to the internet only to check your licence and for payments" in
the free build (Home banner, Privacy, About, marketing site, store listing). What the ads SDK
collects is listed in [docs/release/data-safety.md](../release/data-safety.md).

## Consequences
- Positive: no server to run, no payment provider, no store-billing policy question; everyone
  gets every feature; the placement and the caps are one reviewable file with tests.
- Negative / accepted:
  - The app now contains a third-party advertising SDK that uses the internet, the advertising
    ID and device data. "No tracking / zero trackers / no ads" claims are gone. Documents still
    never leave the phone (architecture test; the SDK has no access to the vault).
  - Revenue depends on fill and on users being online; offline users see no ads and lose
    nothing.
  - APK size grows (see the release notes for measured numbers).
  - Play Console declarations change: "Contains ads", Data safety, Advertising ID.
  - AdMob policy risk if placements change carelessly — hence the allowlist and its tests.

## Settings the owner applies in the AdMob console (not in code)
- **Blocking controls › Sensitive categories:** block the categories that don't belong next to
  ID documents (for example gambling, dating, alcohol, "get rich quick", sexual and
  reproductive health, significant skin exposure, politics, religion).
- **Max ad content rating:** set **PG** (or G) for the app.
- **Frequency capping** is currently "No cap": set an account/app-level cap for interstitials
  as a second safety net (for example 1 impression per 3 minutes and 6 per day, matching the
  app).
- **High-engagement ads** is currently On: these are more intrusive formats; review whether
  they fit a document vault and consider switching them off for the interstitial unit.
- **Privacy & messaging:** create and publish the **European regulations (GDPR)** message and
  the **US states** message for this app. Without a published message UMP shows no form, and
  users in those regions get limited or no ads.
- **app-ads.txt:** the app shows "Requires review / Not verified" until `app-ads.txt` is live
  at the root of the developer website listed on Google Play
  (`apps/marketing-web/public/app-ads.txt`) and the app is published.
- Register your own phones as **test devices** before installing a release build.

## Validation
- `packages/contracts/test/ad_placement_test.dart`: the route allowlist per format, every
  forbidden area, every `ToolId` placed on purpose, the numbers.
- `packages/contracts/test/ad_widgets_test.dart`: slots placed on forbidden routes show and
  request nothing; keyboard; lock; consent not resolved; native slots collapsing; 2× text.
- `packages/contracts/test/monetization_test.dart`, `apps/scanner/test/billing_wiring_test.dart`:
  the three modes; every `ProFeature` usable; `ensurePro` true without the paywall; **no licence
  HTTP client is constructed** (a factory that fails the test).
- `packages/engines/ads/test`: consent gating (no request before consent, non-personalised when
  required), frequency caps with a fake clock (first task, 60 s warm-up, 3 min gap, 6 per day,
  day rollover, clock set back), native preloading, ID checks.
- `packages/features/{home,tools,qr,settings,paywall}/test`: banner and native placement, no
  overflow at 2× text, interstitial only on leaving a result, no ads in Settings.
- `apps/scanner/test/app_integration_test.dart`: the real app and router — no ad widget on any
  forbidden screen (vault, viewer, authenticator, notes, settings, scanner, lock screen).
- `apps/scanner/test/architecture_test.dart`: only `engine_ads` links an ads SDK; ad widgets
  appear only in the allowlisted source files; no network code elsewhere.
- **On a real phone before launch:** see the README checklist (consent form in an EEA test
  geography, test ads in each slot, caps, offline behaviour, lock screen).
