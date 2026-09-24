import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MergeScreen extends ConsumerStatefulWidget {
  const MergeScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<MergeScreen> createState() => _MergeScreenState();
}

class _MergeScreenState extends ConsumerState<MergeScreen>
    with PreselectDocument {
  static const _job = 'merge';
  var _inputs = <ToolInput>[];
  final _name = TextEditingController(text: 'Merged document');

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => const {DocumentFormat.pdf};
  @override
  void onPreselected(ToolInput input) => setState(() => _inputs = [input]);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _inputs.length >= 2;
    return ToolScaffold(
      jobKey: _job,
      title: 'Merge PDFs',
      description:
          'Join several PDFs into one. Drag to set the order — the first '
          'file comes first.',
      primaryLabel: ready
          ? 'Merge ${_inputs.length} files'
          : 'Add at least 2 PDFs',
      primaryIcon: Icons.call_merge_rounded,
      onPrimary: ready ? _run : null,
      children: [
        InputPicker(
          accepts: acceptedFormats,
          inputs: _inputs,
          multiple: true,
          reorderable: true,
          title: 'PDFs to merge',
          onChanged: (v) => setState(() => _inputs = v),
        ),
        if (_inputs.length == 1)
          Text(
            'Add one more PDF to merge.',
            style: context.text.bodyMedium?.copyWith(color: context.ds.warning),
          ),
        OutputNameField(controller: _name),
      ],
    );
  }

  void _run() {
    final inputs = [..._inputs];
    final name = _name.text.trim().isEmpty ? 'Merged document' : _name.text;
    final pdf = ref.read(pdfEngineProvider);
    ref.read(jobProvider(_job).notifier).start((report) async {
      var total = 0;
      for (final (i, input) in inputs.indexed) {
        final count = await pdf.pageCount(input.path);
        if (count case Err(:final failure)) {
          return Err(AppFailure(failure.code, detail: input.fileLabel));
        }
        total += count.valueOrNull!;
        report((i + 1) / inputs.length * 0.3);
      }
      final merged = await pdf.merge([for (final i in inputs) i.path]);
      report(0.95);
      return merged.map(
        (bytes) => [
          OutputFile(
            bytes: bytes,
            format: DocumentFormat.pdf,
            suggestedName: name,
            expectedPages: total,
          ),
        ],
      );
    }, label: 'Merging PDFs…');
  }
}
