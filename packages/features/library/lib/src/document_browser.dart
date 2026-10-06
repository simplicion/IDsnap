import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_library/src/document_actions.dart';
import 'package:feature_library/src/document_tile.dart';
import 'package:feature_library/src/folders/add_menu.dart';
import 'package:feature_library/src/folders/folder_actions.dart';
import 'package:feature_library/src/folders/folder_lock.dart';
import 'package:feature_library/src/folders/folder_providers.dart';
import 'package:feature_library/src/folders/folder_visuals.dart';
import 'package:feature_library/src/library_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The ID Vault browser: one level of the folder tree (the top level when
/// [folderId] is null). Subfolders first, then files; a "+" button to add
/// folders, upload files or scan; search across this folder and everything
/// below it (never inside locked folders that aren't unlocked).
class VaultBrowser extends ConsumerStatefulWidget {
  const VaultBrowser({super.key, this.folderId, this.leading});

  final String? folderId;

  /// Optional sliver above the search field (the privacy banner).
  final Widget? leading;

  @override
  ConsumerState<VaultBrowser> createState() => _VaultBrowserState();
}

class _VaultBrowserState extends ConsumerState<VaultBrowser> {
  final _search = TextEditingController();
  String _text = '';
  DocumentSort _sort = DocumentSort.newest;
  DocumentFilter _filter = DocumentFilter.all;
  bool _grid = false;
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;
  bool get _searching => _text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final id = widget.folderId;
    if (id != null) {
      // Opening a locked folder asks to unlock straight away.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final tree = await ref.read(folderTreeProvider.future);
        if (!mounted) return;
        if (!tree.isAccessible(id, ref.read(folderAccessProvider))) {
          await ensureFolderAccess(context, ref, id);
        }
      });
    }
  }

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

  void _openFolder(Folder f) => unawaited(context.push(Routes.folder(f.id)));

  void _clearSearch() {
    _search.clear();
    setState(() {
      _text = '';
      _filter = DocumentFilter.all;
    });
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.folderId;
    final treeAsync = ref.watch(folderTreeProvider);
    final tree = treeAsync.value;
    final folder = tree?[id];

    if (id != null && tree != null && folder == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.folder_off_rounded,
          title: 'Folder not found',
          message: 'It may have been moved or deleted.',
        ),
      );
    }
    final title = folder?.name ?? (id == null ? 'ID Vault' : 'Folder');
    final accessible = canOpenFolder(ref, id);
    final underLock = tree != null && tree.locksOnPath(id).isNotEmpty;

    if (id != null && !accessible) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: tree == null
            ? const Center(child: CircularProgressIndicator())
            : LockedFolderView(
                name: title,
                onUnlock: () => ensureFolderAccess(context, ref, id),
              ),
      );
    }

    return FolderSecureScope(
      active: underLock,
      child: PopScope(
        canPop: !_selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(_selected.clear);
        },
        child: Scaffold(
          appBar: _selecting ? _selectionBar() : _normalBar(title, folder),
          floatingActionButton: _selecting
              ? null
              : FloatingActionButton(
                  tooltip: 'Add',
                  onPressed: () => showAddMenu(context, ref, folderId: id),
                  child: const Icon(Icons.add_rounded),
                ),
          body: CustomScrollView(
            slivers: [
              ?widget.leading,
              if (tree != null && id != null)
                SliverToBoxAdapter(child: _breadcrumb(tree.pathTo(id))),
              SliverToBoxAdapter(child: _searchField()),
              SliverToBoxAdapter(child: _filters()),
              if (tree == null && treeAsync.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: FailureView(
                    const AppFailure(
                      FailureCode.unknown,
                      message:
                          "Your files couldn't be listed. They are still on "
                          'this phone — try again.',
                    ),
                    onRetry: () => ref.invalidate(folderTreeProvider),
                  ),
                )
              else if (tree == null)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_searching)
                ..._searchResults(tree)
              else
                ..._contents(),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }

  // ── App bars ──────────────────────────────────────────────────────────────

  PreferredSizeWidget _normalBar(String title, Folder? folder) => AppBar(
    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    actions: [
      PopupMenuButton<DocumentSort>(
        tooltip: 'Sort',
        icon: const Icon(Icons.sort_rounded),
        initialValue: _sort,
        onSelected: (s) => setState(() => _sort = s),
        itemBuilder: (_) => [
          for (final s in DocumentSort.values)
            CheckedPopupMenuItem(
              value: s,
              checked: s == _sort,
              child: Text(s.label),
            ),
        ],
      ),
      IconButton(
        tooltip: _grid ? 'Show as list' : 'Show as grid',
        icon: Icon(_grid ? Icons.view_list_rounded : Icons.grid_view_rounded),
        onPressed: () => setState(() => _grid = !_grid),
      ),
      if (folder != null)
        IconButton(
          tooltip: 'Folder actions',
          icon: const Icon(Icons.more_vert_rounded),
          onPressed: () => showFolderActions(
            context,
            ref,
            folder,
            showOpen: false,
            onDeleted: () {
              if (mounted && context.canPop()) context.pop();
            },
          ),
        ),
    ],
  );

  PreferredSizeWidget _selectionBar() {
    final actions = DocumentActions(ref);
    final selected = _visibleSelected();
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

  List<Document> _visibleDocs() {
    final hidden = ref.watch(pendingDeletesProvider);
    final List<Document> docs;
    if (_searching) {
      docs = ref.watch(folderSearchProvider(_searchQuery())).value ?? const [];
    } else {
      docs =
          ref
              .watch(folderContentsProvider((widget.folderId, _sort, _filter)))
              .value
              ?.documents ??
          const [];
    }
    return [
      for (final d in docs)
        if (!hidden.contains(d.id)) d,
    ];
  }

  List<Document> _visibleSelected() => [
    for (final d in _visibleDocs())
      if (_selected.contains(d.id)) d,
  ];

  // ── Header widgets ────────────────────────────────────────────────────────

  Widget _breadcrumb(List<Folder> path) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: Space.x2),
    child: Row(
      children: [
        TextButton.icon(
          icon: const Icon(Icons.shield_outlined, size: 18),
          label: const Text('ID Vault'),
          onPressed: () => context.go(Routes.files),
        ),
        for (final (i, f) in path.indexed) ...[
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: context.ds.textSecondary,
          ),
          if (i == path.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x2),
              child: Text(
                f.name,
                style: context.text.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            TextButton(
              onPressed: () => context.go(Routes.folder(f.id)),
              child: Text(f.name),
            ),
        ],
      ],
    ),
  );

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
        hintText: widget.folderId == null
            ? 'Search your vault'
            : 'Search in this folder',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _search.clear();
                  setState(() => _text = '');
                },
              ),
      ),
      onChanged: (v) => setState(() => _text = v.trim()),
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
              selected: _filter == f,
              onSelected: (_) => setState(() => _filter = f),
            ),
          ),
      ],
    ),
  );

  // ── Contents ──────────────────────────────────────────────────────────────

  List<Widget> _contents() {
    final async = ref.watch(
      folderContentsProvider((widget.folderId, _sort, _filter)),
    );
    final contents = async.value;
    if (contents == null) {
      if (async.hasError) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: FailureView(
              const AppFailure(
                FailureCode.unknown,
                message:
                    "Your files couldn't be listed. They are still on this "
                    'phone — try again.',
              ),
              onRetry: () => ref.invalidate(folderContentsProvider),
            ),
          ),
        ];
      }
      return const [
        SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
      ];
    }
    final docs = _visibleDocs();
    final folders = contents.folders;
    if (folders.isEmpty && docs.isEmpty) {
      return [SliverFillRemaining(hasScrollBody: false, child: _empty())];
    }
    return [
      if (folders.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader('Folders')),
        _foldersSliver(folders),
      ],
      if (docs.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader('Files')),
        if (_grid) _gridSliver(docs) else _listSliver(docs),
      ] else if (_filter != DocumentFilter.all)
        SliverToBoxAdapter(child: _noMatches()),
    ];
  }

  FolderSearch _searchQuery() => FolderSearch(
    text: _text,
    withinFolderId: widget.folderId,
    unlockedFolderIds: ref.watch(folderAccessProvider),
    sort: _sort,
    filter: _filter,
  );

  List<Widget> _searchResults(FolderTree tree) {
    final unlocked = ref.watch(folderAccessProvider);
    final hidden = tree.hiddenContentIds(unlocked);
    final scope = widget.folderId == null
        ? tree.all.map((f) => f.id).toSet()
        : (tree.subtreeIds(widget.folderId!)..remove(widget.folderId));
    final needle = _text.toLowerCase();
    final folders = [
      for (final f in tree.all)
        if (scope.contains(f.id) &&
            !hidden.contains(f.parentId) &&
            f.name.toLowerCase().contains(needle))
          f,
    ]..sort(FolderTree.compareFolders);
    final docs = _visibleDocs();
    if (folders.isEmpty && docs.isEmpty) {
      return [SliverFillRemaining(hasScrollBody: false, child: _noMatches())];
    }
    return [
      if (folders.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader('Folders')),
        _foldersSliver(folders),
      ],
      if (docs.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionHeader('Files')),
        if (_grid) _gridSliver(docs) else _listSliver(docs),
      ],
    ];
  }

  Widget _noMatches() => EmptyState(
    icon: Icons.search_off_rounded,
    title: 'No matches',
    message: 'Nothing matches your search or filter. Try a different name.',
    actionLabel: 'Clear filters',
    onAction: _clearSearch,
  );

  Widget _empty() {
    final id = widget.folderId;
    if (_filter != DocumentFilter.all) return _noMatches();
    if (id == null) {
      return EmptyState(
        icon: Icons.folder_special_rounded,
        title: 'Your vault is empty',
        message:
            'Create a folder such as "IDs & Proofs", then upload files or '
            'scan documents into it. Everything stays on this device.',
        actionLabel: 'Create a folder',
        onAction: () => showNewFolderSheet(context, ref, parentId: null),
      );
    }
    return EmptyState(
      icon: Icons.folder_open_rounded,
      title: 'This folder is empty',
      message: 'Add a folder inside it, upload files or scan a document.',
      actionLabel: 'Add to this folder',
      onAction: () => showAddMenu(context, ref, folderId: id),
    );
  }

  Widget _foldersSliver(List<Folder> folders) {
    final stats = ref.watch(folderStatsProvider);
    final unlocked = ref.watch(folderAccessProvider);
    String subtitle(Folder f) => folderStatsLabel(
      stats[f.id],
      locked: f.isLocked && !unlocked.contains(f.id),
    );
    void more(Folder f) => showFolderActions(context, ref, f);
    if (_grid) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisSpacing: Space.x3,
            crossAxisSpacing: Space.x3,
            childAspectRatio: 1.25,
          ),
          itemCount: folders.length,
          itemBuilder: (context, i) {
            final f = folders[i];
            return FolderGridTile(
              key: ValueKey('folder-${f.id}'),
              folder: f,
              subtitle: subtitle(f),
              onTap: () => _openFolder(f),
              onMore: () => more(f),
            );
          },
        ),
      );
    }
    return SliverList.builder(
      itemCount: folders.length,
      itemBuilder: (context, i) {
        final f = folders[i];
        return FolderListTile(
          key: ValueKey('folder-${f.id}'),
          folder: f,
          subtitle: subtitle(f),
          onTap: () => _openFolder(f),
          onMore: () => more(f),
        );
      },
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
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
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
                'protect',
                Icons.lock_rounded,
                'Protect & share',
              ),
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
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'open':
        _open(d);
      case 'share':
        await actions.share(context, [d]);
      case 'protect':
        await actions.protectAndShare(context, d);
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
