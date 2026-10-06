import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/geometry.dart';
import 'package:docscan_domain/src/ocr/ocr_geometry.dart';
import 'package:docscan_domain/src/ocr/ocr_text.dart';
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

  /// Short name for pickers ("Latin", "Devanagari", …).
  String get shortLabel => label.split(' (').first;

  /// Scripts written without spaces between words: wrapped lines are joined
  /// without inserting a space.
  bool get joinsWithoutSpace =>
      this == OcrScript.chinese || this == OcrScript.japanese;
}

@immutable
class OcrLine {
  const OcrLine(this.text, this.box, {this.confidence, this.angle});

  final String text;

  /// Bounding box in normalized coordinates of the recognized image (see
  /// [OcrResult.quarterTurns] for the frame).
  final NRect box;

  /// 0..1 when the engine reports it (ML Kit: Android only).
  final double? confidence;

  /// Clockwise skew of the line in degrees as reported by the engine, if any.
  final double? angle;

  OcrLine withBox(NRect box) =>
      OcrLine(text, box, confidence: confidence, angle: angle);
}

@immutable
class OcrBlock {
  const OcrBlock(this.lines);

  final List<OcrLine> lines;

  String get text => lines.map((l) => l.text).join('\n');

  /// Union of the line boxes; [NRect.full] never, `null` when empty.
  NRect? get box => unionRects(lines.map((l) => l.box));

  /// Mean of the reported line confidences, `null` when none reported.
  double? get confidence => meanConfidence(lines);
}

/// Recognized text for one image. Confidence is a signal, not a guarantee.
///
/// Line and block boxes are normalized to the *input* image as the user sees
/// it (EXIF orientation applied). When recognition only succeeded after
/// rotating the image, [quarterTurns] says by how many clockwise quarter
/// turns the page must be rotated for the text to read upright; boxes are
/// still expressed in the unrotated input frame, so a searchable-PDF text
/// layer lines up with the page image.
@immutable
class OcrResult {
  const OcrResult({
    required this.blocks,
    required this.script,
    this.quarterTurns = 0,
  });

  static const empty = OcrResult(blocks: [], script: OcrScript.latin);

  final List<OcrBlock> blocks;
  final OcrScript script;

  /// Clockwise quarter turns (0..3) that make the text upright.
  final int quarterTurns;

  /// Raw text: lines joined by `\n`, blocks by a blank line.
  String get text => blocks.map((b) => b.text).join('\n\n');

  /// Cleaned-up text for people: reading order as stored in [blocks],
  /// wrapped lines joined into paragraphs, end-of-line hyphenation removed
  /// and whitespace normalized. Line breaks inside forms and lists are kept.
  String get readableText => formatOcrText(this);

  Iterable<OcrLine> get lines => blocks.expand((b) => b.lines);

  bool get isEmpty => text.trim().isEmpty;

  /// Mean line confidence, `null` when the engine reports none.
  double? get confidence => meanConfidence(lines);

  OcrResult copyWith({
    List<OcrBlock>? blocks,
    OcrScript? script,
    int? quarterTurns,
  }) => OcrResult(
    blocks: blocks ?? this.blocks,
    script: script ?? this.script,
    quarterTurns: quarterTurns ?? this.quarterTurns,
  );
}

/// How much image clean-up to try before/while recognizing.
enum OcrEnhance {
  /// Recognize the image as is (after orientation/size normalization).
  off,

  /// Retry with illumination/contrast normalization when the result is poor.
  auto,

  /// Always normalize illumination/contrast (photos of paper in bad light).
  always,
}

/// Options for [OcrScript] choice and preprocessing.
@immutable
class OcrOptions {
  const OcrOptions({
    this.script,
    this.autoRotate = true,
    this.autoScale = true,
    this.enhance = OcrEnhance.auto,
  });

  /// Explicit script, or `null` for Auto: Latin first, then every other
  /// installed script when the output is poor; the best result wins.
  final OcrScript? script;

  /// Try 90/180/270° when the upright pass finds little or unsure text.
  final bool autoRotate;

  /// Upscale images whose text is too small for the model.
  final bool autoScale;
  final OcrEnhance enhance;

  bool get isAuto => script == null;

  OcrOptions copyWith({
    OcrScript? script,
    bool clearScript = false,
    bool? autoRotate,
    bool? autoScale,
    OcrEnhance? enhance,
  }) => OcrOptions(
    script: clearScript ? null : (script ?? this.script),
    autoRotate: autoRotate ?? this.autoRotate,
    autoScale: autoScale ?? this.autoScale,
    enhance: enhance ?? this.enhance,
  );
}

/// Cooperative cancellation for long OCR jobs. Checked between pages and
/// between recognition passes; a running native call finishes first.
class OcrCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// One input of a multi-file OCR job.
@immutable
sealed class OcrSource {
  const OcrSource(this.path, this.name);

  /// Absolute path of the file.
  final String path;

  /// Display name (no path) used in page labels.
  final String name;
}

final class OcrImageSource extends OcrSource {
  const OcrImageSource(super.path, super.name);
}

final class OcrPdfSource extends OcrSource {
  const OcrPdfSource(super.path, super.name);
}

/// Outcome for one page of an OCR job. Exactly one of [result],
/// [embeddedText] or [failure] is set.
@immutable
class OcrPage {
  const OcrPage({
    required this.sourceIndex,
    required this.pageIndex,
    required this.label,
    this.result,
    this.embeddedText,
    this.failure,
  });

  /// Index into the job's source list.
  final int sourceIndex;

  /// 0-based page within the source (always 0 for images).
  final int pageIndex;

  /// "Receipt.jpg" or "Report.pdf · page 3".
  final String label;
  final OcrResult? result;

  /// Text taken from the PDF's own text layer (no OCR needed).
  final String? embeddedText;

  /// Why this page could not be read; other pages are unaffected.
  final AppFailure? failure;

  bool get fromPdfText => embeddedText != null;
  bool get failed => failure != null;

  /// Best text for display/export.
  String get text => embeddedText ?? result?.readableText ?? '';
}

/// Result of a multi-page job. Partial when [cancelled].
@immutable
class OcrDocumentResult {
  const OcrDocumentResult({required this.pages, this.cancelled = false});

  final List<OcrPage> pages;
  final bool cancelled;

  int get failedCount => pages.where((p) => p.failed).length;

  /// All readable page texts separated by a blank line.
  String get text =>
      pages.map((p) => p.text.trim()).where((t) => t.isNotEmpty).join('\n\n');
}

/// Progress of a multi-page job.
@immutable
class OcrProgress {
  const OcrProgress({
    required this.done,
    required this.total,
    required this.label,
  });

  final int done;
  final int total;

  /// Page currently being read.
  final String label;

  double get fraction => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
}
