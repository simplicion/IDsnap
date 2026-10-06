import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:engine_codes/engine_codes.dart';
import 'package:feature_qr/src/history.dart';
import 'package:feature_qr/src/result_screen.dart';
import 'package:feature_qr/src/services.dart';
import 'package:feature_qr/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Continuous camera scan (every supported symbology, torch toggle) plus
/// decoding pictures from the gallery or files. Fully on-device.
class QrScanScreen extends ConsumerStatefulWidget {
  const QrScanScreen({super.key});

  static const noCodeInImage =
      'No QR code or barcode was found in this '
      'picture.';

  /// The same code is ignored for this long after returning to the camera.
  static const repeatCooldown = Duration(seconds: 3);

  @override
  ConsumerState<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends ConsumerState<QrScanScreen> {
  final _controller = CodeScannerController();
  bool _showing = false;
  String? _lastRaw;
  DateTime _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  AppFailure? _cameraFailure;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _record(List<ScannedCode> codes) async {
    final history = ref.read(qrHistoryProvider.notifier);
    for (final c in codes) {
      try {
        await history.record(c);
      } on Object {
        // History is optional; never block a scan on it.
      }
    }
  }

  Future<void> _showResult(ScannedCode code) async {
    _showing = true;
    _controller.paused.value = true;
    _controller.torch.value = false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CodeResultScreen(code: code)),
    );
    if (!mounted) return;
    _showing = false;
    _lastRaw = code.raw;
    _cooldownUntil = DateTime.now().add(QrScanScreen.repeatCooldown);
    _controller.paused.value = false;
  }

  void _onDetect(List<ScannedCode> codes) {
    if (_showing || !mounted) return;
    final code = codes.where((c) => c.raw.isNotEmpty).firstOrNull;
    if (code == null) return;
    if (code.raw == _lastRaw && DateTime.now().isBefore(_cooldownUntil)) {
      return;
    }
    unawaited(_record([code]));
    unawaited(_showResult(code));
  }

  Future<void> _pick({required bool files}) async {
    final picker = ref.read(mediaPickerProvider);
    final picked = files
        ? await picker.pickFiles(const {
            DocumentFormat.jpeg,
            DocumentFormat.png,
            DocumentFormat.webp,
            DocumentFormat.bmp,
            DocumentFormat.gif,
            DocumentFormat.heic,
          })
        : await picker.pickImages(multiple: false);
    if (!mounted) return;
    switch (picked) {
      case Err(:final failure):
        showFailureSnack(context, failure);
      case Ok(:final value) when value.isEmpty:
        return;
      case Ok(:final value):
        final decoded = await ref
            .read(codeScannerProvider)
            .decodeImage(value.first.path);
        if (!mounted) return;
        switch (decoded) {
          case Err(:final failure):
            showFailureSnack(context, failure);
          case Ok(:final value) when value.isEmpty:
            showAppSnack(context, QrScanScreen.noCodeInImage);
          case Ok(value: final codes):
            unawaited(_record(codes));
            if (codes.length == 1) {
              await _showResult(codes.single);
            } else {
              _controller.paused.value = true;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CodeListScreen(codes: codes),
                ),
              );
              if (mounted) _controller.paused.value = false;
            }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final capability = ref.watch(_capabilityProvider);
    final cameraOk =
        (capability.value?.available ?? false) && _cameraFailure == null;
    final failure =
        _cameraFailure ??
        (capability.value?.available == false
            ? AppFailure(
                FailureCode.cameraUnavailable,
                detail: capability.value?.note,
                action: FailureAction.pickDifferentFile,
              )
            : null);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR / barcode'),
        actions: [
          IconButton(
            tooltip: 'Create QR code',
            onPressed: () =>
                pushIfPro(context, ref, ProFeature.qrTools, Routes.qrGenerate),
            // PRO marker while creating codes is locked by the policy.
            icon: Badge(
              isLabelVisible: proBadgeLabel(ref, ProFeature.qrTools) != null,
              label: const Text('PRO'),
              child: const Icon(Icons.qr_code_2_rounded),
            ),
          ),
          IconButton(
            tooltip: 'Scan history',
            onPressed: () => context.push(Routes.qrHistory),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: capability.isLoading
                ? const Center(child: CircularProgressIndicator())
                : cameraOk
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ref
                          .read(codeScannerProvider)
                          .buildPreview(
                            context,
                            controller: _controller,
                            onDetect: _onDetect,
                            onError: (f) => setState(() => _cameraFailure = f),
                          ),
                      const _Viewfinder(),
                      Positioned(
                        right: Space.x4,
                        bottom: Space.x4,
                        child: _TorchButton(_controller),
                      ),
                    ],
                  )
                : FailureView(
                    failure ?? const AppFailure(FailureCode.cameraUnavailable),
                    actions: {
                      FailureAction.pickDifferentFile: () =>
                          unawaited(_pick(files: false)),
                      FailureAction.retry: () => setState(() {
                        _cameraFailure = null;
                        ref.invalidate(_capabilityProvider);
                      }),
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: Column(
                children: [
                  Text(
                    'Point the camera at a QR code or barcode. Everything is '
                    'decoded on this phone. Nothing is uploaded.',
                    style: context.text.bodyMedium?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.x3),
                  Wrap(
                    spacing: Space.x2,
                    runSpacing: Space.x2,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => unawaited(_pick(files: false)),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Gallery'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => unawaited(_pick(files: true)),
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('Files'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final _capabilityProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(codeScannerProvider).capability(),
);

class _TorchButton extends StatelessWidget {
  const _TorchButton(this.controller);

  final CodeScannerController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: controller.torchAvailable,
    builder: (context, available, _) => !available
        ? const SizedBox.shrink()
        : ValueListenableBuilder<bool>(
            valueListenable: controller.torch,
            builder: (context, on, _) => IconButton.filledTonal(
              tooltip: on ? 'Turn off flashlight' : 'Turn on flashlight',
              isSelected: on,
              onPressed: () => controller.torch.value = !on,
              icon: Icon(
                on ? Icons.flashlight_off_rounded : Icons.flashlight_on_rounded,
              ),
            ),
          ),
  );
}

class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        width: 260,
        height: 200,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 3),
          borderRadius: Radii.cardAll,
        ),
      ),
    ),
  );
}

/// Every code found in one picture.
class CodeListScreen extends StatelessWidget {
  const CodeListScreen({required this.codes, super.key});

  final List<ScannedCode> codes;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${codes.length} codes found')),
    body: ListView.separated(
      itemCount: codes.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final code = codes[i];
        final content = CodeParser.parseCode(code);
        return ListTile(
          leading: IconBadge(kindIcon(content.kind)),
          title: Text(
            content.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('${content.title} · ${code.symbology.label}'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CodeResultScreen(code: code),
            ),
          ),
        );
      },
    ),
  );
}
