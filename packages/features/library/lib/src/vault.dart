import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Session-only dismissal of the privacy banner (it returns next launch).
class PrivacyBannerDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

final privacyBannerDismissedProvider =
    NotifierProvider<PrivacyBannerDismissed, bool>(PrivacyBannerDismissed.new);

/// "Offline vault · Your documents never leave this phone" (roadmap B5).
/// IDSnap connects to the internet only for its licence and payments
/// (ADR-0008 as amended, ADR-0012); an architecture test keeps all network
/// code inside engine_billing.
class PrivacyBanner extends ConsumerWidget {
  const PrivacyBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final show = ref.watch(
      currentSettingsProvider.select((s) => s.showPrivacyBanner),
    );
    if (!show || ref.watch(privacyBannerDismissedProvider)) {
      return const SizedBox.shrink();
    }
    final ds = context.ds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.x2,
        Space.gutter,
        0,
      ),
      child: Semantics(
        container: true,
        label: 'Offline vault. Your documents never leave this phone.',
        child: Container(
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, 0, Space.x2),
          decoration: BoxDecoration(
            color: ds.successContainer,
            borderRadius: Radii.cardAll,
          ),
          child: Row(
            children: [
              Icon(Icons.shield_rounded, color: ds.success, size: 20),
              const SizedBox(width: Space.x3),
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    'Offline vault · Your documents never leave this phone',
                    style: context.text.labelLarge?.copyWith(color: ds.success),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Hide for now',
                icon: Icon(Icons.close_rounded, color: ds.success, size: 20),
                onPressed: () =>
                    ref.read(privacyBannerDismissedProvider.notifier).dismiss(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Secure notes" entry at the top of the ID Vault (feature_notes).
class SecureNotesEntry extends StatelessWidget {
  const SecureNotesEntry({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x2, Space.gutter, 0),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.sticky_note_2_outlined),
        title: const Text('Secure notes'),
        subtitle: const Text('Passwords, account details, recovery codes'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push(Routes.notes),
      ),
    ),
  );
}
