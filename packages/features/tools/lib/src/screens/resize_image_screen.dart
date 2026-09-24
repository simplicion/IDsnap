import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/input_picker.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/providers.dart';
import 'package:feature_tools/src/common/tool_scaffold.dart';
import 'package:feature_tools/src/screens/compress_image_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ResizeImageScreen extends ConsumerStatefulWidget {
  const ResizeImageScreen({super.key, this.initialDocId});

  final String? initialDocId;

  @override
  ConsumerState<ResizeImageScreen> createState() => _ResizeImageScreenState();
}

class _ResizeImageScreenState extends ConsumerState<ResizeImageScreen>
    with PreselectDocument {
  static const _job = 'resize-image';
  var _inputs = <ToolInput>[];
  final _width = TextEditingController();
  final _height = TextEditingController();
  var _lock = true;
  ImageDetails? _details;

  @override
  String? get initialDocId => widget.initialDocId;
  @override
  Set<DocumentFormat> get acceptedFormats => compressibleImages;
  @override
  void onPreselected(ToolInput input) => _setInputs([input]);

  void _setInputs(List<ToolInput> v) => setState(() {
    _inputs = v;
    _details = null;
    _width.clear();
    _height.clear();
  });

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _applyPercent(int percent) {
    final d = _details;
    if (d == null) return;
    setState(() {
      _width.text = '${(d.width * percent / 100).round()}';
      _height.text = '${(d.height * percent / 100).round()}';
    });
  }

  void _onWidth(String v) {
    final d = _details;
    final w = int.tryParse(v);
    if (_lock && d != null && w != null) {
      _height.text = '${(w * d.height / d.width).round()}';
    }
    setState(() {});
  }

  void _onHeight(String v) {
    final d = _details;
    final h = int.tryParse(v);
    if (_lock && d != null && h != null) {
      _width.text = '${(h * d.width / d.height).round()}';
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final input = _inputs.firstOrNull;
    final loaded = input == null
        ? null
        : ref.watch(imageDetailsProvider(input.path)).value;
    if (loaded != null && _details == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _details != null) return;
        setState(() {
          _details = loaded;
          _width.text = '${loaded.width}';
          _height.text = '${loaded.height}';
        });
      });
    }
    final w = int.tryParse(_width.text);
    final h = int.tryParse(_height.text);
    final valid =
        w != null && h != null && w > 0 && h > 0 && w <= 12000 && h <= 12000;

    return ToolScaffold(
      jobKey: _job,
      title: 'Resize image',
      description: 'Set exact pixel dimensions, or scale by a percentage.',
      primaryLabel: valid ? 'Resize to $w × $h' : 'Resize',
      primaryIcon: Icons.aspect_ratio_rounded,
      onPrimary: input != null && valid ? () => _run(input, w, h) : null,
      children: [
        InputPicker(
          accepts: compressibleImages,
          inputs: _inputs,
          onChanged: _setInputs,
        ),
        if (_details != null) ...[
          Text(
            'Original: ${_details!.width} × ${_details!.height} px',
            style: context.text.bodyMedium,
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _width,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Width (px)'),
                  onChanged: _onWidth,
                ),
              ),
              IconButton(
                tooltip: _lock ? 'Unlock aspect ratio' : 'Lock aspect ratio',
                isSelected: _lock,
                icon: const Icon(Icons.link_off_rounded),
                selectedIcon: const Icon(Icons.link_rounded),
                onPressed: () => setState(() => _lock = !_lock),
              ),
              Expanded(
                child: TextField(
                  controller: _height,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Height (px)'),
                  onChanged: _onHeight,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: Space.x2,
            children: [
              for (final p in const [25, 50, 75])
                ActionChip(
                  label: Text('$p%'),
                  onPressed: () => _applyPercent(p),
                ),
            ],
          ),
        ],
      ],
    );
  }

  void _run(ToolInput input, int w, int h) {
    final files = ref.read(fileStoreProvider);
    final images = ref.read(imageProcessorProvider);
    final format = input.format == DocumentFormat.png
        ? ImageOutputFormat.png
        : ImageOutputFormat.jpeg;
    ref.read(jobProvider(_job).notifier).start((report) async {
      final bytes = await files.read(input.path);
      final r = await images.crop(
        bytes,
        NRect.full,
        outputWidth: w,
        outputHeight: h,
        format: format,
      );
      return r.map(
        (enc) => [
          OutputFile(
            bytes: Uint8List.fromList(enc.bytes),
            format: format == ImageOutputFormat.png
                ? DocumentFormat.png
                : DocumentFormat.jpeg,
            suggestedName: '${input.name} ($w×$h)',
          ),
        ],
      );
    }, label: 'Resizing…');
  }
}
