import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:feature_paywall/src/copy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Settings › Subscription: current plan and expiry, refresh the licence,
/// manage or cancel the monthly plan at 180 Pay.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _busy = false;

  EntitlementService get _service => ref.read(entitlementServiceProvider);

  Future<void> _manage() async {
    final opened = await _service.openManageSubscription();
    if (!mounted || opened) return;
    showAppSnack(
      context,
      "Couldn't open the $paymentProvider portal. To cancel: $cancelHowTo.",
    );
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final result = await _service.refreshLicence();
    if (!mounted) return;
    setState(() => _busy = false);
    ref.read(entitlementProvider.notifier).recheck();
    showAppSnack(
      context,
      result.ok
          ? 'Licence refreshed.'
          : (result.message ?? "Couldn't reach the licence server."),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(entitlementProvider);
    final (title, detail) = describeSubscription(state, DateTime.now());
    final monthly = state is MonthlyEntitlement;

    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.x2,
          Space.gutter,
          Space.x12,
        ),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(
                    state.isEntitled
                        ? Icons.workspace_premium_rounded
                        : Icons.lock_clock_rounded,
                    color: state.isEntitled
                        ? context.colors.primary
                        : context.ds.warning,
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: context.text.titleMedium),
                        const SizedBox(height: Space.x1),
                        Text(detail, style: context.text.bodyMedium),
                        if (state.purchasePending) ...[
                          const SizedBox(height: Space.x2),
                          Text(
                            'Waiting for $paymentProvider to confirm a '
                            'payment.',
                            style: context.text.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.x4),
          if (!(state is MonthlyEntitlement && state.willRenew))
            FilledButton(
              onPressed: () => unawaited(context.push(Routes.paywall())),
              child: Text(
                state is DayPassEntitlement
                    ? 'Add days or go monthly'
                    : 'See IDSnap Pro plans',
              ),
            ),
          const SizedBox(height: Space.x2),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh licence'),
          ),
          if (monthly) ...[
            const SizedBox(height: Space.x2),
            OutlinedButton.icon(
              onPressed: () => unawaited(_manage()),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Manage or cancel monthly plan'),
            ),
          ],
          const SizedBox(height: Space.x5),
          Text('Cancelling', style: context.text.titleSmall),
          const SizedBox(height: Space.x1),
          Text(
            'To cancel the monthly plan, $cancelHowTo. Everything stays '
            'unlocked until the end of the month you paid for, and your '
            "documents are never locked away. A day pass doesn't renew, so "
            "there's nothing to cancel.",
            style: context.text.bodySmall?.copyWith(
              color: context.ds.textSecondary,
            ),
          ),
          const SizedBox(height: Space.x3),
          Text(
            networkPrivacyLine,
            style: context.text.bodySmall?.copyWith(
              color: context.ds.textSecondary,
            ),
          ),
          const SizedBox(height: Space.x2),
          Text(
            alwaysFreeLine,
            style: context.text.bodySmall?.copyWith(
              color: context.ds.textSecondary,
            ),
          ),
          const SizedBox(height: Space.x2),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () =>
                  unawaited(context.push(Routes.subscriptionTerms)),
              child: const Text('Terms and privacy'),
            ),
          ),
          if (!kReleaseMode) const _DeveloperSimulation(),
        ],
      ),
    );
  }
}

/// Title and detail for the plan card.
@visibleForTesting
(String, String) describeSubscription(EntitlementState s, DateTime now) =>
    switch (s) {
      FreeEntitlement() => (freeAppTitle, freeAppLine),
      TrialEntitlement(:final endsAt) => (
        'Free day — ends in ${formatTimeLeft(endsAt, now)}',
        'Every feature is unlocked until ${formatMoment(endsAt)}. No card '
            'needed, and nothing is charged when it ends.',
      ),
      DayPassEntitlement(:final expiresAt) => (
        'Day pass — ends in ${formatTimeLeft(expiresAt, now)}',
        'Everything is unlocked until ${formatMoment(expiresAt)}. It ends '
            'by itself; nothing renews.',
      ),
      MonthlyEntitlement(:final renewsAt, inGracePeriod: true) => (
        'Monthly plan',
        "We haven't confirmed this month's renewal yet"
            '${renewsAt == null ? '' : ' (due ${formatDay(renewsAt)})'}. '
            'Everything stays unlocked for a few days; tap "Refresh '
            'licence" while online.',
      ),
      MonthlyEntitlement(:final renewsAt, :final willRenew) => (
        'Monthly plan',
        renewsAt == null
            ? 'Active.'
            : willRenew
            ? 'Renews on ${formatDay(renewsAt)}.'
            : 'Cancelled — everything stays unlocked until '
                  '${formatDay(renewsAt)}.',
      ),
      ExpiredEntitlement(reason: LapseReason.notActivated) => (
        'Not activated yet',
        statusLine(s, now: now),
      ),
      ExpiredEntitlement() => ('No active plan', statusLine(s, now: now)),
    };

/// Debug/profile builds only: simulate a plan without the server.
class _DeveloperSimulation extends ConsumerWidget {
  const _DeveloperSimulation();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(entitlementSimulationProvider);
    void select(EntitlementSimulation? v) =>
        ref.read(entitlementSimulationProvider.notifier).select(v);
    return Padding(
      padding: const EdgeInsets.only(top: Space.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Developer: simulate plan (not in release builds)',
            style: context.text.titleSmall,
          ),
          const SizedBox(height: Space.x2),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              ChoiceChip(
                label: const Text('Real'),
                selected: current == null,
                onSelected: (_) => select(null),
              ),
              for (final s in EntitlementSimulation.values)
                ChoiceChip(
                  label: Text(s.name),
                  selected: current == s,
                  onSelected: (_) => select(s),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
