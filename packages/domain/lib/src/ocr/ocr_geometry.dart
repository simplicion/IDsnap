import 'dart:math' as math;

import 'package:docscan_domain/src/entities/geometry.dart';
import 'package:docscan_domain/src/entities/ocr.dart';

/// Smallest rect containing all [rects]; `null` when there are none.
NRect? unionRects(Iterable<NRect> rects) {
  double? l;
  double? t;
  double? r;
  double? b;
  for (final x in rects) {
    l = l == null ? x.left : math.min(l, x.left);
    t = t == null ? x.top : math.min(t, x.top);
    r = r == null ? x.right : math.max(r, x.right);
    b = b == null ? x.bottom : math.max(b, x.bottom);
  }
  if (l == null) return null;
  return NRect(l, t!, r! - l, b! - t);
}

/// Mean of the reported line confidences, `null` when none reported.
double? meanConfidence(Iterable<OcrLine> lines) {
  var sum = 0.0;
  var n = 0;
  for (final l in lines) {
    final c = l.confidence;
    if (c == null) continue;
    sum += c;
    n++;
  }
  return n == 0 ? null : sum / n;
}

/// Maps a normalized rect into the frame of the same image rotated clockwise
/// by [quarterTurns] × 90°.
NRect rotateNRect(NRect r, int quarterTurns) => switch (quarterTurns % 4) {
  1 => NRect(1 - r.bottom, r.left, r.height, r.width),
  2 => NRect(1 - r.right, 1 - r.bottom, r.width, r.height),
  3 => NRect(r.top, 1 - r.right, r.height, r.width),
  _ => r,
};

/// Re-expresses [result], recognized on an image rotated clockwise by
/// [quarterTurns], in the unrotated input frame and records the rotation.
OcrResult unrotateResult(OcrResult result, int quarterTurns) {
  final t = quarterTurns % 4;
  if (t == 0) return result.copyWith(quarterTurns: 0);
  final back = 4 - t;
  return OcrResult(
    script: result.script,
    quarterTurns: t,
    blocks: [
      for (final b in result.blocks)
        OcrBlock([
          for (final l in b.lines) l.withBox(rotateNRect(l.box, back)),
        ]),
    ],
  );
}

/// Box of [line] in the upright (text-reading) frame of [result].
NRect uprightBox(NRect box, int quarterTurns) => rotateNRect(box, quarterTurns);
