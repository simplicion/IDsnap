// XML fixtures are built from adjacent literals.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:engine_conversion/engine_conversion.dart';
import 'package:engine_conversion/src/ooxml/zip_utils.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

String part(Uint8List zip, String name) =>
    utf8.decode(ZipDecoder().decodeBytes(zip).findFile(name)!.readBytes()!);

void main() {
  group('DOCX', () {
    Uint8List sample() {
      final b = DocxBuilder(title: 'Report & <notes>')
        ..heading('Quarterly report')
        ..paragraph('First line\nsecond line\twith tab & <tags>')
        ..bullet('Point one')
        ..heading('Details', level: 2)
        ..pageBreak()
        ..paragraph('On page two')
        ..image(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 1]),
          widthPx: 2000,
          heightPx: 1000,
        );
      return b.build();
    }

    test('contains every required package part and valid XML', () {
      final zip = sample();
      final archive = ZipDecoder().decodeBytes(zip);
      for (final name in [
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'word/styles.xml',
        'word/_rels/document.xml.rels',
        'docProps/core.xml',
        'word/media/image1.jpeg',
      ]) {
        expect(archive.findFile(name), isNotNull, reason: name);
      }
      for (final xml in [
        '[Content_Types].xml',
        '_rels/.rels',
        'word/document.xml',
        'word/styles.xml',
        'word/_rels/document.xml.rels',
        'docProps/core.xml',
      ]) {
        expect(
          () => XmlDocument.parse(part(zip, xml)),
          returnsNormally,
          reason: xml,
        );
      }
      expect(part(zip, '[Content_Types].xml'), contains('Extension="jpeg"'));
      expect(
        part(zip, 'word/_rels/document.xml.rels'),
        contains('Target="media/image1.jpeg"'),
      );
      expect(part(zip, 'word/document.xml'), contains('r:embed="rIdImg1"'));
      expect(
        DocumentFormat.sniff(zip, nameHint: 'x.docx'),
        DocumentFormat.docx,
      );
    });

    test('image is scaled to fit page width keeping aspect ratio', () {
      final doc = XmlDocument.parse(part(sample(), 'word/document.xml'));
      final extent = doc.descendants.whereType<XmlElement>().firstWhere(
        (e) => e.name.local == 'extent',
      );
      final cx = int.parse(extent.getAttribute('cx')!);
      final cy = int.parse(extent.getAttribute('cy')!);
      expect(cx, (11906 - 2 * 1134) * 635);
      expect((cx / cy - 2).abs(), lessThan(0.001));
    });

    test('writer output round-trips through the reader', () {
      final paras = readDocx(sample());
      expect(paras.map((p) => p.text), [
        'Quarterly report',
        'First line\nsecond line\twith tab & <tags>',
        'Point one',
        'Details',
        'On page two',
        '',
      ]);
      expect(paras[0].headingLevel, 1);
      expect(paras[3].headingLevel, 2);
      expect(paras[2].isBullet, isTrue);
      expect(paras[4].pageBreakBefore, isTrue);
      expect(
        docxToPlainText(paras),
        'Quarterly report\n\nFirst line\nsecond line\twith tab & <tags>\n\n'
        '• Point one\n\nDetails\n\n\nOn page two',
      );
    });

    test('strips characters XML forbids', () {
      final zip = (DocxBuilder()..paragraph('bad\u0001char')).build();
      expect(readDocx(zip).single.text, 'badchar');
    });

    test('rejects non-zip and encrypted Office files', () {
      expect(
        () => readDocx(Uint8List.fromList(utf8.encode('not a zip'))),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.corruptFile,
          ),
        ),
      );
      final ole = Uint8List.fromList([
        0xD0,
        0xCF,
        0x11,
        0xE0,
        0xA1,
        0xB1,
        0x1A,
        0xE1,
      ]);
      expect(
        () => readDocx(ole),
        throwsA(
          isA<AppFailure>().having(
            (f) => f.code,
            'code',
            FailureCode.passwordProtected,
          ),
        ),
      );
    });
  });

  group('XLSX', () {
    test(
      'CSV → XLSX → CSV round-trips commas, quotes, unicode and numbers',
      () {
        const csv =
            'Name,Amount,Code,Note\r\n'
            '"Doe, Jane",12.50,007,"said ""hi"""\r\n'
            'राम,-3,,₹ 500\r\n'
            ',,,last';
        final rows = parseCsv(csv);
        final xlsx = writeXlsx(rows, sheetName: 'My/Data');
        final sheets = readXlsx(xlsx);
        expect(sheets.single.name, 'My Data');
        expect(writeCsv(sheets.single.rows), csv);
        final sheetXml = part(xlsx, 'xl/worksheets/sheet1.xml');
        expect(sheetXml, contains('<c r="B2"><v>12.50</v></c>'));
        expect(sheetXml, contains('<c r="C2" t="inlineStr">'));
      },
    );

    test('reads shared strings, booleans and column gaps', () {
      const ns =
          'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';
      final zip = buildPackage({
        'xl/workbook.xml':
            '<workbook $ns><sheets><sheet name="S" sheetId="1" r:id="rId9"/></sheets></workbook>',
        'xl/_rels/workbook.xml.rels':
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId9" Target="/xl/worksheets/s.xml" Type="x"/></Relationships>',
        'xl/sharedStrings.xml':
            '<sst $ns><si><t>Hello</t></si><si><r><t>Wor</t></r><r><t>ld</t></r><rPh><t>x</t></rPh></si></sst>',
        'xl/worksheets/s.xml':
            '<worksheet $ns><sheetData>'
            '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>'
            '<row r="3"><c r="B3" t="b"><v>1</v></c><c r="C3"><f>1+1</f><v>2</v></c></row>'
            '</sheetData></worksheet>',
      });
      expect(readXlsx(zip).single.rows, [
        ['Hello', '', 'World'],
        <String>[],
        ['', 'TRUE', '2'],
      ]);
    });

    test('date-formatted cells become ISO dates; plain numbers stay', () {
      const ns =
          'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';
      final zip = buildPackage({
        'xl/workbook.xml':
            '<workbook $ns><sheets><sheet name="S" sheetId="1" r:id="rId1"/></sheets></workbook>',
        'xl/_rels/workbook.xml.rels':
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Target="worksheets/sheet1.xml" Type="x"/></Relationships>',
        'xl/styles.xml':
            '<styleSheet $ns>'
            '<numFmts count="2"><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/>'
            '<numFmt numFmtId="165" formatCode="[Red]0.00;&quot;day&quot;0"/></numFmts>'
            '<cellXfs count="6"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="164"/>'
            '<xf numFmtId="165"/><xf numFmtId="22"/><xf numFmtId="20"/></cellXfs></styleSheet>',
        'xl/worksheets/sheet1.xml':
            '<worksheet $ns><sheetData><row r="1">'
            '<c r="A1" s="0"><v>45000</v></c>'
            '<c r="B1" s="1"><v>45000</v></c>'
            '<c r="C1" s="2"><v>45292</v></c>'
            '<c r="D1" s="3"><v>12.5</v></c>'
            '<c r="E1" s="4"><v>45000.75</v></c>'
            '<c r="F1" s="5"><v>0.5</v></c>'
            '<c r="G1" s="1" t="s"><v>0</v></c>'
            '</row></sheetData></worksheet>',
        'xl/sharedStrings.xml': '<sst $ns><si><t>text</t></si></sst>',
      });
      expect(readXlsx(zip).single.rows.single, [
        '45000',
        '2023-03-15',
        '2024-01-01',
        '12.5',
        '2023-03-15 18:00:00',
        '12:00:00',
        'text',
      ]);
    });

    test('1904 date system and format classification', () {
      expect(formatExcelSerial(0, date1904: true), '1904-01-01');
      expect(formatExcelSerial(61), '1900-03-01');
      expect(
        classifyNumberFormat('yyyy-mm-dd'),
        isNot(equals(classifyNumberFormat('0.00'))),
      );
      expect(classifyNumberFormat('mm:ss').name, 'time');
      expect(classifyNumberFormat('"Date:" 0').name, 'plain');
      expect(classifyNumberFormat('mmm yy').name, 'date');
    });

    test('column names', () {
      expect([0, 25, 26, 701, 702].map(columnName), [
        'A',
        'Z',
        'AA',
        'ZZ',
        'AAA',
      ]);
      expect(columnIndex('AB12'), 27);
    });
  });

  group('PPTX', () {
    Uint8List pptx() {
      const a =
          'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
          'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';
      String slide(List<String> paras) =>
          '<p:sld $a><p:cSld><p:spTree><p:sp><p:txBody>'
          '${paras.map((t) => '<a:p><a:r><a:t>$t</a:t></a:r></a:p>').join()}'
          '<a:p></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>';
      return buildPackage({
        '[Content_Types].xml':
            '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
        // Order in presentation.xml is slide2 then slide1.
        'ppt/presentation.xml':
            '<p:presentation $a><p:sldIdLst>'
            '<p:sldId id="256" r:id="rId2"/><p:sldId id="257" r:id="rId1"/>'
            '</p:sldIdLst></p:presentation>',
        'ppt/_rels/presentation.xml.rels':
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Target="slides/slide1.xml" Type="x"/>'
            '<Relationship Id="rId2" Target="slides/slide2.xml" Type="x"/></Relationships>',
        'ppt/slides/slide1.xml': slide(['Second deck slide']),
        'ppt/slides/slide2.xml': slide(['Welcome', 'Agenda &amp; goals']),
      });
    }

    test('reads slide text in presentation order', () {
      final slides = readPptxSlides(pptx());
      expect(slides, ['Welcome\nAgenda & goals', 'Second deck slide']);
      expect(
        pptxToPlainText(slides),
        'Slide 1\nWelcome\nAgenda & goals\n\nSlide 2\nSecond deck slide',
      );
    });

    test('falls back to slide numbering without presentation.xml', () {
      final zip = buildPackage({
        'ppt/slides/slide10.xml': '<sld><p><t>ten</t></p></sld>',
        'ppt/slides/slide2.xml': '<sld><p><t>two</t></p></sld>',
      });
      expect(readPptxSlides(zip), ['two', 'ten']);
    });
  });

  test('resolveTarget handles relative and absolute targets', () {
    expect(
      resolveTarget('xl/workbook.xml', 'worksheets/sheet1.xml'),
      'xl/worksheets/sheet1.xml',
    );
    expect(
      resolveTarget('ppt/slides/slide1.xml', '../media/a.png'),
      'ppt/media/a.png',
    );
    expect(resolveTarget('xl/workbook.xml', '/xl/s.xml'), 'xl/s.xml');
  });
}
