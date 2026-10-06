import 'dart:async';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/providers.dart';
import 'package:feature_tools/src/protect/unlock_inputs.dart' as unlock;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;

/// A file chosen as tool input, from the library or the device.
@immutable
class ToolInput {
  const ToolInput({
    required this.path,
    required this.name,
    required this.format,
    this.sizeBytes,
    this.documentId,
    this.originalFileName,
  });

  /// Absolute, app-readable path.
  final String path;

  /// Display name without extension.
  final String name;
  final DocumentFormat format;
  final int? sizeBytes;

  /// Set when the input came from the library.
  final String? documentId;

  /// The picked file's own name (with its real extension) when the format
  /// is unknown to the app, e.g. `notes.odt` in Protect file.
  final String? originalFileName;

  String get fileLabel =>
      format == DocumentFormat.unknown && originalFileName != null
      ? originalFileName!
      : '$name.${format.extension}';

  /// Library documents are compared by id (each pick decrypts to a new
  /// private copy, ADR-0010); device files by path.
  @override
  bool operator ==(Object other) =>
      other is ToolInput &&
      (documentId != null
          ? other.documentId == documentId
          : other.documentId == null && other.path == path);

  @override
  int get hashCode => documentId?.hashCode ?? path.hashCode;
}

ToolInput inputFromDocument(FileStore files, Document doc) => ToolInput(
  path: files.absolute(doc.relativePath),
  name: doc.name,
  format: doc.format,
  sizeBytes: doc.sizeBytes,
  documentId: doc.id,
);

/// A library document ready for engines that open files by path: vault
/// files are encrypted at rest, so this decrypts a private plaintext copy
/// into the app cache (ADR-0010). Copies are shredded at the next launch or
/// after 30 minutes, whichever comes first.
Future<ToolInput> openDocumentInput(WidgetRef ref, Document doc) async {
  final files = ref.read(fileStoreProvider);
  final plain = await ref
      .read(plainFileAccessProvider)
      .decryptToTemp(files.absolute(doc.relativePath), fileName: doc.fileName);
  return ToolInput(
    path: plain,
    name: doc.name,
    format: doc.format,
    sizeBytes: doc.sizeBytes,
    documentId: doc.id,
  );
}

/// Loads the `?doc=` preselection if its format is accepted.
Future<ToolInput?> inputFromDocId(
  WidgetRef ref,
  String id,
  Set<DocumentFormat> accepts,
) async {
  final doc = await ref.read(documentRepositoryProvider).byId(id);
  if (doc == null || !accepts.contains(doc.format)) return null;
  try {
    return await openDocumentInput(ref, doc);
  } on Object {
    return null;
  }
}

/// Adds the `?doc=` library document to a tool's inputs on first build.
mixin PreselectDocument<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String? get initialDocId;
  Set<DocumentFormat> get acceptedFormats;
  void onPreselected(ToolInput input);

  /// Ask for the password of a protected PDF and use a decrypted copy.
  bool get unlockProtectedPdfs => true;

  @override
  void initState() {
    super.initState();
    final id = initialDocId;
    if (id == null) return;
    unawaited(
      Future<void>.microtask(() async {
        final input = await inputFromDocId(ref, id, acceptedFormats);
        if (input == null || !mounted) return;
        final ready = unlockProtectedPdfs
            ? await unlock.unlockProtectedPdfs(context, ref, [input])
            : [input];
        if (ready.isNotEmpty && mounted) onPreselected(ready.first);
      }),
    );
  }
}

/// Human list of accepted formats: "PDF", "JPEG image or PNG image".
String describeFormats(Set<DocumentFormat> formats) {
  if (formats.every((f) => f.isImage)) return 'images';
  final labels = formats.map((f) => f.extension.toUpperCase()).toList();
  if (labels.length <= 1) return labels.join();
  return '${labels.sublist(0, labels.length - 1).join(', ')} or ${labels.last}';
}

/// Picks and lists tool inputs. Selection lives in the parent.
class InputPicker extends ConsumerWidget {
  const InputPicker({
    required this.accepts,
    required this.inputs,
    required this.onChanged,
    super.key,
    this.multiple = false,
    this.reorderable = false,
    this.title,
    this.anyFile = false,
    this.unlockPdfs = true,
  });

  final Set<DocumentFormat> accepts;
  final List<ToolInput> inputs;
  final ValueChanged<List<ToolInput>> onChanged;
  final bool multiple;
  final bool reorderable;
  final String? title;

  /// Device picks accept any file type (Protect file).
  final bool anyFile;

  /// Password-protected PDFs prompt for their password and are replaced by
  /// a decrypted temp copy (see `unlockProtectedPdfs`).
  final bool unlockPdfs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = anyFile ? 'files' : describeFormats(accepts);
    final heading =
        title ??
        (multiple
            ? 'Choose $kind'
            : 'Choose ${kind == 'images' ? 'an image' : 'a $kind file'}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(heading, style: context.text.titleSmall),
        const SizedBox(height: Space.x2),
        if (inputs.isEmpty)
          _EmptyPick(kind: kind)
        else if (reorderable && inputs.length > 1)
          _reorderableList(context)
        else
          for (final (i, input) in inputs.indexed)
            _InputRow(
              key: ValueKey(input.path),
              input: input,
              index: multiple ? i : null,
              onRemove: () => onChanged([...inputs]..removeAt(i)),
            ),
        const SizedBox(height: Space.x3),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickFromLibrary(context, ref),
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('From library'),
              ),
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => _pickFromDevice(context, ref),
                icon: Icon(
                  accepts.every((f) => f.isImage)
                      ? Icons.photo_library_rounded
                      : Icons.upload_file_rounded,
                ),
                label: Text(
                  !multiple && inputs.isNotEmpty ? 'Replace' : 'From device',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _reorderableList(BuildContext context) => ReorderableListView(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    buildDefaultDragHandles: false,
    onReorderItem: (from, to) {
      final list = [...inputs];
      final item = list.removeAt(from);
      list.insert(to, item);
      onChanged(list);
    },
    children: [
      for (final (i, input) in inputs.indexed)
        _InputRow(
          key: ValueKey(input.path),
          input: input,
          index: i,
          dragIndex: i,
          onRemove: () => onChanged([...inputs]..removeAt(i)),
        ),
    ],
  );

  Future<void> _addUnlocked(
    BuildContext context,
    WidgetRef ref,
    List<ToolInput> picked,
  ) async {
    final ready = unlockPdfs && context.mounted
        ? await unlock.unlockProtectedPdfs(context, ref, picked)
        : picked;
    _add(ready);
  }

  void _add(List<ToolInput> picked) {
    if (picked.isEmpty) return;
    if (!multiple) {
      onChanged([picked.first]);
      return;
    }
    final merged = [...inputs];
    for (final p in picked) {
      if (!merged.contains(p)) merged.add(p);
    }
    onChanged(merged);
  }

  Future<void> _pickFromDevice(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(mediaPickerProvider);
    final files = ref.read(fileStoreProvider);
    final result = anyFile
        ? await picker.pickFiles({DocumentFormat.unknown}, multiple: multiple)
        : accepts.every((f) => f.isImage)
        ? await picker.pickImages(multiple: multiple)
        : await picker.pickFiles(accepts, multiple: multiple);
    if (!context.mounted) return;
    if (result case Err(:final failure)) {
      if (failure.code != FailureCode.captureCancelled) {
        showFailureSnack(context, failure);
      }
      return;
    }
    final picked = <ToolInput>[];
    var rejected = 0;
    for (final f in result.valueOrNull!) {
      var format = DocumentFormat.fromExtension(f.name);
      if (format == DocumentFormat.unknown && accepts.length == 1) {
        format = accepts.first;
      }
      if (!anyFile && !accepts.contains(format)) {
        rejected++;
        continue;
      }
      int? size;
      try {
        size = await files.size(f.path);
      } on Object {
        size = null;
      }
      picked.add(
        ToolInput(
          path: f.path,
          name: f.baseName,
          format: format,
          sizeBytes: size,
          originalFileName: f.name,
        ),
      );
    }
    if (!context.mounted) return;
    if (rejected > 0) {
      showAppSnack(
        context,
        rejected == 1
            ? "That file type isn't supported here. Choose $kindLabel."
            : "$rejected files aren't supported here. Choose $kindLabel.",
      );
    }
    await _addUnlocked(context, ref, picked);
  }

  String get kindLabel => describeFormats(accepts);

  Future<void> _pickFromLibrary(BuildContext context, WidgetRef ref) async {
    final docs = await showModalBottomSheet<List<Document>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LibrarySheet(accepts: accepts, multiple: multiple),
    );
    if (docs == null || docs.isEmpty) return;
    final List<ToolInput> picked;
    try {
      picked = [for (final d in docs) await openDocumentInput(ref, d)];
    } on Object catch (e, st) {
      if (context.mounted) {
        showFailureSnack(
          context,
          AppFailure(FailureCode.corruptFile, cause: e, stackTrace: st),
        );
      }
      return;
    }
    if (!context.mounted) return;
    await _addUnlocked(context, ref, picked);
  }
}

class _EmptyPick extends StatelessWidget {
  const _EmptyPick({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.x5),
    decoration: BoxDecoration(
      borderRadius: Radii.cardAll,
      border: Border.all(color: context.ds.border, width: 1.5),
      color: context.colors.surface,
    ),
    child: Row(
      children: [
        Icon(Icons.note_add_outlined, color: context.ds.textSecondary),
        const SizedBox(width: Space.x3),
        Expanded(
          child: Text(
            'Nothing selected yet. Pick $kind from your library or device.',
            style: context.text.bodyMedium?.copyWith(
              color: context.ds.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.input,
    required this.onRemove,
    super.key,
    this.index,
    this.dragIndex,
  });

  final ToolInput input;
  final VoidCallback onRemove;
  final int? index;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final size = input.sizeBytes;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x2),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.x2),
          child: Row(
            children: [
              InputThumb(input: input),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      index == null
                          ? input.fileLabel
                          : '${index! + 1}. ${input.fileLabel}',
                      style: context.text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      [
                        input.format.label,
                        if (size != null) formatBytes(size),
                      ].join(' · '),
                      style: context.text.bodySmall?.copyWith(
                        color: context.ds.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove ${input.fileLabel}',
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
              if (dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex!,
                  child: Semantics(
                    label: 'Drag to reorder',
                    child: const Padding(
                      padding: EdgeInsets.all(Space.x3),
                      child: Icon(Icons.drag_handle_rounded),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thumbnail for an input: image preview, first PDF page, or a format icon.
class InputThumb extends StatelessWidget {
  const InputThumb({required this.input, super.key, this.size = 48});

  final ToolInput input;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (input.format.isImage) {
      child = ImageThumb(path: input.path, size: size);
    } else if (input.format == DocumentFormat.pdf) {
      child = PdfPageThumb(path: input.path, index: 0, size: size);
    } else {
      child = _FormatIcon(format: input.format, size: size);
    }
    return ClipRRect(borderRadius: Radii.smAll, child: child);
  }
}

/// A library document's own (encrypted) thumbnail, decrypted in memory;
/// the generic input thumbnail when it has none.
class _LibraryThumb extends ConsumerWidget {
  const _LibraryThumb({required this.doc, required this.files});

  static const size = 44.0;

  final Document doc;
  final FileStore files;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumb = doc.thumbnailPath;
    // Vault files are encrypted at rest: a PDF without a stored thumbnail
    // is rendered from a short-lived decrypted copy, never from the
    // ciphertext path (audit L-11).
    final fallback = doc.format == DocumentFormat.pdf
        ? _VaultPdfThumb(path: files.absolute(doc.relativePath), size: size)
        : InputThumb(input: inputFromDocument(files, doc), size: size);
    if (thumb == null) return fallback;
    final bytes = ref.watch(vaultImageBytesProvider(thumb)).value;
    if (bytes == null) return fallback;
    return ClipRRect(
      borderRadius: Radii.smAll,
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}

/// First page of an encrypted vault PDF: decrypts a private copy, renders
/// it and shreds the copy straight away.
final FutureProviderFamily<Uint8List, String> vaultPdfThumbProvider =
    FutureProvider.autoDispose.family<Uint8List, String>((ref, path) async {
      final plain = ref.watch(plainFileAccessProvider);
      final pdf = ref.watch(pdfEngineProvider);
      final copy = await plain.decryptToTemp(path);
      try {
        final png = await pdf.renderPage(copy, 0, targetWidth: 320);
        return switch (png) {
          Ok(:final value) => value,
          Err(:final failure) => throw failure,
        };
      } finally {
        // A no-op when the file wasn't encrypted (copy == path).
        await plain.releaseTemp(copy);
      }
    }, retry: noRetry);

class _VaultPdfThumb extends ConsumerWidget {
  const _VaultPdfThumb({required this.path, required this.size});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ClipRRect(
    borderRadius: Radii.smAll,
    child: SizedBox.square(
      dimension: size,
      child: switch (ref.watch(vaultPdfThumbProvider(path))) {
        AsyncData(:final value) => ColoredBox(
          color: Colors.white,
          child: Image.memory(value, fit: BoxFit.cover, gaplessPlayback: true),
        ),
        AsyncError() => _FormatIcon(format: DocumentFormat.pdf, size: size),
        _ => ColoredBox(color: context.colors.surfaceContainerHigh),
      },
    ),
  );
}

class _FormatIcon extends StatelessWidget {
  const _FormatIcon({required this.format, required this.size});

  final DocumentFormat format;
  final double size;

  @override
  Widget build(BuildContext context) {
    final v = formatVisual(context, format);
    return IconBadge(v.icon, color: v.color, size: size);
  }
}

class ImageThumb extends ConsumerWidget {
  const ImageThumb({required this.path, super.key, this.size = 48});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(fileBytesProvider(path));
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox.square(
      dimension: size,
      child: switch (bytes) {
        AsyncData(:final value) => Image.memory(
          value,
          fit: BoxFit.cover,
          cacheWidth: (size * dpr).round(),
          gaplessPlayback: true,
          errorBuilder: (context, _, _) =>
              _FormatIcon(format: DocumentFormat.jpeg, size: size),
        ),
        AsyncError() => _FormatIcon(format: DocumentFormat.jpeg, size: size),
        _ => ColoredBox(color: context.colors.surfaceContainerHigh),
      },
    );
  }
}

class PdfPageThumb extends ConsumerWidget {
  const PdfPageThumb({
    required this.path,
    required this.index,
    super.key,
    this.size = 48,
    this.fit = BoxFit.cover,
  });

  final String path;
  final int index;
  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(pdfThumbProvider((path, index)));
    return SizedBox.square(
      dimension: size,
      child: switch (bytes) {
        AsyncData(:final value) => ColoredBox(
          color: Colors.white,
          child: Image.memory(value, fit: fit, gaplessPlayback: true),
        ),
        AsyncError() => _FormatIcon(format: DocumentFormat.pdf, size: size),
        _ => ColoredBox(color: context.colors.surfaceContainerHigh),
      },
    );
  }
}

class _LibrarySheet extends ConsumerStatefulWidget {
  const _LibrarySheet({required this.accepts, required this.multiple});

  final Set<DocumentFormat> accepts;
  final bool multiple;

  @override
  ConsumerState<_LibrarySheet> createState() => _LibrarySheetState();
}

class _LibrarySheetState extends ConsumerState<_LibrarySheet> {
  final _selected = <Document>[];

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(documentsProvider(const DocumentQuery()));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              0,
              Space.gutter,
              Space.x2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose from library',
                    style: context.text.titleLarge,
                  ),
                ),
                if (widget.multiple)
                  FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, _selected),
                    child: Text(
                      _selected.isEmpty ? 'Add' : 'Add ${_selected.length}',
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (docs) {
              AsyncData(:final value) => _list(
                controller,
                value.where((d) => widget.accepts.contains(d.format)).toList(),
              ),
              AsyncError(:final error) => FailureView(
                error is AppFailure
                    ? error
                    : const AppFailure(
                        FailureCode.unknown,
                        message:
                            "Your library couldn't be loaded. Close this "
                            'sheet and try again, or pick the file from your '
                            'device instead.',
                      ),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }

  Widget _list(ScrollController controller, List<Document> docs) {
    if (docs.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_rounded,
        title: 'No matching files',
        message:
            'Your library has no ${describeFormats(widget.accepts)} yet. '
            'Pick from your device instead.',
      );
    }
    final files = ref.read(fileStoreProvider);
    return ListView.builder(
      controller: controller,
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final d = docs[i];
        final selected = _selected.contains(d);
        final subtitle = [
          formatBytes(d.sizeBytes),
          if (d.pageCount != null)
            '${d.pageCount} page${d.pageCount == 1 ? '' : 's'}',
          formatRelativeDate(d.updatedAt),
        ].join(' · ');
        return ListTile(
          leading: _LibraryThumb(doc: d, files: files),
          title: Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle),
          trailing: widget.multiple
              ? Checkbox(value: selected, onChanged: (_) => _toggle(d))
              : null,
          selected: selected,
          onTap: () =>
              widget.multiple ? _toggle(d) : Navigator.pop(context, [d]),
        );
      },
    );
  }

  void _toggle(Document d) => setState(
    () => _selected.contains(d) ? _selected.remove(d) : _selected.add(d),
  );
}
