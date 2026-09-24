import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file chosen as tool input, from the library or the device.
@immutable
class ToolInput {
  const ToolInput({
    required this.path,
    required this.name,
    required this.format,
    this.sizeBytes,
    this.documentId,
  });

  /// Absolute, app-readable path.
  final String path;

  /// Display name without extension.
  final String name;
  final DocumentFormat format;
  final int? sizeBytes;

  /// Set when the input came from the library.
  final String? documentId;

  String get fileLabel => '$name.${format.extension}';

  @override
  bool operator ==(Object other) => other is ToolInput && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

ToolInput inputFromDocument(FileStore files, Document doc) => ToolInput(
  path: files.absolute(doc.relativePath),
  name: doc.name,
  format: doc.format,
  sizeBytes: doc.sizeBytes,
  documentId: doc.id,
);

/// Loads the `?doc=` preselection if its format is accepted.
Future<ToolInput?> inputFromDocId(
  WidgetRef ref,
  String id,
  Set<DocumentFormat> accepts,
) async {
  final doc = await ref.read(documentRepositoryProvider).byId(id);
  if (doc == null || !accepts.contains(doc.format)) return null;
  return inputFromDocument(ref.read(fileStoreProvider), doc);
}

/// Adds the `?doc=` library document to a tool's inputs on first build.
mixin PreselectDocument<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  String? get initialDocId;
  Set<DocumentFormat> get acceptedFormats;
  void onPreselected(ToolInput input);

  @override
  void initState() {
    super.initState();
    final id = initialDocId;
    if (id == null) return;
    unawaited(
      Future<void>.microtask(() async {
        final input = await inputFromDocId(ref, id, acceptedFormats);
        if (input != null && mounted) onPreselected(input);
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
  });

  final Set<DocumentFormat> accepts;
  final List<ToolInput> inputs;
  final ValueChanged<List<ToolInput>> onChanged;
  final bool multiple;
  final bool reorderable;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = describeFormats(accepts);
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
    final result = accepts.every((f) => f.isImage)
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
      if (!accepts.contains(format)) {
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
    _add(picked);
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
    final files = ref.read(fileStoreProvider);
    _add([for (final d in docs) inputFromDocument(files, d)]);
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
                    : const AppFailure(FailureCode.unknown),
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
          leading: InputThumb(input: inputFromDocument(files, d), size: 44),
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
