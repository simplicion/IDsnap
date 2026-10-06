import 'package:feature_authenticator/src/account_screen.dart';
import 'package:feature_authenticator/src/add_account_screen.dart';
import 'package:feature_authenticator/src/scan_qr_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Child routes of `/authenticator`, pushed on the root navigator so they
/// cover the navigation bar.
List<RouteBase> authenticatorRoutes(GlobalKey<NavigatorState> rootKey) => [
  GoRoute(
    path: 'add',
    parentNavigatorKey: rootKey,
    builder: (context, state) => const AddAccountScreen(),
  ),
  GoRoute(
    path: 'scan',
    parentNavigatorKey: rootKey,
    builder: (context, state) => const ScanQrScreen(),
  ),
  GoRoute(
    path: 'account/:id',
    parentNavigatorKey: rootKey,
    builder: (context, state) =>
        AccountScreen(accountId: state.pathParameters['id']!),
  ),
];
