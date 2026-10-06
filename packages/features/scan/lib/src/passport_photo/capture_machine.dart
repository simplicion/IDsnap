import 'package:flutter/foundation.dart';

/// What the auto-capture is doing right now.
sealed class CapturePhase {
  const CapturePhase();
}

/// Checks are failing (or no frame yet).
final class Searching extends CapturePhase {
  const Searching();
}

/// Every check passes; waiting for the dwell time. [progress] is 0..1.
@immutable
final class Holding extends CapturePhase {
  const Holding(this.progress);
  final double progress;

  @override
  bool operator ==(Object other) =>
      other is Holding && other.progress == progress;
  @override
  int get hashCode => progress.hashCode;
}

/// 3-2-1 countdown; [secondsLeft] is what the UI shows.
@immutable
final class Countdown extends CapturePhase {
  const Countdown(this.secondsLeft);
  final int secondsLeft;

  @override
  bool operator ==(Object other) =>
      other is Countdown && other.secondsLeft == secondsLeft;
  @override
  int get hashCode => secondsLeft.hashCode;
}

/// The countdown finished: take the photo now. Emitted once.
final class Fire extends CapturePhase {
  const Fire();
}

/// Auto-capture is off (user cancelled or detection unavailable); only the
/// shutter button takes photos.
final class Manual extends CapturePhase {
  const Manual();
}

/// Pure auto-capture logic, driven by check results and timestamps (no
/// timers), so it is fully testable.
///
/// - All checks must pass continuously for [dwell] before the countdown.
/// - Any failing frame before the countdown resets the dwell.
/// - During the countdown, checks may fail briefly (a blink) for up to
///   [countdownGrace]; longer failures cancel it back to [Searching].
class CaptureMachine {
  CaptureMachine({
    this.dwell = const Duration(milliseconds: 800),
    this.countdown = const Duration(seconds: 3),
    this.countdownGrace = const Duration(milliseconds: 400),
    bool autoEnabled = true,
  }) : _auto = autoEnabled,
       _phase = autoEnabled ? const Searching() : const Manual();

  final Duration dwell;
  final Duration countdown;
  final Duration countdownGrace;

  bool _auto;
  CapturePhase _phase;
  DateTime? _passSince;
  DateTime? _countdownStart;
  DateTime? _failSince;

  CapturePhase get phase => _phase;
  bool get autoEnabled => _auto;

  /// Feeds the checks for one analyzed frame.
  CapturePhase onChecks({required bool allPass, required DateTime now}) {
    if (!_auto || _phase is Fire) return _phase;
    if (_phase is Countdown) {
      if (allPass) {
        _failSince = null;
      } else {
        _failSince ??= now;
        if (now.difference(_failSince!) > countdownGrace) {
          return _phase = _searching();
        }
      }
      return tick(now);
    }
    if (!allPass) return _phase = _searching();
    final since = _passSince ??= now;
    final held = now.difference(since);
    if (held >= dwell) {
      _countdownStart = now;
      _failSince = null;
      return _phase = Countdown(_secondsLeft(Duration.zero));
    }
    return _phase = Holding(
      (held.inMicroseconds / dwell.inMicroseconds).clamp(0.0, 1.0),
    );
  }

  /// Advances the countdown clock (call periodically while counting down).
  CapturePhase tick(DateTime now) {
    final start = _countdownStart;
    if (_phase is! Countdown || start == null) return _phase;
    final elapsed = now.difference(start);
    if (elapsed >= countdown) {
      _countdownStart = null;
      return _phase = const Fire();
    }
    return _phase = Countdown(_secondsLeft(elapsed));
  }

  int _secondsLeft(Duration elapsed) {
    final left = countdown - elapsed;
    return (left.inMilliseconds / 1000).ceil().clamp(1, 99);
  }

  /// User cancelled the countdown: auto-capture turns off until re-enabled.
  void cancel() => setAuto(enabled: false);

  /// Turns auto-capture on or off; either way the dwell starts over.
  void setAuto({required bool enabled}) {
    _auto = enabled;
    _phase = enabled ? _searching() : _manual();
  }

  /// After a capture (or retake): start over, keeping the auto setting.
  void reset() => _phase = _auto ? _searching() : _manual();

  CapturePhase _searching() {
    _passSince = null;
    _countdownStart = null;
    _failSince = null;
    return const Searching();
  }

  CapturePhase _manual() {
    _searching();
    return const Manual();
  }

  @visibleForTesting
  DateTime? get passSince => _passSince;
}
