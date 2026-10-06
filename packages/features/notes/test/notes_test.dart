import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_notes/feature_notes.dart';
import 'package:feature_notes/src/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// In-memory repository with the same rules as the Drift one.
class _Repo implements NotesRepository {
  final notes = <String, Note>{};
  final _changes = StreamController<void>.broadcast();
  int _n = 0;
  int saves = 0;

  void _emit() => _changes.add(null);

  List<Note> _query(String search) {
    final q = search.trim().toLowerCase();
    final out =
        [
          for (final n in notes.values)
            if (q.isEmpty ||
                (!n.isLocked &&
                    '${n.title}\n${n.body}\n${n.tag ?? ''}'
                        .toLowerCase()
                        .contains(q)))
              n,
        ]..sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
    return out;
  }

  @override
  Stream<List<Note>> watch({String search = ''}) async* {
    yield _query(search);
    await for (final _ in _changes.stream) {
      yield _query(search);
    }
  }

  @override
  Future<Note?> byId(String id) async => notes[id];

  @override
  Future<List<Note>> all() async => notes.values.toList();

  Note seed({
    required String title,
    String body = '',
    FolderLockMode lockMode = FolderLockMode.none,
  }) {
    final t = DateTime(2026, 1, 1, 0, _n);
    final note = Note(
      id: 'n${_n++}',
      title: title,
      body: body,
      lockMode: lockMode,
      createdAt: t,
      updatedAt: t,
    );
    return notes[note.id] = note;
  }

  @override
  Future<Result<Note>> create({
    String title = '',
    String body = '',
    String? tag,
    NoteTemplate template = NoteTemplate.custom,
  }) async {
    final note = seed(title: title, body: body).copyWith(template: template);
    notes[note.id] = note;
    _emit();
    return Ok(note);
  }

  @override
  Future<Result<void>> save(Note note) async {
    if (!notes.containsKey(note.id)) {
      return const Err(AppFailure(FailureCode.notFound));
    }
    saves++;
    notes[note.id] = notes[note.id]!.copyWith(
      title: note.title,
      body: note.body,
      tag: note.tag,
      clearTag: note.tag == null,
    );
    _emit();
    return const Ok(null);
  }

  @override
  Future<Result<void>> setPinned(String id, {required bool pinned}) async {
    notes[id] = notes[id]!.copyWith(pinned: pinned);
    _emit();
    return const Ok(null);
  }

  @override
  Future<Result<void>> setLockMode(String id, FolderLockMode mode) async {
    notes[id] = notes[id]!.copyWith(lockMode: mode);
    _emit();
    return const Ok(null);
  }

  @override
  Future<Result<void>> delete(String id) async {
    notes.remove(id);
    _emit();
    return const Ok(null);
  }

  @override
  Future<Result<bool>> restore(Note note) async => const Ok(false);
}

class _Pins implements FolderPinStore {
  final pins = <String, String>{};

  @override
  Future<bool> hasPin(String folderId) async => pins.containsKey(folderId);

  @override
  Future<void> removePin(String folderId) async => pins.remove(folderId);

  @override
  Future<Duration?> retryAfter(String folderId) async => null;

  @override
  Future<Result<void>> setPin(String folderId, String pin) async {
    pins[folderId] = pin;
    return const Ok(null);
  }

  @override
  Future<Result<PinCheck>> verifyPin(String folderId, String pin) async => Ok(
    pins[folderId] == pin
        ? const PinAccepted()
        : const PinRejected(attemptsLeft: 4),
  );
}

class _Lock implements AppLock {
  bool result = true;
  int prompts = 0;

  @override
  Future<Result<bool>> authenticate(String reason) async {
    prompts++;
    return Ok(result);
  }

  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: true, worksOffline: true);
}

class _Clipboard implements ClipboardAccess {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String text) async => value = text;
}

class _Harness {
  final repo = _Repo();
  final pins = _Pins();
  final lock = _Lock();
  final clipboard = _Clipboard();
  final secure = <bool>[];
  EntitlementState entitlement = const MonthlyEntitlement();

  Widget app() {
    final root = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: root,
      initialLocation: Routes.notes,
      routes: [
        GoRoute(
          path: Routes.notes,
          builder: (_, _) => const NotesScreen(),
          routes: notesRoutes(root),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        notesRepositoryProvider.overrideWithValue(repo),
        // A paid mode: the default build is free with ads (ADR-0013).
        monetizationModeProvider.overrideWithValue(MonetizationMode.licence),
        entitlementServiceProvider.overrideWithValue(
          StaticEntitlementService(entitlement),
        ),
        notePinStoreProvider.overrideWithValue(pins),
        appLockProvider.overrideWithValue(lock),
        notesClipboardAccessProvider.overrideWithValue(clipboard),
        notesSecureFlagProvider.overrideWithValue(
          NotesSecureFlag(({required enabled}) async {
            secure.add(enabled);
          }, () => false),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }
}

void main() {
  testWidgets('"New note" shows the PRO badge only when creating is locked', (
    tester,
  ) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.text('PRO'), findsNothing, reason: 'entitled: no badge');

    final locked = _Harness()
      ..entitlement = const ExpiredEntitlement(reason: LapseReason.trialEnded);
    await tester.pumpWidget(Container());
    await tester.pumpWidget(locked.app());
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.text('PRO'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('create a note from a template; edits autosave', (tester) async {
    final h = _Harness();
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.text('No notes yet'), findsOneWidget);
    expect(h.secure, [true], reason: 'FLAG_SECURE on the notes screen');

    await tester.tap(find.text('New note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wi-Fi password'));
    await tester.pumpAndSettle();

    final note = h.repo.notes.values.single;
    expect(note.template, NoteTemplate.wifi);
    expect(find.textContaining('Network name:'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('note-title')), 'Home Wi-Fi');
    await tester.enterText(find.byKey(const Key('note-tag')), 'Home');
    expect(h.repo.saves, 0, reason: 'debounced');
    await tester.pump(const Duration(seconds: 1));
    expect(h.repo.notes[note.id]!.title, 'Home Wi-Fi');
    expect(h.repo.notes[note.id]!.tag, 'Home');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Home Wi-Fi'), findsOneWidget);
  });

  testWidgets('checklist items toggle in the body', (tester) async {
    final h = _Harness();
    final note = h.repo.seed(title: 'Codes', body: '- [ ] first\n- [x] second');
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Codes'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'first'));
    await tester.pump(const Duration(seconds: 1));
    expect(h.repo.notes[note.id]!.body, '- [x] first\n- [x] second');
  });

  testWidgets('lock a note with a PIN, then unlock it from the list', (
    tester,
  ) async {
    final h = _Harness();
    final note = h.repo.seed(title: 'Bank', body: 'Account number: 998877');
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Lock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A PIN for this note'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.enterText(find.byType(TextField).last, '2468');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }
    expect(h.repo.notes[note.id]!.lockMode, FolderLockMode.pin);
    expect(h.pins.pins[notePinKey(note.id)], '2468');
    expect(find.text('Note locked'), findsOneWidget);

    // A new session: nothing is unlocked.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.text('Bank'), findsOneWidget);
    expect(find.textContaining('Locked'), findsOneWidget);
    expect(find.textContaining('998877'), findsNothing, reason: 'no preview');

    await tester.tap(find.text('Bank'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('note-pin')), '0000');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Wrong PIN. Try again.'), findsOneWidget);
    expect(find.textContaining('998877'), findsNothing);

    await tester.enterText(find.byKey(const Key('note-pin')), '2468');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.textContaining('998877'), findsOneWidget);
  });

  testWidgets('a device-locked note asks the phone; a refusal keeps it shut', (
    tester,
  ) async {
    final h = _Harness()..lock.result = false;
    h.repo.seed(
      title: 'PIN hint',
      body: 'top secret',
      lockMode: FolderLockMode.device,
    );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('PIN hint'));
    await tester.pumpAndSettle();
    expect(h.lock.prompts, 1);
    expect(find.textContaining('top secret'), findsNothing);

    h.lock.result = true;
    await tester.tap(find.text('PIN hint'));
    await tester.pumpAndSettle();
    expect(find.textContaining('top secret'), findsOneWidget);
  });

  testWidgets('search never matches locked notes', (tester) async {
    final h = _Harness();
    h.repo
      ..seed(title: 'Router', body: 'password: tiger')
      ..seed(
        title: 'Safe',
        body: 'password: tiger',
        lockMode: FolderLockMode.pin,
      );
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    expect(find.text('Router'), findsOneWidget);
    expect(find.text('Safe'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('notes-search')), 'tiger');
    await tester.pumpAndSettle();
    expect(find.text('Router'), findsOneWidget);
    expect(find.text('Safe'), findsNothing);

    await tester.enterText(find.byKey(const Key('notes-search')), 'Safe');
    await tester.pumpAndSettle();
    expect(find.text('No matching notes'), findsOneWidget);
  });

  testWidgets('copy clears the clipboard after 60 s, unless it changed', (
    tester,
  ) async {
    final h = _Harness();
    h.repo.seed(title: 'Key', body: 'ABCD-1234');
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Key'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    expect(h.clipboard.value, 'Key\nABCD-1234');
    expect(find.textContaining('clears in 60 seconds'), findsOneWidget);
    await tester.pump(const Duration(seconds: 59));
    expect(h.clipboard.value, 'Key\nABCD-1234');
    await tester.pump(const Duration(seconds: 2));
    expect(h.clipboard.value, '');

    // Something the user copied afterwards is never wiped.
    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    h.clipboard.value = 'mine';
    await tester.pump(const Duration(seconds: 61));
    expect(h.clipboard.value, 'mine');
  });

  testWidgets('pin moves a note to the top; delete asks first', (tester) async {
    final h = _Harness();
    h.repo
      ..seed(title: 'Older')
      ..seed(title: 'Newer');
    await tester.pumpWidget(h.app());
    await tester.pumpAndSettle();
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('Newer') < y('Older'), isTrue);
    await tester.tap(find.byTooltip('Pin').last);
    await tester.pumpAndSettle();
    expect(y('Older') < y('Newer'), isTrue);

    await tester.tap(find.text('Newer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(h.repo.notes, hasLength(2), reason: 'confirmation first');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(h.repo.notes.values.single.title, 'Older');
    expect(find.text('Newer'), findsNothing);
  });

  test('templates are generic and checklist lines parse', () {
    expect(NoteTemplate.values.map((t) => t.name), [
      'custom',
      'wifi',
      'bankAccount',
      'cardPin',
      'recovery',
      'licence',
    ]);
    expect(ChecklistLine.parse('- [x] done')?.checked, isTrue);
    expect(ChecklistLine.parse('plain'), isNull);
    expect(ChecklistLine.toggle('a\n- [ ] b', 1), 'a\n- [x] b');
    final locked = Note(
      id: '1',
      title: '',
      body: 'secret',
      lockMode: FolderLockMode.device,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(locked.preview, isEmpty);
    expect(locked.displayTitle, 'Untitled note');
  });
}
