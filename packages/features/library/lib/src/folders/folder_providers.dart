import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_security/engine_security.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Feature-local seams. The defaults are the real on-device implementations;
// tests override them with fakes.

/// Per-folder PINs: salted PBKDF2 hashes in the platform keystore.
final folderPinStoreProvider = Provider<FolderPinStore>(
  (ref) => KeystoreFolderPinStore(SecureStorageSecretStore()),
);

/// Toggles Android `FLAG_SECURE`.
typedef FolderSecureSetter = Future<void> Function({required bool enabled});

final folderSecureSetterProvider = Provider<FolderSecureSetter>(
  (ref) => const SecureWindow().setSecure,
);

/// Reference-counted FLAG_SECURE for locked-folder screens: on while at
/// least one is visible; afterwards it returns to what App Lock wants.
class FolderSecureFlag {
  FolderSecureFlag(this._set, this._baseline);

  final FolderSecureSetter _set;
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

final folderSecureFlagProvider = Provider<FolderSecureFlag>(
  (ref) => FolderSecureFlag(
    ref.watch(folderSecureSetterProvider),
    () => ref.read(currentSettingsProvider).appLock,
  ),
);

/// Every folder as a tree, live.
final folderTreeProvider = StreamProvider<FolderTree>(
  (ref) =>
      ref.watch(folderRepositoryProvider).watchAllFolders().map(FolderTree.new),
);

/// Session unlocks for locked folders.
///
/// Design: an unlock lasts until the app goes to the background (Android
/// `onStop` / iOS background), then every folder locks again. Screens IDSnap
/// opens itself (the file picker, share sheet) don't count: wrap them in
/// [whileExternal]; neither does a device-credential prompt
/// (`AppLock.isAuthenticating`). Subfolders inherit
/// access from an unlocked ancestor unless they have their own lock.
class FolderAccess extends Notifier<Set<String>> {
  int _external = 0;

  @override
  Set<String> build() {
    final listener = AppLifecycleListener(onStateChange: _onLifecycle);
    ref.onDispose(listener.dispose);
    return const {};
  }

  void _onLifecycle(AppLifecycleState s) {
    if (s != AppLifecycleState.hidden && s != AppLifecycleState.paused) return;
    if (_external > 0 || _systemPromptShowing()) return;
    lockAll();
  }

  /// Mirrors every change to [unlockedFoldersProvider], so "Save to folder"
  /// pickers in other features can browse folders unlocked this session.
  @override
  set state(Set<String> value) {
    super.state = value;
    ref.read(unlockedFoldersProvider.notifier).publish(value);
  }

  bool get isExternalActive => _external > 0;

  /// The device-credential prompt (App Lock or a folder's device lock) can
  /// send the app to the background; that isn't leaving the app.
  bool _systemPromptShowing() {
    try {
      return ref.read(appLockProvider).isAuthenticating;
    } on Object {
      return false; // App Lock not wired.
    }
  }

  void grant(String folderId) {
    if (!state.contains(folderId)) state = {...state, folderId};
  }

  void revoke(String folderId) {
    if (state.contains(folderId)) state = {...state}..remove(folderId);
  }

  void lockAll() {
    if (state.isNotEmpty) state = const {};
  }

  /// Runs [action] (which opens a system screen) without relocking.
  Future<T> whileExternal<T>(Future<T> Function() action) async {
    _external++;
    try {
      return await action();
    } finally {
      _external--;
    }
  }
}

final folderAccessProvider = NotifierProvider<FolderAccess, Set<String>>(
  FolderAccess.new,
);

/// `(folderId, sort, filter)`; `folderId == null` is the vault's top level.
typedef ContentsKey = (String?, DocumentSort, DocumentFilter);

final folderContentsProvider =
    StreamProvider.family<FolderContents, ContentsKey>(
      (ref, key) => ref
          .watch(folderRepositoryProvider)
          .watchContents(key.$1, sort: key.$2, filter: key.$3),
    );

final folderSearchProvider =
    StreamProvider.family<List<Document>, FolderSearch>(
      (ref, query) => ref.watch(folderRepositoryProvider).watchSearch(query),
    );

final directCountsProvider = StreamProvider<Map<String?, int>>(
  (ref) => ref.watch(folderRepositoryProvider).watchDirectCounts(),
);

/// Recursive counts per folder; contents of locked folders that aren't
/// unlocked are never counted towards an ancestor.
final folderStatsProvider = Provider<Map<String, FolderStats>>((ref) {
  final tree = ref.watch(folderTreeProvider).value;
  final counts = ref.watch(directCountsProvider).value;
  if (tree == null || counts == null) return const {};
  final unlocked = ref.watch(folderAccessProvider);
  return tree.stats(counts, hidden: tree.hiddenContentIds(unlocked));
});

/// Whether [folderId]'s contents may be shown right now.
bool canOpenFolder(WidgetRef ref, String? folderId) {
  final tree = ref.watch(folderTreeProvider).value;
  if (tree == null) return folderId == null;
  return tree.isAccessible(folderId, ref.watch(folderAccessProvider));
}
