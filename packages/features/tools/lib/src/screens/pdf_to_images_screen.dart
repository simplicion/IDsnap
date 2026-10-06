import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/page_range.dart';
import 'package:feature_tools/src/common/providers.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ImageResolution {
  screen('Screen', '~150 dpi', 1240),
  standard('Standard', '~200 dpi', 1654),
  high('High', '~300 dpi', 2480);

  const ImageResolution(this.label, this.hint, this.width);
  final String label;
  final String hint;

  /// Pixel width for an A4-width page.
  final int width;
}

class PdfToImagesScreen extends ConsumerStatefulWidget {
  const PdfToImagesScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<PdfToImagesScreen> createState() => _PdfToImagesScreenState();
}

class _PdfToImagesScreenState extends ConsumerState<PdfToImagesScreen>
    with PreselectDocument {
  static const _job = 'pdf-to-images';
  var _inputs = <ToolInput>[];
  ImageOutputFormat _format = ImageOutputFormat.jpeg;
  ImageResolution _resolution = ImageResolution.standard;
  var _allPages = true;
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
    final range = count == null || _allPages
        ? null
        : parsePageRanges(_range.text, count);
    final pages = count == null
        ? null
        : (_allPages ? [for (var i = 0; i < count; i++) i] : range?.pages);
    final ready = pages != null && pages.isNotEmpty;

    return ToolScaffold(
      jobKey: _job,
      title: 'PDF to images',
      description: 'Save PDF pages as pictures you can post or attach.',
      primaryLabel: ready
          ? 'Export ${pages.length} image${pages.length == 1 ? '' : 's'}'
          : 'Export images',
      primaryIcon: Icons.collections_rounded,
      onPrimary: ready ? () => _run(input!, pages) : null,
      children: [
        InputPicker(
          accepts: acceptedFormats,
          inputs: _inputs,
          onChanged: (v) => setState(() => _inputs = v),
        ),
        ChoiceGroup<ImageOutputFormat>(
          label: 'Format',
          hint: 'JPG is smaller; PNG is sharper for text and drawings.',
          values: ImageOutputFormat.values,
          selected: _format,
          labelOf: (f) => f.label,
          onSelected: (f) => setState(() => _format = f),
        ),
        ChoiceGroup<ImageResolution>(
          label: 'Resolution',
          values: ImageResolution.values,
          selected: _resolution,
          labelOf: (r) => '${r.label} (${r.hint})',
          onSelected: (r) => setState(() => _resolution = r),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('All pages'),
          subtitle: count == null ? null : Text('$count pages'),
          value: _allPages,
          onChanged: (v) => setState(() => _allPages = v),
        ),
        if (!_allPages)
          TextField(
            controller: _range,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Pages',
              hintText: 'e.g. 1-3, 5',
              errorText: _range.text.isEmpty ? null : range?.error,
            ),
          ),
      ],
    );
  }

  void _run(ToolInput input, List<int> pages) {
    final format = _format;
    final width = _resolution.width;
    final pdf = ref.read(pdfEngineProvider);
    final images = ref.read(imageProcessorProvider);
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
      for (final (i, page) in pages.indexed) {
        final png = await pdf.renderPage(input.path, page, targetWidth: width);
        if (png case Err(:final failure)) return Err(failure);
        var bytes = png.valueOrNull!;
        if (format == ImageOutputFormat.jpeg) {
          final jpg = await images.compress(
            bytes,
            const ImageCompressionOptions(quality: 88),
          );
          if (jpg case Err(:final failure)) return Err(failure);
          bytes = Uint8List.fromList(jpg.valueOrNull!.bytes);
        }
        outputs.add(
          OutputFile(
            bytes: bytes,
            format: format == ImageOutputFormat.jpeg
                ? DocumentFormat.jpeg
                : DocumentFormat.png,
            suggestedName: '${input.name} - page ${page + 1}',
          ),
        );
        report((i + 1) / pages.length);
      }
      return Ok(outputs);
    }, label: 'Rendering pages…');
  }
}
