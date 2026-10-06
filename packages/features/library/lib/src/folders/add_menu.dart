import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_library/src/folders/folder_providers.dart';
import 'package:feature_library/src/folders/folder_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What "Upload files" accepts: every format the viewer and tools handle.
/// HEIC is left out (the app can't display it; the error says to export as
/// JPG), as are ZIPs (backups go through Settings › Data).
const uploadFormats = <DocumentFormat>{
  DocumentFormat.pdf,
  DocumentFormat.jpeg,
  DocumentFormat.png,
  DocumentFormat.webp,
  DocumentFormat.gif,
  DocumentFormat.bmp,
  DocumentFormat.tiff,
  DocumentFormat.docx,
  DocumentFormat.xlsx,
  DocumentFormat.pptx,
  DocumentFormat.txt,
  DocumentFormat.markdown,
  DocumentFormat.html,
  DocumentFormat.csv,
};

/// Largest single upload (files are read into memory to validate them).
const maxUploadBytes = 200 * 1024 * 1024;

enum _AddAction { folder, upload, scan, idCard, passportPhoto }

/// The "+" menu of the vault and of every folder. Everything created from
/// it is saved into [folderId] by default (`null` = top level).
Future<void> showAddMenu(
  BuildContext context,
  WidgetRef ref, {
  required String? folderId,
}) async {
  final here = folderId == null ? 'ID Vault' : 'this folder';
  final action = await showModalBottomSheet<_AddAction>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_rounded),
              title: const Text('New folder'),
              subtitle: const Text('Pick a suggestion or name your own'),
              onTap: () => Navigator.pop(context, _AddAction.folder),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_rounded),
              title: const Text('Upload files'),
              subtitle: const Text('PDFs, photos, documents from this phone'),
              onTap: () => Navigator.pop(context, _AddAction.upload),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_rounded),
              title: const Text('Scan document'),
              subtitle: Text('Use the camera; saved into $here'),
              trailing: const ProBadge(ProFeature.scan),
              onTap: () => Navigator.pop(context, _AddAction.scan),
            ),
            ListTile(
              leading: const Icon(Icons.badge_rounded),
              title: const Text('ID card (front & back)'),
              subtitle: Text('Both sides on one page; saved into $here'),
              trailing: const ProBadge(ProFeature.idCard),
              onTap: () => Navigator.pop(context, _AddAction.idCard),
            ),
            ListTile(
              leading: const Icon(Icons.portrait_rounded),
              title: const Text('Passport-size photo'),
              subtitle: Text('Photo or print sheet; saved into $here'),
              trailing: const ProBadge(ProFeature.passportPhoto),
              onTap: () => Navigator.pop(context, _AddAction.passportPhoto),
            ),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _AddAction.folder:
      await showNewFolderSheet(context, ref, parentId: folderId);
    case _AddAction.upload:
      await uploadIntoFolder(context, ref, folderId: folderId);
    case _AddAction.scan:
      await pushIfPro(
        context,
        ref,
        ProFeature.scan,
        Routes.scan(folderId: folderId),
      );
    case _AddAction.idCard:
      await pushIfPro(
        context,
        ref,
        ProFeature.idCard,
        Routes.idCard(folderId: folderId),
      );
    case _AddAction.passportPhoto:
      await pushIfPro(
        context,
        ref,
        ProFeature.passportPhoto,
        Routes.passportPhoto(folderId: folderId),
      );
  }
}

/// A suggestion in the new-folder sheet.
class _Suggestion {
  const _Suggestion(this.name, {this.template});

  final String name;
  final FolderTemplate? template;
}

/// Template suggestions (plus the parent template's suggested subfolders)
/// and "Custom…". Creates the chosen folder under [parentId].
Future<Folder?> showNewFolderSheet(
  BuildContext context,
  WidgetRef ref, {
  required String? parentId,
}) async {
  final tree = await ref.read(folderTreeProvider.future);
  if (!context.mounted) return null;
  final siblings = tree.children(parentId).map((f) => f.name).toList();
  final parentTemplate = FolderTemplate.byKey(tree[parentId]?.templateKey);
  final choice = await showModalBottomSheet<_Suggestion>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _NewFolderSheet(
      siblings: siblings,
      subfolders: parentTemplate?.subfolders ?? const [],
      parentName: tree[parentId]?.name,
    ),
  );
  if (choice == null || !context.mounted) return null;
  var name = choice.name;
  if (name.isEmpty) {
    final custom = await promptFolderName(
      context,
      title: 'New folder',
      confirmLabel: 'Create',
      siblings: siblings,
    );
    if (custom == null || !context.mounted) return null;
    name = custom;
  }
  final t = choice.template;
  final result = await ref
      .read(folderRepositoryProvider)
      .createFolder(
        name: name,
        parentId: parentId,
        templateKey: t?.key,
        icon: t?.icon,
        color: t?.color,
      );
  if (!context.mounted) return result.valueOrNull;
  result.fold(
    (f) => showAppSnack(context, 'Folder "${f.name}" created'),
    (f) => showFailureSnack(context, f),
  );
  return result.valueOrNull;
}

class _NewFolderSheet extends StatelessWidget {
  const _NewFolderSheet({
    required this.siblings,
    required this.subfolders,
    required this.parentName,
  });

  final List<String> siblings;
  final List<String> subfolders;
  final String? parentName;

  bool _taken(String name) =>
      siblings.any((s) => s.toLowerCase() == name.toLowerCase());

  @override
  Widget build(BuildContext context) {
    Widget tile(
      _Suggestion s, {
      required IconData icon,
      required Color color,
      String? hint,
    }) {
      final taken = _taken(s.name);
      return ListTile(
        enabled: !taken,
        leading: IconBadge(icon, color: color, size: 40),
        title: Text(s.name),
        subtitle: taken
            ? const Text('Already here')
            : hint == null
            ? null
            : Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => Navigator.pop(context, s),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.x4,
              Space.gutter,
              Space.x2,
            ),
            child: Text(
              parentName == null ? 'New folder' : 'New folder in $parentName',
              style: context.text.titleMedium,
            ),
          ),
          ListTile(
            leading: IconBadge(
              Icons.edit_rounded,
              color: context.colors.primary,
              size: 40,
            ),
            title: const Text('Custom…'),
            subtitle: const Text('Type your own folder name'),
            onTap: () => Navigator.pop(context, const _Suggestion('')),
          ),
          if (subfolders.isNotEmpty) ...[
            SectionHeader('Suggested for ${parentName ?? 'this folder'}'),
            for (final name in subfolders)
              tile(
                _Suggestion(name),
                icon: Icons.folder_rounded,
                color: context.colors.primary,
              ),
          ],
          const SectionHeader('Suggestions'),
          for (final t in FolderTemplate.all)
            tile(
              _Suggestion(t.label, template: t),
              icon: folderIconData(t.icon),
              color: folderColor(context, t.color),
              hint: t.hint,
            ),
          const SizedBox(height: Space.x4),
        ],
      ),
    );
  }
}

/// Folder name dialog with inline validation (non-empty, max length, no
/// duplicate among [siblings]).
Future<String?> promptFolderName(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required List<String> siblings,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _FolderNameDialog(
    title: title,
    confirmLabel: confirmLabel,
    siblings: siblings,
    initial: initial,
  ),
);

class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.siblings,
    required this.initial,
  });

  final String title;
  final String confirmLabel;
  final List<String> siblings;
  final String initial;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  String? _error;
  bool _touched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate() {
    final name = FolderNames.clean(_controller.text);
    // Renaming to the same name (or a case change) is allowed.
    final others = [
      for (final s in widget.siblings)
        if (s.toLowerCase() != widget.initial.toLowerCase() ||
            widget.initial.isEmpty)
          s,
    ];
    if (widget.initial.isNotEmpty && name == widget.initial) return null;
    return FolderNames.validate(name, others);
  }

  void _submit() {
    final error = _validate();
    setState(() {
      _touched = true;
      _error = error;
    });
    if (error == null) {
      Navigator.pop(context, FolderNames.clean(_controller.text));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('folder-name'),
      controller: _controller,
      autofocus: true,
      maxLength: FolderNames.maxLength,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(hintText: 'Folder name', errorText: _error),
      textInputAction: TextInputAction.done,
      onChanged: (_) {
        if (_touched) setState(() => _error = _validate());
      },
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
    ],
  );
}

/// Picks files with the system picker and imports each into [folderId]
/// through [CommitOutput] (validated, committed atomically, thumbnailed).
Future<void> uploadIntoFolder(
  BuildContext context,
  WidgetRef ref, {
  required String? folderId,
}) async {
  final access = ref.read(folderAccessProvider.notifier);
  final picked = await access.whileExternal(
    () =>
        ref.read(mediaPickerProvider).pickFiles(uploadFormats, multiple: true),
  );
  if (!context.mounted) return;
  final files = switch (picked) {
    Ok(:final value) => value,
    Err(:final failure) => () {
      if (failure.code != FailureCode.captureCancelled) {
        showFailureSnack(context, failure);
      }
      return const <PickedFile>[];
    }(),
  };
  if (files.isEmpty) return;

  final progress = ValueNotifier<int>(0);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (context, done, _) => Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: Space.x4),
                Expanded(child: Text('Adding ${done + 1} of ${files.length}…')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  final report = await importFiles(
    ref,
    files,
    folderId: folderId,
    onFile: (i) {
      progress.value = i;
    },
  );
  progress.dispose();
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  final (:added, :failures) = report;
  if (failures.isEmpty) {
    showAppSnack(context, added == 1 ? 'File added' : '$added files added');
  } else if (added == 0 && failures.length == 1) {
    showFailureSnack(context, failures.single);
  } else {
    final first = failures.first;
    showAppSnack(
      context,
      '$added added, ${failures.length} not added. ${first.title}. '
      '${first.recovery}',
    );
  }
}

/// Imports [files] into [folderId]; returns how many were added and why the
/// others weren't. Exposed for tests.
Future<({int added, List<AppFailure> failures})> importFiles(
  WidgetRef ref,
  List<PickedFile> files, {
  required String? folderId,
  void Function(int index)? onFile,
}) async {
  final store = ref.read(fileStoreProvider);
  final commit = ref.read(commitOutputProvider);
  var added = 0;
  final failures = <AppFailure>[];
  for (final (i, f) in files.indexed) {
    onFile?.call(i);
    try {
      final size = await store.size(f.path);
      if (size == 0) {
        failures.add(const AppFailure(FailureCode.emptyFile));
        continue;
      }
      if (size > maxUploadBytes) {
        failures.add(
          const AppFailure(
            FailureCode.memoryLimitExceeded,
            message: 'Files up to 200 MB can be added.',
            action: FailureAction.pickDifferentFile,
          ),
        );
        continue;
      }
      final bytes = await store.read(f.path);
      final format = DocumentFormat.sniff(
        bytes.length > 64 ? bytes.sublist(0, 64) : bytes,
        nameHint: f.name,
      );
      if (!uploadFormats.contains(format)) {
        failures.add(
          AppFailure(
            FailureCode.unsupportedFormat,
            message: format == DocumentFormat.heic
                ? 'HEIC photos: export as JPG first, then add them.'
                : 'Choose a PDF, image, Office or text file.',
          ),
        );
        continue;
      }
      final result = await commit(
        OutputFile(
          bytes: bytes,
          format: format,
          suggestedName: f.baseName,
          // A password-protected PDF is kept as it is; the viewer asks for
          // its password.
          passwordProtected:
              format == DocumentFormat.pdf && await _needsPassword(ref, f.path),
        ),
        folderId: folderId,
      );
      switch (result) {
        case Ok():
          added++;
          // The vault now holds an encrypted copy: don't leave the picker's
          // plaintext copy in the cache (audit H-07).
          await ref.read(importedSourceDisposerProvider)(f.path);
        case Err(:final failure):
          failures.add(failure);
      }
    } on Object catch (e, st) {
      failures.add(AppFailure(FailureCode.notFound, cause: e, stackTrace: st));
    }
  }
  return (added: added, failures: failures);
}

/// Whether the picked PDF at [path] needs a password to open; false when it
/// can't be checked (the commit then validates it as a normal PDF).
Future<bool> _needsPassword(WidgetRef ref, String path) async {
  try {
    return (await ref.read(pdfProtectorProvider).needsPassword(path))
            .valueOrNull ??
        false;
  } on Object {
    return false;
  }
}
