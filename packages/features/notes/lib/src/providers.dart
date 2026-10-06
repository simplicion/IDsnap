import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_security/engine_security.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Feature-local seams. The defaults are the real on-device implementations;
// tests override them with fakes.

/// Per-note PINs: salted PBKDF2 hashes in the platform keystore (the same
/// store as folder PINs, under `note.<id>`).
final notePinStoreProvider = Provider<FolderPinStore>(
  (ref) => KeystoreFolderPinStore(SecureStorageSecretStore()),
);

/// Keystore key for a note's PIN.
String notePinKey(String noteId) => 'note.$noteId';

/// Toggles Android `FLAG_SECURE`.
typedef NotesSecureSetter = Future<void> Function({required bool enabled});

final notesSecureSetterProvider = Provider<NotesSecureSetter>(
  (ref) => const SecureWindow().setSecure,
);

/// Reference-counted FLAG_SECURE for the notes screens: on while at least
/// one is visible; afterwards it returns to what App Lock wants.
class NotesSecureFlag {
  NotesSecureFlag(this._set, this._baseline);

  final NotesSecureSetter _set;
  final bool Function() _baseline;
  int _holders = 0;

  bool get isSecure => _holders > 0;

  void acquire() {
    if (_holders++ == 0) unawaited(_set(enabled: true));
  }

  void release() {
    if (_holders == 0) return;
    if (--_holders == 0) unawaited(_set(enabled: _baseline()));
  }
}

final notesSecureFlagProvider = Provider<NotesSecureFlag>(
  (ref) => NotesSecureFlag(
    ref.watch(notesSecureSetterProvider),
    () => ref.read(currentSettingsProvider).appLock,
  ),
);

final notesClipboardAccessProvider = Provider<ClipboardAccess>(
  (ref) => const SystemClipboardAccess(),
);

/// Copies with a 60 s clear. App-lifetime so the clear still happens after
/// leaving the screen.
final notesClipboardProvider = Provider<SecureClipboard>((ref) {
  final c = SecureClipboard(ref.watch(notesClipboardAccessProvider));
  ref.onDispose(c.dispose);
  return c;
});

/// Current search text on the notes list.
class NotesSearch extends Notifier<String> {
  @override
  String build() => '';

  // A setter would read oddly at call sites (`notifier.state = …`).
  // ignore: use_setters_to_change_properties
  void set(String value) => state = value;
}

final notesSearchProvider = NotifierProvider<NotesSearch, String>(
  NotesSearch.new,
);

final notesListProvider = StreamProvider.autoDispose<List<Note>>(
  (ref) => ref
      .watch(notesRepositoryProvider)
      .watch(search: ref.watch(notesSearchProvider)),
);

/// Notes unlocked in this session. Cleared when the notes list is left or
/// the app goes to the background.
class UnlockedNotes extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String id) => state = {...state, id};

  /// Safe to call late (screen teardown, app lifecycle callbacks).
  void clear() {
    if (ref.mounted) state = const {};
  }
}

final unlockedNotesProvider = NotifierProvider<UnlockedNotes, Set<String>>(
  UnlockedNotes.new,
);
