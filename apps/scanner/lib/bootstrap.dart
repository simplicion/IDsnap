import 'dart:async';
import 'dart:io';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:docscan_scanner/ads.dart';
import 'package:docscan_scanner/billing.dart';
import 'package:docscan_scanner/code_scanner.dart';
import 'package:docscan_scanner/native_decoder.dart';
import 'package:docscan_scanner/qr_scanner.dart';
import 'package:docscan_scanner/startup_failure.dart';
import 'package:engine_authenticator/engine_authenticator.dart';
import 'package:engine_conversion/engine_conversion.dart';
import 'package:engine_imaging/engine_imaging.dart';
import 'package:engine_ocr/engine_ocr.dart';
import 'package:engine_pdf/engine_pdf.dart';
import 'package:engine_reminders/engine_reminders.dart';
import 'package:engine_scanner/engine_scanner.dart';
import 'package:engine_security/engine_security.dart';
import 'package:engine_vision/engine_vision.dart';
import 'package:feature_authenticator/feature_authenticator.dart';
import 'package:feature_qr/feature_qr.dart';
import 'package:feature_tools/feature_tools.dart'
    show
        SignatureBackupSection,
        backgroundAnalyzerProvider,
        signatureLibraryProvider;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:path_provider/path_provider.dart';

/// Composition root: the only place that knows concrete implementations.
/// Everything else depends on domain ports through docscan_contracts.
///
/// Throws [VaultUnavailableException] when the encrypted vault can't be
/// unlocked on this phone; [onVaultMigration] reports the one-time
/// encryption of an existing vault (ADR-0010). Any other failure is thrown
/// as a [StartupFailure] naming the step, for the recovery screen (H-08).
Future<List<Override>> buildOverrides({
  VaultMigrationProgress? onVaultMigration,
}) async {
  // Monetization (ADR-0013): free with ads by default. Fails fast, before
  // the vault is touched, on an unknown IDSNAP_MONETIZATION or, in a
  // release build that shows ads, on missing or Google-sample AdMob IDs.
  final setup = await runStartupStep(
    StartupStep.billing,
    checkMonetizationConfig,
  );

  // Entitlements. Free with ads: everything unlocked, returns at once, no
  // licence client and no network. Paid modes: trial + cached entitlement
  // from secure storage (up to 5 s when the keystore is slow), started
  // first so it runs in parallel with the vault instead of after it; still
  // awaited before the app is built so the entitlement is right on the
  // first frame (ADR-0009). The startup screen is visible meanwhile.
  // `ignore()` only stops an early error from being reported as unhandled;
  // the await below still receives it.
  final billingStart = startBilling(mode: setup.mode)..ignore();

  await runStartupStep(StartupStep.pdfEngine, initPdfEngine);
  // Files and the database are encrypted at rest: AES-256-GCM per file,
  // SQLCipher for the database, master key in the platform keystore.
  final data = await runStartupStep(
    StartupStep.vault,
    () => openDataLayer(
      security: VaultSecurity(
        keys: vaultKeyStore(),
        crypto: const AesGcmVaultCrypto(),
      ),
      onMigration: onVaultMigration,
      // Streaming backup ZIPs, plain or AES-256 (audit H-04/H-05).
      archiveCodec: const ZipArchiveCodec(),
    ),
  );
  try {
    final font = await runStartupStep(
      StartupStep.assets,
      () => rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final supportDir = await runStartupStep(
      StartupStep.storage,
      getApplicationSupportDirectory,
    );

    // Authenticator: metadata in SQLite, secrets in the platform keystore.
    final secrets = SecureStorageSecretStore();
    final authenticator = DriftAuthenticatorRepository(
      data.database,
      secrets: secrets,
      codec: const OtpCodecImpl(),
    );
    // Clean up keystore entries left by an interrupted add/remove.
    unawaited(authenticator.purgeOrphanSecrets());

    final billing = await runStartupStep(
      StartupStep.billing,
      () => billingStart,
    );
    return productionOverrides(
      data: data,
      unicodeFont: font.buffer.asUint8List(),
      supportDirectory: supportDir.path,
      entitlements: billing,
      // Built here, started later: no ad code runs until the vault is open
      // and an ad slot is on screen (consent comes first, ADR-0013).
      ads: createAdsService(setup: setup, supportDirectory: supportDir.path),
      authenticator: authenticator,
      secrets: secrets,
    );
  } on Object {
    // Release the database so "Try again" can open it cleanly.
    unawaited(data.close().catchError((Object _) {}));
    rethrow;
  }
}

/// The production override list from already-initialised services. Pure:
/// no platform channels, so apps/scanner/test/overrides_coverage_test.dart
/// builds exactly this list and checks every port is wired (audit B-01,
/// M-08). Add new ports HERE.
List<Override> productionOverrides({
  required DataLayer data,
  required Uint8List unicodeFont,
  required String supportDirectory,
  required EntitlementService entitlements,
  required AdsService ads,
  required DriftAuthenticatorRepository authenticator,
  required SecretStore secrets,
}) {
  const images = ImagingEngine(decoder: nativeDecode);
  final pdf = PdfEngineImpl(unicodeFont: unicodeFont);
  // Both models are bundled (see android/app/build.gradle.kts and
  // ios/Podfile), so OCR never downloads anything at runtime. Keep this set
  // equal to the linked models: Chinese/Japanese/Korean would each add
  // roughly 12 MB per device and are not linked.
  final ocr = MlKitTextRecognizer(
    bundledScripts: const {OcrScript.latin, OcrScript.devanagari},
  );
  final conversion = ConversionEngineImpl(
    files: data.files,
    pdf: pdf,
    images: images,
    ocr: ocr,
  );
  const otp = OtpCodecImpl();

  return [
    entitlementServiceProvider.overrideWithValue(entitlements),
    adsServiceProvider.overrideWithValue(ads),
    authenticatorRepositoryProvider.overrideWithValue(authenticator),
    otpCodecProvider.overrideWithValue(otp),
    qrScannerProvider.overrideWithValue(const MobileQrScanner()),
    // QR & barcode tool: same bundled model; history is a local JSON file.
    codeScannerProvider.overrideWithValue(const MobileCodeScanner()),
    qrHistoryStoreProvider.overrideWithValue(
      JsonFileQrHistoryStore(
        File('$supportDirectory/qr/history.json'),
        // Encrypted with the vault cipher, like saved signatures.
        cipher: data.fileCipher,
      ),
    ),
    fileCipherProvider.overrideWithValue(data.fileCipher),
    notesRepositoryProvider.overrideWithValue(data.notes),
    libraryArchiverProvider.overrideWithValue(data.archiver),
    // Everything else the full backup carries and "Erase everything"
    // removes (audit H-04, H-06). The feature stores are the same instances
    // the features use.
    backupSectionsProvider.overrideWith(
      (ref) => [
        AuthenticatorBackupSection(authenticator),
        SignatureBackupSection(ref.watch(signatureLibraryProvider)),
        QrHistoryBackupSection(ref.watch(qrHistoryStoreProvider)),
        SettingsBackupSection(data.settings),
      ],
    ),
    vaultEraserProvider.overrideWith(
      (ref) => DataVaultEraser(
        database: data.database,
        documents: data.documents,
        files: data.files,
        drafts: data.drafts,
        settings: data.settings,
        targets: [
          ...ref.watch(backupSectionsProvider),
          // Folder and note PIN hashes and their attempt counters. The
          // licence lives in its own storage and is never touched.
          SecretPrefixEraser(secrets, const [
            KeystoreFolderPinStore.keyPrefix,
            KeystoreFolderPinStore.attemptsPrefix,
          ], label: 'Folder and note PINs'),
        ],
      ),
    ),
    secureFlagSetterProvider.overrideWithValue(const SecureWindow().setSecure),
    documentRepositoryProvider.overrideWithValue(data.documents),
    draftStoreProvider.overrideWithValue(data.drafts),
    settingsStoreProvider.overrideWithValue(data.settings),
    fileStoreProvider.overrideWithValue(data.files),
    importedSourceDisposerProvider.overrideWithValue(
      data.files.discardImportedSource,
    ),
    imageProcessorProvider.overrideWithValue(images),
    pdfEngineProvider.overrideWithValue(pdf),
    sheetPdfBuilderProvider.overrideWithValue(const SheetPdfBuilderImpl()),
    textRecognizerProvider.overrideWithValue(ocr),
    // EXIF orientation, rotation/scale/contrast retries for OCR.
    ocrImagePreparerProvider.overrideWithValue(
      ImagingOcrPreparer(images: images, files: data.files),
    ),
    documentScannerProvider.overrideWithValue(PlatformDocumentScanner()),
    mediaPickerProvider.overrideWithValue(PlatformMediaPicker()),
    shareServiceProvider.overrideWithValue(PlatformShareService()),
    conversionEngineProvider.overrideWithValue(conversion),
    faceLocatorProvider.overrideWithValue(MlKitFaceLocator()),
    // Signature cleanup for kits and Sign PDF (pdfStamperProvider derives
    // from pdfEngineProvider, so it needs no line here).
    signatureProcessorProvider.overrideWithValue(
      const SignatureProcessorImpl(),
    ),
    // Photo kits' "busy background" hint (audit M-07).
    backgroundAnalyzerProvider.overrideWithValue(backgroundUniformity),
    appLockProvider.overrideWithValue(LocalAuthAppLock()),
    // Expiry reminders: local notifications only, inexact alarms, restored
    // after reboot by the plugin's boot receiver (audit H-01).
    reminderSchedulerProvider.overrideWithValue(LocalReminderScheduler()),
  ];
}

/// The vault master key: platform keystore (Android Keystore-backed secure
/// storage; iOS Keychain, this device only).
VaultKeyStore vaultKeyStore() =>
    SecureStorageVaultKeyStore(SecureStorageSecretStore());
