// XML is built from adjacent literals; whitespace between them is wrong.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:typed_data';

import 'package:engine_conversion/src/ooxml/zip_utils.dart';

/// Paragraph styles defined in the generated styles.xml.
enum DocxStyle {
  normal('Normal'),
  title('Title'),
  heading1('Heading1'),
  heading2('Heading2'),
  heading3('Heading3'),
  listBullet('ListBullet'),
  quote('Quote'),
  code('Code');

  const DocxStyle(this.id);
  final String id;

  static DocxStyle heading(int level) => switch (level) {
    <= 1 => heading1,
    2 => heading2,
    _ => heading3,
  };
}

/// Image formats that can be embedded.
enum DocxImageType {
  jpeg('jpeg', 'image/jpeg'),
  png('png', 'image/png');

  const DocxImageType(this.extension, this.contentType);
  final String extension;
  final String contentType;
}

sealed class _Block {}

class _Para extends _Block {
  _Para(this.text, this.style);
  final String text;
  final DocxStyle style;
}

class _PageBreak extends _Block {}

class _Image extends _Block {
  _Image(this.relId, this.index, this.cx, this.cy);
  final String relId;
  final int index;
  final int cx;
  final int cy;
}

/// Writes a minimal, valid WordprocessingML (.docx) package: content types,
/// package and document relationships, styles, document body and embedded
/// media. A4 portrait page.
class DocxBuilder {
  DocxBuilder({this.title});

  /// Written to docProps/core.xml; leave null to avoid embedding names.
  final String? title;

  static const _pageWidthTwips = 11906; // A4 210 mm
  static const _pageHeightTwips = 16838; // A4 297 mm
  static const _marginTwips = 1134; // 2 cm
  static const _emuPerTwip = 635;

  final _blocks = <_Block>[];
  final _media = <String, Uint8List>{};
  final _mediaTypes = <DocxImageType>{};

  bool get isEmpty => _blocks.isEmpty;

  /// Adds a paragraph; `\n` becomes a line break, `\t` a tab.
  void paragraph(String text, {DocxStyle style = DocxStyle.normal}) =>
      _blocks.add(_Para(text, style));

  void heading(String text, {int level = 1}) =>
      paragraph(text, style: DocxStyle.heading(level));

  /// Bullet item. Rendered as "•" + tab with a hanging indent, so no
  /// numbering part is needed.
  void bullet(String text) =>
      paragraph('$bulletPrefix$text', style: DocxStyle.listBullet);

  static const bulletPrefix = '•\t';

  void pageBreak() => _blocks.add(_PageBreak());

  /// Embeds an image scaled to fit inside the page margins, keeping aspect.
  void image(
    Uint8List bytes, {
    required int widthPx,
    required int heightPx,
    DocxImageType type = DocxImageType.jpeg,
  }) {
    final index = _media.length + 1;
    _media['image$index.${type.extension}'] = bytes;
    _mediaTypes.add(type);
    const maxW = (_pageWidthTwips - 2 * _marginTwips) * _emuPerTwip;
    // Leave room for the paragraph line so Word doesn't push it to a new page.
    const maxH = (_pageHeightTwips - 2 * _marginTwips - 400) * _emuPerTwip;
    final w = widthPx <= 0 ? 1 : widthPx;
    final h = heightPx <= 0 ? 1 : heightPx;
    var cx = maxW;
    var cy = (maxW * h / w).round();
    if (cy > maxH) {
      cy = maxH;
      cx = (maxH * w / h).round();
    }
    _blocks.add(_Image('rIdImg$index', index, cx, cy));
  }

  Uint8List build() {
    final parts = <String, Object>{
      '[Content_Types].xml': _contentTypes(),
      '_rels/.rels': _packageRels,
      'docProps/core.xml': _core(),
      'docProps/app.xml': _app,
      'word/document.xml': _document(),
      'word/styles.xml': _styles,
      'word/_rels/document.xml.rels': _documentRels(),
      for (final m in _media.entries) 'word/media/${m.key}': m.value,
    };
    return buildPackage(parts);
  }

  String _contentTypes() {
    final defaults = StringBuffer()
      ..write(
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>',
      );
    for (final t in _mediaTypes) {
      defaults.write(
        '<Default Extension="${t.extension}" ContentType="${t.contentType}"/>',
      );
    }
    return '$_xmlHeader<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '$defaults'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '</Types>';
  }

  String _core() =>
      '$_xmlHeader<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '${title == null ? '' : '<dc:title>${xmlEscape(title!)}</dc:title>'}'
      '<dc:creator>IDSnap</dc:creator>'
      '</cp:coreProperties>';

  String _documentRels() {
    final b = StringBuffer(
      '$_xmlHeader<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>',
    );
    var i = 1;
    for (final name in _media.keys) {
      b.write(
        '<Relationship Id="rIdImg$i" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/$name"/>',
      );
      i++;
    }
    b.write('</Relationships>');
    return b.toString();
  }

  String _document() {
    final body = StringBuffer();
    for (final block in _blocks) {
      switch (block) {
        case _Para(:final text, :final style):
          body.write(_paragraphXml(text, style));
        case _PageBreak():
          body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
        case _Image(:final relId, :final index, :final cx, :final cy):
          body.write(_imageXml(relId, index, cx, cy));
      }
    }
    return '$_xmlHeader<w:document '
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>$body'
        '<w:sectPr><w:pgSz w:w="$_pageWidthTwips" w:h="$_pageHeightTwips"/>'
        '<w:pgMar w:top="$_marginTwips" w:right="$_marginTwips" w:bottom="$_marginTwips" '
        'w:left="$_marginTwips" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>'
        '</w:body></w:document>';
  }

  static String _paragraphXml(String text, DocxStyle style) {
    final runs = StringBuffer();
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    for (var li = 0; li < lines.length; li++) {
      if (li > 0) runs.write('<w:r><w:br/></w:r>');
      final segments = lines[li].split('\t');
      for (var si = 0; si < segments.length; si++) {
        if (si > 0) runs.write('<w:r><w:tab/></w:r>');
        if (segments[si].isEmpty) continue;
        runs.write(
          '<w:r><w:t xml:space="preserve">${xmlEscape(segments[si])}</w:t></w:r>',
        );
      }
    }
    final pPr = style == DocxStyle.normal
        ? ''
        : '<w:pPr><w:pStyle w:val="${style.id}"/></w:pPr>';
    return '<w:p>$pPr$runs</w:p>';
  }

  static String _imageXml(String relId, int index, int cx, int cy) =>
      '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing>'
      '<wp:inline distT="0" distB="0" distL="0" distR="0">'
      '<wp:extent cx="$cx" cy="$cy"/>'
      '<wp:docPr id="$index" name="Picture $index"/>'
      '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:pic><pic:nvPicPr><pic:cNvPr id="$index" name="Picture $index"/><pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="$relId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
      '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>';
}

const _xmlHeader = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

const _packageRels =
    '$_xmlHeader<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
    '</Relationships>';

const _app =
    '$_xmlHeader<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
    '<Application>IDSnap</Application></Properties>';

String _style(
  String id,
  String name, {
  String? basedOn,
  String pPr = '',
  String rPr = '',
  bool isDefault = false,
}) =>
    '<w:style w:type="paragraph" w:styleId="$id"${isDefault ? ' w:default="1"' : ''}>'
    '<w:name w:val="$name"/>'
    '${basedOn == null ? '' : '<w:basedOn w:val="$basedOn"/><w:next w:val="Normal"/>'}'
    '<w:qFormat/>'
    '${pPr.isEmpty ? '' : '<w:pPr>$pPr</w:pPr>'}'
    '${rPr.isEmpty ? '' : '<w:rPr>$rPr</w:rPr>'}'
    '</w:style>';

final String _styles =
    '$_xmlHeader<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:docDefaults><w:rPrDefault><w:rPr>'
    '<w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Calibri"/>'
    '<w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault>'
    '<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault>'
    '</w:docDefaults>'
    '${_style('Normal', 'Normal', isDefault: true)}'
    '${_style('Title', 'Title', basedOn: 'Normal', pPr: '<w:spacing w:after="240"/>', rPr: '<w:b/><w:sz w:val="48"/><w:szCs w:val="48"/>')}'
    '${_style('Heading1', 'heading 1', basedOn: 'Normal', pPr: '<w:keepNext/><w:spacing w:before="360" w:after="120"/><w:outlineLvl w:val="0"/>', rPr: '<w:b/><w:sz w:val="36"/><w:szCs w:val="36"/>')}'
    '${_style('Heading2', 'heading 2', basedOn: 'Normal', pPr: '<w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="1"/>', rPr: '<w:b/><w:sz w:val="30"/><w:szCs w:val="30"/>')}'
    '${_style('Heading3', 'heading 3', basedOn: 'Normal', pPr: '<w:keepNext/><w:spacing w:before="200" w:after="60"/><w:outlineLvl w:val="2"/>', rPr: '<w:b/><w:sz w:val="26"/><w:szCs w:val="26"/>')}'
    '${_style('ListBullet', 'List Bullet', basedOn: 'Normal', pPr: '<w:spacing w:after="60"/><w:ind w:left="720" w:hanging="360"/>')}'
    '${_style('Quote', 'Quote', basedOn: 'Normal', pPr: '<w:ind w:left="720"/>', rPr: '<w:i/>')}'
    '${_style('Code', 'Code', basedOn: 'Normal', pPr: '<w:spacing w:after="0"/>', rPr: '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="20"/>')}'
    '</w:styles>';
