import 'dart:io';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_data/docscan_data.dart' show VaultUnavailableException;

/// The startup step that failed (audit H-08). Shown in "Copy details" so
/// support can tell a SQLCipher problem from a missing asset.
enum StartupStep { pdfEngine, vault, assets, storage, billing, app }

/// Any startup failure other than [VaultUnavailableException], tagged with
/// the step it happened in.
class StartupFailure implements Exception {
  const StartupFailure(this.step, this.cause, this.stackTrace);

  final StartupStep step;
  final Object cause;
  final StackTrace stackTrace;

  /// Plain-language headline and explanation for the recovery screen.
  (String, String) get explanation {
    final c = cause;
    if (_outOfSpace(c)) {
      return (
        'Your phone is out of storage',
        'IDSnap needs a little free space to open your vault. Delete some '
            'photos, videos or apps, then tap Try again. Your files are '
            'still on this phone.',
      );
    }
    return switch (step) {
      StartupStep.vault => (
        "Your vault couldn't be opened",
        "IDSnap couldn't open its encrypted database. Your files are still "
            'on this phone. Restart the phone and tap Try again. Do not '
            'uninstall IDSnap: that deletes the vault and its key.',
      ),
      StartupStep.pdfEngine || StartupStep.assets => (
        "IDSnap couldn't start",
        "A part of the app didn't load. This usually means the app update "
            'did not finish installing. Restart the phone and tap Try '
            'again; if it keeps happening, update IDSnap from the store '
            '(updating keeps your data).',
      ),
      StartupStep.storage => (
        "IDSnap couldn't reach its storage",
        'The phone did not give IDSnap access to its own folder. Restart '
            'the phone and tap Try again. Your files are still on this '
            'phone.',
      ),
      StartupStep.billing || StartupStep.app => (
        "IDSnap couldn't start",
        'Something unexpected stopped the app while opening. Your files '
            'are still on this phone. Tap Try again; if it keeps happening, '
            'contact support.',
      ),
    };
  }

  /// Redacted details for support: step, exception type and a scrubbed
  /// message (paths removed, length capped). Never document contents.
  String get diagnostics =>
      'step=${step.name} '
      '${AppFailure(FailureCode.unknown, cause: cause).diagnostics}';

  static bool _outOfSpace(Object e) {
    if (e is FileSystemException) {
      final code = e.osError?.errorCode;
      // ENOSPC on Android/iOS; ERROR_DISK_FULL on Windows.
      if (code == 28 || code == 112) return true;
    }
    final text = e.toString().toLowerCase();
    return text.contains('no space left') ||
        text.contains('disk is full') ||
        text.contains('database or disk is full') ||
        text.contains('sqlite_full');
  }

  @override
  String toString() => 'StartupFailure(${step.name}, ${cause.runtimeType})';
}

/// Runs one startup step, tagging any failure (except an already-tagged
/// one or the vault's own recovery exception, which pass through).
Future<T> runStartupStep<T>(StartupStep step, Future<T> Function() body) async {
  try {
    return await body();
  } on StartupFailure {
    rethrow;
  } on VaultUnavailableException {
    rethrow;
  } on Object catch (e, st) {
    throw StartupFailure(step, e, st);
  }
}
