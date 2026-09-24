import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_docs/src/docs_repository.dart';
import 'package:docscan_docs/src/page_view.dart';
import 'package:docscan_docs/src/search.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Responsive frame: persistent nav on wide screens, drawer on phones.
class DocsShell extends StatelessWidget {
  const DocsShell({
    required this.repository,
    required this.path,
    required this.themeMode,
    super.key,
    this.anchor,
  });

  static const wideBreakpoint = 900.0;

  final DocsRepository repository;
  final String path;
  final String? anchor;
  final ValueNotifier<ThemeMode> themeMode;

  @override
  Widget build(BuildContext context) => FutureBuilder<DocsManifest>(
    future: repository.manifest(),
    builder: (context, snap) {
      final manifest = snap.data;
      if (snap.hasError) {
        return const Scaffold(
          body: EmptyState(
            icon: Icons.menu_book_rounded,
            title: 'Docs not found',
            message:
                'Run `dart run tool/sync_docs.dart` to copy /docs into the app.',
          ),
        );
      }
      if (manifest == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= wideBreakpoint;
          final nav = DocsNav(
            manifest: manifest,
            currentPath: path,
            closeOnTap: !wide,
          );
          final page = manifest.byPath(path);
          final body = DocPageView(
            key: ValueKey(path),
            repository: repository,
            path: path,
            anchor: anchor,
            title: page?.title,
          );
          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  const IconBadge(Icons.document_scanner_rounded, size: 32),
                  const SizedBox(width: Space.x3),
                  Flexible(
                    child: Text(
                      manifest.title,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'Search docs',
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => openDocsSearch(context, repository),
                ),
                _ThemeToggle(themeMode),
                const SizedBox(width: Space.x2),
              ],
            ),
            drawer: wide ? null : Drawer(child: SafeArea(child: nav)),
            body: wide
                ? Row(
                    children: [
                      SizedBox(width: 280, child: nav),
                      VerticalDivider(width: 1, color: context.ds.border),
                      Expanded(child: body),
                    ],
                  )
                : body,
          );
        },
      );
    },
  );
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle(this.mode);

  final ValueNotifier<ThemeMode> mode;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
      icon: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
      onPressed: () => mode.value = dark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}

/// Section-grouped page list.
class DocsNav extends StatelessWidget {
  const DocsNav({
    required this.manifest,
    required this.currentPath,
    super.key,
    this.closeOnTap = false,
  });

  final DocsManifest manifest;
  final String currentPath;
  final bool closeOnTap;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(vertical: Space.x3),
    children: [
      for (final section in manifest.sections) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.x5,
            Space.x4,
            Space.x4,
            Space.x1,
          ),
          child: Semantics(
            header: true,
            child: Text(
              section.title.toUpperCase(),
              style: context.text.labelMedium?.copyWith(
                color: context.ds.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
        for (final page in section.pages)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x2),
            child: ListTile(
              dense: true,
              selected: page.path == currentPath,
              selectedTileColor: context.colors.primaryContainer,
              selectedColor: context.colors.onPrimaryContainer,
              shape: const RoundedRectangleBorder(
                borderRadius: Radii.buttonAll,
              ),
              title: Text(page.title),
              onTap: () {
                if (closeOnTap) Navigator.of(context).maybePop();
                context.go(page.location);
              },
            ),
          ),
      ],
    ],
  );
}
