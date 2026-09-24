// This cache stores in-flight futures by design; storing them is not a
// discarded future.
// ignore_for_file: discarded_futures

import 'dart:convert';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory LRU of rendered previews, keyed by source image + edits, so
/// swiping between pages or reopening a sheet doesn't re-run the pipeline.
///
/// Thumbnails are rendered from a small copy of the original: edits are
/// stored in normalized coordinates, so the result matches the full render.
class PreviewCache {
  PreviewCache(this._files, this._images, {this.capacity = 48});

  final FileStore _files;
  final ImageProcessor _images;
  final int capacity;
  final _entries = <String, Future<Uint8List?>>{};

  /// Small thumbnail of the untouched original (EXIF orientation applied).
  Future<Uint8List?> originalThumb(String path, {int maxDimension = 480}) =>
      _get('o|$maxDimension|$path', () async {
        final bytes = await _files.read(path);
        return (await _images.thumbnail(
          bytes,
          maxDimension: maxDimension,
        )).valueOrNull;
      });

  /// Thumbnail-sized render with [edits] applied — fast enough for filter
  /// swatches and the page strip.
  Future<Uint8List?> editedThumb(String path, PageEdits edits) =>
      _get('t|${_key(edits)}|$path', () async {
        final small = await originalThumb(path);
        if (small == null) return null;
        final out = await _images.renderPage(
          small,
          edits,
          preset: QualityPreset.small,
        );
        return out.valueOrNull;
      });

  /// Screen-sized preview with [edits] applied.
  Future<Uint8List?> preview(String path, PageEdits edits) =>
      _get('p|${_key(edits)}|$path', () async {
        final bytes = await _files.read(path);
        final out = await _images.renderPage(
          bytes,
          edits,
          preset: QualityPreset.small,
        );
        return out.valueOrNull;
      });

  /// Larger original for the crop editor.
  Future<Uint8List?> cropSource(String path) =>
      originalThumb(path, maxDimension: 1400);

  void evictPath(String path) =>
      _entries.removeWhere((k, _) => k.endsWith('|$path'));

  Future<Uint8List?> _get(String key, Future<Uint8List?> Function() load) {
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit;
      return hit;
    }
    final future = _safely(load);
    _entries[key] = future;
    // Failed renders are not cached so a retry can succeed.
    future.then((v) {
      if (v == null) _entries.remove(key);
    });
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return future;
  }

  static Future<Uint8List?> _safely(Future<Uint8List?> Function() load) async {
    try {
      return await load();
    } on Object {
      return null;
    }
  }

  static String _key(PageEdits e) => jsonEncode(e.toJson());
}

final previewCacheProvider = Provider<PreviewCache>(
  (ref) => PreviewCache(
    ref.watch(fileStoreProvider),
    ref.watch(imageProcessorProvider),
  ),
);
