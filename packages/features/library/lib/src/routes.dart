import 'package:feature_library/src/document_screen.dart';
import 'package:feature_library/src/folder_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Child routes of `/files`. They are pushed on the root navigator so the
/// bottom navigation bar is covered while viewing a document.
List<RouteBase> libraryRoutes(GlobalKey<NavigatorState> rootKey) => [
  GoRoute(
    path: 'doc/:id',
    parentNavigatorKey: rootKey,
    builder: (context, state) =>
        DocumentScreen(documentId: state.pathParameters['id']!),
  ),
  GoRoute(
    path: 'folder/:id',
    parentNavigatorKey: rootKey,
    builder: (context, state) =>
        FolderScreen(folderId: state.pathParameters['id']!),
  ),
];
