import 'package:docscan_domain/src/entities/ocr.dart';
import 'package:meta/meta.dart';

/// How good a recognition pass looks, used to pick between rotations,
/// preprocessing variants and scripts. Heuristic and engine-agnostic.
@immutable
class OcrQuality {
  const OcrQuality({
    required this.characters,
    required this.lines,
    required this.confidence,
    required this.scriptShare,
    required this.score,
  });

  /// Letters and digits recognized.
  final int characters;
  final int lines;

  /// Mean line confidence, `null` when the engine reports none.
  final double? confidence;

  /// Share (0..1) of letters that belong to the recognizer's own script.
  /// Low values mean the model is reading a script it does not know.
  final double scriptShare;

  /// Higher is better; comparable across passes on the same page.
  final double score;

  /// Little text or unsure text: worth trying another rotation, variant or
  /// script.
  bool get isPoor =>
      characters < minCharacters ||
      (confidence != null && confidence! < minConfidence) ||
      scriptShare < 0.5;

  /// Confident enough to stop searching.
  bool get isGood =>
      characters >= 2 * minCharacters &&
      (confidence == null || confidence! >= 0.8) &&
      scriptShare >= 0.8;

  static const minCharacters = 12;
  static const minConfidence = 0.6;

  /// Assumed confidence when the engine reports none (ML Kit on iOS).
  static const unknownConfidence = 0.7;
}

/// Scores [result]: Σ over lines of (letters in the expected script + digits
/// + half of other letters) × line confidence. Short garbage lines
/// (1–2 characters) are down-weighted — rotated text tends to produce them.
OcrQuality assessOcr(OcrResult result) {
  var chars = 0;
  var lines = 0;
  var own = 0;
  var letters = 0;
  var score = 0.0;
  var confSum = 0.0;
  var confN = 0;
  for (final line in result.lines) {
    var lineOwn = 0;
    var lineOther = 0;
    var lineDigits = 0;
    for (final rune in line.text.runes) {
      if (_isDigit(rune)) {
        lineDigits++;
      } else if (_inScript(rune, result.script)) {
        lineOwn++;
      } else if (_isLetter(rune)) {
        lineOther++;
      }
    }
    final n = lineOwn + lineOther + lineDigits;
    if (n == 0) continue;
    lines++;
    chars += n;
    own += lineOwn;
    letters += lineOwn + lineOther;
    final c = line.confidence;
    if (c != null) {
      confSum += c;
      confN++;
    }
    final weight = n <= 2 ? 0.3 : 1.0;
    score +=
        (lineOwn + lineDigits + 0.5 * lineOther) *
        (c ?? OcrQuality.unknownConfidence) *
        weight;
  }
  return OcrQuality(
    characters: chars,
    lines: lines,
    confidence: confN == 0 ? null : confSum / confN,
    scriptShare: letters == 0 ? 1 : own / letters,
    score: score,
  );
}

/// Median line height in pixels of an image [imageHeight] px tall, measured
/// perpendicular to the text (upright frame). `null` when there are no lines.
double? medianLineHeightPx(
  OcrResult result, {
  required int imageWidth,
  required int imageHeight,
}) {
  final sideways = result.quarterTurns.isOdd;
  final heights = [
    for (final l in result.lines)
      if (sideways) l.box.width * imageWidth else l.box.height * imageHeight,
  ]..sort();
  if (heights.isEmpty) return null;
  return heights[heights.length ~/ 2];
}

/// Clockwise quarter turns to try after an upright pass, most likely first.
/// ML Kit reports each line's skew angle; text read at ~90° hints at a
/// sideways page, ~180° at an upside-down one.
List<int> rotationCandidates(OcrResult upright) {
  final angles = [
    for (final l in upright.lines)
      if (l.angle != null) l.angle!,
  ]..sort();
  if (angles.isNotEmpty) {
    final a = angles[angles.length ~/ 2] % 360;
    // Line tilted clockwise by ~90° → rotate counter-clockwise (3 turns).
    if (a >= 45 && a < 135) return const [3, 1, 2];
    if (a >= 225 && a < 315) return const [1, 3, 2];
    if (a >= 135 && a < 225) return const [2, 1, 3];
  }
  // Tall, narrow line boxes mean vertical text: sideways first.
  final lines = upright.lines.toList();
  if (lines.isNotEmpty) {
    final tall = lines.where((l) => l.box.height > l.box.width).length;
    if (tall * 2 > lines.length) return const [1, 3, 2];
  }
  return const [2, 1, 3];
}

bool _isDigit(int r) =>
    (r >= 0x30 && r <= 0x39) || // ASCII
    (r >= 0x966 && r <= 0x96F) || // Devanagari digits
    (r >= 0xFF10 && r <= 0xFF19); // full-width

bool _isLetter(int r) =>
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0xC0 && r <= 0x24F) ||
    (r >= 0x370 && r <= 0x3FF) || // Greek
    (r >= 0x400 && r <= 0x4FF) || // Cyrillic
    (r >= 0x900 && r <= 0x97F) ||
    (r >= 0x1100 && r <= 0x11FF) ||
    (r >= 0x3040 && r <= 0x30FF) ||
    (r >= 0x3130 && r <= 0x318F) ||
    (r >= 0x3400 && r <= 0x4DBF) ||
    (r >= 0x4E00 && r <= 0x9FFF) ||
    (r >= 0xAC00 && r <= 0xD7AF) ||
    (r >= 0xF900 && r <= 0xFAFF);

bool _latin(int r) =>
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0xC0 && r <= 0x24F && r != 0xD7 && r != 0xF7);

bool _han(int r) =>
    (r >= 0x3400 && r <= 0x4DBF) ||
    (r >= 0x4E00 && r <= 0x9FFF) ||
    (r >= 0xF900 && r <= 0xFAFF);

bool _inScript(int r, OcrScript script) => switch (script) {
  OcrScript.latin => _latin(r),
  // Every non-Latin model also reads Latin, so Latin letters count as its
  // own: mixed pages (Hindi + English) must not look "foreign".
  OcrScript.devanagari => (r >= 0x900 && r <= 0x97F) || _latin(r),
  OcrScript.chinese => _han(r) || _latin(r),
  OcrScript.japanese => (r >= 0x3040 && r <= 0x30FF) || _han(r) || _latin(r),
  OcrScript.korean =>
    (r >= 0xAC00 && r <= 0xD7AF) ||
        (r >= 0x1100 && r <= 0x11FF) ||
        (r >= 0x3130 && r <= 0x318F) ||
        _han(r) ||
        _latin(r),
};

/// True when [b] is clearly better than [a] (by [margin], relative).
bool clearlyBetter(OcrQuality b, OcrQuality a, {double margin = 0.15}) =>
    b.score > a.score * (1 + margin) + 1 ||
    (a.characters == 0 && b.characters > 0);
