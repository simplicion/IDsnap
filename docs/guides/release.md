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
- [ ] Permissions are exactly the expected set (`aapt dump permissions` on the APK): `INTERNET`,
      `ACCESS_NETWORK_STATE` and `com.google.android.gms.permission.AD_ID` are there for the ads SDK
      only ([ADR-0013](../adr/0013-free-with-ads.md)); no storage, location, contacts or microphone
      permission.
- [ ] Ads ([ADR-0013](../adr/0013-free-with-ads.md)): AdMob IDs in `apps/scanner/assets/config/admob.json`
      are the real ones (a release build fails otherwise); consent messages are published in AdMob;
      the real-phone ad checklist in the README passed; Play Console "Contains ads", Advertising ID
      and Data safety match [data-safety.md](../release/data-safety.md).

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
