import 'package:docscan_core/src/run_heavy_web.dart'
    if (dart.library.io) 'package:docscan_core/src/run_heavy_io.dart'
    as impl;

/// Runs CPU-bound [computation] off the UI isolate where the platform allows
/// (a background isolate on mobile/desktop; inline on web).
///
/// [computation] must only capture sendable values.
Future<R> runHeavy<R>(R Function() computation) => impl.runHeavy(computation);
