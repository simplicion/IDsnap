import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_scan/src/preview_cache.dart';
import 'package:feature_scan/src/scan_session_controller.dart';
import 'package:feature_scan/src/widgets/quad_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Manual corner adjustment with auto-detect, full-page and reset (FR-02).
class CropScreen extends ConsumerStatefulWidget {
  const CropScreen({required this.pageId, super.key});

  final String pageId;

  @override
  ConsumerState<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends ConsumerState<CropScreen> {
  Future<(Uint8List, Size)?>? _source;
  Quad? _quad;
  Quad? _initial;
  bool _detecting = false;

  ScanPage? get _page => ref
      .read(scanSessionProvider)
      .value
      ?.pages
      .where((p) => p.id == widget.pageId)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    final page = _page;
    if (page != null) {
      _initial = page.edits.quad ?? Quad.full;
      _quad = _initial;
      _source = _load(page.originalPath);
    }
  }

  Future<(Uint8List, Size)?> _load(String path) async {
    final bytes = await ref.read(previewCacheProvider).cropSource(path);
    if (bytes == null) return null;
    return (bytes, await decodeImageSize(bytes));
  }

  Future<void> _autoDetect() async {
    final page = _page;
    if (page == null) return;
    setState(() => _detecting = true);
    final Result<DetectedQuad> result;
    try {
      final bytes = await ref.read(fileStoreProvider).read(page.originalPath);
      result = await ref.read(imageProcessorProvider).detectDocument(bytes);
    } on Object catch (e) {
      if (mounted) {
        setState(() => _detecting = false);
        showFailureSnack(
          context,
          AppFailure(FailureCode.corruptFile, cause: e),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _detecting = false);
    switch (result) {
      case Ok(:final value):
        setState(() => _quad = value.quad);
        if (!value.isConfident) {
          showAppSnack(
            context,
            'The page edges were hard to find. Check the corners.',
          );
        }
      case Err():
        showAppSnack(
          context,
          "Couldn't find the page edges. Drag the corners instead.",
        );
    }
  }

  Future<void> _done() async {
    final quad = _quad;
    if (quad == null) return;
    await ref.read(scanSessionProvider.notifier).setQuad(widget.pageId, quad);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final quad = _quad;
    final problem = quad == null ? null : validateQuad(quad);
    return Scaffold(
      backgroundColor: const Color(0xFF0E1013),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1013),
        foregroundColor: Colors.white,
        title: const Text('Adjust corners'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.x3),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: quad == null || problem != null ? null : _done,
              child: const Text('Done'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<(Uint8List, Size)?>(
                future: _source,
                builder: (context, snap) {
                  if (_source == null) {
                    return const FailureView(
                      AppFailure(
                        FailureCode.notFound,
                        detail: 'This page was removed.',
                      ),
                    );
                  }
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snap.data;
                  if (data == null || quad == null) {
                    return const FailureView(
                      AppFailure(FailureCode.corruptFile),
                    );
                  }
                  return QuadEditor(
                    image: data.$1,
                    imageSize: data.$2,
                    quad: quad,
                    onChanged: (q) => setState(() => _quad = q),
                  );
                },
              ),
            ),
            AnimatedSwitcher(
              duration: Motion.fast,
              child: problem == null
                  ? const SizedBox(height: Space.x2)
                  : Padding(
                      key: const ValueKey('problem'),
                      padding: const EdgeInsets.fromLTRB(
                        Space.gutter,
                        Space.x2,
                        Space.gutter,
                        0,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            color: context.colors.error,
                            size: 20,
                          ),
                          const SizedBox(width: Space.x2),
                          Expanded(
                            child: Text(
                              problem,
                              style: context.text.bodyMedium?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.x3),
              child: Row(
                children: [
                  Expanded(
                    child: _ToolButton(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Auto detect',
                      busy: _detecting,
                      onTap: _detecting ? null : _autoDetect,
                    ),
                  ),
                  Expanded(
                    child: _ToolButton(
                      icon: Icons.fullscreen_rounded,
                      label: 'Full page',
                      onTap: () => setState(() => _quad = Quad.full),
                    ),
                  ),
                  Expanded(
                    child: _ToolButton(
                      icon: Icons.restart_alt_rounded,
                      label: 'Reset',
                      onTap: () => setState(() => _quad = _initial),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: Radii.buttonAll,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 24,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}
