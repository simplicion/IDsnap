import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_library/src/document_actions.dart';
import 'package:feature_library/src/document_tile.dart';
import 'package:feature_library/src/library_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Viewer for one library document with share/rename/move/delete actions and
/// shortcuts into tools.
class DocumentScreen extends ConsumerWidget {
  const DocumentScreen({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(documentByIdProvider(documentId));
    final hidden = ref.watch(pendingDeletesProvider).contains(documentId);
    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: FailureView(
          AppFailure(FailureCode.unknown, cause: e),
          onRetry: () => ref.invalidate(documentByIdProvider(documentId)),
        ),
      ),
      data: (doc) => doc == null || hidden
          ? Scaffold(
              appBar: AppBar(),
              body: const FailureView(AppFailure(FailureCode.notFound)),
            )
          : _DocumentView(doc: doc),
    );
  }
}

class _DocumentView extends ConsumerWidget {
  const _DocumentView({required this.doc});

  final Document doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = DocumentActions(ref);
    return Scaffold(
      appBar: AppBar(
        title: Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: doc.favorite
                ? 'Remove from favorites'
                : 'Add to favorites',
            icon: Icon(
              doc.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
            ),
            color: doc.favorite ? context.colors.tertiary : null,
            onPressed: () => actions.toggleFavorite(context, doc),
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => actions.share(context, [doc]),
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            onSelected: (v) => _onMenu(context, ref, actions, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'save', child: Text('Save to device')),
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'move', child: Text('Move to folder')),
              PopupMenuItem(value: 'details', child: Text('Details')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _Preview(doc: doc)),
          _ToolShortcuts(doc: doc),
        ],
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    DocumentActions actions,
    String value,
  ) async {
    switch (value) {
      case 'save':
        await actions.saveToDevice(context, doc);
      case 'rename':
        await actions.rename(context, doc);
      case 'move':
        await actions.moveToFolder(context, [doc]);
      case 'details':
        await showModalBottomSheet<void>(
          context: context,
          builder: (_) => _DetailsSheet(doc: doc),
        );
      case 'delete':
        final deleted = await actions.delete(context, [doc]);
        if (deleted && context.mounted) context.pop();
    }
  }
}

class _Preview extends ConsumerWidget {
  const _Preview({required this.doc});

  final Document doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(fileStoreProvider).absolute(doc.relativePath);
    if (doc.format == DocumentFormat.pdf) return _PdfPages(path: path);
    if (doc.format.isImage) {
      return InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.file(
            File(path),
            semanticLabel: doc.name,
            errorBuilder: (_, _, _) =>
                const FailureView(AppFailure(FailureCode.corruptFile)),
          ),
        ),
      );
    }
    if (doc.format.isText) return _TextPreview(path: path);
    return _InfoPreview(doc: doc);
  }
}

class _TextPreview extends ConsumerStatefulWidget {
  const _TextPreview({required this.path});

  final String path;

  @override
  ConsumerState<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends ConsumerState<_TextPreview> {
  late final Future<String> _text = ref
      .read(fileStoreProvider)
      .readText(widget.path);

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _text,
    builder: (context, snap) {
      if (snap.hasError) {
        return const FailureView(AppFailure(FailureCode.corruptFile));
      }
      if (!snap.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.gutter),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: SelectableText(snap.data!, style: context.text.bodyLarge),
            ),
          ),
        ),
      );
    },
  );
}

class _InfoPreview extends StatelessWidget {
  const _InfoPreview({required this.doc});

  final Document doc;

  @override
  Widget build(BuildContext context) {
    final v = formatVisual(context, doc.format);
    return EmptyState(
      icon: v.icon,
      title: doc.format.label,
      message:
          "A preview isn't available for this format. You can share it, save it to your device or convert it with Tools.",
    );
  }
}

/// Lazily renders PDF pages one at a time with pinch-zoom.
class _PdfPages extends ConsumerStatefulWidget {
  const _PdfPages({required this.path});

  final String path;

  @override
  ConsumerState<_PdfPages> createState() => _PdfPagesState();
}

class _PdfPagesState extends ConsumerState<_PdfPages> {
  late final Future<Result<int>> _count = ref
      .read(pdfEngineProvider)
      .pageCount(widget.path);
  final Map<int, Future<Result<Uint8List>>> _pages = {};
  int _current = 0;

  Future<Result<Uint8List>> _page(int i, int width) => _pages.putIfAbsent(
    i,
    () => ref
        .read(pdfEngineProvider)
        .renderPage(widget.path, i, targetWidth: width),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<Result<int>>(
    future: _count,
    builder: (context, snap) {
      final result = snap.data;
      if (result == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return result.fold((count) {
        final width =
            (MediaQuery.sizeOf(context).width *
                    MediaQuery.devicePixelRatioOf(context))
                .clamp(600, 1600)
                .round();
        return Stack(
          children: [
            PageView.builder(
              itemCount: count,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) => InteractiveViewer(
                maxScale: 5,
                child: Padding(
                  padding: const EdgeInsets.all(Space.x4),
                  child: FutureBuilder<Result<Uint8List>>(
                    future: _page(i, width),
                    builder: (context, page) {
                      final r = page.data;
                      if (r == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return r.fold(
                        (bytes) => Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: Image.memory(
                              bytes,
                              gaplessPlayback: true,
                              semanticLabel: 'Page ${i + 1} of $count',
                            ),
                          ),
                        ),
                        FailureView.new,
                      );
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: Space.x3,
              left: 0,
              right: 0,
              child: Center(
                child: Pill(
                  'Page ${_current + 1} of $count',
                  color: context.colors.onInverseSurface,
                  background: context.colors.inverseSurface.withValues(
                    alpha: 0.85,
                  ),
                ),
              ),
            ),
          ],
        );
      }, FailureView.new);
    },
  );
}

class _ToolShortcuts extends StatelessWidget {
  const _ToolShortcuts({required this.doc});

  final Document doc;

  @override
  Widget build(BuildContext context) {
    final isPdf = doc.format == DocumentFormat.pdf;
    final chips = <(IconData, String, ToolId)>[
      if (isPdf || doc.format.isImage)
        (Icons.text_snippet_outlined, 'Extract text', ToolId.ocr),
      if (isPdf) (Icons.compress_rounded, 'Compress', ToolId.compressPdf),
      if (doc.format.isImage)
        (Icons.compress_rounded, 'Compress', ToolId.compressImage),
      if (doc.format.isImage)
        (Icons.crop_rounded, 'Crop photo', ToolId.photoCrop),
      if (isPdf)
        (Icons.view_carousel_outlined, 'Organize pages', ToolId.organize),
      if (isPdf) (Icons.call_split_rounded, 'Split', ToolId.split),
      (Icons.swap_horiz_rounded, 'Convert', ToolId.convert),
    ];
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: context.ds.border)),
        ),
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.gutter,
            vertical: Space.x3,
          ),
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.x2),
          itemBuilder: (context, i) {
            final (icon, label, tool) = chips[i];
            return ActionChip(
              avatar: Icon(icon, size: 18),
              label: Text(label),
              onPressed: () =>
                  unawaited(context.push(Routes.tool(tool, docId: doc.id))),
            );
          },
        ),
      ),
    );
  }
}

class _DetailsSheet extends StatelessWidget {
  const _DetailsSheet({required this.doc});

  final Document doc;

  @override
  Widget build(BuildContext context) {
    String date(DateTime d) =>
        '${formatRelativeDate(d)} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final rows = <(String, String)>[
      ('Type', doc.format.label),
      ('Size', formatBytes(doc.sizeBytes)),
      if (doc.pageCount != null) ('Pages', '${doc.pageCount}'),
      ('Created', date(doc.createdAt)),
      ('Modified', date(doc.updatedAt)),
      ('Stored', 'On this device only'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.x6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DocumentThumb(doc, size: 48),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Text(doc.fileName, style: context.text.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: Space.x4),
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        k,
                        style: context.text.bodyMedium?.copyWith(
                          color: context.ds.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(child: Text(v, style: context.text.bodyMedium)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
