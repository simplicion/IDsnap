import 'dart:convert';
import 'dart:typed_data';

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

const Set<DocumentFormat> ocrInputs = {
  DocumentFormat.jpeg,
  DocumentFormat.png,
  DocumentFormat.webp,
  DocumentFormat.bmp,
  DocumentFormat.pdf,
};

/// One page of the result list: editable text, or the reason it failed.
class _PageText {
  _PageText(this.page) : controller = TextEditingController(text: page.text);

  final OcrPage page;
  final TextEditingController controller;

  String get title => page.label;
  AppFailure? get failure => page.failure;
  bool get fromPdfText => page.fromPdfText;
  bool get rotated => (page.result?.quarterTurns ?? 0) != 0;
}

class OcrScreen extends ConsumerStatefulWidget {
  const OcrScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends ConsumerState<OcrScreen> with PreselectDocument {
  static const _job = 'ocr';
  var _inputs = <ToolInput>[];

  /// `null` = Auto (Latin first, then every other installed script).
  OcrScript? _script;

  /// True once the user picked a script themselves.
  bool _scriptTouched = false;
  OcrCancelToken? _cancel;
  String? _progressLabel;
  double? _progress;
  bool _running = false;
  AppFailure? _failure;
  List<_PageText>? _results;

  /// Inputs of the run that produced [_results].
  List<ToolInput> _resultInputs = const [];

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => ocrInputs;
  @override
  void onPreselected(ToolInput input) => setState(() => _inputs = [input]);

  @override
  void dispose() {
    _cancel?.cancel();
    _disposeResults();
    super.dispose();
  }

  void _disposeResults() {
    for (final r in _results ?? <_PageText>[]) {
      r.controller.dispose();
    }
  }

  OcrScript? get _chosenScript => _scriptTouched ? _script : null;

  String get _allText => [
    for (final r in _results ?? <_PageText>[])
      if (r.failure == null) r.controller.text.trim(),
  ].where((t) => t.isNotEmpty).join('\n\n');

  String get _baseName =>
      _resultInputs.firstOrNull?.name ??
      _inputs.firstOrNull?.name ??
      'Extracted text';

  /// OCR results for a searchable PDF: every input is an image, every page
  /// was read, and all text is Latin (the PDF text layer font covers Latin
  /// only). `null` when a searchable PDF can't be made.
  List<OcrResult>? get _searchableLayers {
    final results = _results;
    if (results == null || results.isEmpty) return null;
    if (_resultInputs.any((i) => i.format == DocumentFormat.pdf)) return null;
    if (results.length != _resultInputs.length) return null;
    final layers = <OcrResult>[];
    for (final r in results) {
      final ocr = r.page.result;
      if (ocr == null || ocr.script != OcrScript.latin) return null;
      layers.add(ocr);
    }
    return layers;
  }

  void _resetScriptToAuto() => setState(() {
    _script = null;
    _scriptTouched = false;
    _failure = null;
  });

  @override
  Widget build(BuildContext context) {
    if (_running) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _stop();
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('Extract text')),
          body: ProgressPanel(
            label: _progressLabel ?? 'Preparing…',
            progress: _progress,
            onCancel: (_cancel?.isCancelled ?? true) ? null : _stop,
          ),
        ),
      );
    }
    final results = _results;
    final docxSpec = _docxSpec();
    final script = _chosenScript;
    return ToolScaffold(
      jobKey: _job,
      title: 'Extract text',
      description:
          'Recognize text in photos and scanned PDFs, right on your phone. '
          'Edit it, copy it, or save it as a file.',
      primaryLabel: results == null ? 'Recognize text' : null,
      primaryIcon: Icons.text_snippet_rounded,
      onPrimary: _inputs.isEmpty ? null : _recognize,
      failureActions: {FailureAction.changeLanguage: _resetToForm},
      actions: [
        if (results != null)
          IconButton(
            tooltip: 'Start over',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: _startOver,
          ),
      ],
      children: results == null
          ? [
              InputPicker(
                accepts: ocrInputs,
                inputs: _inputs,
                multiple: true,
                reorderable: true,
                title: 'Photos or a PDF',
                onChanged: (v) => setState(() => _inputs = v),
              ),
              _ScriptPicker(
                selected: script,
                onSelected: (s) => setState(() {
                  _script = s;
                  _scriptTouched = s != null;
                  _failure = null;
                }),
              ),
              if (script != null) _CapabilityNote(script: script),
              if (_failure != null)
                FailureView(
                  _failure!,
                  onRetry: _recognize,
                  actions: {
                    FailureAction.pickDifferentFile: () => setState(() {
                      _inputs = [];
                      _failure = null;
                    }),
                    FailureAction.changeLanguage: _resetScriptToAuto,
                    FailureAction.useFewerPages: () =>
                        setState(() => _failure = null),
                  },
                ),
            ]
          : _resultChildren(context, results, docxSpec),
    );
  }

  List<Widget> _resultChildren(
    BuildContext context,
    List<_PageText> results,
    ConversionSpec? docxSpec,
  ) {
    final read = results.where((r) => r.failure == null).toList();
    final failed = results.length - read.length;
    final layers = _searchableLayers;
    return [
      const FidelityNote(
        label: 'Review before use',
        explanation:
            'Recognition can make mistakes — review before use, '
            'especially names, numbers and dates.',
      ),
      if (failed > 0)
        FidelityNote(
          label: read.isEmpty
              ? "Couldn't read any page"
              : "$failed ${failed == 1 ? 'page' : 'pages'} couldn't be read",
          explanation: read.isEmpty
              ? 'See the reason under each page below.'
              : 'The other pages were read and are below. See the reason '
                    'under each failed page.',
        ),
      if (read.isNotEmpty &&
          read.every((r) => r.controller.text.trim().isEmpty))
        const EmptyState(
          icon: Icons.text_fields_rounded,
          title: 'No text found',
          message:
              'Try a sharper photo with more light, or choose the '
              'right language.',
        ),
      _ActionBar(
        onCopy: _copy,
        onShare: _share,
        onSaveTxt: _saveTxt,
        onSaveDocx: docxSpec == null ? null : () => _saveDocx(docxSpec),
        onSaveSearchablePdf: layers == null
            ? null
            : () => _saveSearchablePdf(layers),
      ),
      for (final r in results) _PageCard(page: r),
    ];
  }

  ConversionSpec? _docxSpec() {
    for (final s in ref.watch(conversionSpecsProvider)) {
      if (s.inputs.contains(DocumentFormat.txt) &&
          s.output == DocumentFormat.docx) {
        return s;
      }
    }
    return null;
  }

  void _resetToForm() {
    ref.read(jobProvider(_job).notifier).reset();
    _resetScriptToAuto();
  }

  void _startOver() {
    ref.read(jobProvider(_job).notifier).reset();
    setState(() {
      _disposeResults();
      _results = null;
      _resultInputs = const [];
    });
  }

  void _stop() {
    final token = _cancel;
    if (token == null || token.isCancelled) return;
    token.cancel();
    setState(() => _progressLabel = 'Stopping after this page…');
  }

  Future<void> _recognize() async {
    final inputs = [..._inputs];
    if (inputs.isEmpty) return;
    final sources = <OcrSource>[
      for (final i in inputs)
        if (i.format == DocumentFormat.pdf)
          OcrPdfSource(i.path, i.fileLabel)
        else
          OcrImageSource(i.path, i.fileLabel),
    ];
    final token = OcrCancelToken();
    final recognize = ref.read(recognizeDocumentProvider);
    final options = OcrOptions(script: _chosenScript);
    setState(() {
      _running = true;
      _cancel = token;
      _progress = null;
      _progressLabel = 'Preparing…';
      _failure = null;
    });

    Result<OcrDocumentResult> result;
    try {
      result = await recognize(
        sources,
        options: options,
        cancel: token,
        onProgress: (p) {
          if (!mounted || token.isCancelled) return;
          setState(() {
            _progress = p.fraction;
            final n = (p.done + 1).clamp(1, p.total);
            _progressLabel = p.total > 1
                ? 'Reading ${p.label} ($n of ${p.total})…'
                : 'Reading ${p.label}…';
          });
        },
      );
    } on Object catch (e, st) {
      result = Err(
        AppFailure(
          FailureCode.unknown,
          cause: e,
          stackTrace: st,
          message:
              'Text recognition stopped unexpectedly and nothing was saved. '
              'Try again; if it keeps happening, try fewer pages or a '
              'smaller photo, and copy the error details for support.',
        ),
      );
    }
    if (!mounted) return;

    switch (result) {
      case Err(:final failure):
        setState(() {
          _running = false;
          _cancel = null;
          _failure = failure;
        });
      case Ok(value: final doc):
        final pages = doc.pages;
        setState(() {
          _running = false;
          _cancel = null;
          if (doc.cancelled && pages.isEmpty) return;
          _disposeResults();
          _results = [for (final p in pages) _PageText(p)];
          _resultInputs = inputs;
        });
        if (doc.cancelled) {
          final n = pages.length;
          showAppSnack(
            context,
            n == 0
                ? 'Stopped — no pages read'
                : "Stopped — $n ${n == 1 ? 'page' : 'pages'} read",
          );
        }
    }
  }

  Future<void> _copy() async {
    final r = await ref.read(shareServiceProvider).copyText(_allText);
    if (!mounted) return;
    r.fold(
      (_) => showAppSnack(context, 'Text copied'),
      (f) => showFailureSnack(context, f),
    );
  }

  Future<void> _share() async {
    final r = await ref.read(shareServiceProvider).shareText(_allText);
    if (!mounted) return;
    if (r case Err(:final failure)) showFailureSnack(context, failure);
  }

  void _saveTxt() {
    final text = _allText;
    final name = _baseName;
    ref
        .read(jobProvider(_job).notifier)
        .start(
          (report) async => Ok([
            OutputFile(
              bytes: utf8.encode(text),
              format: DocumentFormat.txt,
              suggestedName: '$name (text)',
            ),
          ]),
          label: 'Saving text…',
        );
  }

  void _saveDocx(ConversionSpec spec) {
    final text = _allText;
    final name = _baseName;
    final files = ref.read(fileStoreProvider);
    final engine = ref.read(conversionEngineProvider);
    ref.read(jobProvider(_job).notifier).start((report) async {
      final temp = await files.writeTemp(utf8.encode(text), 'txt');
      try {
        return await engine.convert(
          ConversionRequest(
            specId: spec.id,
            inputs: [
              ConversionInput(
                path: temp,
                name: '$name (text)',
                format: DocumentFormat.txt,
              ),
            ],
          ),
          onProgress: report,
        );
      } finally {
        await files.delete(temp);
      }
    }, label: 'Creating Word document…');
  }

  /// Page images with the recognized text as an invisible, selectable layer.
  /// Boxes are normalized to the upright-as-shown photo, which is what the
  /// JPEG re-encode (EXIF orientation baked in) produces.
  void _saveSearchablePdf(List<OcrResult> layers) {
    final inputs = [..._resultInputs];
    final name = _baseName;
    final files = ref.read(fileStoreProvider);
    final images = ref.read(imageProcessorProvider);
    final pdf = ref.read(pdfEngineProvider);
    ref.read(jobProvider(_job).notifier).start((report) async {
      final jpegs = <Uint8List>[];
      for (final (i, input) in inputs.indexed) {
        final bytes = await files.read(input.path);
        final jpeg = await images.compress(
          bytes,
          const ImageCompressionOptions(quality: 85, maxDimension: 4096),
        );
        if (jpeg case Err(:final failure)) {
          return Err(failure.withDetail(input.fileLabel));
        }
        jpegs.add(Uint8List.fromList(jpeg.valueOrNull!.bytes));
        report((i + 1) / inputs.length * 0.8);
      }
      final out = await pdf.fromImages(
        jpegs,
        const PdfBuildOptions(),
        textLayers: layers,
      );
      return out.map(
        (b) => [
          OutputFile(
            bytes: b,
            format: DocumentFormat.pdf,
            suggestedName: '$name (searchable)',
            expectedPages: jpegs.length,
          ),
        ],
      );
    }, label: 'Creating searchable PDF…');
  }
}

/// Auto plus every script; scripts without an installed model are marked.
class _ScriptPicker extends ConsumerWidget {
  const _ScriptPicker({required this.selected, required this.onSelected});

  final OcrScript? selected;
  final ValueChanged<OcrScript?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool installed(OcrScript s) =>
        ref.watch(ocrCapabilityProvider(s)).value?.available ?? true;
    return ChoiceGroup<OcrScript?>(
      label: 'Language / script',
      hint:
          'Auto reads Latin first and tries the other installed scripts '
          'when that finds little text.',
      values: const [null, ...OcrScript.values],
      selected: selected,
      labelOf: (s) => s == null
          ? 'Auto'
          : installed(s)
          ? s.shortLabel
          : '${s.shortLabel} (not installed)',
      onSelected: onSelected,
    );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard({required this.page});

  final _PageText page;

  @override
  Widget build(BuildContext context) {
    final failure = page.failure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(page.title, style: context.text.titleSmall)),
            if (failure != null)
              Pill(
                "Couldn't read",
                icon: Icons.error_outline_rounded,
                color: context.colors.onErrorContainer,
                background: context.colors.errorContainer,
              )
            else if (page.fromPdfText)
              const Pill('Text from PDF')
            else
              const Pill('Recognized'),
          ],
        ),
        if (page.rotated) ...[
          const SizedBox(height: Space.x1),
          Row(
            children: [
              Icon(
                Icons.rotate_right_rounded,
                size: 16,
                color: context.ds.textSecondary,
              ),
              const SizedBox(width: Space.x1),
              Text(
                'Page was rotated to read it',
                style: context.text.bodySmall?.copyWith(
                  color: context.ds.textSecondary,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: Space.x2),
        if (failure != null)
          FailureView(failure)
        else
          TextField(
            controller: page.controller,
            minLines: 3,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(hintText: 'No text on this page'),
          ),
      ],
    );
  }
}

class _CapabilityNote extends ConsumerWidget {
  const _CapabilityNote({required this.script});

  final OcrScript script;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cap = ref.watch(ocrCapabilityProvider(script)).value;
    if (cap == null || (cap.available && !cap.requiresDownload)) {
      return const SizedBox.shrink();
    }
    return FidelityNote(
      label: cap.available ? 'One-time setup' : 'Not installed in this app',
      explanation:
          cap.note ??
          (cap.available
              ? 'This language model downloads once, then works offline.'
              : '${script.shortLabel} text recognition is not included in '
                    'this app. Choose Auto or another language.'),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onCopy,
    required this.onShare,
    required this.onSaveTxt,
    required this.onSaveDocx,
    required this.onSaveSearchablePdf,
  });

  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onSaveTxt;
  final VoidCallback? onSaveDocx;
  final VoidCallback? onSaveSearchablePdf;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: Space.x2,
    runSpacing: Space.x2,
    children: [
      FilledButton.tonalIcon(
        onPressed: onCopy,
        icon: const Icon(Icons.copy_rounded),
        label: const Text('Copy'),
      ),
      FilledButton.tonalIcon(
        onPressed: onShare,
        icon: const Icon(Icons.ios_share_rounded),
        label: const Text('Share'),
      ),
      OutlinedButton.icon(
        onPressed: onSaveTxt,
        icon: const Icon(Icons.save_alt_rounded),
        label: const Text('Save as TXT'),
      ),
      if (onSaveDocx != null)
        OutlinedButton.icon(
          onPressed: onSaveDocx,
          icon: const Icon(Icons.description_rounded),
          label: const Text('Save as Word'),
        ),
      if (onSaveSearchablePdf != null)
        OutlinedButton.icon(
          onPressed: onSaveSearchablePdf,
          icon: const Icon(Icons.picture_as_pdf_rounded),
          label: const Text('Save as searchable PDF'),
        ),
    ],
  );
}
