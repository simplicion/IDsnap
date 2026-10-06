import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_library/feature_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  setUp(secureCalls.clear);

  List<Document> sampleDocs() => [
    doc('p', 'My passport', DocumentFormat.pdf, folderId: 'ids'),
    doc('m', 'Blood report', DocumentFormat.pdf, folderId: 'med'),
    doc('s', 'Secret deed', DocumentFormat.pdf, folderId: 'priv'),
    doc('x', 'Loose note', DocumentFormat.txt),
  ];

  List<Folder> sampleFolders() => [
    folder('ids', 'IDs & Proofs', templateKey: 'ids'),
    folder('pass', 'Passport', parentId: 'ids'),
    folder('med', 'Medical & Health'),
    folder('priv', 'Private', lockMode: FolderLockMode.pin),
    folder('inner', 'Inner', parentId: 'priv'),
  ];

  Future<void> pumpRouted(
    WidgetTester tester,
    FakeRepository repo, {
    String at = '/files',
    FolderPinStore? pins,
    AppLock? appLock,
    List<Override> extra = const [],
  }) async {
    useTallPhone(tester);
    await tester.pumpWidget(
      routedHarness(
        initialLocation: at,
        overrides: [
          ...baseOverrides(repo, FakeFileStore(), pins: pins, appLock: appLock),
          ...extra,
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  group('vault root', () {
    testWidgets('shows user folders with counts and loose files; nothing '
        'hardcoded', (tester) async {
      await pumpRouted(
        tester,
        FakeRepository(sampleDocs(), folders: sampleFolders()),
      );
      expect(find.text('ID Vault'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Folder IDs & Proofs, 1 file · 1 folder'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Folder Medical & Health, 1 file'),
        findsOneWidget,
      );
      // A locked folder shows no count.
      expect(find.bySemanticsLabel('Folder Private, Locked'), findsOneWidget);
      expect(find.text('Loose note'), findsOneWidget);
      // Files inside folders are not listed at the top level.
      expect(find.text('My passport'), findsNothing);
      expect(
        find.text('Offline vault · Your documents never leave this phone'),
        findsOneWidget,
      );
    });

    testWidgets('an empty vault suggests creating a folder', (tester) async {
      await pumpRouted(tester, FakeRepository([]));
      expect(find.text('Your vault is empty'), findsOneWidget);
      // No preset folders are created on their own.
      expect(find.text('IDs & Proofs'), findsNothing);
      await tester.tap(find.text('Create a folder'));
      await tester.pumpAndSettle();
      expect(find.text('Custom…'), findsOneWidget);
    });

    testWidgets('privacy banner can be dismissed for the session', (
      tester,
    ) async {
      await pumpRouted(tester, FakeRepository([]));
      await tester.tap(find.byTooltip('Hide for now'));
      await tester.pumpAndSettle();
      expect(
        find.text('Offline vault · Your documents never leave this phone'),
        findsNothing,
      );
    });
  });

  group('+ menu', () {
    testWidgets('a template creates the folder', (tester) async {
      final repo = FakeRepository([]);
      await pumpRouted(tester, repo);
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Upload files'), findsOneWidget);
      expect(find.text('Scan document'), findsOneWidget);
      await tester.tap(find.text('New folder'));
      await tester.pumpAndSettle();
      for (final t in FolderTemplate.all) {
        expect(find.text(t.label), findsOneWidget, reason: t.label);
      }
      await tester.tap(find.text('Travel'));
      await tester.pumpAndSettle();
      final created = repo.folders.single;
      expect(created.name, 'Travel');
      expect(created.templateKey, 'travel');
      expect(created.icon, FolderIcons.travel);
      expect(created.parentId, isNull);
      expect(find.text('Folder "Travel" created'), findsOneWidget);
      expect(find.bySemanticsLabel('Folder Travel, Empty'), findsOneWidget);
    });

    testWidgets('templates already present are marked, not duplicated', (
      tester,
    ) async {
      final repo = FakeRepository([], folders: [folder('ids', 'IDs & Proofs')]);
      await pumpRouted(tester, repo);
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New folder'));
      await tester.pumpAndSettle();
      expect(find.text('Already here'), findsOneWidget);
    });

    testWidgets('custom name is validated, then created', (tester) async {
      final repo = FakeRepository([], folders: [folder('w', 'Work')]);
      await pumpRouted(tester, repo);
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom…'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a folder name'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('folder-name')), 'work');
      await tester.pumpAndSettle();
      expect(
        find.text('A folder with this name already exists here'),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('folder-name')),
        '  Family   papers ',
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(repo.folders.map((f) => f.name), contains('Family papers'));
    });

    testWidgets('upload imports picked files into the current folder', (
      tester,
    ) async {
      final repo = FakeRepository([], folders: sampleFolders());
      final picker = FakeMediaPicker(const [
        PickedFile(path: '/pick/a.pdf', name: 'Lease.pdf'),
        PickedFile(path: '/pick/b.txt', name: 'Notes.txt'),
        PickedFile(path: '/pick/c.zip', name: 'Backup.zip'),
      ]);
      final commit = FakeCommit(repo);
      final discarded = <String>[];
      useTallPhone(tester);
      await tester.pumpWidget(
        routedHarness(
          initialLocation: '/files/folder/med',
          overrides: [
            importedSourceDisposerProvider.overrideWithValue(
              (path) async => discarded.add(path),
            ),
            ...baseOverrides(
              repo,
              FakeFileStore(
                texts: {
                  '/pick/a.pdf': '%PDF-1.7 lease',
                  '/pick/b.txt': 'hello',
                  '/pick/c.zip': 'PK\u0003\u0004zip',
                },
              ),
            ),
            mediaPickerProvider.overrideWithValue(picker),
            commitOutputProvider.overrideWithValue(commit),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload files'));
      await tester.pumpAndSettle();

      expect(picker.multiple, isTrue);
      expect(
        picker.requested,
        containsAll([DocumentFormat.pdf, DocumentFormat.jpeg]),
      );
      expect(commit.commits.map((c) => (c.name, c.format, c.folderId)), [
        ('Lease', DocumentFormat.pdf, 'med'),
        ('Notes', DocumentFormat.txt, 'med'),
      ]);
      expect(find.textContaining('2 added, 1 not added'), findsOneWidget);
      expect(find.text('Lease'), findsOneWidget);
      // Imported sources are handed back for shredding; the rejected file
      // was never imported, so it is left for the user.
      expect(discarded, ['/pick/a.pdf', '/pick/b.txt']);
    });

    testWidgets('scan opens the scanner for the current folder', (
      tester,
    ) async {
      await pumpRouted(
        tester,
        FakeRepository([], folders: sampleFolders()),
        at: '/files/folder/med',
      );
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan document'));
      await tester.pumpAndSettle();
      expect(find.text('scan med'), findsOneWidget);
    });
  });

  group('nested folders', () {
    testWidgets('open folders at any depth with a breadcrumb', (tester) async {
      final repo = FakeRepository(sampleDocs(), folders: sampleFolders());
      await pumpRouted(tester, repo);
      await tester.tap(find.text('IDs & Proofs'));
      await tester.pumpAndSettle();
      // Subfolders first, then files.
      expect(find.text('Passport'), findsOneWidget);
      expect(find.text('My passport'), findsOneWidget);
      final folderY = tester.getTopLeft(find.text('Passport')).dy;
      final fileY = tester.getTopLeft(find.text('My passport')).dy;
      expect(folderY, lessThan(fileY));

      // Create a subfolder: the parent template's suggestions come first.
      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New folder'));
      await tester.pumpAndSettle();
      expect(find.text('Suggested for IDs & Proofs'), findsOneWidget);
      await tester.tap(find.text('Driving licence'));
      await tester.pumpAndSettle();
      final dl = repo.folders.firstWhere((f) => f.name == 'Driving licence');
      expect(dl.parentId, 'ids');

      await tester.tap(find.text('Passport'));
      await tester.pumpAndSettle();
      expect(find.text('This folder is empty'), findsOneWidget);
      // Breadcrumb: ID Vault › IDs & Proofs › Passport.
      expect(find.widgetWithText(TextButton, 'ID Vault'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'IDs & Proofs'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'IDs & Proofs'));
      await tester.pumpAndSettle();
      expect(find.text('My passport'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'ID Vault'));
      await tester.pumpAndSettle();
      expect(find.text('Loose note'), findsOneWidget);
    });

    testWidgets('delete a folder, moving its contents to the parent', (
      tester,
    ) async {
      final repo = FakeRepository(sampleDocs(), folders: sampleFolders());
      await pumpRouted(tester, repo);
      await tester.longPress(find.text('IDs & Proofs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete folder'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 file · 1 folder'), findsWidgets);
      await tester.tap(find.text('Move them to ID Vault'));
      await tester.pumpAndSettle();
      expect(repo.folders.any((f) => f.id == 'ids'), isFalse);
      expect(repo.tree['pass']!.parentId, isNull);
      expect((await repo.byId('p'))?.folderId, isNull);
      expect(find.text('My passport'), findsOneWidget);
    });

    testWidgets('delete everything removes files too', (tester) async {
      final repo = FakeRepository(sampleDocs(), folders: sampleFolders());
      await pumpRouted(tester, repo);
      await tester.longPress(find.text('Medical & Health'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete everything'));
      await tester.pumpAndSettle();
      expect(await repo.byId('m'), isNull);
      expect(repo.folders.any((f) => f.id == 'med'), isFalse);
    });

    testWidgets('move a file to another folder', (tester) async {
      final repo = FakeRepository(sampleDocs(), folders: sampleFolders());
      await pumpRouted(tester, repo);
      await tester.tap(find.byTooltip('More actions for Loose note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('IDs & Proofs').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to IDs & Proofs'));
      await tester.pumpAndSettle();
      expect((await repo.byId('x'))?.folderId, 'ids');
    });
  });

  group('folder lock', () {
    Future<FolderPinStore> pinsWith(WidgetTester tester, String pin) async {
      final pins = testPinStore();
      await tester.runAsync(() => pins.setPin('priv', pin));
      return pins;
    }

    testWidgets('PIN: wrong PIN is refused, right PIN shows contents', (
      tester,
    ) async {
      final pins = await pinsWith(tester, '2468');
      await pumpRouted(
        tester,
        FakeRepository(sampleDocs(), folders: sampleFolders()),
        pins: pins,
      );
      await tester.tap(find.text('Private'));
      await tester.pumpAndSettle();
      // The prompt opens by itself; nothing inside is visible behind it.
      expect(find.text('Unlock "Private"'), findsOneWidget);
      expect(find.text('Secret deed'), findsNothing);
      expect(find.text('Inner'), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('folder-pin')), '1111');
      await tester.tap(find.byKey(const ValueKey('pin-unlock')));
      await tester.pumpAndSettle();
      expect(find.text('Wrong PIN. Try again.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('folder-pin')), '2468');
      await tester.tap(find.byKey(const ValueKey('pin-unlock')));
      await tester.pumpAndSettle();
      expect(find.text('Secret deed'), findsOneWidget);
      // Nested folders inherit access.
      expect(find.text('Inner'), findsOneWidget);
      await tester.tap(find.text('Inner'));
      await tester.pumpAndSettle();
      expect(find.text('This folder is empty'), findsOneWidget);
      // FLAG_SECURE while inside a locked folder.
      expect(secureCalls, contains(true));
    });

    testWidgets('PIN: cancelling keeps the folder hidden', (tester) async {
      final pins = await pinsWith(tester, '2468');
      await pumpRouted(
        tester,
        FakeRepository(sampleDocs(), folders: sampleFolders()),
        pins: pins,
        at: '/files/folder/priv',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('"Private" is locked'), findsOneWidget);
      expect(find.text('Secret deed'), findsNothing);
      expect(
        find.textContaining('already encrypted on this phone'),
        findsOneWidget,
      );
    });

    testWidgets('PIN: five wrong tries start a delay', (tester) async {
      final pins = await pinsWith(tester, '2468');
      await pumpRouted(
        tester,
        FakeRepository(sampleDocs(), folders: sampleFolders()),
        pins: pins,
        at: '/files/folder/priv',
      );
      for (var i = 0; i < 5; i++) {
        await tester.enterText(
          find.byKey(const ValueKey('folder-pin')),
          '0000',
        );
        await tester.tap(find.byKey(const ValueKey('pin-unlock')));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('Too many attempts'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('PIN: forgot PIN resets after device authentication', (
      tester,
    ) async {
      final pins = await pinsWith(tester, '2468');
      final lock = FakeAppLock();
      await pumpRouted(
        tester,
        FakeRepository(sampleDocs(), folders: sampleFolders()),
        pins: pins,
        appLock: lock,
        at: '/files/folder/priv',
      );
      await tester.tap(find.text('Forgot PIN?'));
      await tester.pumpAndSettle();
      expect(lock.prompts, 1);
      await tester.enterText(find.byKey(const ValueKey('new-pin')), '97531');
      await tester.enterText(
        find.byKey(const ValueKey('confirm-pin')),
        '97531',
      );
      await tester.tap(find.text('Save PIN'));
      await tester.pumpAndSettle();
      expect(find.text('Secret deed'), findsOneWidget);
      final check = await tester.runAsync(
        () => pins.verifyPin('priv', '97531'),
      );
      expect(check?.valueOrNull, isA<PinAccepted>());
    });

    testWidgets('device lock uses the phone prompt', (tester) async {
      final lock = FakeAppLock(result: false);
      final folders = [folder('dev', 'Bank', lockMode: FolderLockMode.device)];
      final docs = [doc('b', 'Statement', DocumentFormat.pdf, folderId: 'dev')];
      await pumpRouted(
        tester,
        FakeRepository(docs, folders: folders),
        appLock: lock,
        at: '/files/folder/dev',
      );
      expect(lock.prompts, 1);
      expect(find.text('"Bank" is locked'), findsOneWidget);
      lock.result = true;
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Statement'), findsOneWidget);
    });

    testWidgets('going to the background locks folders again', (tester) async {
      final lock = FakeAppLock();
      await pumpRouted(
        tester,
        FakeRepository(
          [doc('b', 'Statement', DocumentFormat.pdf, folderId: 'dev')],
          folders: [folder('dev', 'Bank', lockMode: FolderLockMode.device)],
        ),
        appLock: lock,
        at: '/files/folder/dev',
      );
      expect(find.text('Statement'), findsOneWidget);
      final binding = tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Statement'), findsNothing);
      expect(find.text('"Bank" is locked'), findsOneWidget);
    });

    testWidgets('lock a folder with a PIN from its menu', (tester) async {
      final pins = testPinStore();
      final repo = FakeRepository([], folders: [folder('w', 'Work')]);
      await pumpRouted(tester, repo, pins: pins);
      await tester.tap(find.byTooltip('Folder actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lock folder'));
      await tester.pumpAndSettle();
      expect(find.text(folderLockExplainer), findsOneWidget);
      await tester.tap(find.text('PIN for this folder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('new-pin')), '12');
      await tester.tap(find.text('Save PIN'));
      await tester.pumpAndSettle();
      expect(find.text('Use 4 to 8 digits'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('new-pin')), '1234');
      await tester.enterText(find.byKey(const ValueKey('confirm-pin')), '1235');
      await tester.tap(find.text('Save PIN'));
      await tester.pumpAndSettle();
      expect(find.text("PINs don't match"), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('confirm-pin')), '1234');
      await tester.tap(find.text('Save PIN'));
      await tester.pumpAndSettle();
      expect(repo.tree['w']!.lockMode, FolderLockMode.pin);
      expect(await tester.runAsync(() => pins.hasPin('w')), isTrue);
    });

    testWidgets('search never shows what a locked folder holds', (
      tester,
    ) async {
      await pumpRouted(
        tester,
        FakeRepository([
          ...sampleDocs(),
          doc('s2', 'Secret recipe', DocumentFormat.txt),
        ], folders: sampleFolders()),
      );
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.pumpAndSettle();
      expect(find.text('Secret recipe'), findsOneWidget);
      expect(find.text('Secret deed'), findsNothing);
      await tester.enterText(find.byType(TextField), 'inner');
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);

      // Once unlocked for the session, search includes it.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TextField)),
      );
      container.read(folderAccessProvider.notifier).grant('priv');
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.pumpAndSettle();
      expect(find.text('Secret deed'), findsOneWidget);
    });

    testWidgets('a document in a locked folder is hidden until unlocked', (
      tester,
    ) async {
      final pins = await pinsWith(tester, '2468');
      await pumpRouted(
        tester,
        FakeRepository(sampleDocs(), folders: sampleFolders()),
        pins: pins,
        at: '/files/doc/s',
      );
      expect(find.text('"Private" is locked'), findsOneWidget);
      expect(find.text('Secret deed'), findsNothing);
    });
  });

  testWidgets('document viewer shows its folder and moves it', (tester) async {
    final repo = FakeRepository([
      doc('t', 'ID notes', DocumentFormat.txt, folderId: 'ids'),
    ], folders: sampleFolders());
    await pumpRouted(
      tester,
      repo,
      at: '/files/doc/t',
      extra: [reminderSchedulerProvider.overrideWithValue(FakeReminders())],
    );
    expect(find.widgetWithText(ActionChip, 'IDs & Proofs'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'IDs & Proofs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Up one level'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to ID Vault'));
    await tester.pumpAndSettle();
    expect((await repo.byId('t'))?.folderId, isNull);
  });

  testWidgets('deleting a document with an expiry cancels its reminders', (
    tester,
  ) async {
    final reminders = FakeReminders();
    final expiring = doc(
      'e',
      'Insurance',
      DocumentFormat.pdf,
      expiresAt: DateTime(2030),
    );
    final repo = FakeRepository([expiring]);
    final container = ProviderContainer(
      overrides: [
        ...baseOverrides(repo, FakeFileStore()),
        reminderSchedulerProvider.overrideWithValue(reminders),
      ],
    );
    addTearDown(container.dispose);
    container.read(pendingDeletesProvider.notifier).schedule([expiring]);
    await tester.pump(
      PendingDeleteController.delay + const Duration(seconds: 1),
    );
    await tester.pump();
    expect(reminders.cancelled, ['e']);
  });
}
