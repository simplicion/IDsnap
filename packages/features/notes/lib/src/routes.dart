import 'package:feature_notes/src/note_editor_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Child routes of `/notes`, pushed on the root navigator.
List<RouteBase> notesRoutes(GlobalKey<NavigatorState> rootKey) => [
  GoRoute(
    path: ':id',
    parentNavigatorKey: rootKey,
    builder: (context, state) =>
        NoteEditorScreen(noteId: state.pathParameters['id']!),
  ),
];
