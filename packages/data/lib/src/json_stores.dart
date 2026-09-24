import 'dart:convert';
import 'dart:io';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:path/path.dart' as p;

/// Writes [content] atomically: temp file, flush, then rename over target.
Future<void> writeAtomically(String path, String content) async {
  await Directory(p.dirname(path)).create(recursive: true);
  final tmp = File('$path.part');
  await tmp.writeAsString(content, flush: true);
  await tmp.rename(path);
}

/// Current scan draft at `<root>/drafts/current.json`.
class JsonDraftStore implements DraftStore {
  JsonDraftStore(this.root);

  final String root;

  String get _path => p.join(root, 'drafts', 'current.json');

  @override
  Future<ScanDraft?> load() async {
    final f = File(_path);
    if (!f.existsSync()) return null;
    try {
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return ScanDraft.fromJson(json);
    } on Object {
      // A corrupt draft must not block the app; start fresh.
      await f.delete();
      return null;
    }
  }

  @override
  Future<void> save(ScanDraft draft) =>
      writeAtomically(_path, jsonEncode(draft.toJson()));

  @override
  Future<void> clear({bool deleteImages = true}) async {
    final draft = await load();
    if (deleteImages && draft != null) {
      for (final page in draft.pages) {
        final f = File(page.originalPath);
        // Only remove images the app owns.
        if (p.isWithin(root, page.originalPath) && f.existsSync()) {
          await f.delete();
        }
      }
    }
    final f = File(_path);
    if (f.existsSync()) await f.delete();
  }
}

/// App settings at `<root>/settings.json`.
class JsonSettingsStore implements SettingsStore {
  JsonSettingsStore(this.root);

  final String root;

  String get _path => p.join(root, 'settings.json');

  @override
  Future<AppSettings> load() async {
    final f = File(_path);
    if (!f.existsSync()) return const AppSettings();
    try {
      return AppSettings.fromJson(
        jsonDecode(await f.readAsString()) as Map<String, dynamic>,
      );
    } on Object {
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) =>
      writeAtomically(_path, jsonEncode(settings.toJson()));
}
