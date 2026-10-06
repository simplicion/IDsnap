import 'dart:convert';
import 'dart:io';

/// How often a full-screen ad may appear. The numbers live in ONE place,
/// the placement policy in docscan_contracts (`ad_placement.dart`); the
/// app passes them in.
class InterstitialCapPolicy {
  const InterstitialCapPolicy({
    required this.minGap,
    required this.maxPerDay,
    required this.warmUp,
    required this.freeTasks,
  });

  /// Shortest time between two interstitials.
  final Duration minGap;

  /// Most interstitials per calendar day (the local date of the phone).
  final int maxPerDay;

  /// No interstitial this soon after the app started.
  final Duration warmUp;

  /// The first [freeTasks] finished jobs, ever, never get an interstitial.
  final int freeTasks;
}

/// Why an interstitial may not be shown right now (null = it may).
enum CapBlock { notStarted, firstTasks, warmUp, tooSoon, dailyLimit }

/// Small persistent key/value state for the cap (counters only; nothing
/// about the user or their documents).
abstract interface class AdsStorage {
  Future<Map<String, Object?>> read();

  Future<void> write(Map<String, Object?> state);
}

class MemoryAdsStorage implements AdsStorage {
  MemoryAdsStorage([Map<String, Object?>? initial]) : state = {...?initial};

  Map<String, Object?> state;

  @override
  Future<Map<String, Object?>> read() async => {...state};

  @override
  Future<void> write(Map<String, Object?> state) async =>
      this.state = {...state};
}

/// A JSON file in the app's private support directory. Unreadable or
/// corrupt state counts as a fresh install (the strictest case).
class FileAdsStorage implements AdsStorage {
  FileAdsStorage(this.file);

  final File file;

  @override
  Future<Map<String, Object?>> read() async {
    try {
      if (!file.existsSync()) return {};
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, Object?> ? decoded : {};
    } on Object {
      return {};
    }
  }

  @override
  Future<void> write(Map<String, Object?> state) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(state), flush: true);
    } on Object {
      // Counters only: losing them makes the cap stricter, never looser.
    }
  }
}

/// Decides whether an interstitial may be shown and remembers the ones
/// that were. Pure logic over an injected clock and [AdsStorage].
class InterstitialFrequencyCap {
  InterstitialFrequencyCap({
    required this.storage,
    required this.policy,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AdsStorage storage;
  final InterstitialCapPolicy policy;
  final DateTime Function() _now;

  DateTime? _sessionStart;
  String _day = '';
  int _shownToday = 0;
  DateTime? _lastShown;
  int _tasks = 0;

  /// Finished jobs counted so far, ever.
  int get completedTasks => _tasks;

  int get shownToday => _rolled().$2;

  /// Call once per app start. Idempotent.
  Future<void> startSession() async {
    if (_sessionStart != null) return;
    _sessionStart = _now();
    final state = await storage.read();
    _tasks = (state['tasks'] as num?)?.toInt() ?? 0;
    _day = state['day'] as String? ?? '';
    _shownToday = (state['shownToday'] as num?)?.toInt() ?? 0;
    final last = (state['lastShownMs'] as num?)?.toInt();
    _lastShown = last == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(last);
  }

  /// Call each time the user leaves the result of a finished job: counts
  /// the job, then says whether an interstitial may follow it (null = yes).
  Future<CapBlock?> registerFinishedTask() async {
    if (_sessionStart == null) return CapBlock.notStarted;
    _tasks++;
    await _save();
    return blockReason();
  }

  /// Null when an interstitial may be shown now.
  CapBlock? blockReason() {
    final start = _sessionStart;
    if (start == null) return CapBlock.notStarted;
    if (_tasks <= policy.freeTasks) return CapBlock.firstTasks;
    final now = _now();
    if (now.difference(start) < policy.warmUp) return CapBlock.warmUp;
    final last = _lastShown;
    if (last != null && last.isAfter(now)) {
      // The clock was set back: count the gap from now instead, so it
      // neither unlocks an ad early nor blocks them for good.
      _lastShown = now;
      return CapBlock.tooSoon;
    }
    if (last != null && now.difference(last) < policy.minGap) {
      return CapBlock.tooSoon;
    }
    if (_rolled().$2 >= policy.maxPerDay) return CapBlock.dailyLimit;
    return null;
  }

  bool get canShow => blockReason() == null;

  /// Call when an interstitial is put on screen.
  Future<void> recordShown() async {
    final (day, count) = _rolled();
    _day = day;
    _shownToday = count + 1;
    _lastShown = _now();
    await _save();
  }

  /// The date today and how many were shown today (0 after midnight).
  (String, int) _rolled() {
    final today = _dayKey(_now());
    return today == _day ? (today, _shownToday) : (today, 0);
  }

  static String _dayKey(DateTime t) {
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }

  Future<void> _save() => storage.write({
    'tasks': _tasks,
    'day': _day,
    'shownToday': _shownToday,
    'lastShownMs': _lastShown?.millisecondsSinceEpoch,
  });
}
