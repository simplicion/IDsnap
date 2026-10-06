import 'package:engine_billing/engine_billing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 1, 9);

  group('TrialTracker', () {
    test('first launch starts a 30-day trial', () async {
      final storage = MemoryBillingStorage();
      final status = await TrialTracker(storage).check(t0);
      expect(status.active, isTrue);
      expect(status.daysLeft, 30);
      expect(status.endsAt, t0.add(const Duration(days: 30)));
      expect(storage.values[TrialTracker.firstLaunchKey], isNotNull);
    });

    test('day boundaries: rounds up, 1 on the last day, 0 at the end', () {
      final s = TrialStatus(firstLaunch: t0, maxSeen: t0, now: t0);
      expect(s.at(t0.add(const Duration(minutes: 1))).daysLeft, 30);
      expect(s.at(t0.add(const Duration(days: 1))).daysLeft, 29);
      expect(s.at(t0.add(const Duration(days: 1, seconds: 1))).daysLeft, 29);
      expect(
        s.at(t0.add(const Duration(days: 29, hours: 23, minutes: 59))).daysLeft,
        1,
      );
      final end = s.at(t0.add(const Duration(days: 30)));
      expect(end.active, isFalse);
      expect(end.daysLeft, 0);
    });

    test('a later launch keeps the original start', () async {
      final storage = MemoryBillingStorage();
      await TrialTracker(storage).check(t0);
      final later = await TrialTracker(
        storage,
      ).check(t0.add(const Duration(days: 12, hours: 3)));
      expect(later.firstLaunch, t0);
      expect(later.daysLeft, 18);
    });

    test('existing install upgrading gets a fresh 30 days', () async {
      // An install from before billing has other data but no trial record.
      final storage = MemoryBillingStorage({'other.secret': 'x'});
      final status = await TrialTracker(storage).check(t0);
      expect(status.firstLaunch, t0);
      expect(status.daysLeft, 30);
    });

    test('clock set back more than 10 minutes counts as tampering', () async {
      final storage = MemoryBillingStorage();
      final tracker = TrialTracker(storage);
      await tracker.check(t0);
      await tracker.check(t0.add(const Duration(days: 5)));

      final small = await tracker.check(
        t0.add(const Duration(days: 5)).subtract(const Duration(minutes: 9)),
      );
      expect(small.clockTampered, isFalse, reason: 'within tolerance');

      final back = await tracker.check(t0.add(const Duration(days: 1)));
      expect(back.clockTampered, isTrue);
      expect(back.active, isFalse);
      expect(back.daysLeft, 0);

      // maxSeen never moves backwards; fixing the clock restores the trial.
      final fixed = await tracker.check(t0.add(const Duration(days: 6)));
      expect(fixed.clockTampered, isFalse);
      expect(fixed.daysLeft, 24);
    });

    test('an unreadable record starts a fresh trial', () async {
      final storage = _ThrowingOnceStorage();
      final status = await TrialTracker(storage).check(t0);
      expect(status.active, isTrue);
      expect(status.daysLeft, 30);
      expect(storage.deleted, contains(TrialTracker.firstLaunchKey));
    });
  });
}

class _ThrowingOnceStorage extends MemoryBillingStorage {
  var _thrown = false;
  final deleted = <String>[];

  @override
  Future<String?> read(String key) async {
    if (!_thrown) {
      _thrown = true;
      throw StateError('decryption failed');
    }
    return await super.read(key);
  }

  @override
  Future<void> delete(String key) async {
    deleted.add(key);
    await super.delete(key);
  }
}
