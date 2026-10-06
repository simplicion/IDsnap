import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Deletes documents after a grace period so the user can undo.
///
/// Files can't be restored once removed, so deletion is *delayed*: the
/// documents are hidden immediately (state holds their ids) and only removed
/// from disk and the database when [delay] passes without an undo.
class PendingDeleteController extends Notifier<Set<String>> {
  static const delay = Duration(seconds: 5);

  final Map<String, Timer> _timers = {};

  @override
  Set<String> build() {
    ref.onDispose(() {
      for (final t in _timers.values) {
        t.cancel();
      }
      _timers.clear();
    });
    return const {};
  }

  /// Hides [docs] now and deletes them after [delay].
  void schedule(List<Document> docs) {
    if (docs.isEmpty) return;
    final key = docs.map((d) => d.id).join(',');
    state = {...state, ...docs.map((d) => d.id)};
    _timers[key] = Timer(delay, () {
      _timers.remove(key);
      unawaited(_commit(docs));
    });
  }

  /// Cancels a scheduled deletion; the documents reappear.
  void undo(List<Document> docs) {
    final key = docs.map((d) => d.id).join(',');
    _timers.remove(key)?.cancel();
    final ids = docs.map((d) => d.id).toSet();
    state = state.difference(ids);
  }

  Future<void> _commit(List<Document> docs) async {
    await deleteDocumentsNow(ref, docs);
    if (!ref.mounted) return;
    state = state.difference(docs.map((d) => d.id).toSet());
  }
}

final pendingDeletesProvider =
    NotifierProvider<PendingDeleteController, Set<String>>(
      PendingDeleteController.new,
    );

/// Removes files first, then rows, so a failure never leaves a row pointing
/// at a missing file.
Future<void> deleteDocumentsNow(Ref ref, List<Document> docs) async {
  final files = ref.read(fileStoreProvider);
  final repo = ref.read(documentRepositoryProvider);
  for (final d in docs) {
    await files.delete(d.relativePath);
    final thumb = d.thumbnailPath;
    if (thumb != null) await files.delete(thumb);
    await repo.remove(d.id);
    if (d.expiresAt != null) {
      try {
        await ref.read(reminderSchedulerProvider).cancel(d.id);
      } on Object {
        // Reminders not wired: nothing was scheduled.
      }
    }
  }
}
