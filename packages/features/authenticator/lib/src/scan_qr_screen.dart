import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:feature_authenticator/src/secure_scope.dart';
import 'package:feature_authenticator/src/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Scans an `otpauth://` QR code with the camera (bundled on-device model,
/// no network) or from a picture chosen in the gallery.
class ScanQrScreen extends ConsumerStatefulWidget {
  const ScanQrScreen({super.key});

  static const noQrInImage = 'No QR code was found in this picture.';

  @override
  ConsumerState<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends ConsumerState<ScanQrScreen> {
  bool _handling = false;
  bool _done = false;
  AppFailure? _cameraFailure;
  String? _lastRejected;

  Future<void> _handle(String raw) async {
    if (_handling || _done) return;
    // The camera reports the same code many times a second.
    if (raw == _lastRejected) return;
    _handling = true;
    final parsed = ref.read(otpCodecProvider).parseUri(raw);
    switch (parsed) {
      case Err(:final failure):
        _lastRejected = raw;
        if (mounted) _showFailure(failure);
      case Ok(:final value):
        final added = await ref
            .read(authenticatorRepositoryProvider)
            .add(value);
        if (!mounted) return;
        switch (added) {
          case Ok(value: final account):
            _done = true;
            showAppSnack(context, 'Added ${account.title}');
            Navigator.of(context).pop();
          case Err(:final failure):
            _lastRejected = raw;
            _showFailure(failure);
        }
    }
    _handling = false;
  }

  void _showFailure(AppFailure f) =>
      showAppSnack(context, '${f.title}. ${f.detail ?? f.recovery}');

  Future<void> _pickImage() async {
    final picked = await ref
        .read(mediaPickerProvider)
        .pickImages(multiple: false);
    if (!mounted) return;
    switch (picked) {
      case Err(:final failure):
        _showFailure(failure);
        return;
      case Ok(:final value) when value.isEmpty:
        return; // Cancelled.
      case Ok(:final value):
        final decoded = await ref
            .read(qrScannerProvider)
            .decodeImage(value.first.path);
        if (!mounted) return;
        switch (decoded) {
          case Err(:final failure):
            _showFailure(failure);
          case Ok(value: null):
            _showFailure(
              const AppFailure(
                FailureCode.invalidOtpUri,
                detail: ScanQrScreen.noQrInImage,
              ),
            );
          case Ok(value: final String raw):
            _lastRejected = null;
            await _handle(raw);
        }
    }
  }

  void _manual() {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    unawaited(router.pushReplacement(Routes.authenticatorAdd));
  }

  @override
  Widget build(BuildContext context) {
    final capability = ref.watch(_qrCapabilityProvider);
    final cameraOk =
        (capability.value?.available ?? false) && _cameraFailure == null;
    final failure =
        _cameraFailure ??
        (capability.value?.available == false
            ? AppFailure(
                FailureCode.cameraUnavailable,
                detail: capability.value?.note,
              )
            : null);
    return SecureScope(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scan QR code'),
          actions: [
            IconButton(
              tooltip: 'Choose from gallery',
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_library_outlined),
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
                            .read(qrScannerProvider)
                            .buildPreview(
                              context,
                              onDetect: (raw) => unawaited(_handle(raw)),
                              onError: (f) =>
                                  setState(() => _cameraFailure = f),
                            ),
                        const _Viewfinder(),
                      ],
                    )
                  : FailureView(
                      failure!,
                      actions: {
                        FailureAction.pickDifferentFile: _pickImage,
                        FailureAction.retry: () => setState(() {
                          _cameraFailure = null;
                          ref.invalidate(_qrCapabilityProvider);
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
                      'Point the camera at the QR code shown when you turn on '
                      'two-step verification. Nothing is uploaded.',
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
                          onPressed: _pickImage,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Choose from gallery'),
                        ),
                        TextButton.icon(
                          onPressed: _manual,
                          icon: const Icon(Icons.keyboard_rounded),
                          label: const Text('Enter key manually'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final _qrCapabilityProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(qrScannerProvider).capability(),
);

class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 3),
          borderRadius: Radii.cardAll,
        ),
      ),
    ),
  );
}
