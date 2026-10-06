import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/page_range.dart';
import 'package:feature_tools/src/common/providers.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SplitMode {
  extract('Extract pages', 'Selected pages into one new PDF'),
  eachPage('Every page', 'One PDF per page'),
  everyN('Every N pages', 'Split into equal parts');

  const SplitMode(this.label, this.hint);
  final String label;
  final String hint;
}

class SplitScreen extends ConsumerStatefulWidget {
  const SplitScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends ConsumerState<SplitScreen>
    with PreselectDocument {
  static const _job = 'split';
  var _inputs = <ToolInput>[];
  SplitMode _mode = SplitMode.extract;
  var _every = 2;
  final _range = TextEditingController();

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => const {DocumentFormat.pdf};
  @override
  void onPreselected(ToolInput input) => setState(() => _inputs = [input]);

  @override
  void dispose() {
    _range.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final input = _inputs.firstOrNull;
    final count = input == null
        ? null
        : ref.watch(pdfPageCountProvider(input.path)).value;
    final range = count == null ? null : parsePageRanges(_range.text, count);
    final canRun = switch (_mode) {
      _ when count == null => false,
      SplitMode.extract => range?.isValid ?? false,
      SplitMode.eachPage => count > 1,
      SplitMode.everyN => count > _every,
    };

    return ToolScaffold(
      jobKey: _job,
      title: 'Split & extract',
      description:
          'Pull pages out of a PDF or break it into smaller files. '
          'Your original stays unchanged.',
      primaryLabel: 'Split PDF',
      primaryIcon: Icons.call_split_rounded,
      onPrimary: canRun ? () => _run(input!, count!) : null,
      children: [
        InputPicker(
          accepts: acceptedFormats,
          inputs: _inputs,
          onChanged: (v) => setState(() => _inputs = v),
        ),
        if (count != null)
          Text(
            'This PDF has $count page${count == 1 ? '' : 's'}.',
            style: context.text.bodyMedium,
          ),
        RadioGroup<SplitMode>(
          groupValue: _mode,
          onChanged: (v) => setState(() => _mode = v ?? _mode),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How to split', style: context.text.titleSmall),
              const SizedBox(height: Space.x2),
              for (final m in SplitMode.values)
                RadioListTile<SplitMode>.adaptive(
                  value: m,
                  contentPadding: EdgeInsets.zero,
                  title: Text(m.label),
                  subtitle: Text(m.hint),
                ),
            ],
          ),
        ),
        if (_mode == SplitMode.extract)
          TextField(
            controller: _range,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              labelText: 'Pages',
              hintText: 'e.g. 1-3, 5, 8-10',
              helperText: 'Use commas and dashes. "7-" means 7 to the end.',
              errorText: _range.text.isEmpty ? null : range?.error,
            ),
          ),
        if (_mode == SplitMode.everyN)
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pages per file: $_every',
                  style: context.text.titleSmall,
                ),
              ),
              IconButton.outlined(
                tooltip: 'Fewer pages per file',
                onPressed: _every > 1 ? () => setState(() => _every--) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              const SizedBox(width: Space.x2),
              IconButton.outlined(
                tooltip: 'More pages per file',
                onPressed: () => setState(() => _every++),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
      ],
    );
  }

  void _run(ToolInput input, int count) {
    final groups = switch (_mode) {
      SplitMode.extract => [parsePageRanges(_range.text, count).pages],
      SplitMode.eachPage => chunkPages(count, 1),
      SplitMode.everyN => chunkPages(count, _every),
    };
    final extract = _mode == SplitMode.extract;
    final pdf = ref.read(pdfEngineProvider);
    final inspect = ref.read(inspectInputProvider);
    ref.read(jobProvider(_job).notifier).start((report) async {
      final pre = await inspect(
        input.path,
        accepts: const {DocumentFormat.pdf},
        nameHint: input.fileLabel,
      );
      if (pre case Err(:final failure)) {
        return Err(failure.withDetail(input.fileLabel));
      }
      final outputs = <OutputFile>[];
      for (final (i, pages) in groups.indexed) {
        final r = await pdf.selectPages(input.path, pages);
        if (r case Err(:final failure)) return Err(failure);
        final label = extract ? 'extract' : 'pages ${describePages(pages)}';
        outputs.add(
          OutputFile(
            bytes: r.valueOrNull!,
            format: DocumentFormat.pdf,
            suggestedName: '${input.name} ($label)',
            expectedPages: pages.length,
          ),
        );
        report((i + 1) / groups.length);
      }
      return Ok(outputs);
    }, label: 'Splitting PDF…');
  }
}
