import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:feature_tools/src/kits/kit_catalog.dart';
import 'package:feature_tools/src/kits/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

IconData kitIcon(String id) => switch (id) {
  'us-visa' || 'schengen-visa' => Icons.flight_takeoff_rounded,
  'exam-portal' => Icons.school_rounded,
  'job-application' => Icons.work_rounded,
  _ => Icons.tune_rounded,
};

/// Lists application kits: ready-made upload packs for visa, exam and job
/// portals, plus a custom kit.
class KitsHubScreen extends ConsumerWidget {
  const KitsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Application kits')),
    // Free build only; empty otherwise (ADR-0013).
    bottomNavigationBar: const AdBannerSlot(),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.x2,
        Space.gutter,
        Space.x10,
      ),
      children: [
        Text(
          'Get photos, signatures and documents ready for upload portals in '
          'one go — sized, cropped and under the file limit.',
          style: context.text.bodyMedium?.copyWith(
            color: context.ds.textSecondary,
          ),
        ),
        const SizedBox(height: Space.x2),
        const OfflineBadge(),
        const SizedBox(height: Space.x4),
        for (final kit in kitCatalog) ...[
          _KitCard(kit: kit),
          const SizedBox(height: Space.x3),
        ],
        _KitCard(kit: ref.watch(customKitProvider)),
        const SizedBox(height: Space.x4),
        Text(
          'Limits come from published guidance and are reviewed regularly, '
          "but portals change. Always check the official site — IDSnap can't "
          'guarantee an upload will be accepted.',
          style: context.text.bodySmall?.copyWith(
            color: context.ds.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _KitCard extends StatelessWidget {
  const _KitCard({required this.kit});

  final ApplicationKit kit;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => context.push(Routes.kit(kit.id)),
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(kitIcon(kit.id), color: context.colors.secondary),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kit.label, style: context.text.titleSmall),
                  const SizedBox(height: Space.x1),
                  Text(
                    kit.description,
                    style: context.text.bodySmall?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Space.x2),
                  Wrap(
                    spacing: Space.x2,
                    runSpacing: Space.x1,
                    children: [for (final item in kit.items) Pill(item.label)],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    ),
  );
}
