import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App Lock settings (roadmap B2). Copy is deliberately honest: the vault
/// is encrypted at rest (ADR-0010); App Lock is the access gate on top.
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  static const explanation =
      'Your vault files and database are encrypted on this phone (AES-256). '
      'App Lock also keeps other people out of IDSnap while the phone is '
      'unlocked.';

  static const footnote =
      'While App Lock is on, IDSnap hides its content in the recent-apps '
      'view and blocks screenshots. If you forget your screen lock, reset it '
      "in your phone's settings — IDSnap never stores a separate password. "
      'The encryption key never leaves this phone, so a phone backup '
      "can't restore your vault to a new phone. Before you change phones, "
      'use Your data › Export all data.';

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _busy = false;

  Future<void> _toggle(bool enable) async {
    final lock = ref.read(appLockProvider);
    setState(() => _busy = true);
    try {
      // The phone lost its screen lock: nobody can pass the prompt, and
      // removing the screen lock already required the owner's credential.
      if (!enable && !(await lock.capability()).available) {
        await ref
            .read(settingsProvider.notifier)
            .change((s) => s.copyWith(appLock: false));
        if (mounted) showAppSnack(context, 'App Lock is off');
        return;
      }
      // Turning the lock on *or off* requires proving you're the owner.
      final result = await lock.authenticate(
        enable ? 'Confirm to turn on App Lock' : 'Confirm to turn off App Lock',
      );
      if (!mounted) return;
      switch (result) {
        case Ok(value: true):
          await ref
              .read(settingsProvider.notifier)
              .change((s) => s.copyWith(appLock: enable));
          if (mounted) {
            showAppSnack(
              context,
              enable ? 'App Lock is on' : 'App Lock is off',
            );
          }
        case Ok():
          break; // Cancelled — nothing changes.
        case Err(:final failure):
          showAppSnack(
            context,
            failure.detail ?? '${failure.title}. ${failure.recovery}',
          );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    final capability = ref.watch(_lockCapabilityProvider);
    final available = capability.value?.available ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('App Lock')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.x12),
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.gutter),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconBadge(Icons.lock_rounded),
                const SizedBox(width: Space.x4),
                Expanded(
                  child: Text(
                    SecurityScreen.explanation,
                    style: context.text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint_rounded),
            title: const Text('Lock IDSnap'),
            subtitle: Text(
              available
                  ? 'Use fingerprint, face or your screen lock to open the app'
                  : capability.value?.note ?? 'Checking this device…',
            ),
            value: settings.appLock,
            onChanged: _busy || (!available && !settings.appLock)
                ? null
                : _toggle,
          ),
          if (settings.appLock) ...[
            const SectionHeader('Lock again after'),
            RadioGroup<int>(
              groupValue: settings.lockAfterMinutes,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .change((s) => s.copyWith(lockAfterMinutes: v)),
              child: const Column(
                children: [
                  RadioListTile<int>(value: 0, title: Text('Immediately')),
                  RadioListTile<int>(value: 1, title: Text('After 1 minute')),
                  RadioListTile<int>(value: 5, title: Text('After 5 minutes')),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.all(Space.gutter),
            child: Text(
              SecurityScreen.footnote,
              style: context.text.bodySmall?.copyWith(
                color: context.ds.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final _lockCapabilityProvider = FutureProvider.autoDispose<EngineCapability>(
  (ref) => ref.watch(appLockProvider).capability(),
);
