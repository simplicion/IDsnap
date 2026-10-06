import 'package:engine_billing/src/billing_storage.dart';
import 'package:flutter/foundation.dart';

/// Trial length: every feature, from the first launch of a billing-aware
/// version. No account or card.
const trialLength = Duration(days: 30);

/// How far the clock may go backwards (time-zone travel, NTP corrections)
/// before it counts as being set back.
const clockSkewTolerance = Duration(minutes: 10);

/// The persisted trial record plus what it means at [now].
@immutable
class TrialStatus {
  const TrialStatus({
    required this.firstLaunch,
    required this.maxSeen,
    required this.now,
  });

  /// First launch of this app version with billing (existing installs that
  /// upgrade start here too, so they get a full 30 days).
  final DateTime firstLaunch;

  /// Latest wall-clock time the app has seen.
  final DateTime maxSeen;
  final DateTime now;

  DateTime get endsAt => firstLaunch.add(trialLength);

  /// The clock is more than [clockSkewTolerance] behind a time the app has
  /// already seen: it was set back. The trial then counts as expired until
  /// the correct date is restored.
  bool get clockTampered => now.isBefore(maxSeen.subtract(clockSkewTolerance));

  bool get active => !clockTampered && now.isBefore(endsAt);

  /// Whole days left, rounded up: 30 right after first launch, 1 during the
  /// last 24 hours, 0 once over.
  int get daysLeft {
    if (!active) return 0;
    final left = endsAt.difference(now);
    return (left.inMicroseconds / Duration.microsecondsPerDay).ceil();
  }

  TrialStatus at(DateTime time) =>
      TrialStatus(firstLaunch: firstLaunch, maxSeen: maxSeen, now: time);
}

/// Reads and advances the trial record in [BillingStorage].
class TrialTracker {
  TrialTracker(this._storage);

  static const firstLaunchKey = 'billing.trial.first_launch';
  static const maxSeenKey = 'billing.trial.max_seen';

  final BillingStorage _storage;

  /// Loads the record (creating it on first launch) and moves `maxSeen`
  /// forward. `maxSeen` never moves backwards, so setting the clock back
  /// is detected on every later check until the clock is fixed.
  ///
  /// An unreadable record (e.g. an Android backup restored onto a new
  /// phone, whose Keystore key didn't come along) is replaced by a fresh
  /// one — the same as a reinstall.
  Future<TrialStatus> check(DateTime now) async {
    DateTime? first;
    DateTime? maxSeen;
    try {
      first = _parse(await _storage.read(firstLaunchKey));
      maxSeen = _parse(await _storage.read(maxSeenKey));
    } on Object {
      await _tryDelete(firstLaunchKey);
      await _tryDelete(maxSeenKey);
    }
    if (first == null) {
      first = now;
      maxSeen = now;
      await _tryWrite(firstLaunchKey, now);
      await _tryWrite(maxSeenKey, now);
      return TrialStatus(firstLaunch: now, maxSeen: now, now: now);
    }
    maxSeen ??= first;
    if (maxSeen.isBefore(first)) maxSeen = first;
    if (now.isAfter(maxSeen)) {
      maxSeen = now;
      await _tryWrite(maxSeenKey, now);
    }
    return TrialStatus(firstLaunch: first, maxSeen: maxSeen, now: now);
  }

  static DateTime? _parse(String? value) {
    final ms = value == null ? null : int.tryParse(value);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<void> _tryWrite(String key, DateTime value) async {
    try {
      await _storage.write(key, '${value.millisecondsSinceEpoch}');
    } on Object {
      // Keep going in memory; the next launch retries.
    }
  }

  Future<void> _tryDelete(String key) async {
    try {
      await _storage.delete(key);
    } on Object {
      // Nothing else to do.
    }
  }
}
