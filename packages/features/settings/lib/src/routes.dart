import 'package:feature_settings/src/about_screen.dart';
import 'package:feature_settings/src/privacy_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Child routes of `/settings`, pushed over the navigation bar.
List<RouteBase> settingsRoutes(GlobalKey<NavigatorState> rootKey) => [
  GoRoute(
    path: 'privacy',
    parentNavigatorKey: rootKey,
    builder: (context, state) => const PrivacyScreen(),
  ),
  GoRoute(
    path: 'about',
    parentNavigatorKey: rootKey,
    builder: (context, state) => const AboutScreen(),
  ),
];
