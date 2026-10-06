import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_data/docscan_data.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:docscan_scanner/app_info.dart';
import 'package:docscan_scanner/bootstrap.dart';
import 'package:drift/native.dart';
import 'package:engine_authenticator/engine_authenticator.dart';
import 'package:engine_security/engine_security.dart';
import 'package:feature_authenticator/feature_authenticator.dart';
import 'package:feature_qr/feature_qr.dart';
import 'package:feature_tools/feature_tools.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:flutter_test/flutter_test.dart';

/// Every provider in docscan_contracts whose default throws "not wired"
/// (`_missing(...)`). Keyed by its Dart name; the test below parses the
/// contracts sources and fails when a new one is missing from this map, so a
/// new port can't ship without an override (audit B-01, H-01, M-08).
final _ports = <String, ProviderBase<Object?>>{
  'documentRepositoryProvider': documentRepositoryProvider,
  'draftStoreProvider': draftStoreProvider,
  'settingsStoreProvider': settingsStoreProvider,
  'fileStoreProvider': fileStoreProvider,
  'imageProcessorProvider': imageProcessorProvider,
  'pdfEngineProvider': pdfEngineProvider,
  'textRecognizerProvider': textRecognizerProvider,
  'documentScannerProvider': documentScannerProvider,
  'mediaPickerProvider': mediaPickerProvider,
  'shareServiceProvider': shareServiceProvider,
  'conversionEngineProvider': conversionEngineProvider,
  'folderRepositoryProvider': folderRepositoryProvider,
  'faceLocatorProvider': faceLocatorProvider,
  'sheetPdfBuilderProvider': sheetPdfBuilderProvider,
  'appLockProvider': appLockProvider,
  'libraryArchiverProvider': libraryArchiverProvider,
  'reminderSchedulerProvider': reminderSchedulerProvider,
  'signatureProcessorProvider': signatureProcessorProvider,
  'pdfStamperProvider': pdfStamperProvider,
  'pdfProtectorProvider': pdfProtectorProvider,
  'protectedZipWriterProvider': protectedZipWriterProvider,
  'authenticatorRepositoryProvider': authenticatorRepositoryProvider,
  'otpCodecProvider': otpCodecProvider,
  'notesRepositoryProvider': notesRepositoryProvider,
  'vaultEraserProvider': vaultEraserProvider,
};

/// Providers whose default is a harmless stand-in (null, in-memory,
/// "unavailable") that the app must replace with the real thing.
final _stubDefaults = <String, ProviderBase<Object?>>{
  // entitlementServiceProvider is wired from startBilling() (needs secure
  // storage and the store plugin); this test passes a stand-in for it, so
  // its wiring is covered by test/billing_wiring_test.dart and
  // test/licence_e2e_test.dart instead.
  'ocrImagePreparerProvider': ocrImagePreparerProvider,
  'fileCipherProvider': fileCipherProvider,
  'qrScannerProvider': qrScannerProvider,
  'codeScannerProvider': codeScannerProvider,
  'qrHistoryStoreProvider': qrHistoryStoreProvider,
  'backgroundAnalyzerProvider': backgroundAnalyzerProvider,
};

/// Names of `final xProvider = …` declarations whose body calls `_missing(`
/// or throws `UnimplementedError`, across docscan_contracts' sources.
Set<String> _unwiredByDefault() {
  final dir = Directory('../../packages/contracts/lib/src');
  final names = <String>{};
  final decl = RegExp(r'^final (\w+Provider)\b', multiLine: true);
  for (final f in dir.listSync().whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final src = f.readAsStringSync();
    final matches = decl.allMatches(src).toList();
    for (var i = 0; i < matches.length; i++) {
      final end = i + 1 < matches.length ? matches[i + 1].start : src.length;
      final body = src.substring(matches[i].start, end);
      if (body.contains('_missing(') || body.contains('UnimplementedError')) {
        names.add(matches[i].group(1)!);
      }
    }
  }
  return names;
}

class _Keys implements VaultKeyStore {
  VaultKey? key;

  @override
  Future<VaultKey> create() async => key = VaultKey(
    id: 1,
    bytes: Uint8List.fromList(List.generate(32, (i) => i)),
  );

  @override
  Future<void> delete() async => key = null;

  @override
  Future<VaultKey?> read() async => key;
}

class _Secrets implements SecretStore {
  final _map = <String, String>{};

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async => _map[key] = value;

  @override
  Future<void> delete(String key) async => _map.remove(key);

  @override
  Future<Set<String>> keys() async => _map.keys.toSet();
}

void main() {
  late Directory tmp;
  late DataLayer data;
  late ProviderContainer container;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('idsnap_overrides');
    data = await openDataLayer(
      rootOverride: '${tmp.path}/vault',
      cacheOverride: '${tmp.path}/cache',
      executor: NativeDatabase.memory(),
      security: VaultSecurity(
        keys: _Keys(),
        crypto: const AesGcmVaultCrypto(pureDart: true, runInIsolate: false),
      ),
    );
    final font = File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync();
    final secrets = _Secrets();
    container = ProviderContainer(
      // The REAL production list: the same function buildOverrides returns,
      // fed with test-built services instead of platform-initialised ones.
      overrides: productionOverrides(
        data: data,
        unicodeFont: font,
        supportDirectory: tmp.path,
        entitlements: const StaticEntitlementService(),
        ads: const NoopAdsService(),
        authenticator: DriftAuthenticatorRepository(
          data.database,
          secrets: secrets,
          codec: const OtpCodecImpl(),
        ),
        secrets: secrets,
      ),
    );
  });

  tearDownAll(() async {
    container.dispose();
    await data.close();
    await tmp.delete(recursive: true);
  });

  test('the port list matches the "not wired" providers in contracts', () {
    final parsed = _unwiredByDefault();
    expect(parsed, isNotEmpty);
    expect(
      parsed.difference(_ports.keys.toSet()),
      isEmpty,
      reason:
          'A new port in docscan_contracts defaults to _missing(). Override '
          'it in productionOverrides (apps/scanner/lib/bootstrap.dart) and '
          'add it to _ports here.',
    );
  });

  test('every port is wired in the production override list', () {
    for (final MapEntry(:key, :value) in _ports.entries) {
      expect(
        () => container.read(value),
        returnsNormally,
        reason: '$key is not overridden in productionOverrides',
      );
    }
  });

  test('stand-in defaults are replaced in production', () {
    final defaults = ProviderContainer();
    addTearDown(defaults.dispose);
    for (final MapEntry(:key, :value) in _stubDefaults.entries) {
      final real = container.read(value);
      expect(real, isNotNull, reason: '$key is null in production');
      final stub = defaults.read(value);
      expect(
        real.runtimeType,
        isNot(stub.runtimeType),
        reason: '$key still uses its default ($stub) in production',
      );
    }
  });

  test('appVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(appVersion, version);
  });
}
