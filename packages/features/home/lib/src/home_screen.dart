import 'dart:async';
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

/// Hidden for the rest of the session once dismissed (not persisted: the
/// permanent switch lives in Settings).
final privacyBannerDismissedProvider = NotifierProvider<_BannerDismissed, bool>(
  _BannerDismissed.new,
);

class _BannerDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

class _Kit {
  const _Kit(this.id, this.icon, this.title, this.subtitle);

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
}

/// Kit shortcuts, named by size term — never by country. The ids are the
/// stable kit-catalog ids and must not change.
const _kits = <_Kit>[
  _Kit(
    'us-visa',
    Icons.crop_square_rounded,
    'Square photo (2 × 2 in)',
    'Head 50–69 %, under 240 KB',
  ),
  _Kit(
    'exam-portal',
    Icons.school_outlined,
    'Exam portal pack',
    'Photo, signature & documents to size',
  ),
  _Kit(
    'schengen-visa',
    Icons.portrait_rounded,
    'Passport size photo (35 × 45 mm)',
    'Head 70–80 % of the photo',
  ),
];

const _recentsQuery = DocumentQuery(limit: 6);

class _QuickAction {
  const _QuickAction(
    this.icon,
    this.title,
    this.subtitle,
    this.color,
    this.onTap, {
    this.feature,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color Function(BuildContext) color;
  final void Function(BuildContext) onTap;

  /// Pro feature behind the action (null = free).
  final ProFeature? feature;
}

final _quickActions = <_QuickAction>[
  _QuickAction(
    Icons.badge_outlined,
    'ID card (front & back)',
    'Both sides on one page',
    (c) => c.colors.primary,
    (c) => c.push(Routes.idCard()),
    feature: ProFeature.idCard,
  ),
  _QuickAction(
    Icons.photo_library_outlined,
    'Import photos',
    'Turn pictures into a PDF',
    (c) => c.ds.image,
    (c) => c.push(Routes.scan(source: ScanSource.gallery)),
    feature: ProFeature.scan,
  ),
  _QuickAction(
    Icons.picture_as_pdf_outlined,
    'Import PDF',
    'Reorder, rotate or remove pages',
    (c) => c.ds.pdf,
    (c) => c.push(Routes.tool(ToolId.organize)),
    feature: ProFeature.pdfTools,
  ),
  _QuickAction(
    Icons.text_snippet_outlined,
    'Extract text',
    'Copy text from a photo or scan',
    (c) => c.ds.text,
    (c) => c.push(Routes.tool(ToolId.ocr)),
    feature: ProFeature.ocr,
  ),
  _QuickAction(
    Icons.merge_type_rounded,
    'Merge PDFs',
    'Combine files into one',
    (c) => c.colors.primary,
    (c) => c.push(Routes.tool(ToolId.merge)),
    feature: ProFeature.pdfTools,
  ),
  _QuickAction(
    Icons.compress_rounded,
    'Compress PDF',
    'Make files smaller to send',
    (c) => c.ds.office,
    (c) => c.push(Routes.tool(ToolId.compressPdf)),
    feature: ProFeature.pdfTools,
  ),
  _QuickAction(
    Icons.face_retouching_natural_rounded,
    'Take passport-size photo',
    'Face guide with auto-capture',
    (c) => c.colors.secondary,
    (c) => c.push(Routes.passportPhotoCamera),
    feature: ProFeature.passportPhoto,
  ),
  _QuickAction(
    Icons.portrait_rounded,
    'Crop a photo',
    'Passport, ID and stamp sizes',
    (c) => c.colors.secondary,
    (c) => c.push(Routes.tool(ToolId.photoCrop)),
    feature: ProFeature.imageTools,
  ),
  _QuickAction(
    Icons.photo_size_select_large_rounded,
    'Compress image',
    'Fit upload size limits',
    (c) => c.ds.warning,
    (c) => c.push(Routes.tool(ToolId.compressImage)),
    feature: ProFeature.imageTools,
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
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(homeDraftProvider);
      ref.read(entitlementProvider.notifier).recheck();
    }
  }

  /// Opens a quick action, via the paywall when it is a locked Pro feature.
  Future<void> _open(_QuickAction action) async {
    final feature = action.feature;
    if (feature != null && !await ensurePro(context, ref, feature)) return;
    if (mounted) action.onTap(context);
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
    final showBanner =
        ref.watch(currentSettingsProvider.select((s) => s.showPrivacyBanner)) &&
        !ref.watch(privacyBannerDismissedProvider);
    final recents = ref.watch(documentsProvider(_recentsQuery));
    final entitlement = ref.watch(entitlementProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        // Two-line title; grows with the user's text size.
        toolbarHeight: math.max(kToolbarHeight, 16 + 44 * textScale),
        title: const _AppTitle(),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(Routes.settings),
          ),
          const SizedBox(width: Space.x1),
        ],
      ),
      // Free build only; empty otherwise (ADR-0013).
      bottomNavigationBar: const AdBannerSlot(),
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
                if (showBanner)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      0,
                      Space.gutter,
                      Space.x3,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _PrivacyBanner(
                        showsAds: ref.watch(monetizationModeProvider).showsAds,
                        onDismiss: () => ref
                            .read(privacyBannerDismissedProvider.notifier)
                            .dismiss(),
                      ),
                    ),
                  ),
                if (TrialBanner.visibleFor(entitlement))
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      0,
                      Space.gutter,
                      Space.x3,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: TrialBanner(state: entitlement),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  sliver: SliverToBoxAdapter(
                    child: HeroAction(
                      icon: Icons.document_scanner_rounded,
                      title: 'Scan a document',
                      subtitle: 'Edges are found and straightened for you',
                      onTap: () => unawaited(
                        pushIfPro(context, ref, ProFeature.scan, Routes.scan()),
                      ),
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
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.x3,
                    Space.gutter,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _AuthenticatorCard(
                      onTap: () => context.go(Routes.authenticator),
                    ),
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
                          badge: a.feature == null
                              ? null
                              : proBadgeLabel(ref, a.feature!),
                          onTap: () => unawaited(_open(a)),
                        ),
                    ]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SectionHeader(
                    'Application kits',
                    action: 'All kits',
                    onAction: () => unawaited(
                      pushIfPro(context, ref, ProFeature.kits, Routes.kits),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns == 2 ? 1 : columns - 1,
                      mainAxisSpacing: Space.x3,
                      crossAxisSpacing: Space.x3,
                      mainAxisExtent: 40 + 48 * textScale,
                    ),
                    delegate: SliverChildListDelegate([
                      for (final k in _kits)
                        _KitTile(
                          kit: k,
                          onTap: () => unawaited(
                            pushIfPro(
                              context,
                              ref,
                              ProFeature.kits,
                              Routes.kit(k.id),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.x4,
                    Space.gutter,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _ShortcutCard(
                      icon: Icons.sticky_note_2_outlined,
                      title: 'Secure notes',
                      subtitle:
                          'Wi-Fi passwords, account details and recovery '
                          'codes, encrypted on this phone',
                      onTap: () => context.push(Routes.notes),
                    ),
                  ),
                ),
                // One labelled ad card, only when the user already has
                // files: a nearly empty Home isn't padded out with an ad
                // (ADR-0013). Zero height unless an ad is already loaded.
                if ((recents.value?.length ?? 0) >=
                    AdPlacementPolicy.homeNativeMinRecents)
                  const SliverToBoxAdapter(
                    child: AdNativeSlot(
                      placement: AdNativePlacement.home,
                      padding: EdgeInsets.symmetric(horizontal: Space.gutter),
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
                      child: Text(
                        "Recent files couldn't be loaded. Open ID Vault to "
                        'see all your files.',
                      ),
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

class _AppTitle extends StatelessWidget {
  const _AppTitle();

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('IDSnap', style: context.text.titleLarge),
        Text(
          'Identity & Everyday Document Vault',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.bodySmall?.copyWith(
            color: context.ds.textSecondary,
          ),
        ),
      ],
    ),
  );
}

/// Shortcut to the Authenticator tab (two-step verification codes).
class _AuthenticatorCard extends StatelessWidget {
  const _AuthenticatorCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Row(
          children: [
            IconBadge(Icons.password_rounded, color: context.colors.primary),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Authenticator', style: context.text.titleSmall),
                  Text(
                    'Two-step sign-in codes, generated on this phone',
                    style: context.text.bodySmall?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.ds.textSecondary),
          ],
        ),
      ),
    ),
  );
}

/// A one-line shortcut card (Secure notes).
class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Row(
          children: [
            IconBadge(icon, color: context.colors.primary),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall),
                  Text(
                    subtitle,
                    style: context.text.bodySmall?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.ds.textSecondary),
          ],
        ),
      ),
    ),
  );
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
      Space.x2,
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
    return SizedBox(
      height: 132 + 44 * math.max(1, textScale),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: documents.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.x3),
        itemBuilder: (context, i) => _RecentCard(document: documents[i]),
      ),
    );
  }
}

/// A thumbnail decrypted in memory (vault files are encrypted, ADR-0010).
class _VaultThumb extends ConsumerWidget {
  const _VaultThumb({required this.path, required this.fallback});

  final String path;
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(vaultImageBytesProvider(path)).value;
    if (bytes == null) return fallback;
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      cacheWidth: 300,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.document});

  final Document document;

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
                      : _VaultThumb(path: thumb, fallback: fallback),
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

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner({required this.onDismiss, required this.showsAds});

  final VoidCallback onDismiss;

  /// The free build shows ads, which use the internet: it promises what
  /// stays on the phone, not "offline" (ADR-0013). The full statement is
  /// in Settings › Privacy.
  final bool showsAds;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final (title, promise) = showsAds
        ? (
            'Private vault',
            'Your documents, IDs and codes never leave this phone',
          )
        : ('Offline vault', 'Your documents never leave this phone');
    return Semantics(
      container: true,
      label: '$title. $promise.',
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          Space.x3,
          Space.x1,
          Space.x1,
          Space.x1,
        ),
        decoration: BoxDecoration(
          color: ds.successContainer,
          borderRadius: Radii.buttonAll,
        ),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, color: ds.success, size: 20),
            const SizedBox(width: Space.x2),
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  '$title · $promise',
                  style: context.text.bodyMedium?.copyWith(color: ds.success),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Hide for now',
              icon: Icon(Icons.close_rounded, color: ds.success, size: 20),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _KitTile extends StatelessWidget {
  const _KitTile({required this.kit, required this.onTap});

  final _Kit kit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x4,
          vertical: Space.x3,
        ),
        child: Row(
          children: [
            IconBadge(kit.icon, color: context.colors.secondary, size: 40),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kit.title,
                    style: context.text.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    kit.subtitle,
                    style: context.text.bodySmall?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.ds.textSecondary),
          ],
        ),
      ),
    ),
  );
}

/// Licence status on Home: the free-day countdown ("Free day ends in 5 h"),
/// a day pass in its last 24 hours, a monthly plan waiting for its renewal,
/// and a clear call to action once Pro has lapsed or was never activated.
/// Hidden otherwise, and always in the free build (ADR-0013).
class TrialBanner extends StatelessWidget {
  const TrialBanner({required this.state, super.key, this.now});

  final EntitlementState state;

  /// For tests; defaults to the current time.
  final DateTime? now;

  /// A day pass shows its countdown in its last day.
  static const dayPassCountdown = Duration(hours: 24);

  static bool visibleFor(EntitlementState state, {DateTime? now}) =>
      switch (state) {
        FreeEntitlement() => false,
        TrialEntitlement() => true,
        DayPassEntitlement(:final expiresAt) =>
          expiresAt.difference(now ?? DateTime.now()) <= dayPassCountdown,
        MonthlyEntitlement(:final inGracePeriod) => inGracePeriod,
        ExpiredEntitlement() => true,
      };

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    final at = now ?? DateTime.now();
    final reason = switch (state) {
      ExpiredEntitlement(:final reason) => reason,
      _ => null,
    };
    final tampered =
        reason == LapseReason.clockTampered ||
        reason == LapseReason.notActivated ||
        state is MonthlyEntitlement;
    final (title, body) = switch (state) {
      // Never shown ([visibleFor]); here for completeness.
      FreeEntitlement() => (
        'IDSnap is free',
        'Every feature is unlocked. A few screens show ads.',
      ),
      TrialEntitlement(:final endsAt) => (
        'Free day ends in ${formatTimeLeft(endsAt, at)}',
        'Every feature is unlocked until then. Your documents and the '
            'Authenticator always stay free.',
      ),
      DayPassEntitlement(:final expiresAt) => (
        'Day pass ends in ${formatTimeLeft(expiresAt, at)}',
        'Add days or switch to monthly to keep scanning and using the tools.',
      ),
      MonthlyEntitlement() => (
        'Confirming your monthly renewal',
        'Everything stays unlocked for a few days. Connect to the internet '
            'so IDSnap can refresh your licence.',
      ),
      ExpiredEntitlement(reason: LapseReason.notActivated) => (
        'Connect to the internet once to start your free day',
        'IDSnap needs to register this phone one time. After that it works '
            'offline.',
      ),
      ExpiredEntitlement(reason: LapseReason.clockTampered) => (
        "Check your phone's date",
        'The date is earlier than the last time IDSnap checked it, so your '
            'licence is paused. Set the correct date and time.',
      ),
      ExpiredEntitlement(reason: LapseReason.dayPassEnded) => (
        'Your day pass has ended',
        'Your documents, sharing and the Authenticator stay free. Add days '
            'or go monthly to scan and use the tools again.',
      ),
      ExpiredEntitlement(reason: LapseReason.subscriptionEnded) => (
        'Your monthly plan has ended',
        'Your documents, sharing and the Authenticator stay free. Renew to '
            'scan and use the tools again.',
      ),
      ExpiredEntitlement() => (
        'Your free day has ended',
        'Your documents, sharing and the Authenticator stay free. Get IDSnap '
            'Pro to scan and use the tools again.',
      ),
    };
    final expired = !state.isEntitled;
    final fg = expired ? context.colors.onPrimaryContainer : ds.warning;
    return Card(
      margin: EdgeInsets.zero,
      color: expired ? context.colors.primaryContainer : ds.warningContainer,
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              expired
                  ? Icons.workspace_premium_rounded
                  : Icons.hourglass_bottom_rounded,
              color: fg,
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.text.titleSmall?.copyWith(color: fg),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: context.text.bodySmall?.copyWith(color: fg),
                  ),
                  const SizedBox(height: Space.x2),
                  FilledButton.tonal(
                    onPressed: () => unawaited(
                      context.push(
                        tampered ? Routes.subscription : Routes.paywall(),
                      ),
                    ),
                    child: Text(tampered ? 'Details' : 'See plans'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
