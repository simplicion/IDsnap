import 'dart:io';

import 'package:docscan_data/src/vault/shred.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One place where pickers or the document scanner leave plaintext copies.
class ScratchTarget {
  const ScratchTarget(this.directory, {this.match, this.scanner = false});

  final String directory;

  /// Only direct children whose name matches are removed (files or whole
  /// directories); null = everything inside [directory].
  final bool Function(String name)? match;

  /// Document-scanner output (also swept after each scan).
  final bool scanner;
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

bool _scanFile(String name) => name.startsWith('DOCUMENT_SCAN_');

/// App-owned scratch space outside the vault where plaintext copies of
/// imported sources end up (audit H-07): the ML Kit / VisionKit scanner's
/// output, `image_picker` and `file_picker` copies and IDSnap's own
/// `picked/` folder. Sources inside [roots] are shredded once they have been
/// encrypted into the vault; [sweep] removes leftovers. Nothing outside the
/// app's own cache or app-specific folders is ever touched — a PDF picked
/// straight from Downloads stays where it is.
class PlaintextScratch {
  const PlaintextScratch({this.roots = const [], this.targets = const []});

  /// None (tests, desktop).
  static const none = PlaintextScratch();

  /// Directories whose files belong to the app.
  final List<String> roots;
  final List<ScratchTarget> targets;

  /// True when [path] is an app-owned scratch file.
  bool owns(String path) {
    final full = p.normalize(p.absolute(path));
    return roots.any((r) => p.isWithin(p.normalize(p.absolute(r)), full));
  }

  /// Shreds scratch files last modified before now ([scannerOnly]: only
  /// document-scanner output). Files created while the sweep runs are left
  /// alone. Returns the number of files removed.
  Future<int> sweep({bool scannerOnly = false}) async {
    final cutoff = DateTime.now();
    final victims = <File>[];
    final dirs = <Directory>[];
    for (final t in targets) {
      if (scannerOnly && !t.scanner) continue;
      final dir = Directory(t.directory);
      if (!dir.existsSync()) continue;
      try {
        // Snapshot first, so new picks during the sweep aren't touched.
        for (final e in dir.listSync(followLinks: false)) {
          final name = p.basename(e.path);
          if (t.match != null && !t.match!(name)) continue;
          if (e is File) {
            victims.add(e);
          } else if (e is Directory) {
            dirs.add(e);
            for (final f in e.listSync(recursive: true, followLinks: false)) {
              if (f is File) victims.add(f);
            }
          }
        }
      } on FileSystemException {
        continue;
      }
    }
    var removed = 0;
    for (final f in victims) {
      try {
        if (!f.lastModifiedSync().isBefore(cutoff)) continue;
      } on FileSystemException {
        continue;
      }
      await shredFile(f.path);
      removed++;
    }
    for (final d in dirs.reversed) {
      try {
        if (d.existsSync() &&
            d.listSync(recursive: true).whereType<File>().isEmpty) {
          await d.delete(recursive: true);
        }
      } on FileSystemException {
        // In use or already gone.
      }
    }
    return removed;
  }

  /// The real locations on this phone.
  static Future<PlaintextScratch> platformDefault() async {
    final cache = (await getTemporaryDirectory()).path;
    if (Platform.isAndroid) {
      String? pictures;
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) pictures = p.join(ext.path, 'Pictures');
      } on Object {
        pictures = null;
      }
      return forAndroid(cache: cache, scannerPictures: pictures);
    }
    if (Platform.isIOS) return forIos(caches: cache);
    return none;
  }

  /// Android: `getCacheDir()` and the scanner's app-specific Pictures dir.
  static PlaintextScratch forAndroid({
    required String cache,
    String? scannerPictures,
  }) => PlaintextScratch(
    roots: [cache, ?scannerPictures],
    targets: [
      ScratchTarget(p.join(cache, 'picked')),
      ScratchTarget(p.join(cache, 'file_picker')),
      // image_picker: `<cache>/<uuid>/<name>`, `image_picker*`, `scaled_*`.
      ScratchTarget(
        cache,
        match: (n) =>
            _uuid.hasMatch(n) ||
            n.startsWith('image_picker') ||
            n.startsWith('scaled_'),
      ),
      ScratchTarget(cache, match: _scanFile, scanner: true),
      ScratchTarget(p.join(cache, 'mlkit_docscan_ui_client'), scanner: true),
      if (scannerPictures != null)
        ScratchTarget(scannerPictures, match: _scanFile, scanner: true),
    ],
  );

  /// iOS: `Library/Caches` (scanner output) and the app's `tmp/` (pickers).
  static PlaintextScratch forIos({required String caches}) {
    final container = p.dirname(p.dirname(caches));
    final tmp = p.join(container, 'tmp');
    return PlaintextScratch(
      roots: [caches, tmp],
      targets: [
        ScratchTarget(tmp),
        ScratchTarget(p.join(caches, 'picked')),
        ScratchTarget(
          p.join(caches, 'cunning_document_scanner'),
          scanner: true,
        ),
      ],
    );
  }
}
