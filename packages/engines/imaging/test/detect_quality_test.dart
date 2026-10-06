// Evaluation harness for page detection: synthesizes realistic scenes in pure
// Dart, scores the shipped detector against the original (legacy) one and
// asserts quality thresholds. Run with `flutter test test/detect_quality_test.dart`
// to see the per-category table.
// Benchmark/table output is the point of this file.
// ignore_for_file: avoid_print
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_imaging/engine_imaging.dart';
import 'package:engine_imaging/src/filters/threshold.dart';
import 'package:engine_imaging/src/raster.dart';
import 'package:test/test.dart';

// ── Scene synthesis ─────────────────────────────────────────────────────────

enum Background { dark, wood, fabric, busy, lightTable, warmTable, medium }

enum Category {
  darkPlain('dark plain'),
  wood('dark wood'),
  fabric('textured'),
  busy('busy'),
  lowContrast('low contrast'),
  shadow('shadow/gradient'),
  perspective('strong perspective'),
  small('small page'),
  idCard('ID card'),
  noisy('noise + JPEG'),
  outOfFrame('out of frame'),
  negative('no page');

  const Category(this.label);
  final String label;

  /// Cases that count toward the in-frame detection thresholds.
  bool get inFrame => this != outOfFrame && this != negative;
}

class Scene {
  Scene(this.category, this.image, this.corners);

  final Category category;
  final Rgb image;

  /// Ground-truth corners (continuous pixel coords, clockwise from the
  /// page's own top-left); null for scenes without a page.
  final List<List<double>>? corners;
}

class _Spec {
  _Spec({
    required this.bg,
    this.pageArea = 0.45,
    this.maxRotation = 35,
    this.keystone = 0.9,
    this.aspect = 1 / math.sqrt2,
    this.card = false,
    this.gradient = 0.15,
    this.shadow = false,
    this.noise = 2.5,
    this.jpegQuality,
    this.outOfFrame = false,
    this.cut = 0,
    this.page = true,
  });

  final Background bg;
  final double pageArea;
  final double maxRotation;
  final double keystone; // top/bottom width ratio lower bound (1 = none)
  final double aspect; // width / height of the physical page
  final bool card;
  final double gradient;
  final bool shadow;
  final double noise;
  final int? jpegQuality;
  final bool outOfFrame;

  /// Corners outside the frame (1: a corner cut off, 2: a whole side).
  final int cut;
  final bool page;
}

const _sizes = [(800, 600), (600, 800), (1024, 768), (960, 720)];

_Spec _specFor(Category c, math.Random r) => switch (c) {
  Category.darkPlain => _Spec(bg: Background.dark),
  Category.wood => _Spec(bg: Background.wood),
  Category.fabric => _Spec(bg: Background.fabric),
  Category.busy => _Spec(bg: Background.busy),
  Category.lowContrast => _Spec(
    bg: r.nextBool() ? Background.lightTable : Background.warmTable,
    gradient: 0.12,
  ),
  Category.shadow => _Spec(
    bg: r.nextBool() ? Background.medium : Background.wood,
    gradient: 0.45,
    shadow: true,
  ),
  Category.perspective => _Spec(
    bg: r.nextBool() ? Background.dark : Background.fabric,
    keystone: 0.62,
    maxRotation: 20,
  ),
  Category.small => _Spec(
    bg: Background.values[r.nextInt(4)],
    pageArea: 0.1 + r.nextDouble() * 0.12,
  ),
  Category.idCard => _Spec(
    bg: [Background.dark, Background.wood, Background.medium][r.nextInt(3)],
    pageArea: 0.05 + r.nextDouble() * 0.08,
    aspect: 1.586,
    card: true,
  ),
  Category.noisy => _Spec(
    bg: r.nextBool() ? Background.wood : Background.dark,
    noise: 9,
    jpegQuality: 25 + r.nextInt(15),
  ),
  Category.outOfFrame => _Spec(
    bg: Background.values[r.nextInt(3)],
    pageArea: 0.5,
    outOfFrame: true,
    cut: 1 + r.nextInt(2),
  ),
  Category.negative => _Spec(
    bg: Background.values[r.nextInt(Background.values.length)],
    page: false,
    gradient: 0.3,
  ),
};

Scene buildScene(Category category, int seed, {int? width, int? height}) {
  final r = math.Random(seed * 7919 + category.index);
  final spec = _specFor(category, r);
  final size = _sizes[r.nextInt(_sizes.length)];
  final w = width ?? size.$1;
  final h = height ?? size.$2;
  final image = _background(spec.bg, w, h, r);
  List<List<double>>? corners;
  if (spec.page) {
    corners = _placePage(spec, w, h, r);
    _drawPage(image, corners, spec, r);
  }
  _light(image, spec, r);
  // Optics: lens distortion bends straight page edges, defocus softens them.
  final k1 = (r.nextDouble() - 0.5) * 0.06;
  var lens = _distort(image, k1);
  if (corners != null) {
    corners = [for (final c in corners) _distortPoint(c, k1, w, h)];
  }
  lens = _blur(lens);
  _noise(lens, spec.noise, r);
  var out = lens;
  final q = spec.jpegQuality;
  if (q != null) out = decodeRgb(encodeJpeg(lens, q));
  return Scene(category, out, corners);
}

List<List<double>> _placePage(_Spec s, int w, int h, math.Random r) {
  for (var attempt = 0; ; attempt++) {
    final shrink = s.outOfFrame ? 1.0 : math.pow(0.985, attempt);
    final area = s.pageArea * shrink * (0.8 + 0.4 * r.nextDouble()) * w * h;
    final pw = math.sqrt(area * s.aspect);
    final ph = pw / s.aspect;
    final rot =
        (r.nextDouble() * s.maxRotation) *
        (r.nextBool() ? 1 : -1) *
        math.pi /
        180;
    final k = s.keystone + (1 - s.keystone) * r.nextDouble();
    // Keystone: the far (top) edge is narrower, as with a tilted camera.
    final local = [
      [-pw / 2 * k, -ph / 2],
      [pw / 2 * k, -ph / 2],
      [pw / 2, ph / 2],
      [-pw / 2, ph / 2],
    ];
    final double cx;
    final double cy;
    if (s.outOfFrame) {
      cx = w * (0.15 + 0.7 * r.nextDouble());
      cy = h * (0.15 + 0.7 * r.nextDouble());
    } else {
      cx = w / 2 + (r.nextDouble() - 0.5) * w * 0.2;
      cy = h / 2 + (r.nextDouble() - 0.5) * h * 0.2;
    }
    final c = math.cos(rot);
    final sn = math.sin(rot);
    final pts = [
      for (final p in local)
        [cx + p[0] * c - p[1] * sn, cy + p[0] * sn + p[1] * c],
    ];
    final margin = 0.03 * math.min(w, h);
    final inside = pts.every(
      (p) =>
          p[0] >= margin &&
          p[0] <= w - margin &&
          p[1] >= margin &&
          p[1] <= h - margin,
    );
    final outside = pts.where(
      (p) => p[0] < 0 || p[0] > w || p[1] < 0 || p[1] > h,
    );
    if (s.outOfFrame ? outside.length == s.cut : inside) return pts;
    if (attempt > 400) return pts;
  }
}

/// Cheap approximately-normal sample (Irwin–Hall, 4 uniforms).
double _gauss(math.Random r) =>
    (r.nextDouble() + r.nextDouble() + r.nextDouble() + r.nextDouble() - 2) *
    1.7320508;

int _c(num v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

Rgb _background(Background bg, int w, int h, math.Random r) {
  final img = Rgb(w, h);
  final d = img.data;
  void put(int x, int y, num red, num green, num blue) {
    final p = (y * w + x) * 3;
    d[p] = _c(red);
    d[p + 1] = _c(green);
    d[p + 2] = _c(blue);
  }

  switch (bg) {
    case Background.dark:
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          put(x, y, 38, 40, 46);
        }
      }
    case Background.medium:
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          put(x, y, 138, 128, 116);
        }
      }
    case Background.lightTable:
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          put(x, y, 206, 206, 203);
        }
      }
    case Background.warmTable:
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final v = 3 * math.sin(x / 41 + y / 67);
          put(x, y, 222 + v, 216 + v, 204 + v);
        }
      }
    case Background.wood:
      final a = r.nextDouble() * math.pi;
      final ca = math.cos(a);
      final sa = math.sin(a);
      final plank = 120 + r.nextInt(80);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final along = x * ca + y * sa;
          final across = -x * sa + y * ca;
          final grain =
              0.5 +
              0.5 *
                  math.sin(
                    across / 3.1 +
                        4 * math.sin(along / 90) +
                        1.5 * math.sin(across / 23),
                  );
          final seam = (across % plank).abs() < 2.0 ? 0.55 : 1.0;
          final t = grain * seam;
          put(x, y, 70 + 55 * t, 42 + 38 * t, 24 + 22 * t);
        }
      }
    case Background.fabric:
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final weave = ((x ~/ 3) + (y ~/ 3)).isEven ? 14 : -14;
          final blotch = 10 * math.sin(x / 17) * math.cos(y / 23);
          put(
            x,
            y,
            92 + weave + blotch,
            98 + weave + blotch,
            116 + weave + blotch,
          );
        }
      }
    case Background.busy:
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          put(x, y, 120, 108, 96);
        }
      }
      // Clutter: rotated boxes, discs and cables in random colours.
      for (var i = 0; i < 28; i++) {
        final col = [
          40 + r.nextInt(180),
          40 + r.nextInt(180),
          40 + r.nextInt(180),
        ];
        final cx = r.nextDouble() * w;
        final cy = r.nextDouble() * h;
        final kind = r.nextInt(3);
        final s = (0.04 + r.nextDouble() * 0.12) * math.min(w, h);
        final ang = r.nextDouble() * math.pi;
        final ca = math.cos(ang);
        final sa = math.sin(ang);
        final ext = (s * 2.5).ceil();
        for (
          var y = math.max(0, cy.floor() - ext);
          y < math.min(h, cy.ceil() + ext);
          y++
        ) {
          for (
            var x = math.max(0, cx.floor() - ext);
            x < math.min(w, cx.ceil() + ext);
            x++
          ) {
            final dx = x + 0.5 - cx;
            final dy = y + 0.5 - cy;
            final u = dx * ca + dy * sa;
            final v = -dx * sa + dy * ca;
            final hit = switch (kind) {
              0 => u.abs() < s && v.abs() < s * 0.6,
              1 => dx * dx + dy * dy < s * s * 0.5,
              _ => v.abs() < 2.5 && u.abs() < s * 2.4,
            };
            if (hit) put(x, y, col[0], col[1], col[2]);
          }
        }
      }
  }
  return img;
}

/// Page texture at page coordinates (u, v) in [0, 1]².
List<int> _pageColor(double u, double v, _Spec s, int seed) {
  if (s.card) {
    if (u > 0.06 && u < 0.3 && v > 0.28 && v < 0.84) return [150, 120, 105];
    if (v < 0.18) return [60, 90, 150];
    final row = (v - 0.3) / 0.1;
    if (u > 0.36 && u < 0.92 && row >= 0 && row < 5 && row % 1 < 0.35) {
      final word = ((u - 0.36) / 0.09).floor();
      if ((word * 31 + row.floor() * 17 + seed) % 4 != 0 &&
          ((u - 0.36) / 0.09) % 1 < 0.8) {
        return [45, 50, 60];
      }
    }
    return [232, 238, 244];
  }
  if (u > 0.1 && u < 0.9 && v > 0.08 && v < 0.9) {
    if (v < 0.13) {
      if (u < 0.6 && (v - 0.08) / 0.05 < 0.6) return [30, 30, 36];
    } else {
      const pitch = 0.028;
      final row = ((v - 0.13) / pitch).floor();
      final inRow = ((v - 0.13) / pitch) % 1 < 0.33;
      final wu = u / 0.055 + (row * 0.37) % 1;
      final word = wu.floor();
      final rowEnd = 0.9 - ((row * 13 + seed) % 5) * 0.06;
      if (inRow &&
          u < rowEnd &&
          (word * 7 + row * 11 + seed) % 6 != 0 &&
          wu % 1 < 0.82) {
        return [42, 42, 48];
      }
    }
  }
  return [246, 245, 239];
}

void _drawPage(Rgb img, List<List<double>> corners, _Spec s, math.Random r) {
  final w = img.width;
  final h = img.height;
  final seed = r.nextInt(1000);
  final toPage = Homography.fromPoints(corners, [
    [0.0, 0.0],
    [1.0, 0.0],
    [1.0, 1.0],
    [0.0, 1.0],
  ]);
  // Signed-distance anti-aliasing against the four edges.
  var signedArea = 0.0;
  for (var i = 0; i < 4; i++) {
    final a = corners[i];
    final b = corners[(i + 1) % 4];
    signedArea += a[0] * b[1] - b[0] * a[1];
  }
  final orient = signedArea > 0 ? 1.0 : -1.0;
  final edges = [
    for (var i = 0; i < 4; i++)
      () {
        final a = corners[i];
        final b = corners[(i + 1) % 4];
        final len = math.sqrt(
          math.pow(b[0] - a[0], 2) + math.pow(b[1] - a[1], 2),
        );
        return [a[0], a[1], (b[0] - a[0]) / len, (b[1] - a[1]) / len];
      }(),
  ];
  var minX = w.toDouble();
  var maxX = 0.0;
  var minY = h.toDouble();
  var maxY = 0.0;
  for (final c in corners) {
    minX = math.min(minX, c[0]);
    maxX = math.max(maxX, c[0]);
    minY = math.min(minY, c[1]);
    maxY = math.max(maxY, c[1]);
  }
  final d = img.data;
  for (
    var y = math.max(0, minY.floor() - 1);
    y < math.min(h, maxY.ceil() + 1);
    y++
  ) {
    for (
      var x = math.max(0, minX.floor() - 1);
      x < math.min(w, maxX.ceil() + 1);
      x++
    ) {
      final px = x + 0.5;
      final py = y + 0.5;
      var dist = double.infinity;
      for (final e in edges) {
        final sd = orient * (e[2] * (py - e[1]) - e[3] * (px - e[0]));
        if (sd < dist) dist = sd;
      }
      final cover = (dist + 0.5).clamp(0.0, 1.0);
      if (cover <= 0) continue;
      final uv = toPage.map(px, py);
      final col = _pageColor(
        uv[0].clamp(0.0, 1.0),
        uv[1].clamp(0.0, 1.0),
        s,
        seed,
      );
      final p = (y * w + x) * 3;
      for (var k = 0; k < 3; k++) {
        d[p + k] = _c(d[p + k] * (1 - cover) + col[k] * cover);
      }
    }
  }
}

void _light(Rgb img, _Spec s, math.Random r) {
  final w = img.width;
  final h = img.height;
  final a = r.nextDouble() * 2 * math.pi;
  final gx = math.cos(a);
  final gy = math.sin(a);
  // Shadow half-plane (a hand or phone) with a soft edge.
  final sa = r.nextDouble() * 2 * math.pi;
  final sx = math.cos(sa);
  final sy = math.sin(sa);
  final sOff = (0.15 + 0.2 * r.nextDouble()) * math.min(w, h);
  final diag = math.sqrt(w * w + h * h);
  final d = img.data;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = x - w / 2;
      final dy = y - h / 2;
      final t = (dx * gx + dy * gy) / diag + 0.5; // 0..1
      var f = 1 - s.gradient * t;
      if (s.shadow) {
        final sd = dx * sx + dy * sy - sOff;
        final k = (sd / 25).clamp(0.0, 1.0);
        f *= 1 - 0.45 * k;
      }
      final p = (y * w + x) * 3;
      d[p] = _c(d[p] * f);
      d[p + 1] = _c(d[p + 1] * f);
      d[p + 2] = _c(d[p + 2] * f);
    }
  }
}

/// Radial (barrel/pincushion) distortion: output p samples the undistorted
/// scene at c + (p − c)(1 + k1·r²), r normalised by the half diagonal.
Rgb _distort(Rgb src, double k1) {
  final w = src.width;
  final h = src.height;
  final out = Rgb(w, h);
  final cx = w / 2;
  final cy = h / 2;
  final r2n = cx * cx + cy * cy;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = x + 0.5 - cx;
      final dy = y + 0.5 - cy;
      final f = 1 + k1 * (dx * dx + dy * dy) / r2n;
      final sx = (cx + dx * f - 0.5).clamp(0.0, w - 1.0);
      final sy = (cy + dy * f - 0.5).clamp(0.0, h - 1.0);
      sampleBilinear(src, sx, sy, out.data, (y * w + x) * 3);
    }
  }
  return out;
}

/// Where scene point [c] lands in the distorted image (fixed-point inverse).
List<double> _distortPoint(List<double> c, double k1, int w, int h) {
  final cx = w / 2;
  final cy = h / 2;
  final r2n = cx * cx + cy * cy;
  var px = c[0];
  var py = c[1];
  for (var i = 0; i < 20; i++) {
    final dx = px - cx;
    final dy = py - cy;
    final f = 1 + k1 * (dx * dx + dy * dy) / r2n;
    px = cx + (c[0] - cx) / f;
    py = cy + (c[1] - cy) / f;
  }
  return [px, py];
}

/// Separable 3-tap binomial blur (mild defocus).
Rgb _blur(Rgb src) {
  final w = src.width;
  final h = src.height;
  final d = src.data;
  final tmp = Uint16List(d.length);
  final row = w * 3;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = y * row + x * 3;
      final l = x > 0 ? p - 3 : p;
      final r = x < w - 1 ? p + 3 : p;
      tmp[p] = d[l] + 2 * d[p] + d[r];
      tmp[p + 1] = d[l + 1] + 2 * d[p + 1] + d[r + 1];
      tmp[p + 2] = d[l + 2] + 2 * d[p + 2] + d[r + 2];
    }
  }
  final out = Rgb(w, h);
  final o = out.data;
  for (var y = 0; y < h; y++) {
    final up = y > 0 ? -row : 0;
    final down = y < h - 1 ? row : 0;
    for (var i = y * row; i < (y + 1) * row; i++) {
      o[i] = (tmp[i + up] + 2 * tmp[i] + tmp[i + down] + 8) >> 4;
    }
  }
  return out;
}

void _noise(Rgb img, double sigma, math.Random r) {
  if (sigma <= 0) return;
  // Pre-drawn normal table indexed by a xorshift stream: fast and seeded.
  final table = Int16List(4096);
  for (var i = 0; i < table.length; i++) {
    table[i] = (_gauss(r) * sigma).round();
  }
  var x = 0x9E3779B9 ^ r.nextInt(1 << 30);
  int next() {
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    return table[x & 4095];
  }

  final d = img.data;
  for (var i = 0; i < d.length; i += 3) {
    final n = next();
    d[i] = _c(d[i] + n + (next() * 3) ~/ 10);
    d[i + 1] = _c(d[i + 1] + n);
    d[i + 2] = _c(d[i + 2] + n + (next() * 3) ~/ 10);
  }
}

// ── Scoring ─────────────────────────────────────────────────────────────────

/// Mean corner error in % of the image diagonal, best cyclic assignment.
double cornerErrorPct(Scene s, Quad q) {
  final w = s.image.width;
  final h = s.image.height;
  final gt = [
    for (final c in s.corners!)
      [c[0].clamp(0.0, w.toDouble()), c[1].clamp(0.0, h.toDouble())],
  ];
  final det = [
    for (final p in q.points) [p.x * w, p.y * h],
  ];
  var best = double.infinity;
  for (final dir in [1, -1]) {
    for (var shift = 0; shift < 4; shift++) {
      var sum = 0.0;
      for (var i = 0; i < 4; i++) {
        final g = gt[(shift + dir * i) % 4];
        sum += math.sqrt(
          math.pow(det[i][0] - g[0], 2) + math.pow(det[i][1] - g[1], 2),
        );
      }
      best = math.min(best, sum / 4);
    }
  }
  return 100 * best / math.sqrt(w * w + h * h);
}

/// A detection counts when it is confident and not garbage.
const detectedMaxErrorPct = 4.0;

class Tally {
  int n = 0;
  int detected = 0;
  int confidentWrong = 0;
  double errSum = 0; // over detected cases
  double suggestSum = 0; // over all page cases, whatever the confidence
  int pages = 0;
  final List<double> errors = [];

  double get suggestErr => pages == 0 ? double.nan : suggestSum / pages;

  double get rate => n == 0 ? 0 : detected / n;
  double get meanErr => detected == 0 ? double.nan : errSum / detected;

  void add(Scene s, DetectedQuad d) {
    n++;
    if (s.corners == null) {
      if (d.isConfident) confidentWrong++;
      return;
    }
    final e = cornerErrorPct(s, d.quad);
    pages++;
    suggestSum += e;
    if (!d.isConfident) return;
    if (e <= detectedMaxErrorPct) {
      detected++;
      errSum += e;
      errors.add(e);
    } else {
      confidentWrong++;
    }
  }
}

typedef Detector = DetectedQuad Function(Rgb image);

const casesPerCategory = 10;

/// Set DETECT_SEED_BASE to evaluate on a fresh, unseen set of scenes.
final _seedBase =
    int.tryParse(Platform.environment['DETECT_SEED_BASE'] ?? '') ?? 0;

List<Scene> buildScenes() => [
  for (final c in Category.values)
    for (var i = 0; i < casesPerCategory; i++) buildScene(c, _seedBase + i + 1),
];

Map<Category, Tally> evaluate(List<Scene> scenes, Detector detect) {
  final out = {for (final c in Category.values) c: Tally()};
  for (final s in scenes) {
    out[s.category]!.add(s, detect(s.image));
  }
  return out;
}

Tally overallInFrame(Map<Category, Tally> t) {
  final all = Tally();
  for (final e in t.entries.where((e) => e.key.inFrame)) {
    all
      ..n += e.value.n
      ..detected += e.value.detected
      ..confidentWrong += e.value.confidentWrong
      ..errSum += e.value.errSum
      ..suggestSum += e.value.suggestSum
      ..pages += e.value.pages
      ..errors.addAll(e.value.errors);
  }
  return all;
}

String _pct(double v) => '${(v * 100).toStringAsFixed(0)}%'.padLeft(5);
String _err(double v) => v.isNaN ? '    –' : v.toStringAsFixed(2).padLeft(5);

String _row(String label, Tally b, Tally n) =>
    '| ${label.padRight(18)} '
    '| ${_pct(b.rate).padLeft(8)} | ${_err(b.meanErr).padLeft(8)} '
    '| ${_err(b.suggestErr).padLeft(8)} | ${'${b.confidentWrong}/${b.n}'.padLeft(5)} '
    '| ${_pct(n.rate).padLeft(7)} | ${_err(n.meanErr).padLeft(7)} '
    '| ${_err(n.suggestErr).padLeft(7)} | ${'${n.confidentWrong}/${n.n}'.padLeft(5)} |';

/// det = confident and within 4 % · err = mean corner error of detected
/// cases · sugg = mean error of whatever quad was returned (all page cases,
/// full frame when nothing was found) · bad = confident but wrong (> 4 %, or
/// any confident quad on a scene without a page). Errors in % of diagonal.
void printTable(Map<Category, Tally> base, Map<Category, Tally> next) {
  print(
    '| case               | base det | base err | base sug | bad   '
    '| new det | new err | new sug | bad   |',
  );
  print(
    '|--------------------|----------|----------|----------|-------'
    '|---------|---------|---------|-------|',
  );
  for (final c in Category.values) {
    print(_row(c.label, base[c]!, next[c]!));
  }
  print(_row('ALL in-frame', overallInFrame(base), overallInFrame(next)));
}

void main() {
  late List<Scene> scenes;
  late Map<Category, Tally> base;
  late Map<Category, Tally> next;

  setUpAll(() {
    final sw = Stopwatch()..start();
    scenes = buildScenes();
    print(
      'synthesized ${scenes.length} scenes in ${sw.elapsedMilliseconds} ms',
    );
    sw.reset();
    base = evaluate(scenes, legacyDetectPage);
    print('legacy detector: ${sw.elapsedMilliseconds} ms total');
    sw.reset();
    next = evaluate(scenes, detectPage);
    print('new detector: ${sw.elapsedMilliseconds} ms total');
    printTable(base, next);
  });

  test('in-frame pages: ≥ 90 % detected, mean corner error < 2 %', () {
    final all = overallInFrame(next);
    expect(all.rate, greaterThanOrEqualTo(0.9));
    expect(all.meanErr, lessThan(2.0));
    // Confident garbage is worse than a miss: the UI would auto-crop it.
    expect(all.confidentWrong, lessThanOrEqualTo((all.n * 0.03).ceil()));
  });

  test('every in-frame category is mostly detected', () {
    for (final c in Category.values.where((c) => c.inFrame)) {
      expect(next[c]!.rate, greaterThanOrEqualTo(0.75), reason: c.label);
    }
  });

  test('scenes without a page stay below the accept threshold', () {
    expect(next[Category.negative]!.confidentWrong, lessThanOrEqualTo(1));
  });

  test('never worse than the legacy detector overall', () {
    final b = overallInFrame(base);
    final n = overallInFrame(next);
    expect(n.rate, greaterThanOrEqualTo(b.rate));
  });

  test(
    'detection timing on a 4000x3000 photo',
    tags: 'bench',
    timeout: const Timeout(Duration(minutes: 3)),
    () {
      final scene = buildScene(Category.wood, 99, width: 4000, height: 3000);
      // Full engine path without a native decoder: package:image decode
      // dominates, detection adds the numbers below.
      final jpeg = encodeJpeg(scene.image, 90);
      final s0 = Stopwatch()..start();
      decodeRgb(jpeg);
      print(
        'decode 4000x3000 JPEG (package:image): ${s0.elapsedMilliseconds} ms',
      );
      final s1 = Stopwatch()..start();
      legacyDetectPage(scene.image);
      final legacyMs = s1.elapsedMilliseconds;
      // Warm-up, then timed run.
      detectPage(scene.image);
      final s2 = Stopwatch()..start();
      final d = detectPage(scene.image);
      final newMs = s2.elapsedMilliseconds;
      final small = fitWithin(scene.image, 640);
      final s3 = Stopwatch()..start();
      detectPage(small);
      final smallMs = s3.elapsedMilliseconds;
      print(
        'detect 4000x3000 (decode excluded): legacy $legacyMs ms, new $newMs ms; '
        '640 px (native-decoder path): $smallMs ms; '
        'confidence ${d.confidence.toStringAsFixed(2)}, '
        'error ${cornerErrorPct(scene, d.quad).toStringAsFixed(2)} %',
      );
      expect(d.isConfident, isTrue);
      expect(newMs, lessThan(1500));
    },
  );
}

// ── Legacy detector (verbatim copy of the pre-2026-09 implementation) ───────

DetectedQuad legacyDetectPage(Rgb image, {int workSize = 320}) {
  final small = fitWithin(image, workSize);
  final w = small.width;
  final h = small.height;
  final gray = _legacyBlur3(_legacyBlur3(small.luma(), w, h), w, h);
  final t = otsuThreshold(gray);

  final bright = _legacyAnalyze(gray, w, h, (v) => v > t);
  var best = bright;
  if (bright == null || bright.bordersTouched == 4) {
    final dark = _legacyAnalyze(gray, w, h, (v) => v <= t);
    if (dark != null && (best == null || dark.confidence > best.confidence)) {
      best = dark;
    }
  }
  if (best == null) return const DetectedQuad(Quad.full, 0);
  return DetectedQuad(best.quad, best.confidence);
}

class _LegacyCandidate {
  _LegacyCandidate(this.quad, this.confidence, this.bordersTouched);

  final Quad quad;
  final double confidence;
  final int bordersTouched;
}

_LegacyCandidate? _legacyAnalyze(
  Uint8List gray,
  int w,
  int h,
  bool Function(int v) inMask,
) {
  final n = w * h;
  final labels = Int32List(n);
  final stack = Int32List(n);
  var bestLabel = 0;
  var bestArea = 0;
  var label = 0;
  for (var start = 0; start < n; start++) {
    if (labels[start] != 0 || !inMask(gray[start])) continue;
    label++;
    var area = 0;
    var sp = 0;
    stack[sp++] = start;
    labels[start] = label;
    while (sp > 0) {
      final i = stack[--sp];
      area++;
      final x = i % w;
      final y = i ~/ w;
      void visit(int j) {
        if (labels[j] == 0 && inMask(gray[j])) {
          labels[j] = label;
          stack[sp++] = j;
        }
      }

      if (x > 0) visit(i - 1);
      if (x < w - 1) visit(i + 1);
      if (y > 0) visit(i - w);
      if (y < h - 1) visit(i + w);
    }
    if (area > bestArea) {
      bestArea = area;
      bestLabel = label;
    }
  }
  if (bestLabel == 0 || bestArea < n * 0.02) return null;

  var minSum = 1 << 30;
  var maxSum = -(1 << 30);
  var minDiff = 1 << 30;
  var maxDiff = -(1 << 30);
  var tl = 0;
  var br = 0;
  var tr = 0;
  var bl = 0;
  var top = false;
  var bottom = false;
  var left = false;
  var right = false;
  for (var i = 0; i < n; i++) {
    if (labels[i] != bestLabel) continue;
    final x = i % w;
    final y = i ~/ w;
    final s = x + y;
    final d = x - y;
    if (s < minSum) (minSum, tl) = (s, i);
    if (s > maxSum) (maxSum, br) = (s, i);
    if (d > maxDiff) (maxDiff, tr) = (d, i);
    if (d < minDiff) (minDiff, bl) = (d, i);
    if (y == 0) top = true;
    if (y == h - 1) bottom = true;
    if (x == 0) left = true;
    if (x == w - 1) right = true;
  }
  NPoint pt(int i, double dx, double dy) =>
      NPoint(((i % w) + dx) / w, ((i ~/ w) + dy) / h).clamp();
  final quad = Quad(pt(tl, 0, 0), pt(tr, 1, 0), pt(br, 1, 1), pt(bl, 0, 1));
  final borders = [top, bottom, left, right].where((b) => b).length;

  final area = quad.area;
  final fill = area <= 0 ? 0.0 : (bestArea / n) / area;
  final convex = quad.isConvex;
  final areaScore = area >= 0.15 && area <= 0.98 ? 1.0 : 0.3;
  final fillScore = ((fill - 0.7) / 0.25).clamp(0.0, 1.0);
  var confidence = areaScore * fillScore * (convex ? 1.0 : 0.2);
  if (borders >= 3) confidence *= 0.5;
  return _LegacyCandidate(quad, confidence.clamp(0.0, 1.0), borders);
}

Uint8List _legacyBlur3(Uint8List src, int w, int h) {
  final out = Uint8List(src.length);
  for (var y = 0; y < h; y++) {
    final y0 = y > 0 ? y - 1 : 0;
    final y1 = y < h - 1 ? y + 1 : h - 1;
    for (var x = 0; x < w; x++) {
      final x0 = x > 0 ? x - 1 : 0;
      final x1 = x < w - 1 ? x + 1 : w - 1;
      final s =
          src[y0 * w + x0] +
          src[y0 * w + x] +
          src[y0 * w + x1] +
          src[y * w + x0] +
          src[y * w + x] +
          src[y * w + x1] +
          src[y1 * w + x0] +
          src[y1 * w + x] +
          src[y1 * w + x1];
      out[y * w + x] = s ~/ 9;
    }
  }
  return out;
}
