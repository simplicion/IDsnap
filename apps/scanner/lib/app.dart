import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:docscan_scanner/lock_gate.dart';
import 'package:docscan_scanner/router.dart';
import 'package:engine_security/engine_security.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DocScanApp extends ConsumerStatefulWidget {
  const DocScanApp({super.key});

  @override
  ConsumerState<DocScanApp> createState() => _DocScanAppState();
}

class _DocScanAppState extends ConsumerState<DocScanApp>
    with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter(redirect: _proRedirect);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  /// Re-checks purchases (renewals, cancellations, pending payments that
  /// completed) whenever the app comes back to the foreground. Nothing to
  /// check, and no network, in the free build (ADR-0013).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (ref.read(monetizationModeProvider).isFree) return;
    unawaited(
      ref.read(entitlementServiceProvider).refresh().whenComplete(() {
        if (mounted) ref.read(entitlementProvider.notifier).recheck();
      }),
    );
  }

  /// Backstop for Pro features reached without ensurePro (document
  /// shortcuts, deep links): a locked location goes to the paywall. Never
  /// fires in the free build: nothing is locked.
  String? _proRedirect(BuildContext context, GoRouterState state) {
    if (ref.read(monetizationModeProvider).isFree) return null;
    final entitlement =
        ref.read(entitlementSimulationProvider)?.state ??
        ref.read(entitlementServiceProvider).current;
    return proRedirect(state.uri, entitlement);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentSettingsProvider.select((s) => s.theme));
    return MaterialApp.router(
      title: 'IDSnap',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (theme) {
        ThemePreference.system => ThemeMode.system,
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
      },
      routerConfig: _router,
      builder: (context, child) => LockGate(
        setSecure: const SecureWindow().setSecure,
        externalLaunch: const SecureWindow().consumeExternalLaunch,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
