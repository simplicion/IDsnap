import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_reminders/engine_reminders.dart';
import 'package:flutter_test/flutter_test.dart';

Document _doc({DateTime? expiresAt, String id = 'doc-1'}) => Document(
  id: id,
  name: 'Passport',
  format: DocumentFormat.pdf,
  relativePath: 'documents/p.pdf',
  sizeBytes: 1,
  expiresAt: expiresAt,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _Backend implements NotificationsBackend {
  int inits = 0;
  final scheduled = <int, DateTime>{};
  final cancelled = <int>[];
  bool grant = true;
  Error? initError;
  Error? scheduleError;

  @override
  Future<void> init() async {
    inits++;
    if (initError case final e?) throw e;
  }

  @override
  Future<bool> requestPermission() async => grant;

  @override
  Future<void> schedule(int id, DateTime at, String title, String body) async {
    if (scheduleError case final e?) throw e;
    scheduled[id] = at;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }
}

void main() {
  final now = DateTime(2026, 9, 25, 12);

  test('plans 30 and 7 days before expiry at 10:00 local', () {
    final plans = planExpiryReminders(
      _doc(expiresAt: DateTime(2027, 3, 12)),
      now,
    );
    expect(plans.map((p) => p.daysBefore), [30, 7]);
    expect(plans[0].at, DateTime(2027, 2, 10, 10));
    expect(plans[1].at, DateTime(2027, 3, 5, 10));
    expect(plans[0].body, contains('12 Mar 2027'));
  });

  test('skips reminders already in the past', () {
    final soon = planExpiryReminders(
      _doc(expiresAt: DateTime(2026, 10, 10)),
      now,
    );
    expect(soon.map((p) => p.daysBefore), [7]);
    expect(
      planExpiryReminders(_doc(expiresAt: DateTime(2026, 9, 2)), now),
      isEmpty,
    );
    expect(planExpiryReminders(_doc(), now), isEmpty);
  });

  test('ids are stable, distinct and positive', () {
    expect(reminderId('a', 30), reminderId('a', 30));
    expect(reminderId('a', 30), isNot(reminderId('a', 7)));
    expect(reminderId('a', 30), isNot(reminderId('b', 30)));
    expect(reminderId('x' * 200, 7), greaterThanOrEqualTo(0));
  });

  test('schedule replaces earlier reminders; cancel removes them', () async {
    final backend = _Backend();
    final s = LocalReminderScheduler(
      backend: backend,
      clock: () => now,
      isSupportedPlatform: true,
    );
    final doc = _doc(expiresAt: DateTime(2027, 3, 12));
    expect((await s.scheduleExpiry(doc)).isOk, isTrue);
    expect(backend.scheduled, hasLength(2));
    await s.scheduleExpiry(doc.copyWith(expiresAt: DateTime(2026, 10, 10)));
    expect(backend.scheduled, hasLength(1));
    expect(backend.inits, 1);
    await s.cancel(doc.id);
    expect(backend.scheduled, isEmpty);
  });

  test('denied permission is an actionable failure', () async {
    final backend = _Backend()..grant = false;
    final s = LocalReminderScheduler(
      backend: backend,
      isSupportedPlatform: true,
    );
    final r = await s.requestPermission();
    expect(r.failureOrNull?.code, FailureCode.permissionDenied);
  });

  test('unsupported platform is a quiet no-op', () async {
    final backend = _Backend();
    final s = LocalReminderScheduler(
      backend: backend,
      isSupportedPlatform: false,
    );
    expect(
      (await s.scheduleExpiry(_doc(expiresAt: DateTime(2030)))).isOk,
      isTrue,
    );
    expect(backend.inits, 0);
    expect((await s.capability()).available, isFalse);
  });

  test('denied permission explains where to allow notifications', () async {
    final s = LocalReminderScheduler(
      backend: _Backend()..grant = false,
      isSupportedPlatform: true,
    );
    final f = (await s.requestPermission()).failureOrNull!;
    expect(f.title, 'Notifications are off for IDSnap');
    expect(f.recovery, contains('Settings › Apps › IDSnap › Notifications'));
  });

  test('a scheduling failure is reported with specific copy', () async {
    final backend = _Backend()..scheduleError = StateError('alarm limit');
    final s = LocalReminderScheduler(
      backend: backend,
      clock: () => now,
      isSupportedPlatform: true,
    );
    final f = (await s.scheduleExpiry(
      _doc(expiresAt: DateTime(2027, 3, 12)),
    )).failureOrNull!;
    expect(f.title, 'Reminder not set');
    expect(f.recovery, contains('expiry date is saved'));
    expect(f.nextAction, FailureAction.contactSupport);
  });

  test('a failed init is retried on the next call', () async {
    final backend = _Backend()..initError = StateError('no activity');
    final s = LocalReminderScheduler(
      backend: backend,
      clock: () => now,
      isSupportedPlatform: true,
    );
    final doc = _doc(expiresAt: DateTime(2027, 3, 12));
    expect((await s.scheduleExpiry(doc)).isOk, isFalse);
    backend.initError = null;
    expect((await s.scheduleExpiry(doc)).isOk, isTrue);
    expect(backend.inits, 2);
    expect(backend.scheduled, hasLength(2));
  });
}
