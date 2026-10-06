import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Repo extends Mock implements DocumentRepository, FolderRepository {}

class _Store implements SettingsStore {
  _Store(this.saved);
  AppSettings saved;

  @override
  Future<AppSettings> load() async => saved;

  @override
  Future<void> save(AppSettings s) async => saved = s;
}

class _Reminders implements ReminderScheduler {
  Result<void> permission = const Ok(null);
  Result<void> scheduleResult = const Ok(null);
  final scheduled = <String>[];
  final cancelled = <String>[];

  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<void>> requestPermission() async => permission;

  @override
  Future<Result<void>> scheduleExpiry(Document document) async {
    scheduled.add(document.id);
    return scheduleResult;
  }

  @override
  Future<Result<void>> cancel(String documentId) async {
    cancelled.add(documentId);
    return const Ok(null);
  }
}

Document _doc(String id, {DateTime? expiresAt, String? folderId}) => Document(
  id: id,
  name: id,
  format: DocumentFormat.pdf,
  relativePath: 'documents/$id.pdf',
  sizeBytes: 1,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  expiresAt: expiresAt,
  folderId: folderId,
);

void main() {
  setUpAll(() => registerFallbackValue(const DocumentQuery()));

  late _Repo repo;
  late _Reminders reminders;

  ProviderContainer container({bool on = true, bool wired = true}) {
    final c = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(
          _Store(AppSettings(expiryReminders: on)),
        ),
        documentRepositoryProvider.overrideWithValue(repo),
        if (wired) reminderSchedulerProvider.overrideWithValue(reminders),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    repo = _Repo();
    reminders = _Reminders();
    // The global listing hides locked folders; the per-folder one doesn't.
    when(() => repo.watch(const DocumentQuery())).thenAnswer(
      (_) => Stream.value([_doc('visible', expiresAt: DateTime(2030))]),
    );
    when(() => repo.watch(const DocumentQuery(folderId: 'locked'))).thenAnswer(
      (_) => Stream.value([
        _doc('hidden', expiresAt: DateTime(2031), folderId: 'locked'),
        _doc('no-expiry', folderId: 'locked'),
      ]),
    );
    when(() => repo.allFolders()).thenAnswer(
      (_) async => [
        Folder(
          id: 'locked',
          name: 'Private',
          createdAt: DateTime(2026),
          lockMode: FolderLockMode.values.last,
        ),
      ],
    );
  });

  test('resync schedules documents in locked folders too', () async {
    final c = container();
    final r = await c.read(expiryRemindersProvider).resync();
    expect(r.valueOrNull, 2);
    expect(reminders.scheduled, unorderedEquals(['visible', 'hidden']));
  });

  test('resync cancels everything when reminders are off', () async {
    final c = container(on: false);
    await c.read(settingsProvider.future);
    expect((await c.read(expiryRemindersProvider).resync()).valueOrNull, 0);
    expect(reminders.scheduled, isEmpty);
    expect(reminders.cancelled, unorderedEquals(['visible', 'hidden']));
  });

  test('scheduleFor surfaces a denied permission', () async {
    reminders.permission = const Err(
      AppFailure(FailureCode.permissionDenied, heading: 'Notifications off'),
    );
    final c = container();
    await c.read(settingsProvider.future);
    final r = await c
        .read(expiryRemindersProvider)
        .scheduleFor(_doc('x', expiresAt: DateTime(2030)));
    expect(r.failureOrNull?.title, 'Notifications off');
    expect(reminders.scheduled, isEmpty);
  });

  test('scheduleFor surfaces a scheduling failure', () async {
    reminders.scheduleResult = const Err(
      AppFailure(FailureCode.unknown, heading: 'Reminder not set'),
    );
    final c = container();
    await c.read(settingsProvider.future);
    final r = await c
        .read(expiryRemindersProvider)
        .scheduleFor(_doc('x', expiresAt: DateTime(2030)));
    expect(r.failureOrNull?.title, 'Reminder not set');
  });

  test('scheduleFor is a quiet no-op when off or not wired', () async {
    final off = container(on: false);
    await off.read(settingsProvider.future);
    final doc = _doc('x', expiresAt: DateTime(2030));
    expect(
      (await off.read(expiryRemindersProvider).scheduleFor(doc)).valueOrNull,
      isFalse,
    );
    final unwired = container(wired: false);
    await unwired.read(settingsProvider.future);
    expect(
      (await unwired.read(expiryRemindersProvider).scheduleFor(doc))
          .valueOrNull,
      isFalse,
    );
    expect(reminders.scheduled, isEmpty);
  });
}
