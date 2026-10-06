import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:feature_paywall/src/copy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Prices from the licence server (or the labelled fallback).
final pricingProvider = FutureProvider.autoDispose<ProPricing>(
  (ref) => ref.watch(entitlementServiceProvider).pricing(),
);

/// Quick picks for the day pass; anything else via the stepper.
const dayPassPresets = [1, 3, 7];

/// IDSnap Pro paywall: Monthly (recommended) or a day pass for N days.
/// Pops `true` when the user ends up entitled.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, this.feature, this.from});

  /// The locked feature that opened the paywall, if any.
  final ProFeature? feature;

  /// Location to continue to after a purchase (router backstop).
  final String? from;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  ProPlan _plan = ProPlan.monthly;
  int _days = 1;
  bool _busy = false;
  bool _waitingForPayment = false;
  String? _message;

  EntitlementService get _service => ref.read(entitlementServiceProvider);

  Future<void> _buy(ProPricing pricing) async {
    final request = _plan == ProPlan.monthly
        ? const ProPurchase.monthly()
        : ProPurchase.dayPass(_days.clamp(pricing.minDays, pricing.maxDays));
    final simulation = ref.read(entitlementSimulationProvider);
    if (!kReleaseMode && simulation != null) {
      ref
          .read(entitlementSimulationProvider.notifier)
          .select(
            request.plan == ProPlan.monthly
                ? EntitlementSimulation.monthly
                : EntitlementSimulation.dayPass,
          );
      _finish(simulated: true);
      return;
    }
    setState(() {
      _busy = true;
      _waitingForPayment = true;
      _message = null;
    });
    final outcome = await _service.purchase(request);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _waitingForPayment = false;
    });
    switch (outcome.kind) {
      case PurchaseOutcomeKind.purchased:
        _finish();
      case PurchaseOutcomeKind.pending:
        setState(
          () => _message =
              "We haven't received the payment confirmation from "
              '$paymentProvider yet. If you paid, IDSnap unlocks by itself '
              'within a few minutes while you are online — or tap '
              '"Refresh licence". You can close this screen.',
        );
      case PurchaseOutcomeKind.cancelled:
        break;
      case PurchaseOutcomeKind.failed:
        setState(
          () => _message =
              outcome.message ?? 'The payment did not go through. Try again.',
        );
      case PurchaseOutcomeKind.unavailable:
        setState(
          () => _message =
              outcome.message ??
              'Connect to the internet to pay. You were not charged.',
        );
    }
  }

  Future<void> _refreshLicence() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final result = await _service.refreshLicence();
    if (!mounted) return;
    setState(() => _busy = false);
    ref.read(entitlementProvider.notifier).recheck();
    final state = ref.read(entitlementProvider);
    if (result.ok && state.isEntitled && widget.feature != null) {
      _finish(refreshed: true);
    } else {
      setState(
        () => _message = result.ok
            ? 'Licence is up to date.'
            : (result.message ?? "Couldn't reach the licence server."),
      );
    }
  }

  void _finish({bool refreshed = false, bool simulated = false}) {
    ref.read(entitlementProvider.notifier).recheck();
    showAppSnack(
      context,
      simulated
          ? 'Simulated purchase (debug build).'
          : refreshed
          ? 'Licence refreshed.'
          : 'Payment confirmed. Thank you!',
    );
    final from = widget.from;
    if (from != null) {
      context.pushReplacement(from);
    } else if (context.canPop()) {
      context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(entitlementProvider);
    final pricing = ref.watch(pricingProvider).value ?? fallbackPricing;
    final feature = widget.feature;
    final days = _days.clamp(pricing.minDays, pricing.maxDays);
    final subscribed = state is MonthlyEntitlement && state.willRenew;
    final notActivated =
        state is ExpiredEntitlement && state.reason == LapseReason.notActivated;
    final total = _plan == ProPlan.monthly
        ? pricing.monthPriceCents
        : pricing.dayPassCents(days);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Not now',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.canPop()
              ? context.pop(state.isEntitled)
              : context.go(Routes.home),
        ),
        title: const Text('IDSnap Pro'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.x2,
                Space.gutter,
                Space.x10,
              ),
              children: [
                Text(
                  feature != null && !canUse(feature, state)
                      ? '${feature.label} is part of IDSnap Pro'
                      : 'Get more done with IDSnap Pro',
                  style: context.text.headlineSmall,
                ),
                const SizedBox(height: Space.x2),
                Text(
                  statusLine(state),
                  style: context.text.bodyLarge?.copyWith(
                    color: context.ds.textSecondary,
                  ),
                ),
                if (notActivated) ...[
                  const SizedBox(height: Space.x3),
                  _ActivateCard(
                    busy: _busy,
                    onRetry: () => unawaited(_refreshLicence()),
                  ),
                ],
                const SizedBox(height: Space.x5),
                for (final (icon, title, body) in proBenefits)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconBadge(icon, size: 40),
                        const SizedBox(width: Space.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: context.text.titleSmall),
                              Text(
                                body,
                                style: context.text.bodySmall?.copyWith(
                                  color: context.ds.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  alwaysFreeLine,
                  style: context.text.bodySmall?.copyWith(
                    color: context.ds.textSecondary,
                  ),
                ),
                const SizedBox(height: Space.x5),
                Semantics(
                  header: true,
                  child: Text('Choose a plan', style: context.text.titleMedium),
                ),
                const SizedBox(height: Space.x3),
                _PlanCard(
                  title: 'Monthly',
                  price: '${pricing.format(pricing.monthPriceCents)}/month',
                  detail: subscribed
                      ? 'You already have this plan'
                      : 'Everything unlocked. Renews monthly; cancel anytime.',
                  badge: 'Recommended',
                  selected: _plan == ProPlan.monthly,
                  onTap: _busy
                      ? null
                      : () => setState(() => _plan = ProPlan.monthly),
                ),
                const SizedBox(height: Space.x3),
                _PlanCard(
                  title: 'Day pass',
                  price: '${pricing.format(pricing.dayPriceCents)}/day',
                  detail: 'Pay once for the days you need. Ends by itself.',
                  selected: _plan == ProPlan.dayPass,
                  onTap: _busy
                      ? null
                      : () => setState(() => _plan = ProPlan.dayPass),
                  child: _plan == ProPlan.dayPass
                      ? _DayPicker(
                          days: days,
                          pricing: pricing,
                          enabled: !_busy,
                          onChanged: (d) => setState(() => _days = d),
                          onChooseMonthly: () =>
                              setState(() => _plan = ProPlan.monthly),
                        )
                      : null,
                ),
                const SizedBox(height: Space.x3),
                if (!pricing.fromServer)
                  Text(
                    "Prices are approximate: IDSnap couldn't reach its "
                    'server to check them. You always see the exact amount on '
                    'the $paymentProvider page before you pay.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.ds.warning,
                    ),
                  ),
                const SizedBox(height: Space.x4),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x3),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(_message!, style: context.text.bodyMedium),
                    ),
                  ),
                if (_waitingForPayment)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.x3),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        'Finish paying in the $paymentProvider page that '
                        'opened, then come back. Waiting for the payment '
                        'confirmation…',
                        style: context.text.bodyMedium,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: _busy || (_plan == ProPlan.monthly && subscribed)
                      ? null
                      : () => unawaited(_buy(pricing)),
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _plan == ProPlan.monthly
                              ? 'Subscribe for ${pricing.format(total)}/month'
                              : 'Pay ${pricing.format(total)} for '
                                    '${daysLabel(days)}',
                        ),
                ),
                const SizedBox(height: Space.x2),
                TextButton.icon(
                  onPressed: _busy ? null : () => unawaited(_refreshLicence()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Refresh licence'),
                ),
                const SizedBox(height: Space.x3),
                Text(
                  'Payment is made on the $paymentProvider page in your '
                  'browser — IDSnap never sees your card. Monthly renews '
                  'automatically until you cancel; everything stays unlocked '
                  'until the end of the month you paid for. A day pass is a '
                  'single payment and simply ends after the days you chose. '
                  'IDSnap needs the internet only to check your licence and '
                  'take payments; with a valid licence it works fully '
                  'offline.',
                  style: context.text.bodySmall?.copyWith(
                    color: context.ds.textSecondary,
                  ),
                ),
                const SizedBox(height: Space.x2),
                Wrap(
                  spacing: Space.x2,
                  children: [
                    TextButton(
                      onPressed: () =>
                          unawaited(context.push(Routes.subscriptionTerms)),
                      child: const Text('Terms'),
                    ),
                    TextButton(
                      onPressed: () => unawaited(context.push(Routes.privacy)),
                      child: const Text('Privacy'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivateCard extends StatelessWidget {
  const _ActivateCard({required this.busy, required this.onRetry});

  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    color: context.ds.warningContainer,
    child: Padding(
      padding: const EdgeInsets.all(Space.x4),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: context.ds.warning),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Text(
              'Connect to the internet once to start your free day. After '
              'that IDSnap works offline.',
              style: context.text.bodyMedium?.copyWith(
                color: context.ds.warning,
              ),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.price,
    required this.detail,
    required this.selected,
    required this.onTap,
    this.badge,
    this.child,
  });

  final String title;
  final String price;
  final String detail;
  final String? badge;
  final bool selected;
  final VoidCallback? onTap;

  /// Extra controls shown inside the card (the day picker).
  final Widget? child;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: Radii.cardAll,
      side: BorderSide(
        color: selected ? context.colors.primary : context.ds.border,
        width: selected ? 2 : 1,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          selected: selected,
          button: true,
          label: '$title, $price. $detail',
          excludeSemantics: true,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: selected
                        ? context.colors.primary
                        : context.ds.textSecondary,
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: Space.x2,
                          runSpacing: Space.x1,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(title, style: context.text.titleSmall),
                            if (badge != null) Pill(badge!),
                          ],
                        ),
                        Text(
                          detail,
                          style: context.text.bodySmall?.copyWith(
                            color: context.ds.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  Text(price, style: context.text.titleMedium),
                ],
              ),
            ),
          ),
        ),
        ?child,
      ],
    ),
  );
}

/// Day count: presets 1, 3, 7 plus a stepper up to the server's maximum,
/// the total, and a nudge to monthly once the days cost as much.
class _DayPicker extends StatelessWidget {
  const _DayPicker({
    required this.days,
    required this.pricing,
    required this.enabled,
    required this.onChanged,
    required this.onChooseMonthly,
  });

  final int days;
  final ProPricing pricing;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final VoidCallback onChooseMonthly;

  @override
  Widget build(BuildContext context) {
    final total = pricing.dayPassCents(days);
    final presets = dayPassPresets.where(
      (d) => d >= pricing.minDays && d <= pricing.maxDays,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.x4, 0, Space.x4, Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              for (final d in presets)
                ChoiceChip(
                  label: Text(daysLabel(d)),
                  selected: days == d,
                  onSelected: enabled ? (_) => onChanged(d) : null,
                ),
            ],
          ),
          const SizedBox(height: Space.x3),
          Row(
            children: [
              IconButton.outlined(
                tooltip: 'One day less',
                onPressed: enabled && days > pricing.minDays
                    ? () => onChanged(days - 1)
                    : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '${daysLabel(days)} · ${pricing.format(total)}',
                    key: const ValueKey('day-pass-total'),
                    textAlign: TextAlign.center,
                    style: context.text.titleMedium,
                  ),
                ),
              ),
              IconButton.outlined(
                tooltip: 'One day more',
                onPressed: enabled && days < pricing.maxDays
                    ? () => onChanged(days + 1)
                    : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          Text(
            'Up to ${daysLabel(pricing.maxDays)} at a time. Days add on to '
            'any time you already have.',
            style: context.text.bodySmall?.copyWith(
              color: context.ds.textSecondary,
            ),
          ),
          if (pricing.monthlyIsCheaper(days)) ...[
            const SizedBox(height: Space.x3),
            Card(
              margin: EdgeInsets.zero,
              color: context.colors.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(Space.x3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${daysLabel(days)} cost ${pricing.format(total)}. The '
                      'monthly plan is '
                      '${pricing.format(pricing.monthPriceCents)} for a whole '
                      'month.',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.colors.onPrimaryContainer,
                      ),
                    ),
                    TextButton(
                      onPressed: enabled ? onChooseMonthly : null,
                      child: const Text('Switch to monthly'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
