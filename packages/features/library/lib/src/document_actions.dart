import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_library/src/library_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      final result = await ref
          .read(shareServiceProvider)
          .share(paths, subject: docs.length == 1 ? docs.single.name : null);
      if (result case Err(:final failure) when context.mounted) {
        showFailureSnack(context, failure);
      }
    } on Object catch (e) {
      if (context.mounted) {
        showFailureSnack(context, AppFailure(FailureCode.notFound, cause: e));
      }
    }
  }

  Future<void> saveToDevice(BuildContext context, Document doc) async {
    final files = ref.read(fileStoreProvider);
    try {
      final bytes = await files.read(files.absolute(doc.relativePath));
      final result = await ref
          .read(shareServiceProvider)
          .saveToDevice(bytes, doc.fileName);
      if (!context.mounted) return;
      result.fold((saved) {
        if (saved) showAppSnack(context, 'Saved ${doc.fileName}');
      }, (f) => showFailureSnack(context, f));
    } on Object catch (e) {
      if (context.mounted) {
        showFailureSnack(context, AppFailure(FailureCode.notFound, cause: e));
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

  Future<void> moveToFolder(BuildContext context, List<Document> docs) async {
    final choice = await showModalBottomSheet<_FolderChoice>(
      context: context,
      builder: (context) => const _FolderPicker(),
    );
    if (choice == null || !context.mounted) return;
    var folderId = choice.folderId;
    if (choice.createNew) {
      final name = await promptText(
        context,
        title: 'New folder',
        confirmLabel: 'Create',
        hint: 'Folder name',
      );
      if (name == null || name.isEmpty || !context.mounted) return;
      final created = await ref
          .read(documentRepositoryProvider)
          .addFolder(name);
      folderId = created.valueOrNull?.id;
      if (folderId == null) {
        if (context.mounted) showFailureSnack(context, created.failureOrNull!);
        return;
      }
    }
    for (final d in docs) {
      if (!context.mounted) return;
      await _update(
        context,
        d.copyWith(
          folderId: folderId,
          clearFolder: folderId == null,
          updatedAt: DateTime.now(),
        ),
      );
    }
    if (context.mounted) {
      showAppSnack(
        context,
        docs.length == 1 ? 'Moved' : 'Moved ${docs.length} documents',
      );
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

class _FolderChoice {
  const _FolderChoice(this.folderId, {this.createNew = false});

  final String? folderId;
  final bool createNew;
}

class _FolderPicker extends ConsumerWidget {
  const _FolderPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersProvider).value ?? const <Folder>[];
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.x2,
            ),
            child: Text('Move to', style: context.text.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.inbox_rounded),
            title: const Text('All files (no folder)'),
            onTap: () => Navigator.pop(context, const _FolderChoice(null)),
          ),
          for (final f in folders)
            ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: Text(f.name),
              onTap: () => Navigator.pop(context, _FolderChoice(f.id)),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_rounded),
            title: const Text('New folder…'),
            onTap: () => Navigator.pop(
              context,
              const _FolderChoice(null, createNew: true),
            ),
          ),
        ],
      ),
    );
  }
}
