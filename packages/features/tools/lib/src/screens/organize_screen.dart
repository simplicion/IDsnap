import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/providers.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class _OrgPage {
  const _OrgPage(this.source, [this.turns = 0]);

  /// 0-based page index in the source PDF.
  final int source;
  final int turns;

  _OrgPage rotated() => _OrgPage(source, (turns + 1) % 4);
}

class OrganizeScreen extends ConsumerStatefulWidget {
  const OrganizeScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<OrganizeScreen> createState() => _OrganizeScreenState();
}

class _OrganizeScreenState extends ConsumerState<OrganizeScreen>
    with PreselectDocument {
  static const _job = 'organize';
  var _inputs = <ToolInput>[];
  List<_OrgPage>? _pages;
  int? _loadedFor;

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => const {DocumentFormat.pdf};
  @override
  void onPreselected(ToolInput input) => _setInputs([input]);

  void _setInputs(List<ToolInput> v) => setState(() {
    _inputs = v;
    _pages = null;
    _loadedFor = null;
  });

  @override
  Widget build(BuildContext context) {
    final input = _inputs.firstOrNull;
    final count = input == null
        ? null
        : ref.watch(pdfPageCountProvider(input.path)).value;
    if (count != null && _loadedFor != input.hashCode) {
      _pages = [for (var i = 0; i < count; i++) _OrgPage(i)];
      _loadedFor = input.hashCode;
    }
    final pages = _pages;
    final changed =
        pages != null &&
        (pages.length != count ||
            pages.indexed.any((e) => e.$2.source != e.$1 || e.$2.turns != 0));

    return ToolScaffold(
      jobKey: _job,
      title: 'Organize pages',
      description:
          'Drag pages into a new order, rotate or remove them. '
          'Saves as a new copy — your original is kept.',
      primaryLabel: 'Save as new PDF',
      primaryIcon: Icons.save_alt_rounded,
      onPrimary: changed && pages.isNotEmpty ? () => _run(input!, pages) : null,
      actions: [
        if (changed)
          IconButton(
            tooltip: 'Undo all changes',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () => setState(() => _loadedFor = null),
          ),
      ],
      children: [
        InputPicker(
          accepts: acceptedFormats,
          inputs: _inputs,
          onChanged: _setInputs,
        ),
        if (input != null && pages != null) ...[
          Text(
            '${pages.length} of $count pages · long-press and drag to move',
            style: context.text.bodyMedium?.copyWith(
              color: context.ds.textSecondary,
            ),
          ),
          if (pages.isEmpty)
            Text(
              'All pages removed. Undo to start again.',
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.error,
              ),
            ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pages.length,
            onReorderItem: (from, to) => setState(() {
              final item = pages.removeAt(from);
              pages.insert(to, item);
            }),
            itemBuilder: (context, i) {
              final p = pages[i];
              return Padding(
                key: ValueKey(p.source),
                padding: const EdgeInsets.only(bottom: Space.x2),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.x2),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: Radii.smAll,
                          child: RotatedBox(
                            quarterTurns: p.turns,
                            child: PdfPageThumb(
                              path: input.path,
                              index: p.source,
                              size: 72,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Page ${i + 1}',
                                style: context.text.titleSmall,
                              ),
                              Text(
                                p.source == i
                                    ? 'Original position'
                                    : 'Was page ${p.source + 1}',
                                style: context.text.bodySmall?.copyWith(
                                  color: context.ds.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Rotate page ${i + 1}',
                          icon: const Icon(Icons.rotate_right_rounded),
                          onPressed: () =>
                              setState(() => pages[i] = p.rotated()),
                        ),
                        IconButton(
                          tooltip: 'Remove page ${i + 1}',
                          icon: Icon(
                            Icons.delete_outline_rounded,
                            color: context.colors.error,
                          ),
                          onPressed: () => setState(() => pages.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  void _run(ToolInput input, List<_OrgPage> pages) {
    final order = [for (final p in pages) p.source];
    final turns = {
      for (final (i, p) in pages.indexed)
        if (p.turns != 0) i: p.turns,
    };
    final pdf = ref.read(pdfEngineProvider);
    final files = ref.read(fileStoreProvider);
    ref.read(jobProvider(_job).notifier).start((report) async {
      final selected = await pdf.selectPages(input.path, order);
      if (selected case Err(:final failure)) return Err(failure);
      var bytes = selected.valueOrNull!;
      report(0.5);
      if (turns.isNotEmpty) {
        final temp = await files.writeTemp(bytes, 'pdf');
        try {
          final rotated = await pdf.rotatePages(temp, turns);
          if (rotated case Err(:final failure)) return Err(failure);
          bytes = rotated.valueOrNull!;
        } finally {
          await files.delete(temp);
        }
      }
      return Ok([
        OutputFile(
          bytes: bytes,
          format: DocumentFormat.pdf,
          suggestedName: '${input.name} (organized)',
          expectedPages: order.length,
        ),
      ]);
    }, label: 'Saving pages…');
  }
}
