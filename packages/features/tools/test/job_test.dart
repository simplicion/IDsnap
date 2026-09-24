import 'dart:async';
import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers.dart';

OutputFile _out() => OutputFile(
  bytes: Uint8List.fromList([1, 2, 3]),
  format: DocumentFormat.pdf,
  suggestedName: 'Out',
  expectedPages: 1,
);

void main() {
  setUpAll(registerFallbacks);

  late Harness h;
  late ProviderContainer container;

  setUp(() {
    h = Harness();
    container = ProviderContainer(overrides: h.overrides);
    addTearDown(container.dispose);
    container.listen(jobProvider('t'), (_, _) {});
  });

  JobController job() => container.read(jobProvider('t').notifier);
  JobState state() => container.read(jobProvider('t'));

  test('reports success only after CommitOutput returns Ok', () async {
    final pending = Completer<Result<Document>>();
    when(() => h.commit(any())).thenAnswer((_) => pending.future);

    final run = job().run((report) async => Ok([_out()]));
    await Future<void>.delayed(Duration.zero);
    expect(state(), isA<JobRunning>(), reason: 'still committing');

    pending.complete(Ok(doc('d1')));
    await run;
    expect(state(), isA<JobDone>());
    expect((state() as JobDone).documents.single.id, 'd1');
  });

  test('commit failure ends in JobFailed, never JobDone', () async {
    when(() => h.commit(any())).thenAnswer(
      (_) async => const Err(AppFailure(FailureCode.outputValidationFailed)),
    );
    await job().run((report) async => Ok([_out()]));
    final s = state();
    expect(s, isA<JobFailed>());
    expect((s as JobFailed).failure.code, FailureCode.outputValidationFailed);
  });

  test('work errors, thrown exceptions and empty output fail', () async {
    await job().run(
      (report) async => const Err(AppFailure(FailureCode.corruptFile)),
    );
    expect((state() as JobFailed).failure.code, FailureCode.corruptFile);

    job().reset();
    await job().run((report) async => throw StateError('boom'));
    expect((state() as JobFailed).failure.code, FailureCode.unknown);

    job().reset();
    await job().run((report) async => const Ok([]));
    expect((state() as JobFailed).failure.code, FailureCode.conversionFailed);
    verifyNever(() => h.commit(any()));
  });

  test('NoticeFailure ends in JobNotice without committing', () async {
    await job().run(
      (report) async => const Err(NoticeFailure('Already small')),
    );
    expect(state(), isA<JobNotice>());
    verifyNever(() => h.commit(any()));
  });

  test('progress is reported while running', () async {
    when(() => h.commit(any())).thenAnswer((_) async => Ok(doc('d')));
    final seen = <double?>[];
    container.listen(jobProvider('t'), (_, next) {
      if (next is JobRunning) seen.add(next.progress);
    });
    await job().run((report) async {
      report(0.5);
      return Ok([_out()]);
    });
    expect(seen, contains(0.5));
  });

  testWidgets('ToolScaffold shows FailureView on failure and retries to form', (
    tester,
  ) async {
    await h.pump(
      tester,
      const ToolScaffold(
        jobKey: 'w',
        title: 'T',
        description: 'Form body',
        children: [Text('Field')],
      ),
    );
    expect(find.text('Field'), findsOneWidget);

    final element = tester.element(find.byType(ToolScaffold));
    final c = ProviderScope.containerOf(element);
    await c
        .read(jobProvider('w').notifier)
        .run((r) async => const Err(AppFailure(FailureCode.corruptFile)));
    await tester.pumpAndSettle();

    expect(find.byType(FailureView), findsOneWidget);
    expect(find.text(FailureCode.corruptFile.title), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Field'), findsOneWidget);
  });

  testWidgets('ToolScaffold shows the saved result after success', (
    tester,
  ) async {
    when(() => h.commit(any())).thenAnswer((_) async => Ok(doc('d9')));
    await h.pump(
      tester,
      const ToolScaffold(
        jobKey: 'w2',
        title: 'T',
        description: 'd',
        children: [],
      ),
    );
    final c = ProviderScope.containerOf(
      tester.element(find.byType(ToolScaffold)),
    );
    await c.read(jobProvider('w2').notifier).run((r) async => Ok([_out()]));
    await tester.pumpAndSettle();
    expect(find.text('Saved to your library'), findsOneWidget);
    expect(find.text('Report.pdf'), findsOneWidget);
  });
}
