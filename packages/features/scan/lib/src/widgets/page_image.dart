import 'dart:typed_data';

import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/src/preview_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PageImageSize { thumb, preview }

/// Shows a page with its edits applied. While the render runs, the original
/// thumbnail is shown so the screen never flashes empty.
class PageImage extends ConsumerStatefulWidget {
  const PageImage({
    required this.page,
    super.key,
    this.size = PageImageSize.preview,
    this.edits,
    this.fit = BoxFit.contain,
  });

  final ScanPage page;
  final PageImageSize size;

  /// Overrides the page's own edits (used by filter swatches).
  final PageEdits? edits;
  final BoxFit fit;

  @override
  ConsumerState<PageImage> createState() => _PageImageState();
}

class _PageImageState extends ConsumerState<PageImage> {
  late Future<Uint8List?> _original;
  late Future<Uint8List?> _rendered;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PageImage old) {
    super.didUpdateWidget(old);
    if (old.page.originalPath != widget.page.originalPath ||
        _edits(old) != _edits(widget) ||
        old.size != widget.size) {
      _load();
    }
  }

  PageEdits _edits(PageImage w) => w.edits ?? w.page.edits;

  void _load() {
    final cache = ref.read(previewCacheProvider);
    final path = widget.page.originalPath;
    _original = cache.originalThumb(path);
    _rendered = widget.size == PageImageSize.thumb
        ? cache.editedThumb(path, _edits(widget))
        : cache.preview(path, _edits(widget));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: _rendered,
    builder: (context, rendered) {
      if (rendered.hasData && rendered.data != null) {
        return Image.memory(
          rendered.data!,
          fit: widget.fit,
          gaplessPlayback: true,
        );
      }
      final done = rendered.connectionState == ConnectionState.done;
      return FutureBuilder<Uint8List?>(
        future: _original,
        builder: (context, original) {
          final bytes = original.data;
          return Stack(
            fit: StackFit.passthrough,
            alignment: Alignment.center,
            children: [
              if (bytes != null)
                Opacity(
                  opacity: done ? 1 : 0.55,
                  child: Image.memory(
                    bytes,
                    fit: widget.fit,
                    gaplessPlayback: true,
                  ),
                )
              else if (original.connectionState == ConnectionState.done || done)
                Icon(
                  Icons.broken_image_outlined,
                  color: context.ds.textSecondary,
                  size: 32,
                )
              else
                const SizedBox.shrink(),
              if (!done && widget.size == PageImageSize.preview)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
            ],
          );
        },
      );
    },
  );
}
