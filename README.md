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
| **Comfort** | Light & dark themes · 200 % text support · screen-reader labels · no ads |

Free features cover keeping and viewing your own documents; advanced tools are part of **IDSnap
Pro** (licence-based, see ADR-0012 when present and `docs/adr/0009-offline-billing-entitlements.md`).

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

Debug builds use a local licence server (`http://localhost:8080`, the emulator reaches the host
at `10.0.2.2`) and the published dev key, so no secrets are needed for development.

## Release builds

Release builds **refuse to start** without the licence server settings, so pass them as
dart-defines (a JSON file keeps them out of shell history):

```jsonc
// release-defines.json — never commit this file
{
  "IDSNAP_LICENSE_URL": "https://<licence-server-host>",
  "IDSNAP_LICENSE_PUBLIC_KEY": "<Ed25519 public key, base64url, from apps/license_server/tool/keygen.dart>",
  "IDSNAP_SUPPORT_EMAIL": "<support mailbox>"
}
```

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

Network: the only traffic is HTTPS to the licence server (ADR-0012).
`android/app/src/main/res/xml/network_security_config.xml` refuses cleartext and user CAs. To
also restrict TLS to your licence host, follow the comment in that file and put the host of
`IDSNAP_LICENSE_URL` in its `domain-config` (edit per deployment; not generated from Gradle).

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
the top of `release.yml`; the job fails if any is missing.

## Privacy promise

- No account. Your documents never leave your phone; nothing is uploaded.
- The only network calls are to the licence server (Pro status and checkout: an anonymous
  device id, platform and app version — never documents or document data) and the one-time
  download of Google's document-scanner module on Android. Payment happens in the browser.
- No analytics or crash SDKs. Nothing sensitive is logged.
- Sharing happens only when you tap Share, and the target app handles your file under its own policy.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [Contributing a Tool](docs/guides/contributing-a-tool.md).
Contributions require a prior written agreement with the owner (see LICENSE).

## License

Proprietary. Copyright (c) 2026 Prince kumar. All rights reserved. See [LICENSE](LICENSE).
