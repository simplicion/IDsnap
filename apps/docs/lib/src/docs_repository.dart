import 'dart:convert';

import 'package:flutter/services.dart';

/// One page entry from `manifest.json`.
class DocPage {
  const DocPage({
    required this.title,
    required this.path,
    required this.section,
  });

  final String title;

  /// Path relative to the docs root, e.g. `product/PRD.md`.
  final String path;
  final String section;

  /// Router location: `/product/PRD`, or `/` for `index.md`.
  String get location => pathToLocation(path);
}

class DocSection {
  const DocSection({required this.title, required this.pages});

  final String title;
  final List<DocPage> pages;
}

class DocsManifest {
  const DocsManifest({required this.title, required this.sections});

  factory DocsManifest.fromJson(Map<String, dynamic> json) {
    final sections = <DocSection>[];
    for (final s in json['sections'] as List<dynamic>) {
      final section = s as Map<String, dynamic>;
      final title = section['title'] as String;
      sections.add(
        DocSection(
          title: title,
          pages: [
            for (final p in section['pages'] as List<dynamic>)
              DocPage(
                title: (p as Map<String, dynamic>)['title'] as String,
                path: p['path'] as String,
                section: title,
              ),
          ],
        ),
      );
    }
    return DocsManifest(
      title: json['title'] as String? ?? 'Docs',
      sections: sections,
    );
  }

  final String title;
  final List<DocSection> sections;

  List<DocPage> get pages => [for (final s in sections) ...s.pages];

  DocPage? byPath(String path) {
    for (final p in pages) {
      if (p.path == path) return p;
    }
    return null;
  }
}

/// A search hit: the page plus a short snippet around the first match.
class SearchHit {
  const SearchHit(this.page, this.snippet, {required this.titleMatch});

  final DocPage page;
  final String snippet;
  final bool titleMatch;
}

/// Loads the docs copied into `assets/docs/` by `tool/sync_docs.dart`.
class DocsRepository {
  DocsRepository({AssetBundle? bundle, this.root = 'assets/docs'})
    : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final String root;
  final Map<String, String> _cache = {};
  DocsManifest? _manifest;

  Future<DocsManifest> manifest() async {
    final cached = _manifest;
    if (cached != null) return cached;
    final raw = await _bundle.loadString('$root/manifest.json');
    return _manifest = DocsManifest.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  Future<String> page(String path) async {
    final cached = _cache[path];
    if (cached != null) return cached;
    final text = await _bundle.loadString('$root/$path', cache: false);
    return _cache[path] = text;
  }

  /// Case-insensitive search over titles and page bodies. Title hits first.
  Future<List<SearchHit>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final m = await manifest();
    final hits = <SearchHit>[];
    for (final p in m.pages) {
      final titleMatch = p.title.toLowerCase().contains(q);
      String body;
      try {
        body = await page(p.path);
      } on Object {
        continue;
      }
      final idx = body.toLowerCase().indexOf(q);
      if (!titleMatch && idx < 0) continue;
      hits.add(
        SearchHit(
          p,
          idx < 0 ? p.section : snippetAround(body, idx, q.length),
          titleMatch: titleMatch,
        ),
      );
    }
    hits.sort((a, b) => (b.titleMatch ? 1 : 0) - (a.titleMatch ? 1 : 0));
    return hits;
  }
}

String snippetAround(String body, int index, int length) {
  final start = (index - 50).clamp(0, body.length);
  final end = (index + length + 70).clamp(0, body.length);
  final text = body
      .substring(start, end)
      .replaceAll(RegExp(r'[\s#*|`>_\-]+'), ' ')
      .trim();
  return '${start > 0 ? '…' : ''}$text${end < body.length ? '…' : ''}';
}

/// `product/PRD.md` → `/product/PRD`; `index.md` → `/`.
String pathToLocation(String path) {
  if (path == 'index.md') return '/';
  final noExt = path.endsWith('.md')
      ? path.substring(0, path.length - 3)
      : path;
  return '/$noExt';
}

/// `/product/PRD` → `product/PRD.md`; `/` → `index.md`.
String locationToPath(String location) {
  final clean = location.split('#').first.split('?').first;
  if (clean.isEmpty || clean == '/') return 'index.md';
  final trimmed = clean.startsWith('/') ? clean.substring(1) : clean;
  return trimmed.endsWith('.md') ? trimmed : '$trimmed.md';
}

/// Resolves a markdown link relative to the page at [fromPath].
/// Returns a docs path (`guides/testing.md`) plus optional anchor, or null
/// for external links.
({String path, String? anchor})? resolveDocLink(String fromPath, String href) {
  if (href.startsWith('http://') ||
      href.startsWith('https://') ||
      href.startsWith('mailto:')) {
    return null;
  }
  final hashIdx = href.indexOf('#');
  final target = hashIdx < 0 ? href : href.substring(0, hashIdx);
  final anchor = hashIdx < 0 ? null : href.substring(hashIdx + 1);
  if (target.isEmpty) return (path: fromPath, anchor: anchor);
  final baseParts = fromPath.split('/')..removeLast();
  for (final part in target.split('/')) {
    if (part == '..') {
      if (baseParts.isNotEmpty) baseParts.removeLast();
    } else if (part != '.' && part.isNotEmpty) {
      baseParts.add(part);
    }
  }
  return (path: baseParts.join('/'), anchor: anchor);
}

/// GitHub-style heading slug: "4.1 Color tokens" → "41-color-tokens".
String slugify(String heading) => heading
    .toLowerCase()
    .replaceAll(RegExp('[`*_~]'), '')
    .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), '-');

/// A chunk of a page starting at a heading (or the page intro).
class MdSection {
  const MdSection({required this.markdown, this.heading, this.level = 0});

  final String markdown;
  final String? heading;
  final int level;

  String? get anchor => heading == null ? null : slugify(heading!);
}

/// Splits markdown at `##`/`###` headings, ignoring fenced code blocks, so
/// each heading can be scrolled to.
List<MdSection> splitSections(String markdown) {
  final sections = <MdSection>[];
  final buffer = StringBuffer();
  String? heading;
  var level = 0;
  var inFence = false;
  final headingRe = RegExp(r'^(#{2,3})\s+(.+?)\s*#*\s*$');

  void flush() {
    final text = buffer.toString();
    if (text.trim().isNotEmpty || heading != null) {
      sections.add(MdSection(markdown: text, heading: heading, level: level));
    }
    buffer.clear();
  }

  for (final line in const LineSplitter().convert(markdown)) {
    if (line.trimLeft().startsWith('```')) inFence = !inFence;
    final match = inFence ? null : headingRe.firstMatch(line);
    if (match != null) {
      flush();
      heading = match.group(2);
      level = match.group(1)!.length;
    }
    buffer.writeln(line);
  }
  flush();
  return sections;
}
