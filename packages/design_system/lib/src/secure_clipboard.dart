import 'dart:async';

import 'package:flutter/services.dart';

/// Minimal clipboard seam (the system clipboard in the app).
abstract interface class ClipboardAccess {
  Future<String?> read();
  Future<void> write(String text);
}

class SystemClipboardAccess implements ClipboardAccess {
  const SystemClipboardAccess();

  @override
  Future<String?> read() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;

  @override
  Future<void> write(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

/// Copies sensitive text and clears it again after [clearAfter], but only if
/// the clipboard still holds what we copied (read back before clearing), so
/// something the user copied since is never wiped.
class SecureClipboard {
  SecureClipboard(this._access, {this.clearAfter = defaultClearAfter});

  static const defaultClearAfter = Duration(seconds: 60);

  final ClipboardAccess _access;
  final Duration clearAfter;
  Timer? _timer;
  String? _pending;

  /// True while a clear is scheduled.
  bool get clearScheduled => _timer?.isActive ?? false;

  Future<void> copy(String text) async {
    await _access.write(text);
    _timer?.cancel();
    _pending = text;
    _timer = Timer(clearAfter, () => unawaited(clearIfUnchanged()));
  }

  Future<void> clearIfUnchanged() async {
    _timer?.cancel();
    final ours = _pending;
    _pending = null;
    if (ours == null) return;
    try {
      if (await _access.read() == ours) await _access.write('');
    } on Object {
      // Clipboard unavailable: nothing more we can do.
    }
  }

  void dispose() => _timer?.cancel();
}
