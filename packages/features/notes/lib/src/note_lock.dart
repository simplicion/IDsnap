import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_notes/src/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Honest copy: every note is encrypted on the phone; a lock adds a gate.
const noteLockExplainer =
    'All notes are encrypted on this phone. A lock also hides this note '
    'behind your fingerprint, screen lock or a PIN, and keeps it out of '
    'search.';

/// The phone's biometrics / screen lock. An unlock in the last few seconds
/// (App Lock just opened the app) counts. `true` when the phone has no
/// screen lock at all (nothing to check against).
Future<bool> _deviceAuth(WidgetRef ref, String reason) async {
  final lock = ref.read(appLockProvider);
  if (!(await lock.capability()).available) return true;
  if (lock.recentlyAuthenticated()) return true;
  return (await lock.authenticate(reason)).valueOrNull ?? false;
}

/// Unlocks [note] for this session. Returns true when it may be shown.
Future<bool> unlockNote(BuildContext context, WidgetRef ref, Note note) async {
  if (!note.isLocked || ref.read(unlockedNotesProvider).contains(note.id)) {
    return true;
  }
  final bool ok;
  switch (note.lockMode) {
    case FolderLockMode.pin:
      ok =
          await showDialog<bool>(
            context: context,
            builder: (_) => _NotePinDialog(note: note),
          ) ??
          false;
    case FolderLockMode.device || FolderLockMode.none:
      ok = await _deviceAuth(ref, 'Unlock "${note.displayTitle}"');
  }
  if (ok) ref.read(unlockedNotesProvider.notifier).add(note.id);
  return ok;
}

/// Lets the user pick how [note] is locked; returns the new mode or null.
Future<FolderLockMode?> chooseNoteLock(
  BuildContext context,
  WidgetRef ref,
  Note note,
) async {
  final mode = await showModalBottomSheet<FolderLockMode>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.gutter),
            child: Text(noteLockExplainer, style: context.text.bodyMedium),
          ),
          ListTile(
            leading: const Icon(Icons.fingerprint_rounded),
            title: const Text('Fingerprint or screen lock'),
            onTap: () => Navigator.pop(context, FolderLockMode.device),
          ),
          ListTile(
            leading: const Icon(Icons.pin_outlined),
            title: const Text('A PIN for this note'),
            onTap: () => Navigator.pop(context, FolderLockMode.pin),
          ),
          if (note.isLocked)
            ListTile(
              leading: const Icon(Icons.lock_open_rounded),
              title: const Text('Remove lock'),
              onTap: () => Navigator.pop(context, FolderLockMode.none),
            ),
        ],
      ),
    ),
  );
  if (mode == null || !context.mounted) return null;
  // Changing or removing a lock requires passing the current one.
  if (note.isLocked && !await unlockNote(context, ref, note)) return null;
  if (!context.mounted) return null;
  final pins = ref.read(notePinStoreProvider);
  switch (mode) {
    case FolderLockMode.pin:
      final pin = await promptNotePin(context);
      if (pin == null || !context.mounted) return null;
      final saved = await pins.setPin(notePinKey(note.id), pin);
      if (saved case Err(:final failure)) {
        if (context.mounted) showFailureSnack(context, failure);
        return null;
      }
    case FolderLockMode.device:
      if (!await _deviceAuth(ref, 'Confirm to lock this note')) return null;
      await pins.removePin(notePinKey(note.id));
    case FolderLockMode.none:
      await pins.removePin(notePinKey(note.id));
  }
  return mode;
}

/// Asks for a new 4–8 digit PIN twice.
Future<String?> promptNotePin(BuildContext context) async {
  final first = await _askPin(context, 'Choose a PIN (4–8 digits)');
  if (first == null || !context.mounted) return null;
  final second = await _askPin(context, 'Enter the PIN again');
  if (second == null || !context.mounted) return null;
  if (first != second) {
    showAppSnack(context, "The PINs didn't match. Try again.");
    return null;
  }
  return first;
}

Future<String?> _askPin(BuildContext context, String title) =>
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

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _pin,
      autofocus: true,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(8),
      ],
      decoration: const InputDecoration(labelText: 'PIN'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (FolderPinStore.isValidPin(_pin.text)) {
            Navigator.pop(context, _pin.text);
          }
        },
        child: const Text('OK'),
      ),
    ],
  );
}

class _NotePinDialog extends ConsumerStatefulWidget {
  const _NotePinDialog({required this.note});

  final Note note;

  @override
  ConsumerState<_NotePinDialog> createState() => _NotePinDialogState();
}

class _NotePinDialogState extends ConsumerState<_NotePinDialog> {
  final _pin = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _pin.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(notePinStoreProvider)
        .verifyPin(notePinKey(widget.note.id), _pin.text);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case Ok(value: PinAccepted()):
        Navigator.pop(context, true);
      case Ok(value: PinRejected(:final retryAfter)):
        _pin.clear();
        setState(
          () => _error = retryAfter == null
              ? 'Wrong PIN. Try again.'
              : 'Wrong PIN. Try again in ${_wait(retryAfter)}.',
        );
      case Ok(value: PinThrottled(:final retryAfter)):
        setState(() => _error = 'Too many tries. Wait ${_wait(retryAfter)}.');
      case Err(:final failure):
        setState(() => _error = failure.recovery);
    }
  }

  static String _wait(Duration d) =>
      d.inMinutes >= 1 ? '${d.inMinutes} min' : '${d.inSeconds.clamp(1, 59)} s';

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.lock_rounded),
    title: Text('Unlock "${widget.note.displayTitle}"'),
    content: TextField(
      key: const Key('note-pin'),
      controller: _pin,
      autofocus: true,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: 'PIN', errorText: _error),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: const Text('Unlock'),
      ),
    ],
  );
}
