import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart'
    show ArchiveErrorKind, ArchiveException;
import 'package:engine_pdf/src/protect/crypto.dart';

// Synchronous, streaming ZIP core shared by the protected-ZIP tool
// (`writeAe2ZipSync`) and the full backup (`ZipArchiveCodec`). Plain entries
// are stored or deflated with a streaming CRC-32; with a password every file
// entry is WinZip AE-2 (AES-256-CTR + HMAC-SHA1, PBKDF2 x1000, CRC 0).
// Sizes and CRCs are patched into each local header after the data (no
// data descriptors). Classic ZIP only: under 4 GiB and 65,535 entries.
// Everything runs in fixed-size chunks so memory doesn't grow with the
// archive; call it from a background isolate.

/// Read/write chunk size.
const zipChunkSize = 1 << 20;

const _maxZip32 = 0xFFFFFFFF;
const _maxEntries = 0xFFFF;
const _aesExtraLength = 11;
const _methodStore = 0;
const _methodDeflate = 8;
const _methodAes = 99;
const _versionAes = 51;
const _versionPlain = 20;
const _flagEncrypted = 0x0001;
const _flagUtf8 = 0x0800;
const _sigLocal = 0x04034b50;
const _sigCentral = 0x02014b50;
const _sigEnd = 0x06054b50;

/// The archive would exceed the classic ZIP limits.
class ZipLimitException implements Exception {
  const ZipLimitException(this.message);
  final String message;

  @override
  String toString() => 'ZipLimitException($message)';
}

/// The password can't be used for a ZIP every unzip tool understands.
class ZipPasswordException implements Exception {
  const ZipPasswordException(this.message);
  final String message;

  @override
  String toString() => 'ZipPasswordException($message)';
}

/// Formats that are already compressed: stored, not deflated.
const storedZipExtensions = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'avif', //
  'mp4', 'mov', 'm4v', 'mkv', 'webm', 'mp3', 'm4a', 'aac', 'ogg', 'opus',
  'zip', '7z', 'rar', 'gz', 'bz2', 'xz', 'apk', 'jar',
  'docx', 'xlsx', 'pptx', 'odt', 'ods', 'odp', 'epub',
};

/// Whether an entry called [name] is worth deflating.
bool shouldDeflate(String name) {
  final slash = name.lastIndexOf('/');
  final base = slash < 0 ? name : name.substring(slash + 1);
  final dot = base.lastIndexOf('.');
  final ext = dot < 0 ? '' : base.substring(dot + 1).toLowerCase();
  return !storedZipExtensions.contains(ext);
}

/// The password bytes, or a [ZipPasswordException]. Only printable ASCII is
/// accepted: tools disagree on how non-ASCII ZIP passwords are encoded, so
/// such an archive might not open for the recipient.
Uint8List zipPasswordBytes(String password) {
  if (password.isEmpty) {
    throw const ZipPasswordException('The password is empty.');
  }
  for (final c in password.codeUnits) {
    if (c < 0x20 || c > 0x7E) {
      throw const ZipPasswordException(
        'Use only English letters, digits and standard symbols so every '
        'unzip app can open the file.',
      );
    }
  }
  return Uint8List.fromList(ascii.encode(password));
}

/// Derived WinZip AES keys for one entry (key length 16/24/32).
({Uint8List aesKey, Uint8List hmacKey, Uint8List verifier}) deriveAeKeys(
  List<int> password,
  List<int> salt,
  int keyLength,
) {
  final d = pbkdf2HmacSha1(password, salt, 1000, keyLength * 2 + 2);
  return (
    aesKey: Uint8List.sublistView(d, 0, keyLength),
    hmacKey: Uint8List.sublistView(d, keyLength, keyLength * 2),
    verifier: Uint8List.sublistView(d, keyLength * 2, keyLength * 2 + 2),
  );
}

/// Derived AE-256 keys for one entry: `(aesKey, hmacKey, verifier)`.
({Uint8List aesKey, Uint8List hmacKey, Uint8List verifier}) deriveAe256Keys(
  List<int> password,
  List<int> salt,
) => deriveAeKeys(password, salt, 32);

/// CRC-32 (IEEE 802.3), streaming.
class Crc32 {
  static final Uint32List _table = () {
    final t = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      t[n] = c;
    }
    return t;
  }();

  int _crc = 0xFFFFFFFF;

  void add(List<int> data) {
    var c = _crc;
    final t = _table;
    for (var i = 0; i < data.length; i++) {
      c = t[(c ^ data[i]) & 0xFF] ^ (c >> 8);
    }
    _crc = c;
  }

  int get value => _crc ^ 0xFFFFFFFF;
}

class _Entry {
  _Entry({
    required this.name,
    required this.offset,
    required this.method,
    required this.encrypted,
    required this.time,
    required this.date,
    this.directory = false,
  });

  final Uint8List name;
  final int offset;
  final int method;
  final bool encrypted;
  final int time;
  final int date;
  final bool directory;
  int crc = 0;
  int compressedSize = 0;
  int size = 0;
}

/// Sink that forwards (de)compressor output to a callback.
class _CallbackSink implements Sink<List<int>> {
  _CallbackSink(this.onData);
  final void Function(List<int> data) onData;

  @override
  void add(List<int> data) => onData(data);

  @override
  void close() {}
}

class _Open {
  _Open(this.entry, this.ctr, this.mac);
  final _Entry entry;
  final WinZipAesCtr? ctr;
  final HmacSha1Stream? mac;
  final crc = Crc32();
  ByteConversionSink? deflater;
  int read = 0;
  int written = 0;
}

/// Writes a ZIP entry by entry: [beginEntry], any number of [write]s,
/// [endEntry]; then [finish]. Synchronous.
class ZipStreamWriter {
  ZipStreamWriter._(this.path, this._out, this._password, this._now);

  /// A new archive at [path]. With a [password] every file entry is AE-2.
  factory ZipStreamWriter.create(
    String path, {
    String? password,
    DateTime? now,
  }) {
    final pw = password == null ? null : zipPasswordBytes(password);
    final file = File(path);
    file.parent.createSync(recursive: true);
    return ZipStreamWriter._(
      path,
      file.openSync(mode: FileMode.write),
      pw,
      now,
    );
  }

  final String path;
  final RandomAccessFile _out;
  final Uint8List? _password;
  final DateTime? _now;
  final _entries = <_Entry>[];
  final _names = <String>{};
  _Open? _open;
  bool _closed = false;

  bool get encrypts => _password != null;

  Uint8List _name(String name) {
    if (name.isEmpty || name.startsWith('/') || name.contains(r'\')) {
      throw ArgumentError('Bad entry name');
    }
    if (!_names.add(name)) throw ArgumentError('Duplicate entry name');
    if (_entries.length >= _maxEntries) {
      throw const ZipLimitException('Too many files for one ZIP (max 65,535).');
    }
    final bytes = Uint8List.fromList(utf8.encode(name));
    if (bytes.length > 0xFFFF) throw ArgumentError('Entry name too long');
    return bytes;
  }

  void _checkIdle() {
    if (_closed) throw StateError('Writer closed');
    if (_open != null) throw StateError('An entry is open');
  }

  /// An empty, unencrypted directory entry ([name] ends with `/`).
  void addDirectory(String name, {DateTime? modified}) {
    _checkIdle();
    final dir = name.endsWith('/') ? name : '$name/';
    final (time, date) = _dosDateTime(modified ?? _now ?? DateTime.now());
    final e = _Entry(
      name: _name(dir),
      offset: _out.positionSync(),
      method: _methodStore,
      encrypted: false,
      time: time,
      date: date,
      directory: true,
    );
    _writeLocalHeader(e);
    _entries.add(e);
  }

  /// Starts a file entry. [compress] defaults to [shouldDeflate].
  void beginEntry(String name, {bool? compress, DateTime? modified}) {
    _checkIdle();
    final (time, date) = _dosDateTime(modified ?? _now ?? DateTime.now());
    final deflate = compress ?? shouldDeflate(name);
    final e = _Entry(
      name: _name(name),
      offset: _out.positionSync(),
      method: deflate ? _methodDeflate : _methodStore,
      encrypted: _password != null,
      time: time,
      date: date,
    );
    _writeLocalHeader(e);
    WinZipAesCtr? ctr;
    HmacSha1Stream? mac;
    final pw = _password;
    if (pw != null) {
      final salt = secureRandomBytes(16);
      final keys = deriveAe256Keys(pw, salt);
      _out
        ..writeFromSync(salt)
        ..writeFromSync(keys.verifier);
      ctr = WinZipAesCtr(keys.aesKey);
      mac = HmacSha1Stream(keys.hmacKey);
    }
    final open = _Open(e, ctr, mac);
    if (deflate) {
      open.deflater = ZLibEncoder(
        raw: true,
      ).startChunkedConversion(_CallbackSink((d) => _emit(open, d)));
    }
    _open = open;
  }

  void _emit(_Open o, List<int> data) {
    if (data.isEmpty) return;
    final ctr = o.ctr;
    if (ctr != null) {
      final buf = Uint8List.fromList(data);
      ctr.process(buf);
      o.mac!.add(buf);
      _out.writeFromSync(buf);
    } else {
      _out.writeFromSync(data);
    }
    o.written += data.length;
    if (o.written >= _maxZip32) {
      throw const ZipLimitException('The ZIP would be larger than 4 GB.');
    }
  }

  /// Adds the next chunk of the open entry's content.
  void write(List<int> chunk) {
    final o = _open;
    if (o == null) throw StateError('No open entry');
    if (chunk.isEmpty) return;
    o.read += chunk.length;
    if (o.read >= _maxZip32) {
      throw const ZipLimitException('Files over 4 GB can’t go into a ZIP.');
    }
    if (o.ctr == null) o.crc.add(chunk);
    final d = o.deflater;
    if (d != null) {
      d.add(chunk);
    } else {
      _emit(o, chunk);
    }
  }

  /// Completes the open entry and patches its header.
  void endEntry() {
    final o = _open;
    if (o == null) throw StateError('No open entry');
    o.deflater?.close();
    final e = o.entry;
    if (o.mac != null) {
      _out.writeFromSync(o.mac!.close().sublist(0, 10));
      e
        ..compressedSize = 16 + 2 + o.written + 10
        ..crc = 0; // AE-2 stores no CRC.
    } else {
      e
        ..compressedSize = o.written
        ..crc = o.crc.value;
    }
    e.size = o.read;
    final end = _out.positionSync();
    if (e.compressedSize >= _maxZip32 || end >= _maxZip32) {
      throw const ZipLimitException('The ZIP would be larger than 4 GB.');
    }
    _out
      ..setPositionSync(e.offset + 14)
      ..writeFromSync(_u32(e.crc))
      ..writeFromSync(_u32(e.compressedSize))
      ..writeFromSync(_u32(e.size))
      ..setPositionSync(end);
    _entries.add(e);
    _open = null;
  }

  /// One whole in-memory entry.
  void addBytes(String name, List<int> bytes, {bool? compress}) {
    beginEntry(name, compress: bytes.isEmpty ? false : compress);
    for (var i = 0; i < bytes.length; i += zipChunkSize) {
      final end = i + zipChunkSize < bytes.length
          ? i + zipChunkSize
          : bytes.length;
      write(
        bytes is Uint8List
            ? Uint8List.sublistView(bytes, i, end)
            : bytes.sublist(i, end),
      );
    }
    endEntry();
  }

  /// Writes the central directory and closes the file; returns its size.
  int finish() {
    _checkIdle();
    final cdStart = _out.positionSync();
    _entries.forEach(_writeCentralHeader);
    final cdSize = _out.positionSync() - cdStart;
    if (cdStart + cdSize >= _maxZip32) {
      throw const ZipLimitException('The ZIP would be larger than 4 GB.');
    }
    final eocd = BytesBuilder()
      ..add(_u32(_sigEnd))
      ..add(_u16(0))
      ..add(_u16(0))
      ..add(_u16(_entries.length))
      ..add(_u16(_entries.length))
      ..add(_u32(cdSize))
      ..add(_u32(cdStart))
      ..add(_u16(0));
    _out
      ..writeFromSync(eocd.takeBytes())
      ..flushSync();
    final length = _out.positionSync();
    _out.closeSync();
    _closed = true;
    return length;
  }

  /// Closes and deletes the partial archive (cancel or failure).
  void discard() {
    if (!_closed) {
      _closed = true;
      try {
        _out.closeSync();
      } on Object {
        // Already closed.
      }
    }
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } on FileSystemException {
      // Best effort; the caller's cache sweep removes it later.
    }
  }

  void _writeLocalHeader(_Entry e) {
    final b = BytesBuilder()
      ..add(_u32(_sigLocal))
      ..add(_u16(e.encrypted ? _versionAes : _versionPlain))
      ..add(_u16(_flags(e)))
      ..add(_u16(e.encrypted ? _methodAes : e.method))
      ..add(_u16(e.time))
      ..add(_u16(e.date))
      ..add(_u32(0)) // CRC-32, patched later (0 for AE-2)
      ..add(_u32(0)) // compressed size, patched later
      ..add(_u32(0)) // uncompressed size, patched later
      ..add(_u16(e.name.length))
      ..add(_u16(e.encrypted ? _aesExtraLength : 0))
      ..add(e.name);
    if (e.encrypted) b.add(_aesExtra(e.method));
    _out.writeFromSync(b.takeBytes());
  }

  void _writeCentralHeader(_Entry e) {
    final b = BytesBuilder()
      ..add(_u32(_sigCentral))
      ..add(_u16(e.encrypted ? _versionAes : _versionPlain)) // made by: DOS
      ..add(_u16(e.encrypted ? _versionAes : _versionPlain))
      ..add(_u16(_flags(e)))
      ..add(_u16(e.encrypted ? _methodAes : e.method))
      ..add(_u16(e.time))
      ..add(_u16(e.date))
      ..add(_u32(e.crc))
      ..add(_u32(e.compressedSize))
      ..add(_u32(e.size))
      ..add(_u16(e.name.length))
      ..add(_u16(e.encrypted ? _aesExtraLength : 0))
      ..add(_u16(0)) // comment
      ..add(_u16(0)) // disk
      ..add(_u16(0)) // internal attributes
      ..add(_u32(e.directory ? 0x10 : 0x20)) // directory / archive
      ..add(_u32(e.offset))
      ..add(e.name);
    if (e.encrypted) b.add(_aesExtra(e.method));
    _out.writeFromSync(b.takeBytes());
  }

  static int _flags(_Entry e) => _flagUtf8 | (e.encrypted ? _flagEncrypted : 0);
}

Uint8List _aesExtra(int method) =>
    (BytesBuilder()
          ..add(_u16(0x9901))
          ..add(_u16(7))
          ..add(_u16(2)) // AE-2
          ..add(const [0x41, 0x45]) // "AE"
          ..addByte(3) // AES-256
          ..add(_u16(method)))
        .takeBytes();

(int, int) _dosDateTime(DateTime t) {
  final year = t.year.clamp(1980, 2107);
  final time = (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);
  final date = ((year - 1980) << 9) | (t.month << 5) | t.day;
  return (time, date);
}

Uint8List _u16(int v) => Uint8List(2)
  ..[0] = v & 0xFF
  ..[1] = (v >> 8) & 0xFF;

Uint8List _u32(int v) => Uint8List(4)
  ..[0] = v & 0xFF
  ..[1] = (v >> 8) & 0xFF
  ..[2] = (v >> 16) & 0xFF
  ..[3] = (v >> 24) & 0xFF;

// ── Reading ─────────────────────────────────────────────────────────────

/// One central-directory record.
class ZipRecord {
  ZipRecord({
    required this.name,
    required this.flags,
    required this.method,
    required this.crc,
    required this.compressedSize,
    required this.size,
    required this.localOffset,
    this.aesStrength,
    this.aesVersion,
  });

  final String name;
  final int flags;

  /// The compression method of the content (for AES: the inner method).
  final int method;
  final int crc;
  final int compressedSize;
  final int size;
  final int localOffset;

  /// 1/2/3 = AES-128/192/256 when WinZip AES encrypted.
  final int? aesStrength;
  final int? aesVersion;

  bool get encrypted => (flags & _flagEncrypted) != 0;
  bool get isDirectory => name.endsWith('/');
}

ArchiveException _corrupt([String? m]) =>
    ArchiveException(ArchiveErrorKind.corrupt, m);

int _r16(Uint8List b, int o) => b[o] | b[o + 1] << 8;
int _r32(Uint8List b, int o) => _r16(b, o) | _r16(b, o + 2) << 16;

/// Reads a classic ZIP from its central directory and streams entries out,
/// verifying CRC-32 (plain) or the AE HMAC (encrypted). Synchronous.
class ZipStreamReader {
  ZipStreamReader._(this._file, this.records);

  /// Opens [path]; throws [ArchiveException] when it isn't a readable ZIP.
  factory ZipStreamReader.open(String path) {
    final f = File(path).openSync();
    try {
      return ZipStreamReader._(f, _readDirectory(f));
    } on Object {
      f.closeSync();
      rethrow;
    }
  }

  final RandomAccessFile _file;
  final List<ZipRecord> records;

  static List<ZipRecord> _readDirectory(RandomAccessFile f) {
    final length = f.lengthSync();
    if (length < 22) throw _corrupt('Not a ZIP file');
    final tailLength = length < 65557 ? length : 65557;
    f.setPositionSync(length - tailLength);
    final tail = f.readSync(tailLength);
    var eocd = -1;
    for (var i = tail.length - 22; i >= 0; i--) {
      if (tail[i] == 0x50 &&
          tail[i + 1] == 0x4b &&
          tail[i + 2] == 0x05 &&
          tail[i + 3] == 0x06) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw _corrupt('Not a ZIP file');
    final count = _r16(tail, eocd + 10);
    final cdSize = _r32(tail, eocd + 12);
    final cdOffset = _r32(tail, eocd + 16);
    if (count == 0xFFFF || cdSize == _maxZip32 || cdOffset == _maxZip32) {
      throw const ArchiveException(
        ArchiveErrorKind.unsupported,
        'ZIP64 archives are not supported',
      );
    }
    if (cdOffset + cdSize > length || cdSize > 64 * 1024 * 1024) {
      throw _corrupt('Truncated ZIP');
    }
    f.setPositionSync(cdOffset);
    final cd = f.readSync(cdSize);
    if (cd.length != cdSize) throw _corrupt('Truncated ZIP');
    final out = <ZipRecord>[];
    var o = 0;
    for (var i = 0; i < count; i++) {
      if (o + 46 > cd.length || _r32(cd, o) != _sigCentral) {
        throw _corrupt('Bad central directory');
      }
      final flags = _r16(cd, o + 8);
      var method = _r16(cd, o + 10);
      final crc = _r32(cd, o + 16);
      final comp = _r32(cd, o + 20);
      final size = _r32(cd, o + 24);
      final nameLen = _r16(cd, o + 28);
      final extraLen = _r16(cd, o + 30);
      final commentLen = _r16(cd, o + 32);
      final local = _r32(cd, o + 42);
      final end = o + 46 + nameLen + extraLen + commentLen;
      if (end > cd.length) throw _corrupt('Bad central directory');
      if (comp == _maxZip32 || size == _maxZip32 || local == _maxZip32) {
        throw const ArchiveException(
          ArchiveErrorKind.unsupported,
          'ZIP64 archives are not supported',
        );
      }
      final nameBytes = Uint8List.sublistView(cd, o + 46, o + 46 + nameLen);
      final name = (flags & _flagUtf8) != 0
          ? utf8.decode(nameBytes, allowMalformed: true)
          : _decodeLegacyName(nameBytes);
      int? strength;
      int? aesVersion;
      var x = o + 46 + nameLen;
      final xEnd = x + extraLen;
      while (x + 4 <= xEnd) {
        final id = _r16(cd, x);
        final len = _r16(cd, x + 2);
        if (id == 0x9901 && len >= 7 && x + 4 + len <= xEnd) {
          aesVersion = _r16(cd, x + 4);
          strength = cd[x + 8];
          if (method == _methodAes) method = _r16(cd, x + 9);
        }
        x += 4 + len;
      }
      out.add(
        ZipRecord(
          name: name.replaceAll(r'\', '/'),
          flags: flags,
          method: method,
          crc: crc,
          compressedSize: comp,
          size: size,
          localOffset: local,
          aesStrength: strength,
          aesVersion: aesVersion,
        ),
      );
      o = end;
    }
    return out;
  }

  /// Names without the UTF-8 flag are CP437 in theory; ASCII in practice.
  static String _decodeLegacyName(Uint8List b) {
    try {
      return utf8.decode(b);
    } on FormatException {
      return latin1.decode(b);
    }
  }

  ZipRecord? record(String name) {
    for (final r in records) {
      if (r.name == name) return r;
    }
    return null;
  }

  /// Starts extracting [r] into [onData]; drive it with
  /// [ZipEntryExtraction.step] until it returns false, then
  /// [ZipEntryExtraction.finish].
  ZipEntryExtraction begin(
    ZipRecord r,
    void Function(List<int> data) onData, {
    String? password,
  }) => ZipEntryExtraction._(_file, r, onData, password);

  /// Extracts [r] to [target] (via `target.part`, renamed on success).
  /// [onBytes] gets output bytes so far; [shouldStop] is polled per chunk.
  void extractToFile(
    ZipRecord r,
    String target, {
    String? password,
    void Function(int bytes)? onBytes,
    bool Function()? shouldStop,
  }) {
    final part = File('$target.part');
    part.parent.createSync(recursive: true);
    final out = part.openSync(mode: FileMode.write);
    var written = 0;
    try {
      final job = begin(r, (d) {
        out.writeFromSync(d);
        written += d.length;
      }, password: password);
      while (job.step()) {
        if (shouldStop?.call() ?? false) {
          throw const ArchiveException(ArchiveErrorKind.cancelled);
        }
        onBytes?.call(written);
      }
      job.finish();
      out
        ..flushSync()
        ..closeSync();
      part.renameSync(target);
      onBytes?.call(written);
    } on Object {
      try {
        out.closeSync();
      } on Object {
        // Already closed.
      }
      if (part.existsSync()) part.deleteSync();
      rethrow;
    }
  }

  /// Reads a whole entry into memory (refused above [maxBytes]).
  Uint8List readBytes(ZipRecord r, {String? password, int? maxBytes}) {
    if (maxBytes != null && r.size > maxBytes) {
      throw const ArchiveException(ArchiveErrorKind.tooLarge);
    }
    final out = BytesBuilder(copy: false);
    final job = begin(r, (d) {
      out.add(d is Uint8List ? Uint8List.fromList(d) : d);
      if (maxBytes != null && out.length > maxBytes) {
        throw const ArchiveException(ArchiveErrorKind.tooLarge);
      }
    }, password: password);
    while (job.step()) {}
    job.finish();
    return out.takeBytes();
  }

  void close() => _file.closeSync();
}

/// One entry being extracted chunk by chunk.
class ZipEntryExtraction {
  ZipEntryExtraction._(
    this._file,
    this.record,
    void Function(List<int>) onData,
    String? password,
  ) {
    final r = record;
    if (r.isDirectory) throw ArgumentError('Directory entry');
    if (r.method != _methodStore && r.method != _methodDeflate) {
      throw const ArchiveException(
        ArchiveErrorKind.unsupported,
        'Unsupported compression method',
      );
    }
    _file.setPositionSync(r.localOffset);
    final head = _file.readSync(30);
    if (head.length != 30 || _r32(head, 0) != _sigLocal) {
      throw _corrupt('Bad local header');
    }
    _position = r.localOffset + 30 + _r16(head, 26) + _r16(head, 28);
    _remaining = r.compressedSize;
    void sink(List<int> d) {
      if (d.isEmpty) return;
      _crc.add(d);
      _produced += d.length;
      if (_produced > r.size) throw _corrupt('Entry larger than declared');
      onData(d);
    }

    if (r.encrypted) {
      final strength = r.aesStrength;
      if (strength == null || strength < 1 || strength > 3) {
        throw const ArchiveException(
          ArchiveErrorKind.unsupported,
          'Only AES-encrypted ZIP entries are supported',
        );
      }
      if (password == null) {
        throw const ArchiveException(ArchiveErrorKind.passwordRequired);
      }
      final pw = Uint8List.fromList(utf8.encode(password));
      final keyLength = 8 + strength * 8;
      final saltLength = keyLength ~/ 2;
      if (_remaining < saltLength + 2 + 10) throw _corrupt('Truncated entry');
      _file.setPositionSync(_position);
      final salt = _file.readSync(saltLength);
      final verifier = _file.readSync(2);
      final keys = deriveAeKeys(pw, salt, keyLength);
      if (!bytesEqual(verifier, keys.verifier)) {
        throw const ArchiveException(ArchiveErrorKind.wrongPassword);
      }
      _ctr = WinZipAesCtr(keys.aesKey);
      _mac = HmacSha1Stream(keys.hmacKey);
      _position += saltLength + 2;
      _remaining -= saltLength + 2 + 10;
    }
    _inflater = r.method == _methodDeflate
        ? ZLibDecoder(raw: true).startChunkedConversion(_CallbackSink(sink))
        : null;
    _sink = sink;
  }

  final RandomAccessFile _file;
  final ZipRecord record;
  late final void Function(List<int>) _sink;
  ByteConversionSink? _inflater;
  WinZipAesCtr? _ctr;
  HmacSha1Stream? _mac;
  final _crc = Crc32();
  late int _position;
  late int _remaining;
  int _produced = 0;

  /// Processes the next chunk; false when all input is consumed.
  bool step() {
    if (_remaining <= 0) return false;
    final n = _remaining < zipChunkSize ? _remaining : zipChunkSize;
    _file.setPositionSync(_position);
    final buf = _file.readSync(n);
    if (buf.length != n) throw _corrupt('Truncated entry');
    _position += n;
    _remaining -= n;
    final ctr = _ctr;
    if (ctr != null) {
      _mac!.add(buf);
      ctr.process(buf);
    }
    try {
      final inflater = _inflater;
      if (inflater != null) {
        inflater.add(buf);
      } else {
        _sink(buf);
      }
    } on FormatException {
      throw _corrupt('Damaged compressed data');
    }
    return _remaining > 0;
  }

  /// Verifies size and integrity.
  void finish() {
    while (step()) {}
    try {
      _inflater?.close();
    } on FormatException {
      throw _corrupt('Damaged compressed data');
    }
    final mac = _mac;
    if (mac != null) {
      _file.setPositionSync(_position);
      final stored = _file.readSync(10);
      final computed = mac.close().sublist(0, 10);
      if (stored.length != 10 || !bytesEqual(stored, computed)) {
        throw _corrupt('Integrity check failed (damaged, or wrong password)');
      }
    }
    if (_produced != record.size) throw _corrupt('Entry size mismatch');
    final checkCrc = mac == null || record.aesVersion == 1;
    if (checkCrc && _crc.value != record.crc) {
      throw _corrupt('CRC mismatch');
    }
  }
}
