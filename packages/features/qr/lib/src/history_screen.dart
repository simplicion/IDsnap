import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:feature_qr/src/history.dart';
import 'package:feature_qr/src/result_screen.dart';
import 'package:feature_qr/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Local scan history with its on/off settings. Stored only on this phone.
class QrHistoryScreen extends ConsumerWidget {
  const QrHistoryScreen({super.key});

  static const sensitiveHint =
      'Wi-Fi passwords, payment requests and ID card data. Two-step '
      'verification keys are never kept.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(qrHistoryProvider);
    final controller = ref.read(qrHistoryProvider.notifier);
    final state = history.value;

    Future<void> clearAll() async {
      final ok = await confirmAction(
        context,
        title: 'Clear scan history?',
        message: 'Every remembered scan is deleted from this phone.',
        confirmLabel: 'Clear',
        destructive: true,
      );
      if (ok) await controller.clear();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan history'),
        actions: [
          if (state != null && state.entries.isNotEmpty)
            IconButton(
              tooltip: 'Clear all',
              onPressed: () => unawaited(clearAll()),
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ],
      ),
      body: state == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  title: const Text('Keep scan history'),
                  subtitle: const Text(
                    'Saved on this phone only. Turning it off deletes it.',
                  ),
                  value: state.enabled,
                  onChanged: (v) =>
                      unawaited(controller.setEnabled(enabled: v)),
                ),
                SwitchListTile(
                  title: const Text('Include sensitive codes'),
                  subtitle: const Text(sensitiveHint),
                  value: state.includeSensitive,
                  onChanged: state.enabled
                      ? (v) => unawaited(
                          controller.setIncludeSensitive(include: v),
                        )
                      : null,
                ),
                const Divider(),
                if (state.entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.x6),
                    child: EmptyState(
                      icon: Icons.history_rounded,
                      title: 'No scans yet',
                      message: state.enabled
                          ? 'Codes you scan appear here.'
                          : 'Scan history is off.',
                    ),
                  ),
                for (final (i, e) in state.entries.indexed) ...[
                  // One labelled ad card after the 5th entry, never in a
                  // shorter list (ADR-0013). Zero height unless an ad is
                  // already loaded.
                  if (i == AdPlacementPolicy.qrHistoryNativeAfterItem)
                    const AdNativeSlot(
                      placement: AdNativePlacement.qrHistory,
                      padding: EdgeInsets.symmetric(horizontal: Space.gutter),
                    ),
                  ListTile(
                    key: ValueKey(e.id),
                    leading: IconBadge(kindIcon(e.kind)),
                    title: Text(
                      e.summary.isEmpty ? e.kind.label : e.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${e.kind.label} · ${formatRelativeDate(e.scannedAt)}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      onPressed: () => unawaited(controller.remove(e.id)),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CodeResultScreen(code: e.code),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
