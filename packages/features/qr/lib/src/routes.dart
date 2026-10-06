import 'package:feature_qr/src/generate_screen.dart';
import 'package:feature_qr/src/history_screen.dart';
import 'package:feature_qr/src/scan_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Relative path of the QR tool under `/tools` (see `Routes.qrScanner`).
const qrToolPath = 'qr';

/// The QR & barcode tool's routes, relative to `/tools`: the scanner, with
/// `generate` and `history` below it. This is the feature's single entry
/// point: pass [redirect] to gate the whole tool (it runs for every
/// sub-route too).
List<RouteBase> qrRoutes(
  GlobalKey<NavigatorState> rootKey, {
  GoRouterRedirect? redirect,
}) => [
  GoRoute(
    path: qrToolPath,
    parentNavigatorKey: rootKey,
    redirect: redirect,
    builder: (context, state) => const QrScanScreen(),
    routes: [
      GoRoute(
        path: 'generate',
        parentNavigatorKey: rootKey,
        builder: (context, state) => const QrGenerateScreen(),
      ),
      GoRoute(
        path: 'history',
        parentNavigatorKey: rootKey,
        builder: (context, state) => const QrHistoryScreen(),
      ),
    ],
  ),
];
