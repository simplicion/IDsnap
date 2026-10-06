import 'dart:collection';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Local-only error log (audit H-08). Uncaught errors are recorded as
/// redacted one-liners (error type and a scrubbed, length-capped message;
/// no paths, no document contents) in memory and printed to the device log.
/// Nothing is ever sent anywhere: the app has no network access (ADR-0008).
/// The recent lines are included when the user copies details for support.
class LocalErrorLog {
  LocalErrorLog._();

  static const capacity = 30;
  static final _lines = ListQueue<String>(capacity);
  static final _logger = RedactedLogger('app', sink: _record);

  /// The most recent redacted lines, oldest first.
  static List<String> get recent => List.unmodifiable(_lines);

  static void _record(String line) {
    if (_lines.length == capacity) _lines.removeFirst();
    _lines.add('${DateTime.now().toUtc().toIso8601String()} $line');
    debugPrint(line);
  }

  /// Records [error] under [event] with redacted fields only.
  static void record(String event, Object error, {String? where}) {
    final scrubbed = AppFailure(FailureCode.unknown, cause: error).diagnostics;
    _logger.error(event, {
      'type': error.runtimeType.toString(),
      'where': ?where,
    });
    // diagnostics is already scrubbed of paths; keep it as its own line so
    // the logger's 64-character limit doesn't drop it entirely.
    _record('  $scrubbed');
  }

  @visibleForTesting
  static void clear() => _lines.clear();
}

/// Installs the global handlers. Call once, before the first `runApp`.
///
/// - Framework errors (build/layout/paint): logged; in debug also printed
///   in full by Flutter's default presenter.
/// - Uncaught async errors (e.g. an `unawaited` save that throws, audit
///   B-01): logged via [PlatformDispatcher.onError] instead of vanishing.
///   No `runZonedGuarded`: [PlatformDispatcher.onError] covers the root
///   zone, and a custom zone around `runApp` triggers zone-mismatch
///   warnings with `WidgetsFlutterBinding.ensureInitialized` in `main`.
/// - Release builds show [ReleaseErrorWidget] for a widget that fails to
///   build, instead of a grey box.
void installErrorHandlers() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    LocalErrorLog.record(
      'flutter_error',
      details.exception,
      where: details.library,
    );
    if (kDebugMode) (previous ?? FlutterError.presentError)(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    LocalErrorLog.record('uncaught_async', error);
    return true;
  };
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const ReleaseErrorWidget();
  }
}

/// Shown in place of a widget that failed to build (release builds).
/// Deliberately plain: no error text, which may contain names or paths.
class ReleaseErrorWidget extends StatelessWidget {
  const ReleaseErrorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final material = Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 20),
            const SizedBox(width: Space.x2),
            Flexible(
              child: Text(
                "This part couldn't be shown. Go back and open it again.",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
    // ErrorWidget may be built outside a Directionality (e.g. at the root).
    return Directionality.maybeOf(context) == null
        ? Directionality(textDirection: TextDirection.ltr, child: material)
        : material;
  }
}
