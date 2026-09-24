import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_library/src/document_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Files tab: the local library.
class FilesScreen extends ConsumerWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => DocumentBrowser(
    title: 'Files',
    actions: [
      IconButton(
        tooltip: 'New folder',
        icon: const Icon(Icons.create_new_folder_outlined),
        onPressed: () => createFolder(context, ref),
      ),
    ],
    header: const SliverToBoxAdapter(child: _FoldersRow()),
  );
}

Future<void> createFolder(BuildContext context, WidgetRef ref) async {
  final name = await promptText(
    context,
    title: 'New folder',
    confirmLabel: 'Create',
    hint: 'Folder name',
  );
  if (name == null || name.isEmpty) return;
  final result = await ref.read(documentRepositoryProvider).addFolder(name);
  if (!context.mounted) return;
  result.fold(
    (f) => showAppSnack(context, 'Folder "${f.name}" created'),
    (f) => showFailureSnack(context, f),
  );
}

class _FoldersRow extends ConsumerWidget {
  const _FoldersRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersProvider).value ?? const <Folder>[];
    if (folders.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.x2,
          Space.gutter,
          Space.x1,
        ),
        itemCount: folders.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.x2),
        itemBuilder: (context, i) {
          final f = folders[i];
          return ActionChip(
            avatar: Icon(Icons.folder_rounded, color: context.colors.primary),
            label: Text(f.name),
            tooltip: 'Open folder ${f.name}',
            onPressed: () => context.push(Routes.folder(f.id)),
          );
        },
      ),
    );
  }
}
