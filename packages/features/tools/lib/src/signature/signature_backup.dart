import 'dart:convert';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';

/// Saved signatures in the full backup (audit H-04): each PNG (Base64),
/// its size and which one is the default.
class SignatureBackupSection implements BackupSection {
  SignatureBackupSection(this._library);

  static const sectionKey = 'signatures';

  final SignatureLibrary _library;

  @override
  String get key => sectionKey;

  @override
  String get label => 'Saved signatures';

  T _orThrow<T>(Result<T> r) => r.fold((v) => v, (f) => throw f);

  @override
  Future<BackupSectionData?> export() async {
    final list = _orThrow(await _library.list());
    if (list.isEmpty) return null;
    final items = <Map<String, Object?>>[];
    for (final s in list) {
      final png = _orThrow(await _library.load(s.id));
      items.add({
        'png': base64Encode(png),
        'width': s.width,
        'height': s.height,
        'createdAt': s.createdAt.toIso8601String(),
        'isDefault': s.isDefault,
      });
    }
    return BackupSectionData(version: 1, data: items, count: items.length);
  }

  /// Skips signatures already saved (same image). Stops quietly at
  /// [SignatureLibrary.capacity].
  @override
  Future<int> restore(Object? data, {required int version}) async {
    if (data is! List) return 0;
    final existing = _orThrow(await _library.list());
    final have = <String>{};
    for (final s in existing) {
      have.add(base64Encode(_orThrow(await _library.load(s.id))));
    }
    var added = 0;
    String? defaultId;
    for (final item in data) {
      if (item is! Map) continue;
      final png = item['png'];
      final width = item['width'];
      final height = item['height'];
      if (png is! String || width is! int || height is! int) continue;
      if (have.contains(png)) continue;
      if (existing.length + added >= SignatureLibrary.capacity) break;
      final List<int> bytes;
      try {
        bytes = base64Decode(png);
      } on FormatException {
        continue;
      }
      final saved = await _library.add(
        Uint8List.fromList(bytes),
        width: width,
        height: height,
      );
      final sig = saved.valueOrNull;
      if (sig == null) continue; // Unreadable image: skip it.
      have.add(png);
      added++;
      if (item['isDefault'] == true) defaultId = sig.id;
    }
    // The old default stays the default unless this phone had none.
    if (defaultId != null && existing.isEmpty) {
      await _library.setDefault(defaultId);
    }
    return added;
  }

  @override
  Future<void> erase() async {
    for (final s in _orThrow(await _library.list())) {
      _orThrow(await _library.delete(s.id));
    }
  }
}
