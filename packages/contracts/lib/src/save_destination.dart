import 'package:docscan_contracts/src/providers.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// "Save to folder": the one destination control every flow that creates
// documents uses (scan, ID card, passport photo, kits, tools, Protect file,
// QR). It lives here because features may not import feature_library.
//
// Locked-folder rule (decided for launch): saving INTO a locked folder is
// allowed without unlocking it. It is write-only: the picker shows folder
// names only (never documents), a locked folder that isn't unlocked this
// session can be chosen but not opened, so the names of its subfolders stay
// hidden, and the saved file is only visible once the folder is unlocked in
// ID Vault. Folders unlocked this session ([unlockedFoldersProvider]) can be
// browsed as usual.

/// Every folder as a tree, live. Empty when folders aren't wired (tests,
/// previews), so a destination control never breaks a save flow.
final saveFolderTreeProvider = StreamProvider<FolderTree>((ref) {
  final FolderRepository folders;
  try {
    folders = ref.watch(folderRepositoryProvider);
  } on Object {
    return Stream.value(FolderTree(const []));
  }
  return folders.watchAllFolders().map(FolderTree.new);
}, retry: (_, _) => null);

/// Locked folders unlocked in this session. Published by feature_library's
/// folder access controller; empty when the library isn't loaded.
final unlockedFoldersProvider = NotifierProvider<UnlockedFolders, Set<String>>(
  UnlockedFolders.new,
);

class UnlockedFolders extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void publish(Set<String> unlocked) => state = Set.unmodifiable(unlocked);
}

/// The destination chosen last in any flow (this session), used as the
/// default when a flow isn't started from a folder.
final lastSaveFolderProvider = NotifierProvider<LastSaveFolder, String?>(
  LastSaveFolder.new,
);

class LastSaveFolder extends Notifier<String?> {
  @override
  String? build() => null;

  void remember(String? folderId) {
    if (state != folderId) state = folderId;
  }
}

/// The destination of one flow (key: a stable flow name such as
/// `'id-card'` or `'tool:merge'`); `null` = the vault's top level.
final saveFolderProvider =
    NotifierProvider.family<SaveFolderChoice, String?, String>(
      SaveFolderChoice.new,
    );

class SaveFolderChoice extends Notifier<String?> {
  SaveFolderChoice(this.flow);

  final String flow;

  @override
  String? build() => ref.read(lastSaveFolderProvider);

  /// Call when the flow opens: the folder it was started from (the folder
  /// "+" menu passes `?folder=`), otherwise the last choice.
  void start(String? startedFrom) =>
      state = startedFrom ?? ref.read(lastSaveFolderProvider);

  /// The user picked a destination; remembered for the next flow.
  void choose(String? folderId) {
    state = folderId;
    ref.read(lastSaveFolderProvider.notifier).remember(folderId);
  }
}

/// [folderId] when that folder still exists, otherwise `null` (top level),
/// so a folder deleted meanwhile never blocks a save. [folders] is only
/// called when a folder was chosen.
Future<String?> existingSaveFolder(
  FolderRepository Function() folders,
  String? folderId,
) async {
  if (folderId == null) return null;
  try {
    final all = await folders().allFolders();
    return all.any((f) => f.id == folderId) ? folderId : null;
  } on Object {
    return null;
  }
}

/// "ID Vault › Family › Passports" (just "ID Vault" for the top level or an
/// unknown folder).
String saveFolderLabel(FolderTree? tree, String? folderId) =>
    ['ID Vault', ...?tree?.pathTo(folderId).map((f) => f.name)].join(' › ');

/// "Saved to ID Vault › Family" for a saved document's folder.
class SavedToFolderText extends ConsumerWidget {
  const SavedToFolderText(
    this.folderId, {
    super.key,
    this.prefix = 'Saved to',
    this.style,
    this.textAlign,
  });

  final String? folderId;
  final String prefix;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(saveFolderTreeProvider).value;
    return Text(
      '$prefix ${saveFolderLabel(tree, folderId)}',
      key: const ValueKey('saved-to-folder'),
      style: style,
      textAlign: textAlign,
    );
  }
}

/// "Save to: ID Vault › Family [Change]". Shows and changes the
/// destination of [flow] (see [saveFolderProvider]).
class SaveFolderField extends ConsumerWidget {
  const SaveFolderField({required this.flow, super.key, this.enabled = true});

  final String flow;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(saveFolderTreeProvider).value;
    final chosen = ref.watch(saveFolderProvider(flow));
    // A folder deleted meanwhile falls back to the top level.
    final id = tree != null && !tree.contains(chosen) ? null : chosen;
    final locked = tree != null && tree.locksOnPath(id).isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    Future<void> change() async {
      final pick = await pickSaveFolder(context, initial: id);
      if (pick != null) {
        ref.read(saveFolderProvider(flow).notifier).choose(pick.folderId);
      }
    }

    return Card(
      key: const ValueKey('save-folder-field'),
      margin: EdgeInsets.zero,
      child: ListTile(
        enabled: enabled,
        leading: Icon(
          id == null
              ? Icons.shield_outlined
              : locked
              ? Icons.lock_rounded
              : Icons.folder_rounded,
          color: scheme.primary,
        ),
        title: const Text('Save to'),
        subtitle: Text(
          locked
              ? '${saveFolderLabel(tree, id)}\nLocked folder: unlock it in ID '
                    'Vault to see the file.'
              : saveFolderLabel(tree, id),
        ),
        isThreeLine: locked,
        trailing: TextButton(
          onPressed: enabled ? change : null,
          child: const Text('Change'),
        ),
        onTap: enabled ? change : null,
      ),
    );
  }
}

/// The folder picked in [pickSaveFolder] (`folderId == null` = top level).
typedef SaveFolderPick = ({String? folderId});

/// Browses the folder tree for a save destination. See the locked-folder
/// rule at the top of this file. Returns null when dismissed.
Future<SaveFolderPick?> pickSaveFolder(
  BuildContext context, {
  String? initial,
  String title = 'Save to folder',
}) => showModalBottomSheet<SaveFolderPick>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _SaveFolderSheet(title: title, initial: initial),
);

class _SaveFolderSheet extends ConsumerStatefulWidget {
  const _SaveFolderSheet({required this.title, required this.initial});

  final String title;
  final String? initial;

  @override
  ConsumerState<_SaveFolderSheet> createState() => _SaveFolderSheetState();
}

class _SaveFolderSheetState extends ConsumerState<_SaveFolderSheet> {
  String? _current;
  var _placed = false;

  /// Starts at [_SaveFolderSheet.initial], or at its nearest ancestor that
  /// may be opened right now.
  void _place(FolderTree tree, Set<String> unlocked) {
    if (_placed) return;
    _placed = true;
    final path = tree.pathTo(widget.initial);
    for (var i = path.length - 1; i >= 0; i--) {
      if (tree.isAccessible(path[i].id, unlocked)) {
        _current = path[i].id;
        return;
      }
    }
  }

  Future<void> _newFolder(FolderTree tree) async {
    final siblings = tree.children(_current).map((f) => f.name).toList();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NewFolderDialog(siblings: siblings),
    );
    if (name == null || !mounted) return;
    final created = await ref
        .read(folderRepositoryProvider)
        .createFolder(name: name, parentId: _current);
    if (!mounted) return;
    switch (created) {
      case Ok(:final value):
        setState(() => _current = value.id);
      case Err(:final failure):
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('${failure.title}. ${failure.recovery}')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(saveFolderTreeProvider).value;
    if (tree == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final unlocked = ref.watch(unlockedFoldersProvider);
    _place(tree, unlocked);
    if (_current != null && !tree.contains(_current)) _current = null;
    final path = tree.pathTo(_current);
    final here = _current == null ? 'ID Vault' : path.last.name;
    final theme = Theme.of(context);
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
            title: Text(widget.title, style: theme.textTheme.titleMedium),
            subtitle: Text(
              saveFolderLabel(tree, _current),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              children: [
                for (final f in tree.children(_current))
                  if (tree.isAccessible(f.id, unlocked))
                    ListTile(
                      leading: Icon(
                        f.isLocked
                            ? Icons.lock_open_rounded
                            : Icons.folder_rounded,
                      ),
                      title: Text(f.name),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => setState(() => _current = f.id),
                    )
                  else
                    // Write-only: chosen directly, never opened from here.
                    ListTile(
                      leading: const Icon(Icons.lock_rounded),
                      title: Text(f.name),
                      subtitle: const Text(
                        'Locked · save here without opening it',
                      ),
                      onTap: () => Navigator.pop<SaveFolderPick>(context, (
                        folderId: f.id,
                      )),
                    ),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_rounded),
                  title: const Text('New folder here…'),
                  onTap: () => _newFolder(tree),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    'Save in $here',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => Navigator.pop<SaveFolderPick>(context, (
                    folderId: _current,
                  )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NewFolderDialog extends StatefulWidget {
  const _NewFolderDialog({required this.siblings});

  final List<String> siblings;

  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<_NewFolderDialog> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final error = FolderNames.validate(_name.text, widget.siblings);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, FolderNames.clean(_name.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New folder'),
    content: TextField(
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      maxLength: FolderNames.maxLength,
      onSubmitted: (_) => _submit(),
      decoration: InputDecoration(labelText: 'Folder name', errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Create')),
    ],
  );
}
