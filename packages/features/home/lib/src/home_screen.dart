import 'dart:io';
import 'dart:math' as math;

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The unfinished scan, if any. Refreshed whenever Home becomes visible.
final homeDraftProvider = FutureProvider<ScanDraft?>(
  (ref) => ref.watch(draftStoreProvider).load(),
);

const _recentsQuery = DocumentQuery(limit: 6);

class _QuickAction {
  const _QuickAction(
    this.icon,
    this.title,
    this.subtitle,
    this.color,
    this.onTap,
  );

  final IconData icon;
  final String title;
  final String subtitle;
  final Color Function(BuildContext) color;
  final void Function(BuildContext) onTap;
}

final _quickActions = <_QuickAction>[
  _QuickAction(
    Icons.photo_library_outlined,
    'Import photos',
    'Turn pictures into a PDF',
    (c) => c.ds.image,
    (c) => c.push(Routes.scan(source: ScanSource.gallery)),
  ),
  _QuickAction(
    Icons.picture_as_pdf_outlined,
    'Import PDF',
    'Reorder, rotate or remove pages',
    (c) => c.ds.pdf,
    (c) => c.push(Routes.tool(ToolId.organize)),
  ),
  _QuickAction(
    Icons.text_snippet_outlined,
    'Extract text',
    'Copy text from a photo or scan',
    (c) => c.ds.text,
    (c) => c.push(Routes.tool(ToolId.ocr)),
  ),
  _QuickAction(
    Icons.merge_type_rounded,
    'Merge PDFs',
    'Combine files into one',
    (c) => c.colors.primary,
    (c) => c.push(Routes.tool(ToolId.merge)),
  ),
  _QuickAction(
    Icons.compress_rounded,
    'Compress PDF',
    'Make files smaller to send',
    (c) => c.ds.office,
    (c) => c.push(Routes.tool(ToolId.compressPdf)),
  ),
  _QuickAction(
    Icons.portrait_rounded,
    'Passport photo',
    'Crop to official photo sizes',
    (c) => c.colors.secondary,
    (c) => c.push(Routes.tool(ToolId.photoCrop)),
  ),
  _QuickAction(
    Icons.photo_size_select_large_rounded,
    'Compress image',
    'Fit upload size limits',
    (c) => c.ds.warning,
    (c) => c.push(Routes.tool(ToolId.compressImage)),
  ),
  _QuickAction(
    Icons.apps_rounded,
    'All tools',
    'Convert, split and more',
    (c) => c.ds.textSecondary,
    (c) => c.go(Routes.tools),
  ),
];

/// Home tab: scan CTA, resume banner, quick tools and recent files.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.now});

  /// Injected clock for tests (greeting).
  final DateTime? now;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_onRouteChanged);
      _router = router?..routerDelegate.addListener(_onRouteChanged);
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(homeDraftProvider);
  }

  /// The scan flow changes the draft on top of this tab; reload it whenever
  /// Home is the visible location again.
  void _onRouteChanged() {
    final router = _router;
    if (!mounted || router == null) return;
    if (router.routerDelegate.currentConfiguration.uri.path == Routes.home) {
      ref.invalidate(homeDraftProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final columns = width >= 840 ? 4 : (width >= 600 ? 3 : 2);
    final draft = ref.watch(homeDraftProvider).value;
    final recents = ref.watch(documentsProvider(_recentsQuery));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(now: widget.now ?? DateTime.now()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  sliver: SliverToBoxAdapter(
                    child: HeroAction(
                      icon: Icons.document_scanner_rounded,
                      title: 'Scan a document',
                      subtitle: 'Edges are found and straightened for you',
                      onTap: () => context.push(Routes.scan()),
                    ),
                  ),
                ),
                if (draft != null && !draft.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.x3,
                      Space.gutter,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _ResumeBanner(draft: draft),
                    ),
                  ),
                const SliverToBoxAdapter(child: SectionHeader('Quick tools')),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: Space.x3,
                      crossAxisSpacing: Space.x3,
                      // Fixed chrome + two lines of title and subtitle,
                      // scaled with the user's text size.
                      mainAxisExtent: 104 + 76 * textScale,
                    ),
                    delegate: SliverChildListDelegate([
                      for (final a in _quickActions)
                        ToolTile(
                          icon: a.icon,
                          title: a.title,
                          subtitle: a.subtitle,
                          color: a.color(context),
                          onTap: () => a.onTap(context),
                        ),
                    ]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SectionHeader(
                    'Recent files',
                    action: (recents.value?.isNotEmpty ?? false)
                        ? 'See all'
                        : null,
                    onAction: () => context.go(Routes.files),
                  ),
                ),
                SliverToBoxAdapter(
                  child: switch (recents) {
                    AsyncData(:final value) when value.isEmpty =>
                      const _FirstRun(),
                    AsyncData(:final value) => _RecentStrip(
                      documents: value,
                      textScale: textScale,
                    ),
                    AsyncError() => const Padding(
                      padding: EdgeInsets.all(Space.gutter),
                      child: Text("Recent files couldn't be loaded."),
                    ),
                    _ => const SizedBox(
                      height: 120,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: Space.x8)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.now});

  final DateTime now;

  String get _greeting {
    final h = now.hour;
    if (h < 5) return 'Good evening';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.x5,
      Space.gutter,
      Space.x5,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Space.x3,
          runSpacing: Space.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(_greeting, style: context.text.headlineSmall),
            ),
            const OfflineBadge(),
          ],
        ),
        const SizedBox(height: Space.x1),
        Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: context.ds.textSecondary,
            ),
            const SizedBox(width: Space.x1),
            Flexible(
              child: Text(
                'No account. Files stay on this phone.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.ds.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({required this.draft});

  final ScanDraft draft;

  @override
  Widget build(BuildContext context) {
    final n = draft.pages.length;
    return Card(
      color: context.colors.primaryContainer,
      shape: const RoundedRectangleBorder(borderRadius: Radii.cardAll),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.scan(source: ScanSource.resume)),
        child: Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: Row(
            children: [
              Icon(
                Icons.pending_actions_rounded,
                color: context.colors.onPrimaryContainer,
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unfinished scan',
                      style: context.text.titleSmall?.copyWith(
                        color: context.colors.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      '$n ${n == 1 ? 'page' : 'pages'} · ${formatRelativeDate(draft.createdAt)}',
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.x2),
              Text(
                'Resume',
                style: context.text.labelLarge?.copyWith(
                  color: context.colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FirstRun extends StatelessWidget {
  const _FirstRun();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.x5),
        child: Row(
          children: [
            const IconBadge(Icons.inventory_2_outlined, size: 52),
            const SizedBox(width: Space.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nothing here yet', style: context.text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    'Your scans and converted files will appear here. They never leave your phone unless you share them.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecentStrip extends ConsumerWidget {
  const _RecentStrip({required this.documents, required this.textScale});

  final List<Document> documents;
  final double textScale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = ref.watch(fileStoreProvider);
    return SizedBox(
      height: 132 + 44 * math.max(1, textScale),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: documents.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.x3),
        itemBuilder: (context, i) =>
            _RecentCard(document: documents[i], files: files),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.document, required this.files});

  final Document document;
  final FileStore files;

  @override
  Widget build(BuildContext context) {
    final visual = formatVisual(context, document.format);
    final thumb = document.thumbnailPath;
    final pages = document.pageCount;
    final meta = [
      if (document.format == DocumentFormat.pdf && pages != null)
        '$pages ${pages == 1 ? 'page' : 'pages'}'
      else
        document.format.extension.toUpperCase(),
      formatRelativeDate(document.updatedAt),
    ].join(' · ');
    final fallback = ColoredBox(
      color: visual.color.withValues(alpha: 0.1),
      child: Center(child: Icon(visual.icon, color: visual.color, size: 40)),
    );

    return SizedBox(
      width: 148,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(Routes.document(document.id)),
          child: Semantics(
            button: true,
            label: '${document.name}, ${document.format.label}, $meta',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 112,
                  width: double.infinity,
                  child: thumb == null
                      ? fallback
                      : Image.file(
                          File(files.absolute(thumb)),
                          fit: BoxFit.cover,
                          cacheWidth: 300,
                          errorBuilder: (_, _, _) => fallback,
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.x3,
                    Space.x2,
                    Space.x3,
                    0,
                  ),
                  child: Text(
                    document.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x3),
                  child: Row(
                    children: [
                      Icon(visual.icon, size: 14, color: visual.color),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: context.ds.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
