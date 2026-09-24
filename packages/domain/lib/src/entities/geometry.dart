import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A point in normalized image space: (0,0) top-left, (1,1) bottom-right.
@immutable
class NPoint {
  const NPoint(this.x, this.y);

  factory NPoint.fromJson(List<dynamic> j) =>
      NPoint((j[0] as num).toDouble(), (j[1] as num).toDouble());

  final double x;
  final double y;

  NPoint clamp() => NPoint(x.clamp(0, 1), y.clamp(0, 1));

  List<double> toJson() => [x, y];

  @override
  bool operator ==(Object other) =>
      other is NPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() =>
      'NPoint(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// Document corners in normalized coordinates, clockwise from top-left.
@immutable
class Quad {
  const Quad(this.topLeft, this.topRight, this.bottomRight, this.bottomLeft);

  factory Quad.fromJson(List<dynamic> j) => Quad(
    NPoint.fromJson(j[0] as List<dynamic>),
    NPoint.fromJson(j[1] as List<dynamic>),
    NPoint.fromJson(j[2] as List<dynamic>),
    NPoint.fromJson(j[3] as List<dynamic>),
  );

  /// The whole image — the identity crop.
  static const full = Quad(
    NPoint(0, 0),
    NPoint(1, 0),
    NPoint(1, 1),
    NPoint(0, 1),
  );

  final NPoint topLeft;
  final NPoint topRight;
  final NPoint bottomRight;
  final NPoint bottomLeft;

  List<NPoint> get points => [topLeft, topRight, bottomRight, bottomLeft];

  bool get isFull => this == full;

  Quad withPoint(int index, NPoint p) {
    final pts = points..[index] = p.clamp();
    return Quad(pts[0], pts[1], pts[2], pts[3]);
  }

  /// True when the four corners form a convex, non-degenerate polygon.
  bool get isConvex {
    final p = points;
    double? sign;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      final c = p[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() < 1e-6) return false;
      sign ??= cross.sign;
      if (cross.sign != sign) return false;
    }
    return true;
  }

  /// Shoelace area in normalized units (1.0 = the whole image).
  double get area {
    final p = points;
    var s = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      s += a.x * b.y - b.x * a.y;
    }
    return s.abs() / 2;
  }

  List<List<double>> toJson() => [for (final p in points) p.toJson()];

  @override
  bool operator ==(Object other) =>
      other is Quad &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);
}

/// Axis-aligned crop rectangle in normalized coordinates.
@immutable
class NRect {
  const NRect(this.left, this.top, this.width, this.height);

  factory NRect.fromJson(List<dynamic> j) => NRect(
    (j[0] as num).toDouble(),
    (j[1] as num).toDouble(),
    (j[2] as num).toDouble(),
    (j[3] as num).toDouble(),
  );

  static const full = NRect(0, 0, 1, 1);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  /// Largest rect with [aspect] (w/h, in pixels) centered in an image of
  /// [imageWidth] x [imageHeight].
  static NRect centeredWithAspect(
    double aspect,
    int imageWidth,
    int imageHeight,
  ) {
    final imgAspect = imageWidth / imageHeight;
    if (imgAspect > aspect) {
      final w = aspect / imgAspect;
      return NRect((1 - w) / 2, 0, w, 1);
    }
    final h = imgAspect / aspect;
    return NRect(0, (1 - h) / 2, 1, h);
  }

  List<double> toJson() => [left, top, width, height];

  @override
  bool operator ==(Object other) =>
      other is NRect &&
      other.left == left &&
      other.top == top &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}

/// Result of automatic page detection.
@immutable
class DetectedQuad {
  const DetectedQuad(this.quad, this.confidence);

  final Quad quad;

  /// 0..1. Below [DetectedQuad.acceptThreshold] the UI must ask the user to
  /// confirm corners instead of auto-cropping (PRD FR-02).
  final double confidence;

  static const acceptThreshold = 0.6;

  bool get isConfident => confidence >= acceptThreshold;
}

double distance(NPoint a, NPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
