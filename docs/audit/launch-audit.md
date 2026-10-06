# IDSnap launch audit

Date: 2026-10-06 · Scope: working tree of `main` (224 uncommitted paths) · Method: read-only code
review, `dart analyze`, `flutter test` in every package, inspection of the release artifacts in
`build-artifacts/`. No source file was changed by this audit.

Two other agents were editing while this ran (encryption at rest + secure notes; billing → "180 Pay"
licence server). Findings in their areas are marked **in flux** and should be re-checked when they
land. Everything else was verified by reading the code path end to end, not by trusting comments.

Paths are relative to the repo root. Abbreviations: `contracts` = `packages/contracts/lib/src`,
`f/<x>` = `packages/features/<x>/lib/src`, `app` = `apps/scanner`.

---

## 1. Executive summary

**Launch blockers: 3** (1 in shared code, 1 Android store, 1 iOS store) · **High: 9** · Medium: 19 · Low: 11

The app is much closer to shippable than the size of the uncommitted diff suggests: every route has
a UI entry point, tests pass in every package (968 tests, see §6), folder locks are enforced in the
data layer, and the error model is mostly actionable. The problems are concentrated in the
**composition root and the seams between features built by different agents**:

1. **Two ports are never wired in `app/lib/bootstrap.dart`.** `SheetPdfBuilder` is missing, so
   *ID card → Save* and *Passport photo → Print sheet* throw `UnimplementedError`, and because the
   save is fire-and-forget the screen sits on a spinner forever with Back disabled (B-01).
   `ReminderScheduler` is missing, so expiry reminders silently never fire although Settings has a
   switch for them and the manifest asks for notification permission (H-01). Package tests pass
   because each one injects its own fakes; nothing tests the real `buildOverrides()`.
2. **Folders were added but only the scan flow uses them.** ID card, kits, passport photo and every
   tool save to the vault's top level; ID card and kits even say "Filed in IDs & Proofs / Education",
   a category the library UI no longer shows (H-03).
3. **The migration and deletion stories are incomplete for a vault.** OS backup is (correctly)
   disabled, so "Export all data" is the only way to move phones, but it leaves out authenticator
   accounts and saved signatures (H-04) and builds the whole ZIP in memory on the UI isolate (H-05).
   "Delete all documents" skips locked folders, notes and the authenticator (H-06). Plaintext copies
   of imported/scanned sources stay in the app cache outside the encrypted vault (H-07).
4. **Store readiness:** `targetSdk` is pinned to 35 while the project's own Flutter SDK defaults to
   36 (B-02); iOS still has the Flutter template icon, the `com.docscan.docscanScanner` bundle id
   and no signing team (B-03).
5. **Architecture in flux:** the release manifest strips `INTERNET` and the in-app Privacy/Terms
   text says "no servers", which the 180 Pay licence server will contradict (H-09).

Smallest path to a launchable Android build: fix B-01, B-02, H-01 (or remove the switch and the
permissions), H-02, H-06, H-08, then decide H-03/H-04/H-05 scope. B-01 and H-01 are one line each
plus a test.

---

## 2. Findings

Effort: **S** ≤ half a day · **M** 1–2 days · **L** 3+ days.

### BLOCKER — crash, data loss, store rejection or a feature that does not work

| ID | Area | What is wrong | Evidence | How to verify | Suggested fix | Effort |
|---|---|---|---|---|---|---|
| **B-01** | Bootstrap · ID card · Passport photo | `sheetPdfBuilderProvider` defaults to `throw UnimplementedError` and is never overridden in the app. `IdCardFlowController.save()` sets `IdCardSaving`, then reads the provider and throws. The screen calls it with `unawaited(...)`, so the error is swallowed; state stays `IdCardSaving`; the screen has `PopScope(canPop: false)`, ignores back while saving and hides the app-bar Back button. The user is stuck on a spinner and must kill the app; the captured photos are never saved. `savePrintSheet()` in the passport flow has the same call and sticks on `PassportSaving`. (`saveJpeg()` is fine.) The implementation exists and is tested: `SheetPdfBuilderImpl`. | `contracts/providers.dart:117-119` · `app/lib/bootstrap.dart:76-118` (no `sheetPdfBuilderProvider` line; HEAD had none either) · `f/scan/id_card/id_card_controller.dart:347-359` · `f/scan/id_card/id_card_screen.dart:128-150, 199` · `f/scan/passport_photo/passport_photo_controller.dart:481-510` · `f/scan/passport_photo/passport_photo_screen.dart:563` · impl `packages/engines/pdf/lib/src/sheet_pdf_builder.dart:15` · only tests override it: `packages/features/scan/test/id_card_fakes.dart:190`, `passport_photo_fakes.dart:210` | On a device: Home → "ID card (front & back)" → capture both sides → Save. Spinner never ends. Same for Passport photo → Print sheet. Or `grep -rn sheetPdfBuilderProvider apps/` → no hits. | Add `sheetPdfBuilderProvider.overrideWithValue(const SheetPdfBuilderImpl())` to `buildOverrides`. Wrap both `save` bodies in try/catch → `…SaveFailed`. Add an app test that builds a `ProviderContainer` from the real override list and reads every port provider in `contracts/providers.dart` (see M-08). | S |
| **B-02** | Android · Play | `targetSdk = 35` is hard-coded. The Flutter SDK in use defaults to `targetSdkVersion = 36` / `compileSdk = 36`, and Google Play's yearly rule moves the minimum for new apps and updates to API 36 from 31 Aug 2026, so an upload today is expected to be rejected. (Confirm the exact date in Play Console → Policy status; the pattern has held every year.) | `app/android/app/build.gradle.kts:35` · `flutter_sdk/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:23,34` | Upload the AAB to an internal track; Play Console reports the target-API error. | `targetSdk = flutter.targetSdkVersion`. Then re-test on Android 16: edge-to-edge is mandatory (no opt-out) and predictive back is on — check the `PopScope` screens (ID card, kits, save) and the lock screen. | S + device pass |
| **B-03** | iOS · App Store | iOS is not submittable: (a) the app icon set is still the Flutter template logo (Android has the real IDSnap icon); (b) bundle id is `com.docscan.docscanScanner` while Android/billing use `com.idsnap.app`; (c) no `DEVELOPMENT_TEAM`; (d) project deployment target 15.0 vs Podfile 15.5 (ML Kit needs 15.5); (e) launch image is the template. Only blocks an iOS launch. | `app/ios/Runner/Assets.xcassets/AppIcon.appiconset/*` (unchanged in git, Flutter logo) · `app/ios/Runner.xcodeproj/project.pbxproj:386,567,589` and `:363,490,542` · `app/ios/Podfile:2` | Open the icon PNGs; `grep PRODUCT_BUNDLE_IDENTIFIER project.pbxproj`. | Generate icons/launch screen, set bundle id + team, set deployment target 15.5, run a TestFlight build. If iOS is not in the first launch, say so in README/marketing (the site advertises iOS). | M |

### HIGH — feature incomplete, unreachable or not actually active

| ID | Area | What is wrong | Evidence | How to verify | Suggested fix | Effort |
|---|---|---|---|---|---|---|
| **H-01** | Expiry reminders | `reminderSchedulerProvider` is never overridden, so `_schedule()` always lands in its `catch` and returns false. Reminders are never scheduled, yet Settings › Your data shows an "Expiry reminders — Local notifications 30 and 7 days before a document expires" switch (default on), the manifest requests `POST_NOTIFICATIONS` + `RECEIVE_BOOT_COMPLETED` and registers the notification receivers, and `engine_reminders` is a dependency. The engine itself exists and has tests. | `contracts/providers.dart:124-126` · `app/lib/bootstrap.dart:76-118` · `f/library/document_actions.dart:171-185` (catch-all "Reminders not wired") · `f/settings/data_screen.dart:176-183` · `app/android/app/src/main/AndroidManifest.xml:13,15,61-74` · `packages/engines/reminders/lib/src/local_reminder_scheduler.dart:88` | Set an expiry date on a document: the snack says "Expiry date saved" (never "You will be reminded…"); no permission prompt appears. | Wire `LocalReminderScheduler` in bootstrap, add ProGuard keep rules for `flutter_local_notifications` (Gson), reschedule after import; or remove the switch, permissions and receivers for v1. Narrow the `on Object` catch so a real scheduling failure is shown. | S–M |
| **H-02** | Vault viewer · protected PDFs | A password-protected PDF stored in the vault cannot be opened in the app. `_PdfPages._open()` calls `pageCount`, the engine returns `passwordProtected`, and the viewer renders `FailureView.new` with no handlers: the text says "Enter its password when asked…" but nothing asks, and the default action ("Choose another file") has no handler in a viewer. The password prompt exists (`unlockProtectedPdfs`) but only the tool pickers use it. Protect file can save its output to the vault, so the app creates documents its own viewer cannot show. | `f/library/document_screen.dart:377-385, 473` · `packages/engines/pdf/lib/src/pdf_engine_impl.dart:63-64, 411-417` · `packages/core/lib/src/failure.dart:58-63` · prompt lives in `f/tools/protect/unlock_inputs.dart` (used at `f/tools/common/input_picker.dart:116-118, 243-245`) | Tools → Protect file → PDF → save to vault → open it from ID Vault. | In `_PdfPages`, on `passwordProtected` show a password field, decrypt to a temp copy (`PdfProtector.unlock` → `releaseTemp` on dispose) and render that; offer "Remove password" as the secondary action. Add a widget test. | M |
| **H-03** | Folders ↔ ID card, kits, passport photo, tools | Only the scan flow can save into a user folder. ID card, kits "Save all", passport photo, protect file and every tool result call `commitOutput` without `folderId`, so output lands at the vault's top level. ID card and kits additionally write the legacy `DocumentCategory`/`slot` and tell the user "Filed in IDs & Proofs" / "Filed under Education" — the library UI has no reference to categories any more, so that location does not exist on screen. This is the hard-coded structure the owner asked to replace with user-created folders. The folder "+" menu offers only New folder / Upload / Scan (no ID card, no passport photo). | `f/scan/id_card/id_card_controller.dart:370-390` · `f/scan/id_card/id_card_screen.dart:776, 809` · `f/tools/kits/kit_controller.dart:219-244` · `f/tools/kits/kit_screen.dart:46-50` · `f/tools/kits/kit_catalog.dart:25,45,66,101` · `f/scan/passport_photo/passport_photo_controller.dart:458-467, 512-521` · `packages/domain/lib/src/usecases/commit_output.dart:30` (supports `folderId`) · `f/library/folders/add_menu.dart:36, 50-68` · no `category` use anywhere under `packages/features/library/lib` | Save an ID card copy: success screen says "Filed in IDs & Proofs"; ID Vault shows it at top level and no such folder. | Add a shared "Save to folder" picker (reuse `pickFolder`) to the ID card preview, kit save, passport save and `ResultSheet`; pass `folderId` to `commitOutput`; drop the "Filed in/under" lines and the legacy category writes; add ID card + passport photo to the folder "+" menu with `folderId`. | M |
| **H-04** | Export / phone migration | "Export all data" is presented as "the way to move to a new phone" (OS backup and device transfer are disabled, correctly, because the key is Keystore-bound). The ZIP contains documents, folders and notes only. Not included and not mentioned: **authenticator accounts** (secrets live only in the Keystore and the authenticator has no export of its own, and Google Authenticator migration QR codes are rejected), saved signatures, QR history, folder/note PINs, custom kits, settings. A user who follows the app's instructions loses every 2FA account on the old phone. | `f/settings/data_screen.dart:41-50, 135-142` · `packages/data/lib/src/zip_library_archiver.dart:53-131` · `app/android/app/src/main/AndroidManifest.xml:26-28` + `res/xml/data_extraction_rules.xml` · no export in `packages/features/authenticator/lib` (grep `export|backup` → none) · `packages/engines/authenticator/lib/src/otpauth_uri.dart:15-16, 53` | Add an authenticator account, export, erase/reinstall, import: the account is gone. | Minimum (S): say so in the export dialog and on the Authenticator tab ("codes are not in the backup — move each account on its website first"). Proper (M): per-account "Show setup QR" behind the reveal gate, and/or include `otpauth://` URIs and signatures in the export behind the existing re-authentication. | S / M |
| **H-05** | Export / import robustness | `exportAll()` decrypts every document into an in-memory `Archive`, then `ZipEncoder().encodeBytes` builds a second full copy and returns a `Uint8List`, which is then handed to `saveToDevice(bytes, …)` — roughly 2–3× the vault size in RAM, on the UI isolate (no `Isolate.run`). `importArchive()` does `File(zipPath).readAsBytes()` + `decodeBytes`. A vault of a few hundred MB will freeze and then be killed for memory; since this is the only migration path, that is effectively data lock-in. Any export error is also reported as "Not enough storage" (`guard(..., code: insufficientStorage)`), and imported documents get no thumbnails. | `packages/data/lib/src/zip_library_archiver.dart:53-141, 160-176, 228-229` · port returns bytes: `packages/domain/lib/src/ports/roadmap_ports.dart:89` · `f/settings/data_screen.dart:57-74` | Fill a test device with ~400 MB of scans and export; watch memory / ANR. | Stream to a temp file (`ZipFileEncoder` / `OutputFileStream`, one document at a time), change the port to return a path, run in an isolate, save via a path-based `saveToDevice`. Import with `InputFileStream`. Map failures properly. | M |
| **H-06** | Settings · Delete all | "Delete all documents" ("Every scan and file in IDSnap will be removed", button "Delete everything") enumerates with `repo.watch(const DocumentQuery())`, which by design hides everything inside locked folders. Those documents stay, with no message. It also leaves notes, authenticator accounts, saved signatures, QR history, folders and pending reminders. The Privacy screen promises "Delete … everything at once from Settings → Storage". The storage bar and the "Deleted N documents" count have the same blind spot. | `f/settings/settings_screen.dart:451-486` (query at `:477`) · `packages/data/lib/src/drift_document_repository.dart:47-61` · `f/settings/privacy_screen.dart:52-56` | Lock a folder with a document in it → Settings → Delete all documents → unlock the folder: the document is still there. | Use `repo.all()` (the archiver already does), re-authenticate first (as export does), and either rename the action to what it does or add a real "Erase everything" that reuses `eraseVault` + authenticator/notes/signature/QR stores. | S–M |
| **H-07** | Encryption at rest · temp files | Sources are encrypted when they enter the vault, but the plaintext originals stay in the app cache: `importOriginal()` encrypts a copy and never deletes the external file (ML Kit scanner JPEGs, `image_picker` re-encoded copies, `file_picker` cache copies), and the app's own `<cache>/picked/<id>/` copies are never removed. `clearTemp()` — at launch and from "Clear temporary files" — only shreds `<cache>/docscan/{tmp,view,share}`. So photos of IDs remain unencrypted in app-private cache until Android evicts it, while the UI says vault files are encrypted (AES-256). Not readable by other apps without root, but it weakens the at-rest claim. **In flux** (encryption agent). | `packages/data/lib/src/local_file_store.dart:119-134, 258-265` · `packages/engines/scanner/lib/src/platform_media_picker.dart:22-36, 76-88` · callers `f/scan/scan_session_controller.dart:119`, `f/scan/id_card/id_card_controller.dart:205` · claims: `f/settings/privacy_screen.dart:21-27`, `about_screen.dart:43-46` | Scan and save a document, then `adb shell run-as com.idsnap.app ls -R cache` (debug build): source images are still there. | After a successful `importOriginal`, shred the source when it lives under the app cache; put `picked/` under the vault cache root; make launch cleanup and "Clear temporary files" sweep the picker/scanner cache directories. Add a test that the cache is empty after a scan → save. | M |
| **H-08** | Startup error handling | `startApp()` catches only `VaultUnavailableException`. Anything else thrown by `buildOverrides()` (PDFium init, font asset, database open/migration `StateError`, path_provider) leaves the user on `VaultStartupScreen`, which is a blank page when there is no migration progress — a white screen forever with no message. There is also no `FlutterError.onError` / `PlatformDispatcher.onError` / `runZonedGuarded`, so uncaught async errors (such as B-01) vanish. Related: `startBilling()` is awaited with a 5 s timeout before the first real frame, behind a blank template splash. | `app/lib/vault_startup.dart:15-38, 66` · `app/lib/main.dart:4-7` · `app/lib/bootstrap.dart:34, 46, 74` · `app/lib/billing.dart:30-35` · `packages/data/lib/src/vault/encrypted_database.dart:44, 122` | Make `initPdfEngine()` throw in a debug build: blank screen. | Catch `Object` in `startApp()` and show a recovery screen (what failed, Retry, "copy details"); install global error handlers that log through `RedactedLogger`; start billing after the first frame. | S |
| **H-09** | Billing ↔ privacy architecture (**in flux**) | Three things currently contradict each other and need one decision: (a) the release manifest removes `INTERNET`/`ACCESS_NETWORK_STATE` (ADR-0008) — fine for Play Billing, which talks to the Play Store over IPC, but a "180 Pay" licence server cannot be reached without it; (b) in-app Privacy and Subscription terms say "IDSnap has no … servers" and "Purchases are handled entirely by Google Play"; (c) the paywall, terms, cancel instructions and `androidPackageName` management link are all store-specific. Also today: Play purchase signatures are verified only if the build passes `--dart-define=IDSNAP_PLAY_LICENSE_KEY=…`, and neither workflow does, so a CI release build accepts unverified purchase data. | `app/android/app/src/main/AndroidManifest.xml:4-7` · `docs/adr/0008-privacy-no-network.md`, `0009-offline-billing-entitlements.md` · `f/settings/privacy_screen.dart:10-13` · `f/paywall/terms_screen.dart:41-46` · `f/paywall/copy.dart:28-37` · `packages/engines/billing/lib/src/play_signature.dart:8-14` · `.github/workflows/release.yml:47-51` | Build release, run `aapt dump permissions` on the APK; search the workflows for `IDSNAP_PLAY_LICENSE_KEY`. | Decide the model, then update manifest, ADR-0008/0009, Privacy, Terms, paywall copy and the Play Data safety form together. If the app goes online for licensing, the "100% offline / no servers" wording in the app and on the marketing site must change. | M |

### MEDIUM

| ID | Area | What is wrong | Evidence | How to verify | Suggested fix | Effort |
|---|---|---|---|---|---|---|
| M-01 | Product rule: no country / visa naming | User-visible: crop preset labelled **"Visa photo"** (33 × 48 mm); descriptions "passport and visa photo size", "2 × 2 inch passport and visa photo"; paywall benefit "exam, visa and job portals"; paywall fallback "these are the US prices as a guide"; brand name "LinkedIn" in a preset description. Not visible but worth cleaning: search keywords `aadhaar pan` and `visa`; internal ids `us-visa`, `schengen-visa`, `passportUs`, `visaChina`, `passportCanada`; README "US 2×2 in, China visa". | `packages/domain/lib/src/entities/crop_preset.dart:58, 66, 72, 108` · `f/paywall/copy.dart:68` · `f/paywall/paywall_screen.dart:212-216` · `f/tools/tools_screen.dart:55, 131, 179` · `f/tools/kits/kit_catalog.dart:18, 40` · `f/home/home_screen.dart:43, 55` · `README.md:20` | Tools → Crop a photo → preset list. | Rename to size terms ("33 × 48 mm photo"), reword descriptions, say "prices in US dollars". Keep kit ids (saved state depends on them) but rename the Dart constants. Add a test that scans user-visible catalog strings for a country/visa word list. | S |
| M-02 | Paywall · missing PRO badges | Only `ToolTile`s on Home and Tools show the "Pro" badge (`ProBadge` widget is never used). These gated entry points have no badge and several rely on the router backstop instead of `ensurePro`: Home hero "Scan a document"; Home kit tiles and "All kits"; folder "+" → Scan document; Notes "New note" FAB; QR "Create QR code"; document viewer tool chips and "Protect & share"; passport → "Crop a photo"; convert chips. The backstop works (redirect to paywall with `from`), but the user gets no warning before the tap. | `contracts/pro_gate.dart:136-181` (badge), `:184-239` (backstop) · `f/home/home_screen.dart:297-304, 363, 379-389` · `f/library/folders/add_menu.dart:63-67, 79` · `f/notes/notes_screen.dart:146-150` · `f/qr/scan_screen.dart:143-147` · `f/library/document_screen.dart:517-521` · `f/library/document_actions.dart:59` | Run with `--dart-define=IDSNAP_SIMULATE_ENTITLEMENT=expired` and walk those entry points. | Add `ProBadge(feature)` (or a lock glyph) to each; call `pushIfPro` at the tap so the paywall is a push with a result rather than a redirect. | S |
| M-03 | Paywall · policy edges (**in flux**) | (a) `ProFeature.batch` is in the policy but nothing uses it. (b) "My signature" is gated as a whole, so after the trial a user cannot see, export or delete signatures they already saved — the one place where existing user data sits behind Pro. (c) A scan draft that exists when the trial ends can be resumed and extended with new pages indefinitely (`/scan?source=resume` and `/scan/review` are free; the review screen's add-page actions are not gated). (d) Editing existing notes is free, creating is Pro — fine, but the split is not stated in the UI. | `contracts/entitlements.dart:32, 67` · `contracts/pro_gate.dart:186-198, 215-216` · `f/scan/screens/review_screen.dart:57-58` (add page, no gate) · `f/notes/notes_screen.dart:54` | Simulate `expired` and open Tools → My signature. | Remove `batch` or use it; let the signature list/export stay free and gate "create"; gate add-page in review when not entitled. | S |
| M-04 | Error handling | (a) About two dozen places produce `FailureCode.unknown` with no specific message, so the user sees "Unexpected error — Please try again. If it keeps happening, copy the error details and send them to support" — and the app contains no support address anywhere. (b) Share / Save-to-device map every exception to `notFound` ("File not found — it may have been moved or deleted"). (c) Export maps every error to "Not enough storage". (d) See B-01/H-08 for swallowed async errors. | `packages/core/lib/src/failure.dart:150-155` · list: `packages/engines/imaging/lib/src/imaging_engine.dart:138`, `signature/signature_processor.dart:45,75`, `engines/ocr/…/mlkit_text_recognizer.dart:146,217`, `engines/scanner/…/platform_media_picker.dart:39,73,96`, `engines/security/…/local_auth_app_lock.dart:189,198,235,247`, `engines/vision/…/mlkit_face_locator.dart:67`, `f/authenticator/account_screen.dart:26`, `authenticator_screen.dart:216`, `widgets.dart:135`, `f/notes/notes_screen.dart:193`, `note_editor_screen.dart:48`, `f/tools/signature/my_signature_screen.dart:105`, `signature_library.dart:74`, `sign_pdf_screen.dart:347` · `f/library/document_actions.dart:47-50, 81-84` · `packages/data/lib/src/zip_library_archiver.dart:141` | Force a failure in each (e.g. revoke gallery permission mid-pick). | Give each site a message that says what was (not) changed and what to do; put the support address in About and in the "copy details" sheet. | M |
| M-05 | About / claims | (a) Version is the constructor default `'1.0.0'`; the route never passes a value, so it will be wrong after the first bump. (b) "…the essential tools are free" — scanning, OCR, PDF/image tools, kits, signatures are Pro after the trial. (c) "Documentation" tile has no `onTap` and points to an "official guide" that is not linked. (d) "secure hardware-backed storage" is true on most phones, not guaranteed on all. | `f/settings/about_screen.dart:6, 43-46, 56-62` · `f/settings/routes.dart:27-30` · `f/settings/privacy_screen.dart:24` | Open Settings → About. | Read the version from `package_info_plus`; reword the free claim to match `alwaysFreeLine`; remove or wire the tile; say "the phone's secure storage (Keystore/Keychain)". | S |
| M-06 | Kits / passport · session-only state | Custom kit limits live in a `Notifier` and reset on restart (the code says so: "Gap: kept in memory for the session only"). A custom passport-photo size is also not remembered. Neither is in the export. | `f/tools/kits/kit_catalog.dart:121-137, 183-185` · `f/scan/passport_photo/passport_dialogs.dart:12-61` | Edit custom limits, restart, reopen Custom kit. | Persist in `AppSettings` (JSON store) and include in export. | S |
| M-07 | Kits · background hint inactive | `backgroundAnalyzerProvider` returns null unless "overridden by the app with the imaging engine's `backgroundUniformity`" — the app never does, so `backgroundHint: true` on the photo kits does nothing. | `f/tools/kits/kit_controller.dart:11-13, 30` · `app/lib/bootstrap.dart` (no override) · `f/tools/kits/kit_catalog.dart:34, 52` | Process a photo with a busy background in the Square photo kit: no hint. | Override in bootstrap, or delete the hook. | S |
| M-08 | Quality gates | (a) No test instantiates the real `buildOverrides()`; app tests assemble their own 15-entry fake list, which is how B-01/H-01/M-07 survived. (b) `dart analyze --fatal-infos .` failed mid-audit on `app/test/encrypted_vault_e2e_test.dart:66, 33`; clean on re-check at the end. (c) `dart format --set-exit-if-changed` fails on `packages/features/library/test/vault_test.dart`. Both would fail CI. | `app/test/app_integration_test.dart` (own overrides) · `app/lib/vault_startup.dart:19` (only caller of `buildOverrides`) | Run the two commands at the root. | Add a "composition root" test: collect every `Provider` in `contracts/providers.dart` whose default is `_missing`/null and assert the app's override list covers it (with fakes for platform channels). Fix the two files. | S |
| M-09 | Release pipeline | `release.yml` builds a universal APK + AAB with no `--dart-define`, no `--obfuscate --split-debug-info`, no `--split-per-abi`, names artifacts `docscan-<tag>`, and when signing secrets are missing publishes debug-signed files to a GitHub Release (suffix `-unsigned`, which they are not). No git remote is configured, so no workflow has ever run. Version is still `1.0.0+1`; Gradle `namespace` is `com.docscan.docscan_scanner` (harmless, but leftover). Local signing is set up correctly (`key.properties` present, git-ignored). | `.github/workflows/release.yml:13-14, 47-58` · `app/android/app/build.gradle.kts:11-16, 19, 65-69` · `app/pubspec.yaml:4` · `git remote -v` → empty | Read the workflow; `git remote -v`. | Fail the release job when signing secrets are absent; pass the licence key define; add obfuscation + upload symbols; rename artifacts; add a version-bump step. | S |
| M-10 | App size | See §5. Universal APK 151 MB (Sep 25 artifact; owner reports 163 MB now with the barcode model): three ABIs of uncompressed native code, including **51 MB of x86_64** that no phone needs. arm64 APK 58.5 MB; AAB 110 MB. | `build-artifacts/*.apk` (unzip listing) | `unzip -lv idsnap-release-v1.0.0.apk` | Ship the AAB to Play; for direct downloads use `--split-per-abi` and `--target-platform android-arm,android-arm64`; add `--obfuscate --split-debug-info`. | S |
| M-11 | Repo hygiene | No `LICENSE` file (README/CONTRIBUTING describe an open project). README is entirely "DocScan", has `OWNER/REPO` badge placeholders, "Screenshots: Coming soon", and lists country presets. `build-artifacts/` (≈360 MB of APK/AAB) is untracked and **not** in `.gitignore` — one `git add .` commits it. `.env` is not ignored. A stray deletion `packages/engines/reminders/3.1.0-dev.2` is pending. `docs/product/PRD.md` is the original DocScan scanner PRD (no vault, authenticator, notes, QR or Pro; it lists "subscriptions gating basic features" as the problem to solve), while code comments cite "PRD Module 2" / "PRD 3.3" that do not exist in it. `docs/manifest.json` title is "DocScan Docs". | `README.md:1-30` · `.gitignore` · `git status` · `docs/product/PRD.md:1, 30` · `docs/manifest.json:2` | `ls LICENSE`; `git status --short build-artifacts`. | Add a licence (or mark proprietary), rewrite README for IDSnap with screenshots, ignore `build-artifacts/` and `.env`, refresh or archive the PRD. | S–M |
| M-12 | Secrets and keys (no values printed) | Nothing secret is tracked by git (checked `git ls-files` for keystores, `key.properties`, `.env`, `.pem`, `.p12`, google-services). On disk, ignored: the upload keystore exists in three copies — `app/android/upload-keystore.jks`, `app/android/app/upload-keystore.jks`, `build-artifacts/upload-keystore.jks` — and `app/android/key.properties` holds its passwords in plain text. `build-artifacts/` is only protected by the `*.jks` pattern. A personal email address is hard-coded as a fallback in a workflow. | paths above · `.gitignore:19-21` · `.github/workflows/marketing-pages.yml:53` | `git check-ignore -v <path>` | Keep one keystore copy outside the repo plus an offline backup (losing it blocks updates unless Play App Signing is enrolled); remove the email fallback. | S |
| M-13 | iOS configuration | `UIFileSharingEnabled = true` exposes the app's Documents folder in the Files app; the vault lives at `Documents/docscan/` (encrypted files + `library.sqlite`), so users can see a folder called "docscan" and delete or move vault files. `ITSAppUsesNonExemptEncryption = false` while the app ships its own AES (SQLCipher, AES-GCM, AES-256 PDF/ZIP) — review the export-compliance answer. | `app/ios/Runner/Info.plist:13-18` · `packages/data/lib/docscan_data.dart:78-79` | Files app → On My iPhone → IDSnap. | Move the vault to Application Support or turn file sharing off; get the encryption declaration right before TestFlight. | S |
| M-14 | Notes · PIN recovery (**in flux**) | A folder PIN has "Forgot PIN?" (reset with the device lock). A note PIN has no such path; a forgotten note PIN leaves the note unreadable in the app, while "Export all data" writes locked notes out in plain JSON after only the device prompt. | `f/library/folders/folder_lock.dart:191-197, 240` vs `f/notes/note_lock.dart` (no reset) · `packages/data/lib/src/zip_library_archiver.dart:22-26, 106-115` | Lock a note with a PIN and try to recover it. | Mirror the folder reset flow; mention in the export dialog that locked notes are included. | S |
| M-15 | Accessibility coverage | Good: every `IconButton` in the features has a tooltip; headers and live regions are used; Home/Tools grids scale with text size. Gaps: text-scale tests exist for only three places (design system, Home, ID card); none for Tools, tool screens, Authenticator, Paywall, Notes, QR, Library; no `meetsGuideline` tap-target/contrast tests. Fixed-height rows that may clip at 200 %: document viewer tool strip (`height: 64`), save-screen folder `DropdownButton` in a `ListTile.trailing`. | `packages/features/*/test` (grep `textScale`) · `f/library/document_screen.dart:506` · `f/scan/screens/save_screen.dart:221-251` | Set font size to largest and walk the tabs with TalkBack. | Add a shared "renders at 2.0× without overflow" test per top-level screen and `androidTapTargetGuideline` checks. | M |
| M-16 | Marketing site vs app | `apps/marketing-web` says users can export "encrypted backups" (the export is explicitly unencrypted), uses "military-grade", and the pages checked do not mention the trial or Pro pricing. | `apps/marketing-web/src/pages/index.astro:24, 318` · `f/settings/data_screen.dart:45-49` | Read the FAQ block. | Align the copy with the app and with H-09's outcome before the store listing links to it. | S |
| M-17 | Memory on large files | Upload reads each file fully into memory "to validate" with a 200 MB cap; Save to device reads the whole document; the PDF viewer and tools decrypt whole files to temp (fine) but thumbnails/`fileBytesProvider` load full images. On 3–4 GB phones a 150 MB PDF upload is at risk. | `f/library/folders/add_menu.dart:33-34, 423-428` · `f/library/document_actions.dart:65-72` · `f/tools/common/providers.dart:17` | Upload a 180 MB PDF on a low-RAM device. | Validate by sniffing the header and stream-encrypt; lower the cap or make it RAM-aware; path-based save. | M |
| M-18 | R8 / ProGuard | Rules cover ML Kit text + face and PDFium. Nothing for `flutter_local_notifications` (needs Gson keep rules as soon as H-01 is wired) and nothing explicit for the bundled barcode model (relies on the AAR's consumer rules). The existing rules were added after a release-only OCR crash, so each ML feature needs a release-build check. | `app/android/app/proguard-rules.pro:1-27` | Release build on a device: OCR, QR scan, passport face guide, document scanner, a purchase, a reminder. | Add the plugin rules; keep a release smoke checklist (§8). | S |
| M-19 | Searchable PDF scope | "Make text searchable" and the OCR tool's "Save as searchable PDF" use a Latin-only text layer, although Devanagari OCR is bundled. The UI says "Latin script only", so it is honest, but users who scan Hindi documents get no searchable layer. | `f/scan/save_controller.dart:69-71` · `f/scan/screens/save_screen.dart:214-217` · `f/settings/settings_screen.dart:92-98` · `f/tools/screens/ocr_screen.dart:96-99` | Scan a Hindi page with searchable on; search the PDF. | Embed a Devanagari-capable font for the invisible layer, or hide the toggle when the OCR language is not Latin. | M |

### LOW

| ID | Area | What is wrong | Evidence | Suggested fix | Effort |
|---|---|---|---|---|---|
| L-01 | Wording | The vault is "ID Vault" in navigation but "library" in tools: "From library", "Choose from library", "Save all to library", "Saving to your library…". | `f/tools/common/input_picker.dart:193, 606` · `f/tools/kits/kit_screen.dart:40, 94-95` | Use one term. | S |
| L-02 | Dead parameters / discoverability | `Routes.scan(slot:)` and `Routes.idCard(slot:)` are never called with a slot; `/scan` ignores `slot`. ID card is reachable only from the Home quick action (not in the Tools catalog, not in the folder "+" menu). Sign PDF has no shortcut from the document viewer. | `contracts/routes.dart:25-35` · `f/scan/routes.dart:25-33` · `f/tools/tools_screen.dart:48-205` · `f/library/document_screen.dart:486-498` | Remove the params; add ID card to Tools; add "Sign" chip for PDFs. | S |
| L-03 | Leftover "DocScan" identifiers | Not user-visible on Android: class `DocScanApp`, vault dir `docscan`, channel `docscan/secure_window`, Gradle namespace, package names. Visible on iOS via M-13. Release artifacts are named `docscan-*`. | `app/lib/app.dart:13` · `packages/data/lib/docscan_data.dart:79, 83` · `packages/engines/security/lib/src/secure_window.dart:25` | Leave the vault dir (renaming needs a migration); fix the rest opportunistically. | S |
| L-04 | Tool picker vs locked folders | "From library" never lists documents in a locked folder, even one unlocked this session (`hiddenContentIds(const {})`). The only way to run a tool on such a file is the viewer's chips. Intentional for privacy, but not explained in the empty state. | `packages/data/lib/src/drift_document_repository.dart:55-60` · `f/tools/common/input_picker.dart:588, 648-655` | Pass the session's unlocked ids, or add a hint line. | S |
| L-05 | OCR language list | Settings offers Chinese/Japanese/Korean, which are not bundled; choosing one shows "Not available on this device". | `f/settings/settings_screen.dart:107-115` · `app/lib/bootstrap.dart:48-54` | Hide unbundled scripts. | S |
| L-06 | Save-screen folder list | Flat list of folder names (nested folders with the same name are indistinguishable); a locked folder can be chosen without unlocking (write-only, acceptable). | `f/scan/screens/save_screen.dart:231-250` | Show the path or reuse `pickFolder`. | S |
| L-07 | Unused Android declarations | Until H-01 is wired, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED` and two receivers are declared for nothing (shows in the Play permissions list). | `AndroidManifest.xml:13-15, 61-74` | Tie to the H-01 decision. | S |
| L-08 | Slow test | `packages/engines/imaging` takes ~3 min (`detect_quality_test.dart` decodes 4000×3000 JPEGs in pure Dart); everything else is ≤ 1 min per package. No flaky test was seen in one full pass. | §6 | Tag as `slow` and run on CI only. | S |
| L-09 | Stale artifacts | `build-artifacts/` dates from Sep 25 and predates the QR/authenticator/billing work (no barcode library inside). Do not ship or measure from these. | `build-artifacts/` listing | Rebuild after the blockers. | — |
| L-11 | Encryption · library picker thumbnail | In "From library", a document with no stored thumbnail falls back to `InputThumb(inputFromDocument(...))`, which passes the **encrypted** vault path to `pdfThumbProvider`; PDFium opens ciphertext, fails, and a generic PDF icon is shown. Cosmetic (images go through `FileStore.read` and decrypt). This is the only reader found that still receives a ciphertext path. | `f/tools/common/input_picker.dart:57-63, 480-485` · `f/tools/common/providers.dart:38-45` | Fall back to a format icon, or render via `decryptToTemp`. | S |
| L-10 | This document | `docs/audit/launch-audit.md` is not listed in `docs/manifest.json`, so the docs app will not show it (the sync script tolerates unlisted pages). | `tool/sync_docs.dart:35-47` | Add a manifest entry if wanted. | S |

---

## 3. Route and feature inventory

Every route pattern in `contracts/routes.dart` and `app/lib/router.dart` has a UI entry point; none is dead. "Gate" = how Pro is enforced
(`ensurePro` at the tap, or only the router backstop in `app/lib/app.dart:51-56`).

| Route | Screen | Entry point(s) | Wiring | Gate | Tests |
|---|---|---|---|---|---|
| `/` | Home | tab | ok | — | `home_screen_test`, `home_gating_test` |
| `/authenticator`, `/add`, `/scan`, `/account/:id` | Authenticator | tab, Home card, add sheet | repo, codec, `MobileQrScanner`, secure flag wired | free | 3 feature tests + engine + data |
| `/files`, `/files/doc/:id`, `/files/folder/:id` | ID Vault, viewer, folder | tab, recents, browser, result sheets | repo/files/folder PIN store (default = real) | free | `library_test`, `vault_test`, data `folders_test` |
| `/tools` | Tools | tab | ok | — | `tools_gating_test`, `screens_test` |
| `/tools/<14 tool ids>` | PDF/image/OCR/sign/protect tools | Tools tiles, Home quick tools, viewer chips | all ports wired (stamper/protector/zip derive from `PdfEngine`) | `ensurePro` from Tools/Home; backstop from viewer chips | `screens_test`, `ocr_screen_test`, `protect_file_test`, `sign_pdf_test`, `signature_test`, `job_test`, `target_size_test`, `page_range_test` |
| `/tools/remove-pdf-password` | Remove password | Tools tile | ok | free (by design) | `protect_file_test` |
| `/tools/kits`, `/tools/kits/:id` | Kits hub, kit | Tools tile, Home kits | pipeline ok; background analyzer **not wired** (M-07); saves to root (H-03) | `pushIfPro` | `kits_test` |
| `/tools/convert`, `/convert/:specId` | Convert | Tools tile + chips, viewer chip | ok | `ensurePro` / backstop | `screens_test`, engine tests |
| `/tools/qr`, `/qr/generate`, `/qr/history` | QR tool | Tools tile, app-bar icons | `MobileCodeScanner`, encrypted history wired | scan/history free; generate backstop only (M-02) | `qr_flow_test`, `history_encryption_test` |
| `/scan`, `/scan/review`, `/scan/crop/:id`, `/scan/save` | Scan flow | Home hero, Home "Import photos", Tools, folder "+", resume banner | ok, folder supported | `pushIfPro` (Home/Tools); backstop (folder "+") | 5 feature tests |
| `/scan/id-card` | ID card | Home quick action only | **`SheetPdfBuilder` not wired (B-01)**; no folder (H-03) | `ensurePro` | 3 feature tests (with fakes) |
| `/scan/passport-photo` | Passport photo camera | Home, Tools | `CameraFaceSession` default is the real camera; `FaceLocator` wired; **print sheet broken (B-01)** | `ensurePro` | 2 feature tests (with fakes) |
| `/settings`, `/privacy`, `/about`, `/security`, `/data` | Settings | Home gear | app lock, archiver wired; **reminders not wired (H-01)** | free | `settings_test`, `security_test`, `subscription_entry_test` |
| `/notes`, `/notes/:id` | Secure notes | Home card, vault banner | repo wired (**in flux**) | create = `ensurePro`; read/edit free | `notes_test` |
| `/paywall`, `/subscription`, `/subscription/terms` | Pro | gates, Settings, trial banner | billing wired (**in flux**) | — | `paywall_test`, `billing_wiring_test`, engine tests |

Providers with a throwing / null / fake default and their status in the app:

| Provider | Default | Overridden in bootstrap? |
|---|---|---|
| `sheetPdfBuilderProvider` | throws | **No — B-01** |
| `reminderSchedulerProvider` | throws | **No — H-01** |
| `backgroundAnalyzerProvider` | null | **No — M-07** |
| `folderRepositoryProvider`, `pdfStamperProvider`, `pdfProtectorProvider`, `protectedZipWriterProvider`, `plainFileAccessProvider` | derive from wired ports | n/a (derive correctly: Drift repo / `PdfEngineImpl` / `LocalFileStore`) |
| `folderPinStoreProvider`, `notePinStoreProvider`, `folder/notesSecureSetterProvider`, `liveFaceCameraProvider`, `signatureLibraryProvider`, clipboard providers | real implementation | n/a |
| `qrScannerProvider`, `codeScannerProvider`, `qrHistoryStoreProvider`, `secureFlagSetterProvider`, `fileCipherProvider`, `ocrImagePreparerProvider`, `entitlementServiceProvider` | unavailable / memory / no-op / null / unlock-all | Yes |
| all other `_missing` ports (22) | throws | Yes |

Stubs search (`TODO`, `FIXME`, `Gap:`, `UnimplementedError`, "coming soon", "not implemented",
placeholder) over every `lib/`: one hit in product code — `kit_catalog.dart:123` (M-06) — plus the
`_missing` helper. No hard-coded sample data, no disabled buttons without a reason, and debug-only
paths (entitlement simulation) are compiled out behind `kReleaseMode`.

---

## 4a. Encryption at rest and secure notes: what is actually wired

The encryption + secure-notes agent stopped partway. This section checks its work in the code as it
stands (tests: data 61, security 52, notes 8, home 19, app 49, all passing).

| # | Question | Verdict | Evidence |
|---|---|---|---|
| 1 | Is the vault file cipher used by the app's file store, for new **and** existing files? | **Yes.** `buildOverrides` passes `VaultSecurity(keys: SecureStorageVaultKeyStore, crypto: AesGcmVaultCrypto)`. `openDataLayer` calls `openVault` and builds `LocalFileStore(cipher: vault.cipher)`. New files: `commit` encrypts and then shreds the temp; `writeThumbnail` and `importOriginal` encrypt. Existing plaintext files in `documents/`, `originals/`, `thumbs/` and `signatures/` are converted by `VaultFileMigrator.run` at every start (idempotent and resumable), behind a progress screen. Reads detect the header, so a half-migrated vault still opens. | `app/lib/bootstrap.dart:37-43` · `packages/data/lib/docscan_data.dart:104-125` · `packages/data/lib/src/local_file_store.dart:47-52, 68-91, 119-163` · `packages/data/lib/src/vault/file_migration.dart:90` · `app/lib/vault_startup.dart:15-38` |
| 2 | Does bootstrap use SQLCipher for the real DB, including the plaintext → encrypted migration? | **Yes.** `EncryptedDatabase.migrate(dbFile, key)` does a crash-safe swap in an isolate and shreds the plaintext. `EncryptedDatabase.open` follows. The root `pubspec.yaml` sets `hooks.user_defines.sqlite3.source: sqlcipher`, so package:sqlite3 bundles SQLCipher. If SQLCipher is missing, `open` throws `StateError`, which today ends on a blank screen (H-08). Confirm on a release build on a device (§8). | `packages/data/lib/docscan_data.dart:119-122` · `packages/data/lib/src/vault/encrypted_database.dart:44, 59-134` · `pubspec.yaml` (`hooks:`) |
| 3 | Does every reader of document bytes get plaintext? | **Yes, with one cosmetic exception.** Viewer images and all thumbnails use `vaultImageBytesProvider` → `FileStore.read`. The PDF viewer uses `decryptToTemp` and releases the copy on dispose. Text preview uses `readText`, which decrypts. Share uses `exportCopy`: it decrypts to `share/`, and the copy is shredded after 2 min. Save to device, the result-sheet save and Export all use `FileStore.read`. Every tool takes library input through `openDocumentInput` → `decryptToTemp`; this includes Protect file, Remove password, OCR, Sign PDF, Convert and kits. The `?doc=` preselect uses the same path. Scan and ID-card originals go through `files.read` (`previewCache`, `cropSource`, `SaveScanAsPdf`). The OCR preparer and the conversion engine read through `FileStore.read`. ML Kit and PDFium only receive temp plaintext paths. **Exception:** in the library picker, a PDF with no stored thumbnail is rendered from ciphertext, so an icon shows (L-11). | `contracts/providers.dart:178-191` · `f/library/document_screen.dart:268-399` · `f/library/document_actions.dart:20-72` · `f/tools/common/input_picker.dart:69-96` · `f/scan/preview_cache.dart:28, 52` · `packages/domain/lib/src/usecases/save_scan_as_pdf.dart:58, 89` · `packages/engines/ocr/lib/src/imaging_ocr_preparer.dart:34, 64` · `packages/engines/conversion/lib/src/conversion_engine.dart:134-499` |
| 4 | Are notes reachable, gated only on "new note", and included in export/import? | **Yes.** Schema v5 creates `notes` inside SQLCipher. Notes are reachable from the Home "Secure notes" card and the ID Vault banner (`/notes`, `/notes/:id`). Only `createNote` calls `ensurePro(ProFeature.secureNotes)`; reading, editing and locking are free (`readSecureNotes` is free in the policy). Export writes `secure-notes.json` as plain JSON inside the unencrypted ZIP, which the dialog discloses. Import restores the notes; PIN-locked notes come back locked to the device lock. Gaps: no PIN reset for notes (M-14); no PRO badge on the "New note" button (M-02). | `packages/data/lib/src/database.dart:93, 126, 166` · `f/home/home_screen.dart:400-408` · `f/library/vault.dart:88` · `f/notes/notes_screen.dart:54, 146-150` · `contracts/entitlements.dart:15, 48` · `packages/data/lib/src/zip_library_archiver.dart:22-26, 106-115, 265-315` |
| 5 | Do any in-app texts claim "encrypted" when it isn't true end to end? | **Mostly accurate, with three caveats.** (a) Plaintext source images stay in the app cache after a scan or import (H-07). That goes against the spirit of "your vault files … are encrypted". (b) Privacy says the key is in "hardware-backed storage", which is not guaranteed on every phone (M-05). (c) The marketing site says "encrypted backups", but the export is unencrypted (M-16). These texts are accurate: the export dialog says NOT encrypted; Privacy says shared copies are unencrypted; the folder and note lock copy calls the lock an access gate, not extra encryption; Protect file's AES-256 claims match `engines/pdf/protect`. Drafts and settings JSON are plaintext but hold only paths and preferences, never content. | `f/settings/privacy_screen.dart:21-33` · `f/settings/data_screen.dart:13-18, 41-50` · `f/library/folders/folder_lock.dart:14-16` · `f/notes/note_lock.dart:12` · `packages/data/lib/src/json_stores.dart:15-70` |
| 6 | Are QR history and the signature store encrypted? | **Yes.** QR history: bootstrap passes `JsonFileQrHistoryStore(cipher: data.fileCipher)`, and legacy plaintext is re-saved encrypted on first load. Signatures: `FileSignatureLibrary(cipher: fileCipherProvider)`, and bootstrap overrides `fileCipherProvider` with the vault cipher. Existing signature files are covered by the migrator because `signatures/` is a vault directory. Neither store is in the export (H-04). | `app/lib/bootstrap.dart:83-92` · `f/qr/history.dart:137-175` · `f/tools/signature/signature_providers.dart:16-21` · `f/tools/signature/signature_library.dart:28-41` · `packages/data/lib/src/local_file_store.dart:47-52` |

**Ranking of the encryption and notes gaps:** no BLOCKER. HIGH: H-07 (plaintext source copies left
in the cache), H-08 (a SQLCipher or startup failure shows a blank screen) and H-04 (signatures and
authenticator are missing from the only migration path). MEDIUM: M-05, M-14, M-16. LOW: L-11.

## 4. Verified working (wired end to end, with passing tests)

Verified by reading the entry point → provider → implementation chain and by the package tests
passing in this run. "Wired" means the real implementation is in `buildOverrides`; none of these was
exercised on a physical device (see §8).

- **Scan → review → crop → save, including save-to-folder.** `Routes.scan(folderId:)` →
  `scanTargetFolderProvider` → `SaveRequest.folderId` → `SaveScanAsPdf` → `CommitOutput(folderId)`.
  Tests: `save_screen_test`, `scan_session_controller_test`, `review_screen_test`.
- **Nested folders and folder locks.** Global lists (Home recents, tool pickers, search) exclude
  locked content in the repository itself (`drift_document_repository.dart:55-60, 209-216, 471`);
  the viewer re-checks the lock for direct links (`document_screen.dart:59-88`); PIN throttling and
  "Forgot PIN" exist. Tests: library `vault_test`, data `folders_test`, security
  `folder_pin_store_test`.
- **App Lock.** Cold-start gate, re-lock timing with excused external launches, no-screen-lock
  escape hatch, FLAG_SECURE / iOS snapshot cover, shared with authenticator and folder/notes secure
  scopes through one baseline. Tests: `lock_gate_test`, `app_lock_test`, `secure_window_test`.
- **Authenticator.** TOTP/HOTP, QR and manual add, reveal gate, keystore secrets with orphan purge.
  Tests: engine (69), data `authenticator_test`, 3 feature tests.
- **QR tool → Authenticator hand-off.** `result_screen.dart:135-166` parses with the wired
  `OtpCodec`, adds through the wired repository and switches tab. Test: `qr_flow_test` ("otpauth
  hands off to the Authenticator"). History is encrypted with the vault cipher.
- **OCR tool and searchable PDF (Latin).** Recognizer + imaging preparer wired; tests:
  `ocr_screen_test`, domain `recognize_text_test`, `imaging_ocr_preparer_test`.
- **PDF tools, image tools, conversions.** Tests: tools `screens_test`, engine pdf (56),
  conversion (48), imaging (34), `phase1_verification_test`, `pipeline_e2e_test`.
- **Protect file / Remove PDF password, with vault documents as input** (`?doc=` preselect decrypts a
  temp copy and prompts for an existing password). Tests: `protect_file_test`, engine `protect_test`,
  `protected_zip_large_test`, domain `commit_protected_test`. (Viewing the result in the vault: H-02.)
- **Signature library and Sign PDF.** Processor wired, stamper derived from the PDF engine, library
  encrypted with the vault cipher. Tests: `signature_test`, `sign_pdf_test`, `stamp_test`.
- **Kits pipeline** (photo/signature/document to size, all-or-nothing save with rollback). Test:
  `kits_test`. Caveats: H-03, M-06, M-07.
- **Export/import of documents, folders, notes and expiry dates** for small vaults, including
  re-encryption on import and de-duplication. Tests: data `vault_test`, `encryption_test`. Caveats:
  H-04, H-05.
- **Paywall policy.** One policy map, a completeness test, router backstop, free "own data" paths
  (view, share, save to device, export, remove password, authenticator, notes read/edit). Tests:
  `entitlements_test`, `tools_gating_test`, `home_gating_test`, billing engine (42). **In flux.**
- **Encryption at rest** for vault files, thumbnails, signatures, QR history and the database, with
  a migration screen and a recovery screen for a missing key. Tests: data `encryption_test`,
  `vault_test`, security `vault_crypto_test`, app `vault_startup_test`. **In flux**; caveat H-07.
- **Android release basics.** `allowBackup=false` + data-extraction rules exclude everything; only
  the launcher activity is exported; no `INTERNET` in release; camera without microphone; real
  launcher icons incl. adaptive; R8 + resource shrinking on; upload-key signing configured locally.

---

## 5. App size

From `build-artifacts/idsnap-release-v1.0.0.apk` (151 MB, Sep 25 — predates the bundled barcode
model, which explains the owner's 163 MB figure). Native libraries are stored uncompressed, so
on-disk size ≈ download size for them.

| Part | Size |
|---|---|
| `lib/x86_64` (emulators/Chromebooks only) | 51.1 MB |
| `lib/arm64-v8a` | 47.8 MB |
| `lib/armeabi-v7a` | 36.9 MB |
| ML Kit model assets (face, OCR incl. Devanagari) | 5.5 MB |
| Dex, resources, Flutter assets (NotoSans 0.3 MB) | ~2.5 MB |

Inside arm64: Flutter engine 11.2 MB · ML Kit OCR pipeline 10.6 MB · Dart AOT (`libapp.so`) 10.0 MB ·
ML Kit face detector 8.1 MB · PDFium 6.1 MB · SQLCipher 1.7 MB.

What dominates is **shipping three ABIs in one file**, not any single feature. Recommendations, in
order of payoff:

1. Publish the **AAB** on Play: each phone downloads one ABI (≈ 55–62 MB for arm64 today).
2. For direct downloads: `flutter build apk --release --split-per-abi
   --target-platform android-arm,android-arm64` (drops x86_64 entirely; arm64 APK ≈ 58–62 MB,
   v7a ≈ 47–50 MB).
3. Add `--obfuscate --split-debug-info=build/symbols` (smaller `libapp.so`, and needed to read
   stack traces from the field).
4. Only if size still matters: the bundled face detector (8 MB) serves passport photo + kits; the
   alternative is the Play-services model, which downloads on first use and conflicts with the
   offline promise — keep bundled unless that promise changes. CJK OCR is already left out.

ML Kit bundling is consistent with the offline claim: Latin + Devanagari text, face detection and
(per `app/android/gradle.properties:9`) the barcode model are bundled. The one runtime download is the ML Kit
**document scanner** module from Google Play services, which the Privacy screen and the scan launch
screen both disclose.

---

## 6. Quality signals from this run

`dart analyze --fatal-infos .` (5 m 50 s, three analyzers were running concurrently): **exit 3**,
2 issues, both in `apps/scanner/test/encrypted_vault_e2e_test.dart` (`undefined_identifier
DocumentFormat` at :66; `async_return_with_no_await` at :33) — in flux at the time. **Re-checked at the end of the audit: `dart analyze --fatal-infos apps/scanner` → No issues found**, and that test now passes.

`dart format --set-exit-if-changed`: 1 of 404 files would change
(`packages/features/library/test/vault_test.dart`).

`flutter test`, sequential, one pass:

| Package | Result | Tests | Wall time |
|---|---|---|---|
| core | pass | 6 | 20 s |
| domain | pass | 60 | 16 s |
| contracts | pass | 16 | 21 s |
| design_system | pass | 24 | 16 s |
| data | pass | 61 | 31 s |
| engines/authenticator | pass | 69 | 14 s |
| engines/billing | pass | 42 | 14 s |
| engines/codes | pass | 87 | 17 s |
| engines/conversion | pass | 48 | 16 s |
| engines/imaging | pass | 34 | **197 s** |
| engines/ocr | pass | 18 | 27 s |
| engines/pdf | pass | 56 | 61 s |
| engines/reminders | pass | 6 | 16 s |
| engines/scanner | pass | 6 | 24 s |
| engines/security | pass | 52 | 25 s |
| engines/vision | pass | 15 | 15 s |
| features/authenticator | pass | 30 | 53 s |
| features/home | pass | 19 | 37 s |
| features/library | pass | 29 | 79 s |
| features/notes | pass | 8 | 38 s |
| features/paywall | pass | 16 | 56 s |
| features/qr | pass | 28 | 54 s |
| features/scan | pass | 82 | 36 s |
| features/settings | pass | 13 | 22 s |
| features/tools | pass | 85 | 26 s |
| apps/docs | pass | 7 | 12 s |
| apps/lab | pass | 2 | ~15 s |
| apps/scanner | pass | 49 | 106 s |

**Total: 968 tests, 0 failures, no flaky test seen in one pass.**

`packages/engines/license` and `apps/license_server` appeared during the run (billing agent) and
were not part of this pass. A release build was **not** run: the tree was changing under two other
agents and the existing artifacts were enough for the size analysis; rebuild after the blockers.

---

## 7. Performance and robustness risks seen in code

| Risk | Where | Note |
|---|---|---|
| Whole vault in memory, UI isolate | `zip_library_archiver.dart:53-141, 167-174` | H-05 |
| 200 MB upload read into memory | `add_menu.dart:33-34` | M-17 |
| Swallowed async errors (`unawaited` on controller saves) | `id_card_screen.dart:199`, pattern repeated for tool jobs | B-01, H-08; add a global handler |
| Plaintext temp copies outliving their use | picker/scanner caches | H-07. The vault's own temp copies are handled well: shredded on release, after 30 min, and at launch (`local_file_store.dart:181-265`) |
| "Clear temporary files" can run during a tool job | `settings_screen.dart:427-437` | Low: would delete inputs of a job in another tab; disable while a job is running |
| Blank first frames | `vault_startup.dart:66`, `billing.dart:31` | up to 5 s wait on secure storage before the app appears |
| Heavy work off the UI isolate | `engines/pdf/isolate_jobs.dart`, `vault_cipher.dart`, `folder_pin_store.dart`, `run_heavy_io.dart` | Good. Pure-Dart JPEG decode of a 12 MP photo takes ~2.2 s on a desktop (`detect_quality_test` output); the app uses the native decoder path — confirm on a low-end phone |
| Cancellation | `RecognizeDocument` supports it; `ToolScaffold` jobs expose progress | Not audited screen by screen |

---

## 8. Needs a real device

Run on a release build (R8 on), ideally one Android 16 phone, one low-RAM Android 8–10 phone and,
if iOS ships, one iPhone.

- [ ] B-01 fixed: ID card front/back → Save → opens in vault; Passport photo → Print sheet.
- [ ] Android 16 with `targetSdk 36`: edge-to-edge insets on every tab, predictive back on ID card,
      kit, save and lock screens.
- [ ] Document scanner first run with no network (Play services module missing) → message and
      "Import photos" fallback; then with network.
- [ ] Release-only ML checks: OCR Latin + Devanagari, QR scan (bundled barcode model), passport face
      guide + auto-capture, kit face framing.
- [ ] `aapt dump permissions` on the release APK: no `INTERNET`, no `RECORD_AUDIO`; decide on the
      notification permissions (H-01).
- [ ] Purchase, restore, pending purchase, refund and the "manage subscription" link with a licence
      tester account; trial expiry; clock set back; airplane-mode cold start. (**In flux.**)
- [ ] App Lock: cold start, background 0/1/5 min, camera/picker/share round trips, biometric
      lockout, removing the screen lock, FLAG_SECURE in recents, split screen.
- [ ] Folder lock + App Lock + authenticator reveal back to back: no double prompts, no prompt loop.
- [ ] Encryption migration from a pre-encryption install with ~500 files; kill the app mid-way;
      reinstall/restore-from-backup → recovery screen.
- [ ] Export with a 300–500 MB vault (H-05), import on a second phone, check folders, notes, expiry
      dates, thumbnails; confirm what is missing (H-04).
- [ ] Protected PDF from Protect file opens in Adobe/Drive/Files; AES ZIP opens in 7-Zip and a phone
      file manager; open the same PDF from the vault (H-02).
- [ ] Share and Save to device for PDF, JPEG, DOCX; check the 2-minute shred of share copies does not
      break slow receivers (email attach, cloud upload).
- [ ] App cache contents after scan/import/upload (H-07).
- [ ] 200 % font size and TalkBack pass over the four tabs, paywall, a tool, the viewer.
- [ ] Large inputs: 100-page PDF merge/compress/OCR, 50 MP photo, 180 MB upload.
- [ ] Cold-start time and first-frame blank duration on the low-end phone.
- [ ] Expiry reminder actually fires after reboot (once H-01 is wired).
- [ ] iOS (if in scope): icon, Face ID prompt, camera, Files app visibility of the vault, StoreKit.
