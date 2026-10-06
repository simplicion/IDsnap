import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:feature_authenticator/feature_authenticator.dart';
import 'package:feature_home/feature_home.dart';
import 'package:feature_library/feature_library.dart';
import 'package:feature_notes/feature_notes.dart';
import 'package:feature_paywall/feature_paywall.dart';
import 'package:feature_qr/feature_qr.dart';
import 'package:feature_scan/feature_scan.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:feature_tools/feature_tools.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// App routes: four tabs in a stateful shell (each keeps its own stack) plus
/// full-screen flows pushed over the shell. Feature packages own their
/// screens; this file only composes them (see Routes in docscan_contracts).
/// [redirect] is the IDSnap Pro backstop (see proRedirect in contracts).
GoRouter buildRouter({GoRouterRedirect? redirect}) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: Routes.home,
  redirect: redirect,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.home,
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.authenticator,
              builder: (context, state) => const AuthenticatorScreen(),
              routes: authenticatorRoutes(rootNavigatorKey),
            ),
          ],
        ),
        // "ID Vault" tab: the library/vault keeps its /files paths.
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.files,
              builder: (context, state) => const FilesScreen(),
              routes: libraryRoutes(rootNavigatorKey),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: Routes.tools,
              builder: (context, state) => const ToolsScreen(),
              routes: [
                ...toolRoutes(rootNavigatorKey),
                // QR & barcode tool: one entry point, easy to gate.
                ...qrRoutes(rootNavigatorKey),
              ],
            ),
          ],
        ),
      ],
    ),
    // Settings is no longer a tab: a full-screen page pushed over the shell
    // (Home's app-bar gear calls context.push(Routes.settings)).
    GoRoute(
      path: Routes.settings,
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const SettingsScreen(),
      routes: settingsRoutes(rootNavigatorKey),
    ),
    // Secure notes: pushed over the shell from Home and the ID Vault.
    GoRoute(
      path: Routes.notes,
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const NotesScreen(),
      routes: notesRoutes(rootNavigatorKey),
    ),
    ...scanRoutes(),
    // IDSnap Pro: paywall, Settings › Subscription, terms.
    ...paywallRoutes(),
  ],
);

/// Bottom navigation on phones, navigation rail on tablets / wide windows.
class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  static const List<({IconData icon, String label, IconData selected})>
  _destinations = [
    (icon: Icons.home_outlined, selected: Icons.home_rounded, label: 'Home'),
    (
      icon: Icons.shield_outlined,
      selected: Icons.shield_rounded,
      label: 'Authenticator',
    ),
    (
      icon: Icons.badge_outlined,
      selected: Icons.badge_rounded,
      label: 'ID Vault',
    ),
    (
      icon: Icons.handyman_outlined,
      selected: Icons.handyman_rounded,
      label: 'Tools',
    ),
  ];

  void _go(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _go,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selected),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
