/// Structured logger that only accepts non-sensitive fields.
///
/// Callers pass an event name and primitive fields (counts, durations,
/// codes). Strings longer than 64 chars or containing path separators are
/// redacted so filenames, paths and OCR text can't leak by accident.
class RedactedLogger {
  RedactedLogger(this.scope, {void Function(String line)? sink})
    : _sink = sink ?? _noop;

  final String scope;
  final void Function(String line) _sink;

  static void _noop(String _) {}

  void info(String event, [Map<String, Object?> fields = const {}]) =>
      _emit('I', event, fields);

  void warn(String event, [Map<String, Object?> fields = const {}]) =>
      _emit('W', event, fields);

  void error(String event, [Map<String, Object?> fields = const {}]) =>
      _emit('E', event, fields);

  void _emit(String level, String event, Map<String, Object?> fields) {
    final safe = <String, Object?>{
      for (final e in fields.entries)
        e.key: isSafe(e.value) ? e.value : '<redacted>',
    };
    _sink('$level/$scope $event $safe');
  }

  static bool isSafe(Object? v) => switch (v) {
    null || num() || bool() || Enum() => true,
    final String s => s.length <= 64 && !s.contains('/') && !s.contains(r'\'),
    _ => false,
  };
}
