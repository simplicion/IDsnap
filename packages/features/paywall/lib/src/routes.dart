import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:feature_paywall/src/paywall_screen.dart';
import 'package:feature_paywall/src/subscription_screen.dart';
import 'package:feature_paywall/src/terms_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Top-level routes: `/paywall`, `/subscription`, `/subscription/terms`.
/// Register outside the tab shell so they cover the navigation bar.
///
/// In the free, ad-supported build (`IDSNAP_MONETIZATION=ads`, ADR-0013)
/// nothing links to these routes; opened directly (a stale deep link),
/// each one closes itself at once instead of showing a paywall.
List<RouteBase> paywallRoutes() => [
  GoRoute(
    path: '/paywall',
    builder: (context, state) => _PaidOnly(
      child: PaywallScreen(
        feature: ProFeature.values
            .asNameMap()[state.uri.queryParameters['feature']],
        from: state.uri.queryParameters['from'],
      ),
    ),
  ),
  GoRoute(
    path: Routes.subscription,
    builder: (context, state) => const _PaidOnly(child: SubscriptionScreen()),
    routes: [
      GoRoute(
        path: 'terms',
        builder: (context, state) =>
            const _PaidOnly(child: SubscriptionTermsScreen()),
      ),
    ],
  ),
];

/// Shows [child] in the paid modes; in the free build pops straight back
/// (or goes Home when there is nothing to go back to).
class _PaidOnly extends ConsumerStatefulWidget {
  const _PaidOnly({required this.child});

  final Widget child;

  @override
  ConsumerState<_PaidOnly> createState() => _PaidOnlyState();
}

class _PaidOnlyState extends ConsumerState<_PaidOnly> {
  bool _closing = false;

  void _close() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final router = GoRouter.of(context);
      if (router.canPop()) {
        // "true": the caller asked for a feature and may use it.
        router.pop(true);
      } else {
        router.go(Routes.home);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(monetizationModeProvider).isFree) return widget.child;
    _close();
    return const Scaffold(body: SizedBox.shrink());
  }
}
