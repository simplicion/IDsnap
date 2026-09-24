import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_library/src/document_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Documents in one folder, with rename/delete folder actions.
class FolderScreen extends ConsumerWidget {
  const FolderScreen({required this.folderId, super.key});

  final String folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersProvider).value ?? const <Folder>[];
    final folder = folders.where((f) => f.id == folderId).firstOrNull;
    return DocumentBrowser(
      key: ValueKey(folderId),
      title: folder?.name ?? 'Folder',
      folderId: folderId,
      emptyTitle: 'This folder is empty',
      emptyMessage:
          'Long-press documents in Files and choose "Move to folder".',
      actions: [
        if (folder != null)
          PopupMenuButton<String>(
            tooltip: 'Folder actions',
            onSelected: (v) => v == 'rename'
                ? _rename(context, ref, folder)
                : _delete(context, ref, folder),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename folder')),
              PopupMenuItem(value: 'delete', child: Text('Delete folder')),
            ],
          ),
      ],
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    Folder folder,
  ) async {
    final name = await promptText(
      context,
      title: 'Rename folder',
      confirmLabel: 'Rename',
      initial: folder.name,
    );
    if (name == null || name.isEmpty) return;
    final r = await ref
        .read(documentRepositoryProvider)
        .renameFolder(folder.id, name);
    if (r.failureOrNull case final f? when context.mounted) {
      showFailureSnack(context, f);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Folder folder,
  ) async {
    final ok = await confirmAction(
      context,
      title: 'Delete folder?',
      message:
          'The folder is removed. Its documents are kept and move back to All files.',
      confirmLabel: 'Delete folder',
      destructive: true,
    );
    if (!ok) return;
    final r = await ref
        .read(documentRepositoryProvider)
        .removeFolder(folder.id);
    if (!context.mounted) return;
    r.fold((_) {
      showAppSnack(context, 'Folder deleted');
      context.pop();
    }, (f) => showFailureSnack(context, f));
  }
}
