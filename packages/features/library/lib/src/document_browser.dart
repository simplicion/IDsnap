import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_library/src/document_actions.dart';
import 'package:feature_library/src/document_tile.dart';
import 'package:feature_library/src/library_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Searchable, filterable, multi-select document list used by the Files tab
/// and folder screens.
class DocumentBrowser extends ConsumerStatefulWidget {
  const DocumentBrowser({
    required this.title,
    super.key,
    this.folderId,
    this.actions = const [],
    this.header,
    this.emptyTitle = 'No documents yet',
    this.emptyMessage =
        'Scan a page or import a file and it will appear here. Everything stays on this device.',
  });

  final String title;
  final String? folderId;
  final List<Widget> actions;

  /// Optional sliver shown above the documents (e.g. folders row).
  final Widget? header;
  final String emptyTitle;
  final String emptyMessage;

  @override
  ConsumerState<DocumentBrowser> createState() => _DocumentBrowserState();
}

class _DocumentBrowserState extends ConsumerState<DocumentBrowser> {
  late DocumentQuery _query = DocumentQuery(folderId: widget.folderId);
  final _search = TextEditingController();
  bool _grid = false;
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(Document d) => setState(() {
    if (!_selected.remove(d.id)) _selected.add(d.id);
  });

  void _open(Document d) {
    if (_selecting) {
      _toggle(d);
    } else {
      unawaited(context.push(Routes.document(d.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(documentsProvider(_query));
    final hidden = ref.watch(pendingDeletesProvider);
    final docs = (async.value ?? const <Document>[])
        .where((d) => !hidden.contains(d.id))
        .toList();
    final selectedDocs = docs.where((d) => _selected.contains(d.id)).toList();

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: _selecting ? _selectionBar(selectedDocs) : _normalBar(),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _searchField()),
            SliverToBoxAdapter(child: _filters()),
            ?widget.header,
            if (async.hasError && async.value == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: FailureView(
                  const AppFailure(FailureCode.unknown),
                  onRetry: () => ref.invalidate(documentsProvider(_query)),
                ),
              )
            else if (async.isLoading && async.value == null)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (docs.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: _empty())
            else if (_grid)
              _gridSliver(docs)
            else
              _listSliver(docs),
            const SliverToBoxAdapter(child: SizedBox(height: Space.x12)),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _normalBar() => AppBar(
    title: Text(widget.title),
    actions: [
      PopupMenuButton<DocumentSort>(
        tooltip: 'Sort',
        icon: const Icon(Icons.sort_rounded),
        initialValue: _query.sort,
        onSelected: (s) => setState(() => _query = _query.copyWith(sort: s)),
        itemBuilder: (_) => [
          for (final s in DocumentSort.values)
            CheckedPopupMenuItem(
              value: s,
              checked: s == _query.sort,
              child: Text(s.label),
            ),
        ],
      ),
      IconButton(
        tooltip: _grid ? 'Show as list' : 'Show as grid',
        icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
        onPressed: () => setState(() => _grid = !_grid),
      ),
      ...widget.actions,
    ],
  );

  PreferredSizeWidget _selectionBar(List<Document> selected) {
    final actions = DocumentActions(ref);
    final allPdf =
        selected.length >= 2 &&
        selected.every((d) => d.format == DocumentFormat.pdf);
    return AppBar(
      leading: IconButton(
        tooltip: 'Clear selection',
        icon: const Icon(Icons.close_rounded),
        onPressed: () => setState(_selected.clear),
      ),
      title: Text('${selected.length} selected'),
      actions: [
        IconButton(
          tooltip: 'Share',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: selected.isEmpty
              ? null
              : () => actions.share(context, selected),
        ),
        IconButton(
          tooltip: 'Move to folder',
          icon: const Icon(Icons.drive_file_move_rounded),
          onPressed: selected.isEmpty
              ? null
              : () async {
                  await actions.moveToFolder(context, selected);
                  if (mounted) setState(_selected.clear);
                },
        ),
        if (allPdf)
          IconButton(
            tooltip: 'Merge PDFs',
            icon: const Icon(Icons.merge_rounded),
            onPressed: () {
              final first = selected.first.id;
              setState(_selected.clear);
              unawaited(context.push(Routes.tool(ToolId.merge, docId: first)));
            },
          ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: selected.isEmpty
              ? null
              : () async {
                  final deleted = await actions.delete(context, selected);
                  if (deleted && mounted) setState(_selected.clear);
                },
        ),
      ],
    );
  }

  Widget _searchField() => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.x2,
      Space.gutter,
      Space.x2,
    ),
    child: TextField(
      controller: _search,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search by name',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.search.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = _query.copyWith(search: ''));
                },
              ),
      ),
      onChanged: (v) =>
          setState(() => _query = _query.copyWith(search: v.trim())),
    ),
  );

  Widget _filters() => SizedBox(
    height: 48,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      children: [
        for (final f in DocumentFilter.values)
          Padding(
            padding: const EdgeInsets.only(right: Space.x2),
            child: ChoiceChip(
              label: Text(f.label),
              selected: _query.filter == f,
              onSelected: (_) =>
                  setState(() => _query = _query.copyWith(filter: f)),
            ),
          ),
      ],
    ),
  );

  Widget _empty() {
    final searching =
        _query.search.isNotEmpty || _query.filter != DocumentFilter.all;
    if (searching) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches',
        message: 'Nothing matches your search or filter. Try a different name.',
        actionLabel: 'Clear filters',
        onAction: () {
          _search.clear();
          setState(
            () => _query = _query.copyWith(
              search: '',
              filter: DocumentFilter.all,
            ),
          );
        },
      );
    }
    return EmptyState(
      icon: Icons.folder_open_rounded,
      title: widget.emptyTitle,
      message: widget.emptyMessage,
      actionLabel: widget.folderId == null ? 'Scan a document' : null,
      onAction: widget.folderId == null
          ? () => context.push(Routes.scan())
          : null,
    );
  }

  Widget _listSliver(List<Document> docs) => SliverList.builder(
    itemCount: docs.length,
    itemBuilder: (context, i) {
      final d = docs[i];
      return DocumentListTile(
        key: ValueKey(d.id),
        doc: d,
        selected: _selected.contains(d.id),
        selecting: _selecting,
        onTap: () => _open(d),
        onLongPress: () => _toggle(d),
        onMore: () => _showMore(d),
      );
    },
  );

  Widget _gridSliver(List<Document> docs) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
    sliver: SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: Space.x3,
        crossAxisSpacing: Space.x3,
        childAspectRatio: 0.78,
      ),
      itemCount: docs.length,
      itemBuilder: (context, i) {
        final d = docs[i];
        return DocumentGridTile(
          key: ValueKey(d.id),
          doc: d,
          selected: _selected.contains(d.id),
          selecting: _selecting,
          onTap: () => _open(d),
          onLongPress: () => _toggle(d),
        );
      },
    ),
  );

  Future<void> _showMore(Document d) async {
    final actions = DocumentActions(ref);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(d.name, style: context.text.titleMedium),
              subtitle: Text(documentMeta(d)),
            ),
            const Divider(),
            _sheetItem(context, 'open', Icons.open_in_new_rounded, 'Open'),
            _sheetItem(context, 'share', Icons.ios_share_rounded, 'Share'),
            _sheetItem(
              context,
              'rename',
              Icons.drive_file_rename_outline_rounded,
              'Rename',
            ),
            _sheetItem(
              context,
              'favorite',
              d.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              d.favorite ? 'Remove from favorites' : 'Add to favorites',
            ),
            _sheetItem(
              context,
              'move',
              Icons.drive_file_move_rounded,
              'Move to folder',
            ),
            _sheetItem(
              context,
              'delete',
              Icons.delete_outline_rounded,
              'Delete',
              destructive: true,
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'open':
        _open(d);
      case 'share':
        await actions.share(context, [d]);
      case 'rename':
        await actions.rename(context, d);
      case 'favorite':
        await actions.toggleFavorite(context, d);
      case 'move':
        await actions.moveToFolder(context, [d]);
      case 'delete':
        await actions.delete(context, [d]);
    }
  }

  Widget _sheetItem(
    BuildContext context,
    String value,
    IconData icon,
    String label, {
    bool destructive = false,
  }) {
    final color = destructive ? context.colors.error : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: () => Navigator.pop(context, value),
    );
  }
}
