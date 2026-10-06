import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:docscan_domain/docscan_domain.dart';

/// The `IDSV` v1 vault file format (ADR-0010).
///
/// ```text
/// 0   8  magic 89 49 44 53 56 4C 54 1A ("\x89IDSVLT\x1A")
/// 8   1  version = 1
/// 9   1  algorithm = 1 (AES-256-GCM, 96-bit nonce, 128-bit tag)
/// 10  1  log2(chunk size), 12..24 (default 18 = 256 KiB)
/// 11  1  reserved = 0
/// 12  4  master key id (u32 BE)
/// 16  12 wrap nonce
/// 28  48 file key wrapped with the master key (AES-256-GCM, AAD = bytes 0..15)
/// 76  8  chunk nonce prefix
/// 84  …  chunks: ciphertext ‖ 16-byte tag
/// ```
///
/// Chunk `i`: nonce = prefix ‖ u32(i), AAD = header(0..83) ‖ u32(i) ‖ u8(final).
/// Every chunk except the last holds a full chunk of plaintext; the last one
/// (0..chunk size bytes) is sealed with final = 1.
abstract final class VaultFormat {
  static const magic = <int>[0x89, 0x49, 0x44, 0x53, 0x56, 0x4C, 0x54, 0x1A];
  static const version = 1;
  static const algorithmAesGcm = 1;
  static const headerLength = 84;
  static const tagLength = 16;
  static const nonceLength = 12;
  static const keyLength = 32;
  static const defaultChunkLog2 = 18;
  static const minChunkLog2 = 12;
  static const maxChunkLog2 = 24;

  /// Bytes 0..15 are authenticated by the key wrap.
  static const wrapAadLength = 16;

  static bool isEncrypted(List<int> head) {
    if (head.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (head[i] != magic[i]) return false;
    }
    return true;
  }

  /// Plaintext size for a well-formed file of [fileLength] bytes (the
  /// default chunk size is assumed; exact for every file we write).
  static int plaintextLength(
    int fileLength, {
    int chunkLog2 = defaultChunkLog2,
  }) {
    final body = fileLength - headerLength;
    if (body < tagLength) return 0;
    final per = (1 << chunkLog2) + tagLength;
    final chunks = (body + per - 1) ~/ per;
    return body - chunks * tagLength;
  }

  static Uint8List chunkNonce(List<int> prefix, int index) {
    final n = Uint8List(nonceLength)..setRange(0, 8, prefix);
    ByteData.sublistView(n).setUint32(8, index);
    return n;
  }

  static Uint8List chunkAad(Uint8List header, int index, {required bool last}) {
    final aad = Uint8List(headerLength + 5)..setRange(0, headerLength, header);
    ByteData.sublistView(aad)
      ..setUint32(headerLength, index)
      ..setUint8(headerLength + 4, last ? 1 : 0);
    return aad;
  }
}

/// Where ciphertext/plaintext comes from.
abstract interface class ByteSource {
  int get length;

  /// Exactly [count] bytes (throws when the source is shorter).
  Future<Uint8List> read(int count);
}

class MemorySource implements ByteSource {
  MemorySource(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  @override
  int get length => _bytes.length;

  @override
  Future<Uint8List> read(int count) async {
    if (_offset + count > _bytes.length) {
      throw const VaultIntegrityException('unexpected end of data');
    }
    final out = Uint8List.sublistView(_bytes, _offset, _offset + count);
    _offset += count;
    return out;
  }
}

class FileSource implements ByteSource {
  FileSource._(this._file, this.length);

  static Future<FileSource> open(String path) async {
    final f = await File(path).open();
    return FileSource._(f, await f.length());
  }

  final RandomAccessFile _file;

  @override
  final int length;

  @override
  Future<Uint8List> read(int count) async {
    final out = await _file.read(count);
    if (out.length != count) {
      throw const VaultIntegrityException('unexpected end of file');
    }
    return out;
  }

  Future<void> close() => _file.close();
}

typedef ByteSink = Future<void> Function(List<int> bytes);

/// Streaming encryption / decryption of the vault format with [aes].
class VaultStreamCipher {
  VaultStreamCipher(this.aes, {Random? random, this.chunkLog2 = 18})
    : _random = random ?? Random.secure();

  final AesGcm aes;
  final int chunkLog2;
  final Random _random;

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));

  Future<void> encrypt(VaultKey key, ByteSource input, ByteSink output) async {
    final chunk = 1 << chunkLog2;
    final fileKey = _randomBytes(VaultFormat.keyLength);
    final header = Uint8List(VaultFormat.headerLength)
      ..setRange(0, 8, VaultFormat.magic);
    ByteData.sublistView(header)
      ..setUint8(8, VaultFormat.version)
      ..setUint8(9, VaultFormat.algorithmAesGcm)
      ..setUint8(10, chunkLog2)
      ..setUint8(11, 0)
      ..setUint32(12, key.id);
    final wrapNonce = _randomBytes(VaultFormat.nonceLength);
    header.setRange(16, 28, wrapNonce);
    final wrapped = await aes.encrypt(
      fileKey,
      secretKey: SecretKeyData(key.bytes),
      nonce: wrapNonce,
      aad: Uint8List.sublistView(header, 0, VaultFormat.wrapAadLength),
    );
    header
      ..setRange(28, 60, wrapped.cipherText)
      ..setRange(60, 76, wrapped.mac.bytes)
      ..setRange(76, 84, _randomBytes(8));
    await output(header);

    final prefix = Uint8List.sublistView(header, 76, 84);
    final secret = SecretKeyData(fileKey);
    final total = input.length;
    final chunks = total == 0 ? 1 : (total + chunk - 1) ~/ chunk;
    for (var i = 0; i < chunks; i++) {
      final size = i < chunks - 1 ? chunk : total - i * chunk;
      final plain = await input.read(size);
      final box = await aes.encrypt(
        plain,
        secretKey: secret,
        nonce: VaultFormat.chunkNonce(prefix, i),
        aad: VaultFormat.chunkAad(header, i, last: i == chunks - 1),
      );
      await output(box.cipherText);
      await output(box.mac.bytes);
    }
  }

  Future<void> decrypt(VaultKey key, ByteSource input, ByteSink output) async {
    final total = input.length;
    if (total < VaultFormat.headerLength + VaultFormat.tagLength) {
      throw const VaultIntegrityException('too short');
    }
    final header = Uint8List.fromList(
      await input.read(VaultFormat.headerLength),
    );
    if (!VaultFormat.isEncrypted(header)) {
      throw const VaultIntegrityException('not a vault file');
    }
    final view = ByteData.sublistView(header);
    final log2 = view.getUint8(10);
    if (view.getUint8(8) != VaultFormat.version ||
        view.getUint8(9) != VaultFormat.algorithmAesGcm ||
        view.getUint8(11) != 0 ||
        log2 < VaultFormat.minChunkLog2 ||
        log2 > VaultFormat.maxChunkLog2) {
      throw const VaultIntegrityException('unsupported header');
    }
    if (view.getUint32(12) != key.id) {
      throw const VaultIntegrityException('encrypted with another key');
    }
    final List<int> fileKey;
    try {
      fileKey = await aes.decrypt(
        SecretBox(
          Uint8List.sublistView(header, 28, 60),
          nonce: Uint8List.sublistView(header, 16, 28),
          mac: Mac(Uint8List.sublistView(header, 60, 76)),
        ),
        secretKey: SecretKeyData(key.bytes),
        aad: Uint8List.sublistView(header, 0, VaultFormat.wrapAadLength),
      );
    } on SecretBoxAuthenticationError {
      throw const VaultIntegrityException('wrong key or damaged header');
    }
    final secret = SecretKeyData(fileKey);
    final prefix = Uint8List.sublistView(header, 76, 84);
    final per = (1 << log2) + VaultFormat.tagLength;
    final body = total - VaultFormat.headerLength;
    final chunks = (body + per - 1) ~/ per;
    final lastSize = body - (chunks - 1) * per;
    if (lastSize < VaultFormat.tagLength) {
      throw const VaultIntegrityException('truncated');
    }
    for (var i = 0; i < chunks; i++) {
      final last = i == chunks - 1;
      final sealed = await input.read(last ? lastSize : per);
      final cut = sealed.length - VaultFormat.tagLength;
      try {
        final plain = await aes.decrypt(
          SecretBox(
            Uint8List.sublistView(sealed, 0, cut),
            nonce: VaultFormat.chunkNonce(prefix, i),
            mac: Mac(Uint8List.sublistView(sealed, cut)),
          ),
          secretKey: secret,
          aad: VaultFormat.chunkAad(header, i, last: last),
        );
        await output(plain);
      } on SecretBoxAuthenticationError {
        throw VaultIntegrityException('chunk $i failed authentication');
      }
    }
  }
}
