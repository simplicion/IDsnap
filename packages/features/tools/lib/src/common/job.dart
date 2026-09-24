import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lifecycle of a tool run. Success ([JobDone]) is only reached after every
/// output was committed (validated + saved) through [CommitOutput].
sealed class JobState {
  const JobState();
}

final class JobIdle extends JobState {
  const JobIdle();
}

final class JobRunning extends JobState {
  const JobRunning({this.progress, this.label = 'Working…'});

  /// Null when real progress is unknown (indeterminate spinner).
  final double? progress;
  final String label;
}

final class JobDone extends JobState {
  const JobDone(this.documents);
  final List<Document> documents;
}

final class JobFailed extends JobState {
  const JobFailed(this.failure);
  final AppFailure failure;
}

/// The run finished but intentionally produced nothing (e.g. compression
/// would not make the file smaller).
final class JobNotice extends JobState {
  const JobNotice(this.message);
  final String message;
}

/// Returned by work to end in [JobNotice] instead of an error.
class NoticeFailure extends AppFailure {
  const NoticeFailure(this.message)
    : super(FailureCode.processingCancelled, detail: message);

  final String message;
}

typedef ReportProgress = void Function(double progress);

/// Produces files to commit. Must not write to the library itself.
typedef JobWork =
    Future<Result<List<OutputFile>>> Function(ReportProgress report);

class JobController extends Notifier<JobState> {
  JobController(this.key);

  /// One job per tool screen.
  final String key;

  @override
  JobState build() => const JobIdle();

  void reset() => state = const JobIdle();

  /// Fire-and-forget [run] for button handlers.
  void start(JobWork work, {String label = 'Working…'}) =>
      unawaited(run(work, label: label));

  Future<void> run(JobWork work, {String label = 'Working…'}) async {
    if (state is JobRunning) return;
    state = JobRunning(label: label);

    Result<List<OutputFile>> result;
    try {
      result = await work((p) {
        if (ref.mounted) {
          state = JobRunning(progress: p.clamp(0, 1).toDouble(), label: label);
        }
      });
    } on AppFailure catch (f) {
      result = Err(f);
    } on Object catch (e, st) {
      result = Err(AppFailure(FailureCode.unknown, cause: e, stackTrace: st));
    }
    if (!ref.mounted) return;

    switch (result) {
      case Err(:final failure):
        state = failure is NoticeFailure
            ? JobNotice(failure.message)
            : JobFailed(failure);
      case Ok(value: final outputs):
        if (outputs.isEmpty) {
          state = const JobFailed(AppFailure(FailureCode.conversionFailed));
          return;
        }
        state = const JobRunning(label: 'Saving to your library…');
        final commit = ref.read(commitOutputProvider);
        final docs = <Document>[];
        for (final out in outputs) {
          final saved = await commit(out);
          if (!ref.mounted) return;
          if (saved case Err(:final failure)) {
            state = JobFailed(failure);
            return;
          }
          docs.add(saved.valueOrNull!);
        }
        state = JobDone(docs);
    }
  }
}

final jobProvider = NotifierProvider.autoDispose
    .family<JobController, JobState, String>(JobController.new);
