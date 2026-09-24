import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:feature_scan/src/scan_session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Entry point of the scan flow (`/scan?source=`). Opens the camera or photo
/// picker, then hands over to the review screen.
class ScanLaunchScreen extends ConsumerStatefulWidget {
  const ScanLaunchScreen({required this.source, super.key});

  final ScanSource source;

  @override
  ConsumerState<ScanLaunchScreen> createState() => _ScanLaunchScreenState();
}

class _ScanLaunchScreenState extends ConsumerState<ScanLaunchScreen> {
  AppFailure? _failure;
  EngineCapability? _capability;
  bool _scannerUnavailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start(widget.source));
  }

  Future<void> _start(ScanSource source) async {
    setState(() {
      _failure = null;
      _scannerUnavailable = false;
    });
    final session = ref.read(scanSessionProvider.notifier);
    final draft = await ref.read(scanSessionProvider.future);
    if (!mounted) return;
    final hasPages = draft != null && !draft.isEmpty;

    if (source == ScanSource.resume) {
      _goReview(hasPages);
      return;
    }

    final Result<int> result;
    if (source == ScanSource.gallery) {
      result = await session.addFromGallery();
    } else {
      final cap = await ref.read(documentScannerProvider).capability();
      if (!mounted) return;
      setState(() => _capability = cap);
      if (!cap.available) {
        setState(() => _scannerUnavailable = true);
        return;
      }
      result = await session.addFromCamera();
    }
    if (!mounted) return;
    switch (result) {
      case Ok(:final value):
        final nowHasPages = hasPages || value > 0;
        _goReview(nowHasPages);
      case Err(:final failure):
        setState(() => _failure = failure);
    }
  }

  void _goReview(bool hasPages) {
    if (hasPages) {
      context.pushReplacement(Routes.scanReview);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_failure != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: FailureView(_failure!, onRetry: () => _start(widget.source)),
          ),
          if (widget.source == ScanSource.camera)
            TextButton.icon(
              onPressed: () => _start(ScanSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Use photos instead'),
            ),
        ],
      );
    } else if (_scannerUnavailable) {
      body = EmptyState(
        icon: Icons.document_scanner_outlined,
        title: 'Camera scanner not available',
        message:
            _capability?.note ??
            'This device does not provide a document camera. You can still '
                'import photos of your pages — edges are detected automatically.',
        actionLabel: 'Import photos',
        onAction: () => _start(ScanSource.gallery),
      );
    } else {
      final downloading = _capability?.requiresDownload ?? false;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProgressPanel(
            label: widget.source == ScanSource.gallery
                ? 'Opening your photos…'
                : 'Opening the scanner…',
          ),
          if (downloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x8),
              child: Text(
                'On first use, your phone may need to install the scanner '
                'component. After that it works offline.',
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(
                  color: context.ds.textSecondary,
                ),
              ),
            ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.home),
        ),
      ),
      body: SafeArea(child: Center(child: body)),
    );
  }
}
