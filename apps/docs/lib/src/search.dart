import 'dart:async';

import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_docs/src/docs_repository.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

Future<void> openDocsSearch(
  BuildContext context,
  DocsRepository repository,
) async {
  final location = await showDialog<String>(
    context: context,
    builder: (context) => DocsSearchDialog(repository: repository),
  );
  if (location != null && context.mounted) context.go(location);
}

/// Full-text search across page titles and content.
class DocsSearchDialog extends StatefulWidget {
  const DocsSearchDialog({required this.repository, super.key});

  final DocsRepository repository;

  @override
  State<DocsSearchDialog> createState() => _DocsSearchDialogState();
}

class _DocsSearchDialogState extends State<DocsSearchDialog> {
  List<SearchHit> _hits = const [];
  String _query = '';
  Timer? _debounce;

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () async {
      final hits = await widget.repository.search(value);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _query = value.trim();
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(Space.x4),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText: 'Search the docs',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: Space.x3),
            Expanded(
              child: _query.isEmpty
                  ? Center(
                      child: Text(
                        'Try "offline", "passport" or "ADR"',
                        style: context.text.bodyMedium?.copyWith(
                          color: context.ds.textSecondary,
                        ),
                      ),
                    )
                  : _hits.isEmpty
                  ? Center(child: Text('No results for "$_query"'))
                  : ListView.separated(
                      itemCount: _hits.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, i) {
                        final hit = _hits[i];
                        return ListTile(
                          leading: const Icon(Icons.article_rounded),
                          title: Text(hit.page.title),
                          subtitle: Text(
                            hit.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Pill(hit.page.section),
                          onTap: () =>
                              Navigator.pop(context, hit.page.location),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
