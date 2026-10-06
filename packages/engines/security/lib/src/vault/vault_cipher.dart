import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_security/src/vault/vault_format.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// AES-256-GCM with the platform implementation when the
/// `cryptography_flutter` plugin is registered in this isolate (javax.crypto
/// on Android, CryptoKit on iOS), pure Dart otherwise (tests, desktop).
AesGcm platformAesGcm() {
  if (FlutterCryptography.isPluginPresent) {
    final native = FlutterAesGcm(
      secretKeyLength: 32,
      fallback: DartAesGcm.with256bits(),
      // Chunks are 256 KiB; the plugin's Android queue allows 20 MB.
      channelPolicy: const CryptographyChannelPolicy(
        minLength: 2048,
        maxLength: 8 * 1024 * 1024,
      ),
    );
    if (native.isSupportedPlatform) return native;
  }
  return DartAesGcm.with256bits();
}

/// Plain data for a background job. Only primitives and typed data cross
/// the isolate boundary.
typedef _Job = ({
  int op,
  int keyId,
  Uint8List key,
  String source,
  String target,
  RootIsolateToken? token,
});

const _opEncrypt = 0;
const _opDecrypt = 1;
const _opDecryptToBytes = 2;

/// Entry point of the worker isolate.
Future<Uint8List?> _runJob(_Job job) async {
  final token = job.token;
  if (token != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    FlutterCryptography.registerWith();
  }
  return await _execute(VaultStreamCipher(platformAesGcm()), job);
}

Future<Uint8List?> _execute(VaultStreamCipher cipher, _Job job) async {
  final key = VaultKey(id: job.keyId, bytes: job.key);
  switch (job.op) {
    case _opEncrypt:
      await _streamToFile(
        job.source,
        job.target,
        (source, sink) => cipher.encrypt(key, source, sink),
      );
      return null;
    case _opDecrypt:
      await _streamToFile(
        job.source,
        job.target,
        (source, sink) => cipher.decrypt(key, source, sink),
      );
      return null;
    default:
      final source = await FileSource.open(job.source);
      final out = BytesBuilder(copy: false);
      try {
        await cipher.decrypt(key, source, (b) async => out.add(b));
      } finally {
        await source.close();
      }
      return out.takeBytes();
  }
}

/// Streams [source] through [transform] into `target.part`, fsyncs, then
/// renames over [target]. On any failure the partial file is deleted.
Future<void> _streamToFile(
  String source,
  String target,
  Future<void> Function(ByteSource, ByteSink) transform,
) async {
  final part = File('$target.part');
  final input = await FileSource.open(source);
  final output = await part.open(mode: FileMode.write);
  try {
    await transform(input, output.writeFrom);
    await output.flush();
  } on Object {
    await output.close();
    await input.close();
    if (part.existsSync()) await part.delete();
    rethrow;
  }
  await output.close();
  await input.close();
  await part.rename(target);
}

/// [FileCipher] for the `IDSV` format bound to one [VaultKey].
///
/// File jobs run in a background isolate that attaches to the platform
/// channels (so the native AES-GCM is used there too); memory stays at a
/// few 256 KiB chunks whatever the file size. Byte jobs under
/// [inlineLimit] run on the calling isolate.
class VaultFileCipher implements FileCipher {
  VaultFileCipher(
    this.key, {
    @visibleForTesting AesGcm? aes,
    @visibleForTesting this.runInIsolate = true,
    this.inlineLimit = 1024 * 1024,
  }) : _aes = aes;

  final VaultKey key;
  final bool runInIsolate;
  final int inlineLimit;
  final AesGcm? _aes;

  VaultStreamCipher get _inline => VaultStreamCipher(_aes ?? platformAesGcm());

  @override
  int get headerLength => VaultFormat.headerLength;

  @override
  bool isEncrypted(List<int> head) => VaultFormat.isEncrypted(head);

  @override
  int plaintextLength(int encryptedLength) =>
      VaultFormat.plaintextLength(encryptedLength);

  Future<Uint8List?> _job(int op, String source, String target) {
    final job = (
      op: op,
      keyId: key.id,
      key: key.bytes,
      source: source,
      target: target,
      // Only phones have the native AES-GCM plugin; elsewhere (tests,
      // desktop) the worker uses pure Dart and needs no platform channel.
      token: (Platform.isAndroid || Platform.isIOS)
          ? RootIsolateToken.instance
          : null,
    );
    if (!runInIsolate || _aes != null) return _runInline(job);
    return Isolate.run(() => _runJob(job));
  }

  /// Same work on this isolate with the configured [AesGcm].
  Future<Uint8List?> _runInline(_Job job) => _execute(_inline, job);

  @override
  Future<void> encryptFile(String source, String target) =>
      _job(_opEncrypt, source, target);

  @override
  Future<void> decryptFile(String source, String target) =>
      _job(_opDecrypt, source, target);

  @override
  Future<Uint8List> decryptFileToBytes(String source) async =>
      (await _job(_opDecryptToBytes, source, ''))!;

  @override
  Future<Uint8List> encryptBytes(List<int> plaintext) async {
    final out = BytesBuilder(copy: false);
    await _inline.encrypt(
      key,
      MemorySource(
        plaintext is Uint8List ? plaintext : Uint8List.fromList(plaintext),
      ),
      (b) async => out.add(b is Uint8List ? Uint8List.fromList(b) : b),
    );
    return out.takeBytes();
  }

  @override
  Future<Uint8List> decryptBytes(Uint8List encrypted) async {
    final out = BytesBuilder(copy: false);
    await _inline.decrypt(
      key,
      MemorySource(encrypted),
      (b) async => out.add(b is Uint8List ? Uint8List.fromList(b) : b),
    );
    return out.takeBytes();
  }
}

/// [VaultCrypto] on AES-256-GCM (files) and HKDF/HMAC-SHA256 (subkeys).
class AesGcmVaultCrypto implements VaultCrypto {
  const AesGcmVaultCrypto({
    @visibleForTesting this.runInIsolate = true,
    @visibleForTesting this.pureDart = false,
  });

  final bool runInIsolate;

  /// Forces the pure-Dart AES (tests).
  final bool pureDart;

  static const _salt = 'idsnap.vault';
  static const _kcvLabel = 'idsnap/kcv/v1';

  @override
  FileCipher fileCipher(VaultKey key) => VaultFileCipher(
    key,
    aes: pureDart ? DartAesGcm.with256bits() : null,
    runInIsolate: runInIsolate,
  );

  @override
  Future<Uint8List> deriveKey(VaultKey key, String purpose) async {
    final hkdf = DartHkdf(hmac: DartHmac.sha256(), outputLength: 32);
    final out = await hkdf.deriveKey(
      secretKey: SecretKeyData(key.bytes),
      nonce: utf8.encode(_salt),
      info: utf8.encode(purpose),
    );
    return Uint8List.fromList(await out.extractBytes());
  }

  @override
  Future<String> keyCheck(VaultKey key) async {
    final mac = await DartHmac.sha256().calculateMac(
      utf8.encode(_kcvLabel),
      secretKey: SecretKeyData(key.bytes),
    );
    return mac.bytes
        .take(8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
