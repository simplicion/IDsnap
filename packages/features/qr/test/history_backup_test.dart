import 'package:engine_codes/engine_codes.dart';
import 'package:feature_qr/feature_qr.dart';
import 'package:flutter_test/flutter_test.dart';

QrHistoryEntry _entry(String id, int day) => QrHistoryEntry(
  id: id,
  raw: 'https://example.com/$id',
  symbology: CodeSymbology.byName('qr'),
  kind: CodeKind.url,
  summary: id,
  scannedAt: DateTime(2026, 1, day),
);

void main() {
  test('QR history: export → erase → restore, merged and idempotent', () async {
    final store = MemoryQrHistoryStore(
      QrHistoryState(
        includeSensitive: true,
        entries: [_entry('b', 2), _entry('a', 1)],
      ),
    );
    final section = QrHistoryBackupSection(store);
    final data = (await section.export())!;
    expect(data.count, 2);

    await section.erase();
    expect(store.state.entries, isEmpty);
    expect(store.state.includeSensitive, isFalse);

    // Something scanned on the new phone stays; the backup is merged in.
    store.state = QrHistoryState(entries: [_entry('c', 3)]);
    expect(await section.restore(data.data, version: data.version), 2);
    expect(store.state.entries.map((e) => e.id), ['c', 'b', 'a']);
    expect(store.state.includeSensitive, isTrue);
    expect(await section.restore(data.data, version: 1), 0);
    expect(store.state.entries, hasLength(3));
    expect(await section.restore('junk', version: 1), 0);
  });
}
