import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:feature_scan/src/screens/crop_screen.dart';
import 'package:feature_scan/src/screens/review_screen.dart';
import 'package:feature_scan/src/screens/save_screen.dart';
import 'package:feature_scan/src/screens/scan_launch_screen.dart';
import 'package:go_router/go_router.dart';

/// Top-level scan flow routes. Register outside the tab shell so they cover
/// the navigation bar.
List<RouteBase> scanRoutes() => [
  GoRoute(
    path: '/scan',
    builder: (context, state) => ScanLaunchScreen(
      source:
          ScanSource.values.asNameMap()[state.uri.queryParameters['source']] ??
          ScanSource.camera,
    ),
    routes: [
      GoRoute(
        path: 'review',
        builder: (context, state) => const ReviewScreen(),
      ),
      GoRoute(
        path: 'crop/:pageId',
        builder: (context, state) =>
            CropScreen(pageId: state.pathParameters['pageId']!),
      ),
      GoRoute(path: 'save', builder: (context, state) => const SaveScreen()),
    ],
  ),
];
