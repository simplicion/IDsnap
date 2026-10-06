# IDSnap

**A private vault for your ID documents, with the everyday document tools built in. No account.
Your documents never leave your phone.**

IDSnap keeps scans of ID cards, certificates and everyday paperwork in an encrypted vault on the
device and bundles the tools people usually need five apps for: scanning, passport-size photos,
"compress under 200 KB", merging, signing, password protection and conversion. It's built with
Flutter for Android (first release) and iOS (prepared; needs a Mac build, see below).

> The repository and some package names still say `docscan` (the project's original name). The
> product, store listing and app identifiers are **IDSnap** (`com.idsnap.app`).

## Features

| Area | What you can do |
|---|---|
| **ID Vault** | Encrypted on-device storage for documents (AES-GCM files, SQLCipher database, key in the platform keystore) · nested folders · folder PIN locks · expiry dates with local reminders · search, sort, favourites, rename, share, save to device |
| **Scan** | Platform document scanner with edge detection · gallery import · 4-corner crop · filters · multi-page reorder/rotate/retake · searchable PDF (OCR text layer) · save straight into a folder |
| **ID card** | Front and back of a card on one page, ready to print or send |
| **Passport-size photo** | Live camera with on-device face checks and auto-capture · crop to standard photo sizes (35 × 45 mm, 2 × 2 in, 33 × 48 mm and more) · print sheets |
| **Kits** | Guided "photo + signature + document at the required size" bundles for application portals |
| **PDF tools** | Images → PDF · merge · split/extract · organize pages · compress (incl. to a target size) · PDF → images · sign with saved signatures · password-protect (AES-256 PDF or AES-256 ZIP) · remove a known password |
| **Image tools** | Compress to a target size · resize · crop presets · JPG ↔ PNG |
| **Text (OCR)** | On-device text recognition (Latin and Devanagari bundled) · copy, edit, export TXT/DOCX |
| **Convert** | DOCX ↔ TXT/PDF, PDF → TXT/DOCX, TXT/MD/HTML → PDF, CSV ↔ XLSX, PPTX → TXT, images → DOCX, each with an honest fidelity label |
| **Authenticator** | Offline 2FA codes (TOTP/HOTP) with QR or manual setup; secrets stay in the keystore |
| **QR & barcodes** | Scan and generate codes; `otpauth://` codes hand off to the authenticator |
| **Notes** | Private notes with an optional PIN |
| **Security** | App Lock (biometrics / device credential) · screenshot and recent-apps protection on sensitive screens · optional password-protected backups (AES-256) · no OS cloud backup of vault data |
| **Comfort** | Light & dark themes · 200 % text support · screen-reader labels |

**IDSnap is free: every feature is unlocked for everyone**, with no trial and no paywall. It is
supported by Google AdMob ads on a few screens (Home, Tools, some tool screens, and after a tool
has finished) and never in the ID Vault, the Authenticator, Secure notes, the scanner or Settings
— see [ADR-0013](docs/adr/0013-free-with-ads.md). The earlier paid model (IDSnap Pro: licence
server, ADR-0012; store billing, ADR-0009) is switched off, not deleted: it is still in the code
behind `--dart-define=IDSNAP_MONETIZATION=licence|store`.

> Scans are copies, not certified originals. Conversions state their fidelity; layout-perfect
> Office rendering is intentionally not offered offline (see ADR-0007).

## Monorepo

```
apps/
  scanner/        IDSnap Android + iOS app (composition root)
  license_server/ 180 Pay licence server (Dart)
  marketing-web/  Marketing site (Astro)
  docs/           Documentation site (Flutter web) rendering /docs
  lab/            Engine lab for fixtures and benchmarks
packages/
  core/           Result, failures, logging, format sniffing (pure Dart)
  domain/         Entities, ports, use cases (pure Dart)
  contracts/      Riverpod providers for ports, settings, route contract
  design_system/  Tokens, light/dark themes, components
  data/           Drift/SQLCipher DB, encrypted file store, settings
  engines/        imaging · pdf · ocr · scanner · conversion · vision · security ·
                  reminders · authenticator · codes · billing · license
  features/       home · scan · library · tools · settings · authenticator ·
                  notes · qr · paywall
docs/             PRD, design, architecture, ADRs, guides, audits
tool/             Scripts (docs sync, CI, docker config)
```

Architecture: [docs/architecture/overview.md](docs/architecture/overview.md) ·
Design: [docs/design/DESIGN.md](docs/design/DESIGN.md)

## Development

Requirements: Flutter stable (3.47+, Dart 3.9+), Android SDK with API 36, JDK 17. iOS needs
macOS with Xcode and CocoaPods.

```bash
flutter pub get                      # whole workspace, one lockfile
dart run melos run codegen           # Drift code generation
dart run melos run format:check
dart analyze --fatal-infos .
dart run melos run test

cd apps/scanner && flutter run       # debug build on a device/emulator
```

Melos scripts: `analyze`, `format`, `format:check`, `test`, `codegen`, `run:scanner`, `run:docs`, `run:lab`.

Debug and profile builds always show **Google's test ads** (sample ad units), never the real
ones: tapping your own live ads can get the AdMob account suspended. Run with
`--dart-define=IDSNAP_ADS_DISABLED=true` for no ads at all (screenshots, store listings). To work
on the paid model instead, run with `--dart-define=IDSNAP_MONETIZATION=licence`: debug builds
then use a local licence server (`http://localhost:8080`, the emulator reaches the host at
`10.0.2.2`) and the published dev key.

## Release builds

A normal release build is the **free app with ads** and needs no secret:

```jsonc
// release-defines.json — optional; keeps values out of shell history
{
  "IDSNAP_SUPPORT_EMAIL": "<support mailbox>"
}
```

#### Monetization settings (ADR-0013)

| `--dart-define` | Default | Meaning |
|---|---|---|
| `IDSNAP_MONETIZATION` | `ads` | `ads`: free, every feature unlocked, ads. `licence`: IDSnap Pro through the 180 Pay licence server (ADR-0012), no ads. `store`: IDSnap Pro through Play Billing / StoreKit (ADR-0009), no ads. |
| `IDSNAP_ADS_DISABLED` | `false` | `true`: no ads at all and the ads SDK never starts (screenshots, store listings). |
| `IDSNAP_ADMOB_TEST_DEVICE_IDS` | — | Comma-separated hashed device IDs (the ads SDK prints a phone's ID to logcat on its first ad request). Release build: those phones get test ads. Debug/profile build: the explicit opt-in to use the real ad units on those phones. |
| `IDSNAP_ADMOB_APP_ID_ANDROID`, `IDSNAP_ADMOB_APP_ID_IOS`, `IDSNAP_ADMOB_BANNER_ID`, `IDSNAP_ADMOB_INTERSTITIAL_ID`, `IDSNAP_ADMOB_NATIVE_ID` | from the file below | Override one AdMob ID. Rarely needed. |
| `IDSNAP_LICENSE_URL`, `IDSNAP_LICENSE_PUBLIC_KEY` | — | **Only for `IDSNAP_MONETIZATION=licence`**, where a release build refuses to start without them. Not read in the free build. |

**AdMob IDs** live in one committed file, [`apps/scanner/assets/config/admob.json`](apps/scanner/assets/config/admob.json)
(they are not secrets: they are readable in every APK). Gradle reads it for the manifest and the
app reads it as a bundled asset. To change them: AdMob → *Apps* → IDSnap → *App settings* for
the **App ID** (`ca-app-pub-…~…`), and *Ad units* for each **ad unit ID** (`ca-app-pub-…/…`):
one banner, one interstitial, one native advanced.

A **release build that shows ads fails fast** — at Gradle time and again at app start — if an ID
is missing, malformed, one of Google's sample IDs (they earn nothing), or if the IDs belong to
different AdMob accounts. Debug and profile builds ignore the real IDs and use Google's samples.

**iOS has no AdMob IDs yet**, so ads are off on iOS until the `ios` block of `admob.json` is
filled in (and `ios/Flutter/AdMob.xcconfig` gets the real App ID). An Android release never fails
because of that.

#### Before the first release with ads (owner checklist)

In the **AdMob console**:
- *Privacy & messaging*: create and publish the **European regulations** message and the **US
  states** message for the app. Without them no consent form is shown and users there get
  limited or no ads.
- *Blocking controls*: block sensitive categories; set the **max ad content rating** to PG.
- *Frequency capping* (currently "No cap"): add a cap for interstitials as a second safety net.
- *High-engagement ads* (currently On): decide whether those formats fit a document vault.
- Register your own phones as **test devices**.
- `app-ads.txt`: the app stays "Requires review / Not verified" until
  `apps/marketing-web/public/app-ads.txt` is live at the root of the developer website shown on
  Google Play and the app is published.

In the **Play Console** (answers in [docs/release/data-safety.md](docs/release/data-safety.md)):
- *App content → Ads*: **Yes, my app contains ads**.
- *App content → Advertising ID*: **Yes**, used for *Advertising or marketing* (and analytics
  by the ads SDK).
- *App content → Data safety*: update the form.
- *Target audience*: not directed at children (13+ / 18+ per your markets).

**On a real phone** (a release build, with your phone registered as a test device):
1. First launch with a VPN in an EEA country: the consent form appears before any ad; refuse →
   ads still appear and are non-personalised; *Settings → Ad privacy choices* reopens the form.
2. Home and Tools show one banner above the navigation bar; it disappears with the keyboard;
   nothing is covered; no layout jump when it loads or fails (try Airplane mode).
3. Native cards appear (after a first visit) in the Tools list, on Home with files, on a tool's
   result and in a QR history of 6+ entries; each is labelled "Ad" and shows AdChoices.
4. Finish a tool job twice: no interstitial after the first job ever; one after a later job when
   you leave the result; then none for 3 minutes; never on app open.
5. No ads anywhere in the ID Vault, a document, the Authenticator, Secure notes, the scanner, ID
   card, passport photo, Sign PDF, Protect file, Settings, or while the app is locked.
6. With App Lock on: returning from an interstitial does not re-lock or leave a blank screen.
7. Airplane mode: every feature works, no errors, no empty ad boxes.

### Android

Signing: create `apps/scanner/android/key.properties` (git-ignored) pointing at your upload
keystore — keep the keystore itself outside the repo, with an offline backup:

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Without `key.properties`, local release builds are debug-signed (for device testing only) and CI
release builds fail.

```bash
cd apps/scanner

# Google Play: App Bundle (Play delivers one ABI per phone)
flutter build appbundle --release \
  --dart-define-from-file=release-defines.json \
  --obfuscate --split-debug-info=build/symbols

# Direct download: one APK per ABI, phones only (no x86_64)
flutter build apk --release --split-per-abi \
  --target-platform android-arm,android-arm64 \
  --dart-define-from-file=release-defines.json \
  --obfuscate --split-debug-info=build/symbols
```

Outputs: `build/app/outputs/bundle/release/app-release.aab` and
`build/app/outputs/flutter-apk/app-{arm64-v8a,armeabi-v7a}-release.apk`. Keep `build/symbols`
for each release to read obfuscated stack traces (`flutter symbolize`).

Network: in the free build the only traffic is the Google Mobile Ads SDK's (ads and the consent
form) over HTTPS; IDSnap's own code makes no network calls.
`android/app/src/main/res/xml/network_security_config.xml` refuses cleartext and user CAs and
must **not** be restricted to a single host in a build that shows ads. (A `licence`-mode build,
which shows no ads, talks only to the licence server and may restrict TLS to that host: see the
comment in that file.)

Permissions added for ads: `ACCESS_NETWORK_STATE` and `com.google.android.gms.permission.AD_ID`.

Targets: `minSdk 24`, `targetSdk`/`compileSdk` follow Flutter (36). Before each Play upload,
confirm the required target API in Play Console → Policy status.

### iOS (needs a Mac)

Bundle id `com.idsnap.app`, deployment target iOS 15.5. Set your Apple team once in Xcode:
open `apps/scanner/ios/Runner.xcworkspace` → target **Runner** → *Signing & Capabilities* →
**Team** (this writes `DEVELOPMENT_TEAM` into `ios/Runner.xcodeproj/project.pbxproj` for the
Debug, Release and Profile configurations; do the same for **RunnerTests** if you run its
tests). Then:

```bash
cd apps/scanner/ios && pod install && cd ..
flutter build ipa --release --dart-define-from-file=release-defines.json \
  --obfuscate --split-debug-info=build/symbols
```

### App icon and splash

Generated from `apps/scanner/assets/brand/idsnap_mark.svg` geometry by
`dart run tool/generate_brand_assets.dart` (run in `apps/scanner`): iOS AppIcon set, Android
themed (monochrome) icon, Android 12+ splash icon and the iOS launch logo.

### CI

GitHub Actions: `ci.yml` (format, analyze, tests on every PR and push to `main`; docs web;
debug APK), `docs.yml` (docs image), `marketing-pages.yml` (marketing site), `release.yml`
(tag `vX.Y.Z` → signed AAB + per-ABI APKs on a GitHub Release). Release secrets are listed at
the top of `release.yml`; the job fails if any is missing. The licence secrets are needed only
when the repository variable `IDSNAP_MONETIZATION` is `licence`.

## Privacy promise

- Your documents, IDs and codes never leave this phone. IDSnap is free and shows ads on a few
  screens; the ads are provided by Google, which may use your device's advertising ID.
- No account. Nothing you scan, store or type is uploaded.
- IDSnap's own code makes no network calls. The only connections are made by the Google Mobile
  Ads SDK (to load and measure ads, and for the consent form) and, on Android, the one-time
  download of Google's document-scanner module. The ads SDK has no access to the vault. What it
  collects is listed in `docs/release/data-safety.md`.
- Ads never appear in the ID Vault, on a document, in the Authenticator, in Secure notes, in the
  scanner or in Settings.
- No analytics or crash SDKs of our own. Nothing sensitive is logged.
- Sharing happens only when you tap Share, and the target app handles your file under its own policy.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [Contributing a Tool](docs/guides/contributing-a-tool.md).
Contributions require a prior written agreement with the owner (see LICENSE).

## License

Proprietary. Copyright (c) 2026 Prince kumar. All rights reserved. See [LICENSE](LICENSE).
