import 'dart:io';

import 'package:engine_ads/engine_ads.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

void main() {
  late FakeClock clock;
  late MemoryAdsStorage storage;

  InterstitialFrequencyCap newCap() => InterstitialFrequencyCap(
    storage: storage,
    policy: testCapPolicy,
    now: clock.call,
  );

  setUp(() {
    clock = FakeClock(DateTime(2026, 10, 7, 9));
    storage = MemoryAdsStorage();
  });

  test('nothing is allowed before the session starts', () async {
    final cap = newCap();
    expect(cap.blockReason(), CapBlock.notStarted);
    expect(await cap.registerFinishedTask(), CapBlock.notStarted);
    expect(cap.completedTasks, 0);
  });

  test("the user's first finished task ever never gets an interstitial, "
      'however long they wait', () async {
    final cap = newCap();
    await cap.startSession();
    clock.advance(const Duration(hours: 2));
    expect(await cap.registerFinishedTask(), CapBlock.firstTasks);
    // The second task may.
    expect(await cap.registerFinishedTask(), isNull);
  });

  test('the first task is remembered across app starts', () async {
    final first = newCap();
    await first.startSession();
    expect(await first.registerFinishedTask(), CapBlock.firstTasks);

    final second = newCap();
    await second.startSession();
    clock.advance(const Duration(minutes: 5));
    expect(second.completedTasks, 1);
    expect(await second.registerFinishedTask(), isNull);
  });

  test('never within the first 60 seconds of a session', () async {
    storage.state = {'tasks': 5};
    final cap = newCap();
    await cap.startSession();
    expect(await cap.registerFinishedTask(), CapBlock.warmUp);
    clock.advance(const Duration(seconds: 59));
    expect(cap.blockReason(), CapBlock.warmUp);
    clock.advance(const Duration(seconds: 1));
    expect(cap.blockReason(), isNull);
  });

  test('at least 3 minutes between two interstitials', () async {
    storage.state = {'tasks': 5};
    final cap = newCap();
    await cap.startSession();
    clock.advance(const Duration(minutes: 2));
    expect(cap.canShow, isTrue);
    await cap.recordShown();
    expect(cap.blockReason(), CapBlock.tooSoon);
    clock.advance(const Duration(minutes: 2, seconds: 59));
    expect(cap.blockReason(), CapBlock.tooSoon);
    clock.advance(const Duration(seconds: 1));
    expect(cap.blockReason(), isNull);
  });

  test('the gap also holds across an app restart', () async {
    storage.state = {'tasks': 5};
    final first = newCap();
    await first.startSession();
    clock.advance(const Duration(minutes: 2));
    await first.recordShown();

    clock.advance(const Duration(minutes: 1));
    final second = newCap();
    await second.startSession();
    clock.advance(const Duration(seconds: 61)); // past the warm-up
    expect(second.blockReason(), CapBlock.tooSoon);
    clock.advance(const Duration(minutes: 1));
    expect(second.blockReason(), isNull);
  });

  test('at most 6 per day, and the count starts again the next day', () async {
    storage.state = {'tasks': 5};
    final cap = newCap();
    await cap.startSession();
    clock.advance(const Duration(minutes: 2));
    for (var i = 0; i < 6; i++) {
      expect(cap.blockReason(), isNull, reason: 'ad ${i + 1}');
      await cap.recordShown();
      clock.advance(const Duration(minutes: 10));
    }
    expect(cap.shownToday, 6);
    expect(cap.blockReason(), CapBlock.dailyLimit);
    clock.advance(const Duration(hours: 5));
    expect(cap.blockReason(), CapBlock.dailyLimit);

    // Day rollover.
    clock.now = DateTime(2026, 10, 8, 0, 1);
    expect(cap.shownToday, 0);
    expect(cap.blockReason(), isNull);
    await cap.recordShown();
    expect(cap.shownToday, 1);
  });

  test('the daily count survives an app restart on the same day', () async {
    storage.state = {'tasks': 5};
    final first = newCap();
    await first.startSession();
    for (var i = 0; i < 6; i++) {
      clock.advance(const Duration(minutes: 10));
      await first.recordShown();
    }
    final second = newCap();
    await second.startSession();
    clock.advance(const Duration(minutes: 30));
    expect(second.blockReason(), CapBlock.dailyLimit);
  });

  test('setting the clock back never unlocks an ad early, and heals', () async {
    storage.state = {'tasks': 5};
    final cap = newCap();
    await cap.startSession();
    clock.advance(const Duration(minutes: 2));
    await cap.recordShown();

    // The phone's time is set back two hours (same day).
    clock.now = clock.now.subtract(const Duration(hours: 2));
    final fresh = newCap();
    await fresh.startSession();
    clock.advance(const Duration(seconds: 61));
    expect(fresh.blockReason(), CapBlock.tooSoon);
    // Counted from "now", not from the stored future time.
    clock.advance(const Duration(minutes: 3));
    expect(fresh.blockReason(), isNull);
  });

  test(
    'a corrupt or unreadable state file counts as a fresh install',
    () async {
      final dir = await Directory.systemTemp.createTemp('ads_cap');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/ads/state.json');
      final fileStorage = FileAdsStorage(file);
      expect(await fileStorage.read(), isEmpty);

      await fileStorage.write({'tasks': 3, 'day': '2026-10-07'});
      expect((await fileStorage.read())['tasks'], 3);

      await file.writeAsString('{not json');
      expect(await fileStorage.read(), isEmpty);
      final cap = InterstitialFrequencyCap(
        storage: fileStorage,
        policy: testCapPolicy,
        now: clock.call,
      );
      await cap.startSession();
      expect(await cap.registerFinishedTask(), CapBlock.firstTasks);
    },
  );
}
