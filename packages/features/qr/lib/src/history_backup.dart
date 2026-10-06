import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_qr/src/history.dart';

/// QR scan history in the full backup (audit H-04): settings and entries.
class QrHistoryBackupSection implements BackupSection {
  QrHistoryBackupSection(this._store);

  static const sectionKey = 'qr-history';

  final QrHistoryStore _store;

  @override
  String get key => sectionKey;

  @override
  String get label => 'QR scan history';

  @override
  Future<BackupSectionData?> export() async {
    final state = await _store.load();
    return BackupSectionData(
      version: 1,
      data: state.toJson(),
      count: state.entries.length,
    );
  }

  /// Merges entries (by id), newest first, capped like the live history.
  /// The history switches come from the backup.
  @override
  Future<int> restore(Object? data, {required int version}) async {
    if (data is! Map) return 0;
    final incoming = QrHistoryState.fromJson(data.cast<String, Object?>());
    final current = await _store.load();
    final ids = {for (final e in current.entries) e.id};
    final added = [
      for (final e in incoming.entries)
        if (!ids.contains(e.id)) e,
    ];
    final merged = [...current.entries, ...added]
      ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    await _store.save(
      current.copyWith(
        enabled: incoming.enabled,
        includeSensitive: incoming.includeSensitive,
        entries: merged.take(QrHistoryController.maxEntries).toList(),
      ),
    );
    return added.length;
  }

  @override
  Future<void> erase() => _store.save(const QrHistoryState());
}
