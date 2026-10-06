import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart' show FileCipher;
import 'package:engine_codes/engine_codes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One remembered scan. Only the payload is kept; it is re-parsed on open.
@immutable
class QrHistoryEntry {
  const QrHistoryEntry({
    required this.id,
    required this.raw,
    required this.symbology,
    required this.kind,
    required this.summary,
    required this.scannedAt,
  });

  factory QrHistoryEntry.fromJson(Map<String, Object?> json) => QrHistoryEntry(
    id: json['id']! as String,
    raw: json['raw']! as String,
    symbology: CodeSymbology.byName(json['symbology'] as String?),
    kind: CodeKind.byName(json['kind'] as String?),
    summary: (json['summary'] as String?) ?? '',
    scannedAt:
        DateTime.tryParse((json['scannedAt'] as String?) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  final String id;
  final String raw;
  final CodeSymbology symbology;
  final CodeKind kind;
  final String summary;
  final DateTime scannedAt;

  ScannedCode get code => ScannedCode(raw: raw, symbology: symbology);

  Map<String, Object?> toJson() => {
    'id': id,
    'raw': raw,
    'symbology': symbology.name,
    'kind': kind.name,
    'summary': summary,
    'scannedAt': scannedAt.toIso8601String(),
  };
}

/// History settings and entries (newest first).
@immutable
class QrHistoryState {
  const QrHistoryState({
    this.enabled = true,
    this.includeSensitive = false,
    this.entries = const [],
  });

  factory QrHistoryState.fromJson(Map<String, Object?> json) {
    final list = json['entries'];
    return QrHistoryState(
      enabled: json['enabled'] as bool? ?? true,
      includeSensitive: json['includeSensitive'] as bool? ?? false,
      entries: [
        if (list is List)
          for (final e in list)
            if (e is Map<String, Object?>) ?_tryEntry(e),
      ],
    );
  }

  /// Keep a history of scans at all.
  final bool enabled;

  /// Also keep Wi-Fi passwords, payment requests and ID card data.
  /// Two-step verification keys are never kept.
  final bool includeSensitive;
  final List<QrHistoryEntry> entries;

  QrHistoryState copyWith({
    bool? enabled,
    bool? includeSensitive,
    List<QrHistoryEntry>? entries,
  }) => QrHistoryState(
    enabled: enabled ?? this.enabled,
    includeSensitive: includeSensitive ?? this.includeSensitive,
    entries: entries ?? this.entries,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'enabled': enabled,
    'includeSensitive': includeSensitive,
    'entries': [for (final e in entries) e.toJson()],
  };

  /// Whether [content] may be stored under these settings.
  bool allows(CodeContent content) {
    if (!enabled || content.neverStore) return false;
    if (content.isSensitive && !includeSensitive) return false;
    return content.raw.trim().isNotEmpty;
  }
}

QrHistoryEntry? _tryEntry(Map<String, Object?> json) {
  try {
    return QrHistoryEntry.fromJson(json);
  } on Object {
    return null;
  }
}

/// Where history is kept.
abstract interface class QrHistoryStore {
  Future<QrHistoryState> load();
  Future<void> save(QrHistoryState state);
}

class MemoryQrHistoryStore implements QrHistoryStore {
  MemoryQrHistoryStore([this.state = const QrHistoryState()]);

  QrHistoryState state;

  @override
  Future<QrHistoryState> load() async => state;

  @override
  Future<void> save(QrHistoryState state) async => this.state = state;
}

/// A JSON file in app-private storage, replaced atomically on save. A
/// missing or unreadable file starts an empty history.
///
/// With a [cipher] (the app's vault cipher, ADR-0010) the file is encrypted
/// at rest; a plaintext file from an older version is read once and
/// rewritten encrypted.
class JsonFileQrHistoryStore implements QrHistoryStore {
  JsonFileQrHistoryStore(this.file, {this.cipher});

  final File file;
  final FileCipher? cipher;

  @override
  Future<QrHistoryState> load() async {
    try {
      if (!file.existsSync()) return const QrHistoryState();
      var bytes = await file.readAsBytes();
      final c = cipher;
      final legacy = c != null && !c.isEncrypted(bytes);
      if (c != null && !legacy) bytes = await c.decryptBytes(bytes);
      final json = jsonDecode(utf8.decode(bytes));
      if (json is Map<String, Object?>) {
        final state = QrHistoryState.fromJson(json);
        if (legacy) await save(state); // Migrate to the encrypted format.
        return state;
      }
    } on Object {
      // Corrupt file: start again rather than failing the scanner.
    }
    return const QrHistoryState();
  }

  @override
  Future<void> save(QrHistoryState state) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    final plain = utf8.encode(jsonEncode(state.toJson()));
    final c = cipher;
    await tmp.writeAsBytes(
      c == null ? plain : await c.encryptBytes(plain),
      flush: true,
    );
    await tmp.rename(file.path);
  }
}

final qrHistoryStoreProvider = Provider<QrHistoryStore>(
  (ref) => MemoryQrHistoryStore(),
);

class QrHistoryController extends AsyncNotifier<QrHistoryState> {
  static const maxEntries = 200;

  QrHistoryStore get _store => ref.read(qrHistoryStoreProvider);

  @override
  Future<QrHistoryState> build() => ref.watch(qrHistoryStoreProvider).load();

  Future<QrHistoryState> _current() async => state.value ?? await future;

  Future<void> _set(QrHistoryState next) async {
    state = AsyncData(next);
    try {
      await _store.save(next);
    } on Object {
      // Storage full or unavailable: keep the in-memory state.
    }
  }

  /// Stores [code] when the settings allow it. Returns whether it was kept.
  Future<bool> record(ScannedCode code, {CodeContent? content}) async {
    final parsed = content ?? CodeParser.parseCode(code);
    final current = await _current();
    if (!current.allows(parsed)) return false;
    final entry = QrHistoryEntry(
      id: newId(),
      raw: code.raw,
      symbology: code.symbology,
      kind: parsed.kind,
      summary: parsed.summary,
      scannedAt: DateTime.now(),
    );
    final rest = current.entries.where(
      (e) => !(e.raw == code.raw && e.symbology == code.symbology),
    );
    await _set(
      current.copyWith(entries: [entry, ...rest].take(maxEntries).toList()),
    );
    return true;
  }

  /// Turning history off also deletes what was kept.
  Future<void> setEnabled({required bool enabled}) async {
    final current = await _current();
    await _set(
      current.copyWith(
        enabled: enabled,
        entries: enabled ? current.entries : const [],
      ),
    );
  }

  /// Turning sensitive items off removes the ones already kept.
  Future<void> setIncludeSensitive({required bool include}) async {
    final current = await _current();
    await _set(
      current.copyWith(
        includeSensitive: include,
        entries: include
            ? current.entries
            : current.entries
                  .where((e) => !CodeParser.parseCode(e.code).isSensitive)
                  .toList(),
      ),
    );
  }

  Future<void> remove(String id) async {
    final current = await _current();
    await _set(
      current.copyWith(
        entries: current.entries.where((e) => e.id != id).toList(),
      ),
    );
  }

  Future<void> clear() async {
    final current = await _current();
    await _set(current.copyWith(entries: const []));
  }
}

final qrHistoryProvider =
    AsyncNotifierProvider<QrHistoryController, QrHistoryState>(
      QrHistoryController.new,
    );
