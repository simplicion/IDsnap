import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_library/src/folders/folder_actions.dart';
import 'package:feature_library/src/folders/folder_lock.dart';
import 'package:feature_library/src/folders/folder_providers.dart';
import 'package:feature_library/src/library_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// User-initiated actions on library documents, shared by the list and the
/// viewer so behaviour (and copy) stays consistent.
class DocumentActions {
  DocumentActions(this.ref);

  final WidgetRef ref;

  Future<void> share(BuildContext context, List<Document> docs) async {
    final files = ref.read(fileStoreProvider);
    try {
      final paths = [
        for (final d in docs)
          await files.exportCopy(d.relativePath, d.fileName),
      ];
      // The share sheet is a system screen: don't relock folders for it.
      final result = await ref
          .read(folderAccessProvider.notifier)
          .whileExternal(
            () => ref
                .read(shareServiceProvider)
                .share(
                  paths,
                  subject: docs.length == 1 ? docs.single.name : null,
                ),
          );
      // Decrypted share copies are shredded once the receiving app has had
      // time to read them, and at the next launch otherwise (ADR-0010).
      final plain = ref.read(plainFileAccessProvider);
      for (final path in paths) {
        await plain.releaseTemp(path, grace: const Duration(minutes: 2));
      }
      if (result case Err(:final failure) when context.mounted) {
        showFailureSnack(context, failure);
      }
    } on Object catch (e) {
      if (context.mounted) {
        showFailureSnack(
          context,
          AppFailure(
            FailureCode.unknown,
            cause: e,
            message:
                "The file couldn't be prepared for sharing. It is still in "
                'ID Vault and unchanged; try again.',
          ),
        );
      }
    }
  }

  /// Opens the Protect file tool with [doc] preselected: password-protect
  /// it (AES-256 PDF or ZIP), then share. The vault copy is unchanged.
  Future<void> protectAndShare(BuildContext context, Document doc) async {
    // A document in a locked folder is only reachable once unlocked, so no
    // extra access check is needed here. Pro: asks before opening the tool.
    if (!await ensurePro(context, ref, ProFeature.protectFile)) return;
    if (!context.mounted) return;
    await context.push<void>(Routes.tool(ToolId.protectFile, docId: doc.id));
  }

  Future<void> saveToDevice(BuildContext context, Document doc) async {
    final files = ref.read(fileStoreProvider);
    try {
      final bytes = await files.read(files.absolute(doc.relativePath));
      final result = await ref
          .read(folderAccessProvider.notifier)
          .whileExternal(
            () => ref
                .read(shareServiceProvider)
                .saveToDevice(bytes, doc.fileName),
          );
      if (!context.mounted) return;
      result.fold((saved) {
        if (saved) showAppSnack(context, 'Saved ${doc.fileName}');
      }, (f) => showFailureSnack(context, f));
    } on Object catch (e) {
      if (context.mounted) {
        showFailureSnack(
          context,
          AppFailure(
            FailureCode.unknown,
            cause: e,
            message:
                "The file couldn't be saved to this phone's storage. It is "
                'still in ID Vault and unchanged; try again or use Share.',
          ),
        );
      }
    }
  }

  Future<void> rename(BuildContext context, Document doc) async {
    final name = await promptText(
      context,
      title: 'Rename',
      confirmLabel: 'Rename',
      initial: doc.name,
      hint: 'Document name',
    );
    if (name == null || name.isEmpty || name == doc.name || !context.mounted) {
      return;
    }
    await _update(context, doc.copyWith(name: name, updatedAt: DateTime.now()));
  }

  Future<void> toggleFavorite(BuildContext context, Document doc) => _update(
    context,
    doc.copyWith(favorite: !doc.favorite, updatedAt: DateTime.now()),
  );

  /// Moves documents into a folder picked from the tree. Moving out of a
  /// locked folder needs it unlocked first.
  Future<void> moveToFolder(BuildContext context, List<Document> docs) async {
    if (docs.isEmpty) return;
    for (final folderId in {for (final d in docs) d.folderId}) {
      if (!await ensureFolderAccess(context, ref, folderId)) return;
      if (!context.mounted) return;
    }
    final target = await pickFolder(
      context,
      title: docs.length == 1
          ? 'Move "${docs.single.name}" to'
          : 'Move ${docs.length} files to',
      initial: docs.first.folderId,
    );
    if (target == null || !context.mounted) return;
    final result = await ref.read(folderRepositoryProvider).moveDocuments([
      for (final d in docs) d.id,
    ], target.folderId);
    for (final d in docs) {
      ref.invalidate(documentByIdProvider(d.id));
    }
    if (!context.mounted) return;
    result.fold(
      (_) => showAppSnack(
        context,
        docs.length == 1 ? 'Moved' : 'Moved ${docs.length} files',
      ),
      (f) => showFailureSnack(context, f),
    );
  }

  /// Sets an expiry date and (re)schedules local reminders.
  Future<void> setExpiry(BuildContext context, Document doc) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: doc.expiresAt ?? DateTime(now.year + 1, now.month, now.day),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 30),
      helpText: 'Expiry date',
      confirmText: 'Save',
    );
    if (picked == null || !context.mounted) return;
    final updated = doc.copyWith(expiresAt: picked, updatedAt: DateTime.now());
    await _update(context, updated);
    if (!context.mounted) return;
    final remind = ref.read(currentSettingsProvider).expiryReminders;
    final scheduled = remind ? await _schedule(context, updated) : false;
    // null: a failure snack already says the date is saved and what to do.
    if (scheduled != null && context.mounted) {
      showAppSnack(
        context,
        scheduled
            ? 'Expiry saved. You will be reminded 30 and 7 days before.'
            : 'Expiry date saved',
      );
    }
  }

  Future<void> clearExpiry(BuildContext context, Document doc) async {
    await _update(
      context,
      doc.copyWith(clearExpiry: true, updatedAt: DateTime.now()),
    );
    await cancelReminders(ref, doc.id);
    if (context.mounted) showAppSnack(context, 'Expiry date removed');
  }

  /// `true` scheduled, `false` reminders unavailable here, `null` failed
  /// (permission denied or the phone refused): the failure is shown with
  /// what to do (audit H-01), and the expiry date stays saved.
  Future<bool?> _schedule(BuildContext context, Document doc) async {
    switch (await ref.read(expiryRemindersProvider).scheduleFor(doc)) {
      case Ok(:final value):
        return value;
      case Err(:final failure):
        if (context.mounted) showFailureSnack(context, failure);
        return null;
    }
  }

  /// Confirms, then hides the documents with a 5-second undo window.
  Future<bool> delete(BuildContext context, List<Document> docs) async {
    final single = docs.length == 1;
    final ok = await confirmAction(
      context,
      title: single ? 'Delete document?' : 'Delete ${docs.length} documents?',
      message: single
          ? '"${docs.single.name}" will be removed from this device.'
          : 'These documents will be removed from this device.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return false;
    final pending = ref.read(pendingDeletesProvider.notifier)..schedule(docs);
    showAppSnack(
      context,
      single ? 'Document deleted' : '${docs.length} documents deleted',
      actionLabel: 'Undo',
      onAction: () => pending.undo(docs),
    );
    return true;
  }

  Future<void> _update(BuildContext context, Document doc) async {
    final result = await ref.read(documentRepositoryProvider).update(doc);
    ref.invalidate(documentByIdProvider(doc.id));
    if (result case Err(:final failure) when context.mounted) {
      showFailureSnack(context, failure);
    }
  }
}

/// Cancels reminders for a document; a no-op when reminders aren't wired.
Future<void> cancelReminders(WidgetRef ref, String documentId) async {
  try {
    await ref.read(reminderSchedulerProvider).cancel(documentId);
  } on Object {
    // Reminders unavailable: nothing was scheduled.
  }
}
