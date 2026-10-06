import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_library/src/folders/add_menu.dart';
import 'package:feature_library/src/folders/folder_lock.dart';
import 'package:feature_library/src/folders/folder_providers.dart';
import 'package:feature_library/src/folders/folder_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _FolderAction { open, rename, style, move, lock, delete }

/// Long-press / overflow menu for a folder. [onDeleted] runs after the
/// folder is gone (e.g. to leave its screen).
Future<void> showFolderActions(
  BuildContext context,
  WidgetRef ref,
  Folder folder, {
  bool showOpen = true,
  VoidCallback? onDeleted,
}) async {
  final action = await showModalBottomSheet<_FolderAction>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      Widget item(
        _FolderAction a,
        IconData icon,
        String label, {
        bool destructive = false,
      }) {
        final color = destructive ? context.colors.error : null;
        return ListTile(
          leading: Icon(icon, color: color),
          title: Text(label, style: TextStyle(color: color)),
          onTap: () => Navigator.pop(context, a),
        );
      }

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: FolderBadge(folder: folder),
                title: Text(folder.name, style: context.text.titleMedium),
                subtitle: folder.isLocked
                    ? Text(
                        folder.lockMode == FolderLockMode.pin
                            ? 'Locked with a PIN'
                            : 'Locked with your phone’s screen lock',
                      )
                    : null,
              ),
              const Divider(),
              if (showOpen)
                item(_FolderAction.open, Icons.folder_open_rounded, 'Open'),
              item(
                _FolderAction.rename,
                Icons.drive_file_rename_outline_rounded,
                'Rename',
              ),
              item(
                _FolderAction.style,
                Icons.palette_outlined,
                'Change icon & colour',
              ),
              item(_FolderAction.move, Icons.drive_file_move_rounded, 'Move'),
              item(
                _FolderAction.lock,
                folder.isLocked
                    ? Icons.lock_rounded
                    : Icons.lock_outline_rounded,
                folder.isLocked ? 'Change lock' : 'Lock folder',
              ),
              item(
                _FolderAction.delete,
                Icons.delete_outline_rounded,
                'Delete folder',
                destructive: true,
              ),
            ],
          ),
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;
  if (action == _FolderAction.open) {
    unawaited(context.push(Routes.folder(folder.id)));
    return;
  }
  // Every change to a locked folder needs it unlocked first.
  if (!await ensureFolderAccess(context, ref, folder.id)) return;
  if (!context.mounted) return;
  switch (action) {
    case _FolderAction.open:
      break;
    case _FolderAction.rename:
      await renameFolder(context, ref, folder);
    case _FolderAction.style:
      await changeFolderStyle(context, ref, folder);
    case _FolderAction.move:
      await moveFolder(context, ref, folder);
    case _FolderAction.lock:
      await configureFolderLock(context, ref, folder);
    case _FolderAction.delete:
      final deleted = await deleteFolder(context, ref, folder);
      if (deleted) onDeleted?.call();
  }
}

Future<void> renameFolder(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final tree = await ref.read(folderTreeProvider.future);
  if (!context.mounted) return;
  final name = await promptFolderName(
    context,
    title: 'Rename folder',
    confirmLabel: 'Rename',
    initial: folder.name,
    siblings: [
      for (final f in tree.children(folder.parentId))
        if (f.id != folder.id) f.name,
    ],
  );
  if (name == null || name == folder.name || !context.mounted) return;
  final r = await ref
      .read(folderRepositoryProvider)
      .renameFolder(folder.id, name);
  if (r case Err(:final failure) when context.mounted) {
    showFailureSnack(context, failure);
  }
}

Future<void> changeFolderStyle(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final picked = await showModalBottomSheet<({String? icon, String? color})>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _StyleSheet(folder: folder),
  );
  if (picked == null || !context.mounted) return;
  final r = await ref
      .read(folderRepositoryProvider)
      .setFolderStyle(folder.id, icon: picked.icon, color: picked.color);
  if (r case Err(:final failure) when context.mounted) {
    showFailureSnack(context, failure);
  }
}

class _StyleSheet extends StatefulWidget {
  const _StyleSheet({required this.folder});

  final Folder folder;

  @override
  State<_StyleSheet> createState() => _StyleSheetState();
}

class _StyleSheetState extends State<_StyleSheet> {
  late String? _icon = widget.folder.icon;
  late String? _color = widget.folder.color;

  @override
  Widget build(BuildContext context) {
    final accent = folderColor(context, _color);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Icon & colour', style: context.text.titleMedium),
            const SizedBox(height: Space.x3),
            Wrap(
              spacing: Space.x2,
              runSpacing: Space.x2,
              children: [
                for (final key in FolderIcons.all)
                  ChoiceChip(
                    tooltip: key,
                    label: Icon(folderIconData(key), color: accent),
                    selected: (_icon ?? FolderIcons.folder) == key,
                    onSelected: (_) => setState(() => _icon = key),
                  ),
              ],
            ),
            const SizedBox(height: Space.x4),
            Wrap(
              spacing: Space.x2,
              runSpacing: Space.x2,
              children: [
                for (final key in FolderColors.all)
                  Semantics(
                    label: 'Colour $key',
                    selected: _color == key,
                    button: true,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = key),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: folderColor(context, key),
                          shape: BoxShape.circle,
                          border: _color == key
                              ? Border.all(
                                  color: context.colors.onSurface,
                                  width: 3,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.x4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    Navigator.pop(context, (icon: _icon, color: _color)),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> moveFolder(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final tree = await ref.read(folderTreeProvider.future);
  if (!context.mounted) return;
  final target = await pickFolder(
    context,
    title: 'Move "${folder.name}" to',
    exclude: tree.subtreeIds(folder.id),
    initial: folder.parentId,
  );
  if (target == null || !context.mounted) return;
  final r = await ref
      .read(folderRepositoryProvider)
      .moveFolder(folder.id, target.folderId);
  if (!context.mounted) return;
  r.fold(
    (_) => showAppSnack(context, 'Moved'),
    (f) => showFailureSnack(context, f),
  );
}

/// Deletes [folder] after asking what to do with its contents. Returns true
/// when the folder was deleted.
Future<bool> deleteFolder(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final tree = await ref.read(folderTreeProvider.future);
  final counts = await ref.read(directCountsProvider.future);
  if (!context.mounted) return false;
  final stats = tree.stats(counts)[folder.id] ?? FolderStats.empty;
  final parentName = tree[folder.parentId]?.name ?? 'ID Vault';
  final FolderDeleteMode? mode;
  if (stats.isEmpty) {
    final ok = await confirmAction(
      context,
      title: 'Delete "${folder.name}"?',
      message: 'This empty folder will be removed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    mode = ok ? FolderDeleteMode.deleteContents : null;
  } else {
    mode = await showDialog<FolderDeleteMode>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${folder.name}"?'),
        content: Text(
          'It contains ${folderStatsLabel(stats, locked: false)}. What '
          'should happen to them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, FolderDeleteMode.moveContentsToParent),
            child: Text('Move them to $parentName'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              foregroundColor: context.colors.onError,
            ),
            onPressed: () =>
                Navigator.pop(context, FolderDeleteMode.deleteContents),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
  }
  if (mode == null || !context.mounted) return false;
  // Deleting what's inside locked subfolders needs them unlocked too.
  if (mode == FolderDeleteMode.deleteContents &&
      !await ensureFolderAccess(context, ref, folder.id, subtree: true)) {
    return false;
  }
  final removedFolders = mode == FolderDeleteMode.deleteContents
      ? [for (final id in tree.subtreeIds(folder.id)) tree[id]!]
      : [folder];
  final result = await ref
      .read(folderRepositoryProvider)
      .deleteFolder(folder.id, mode);
  switch (result) {
    case Err(:final failure):
      if (context.mounted) showFailureSnack(context, failure);
      return false;
    case Ok(value: final docs):
      await _deleteFiles(ref, docs);
      final pins = ref.read(folderPinStoreProvider);
      final access = ref.read(folderAccessProvider.notifier);
      for (final f in removedFolders) {
        access.revoke(f.id);
        if (f.lockMode == FolderLockMode.pin) {
          try {
            await pins.removePin(f.id);
          } on Object {
            // The keystore entry is unreachable without the folder anyway.
          }
        }
      }
      if (context.mounted) showAppSnack(context, 'Folder deleted');
      return true;
  }
}

/// Files and thumbnails of documents whose rows are already gone.
Future<void> _deleteFiles(WidgetRef ref, List<Document> docs) async {
  final files = ref.read(fileStoreProvider);
  for (final d in docs) {
    try {
      await files.delete(d.relativePath);
      final thumb = d.thumbnailPath;
      if (thumb != null) await files.delete(thumb);
    } on Object {
      // A leftover file is harmless; the row is gone.
    }
    if (d.expiresAt != null) {
      try {
        await ref.read(reminderSchedulerProvider).cancel(d.id);
      } on Object {
        // Reminders not wired.
      }
    }
  }
}

/// The folder picked in [pickFolder] (`folderId == null` = top level).
typedef FolderPick = ({String? folderId});

/// Browses the folder tree and returns the chosen destination. Folders in
/// [exclude] can't be chosen or entered; locked folders ask to unlock.
Future<FolderPick?> pickFolder(
  BuildContext context, {
  required String title,
  Set<String> exclude = const {},
  String? initial,
}) => showModalBottomSheet<FolderPick>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) =>
      _FolderPicker(title: title, exclude: exclude, initial: initial),
);

class _FolderPicker extends ConsumerStatefulWidget {
  const _FolderPicker({
    required this.title,
    required this.exclude,
    required this.initial,
  });

  final String title;
  final Set<String> exclude;
  final String? initial;

  @override
  ConsumerState<_FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends ConsumerState<_FolderPicker> {
  String? _current;

  @override
  void initState() {
    super.initState();
    final tree = ref.read(folderTreeProvider).value;
    final start = widget.initial;
    // Start where the item is, if that place is open right now.
    if (tree != null &&
        start != null &&
        !widget.exclude.contains(start) &&
        tree.isAccessible(start, ref.read(folderAccessProvider))) {
      _current = start;
    }
  }

  Future<void> _enter(Folder f) async {
    if (!await ensureFolderAccess(context, ref, f.id)) return;
    if (mounted) setState(() => _current = f.id);
  }

  Future<void> _newFolder() async {
    final created = await showNewFolderSheet(context, ref, parentId: _current);
    if (created != null && mounted) setState(() => _current = created.id);
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(folderTreeProvider).value;
    if (tree == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final path = tree.pathTo(_current);
    final children = [
      for (final f in tree.children(_current))
        if (!widget.exclude.contains(f.id)) f,
    ];
    final here = _current == null ? 'ID Vault' : path.last.name;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          ListTile(
            leading: _current == null
                ? const Icon(Icons.shield_outlined)
                : IconButton(
                    tooltip: 'Up one level',
                    icon: const Icon(Icons.arrow_upward_rounded),
                    onPressed: () =>
                        setState(() => _current = path.last.parentId),
                  ),
            title: Text(widget.title, style: context.text.titleMedium),
            subtitle: Text(
              ['ID Vault', ...path.map((f) => f.name)].join(' › '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              children: [
                for (final f in children)
                  ListTile(
                    leading: FolderBadge(folder: f, size: 40),
                    title: Text(f.name),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _enter(f),
                  ),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_rounded),
                  title: const Text('New folder here…'),
                  onTap: _newFolder,
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.drive_file_move_rounded),
                  label: Text('Move to $here'),
                  onPressed: () =>
                      Navigator.pop<FolderPick>(context, (folderId: _current)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
