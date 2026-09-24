import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_docs/src/docs_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders one markdown page split into heading sections so anchors and
/// the "On this page" outline can scroll to them.
class DocPageView extends StatefulWidget {
  const DocPageView({
    required this.repository,
    required this.path,
    super.key,
    this.anchor,
    this.title,
  });

  final DocsRepository repository;
  final String path;
  final String? anchor;
  final String? title;

  @override
  State<DocPageView> createState() => _DocPageViewState();
}

class _DocPageViewState extends State<DocPageView> {
  late final Future<String> _content = widget.repository.page(widget.path);
  final Map<String, GlobalKey> _keys = {};
  bool _scrolledToAnchor = false;

  GlobalKey _keyFor(String anchor) => _keys.putIfAbsent(anchor, GlobalKey.new);

  void _scrollTo(String anchor) {
    final ctx = _keys[anchor]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: Motion.medium,
        curve: Motion.curve,
      );
    }
  }

  Future<void> _onLink(String? href) async {
    if (href == null) return;
    final doc = resolveDocLink(widget.path, href);
    if (doc == null) {
      await launchUrl(Uri.parse(href));
      return;
    }
    if (doc.path == widget.path) {
      if (doc.anchor != null) _scrollTo(doc.anchor!);
      return;
    }
    if (!mounted) return;
    final location = pathToLocation(doc.path);
    context.go(doc.anchor == null ? location : '$location#${doc.anchor}');
  }

  MarkdownStyleSheet _style(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      fontSize: 13,
      height: 1.45,
      color: scheme.onSurface,
    );
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      h1: context.text.displaySmall,
      h2: context.text.headlineSmall,
      h3: context.text.titleLarge,
      h4: context.text.titleMedium,
      p: context.text.bodyLarge,
      a: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600),
      code: mono.copyWith(backgroundColor: scheme.surfaceContainerHigh),
      codeblockPadding: const EdgeInsets.all(Space.x4),
      codeblockDecoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: Radii.buttonAll,
        border: Border.all(color: context.ds.border),
      ),
      blockquoteDecoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: Radii.buttonAll,
        border: Border(left: BorderSide(color: scheme.primary, width: 4)),
      ),
      blockquotePadding: const EdgeInsets.all(Space.x4),
      tableBorder: TableBorder.all(color: context.ds.border),
      tableHead: context.text.titleSmall,
      tableBody: context.text.bodyMedium,
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: Space.x3,
        vertical: Space.x2,
      ),
      tableColumnWidth: const IntrinsicColumnWidth(),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.ds.border)),
      ),
      h2Padding: const EdgeInsets.only(top: Space.x6),
      h3Padding: const EdgeInsets.only(top: Space.x4),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _content,
    builder: (context, snap) {
      if (snap.hasError) {
        return EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Page not found',
          message: 'No page at "${widget.path}". Pick one from the menu.',
          actionLabel: 'Go to home',
          onAction: () => context.go('/'),
        );
      }
      final markdown = snap.data;
      if (markdown == null) {
        return const Center(child: CircularProgressIndicator());
      }

      final sections = splitSections(markdown);
      final outline = [
        for (final s in sections)
          if (s.heading != null && s.level == 2) s,
      ];
      if (widget.anchor != null && !_scrolledToAnchor) {
        _scrolledToAnchor = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollTo(widget.anchor!),
        );
      }
      final style = _style(context);

      final content = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.x6,
          Space.x6,
          Space.x6,
          Space.x12,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in sections)
                    KeyedSubtree(
                      key: s.anchor == null ? null : _keyFor(s.anchor!),
                      child: MarkdownBody(
                        data: s.markdown,
                        styleSheet: style,
                        onTapLink: (text, href, title) => _onLink(href),
                        fitContent: false,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      return LayoutBuilder(
        builder: (context, c) {
          if (c.maxWidth < 1100 || outline.length < 3) return content;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content),
              SizedBox(
                width: 240,
                child: ListView(
                  padding: const EdgeInsets.all(Space.x5),
                  children: [
                    Text('On this page', style: context.text.titleSmall),
                    const SizedBox(height: Space.x2),
                    for (final s in outline)
                      TextButton(
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.x2,
                          ),
                        ),
                        onPressed: () => _scrollTo(s.anchor!),
                        child: Text(
                          s.heading!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
