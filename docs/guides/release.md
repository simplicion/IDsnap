# Release Checklist

Releases are cut from `main` by pushing a tag `vX.Y.Z`. `.github/workflows/release.yml`
builds the Android APK and AAB and attaches them to a GitHub Release. They're signed if the
signing secrets are configured, and unsigned otherwise.

## Before tagging
- [ ] CI green on `main` (format, analyze, tests, builds).
- [ ] `version:` bumped in `apps/scanner/pubspec.yaml` (`X.Y.Z+build`).
- [ ] CHANGELOG entry and store release notes, written per DESIGN §7 (no "certified" or "perfect" claims).
- [ ] Airplane-mode checklist passed on the low/mid/high device matrix ([Testing](testing.md)).
- [ ] Accessibility pass: TalkBack/VoiceOver on the scan flow, 200% text, dark mode.
- [ ] Performance budgets met (PRD §11) on the low-tier device.
- [ ] Dependency audit: `flutter pub outdated`, license review of new packages, no new network dependencies.
- [ ] The release manifest has no `INTERNET` permission (`apps/scanner/android/app/src/main/AndroidManifest.xml`).

## Android
- [ ] `key.properties` + keystore configured locally or as CI secrets
      (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`).
- [ ] `flutter build appbundle --release` → upload to the Play Console internal track.
- [ ] Data safety form: "No data collected. No data shared."
- [ ] Verify on a device without the ML Kit scanner module that the fallback works.

## iOS
- [ ] Bundle ID, team and signing set in Xcode (`apps/scanner/ios/Runner.xcworkspace`).
- [ ] Info.plist usage strings: `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
      and `NSPhotoLibraryAddUsageDescription`, all in plain language.
- [ ] `flutter build ipa --release` → TestFlight.
- [ ] App Privacy: "Data Not Collected".

## After release
- [ ] Monitor store reviews for scan-quality complaints; add failing cases to the fixture corpus.
- [ ] Publish the docs image (automatic on tag via `docs.yml`).
