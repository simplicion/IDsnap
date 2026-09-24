import 'dart:typed_data';

import 'package:engine_conversion/src/ooxml/zip_utils.dart';
import 'package:xml/xml.dart';

/// Returns the text of each slide (paragraphs joined by newlines), in the
/// order defined by presentation.xml. Falls back to slide file numbering.
List<String> readPptxSlides(Uint8List bytes) {
  final archive = openPackage(bytes);
  final paths = <String>[];

  final presentation = readXmlPart(archive, 'ppt/presentation.xml');
  if (presentation != null) {
    final rels = readRelationships(archive, 'ppt/_rels/presentation.xml.rels');
    for (final id in descendantsNamed(presentation, 'sldId')) {
      final target = rels[relationshipId(id)];
      if (target != null) {
        paths.add(resolveTarget('ppt/presentation.xml', target));
      }
    }
  }
  if (paths.isEmpty) {
    final numbered = RegExp(r'^ppt/slides/slide(\d+)\.xml$');
    final found = [
      for (final f in archive.files)
        if (numbered.firstMatch(f.name) case final m?)
          (int.parse(m[1]!), f.name),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    paths.addAll(found.map((e) => e.$2));
  }
  if (paths.isEmpty) return const [];

  return [
    for (final path in paths)
      if (readXmlPart(archive, path) case final slide?)
        descendantsNamed(slide, 'p')
            .map((p) => descendantsNamed(p, 't').map((t) => t.innerText).join())
            .where((line) => line.trim().isNotEmpty)
            .join('\n'),
  ];
}

/// "Slide 1" headings followed by slide text. Slides are separated by a
/// blank line, or by [separator] (e.g. a form feed for one slide per page).
String pptxToPlainText(List<String> slides, {String? separator}) {
  final out = StringBuffer();
  for (var i = 0; i < slides.length; i++) {
    if (i > 0) {
      if (separator == null) {
        out.writeln();
      } else {
        // Drop the trailing newline so the page starts cleanly.
        final soFar = out.toString().trimRight();
        out
          ..clear()
          ..write(soFar)
          ..write(separator);
      }
    }
    out
      ..writeln('Slide ${i + 1}')
      ..writeln(slides[i].trim().isEmpty ? '(no text)' : slides[i]);
  }
  return out.toString().trimRight();
}
