import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum ToolSection {
  kits('Application kits'),
  capture('Scan & capture'),
  pdf('PDF tools'),
  text('Text & OCR'),
  image('Image tools'),
  convert('Convert');

  const ToolSection(this.title);
  final String title;
}

@immutable
class ToolEntry {
  const ToolEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.section,
    required this.route,
    this.keywords = '',
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final ToolSection section;
  final String route;
  final String keywords;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '$title $subtitle $keywords'.toLowerCase().contains(q);
  }
}

final List<ToolEntry> toolCatalog = [
  const ToolEntry(
    title: 'Photo, exam & job kits',
    subtitle: 'Photo, signature & PDFs under portal limits',
    icon: Icons.assignment_turned_in_rounded,
    section: ToolSection.kits,
    route: Routes.kits,
    keywords: 'application portal visa exam job upload kb signature form',
  ),
  ToolEntry(
    title: 'Scan document',
    subtitle: 'Camera scan with auto edges',
    icon: Icons.document_scanner_rounded,
    section: ToolSection.capture,
    route: Routes.scan(),
    keywords: 'camera capture photo',
  ),
  const ToolEntry(
    title: 'Take passport-size photo',
    subtitle: 'Face guide + auto-capture, print sheet',
    icon: Icons.face_retouching_natural_rounded,
    section: ToolSection.capture,
    route: Routes.passportPhotoCamera,
    keywords: 'passport photo camera face selfie id',
  ),
  const ToolEntry(
    title: 'Scan QR / barcode',
    subtitle: 'Read codes offline, create QR codes',
    icon: Icons.qr_code_scanner_rounded,
    section: ToolSection.capture,
    route: Routes.qrScanner,
    keywords:
        'qr barcode scan scanner wifi contact vcard link ean upc isbn '
        'generate create code',
  ),
  ToolEntry(
    title: 'Images to PDF',
    subtitle: 'Combine photos into one PDF',
    icon: Icons.photo_library_rounded,
    section: ToolSection.capture,
    route: Routes.tool(ToolId.imagesToPdf),
    keywords: 'jpg png gallery convert',
  ),
  ToolEntry(
    title: 'Merge PDFs',
    subtitle: 'Join files in any order',
    icon: Icons.call_merge_rounded,
    section: ToolSection.pdf,
    route: Routes.tool(ToolId.merge),
    keywords: 'combine join',
  ),
  ToolEntry(
    title: 'Split & extract',
    subtitle: 'Pull out pages or ranges',
    icon: Icons.call_split_rounded,
    section: ToolSection.pdf,
    route: Routes.tool(ToolId.split),
    keywords: 'pages range separate',
  ),
  ToolEntry(
    title: 'Organize pages',
    subtitle: 'Reorder, rotate, delete',
    icon: Icons.dashboard_customize_rounded,
    section: ToolSection.pdf,
    route: Routes.tool(ToolId.organize),
    keywords: 'reorder rotate delete remove sort',
  ),
  ToolEntry(
    title: 'Sign PDF',
    subtitle: 'Add your signature & date',
    icon: Icons.draw_rounded,
    section: ToolSection.pdf,
    route: Routes.tool(ToolId.signPdf),
    keywords: 'signature sign stamp date fill esign',
  ),
  ToolEntry(
    title: 'Protect file',
    subtitle: 'Password-lock PDFs, IDs & any file',
    icon: Icons.lock_rounded,
    section: ToolSection.pdf,
    route: Routes.tool(ToolId.protectFile),
    keywords:
        'password encrypt lock secure protect zip aes whatsapp email send '
        'id aadhaar pan tax',
  ),
  ToolEntry(
    title: 'Remove PDF password',
    subtitle: 'Unlock a PDF you have the password for',
    icon: Icons.lock_open_rounded,
    section: ToolSection.pdf,
    route: Routes.tool(ToolId.removePdfPassword),
    keywords: 'password unlock decrypt remove open protected',
  ),
  ToolEntry(
    title: 'Compress PDF',
    subtitle: 'Make PDFs smaller to send',
    icon: Icons.compress_rounded,
    section: ToolSection.pdf,
    route: Routes.tool(ToolId.compressPdf),
    keywords: 'reduce size shrink email',
  ),
  ToolEntry(
    title: 'PDF to images',
    subtitle: 'Save pages as JPG or PNG',
    icon: Icons.collections_rounded,
    section: ToolSection.pdf,
    route: Routes.tool(ToolId.pdfToImages),
    keywords: 'jpg png export',
  ),
  ToolEntry(
    title: 'Extract text',
    subtitle: 'Copy text from photos & PDFs',
    icon: Icons.text_snippet_rounded,
    section: ToolSection.text,
    route: Routes.tool(ToolId.ocr),
    keywords: 'ocr recognize read copy',
  ),
  ToolEntry(
    title: 'Compress image',
    subtitle: 'Hit an upload size limit',
    icon: Icons.photo_size_select_small_rounded,
    section: ToolSection.image,
    route: Routes.tool(ToolId.compressImage),
    keywords: 'reduce kb size jpg',
  ),
  ToolEntry(
    title: 'Crop a photo',
    subtitle: 'Passport, ID & stamp sizes',
    icon: Icons.badge_rounded,
    section: ToolSection.image,
    route: Routes.tool(ToolId.photoCrop),
    keywords: 'crop passport size visa stamp photo preset id',
  ),
  ToolEntry(
    title: 'My signature',
    subtitle: 'Draw or photograph, export PNG',
    icon: Icons.gesture_rounded,
    section: ToolSection.image,
    route: Routes.tool(ToolId.mySignature),
    keywords: 'signature sign transparent png draw autograph',
  ),
  ToolEntry(
    title: 'Resize image',
    subtitle: 'Set exact width and height',
    icon: Icons.aspect_ratio_rounded,
    section: ToolSection.image,
    route: Routes.tool(ToolId.resizeImage),
    keywords: 'dimensions pixels scale',
  ),
  ToolEntry(
    title: 'Convert files',
    subtitle: 'PDF, Word, text, images & more',
    icon: Icons.swap_horiz_rounded,
    section: ToolSection.convert,
    route: Routes.tool(ToolId.convert),
    keywords: 'docx word txt csv excel xlsx html markdown pptx',
  ),
];

Color sectionColor(BuildContext context, ToolSection section) =>
    switch (section) {
      ToolSection.kits => context.colors.secondary,
      ToolSection.capture => context.colors.primary,
      ToolSection.pdf => context.ds.pdf,
      ToolSection.text => context.ds.text,
      ToolSection.image => context.ds.image,
      ToolSection.convert => context.ds.office,
    };

/// "DOCX → PDF" for a spec.
String specArrow(ConversionSpec spec) {
  final inputs = spec.inputs.every((f) => f.isImage)
      ? 'Images'
      : spec.inputs.map((f) => f.extension.toUpperCase()).join('/');
  return '$inputs → ${spec.output.extension.toUpperCase()}';
}

/// Tab root: every tool, grouped and searchable.
class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key});

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Opens [route], via the paywall when it is a locked Pro feature (the
  /// feature comes from the location, see proFeatureForLocation).
  Future<void> _open(String route) async {
    final feature = proFeatureForLocation(Uri.parse(route));
    if (feature == null) {
      unawaited(context.push(route));
      return;
    }
    await pushIfPro(context, ref, feature, route);
  }

  String? _proBadge(String route) {
    final feature = proFeatureForLocation(Uri.parse(route));
    return feature == null ? null : proBadgeLabel(ref, feature);
  }

  @override
  Widget build(BuildContext context) {
    final specs = ref.watch(conversionSpecsProvider);
    final visible = toolCatalog.where((t) => t.matches(_query)).toList();
    final matchingSpecs = _query.trim().isEmpty
        ? specs.take(6).toList()
        : specs
              .where(
                (s) => '${s.title} ${specArrow(s)}'.toLowerCase().contains(
                  _query.trim().toLowerCase(),
                ),
              )
              .toList();

    // Groups that are listed, in order; the ad card goes after the Nth
    // one (and only while nothing is being searched).
    final shownSections = [
      for (final section in ToolSection.values)
        if (visible.any((t) => t.section == section) ||
            (section == ToolSection.convert && matchingSpecs.isNotEmpty))
          section,
    ];
    final adAfter =
        _query.trim().isEmpty &&
            shownSections.length > AdPlacementPolicy.toolsNativeAfterGroup
        ? shownSections[AdPlacementPolicy.toolsNativeAfterGroup - 1]
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      // Free build only; empty otherwise (ADR-0013).
      bottomNavigationBar: const AdBannerSlot(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: Space.x10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Everything runs on your phone — no uploads, no account.',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                  ),
                  const SizedBox(height: Space.x2),
                  const OfflineBadge(),
                  const SizedBox(height: Space.x4),
                  TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search tools',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (visible.isEmpty && matchingSpecs.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: Space.x8),
                child: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No tools match',
                  message: 'Try "PDF", "compress" or "text".',
                ),
              ),
            for (final section in shownSections) ...[
              SectionHeader(section.title),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                child: _TileGrid(
                  children: [
                    for (final t in visible.where((t) => t.section == section))
                      ToolTile(
                        icon: t.icon,
                        title: t.title,
                        subtitle: t.subtitle,
                        color: sectionColor(context, section),
                        badge: _proBadge(t.route),
                        onTap: () => unawaited(_open(t.route)),
                      ),
                  ],
                ),
              ),
              if (section == ToolSection.convert && matchingSpecs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.x3,
                    Space.gutter,
                    0,
                  ),
                  child: Wrap(
                    spacing: Space.x2,
                    runSpacing: Space.x2,
                    children: [
                      for (final s in matchingSpecs)
                        ActionChip(
                          avatar: const Icon(
                            Icons.swap_horiz_rounded,
                            size: 18,
                          ),
                          label: Text(specArrow(s)),
                          tooltip: '${s.title} · ${s.fidelity.label}',
                          onPressed: () =>
                              unawaited(_open(Routes.convert(s.id))),
                        ),
                    ],
                  ),
                ),
              // One labelled ad card between two tool groups, never
              // above the first group or the search field (ADR-0013).
              // Zero height unless an ad is already loaded.
              if (section == adAfter)
                const AdNativeSlot(
                  placement: AdNativePlacement.toolsList,
                  padding: EdgeInsets.symmetric(horizontal: Space.gutter),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Grid whose rows grow with their content, so large text never clips.
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cols = (constraints.maxWidth / 170).floor().clamp(2, 5);
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += cols) {
        rows
          ..add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < cols; c++) ...[
                    if (c > 0) const SizedBox(width: Space.x3),
                    Expanded(
                      child: i + c < children.length
                          ? children[i + c]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          )
          ..add(const SizedBox(height: Space.x3));
      }
      return Column(children: rows);
    },
  );
}
