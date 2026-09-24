// Copies /docs (markdown + manifest.json) into apps/docs/assets/docs so the
// documentation app can bundle them. Run from the repo root:
//
//   dart run tool/sync_docs.dart
//
// Exits non-zero if the manifest references a missing page or if a docs
// subfolder isn't declared as an asset directory in apps/docs/pubspec.yaml.
import 'dart:convert';
import 'dart:io';

void main() {
  final root = _repoRoot();
  final source = Directory('${root.path}/docs');
  final target = Directory('${root.path}/apps/docs/assets/docs');
  if (!source.existsSync()) _fail('No docs/ folder at ${source.path}');

  if (target.existsSync()) target.deleteSync(recursive: true);
  target.createSync(recursive: true);

  final copied = <String>[];
  final folders = <String>{''};
  for (final entity in source.listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = _relative(entity.path, source.path);
    if (!rel.endsWith('.md') && rel != 'manifest.json') continue;
    final dest = File('${target.path}/$rel')
      ..parent.createSync(recursive: true);
    entity.copySync(dest.path);
    copied.add(rel);
    final slash = rel.lastIndexOf('/');
    if (slash > 0) folders.add(rel.substring(0, slash));
  }
  copied.sort();

  // Every manifest page must exist.
  final manifestFile = File('${source.path}/manifest.json');
  if (!manifestFile.existsSync()) _fail('docs/manifest.json is missing');
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  final missing = <String>[
    for (final s in manifest['sections'] as List<dynamic>)
      for (final p in (s as Map<String, dynamic>)['pages'] as List<dynamic>)
        if (!copied.contains((p as Map<String, dynamic>)['path']))
          p['path'] as String,
  ];
  if (missing.isNotEmpty) {
    _fail('manifest.json references missing pages: $missing');
  }

  // Flutter needs every asset subdirectory listed explicitly.
  final declared = File('${root.path}/apps/docs/pubspec.yaml')
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.startsWith('- assets/'))
      .map((l) => l.substring(2).trim())
      .toSet();
  final undeclared = [
    for (final f in folders)
      if (!declared.contains('assets/docs/${f.isEmpty ? '' : '$f/'}'))
        'assets/docs/${f.isEmpty ? '' : '$f/'}',
  ];
  if (undeclared.isNotEmpty) {
    _fail('Add these asset folders to apps/docs/pubspec.yaml: $undeclared');
  }

  File(
    '${target.path}/files.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(copied));
  stdout.writeln(
    'Synced ${copied.length} files into ${_relative(target.path, root.path)}',
  );
}

Directory _repoRoot() {
  var dir = Directory.current.absolute;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        Directory('${dir.path}/docs').existsSync() &&
        Directory('${dir.path}/apps').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) _fail('Run this from inside the repository');
    dir = parent;
  }
}

String _relative(String path, String base) =>
    path.substring(base.length + 1).replaceAll(r'\', '/');

Never _fail(String message) {
  stderr.writeln('sync_docs: $message');
  exit(1);
}
