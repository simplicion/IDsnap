import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_docs/src/docs_repository.dart';
import 'package:docscan_docs/src/docs_shell.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Documentation site: renders `/docs` (copied into assets) with the
/// DocScan design system, in light or dark mode.
class DocsApp extends StatefulWidget {
  const DocsApp({super.key, this.bundle, this.initialLocation = '/'});

  /// Override for tests.
  final AssetBundle? bundle;
  final String initialLocation;

  @override
  State<DocsApp> createState() => _DocsAppState();
}

class _DocsAppState extends State<DocsApp> {
  late final DocsRepository _repository = DocsRepository(bundle: widget.bundle);
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.system);

  late final GoRouter _router = GoRouter(
    initialLocation: widget.initialLocation,
    routes: [
      GoRoute(path: '/', builder: _page),
      GoRoute(path: '/:a', builder: _page),
      GoRoute(path: '/:a/:b', builder: _page),
    ],
  );

  Widget _page(BuildContext context, GoRouterState state) => DocsShell(
    key: const ValueKey('shell'),
    repository: _repository,
    path: locationToPath(state.uri.path),
    anchor: state.uri.fragment.isEmpty ? null : state.uri.fragment,
    themeMode: _themeMode,
  );

  @override
  void dispose() {
    _router.dispose();
    _themeMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: _themeMode,
    builder: (context, mode, _) => MaterialApp.router(
      title: 'DocScan Docs',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      routerConfig: _router,
    ),
  );
}
