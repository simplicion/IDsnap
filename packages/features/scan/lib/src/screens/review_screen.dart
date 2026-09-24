import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/src/scan_session_controller.dart';
import 'package:feature_scan/src/widgets/filters_sheet.dart';
import 'package:feature_scan/src/widgets/page_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Review pages: preview, reorder, crop, rotate, filter, retake, delete, add.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _pager = PageController();
  int _index = 0;
  bool _busy = false;

  ScanSessionController get _session => ref.read(scanSessionProvider.notifier);

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _jumpTo(int index) {
    setState(() => _index = index);
    if (_pager.hasClients) {
      _pager.animateToPage(index, duration: Motion.medium, curve: Motion.curve);
    }
  }

  Future<void> _run(Future<Result<Object?>> Function() action) async {
    setState(() => _busy = true);
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result case Err(:final failure)) showFailureSnack(context, failure);
  }

  Future<void> _addPages() async {
    final source = await showModalBottomSheet<ScanSource>(
      context: context,
      builder: (context) => const _SourceSheet(title: 'Add pages'),
    );
    if (source == null || !mounted) return;
    final before = _session.pages.length;
    await _run(
      () => source == ScanSource.gallery
          ? _session.addFromGallery()
          : _session.addFromCamera(),
    );
    if (mounted && _session.pages.length > before) _jumpTo(before);
  }

  Future<void> _retake(ScanPage page) async {
    final source = await showModalBottomSheet<ScanSource>(
      context: context,
      builder: (context) => const _SourceSheet(title: 'Retake this page'),
    );
    if (source == null || !mounted) return;
    await _run(() => _session.replacePage(page.id, source: source));
  }

  Future<void> _delete(ScanPage page) async {
    final removed = await _session.removePage(page.id);
    if (removed == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final pages = _session.pages;
    if (_index >= pages.length && pages.isNotEmpty) _jumpTo(pages.length - 1);
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text('Page ${removed.index + 1} deleted'),
        action: SnackBarAction(label: 'Undo', onPressed: () {}),
      ),
    );
    final reason = await controller.closed;
    if (reason == SnackBarClosedReason.action) {
      await _session.restorePage(removed.page, removed.index);
      if (mounted) _jumpTo(removed.index);
    } else {
      await _session.purge(removed.page);
    }
  }

  Future<void> _openFilters(ScanPage page) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => FiltersSheet(pageId: page.id),
  );

  Future<bool> _confirmLeave() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this scan?'),
        content: const Text(
          'Your pages are kept as a draft on this phone. You can resume from Home, or discard them now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: const Text('Keep draft'),
          ),
        ],
      ),
    );
    if (choice == 'discard') await _session.discard();
    return choice != null;
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(scanSessionProvider);
    final flagged = ref.watch(pagesNeedingReviewProvider);
    final pages = draft.value?.pages ?? const <ScanPage>[];
    if (pages.isNotEmpty && _index >= pages.length) _index = pages.length - 1;
    final current = pages.isEmpty ? null : pages[_index];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (pages.isEmpty || await _confirmLeave()) {
          if (mounted) _leave();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: Text(
            pages.isEmpty ? 'Review' : 'Page ${_index + 1} of ${pages.length}',
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: Space.x3),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                onPressed: pages.isEmpty || _busy
                    ? null
                    : () => context.push(Routes.scanSave),
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text('Save'),
              ),
            ),
          ],
        ),
        body: switch (draft) {
          AsyncLoading() when draft.value == null => const ProgressPanel(
            label: 'Loading your scan…',
          ),
          _ when pages.isEmpty => EmptyState(
            icon: Icons.note_add_outlined,
            title: 'No pages yet',
            message: 'Scan with the camera or add photos of your pages.',
            actionLabel: 'Add pages',
            onAction: _addPages,
          ),
          _ => SafeArea(
            child: Column(
              children: [
                if (_busy) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: Stack(
                    children: [
                      PageView.builder(
                        controller: _pager,
                        itemCount: pages.length,
                        onPageChanged: (i) => setState(() => _index = i),
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Space.x6,
                            Space.x3,
                            Space.x6,
                            Space.x3,
                          ),
                          child: Semantics(
                            label: 'Page ${i + 1} preview',
                            image: true,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: PageImage(page: pages[i]),
                            ),
                          ),
                        ),
                      ),
                      if (current != null && flagged.contains(current.id))
                        Positioned(
                          top: Space.x4,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: ActionChip(
                              avatar: Icon(
                                Icons.crop_free_rounded,
                                color: context.ds.warning,
                                size: 18,
                              ),
                              label: const Text('Check corners'),
                              backgroundColor: context.ds.warningContainer,
                              onPressed: () =>
                                  context.push(Routes.scanCrop(current.id)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                _PageStrip(
                  pages: pages,
                  selected: _index,
                  flagged: flagged,
                  onSelect: _jumpTo,
                  onAdd: _addPages,
                  onReorder: (from, to) async {
                    final selectedId = pages[_index].id;
                    await _session.reorder(from, to);
                    final i = _session.pages.indexWhere(
                      (p) => p.id == selectedId,
                    );
                    if (mounted && i >= 0) _jumpTo(i);
                  },
                ),
                _ActionBar(
                  actions: [
                    _Action(
                      Icons.crop_rounded,
                      'Crop',
                      () => context.push(Routes.scanCrop(current!.id)),
                    ),
                    _Action(
                      Icons.rotate_right_rounded,
                      'Rotate',
                      () => _session.rotate(current!.id),
                    ),
                    _Action(
                      Icons.auto_fix_high_rounded,
                      'Filters',
                      () => _openFilters(current!),
                    ),
                    _Action(
                      Icons.replay_rounded,
                      'Retake',
                      () => _retake(current!),
                    ),
                    _Action(
                      Icons.delete_outline_rounded,
                      'Delete',
                      () => _delete(current!),
                    ),
                  ],
                ),
              ],
            ),
          ),
        },
      ),
    );
  }
}

class _PageStrip extends StatelessWidget {
  const _PageStrip({
    required this.pages,
    required this.selected,
    required this.flagged,
    required this.onSelect,
    required this.onAdd,
    required this.onReorder,
  });

  final List<ScanPage> pages;
  final int selected;
  final Set<String> flagged;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final void Function(int from, int to) onReorder;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return SizedBox(
      height: 104,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.x3,
          vertical: Space.x2,
        ),
        buildDefaultDragHandles: false,
        itemCount: pages.length,
        onReorderItem: onReorder,
        footer: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x1),
          child: Tooltip(
            message: 'Add pages',
            child: InkWell(
              onTap: onAdd,
              borderRadius: Radii.buttonAll,
              child: Container(
                width: 64,
                decoration: BoxDecoration(
                  borderRadius: Radii.buttonAll,
                  border: Border.all(color: scheme.outline),
                ),
                child: Icon(Icons.add_rounded, color: scheme.primary),
              ),
            ),
          ),
        ),
        itemBuilder: (context, i) {
          final page = pages[i];
          final isSelected = i == selected;
          return ReorderableDelayedDragStartListener(
            key: ValueKey(page.id),
            index: i,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x1),
              child: Semantics(
                button: true,
                selected: isSelected,
                label:
                    'Page ${i + 1}${flagged.contains(page.id) ? ', check corners' : ''}. Long press to reorder.',
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    width: 64,
                    decoration: BoxDecoration(
                      borderRadius: Radii.buttonAll,
                      border: Border.all(
                        color: isSelected ? scheme.primary : context.ds.border,
                        width: isSelected ? 2.5 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(
                        Radius.circular(Radii.button - 2),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: scheme.surfaceContainerHigh,
                            child: PageImage(
                              page: page,
                              size: PageImageSize.thumb,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            left: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          if (flagged.contains(page.id))
                            Positioned(
                              right: 3,
                              top: 3,
                              child: Icon(
                                Icons.warning_rounded,
                                size: 16,
                                color: context.ds.warning,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Action {
  const _Action(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.actions});

  final List<_Action> actions;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.surface,
      border: Border(top: BorderSide(color: context.ds.border)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x1),
      child: Row(
        children: [
          for (final a in actions)
            Expanded(
              child: InkWell(
                onTap: a.onTap,
                borderRadius: Radii.buttonAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.x2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(a.icon),
                      const SizedBox(height: 2),
                      Text(
                        a.label,
                        style: context.text.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            0,
            Space.gutter,
            Space.x2,
          ),
          child: Text(title, style: context.text.titleMedium),
        ),
        ListTile(
          leading: const IconBadge(Icons.document_scanner_outlined, size: 40),
          title: const Text('Scan with camera'),
          subtitle: const Text('Edges are found and cropped automatically'),
          onTap: () => Navigator.pop(context, ScanSource.camera),
        ),
        ListTile(
          leading: IconBadge(
            Icons.photo_library_outlined,
            size: 40,
            color: context.ds.image,
          ),
          title: const Text('Choose from photos'),
          subtitle: const Text('Pick existing pictures of documents'),
          onTap: () => Navigator.pop(context, ScanSource.gallery),
        ),
        const SizedBox(height: Space.x3),
      ],
    ),
  );
}
