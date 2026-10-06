import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_vision/engine_vision.dart';
import 'package:feature_scan/src/passport_photo/photo_presets.dart';
import 'package:flutter/foundation.dart';

/// One live check, in the order hints are shown (most important first).
enum FaceCheck {
  oneFace,
  headSize,
  centred,
  level,
  facingCamera,
  eyesOpen,
  lighting,
  steady,
}

/// Tunable thresholds for the live checks.
abstract final class FaceCheckLimits {
  static const maxRollDegrees = 8.0;
  static const maxYawDegrees = 12.0;
  static const minEyeOpen = 0.4;
  static const minBrightness = 0.25;
  static const maxBrightness = 0.9;

  /// Allowed head-centre offset, as a fraction of the photo outline.
  static const centreToleranceX = 0.12;
  static const centreToleranceY = 0.1;

  /// Live head size may be a little outside the preset range: the final
  /// crop re-frames the head to the exact target.
  static const headSlackBelow = 0.85;
  static const headSlackAbove = 1.08;

  /// Max movement between analyzed frames (fraction of preview) to count as
  /// steady.
  static const maxMove = 0.025;
  static const maxResize = 0.06;

  /// Detector boxes stop around the brow; the full head is ~1.3× taller
  /// (same factor as `autoFramePortrait`).
  static const crownFactor = 1.3;
}

/// Outcome of the checks for one frame.
@immutable
class FaceCheckResult {
  const FaceCheckResult({required this.failing, required this.hint});

  static const noFrame = FaceCheckResult(
    failing: {FaceCheck.oneFace},
    hint: 'Look at the camera',
  );

  final Set<FaceCheck> failing;

  /// One friendly instruction for the most important failing check.
  final String hint;

  bool get allPass => failing.isEmpty;
  bool passes(FaceCheck c) => !failing.contains(c);
}

/// Runs every live check on [frame] against the preset [guide].
/// [previous] is the face from the previous analyzed frame (for steadiness).
FaceCheckResult evaluateFace(
  LiveFaceFrame frame,
  GuideGeometry guide, {
  LiveFace? previous,
}) {
  final failing = <FaceCheck>{};
  final hints = <FaceCheck, String>{};
  void fail(FaceCheck c, String hint) {
    failing.add(c);
    hints.putIfAbsent(c, () => hint);
  }

  final faces = frame.faces;
  if (faces.isEmpty) {
    fail(FaceCheck.oneFace, 'Look at the camera — no face found');
  } else if (faces.length > 1) {
    fail(FaceCheck.oneFace, 'Only one person should be in the photo');
  }

  final face = faces.length == 1 ? faces.single : null;
  if (face != null) {
    final m = measureHead(face.box);
    final frameRect = guide.frame;
    final ratio = m.height / frameRect.height;
    if (ratio < guide.headMin * FaceCheckLimits.headSlackBelow) {
      fail(FaceCheck.headSize, 'Move a little closer');
    } else if (ratio > guide.headMax * FaceCheckLimits.headSlackAbove) {
      fail(FaceCheck.headSize, 'Move back a little');
    }

    final targetCx = guide.oval.left + guide.oval.width / 2;
    final targetCy = guide.oval.top + guide.oval.height / 2;
    final dx = (m.centreX - targetCx) / frameRect.width;
    final dy = (m.centreY - targetCy) / frameRect.height;
    if (dy.abs() > FaceCheckLimits.centreToleranceY &&
        dx.abs() <= FaceCheckLimits.centreToleranceX) {
      fail(
        FaceCheck.centred,
        dy > 0 ? 'Lower the phone a little' : 'Raise the phone a little',
      );
    } else if (dx.abs() > FaceCheckLimits.centreToleranceX ||
        dy.abs() > FaceCheckLimits.centreToleranceY) {
      fail(FaceCheck.centred, 'Centre your face in the oval');
    }

    final roll = face.rollDegrees;
    if (roll != null && roll.abs() > FaceCheckLimits.maxRollDegrees) {
      fail(FaceCheck.level, 'Keep your head level');
    }
    final yaw = face.yawDegrees;
    if (yaw != null && yaw.abs() > FaceCheckLimits.maxYawDegrees) {
      fail(FaceCheck.facingCamera, 'Look straight at the camera');
    }
    final l = face.leftEyeOpen;
    final r = face.rightEyeOpen;
    if (l != null &&
        r != null &&
        (l < FaceCheckLimits.minEyeOpen || r < FaceCheckLimits.minEyeOpen)) {
      fail(FaceCheck.eyesOpen, 'Keep your eyes open');
    }

    if (previous != null && !_isSteady(previous.box, face.box)) {
      fail(FaceCheck.steady, 'Hold still');
    }
  }

  final b = frame.brightness;
  if (b != null && b < FaceCheckLimits.minBrightness) {
    fail(FaceCheck.lighting, 'Find more light — face a window');
  } else if (b != null && b > FaceCheckLimits.maxBrightness) {
    fail(FaceCheck.lighting, 'Too bright — avoid direct light');
  }

  if (failing.isEmpty) {
    return const FaceCheckResult(failing: {}, hint: 'Great — hold still');
  }
  final first = FaceCheck.values.firstWhere(failing.contains);
  return FaceCheckResult(failing: failing, hint: hints[first]!);
}

/// Estimated head (chin to crown) from a detector box.
({double height, double top, double centreX, double centreY}) measureHead(
  NRect box,
) {
  final h = box.height * FaceCheckLimits.crownFactor;
  final top = box.bottom - h;
  return (
    height: h,
    top: top,
    centreX: box.left + box.width / 2,
    centreY: top + h / 2,
  );
}

bool _isSteady(NRect a, NRect b) {
  final dx = (a.left + a.width / 2) - (b.left + b.width / 2);
  final dy = (a.top + a.height / 2) - (b.top + b.height / 2);
  final resize = (a.height - b.height).abs() / a.height;
  return dx.abs() <= FaceCheckLimits.maxMove &&
      dy.abs() <= FaceCheckLimits.maxMove &&
      resize <= FaceCheckLimits.maxResize;
}
