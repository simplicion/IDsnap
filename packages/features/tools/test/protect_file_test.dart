import 'dart:math';
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/protect/password_form.dart';
import 'package:feature_tools/src/protect/password_tools.dart';
import 'package:feature_tools/src/protect/protect_file_screen.dart';
import 'package:feature_tools/src/protect/remove_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

/// In-memory protector: records calls; `locked` paths need `current`.
class FakeProtector implements PdfProtector, ProtectedZipWriter {
  final locked = <String, String>{};
  final protectCalls = <(String, PdfProtection, String?)>[];
  final zipCalls = <(List<ZipSource>, String)>[];
  final removeCalls = <(String, String)>[];
  String unlockPassword = 'right';

  @override
  Future<Result<bool>> needsPassword(String path) async =>
      Ok(locked.containsKey(path));

  @override
  Future<Result<ProtectedFile>> protectPdf(
    String inputPath,
    PdfProtection protection, {
    required String outputPath,
    String? currentPassword,
  }) async {
    protectCalls.add((inputPath, protection, currentPassword));
    final need = locked[inputPath];
    if (need != null && currentPassword == null) {
      return const Err(AppFailure(FailureCode.passwordProtected));
    }
    if (need != null && currentPassword != need) {
      return const Err(AppFailure(FailureCode.wrongPassword));
    }
    return Ok(
      ProtectedFile(
        path: outputPath,
        format: DocumentFormat.pdf,
        sizeBytes: 2048,
        pageCount: 2,
      ),
    );
  }

  @override
  Future<Result<ProtectedFile>> removePdfPassword(
    String inputPath,
    String password, {
    required String outputPath,
  }) async {
    removeCalls.add((inputPath, password));
    if (password != unlockPassword) {
      return const Err(AppFailure(FailureCode.wrongPassword));
    }
    return Ok(
      ProtectedFile(
        path: outputPath,
        format: DocumentFormat.pdf,
        sizeBytes: 1000,
        pageCount: 3,
      ),
    );
  }

  @override
  Future<Result<ProtectedFile>> writeProtectedZip(
    List<ZipSource> sources,
    String password, {
    required String outputPath,
    void Function(double progress)? onProgress,
  }) async {
    zipCalls.add((sources, password));
    onProgress?.call(0.5);
    return Ok(
      ProtectedFile(
        path: outputPath,
        format: DocumentFormat.zip,
        sizeBytes: 4096,
      ),
    );
  }
}

void main() {
  late Harness h;
  late FakeProtector protector;

  setUpAll(registerFallbacks);

  setUp(() {
    h = Harness();
    protector = FakeProtector();
    var n = 0;
    when(
      () => h.files.writeTemp(any(), any()),
    ).thenAnswer((_) async => '/app/tmp/probe${n++}.tmp');
    when(() => h.files.delete(any())).thenAnswer((_) async {});
    when(
      () => h.share.share(any(), subject: any(named: 'subject')),
    ).thenAnswer((_) async => const Ok(null));
    when(() => h.share.copyText(any())).thenAnswer((_) async => const Ok(null));
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view
      ..physicalSize = const Size(1200, 5000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...h.overrides,
          pdfProtectorProvider.overrideWithValue(protector),
          protectedZipWriterProvider.overrideWithValue(protector),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  void pickFromDevice(List<PickedFile> files) {
    when(
      () => h.picker.pickFiles(any(), multiple: any(named: 'multiple')),
    ).thenAnswer((_) async => Ok(files));
  }

  group('password tools', () {
    test('generates 4 groups of 4 unambiguous characters', () {
      final pw = generatePassword(random: Random(1));
      expect(pw, matches(RegExp(r'^[A-Za-z2-9]{4}(-[A-Za-z2-9]{4}){3}$')));
      expect(pw, isNot(contains(RegExp('[01OIl]'))));
      expect(generatePassword(), isNot(generatePassword()));
      expect(
        estimatePasswordStrength(pw).strength,
        PasswordStrength.veryStrong,
      );
      expect(zipPasswordProblem(pw), isNull);
    });

    test('rates weak, common and strong passwords', () {
      expect(
        estimatePasswordStrength('password').strength,
        PasswordStrength.tooWeak,
      );
      expect(
        estimatePasswordStrength('abc12').strength,
        PasswordStrength.tooWeak,
      );
      expect(estimatePasswordStrength('aaaaaaaa').strength.acceptable, isFalse);
      expect(
        estimatePasswordStrength(
          'correct horse battery staple',
        ).strength.acceptable,
        isTrue,
      );
      expect(zipPasswordProblem('pässword1'), isNotNull);
    });

    test('setup problems: empty, weak, mismatch, non-ASCII for ZIP', () {
      expect(PasswordSetup.problem('', ''), isNotNull);
      expect(PasswordSetup.problem('password', 'password'), isNotNull);
      const good = 'Kx7q-Pm3r-Zt9w-Hb4n';
      expect(PasswordSetup.problem(good, 'other'), contains("don't match"));
      expect(PasswordSetup.problem(good, good), isNull);
      expect(
        PasswordSetup.problem(
          'Grüße-Kx7q-Pm3r',
          'Grüße-Kx7q-Pm3r',
          ascii: true,
        ),
        contains('ZIP'),
      );
    });
  });

  group('Protect file', () {
    testWidgets('PDF → protected PDF → share and save to the vault', (
      tester,
    ) async {
      pickFromDevice(const [
        PickedFile(path: '/cache/Tax.pdf', name: 'Tax.pdf'),
      ]);
      when(
        () => h.files.read(any()),
      ).thenAnswer((_) async => Uint8List.fromList('%PDF-2.0'.codeUnits));
      when(() => h.commit(any())).thenAnswer((_) async => Ok(doc('saved')));
      await pump(tester, const ProtectFileScreen());

      expect(find.text(passwordNotKeptWarning), findsOneWidget);
      await tester.tap(find.text('From device'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tax.pdf'), findsOneWidget);
      // PDFs default to a protected PDF.
      final pdfChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Protected PDF'),
      );
      expect(pdfChip.selected, isTrue);

      await tester.tap(find.text('Generate strong password'));
      await tester.pumpAndSettle();
      final pw = tester
          .widget<TextField>(find.byKey(const ValueKey('password-field')))
          .controller!
          .text;
      expect(pw, hasLength(19));
      expect(find.textContaining('Very strong'), findsOneWidget);

      await tester.tap(find.text('Protect PDF'));
      await tester.pumpAndSettle();
      expect(protector.protectCalls.single.$1, '/cache/Tax.pdf');
      expect(protector.protectCalls.single.$2.openPassword, pw);
      expect(protector.protectCalls.single.$2.ownerPassword, isNull);
      expect(find.text('File protected'), findsOneWidget);
      expect(find.text('Tax (protected).pdf'), findsOneWidget);

      await tester.tap(find.text('Share').first);
      await tester.pumpAndSettle();
      final shared =
          verify(
                () =>
                    h.share.share(captureAny(), subject: any(named: 'subject')),
              ).captured.single
              as List<String>;
      expect(shared.single, endsWith('Tax (protected).pdf'));

      // "Save to" destination control (default: top level).
      expect(find.byKey(const ValueKey('save-folder-field')), findsOneWidget);
      await tester.tap(find.text('Save to ID Vault'));
      await tester.pumpAndSettle();
      expect(find.text('Saved to ID Vault'), findsOneWidget);
      final out =
          verify(() => h.commit(captureAny())).captured.single as OutputFile;
      expect(out.passwordProtected, isTrue);
      expect(out.expectedPages, 2);
      expect(out.format, DocumentFormat.pdf);
      expect(find.text('Saved · Open'), findsOneWidget);
    });

    testWidgets('mixed files → one ZIP; blocks mismatched confirmation', (
      tester,
    ) async {
      pickFromDevice(const [
        PickedFile(path: '/cache/Tax.pdf', name: 'Tax.pdf'),
        PickedFile(path: '/cache/id.jpg', name: 'id.jpg'),
        PickedFile(path: '/cache/notes.odt', name: 'notes.odt'),
      ]);
      await pump(tester, const ProtectFileScreen());
      await tester.tap(find.text('From device'));
      await tester.pumpAndSettle();
      expect(find.textContaining('notes.odt'), findsOneWidget); // any file
      expect(find.widgetWithText(ChoiceChip, 'Protected PDF'), findsNothing);
      expect(find.text('Create protected ZIP'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('password-field')),
        'Kx7q-Pm3r-Zt9w-Hb4n',
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirm-field')),
        'Kx7q-Pm3r-Zt9w-Hb4X',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create protected ZIP'));
      await tester.pumpAndSettle();
      expect(protector.zipCalls, isEmpty);
      expect(find.text("The passwords don't match."), findsWidgets);

      await tester.enterText(
        find.byKey(const ValueKey('confirm-field')),
        'Kx7q-Pm3r-Zt9w-Hb4n',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create protected ZIP'));
      await tester.pumpAndSettle();
      final (sources, password) = protector.zipCalls.single;
      expect(password, 'Kx7q-Pm3r-Zt9w-Hb4n');
      expect(sources.map((s) => s.fileName), [
        'Tax.pdf',
        'id.jpg',
        'notes.odt',
      ]);
      expect(find.text('Protected files.zip'), findsOneWidget);
      expect(find.textContaining('Archive Utility'), findsOneWidget);
    });

    testWidgets('asks for the current password of a protected PDF', (
      tester,
    ) async {
      protector.locked['/cache/Old.pdf'] = 'old-pass';
      pickFromDevice(const [
        PickedFile(path: '/cache/Old.pdf', name: 'Old.pdf'),
      ]);
      await pump(tester, const ProtectFileScreen());
      await tester.tap(find.text('From device'));
      await tester.pumpAndSettle();
      // The picker doesn't prompt in this tool.
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Generate strong password'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Protect PDF'));
      await tester.pumpAndSettle();

      expect(find.text('Current password needed'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-password-prompt')),
        'nope',
      );
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining("That password isn't right"), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-password-prompt')),
        'old-pass',
      );
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('File protected'), findsOneWidget);
      expect(protector.protectCalls.last.$3, 'old-pass');
    });

    testWidgets('owner password restricts permissions', (tester) async {
      pickFromDevice(const [PickedFile(path: '/cache/A.pdf', name: 'A.pdf')]);
      await pump(tester, const ProtectFileScreen());
      await tester.tap(find.text('From device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate strong password'));
      await tester.tap(find.text('Restrict printing, copying and editing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Protect PDF'));
      await tester.pumpAndSettle();
      expect(protector.protectCalls, isEmpty); // needs the owner password
      await tester.enterText(
        find.byKey(const ValueKey('owner-field')),
        'owner-secret-1',
      );
      await tester.tap(find.text('Allow printing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Protect PDF'));
      await tester.pumpAndSettle();
      final p = protector.protectCalls.single.$2;
      expect(p.ownerPassword, 'owner-secret-1');
      expect(p.allowPrinting, isTrue);
      expect(p.allowCopying, isFalse);
      expect(p.allowEditing, isFalse);
    });

    testWidgets('engine failures are shown with a way back', (tester) async {
      pickFromDevice(const [PickedFile(path: '/cache/a.txt', name: 'a.txt')]);
      await pump(tester, const ProtectFileScreen());
      await tester.tap(find.text('From device'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('password-field')),
        'Grüße-Kx7q-Pm3r-Zt9w',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('English letters'), findsWidgets);
    });
  });

  group('Remove PDF password', () {
    testWidgets('wrong password → typed error; right password → saved', (
      tester,
    ) async {
      pickFromDevice(const [PickedFile(path: '/cache/L.pdf', name: 'L.pdf')]);
      when(
        () => h.files.read(any()),
      ).thenAnswer((_) async => Uint8List.fromList('%PDF-1.7'.codeUnits));
      when(() => h.commit(any())).thenAnswer((_) async => Ok(doc('u')));
      await pump(tester, const RemovePdfPasswordScreen());
      await tester.tap(find.text('From device'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing); // no unlock prompt
      await tester.enterText(
        find.byKey(const ValueKey('current-password')),
        'wrong',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove password'));
      await tester.pumpAndSettle();
      expect(find.text(FailureCode.wrongPassword.title), findsOneWidget);

      await tester.tap(find.text(FailureAction.retry.label).first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('current-password')),
        'right',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove password'));
      await tester.pumpAndSettle();
      final out =
          verify(() => h.commit(captureAny())).captured.single as OutputFile;
      expect(out.suggestedName, 'L (no password)');
      expect(out.passwordProtected, isFalse);
      expect(out.expectedPages, 3);
      expect(find.text('Saved to ID Vault'), findsOneWidget);
    });
  });

  group('input picker unlocks protected PDFs for other tools', () {
    Widget picker(
      List<ToolInput> Function() get,
      void Function(List<ToolInput>) set,
    ) => Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => InputPicker(
          accepts: const {DocumentFormat.pdf},
          inputs: get(),
          multiple: true,
          onChanged: (v) => setState(() => set(v)),
        ),
      ),
    );

    testWidgets('prompts, then uses a decrypted copy', (tester) async {
      protector.locked['/cache/Locked.pdf'] = 'x';
      pickFromDevice(const [
        PickedFile(path: '/cache/Locked.pdf', name: 'Locked.pdf'),
        PickedFile(path: '/cache/Open.pdf', name: 'Open.pdf'),
      ]);
      var inputs = <ToolInput>[];
      await pump(tester, picker(() => inputs, (v) => inputs = v));
      await tester.tap(find.text('From device'));
      await tester.pumpAndSettle();
      expect(find.text('Password needed'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('pdf-password-prompt')),
        'right',
      );
      await tester.pump();
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(inputs, hasLength(2));
      expect(inputs.first.name, 'Locked');
      expect(inputs.first.path, endsWith('unlocked.pdf'));
      expect(inputs.last.path, '/cache/Open.pdf');
      expect(protector.removeCalls.single, ('/cache/Locked.pdf', 'right'));
    });

    testWidgets('cancelling drops the file with a note', (tester) async {
      protector.locked['/cache/Locked.pdf'] = 'x';
      pickFromDevice(const [
        PickedFile(path: '/cache/Locked.pdf', name: 'Locked.pdf'),
      ]);
      var inputs = <ToolInput>[];
      await pump(tester, picker(() => inputs, (v) => inputs = v));
      await tester.tap(find.text('From device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(inputs, isEmpty);
      expect(find.textContaining('needs its password'), findsOneWidget);
    });
  });
}
