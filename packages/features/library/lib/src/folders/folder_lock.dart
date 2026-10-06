import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_library/src/folders/folder_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Honest copy: every vault file is encrypted on the phone (ADR-0010); a
/// folder lock is the extra access gate, not a second layer of encryption.
const folderLockExplainer =
    'Folder lock hides this folder behind your fingerprint or a PIN. '
    'All vault files are already encrypted on this phone.';

/// Makes sure every locked folder on the path to [folderId] is unlocked for
/// this session, prompting for each (outermost first). With [subtree], also
/// unlocks locked folders *below* [folderId] (used before deleting
/// everything inside). Returns false if the user cancels or fails.
Future<bool> ensureFolderAccess(
  BuildContext context,
  WidgetRef ref,
  String? folderId, {
  bool subtree = false,
}) async {
  if (folderId == null) return true;
  final tree = await ref.read(folderTreeProvider.future);
  final needed = [
    ...tree.locksOnPath(folderId),
    if (subtree)
      for (final id in tree.subtreeIds(folderId))
        if (id != folderId && tree[id]!.isLocked) tree[id]!,
  ];
  for (final folder in needed) {
    if (ref.read(folderAccessProvider).contains(folder.id)) continue;
    if (!context.mounted) return false;
    final ok = await unlockFolder(context, ref, folder);
    if (!ok) return false;
  }
  return true;
}

/// Prompts for one folder's lock and grants session access on success.
Future<bool> unlockFolder(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  final bool ok;
  switch (folder.lockMode) {
    case FolderLockMode.none:
      ok = true;
    case FolderLockMode.device:
      ok = await _deviceAuth(context, ref, 'Unlock "${folder.name}"');
    case FolderLockMode.pin:
      ok =
          await showDialog<bool>(
            context: context,
            builder: (_) => PinUnlockDialog(folder: folder),
          ) ??
          false;
  }
  if (ok) ref.read(folderAccessProvider.notifier).grant(folder.id);
  return ok;
}

Future<bool> _deviceAuth(
  BuildContext context,
  WidgetRef ref,
  String reason,
) async {
  final Result<bool> result;
  try {
    final lock = ref.read(appLockProvider);
    // No second prompt right after App Lock unlocked the app.
    if (lock.recentlyAuthenticated()) return true;
    result = await lock.authenticate(reason);
  } on Object catch (e) {
    // App Lock not wired (never in the app).
    if (context.mounted) {
      showFailureSnack(
        context,
        AppFailure(FailureCode.offlineDependencyUnavailable, cause: e),
      );
    }
    return false;
  }
  if (result case Err(:final failure) when context.mounted) {
    showAppSnack(context, failure.detail ?? '${failure.title}.');
  }
  return result.valueOrNull ?? false;
}

String _waitLabel(Duration d) {
  final s = d.inSeconds + (d.inMilliseconds % 1000 > 0 ? 1 : 0);
  if (s < 60) return '$s s';
  final m = (s / 60).ceil();
  return '$m min';
}

/// Asks for a folder's PIN. Pops `true` when accepted.
class PinUnlockDialog extends ConsumerStatefulWidget {
  const PinUnlockDialog({required this.folder, super.key});

  final Folder folder;

  @override
  ConsumerState<PinUnlockDialog> createState() => _PinUnlockDialogState();
}

class _PinUnlockDialogState extends ConsumerState<PinUnlockDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;
  Duration? _wait;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    unawaited(_checkThrottle());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _checkThrottle() async {
    final wait = await ref
        .read(folderPinStoreProvider)
        .retryAfter(widget.folder.id);
    if (mounted) _startWait(wait);
  }

  void _startWait(Duration? wait) {
    _ticker?.cancel();
    setState(() => _wait = wait);
    if (wait == null) return;
    final until = DateTime.now().add(wait);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = until.difference(DateTime.now());
      if (!mounted) return t.cancel();
      if (left <= Duration.zero) {
        t.cancel();
        setState(() => _wait = null);
      } else {
        setState(() => _wait = left);
      }
    });
  }

  Future<void> _submit() async {
    if (_busy || _wait != null) return;
    final pin = _pin.text;
    if (pin.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(folderPinStoreProvider)
        .verifyPin(widget.folder.id, pin);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok(value: PinAccepted()):
        Navigator.pop(context, true);
      case Ok(value: PinRejected(:final attemptsLeft, :final retryAfter)):
        _pin.clear();
        setState(
          () => _error = retryAfter != null
              ? 'Wrong PIN.'
              : attemptsLeft <= 2
              ? 'Wrong PIN. $attemptsLeft '
                    '${attemptsLeft == 1 ? 'try' : 'tries'} before a delay.'
              : 'Wrong PIN. Try again.',
        );
        _startWait(retryAfter);
      case Ok(value: PinThrottled(:final retryAfter)):
        _startWait(retryAfter);
      case Err(:final failure):
        setState(() => _error = failure.recovery);
    }
  }

  Future<void> _forgot() async {
    final folder = widget.folder;
    final ok = await _deviceAuth(
      context,
      ref,
      'Confirm it’s you to reset the PIN for "${folder.name}"',
    );
    if (!ok || !mounted) return;
    final pin = await promptNewPin(context, title: 'New PIN');
    if (pin == null || !mounted) return;
    final saved = await ref.read(folderPinStoreProvider).setPin(folder.id, pin);
    if (!mounted) return;
    saved.fold((_) {
      showAppSnack(context, 'PIN changed');
      Navigator.pop(context, true);
    }, (f) => setState(() => _error = f.recovery));
  }

  @override
  Widget build(BuildContext context) {
    final wait = _wait;
    return AlertDialog(
      icon: const Icon(Icons.lock_rounded),
      title: Text('Unlock "${widget.folder.name}"'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('folder-pin'),
            controller: _pin,
            autofocus: true,
            obscureText: true,
            enabled: wait == null && !_busy,
            keyboardType: TextInputType.number,
            maxLength: 8,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Folder PIN',
              errorText: wait != null
                  ? 'Too many attempts. Try again in ${_waitLabel(wait)}.'
                  : _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _submit(),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _forgot,
              child: const Text('Forgot PIN?'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('pin-unlock'),
          onPressed: wait != null || _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Unlock'),
        ),
      ],
    );
  }
}

/// Asks for a new 4–8 digit PIN twice. Returns it, or null when cancelled.
Future<String?> promptNewPin(BuildContext context, {required String title}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NewPinDialog(title: title),
    );

class _NewPinDialog extends StatefulWidget {
  const _NewPinDialog({required this.title});

  final String title;

  @override
  State<_NewPinDialog> createState() => _NewPinDialogState();
}

class _NewPinDialogState extends State<_NewPinDialog> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _pinError;
  String? _confirmError;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _save() {
    setState(() {
      _pinError = FolderPinStore.isValidPin(_pin.text)
          ? null
          : 'Use 4 to 8 digits';
      _confirmError = _pinError == null && _confirm.text != _pin.text
          ? "PINs don't match"
          : null;
    });
    if (_pinError == null && _confirmError == null) {
      Navigator.pop(context, _pin.text);
    }
  }

  InputDecoration _decoration(String label, String? error) =>
      InputDecoration(labelText: label, errorText: error, counterText: '');

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Choose 4 to 8 digits. If you forget it, you can reset it with your '
          "phone's screen lock.",
          style: context.text.bodyMedium,
        ),
        const SizedBox(height: Space.x3),
        TextField(
          key: const ValueKey('new-pin'),
          controller: _pin,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _decoration('PIN', _pinError),
        ),
        TextField(
          key: const ValueKey('confirm-pin'),
          controller: _confirm,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _decoration('Confirm PIN', _confirmError),
          onSubmitted: (_) => _save(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save PIN')),
    ],
  );
}

/// Lock / change lock / remove lock for [folder]. Requires access first.
Future<void> configureFolderLock(
  BuildContext context,
  WidgetRef ref,
  Folder folder,
) async {
  if (!await ensureFolderAccess(context, ref, folder.id)) return;
  if (!context.mounted) return;
  EngineCapability? device;
  try {
    device = await ref.read(appLockProvider).capability();
  } on Object {
    device = null;
  }
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<FolderLockMode>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _LockSheet(folder: folder, device: device),
  );
  if (choice == null || choice == folder.lockMode || !context.mounted) return;

  final repo = ref.read(folderRepositoryProvider);
  final pins = ref.read(folderPinStoreProvider);
  switch (choice) {
    case FolderLockMode.none:
      final r = await repo.setFolderLockMode(folder.id, FolderLockMode.none);
      if (r case Err(:final failure)) {
        if (context.mounted) showFailureSnack(context, failure);
        return;
      }
      await pins.removePin(folder.id);
      if (context.mounted) showAppSnack(context, 'Lock removed');
    case FolderLockMode.device:
      // Confirm the prompt works before relying on it.
      final ok = await _deviceAuth(
        context,
        ref,
        'Confirm it’s you to lock "${folder.name}"',
      );
      if (!ok || !context.mounted) return;
      final r = await repo.setFolderLockMode(folder.id, FolderLockMode.device);
      if (r case Err(:final failure)) {
        if (context.mounted) showFailureSnack(context, failure);
        return;
      }
      await pins.removePin(folder.id);
      ref.read(folderAccessProvider.notifier).grant(folder.id);
      if (context.mounted) {
        showAppSnack(context, 'Locked with your phone’s screen lock');
      }
    case FolderLockMode.pin:
      final pin = await promptNewPin(context, title: 'Set a folder PIN');
      if (pin == null || !context.mounted) return;
      final saved = await pins.setPin(folder.id, pin);
      if (saved case Err(:final failure)) {
        if (context.mounted) showFailureSnack(context, failure);
        return;
      }
      final r = await repo.setFolderLockMode(folder.id, FolderLockMode.pin);
      if (r case Err(:final failure)) {
        await pins.removePin(folder.id);
        if (context.mounted) showFailureSnack(context, failure);
        return;
      }
      ref.read(folderAccessProvider.notifier).grant(folder.id);
      if (context.mounted) showAppSnack(context, 'Locked with a PIN');
  }
}

class _LockSheet extends StatelessWidget {
  const _LockSheet({required this.folder, required this.device});

  final Folder folder;
  final EngineCapability? device;

  @override
  Widget build(BuildContext context) {
    final deviceOk = device?.available ?? false;
    Widget option(
      FolderLockMode mode,
      IconData icon,
      String title,
      String subtitle, {
      bool enabled = true,
    }) => ListTile(
      enabled: enabled,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: folder.lockMode == mode
          ? Icon(Icons.check_rounded, color: context.colors.primary)
          : null,
      onTap: () => Navigator.pop(context, mode),
    );
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.x4,
                Space.gutter,
                Space.x2,
              ),
              child: Text(
                'Lock "${folder.name}"',
                style: context.text.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Text(
                folderLockExplainer,
                style: context.text.bodyMedium?.copyWith(
                  color: context.ds.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: Space.x2),
            option(
              FolderLockMode.device,
              Icons.fingerprint_rounded,
              'Fingerprint or screen lock',
              deviceOk
                  ? 'Uses the same prompt as unlocking your phone'
                  : (device?.note ?? 'Not available on this device'),
              enabled: deviceOk,
            ),
            option(
              FolderLockMode.pin,
              Icons.pin_rounded,
              folder.lockMode == FolderLockMode.pin
                  ? 'Change folder PIN'
                  : 'PIN for this folder',
              '4 to 8 digits, separate from your phone’s PIN',
            ),
            if (folder.isLocked)
              option(
                FolderLockMode.none,
                Icons.lock_open_rounded,
                'Remove lock',
                'Anyone using IDSnap can open this folder',
              ),
            const SizedBox(height: Space.x2),
          ],
        ),
      ),
    );
  }
}

/// Shown instead of a locked folder's contents.
class LockedFolderView extends StatelessWidget {
  const LockedFolderView({
    required this.name,
    required this.onUnlock,
    super.key,
  });

  final String name;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.lock_rounded,
    title: '"$name" is locked',
    message: 'Unlock to see what’s inside. $folderLockExplainer',
    actionLabel: 'Unlock',
    onAction: onUnlock,
  );
}

/// Keeps FLAG_SECURE on while [active] and this widget is mounted.
class FolderSecureScope extends ConsumerStatefulWidget {
  const FolderSecureScope({
    required this.active,
    required this.child,
    super.key,
  });

  final bool active;
  final Widget child;

  @override
  ConsumerState<FolderSecureScope> createState() => _FolderSecureScopeState();
}

class _FolderSecureScopeState extends ConsumerState<FolderSecureScope> {
  FolderSecureFlag? _flag;
  bool _held = false;

  void _sync() {
    _flag ??= ref.read(folderSecureFlagProvider);
    if (widget.active && !_held) {
      _flag!.acquire();
      _held = true;
    } else if (!widget.active && _held) {
      _flag!.release();
      _held = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(FolderSecureScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    if (_held) _flag?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
