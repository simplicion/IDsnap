import 'package:docscan_domain/src/entities/geometry.dart';
import 'package:meta/meta.dart';

/// Writing systems with on-device OCR models.
enum OcrScript {
  latin('Latin (English, Spanish, French…)'),
  devanagari('Devanagari (Hindi, Marathi, Nepali…)'),
  chinese('Chinese'),
  japanese('Japanese'),
  korean('Korean');

  const OcrScript(this.label);
  final String label;
}

@immutable
class OcrLine {
  const OcrLine(this.text, this.box, {this.confidence});

  final String text;

  /// Bounding box in normalized coordinates of the recognized image.
  final NRect box;
  final double? confidence;
}

@immutable
class OcrBlock {
  const OcrBlock(this.lines);

  final List<OcrLine> lines;

  String get text => lines.map((l) => l.text).join('\n');
}

/// Recognized text for one image. Confidence is a signal, not a guarantee.
@immutable
class OcrResult {
  const OcrResult({required this.blocks, required this.script});

  static const empty = OcrResult(blocks: [], script: OcrScript.latin);

  final List<OcrBlock> blocks;
  final OcrScript script;

  String get text => blocks.map((b) => b.text).join('\n\n');

  Iterable<OcrLine> get lines => blocks.expand((b) => b.lines);

  bool get isEmpty => text.trim().isEmpty;
}
