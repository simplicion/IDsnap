import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/result_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Standard tool layout: header with description + offline badge, a
/// scrollable form, and a sticky primary button. While the tool's job runs
/// or finishes, the form is replaced by progress / error / result panels.
class ToolScaffold extends ConsumerStatefulWidget {
  const ToolScaffold({
    required this.jobKey,
    required this.title,
    required this.description,
    required this.children,
    super.key,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
    this.doneSummary,
    this.actions,
    this.failureActions = const {},
    this.showSaveFolder = true,
  });

  final String jobKey;
  final String title;
  final String description;
  final List<Widget> children;
  final String? primaryLabel;
  final IconData? primaryIcon;

  /// Null disables the primary button.
  final VoidCallback? onPrimary;
  final Widget Function(List<Document> documents)? doneSummary;
  final List<Widget>? actions;

  /// Screen-specific handlers for failure next-actions; merged over the
  /// defaults (back to the form for file/quality/page issues, open the OCR
  /// tool for scanned PDFs, open Settings for storage).
  final Map<FailureAction, VoidCallback> failureActions;

  /// Shows the "Save to" folder control at the end of the form. Results
  /// are committed into that folder by [JobController.run].
  final bool showSaveFolder;

  @override
  ConsumerState<ToolScaffold> createState() => _ToolScaffoldState();
}

class _ToolScaffoldState extends ConsumerState<ToolScaffold> {
  String get jobKey => widget.jobKey;
  String get title => widget.title;
  String get description => widget.description;
  List<Widget> get children => widget.children;
  String? get primaryLabel => widget.primaryLabel;
  IconData? get primaryIcon => widget.primaryIcon;
  VoidCallback? get onPrimary => widget.onPrimary;
  Widget Function(List<Document> documents)? get doneSummary =>
      widget.doneSummary;
  List<Widget>? get actions => widget.actions;
  Map<FailureAction, VoidCallback> get failureActions => widget.failureActions;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSaveFolder());
  }

  /// Default destination: the folder of the document the tool was opened
  /// with (`?doc=`, e.g. from the viewer), else the last choice.
  Future<void> _startSaveFolder() async {
    if (!mounted) return;
    String? docId;
    try {
      docId = GoRouterState.of(context).uri.queryParameters['doc'];
    } on Object {
      docId = null; // No router (tests, previews).
    }
    String? startedFrom;
    if (docId != null) {
      try {
        startedFrom = (await ref.read(
          documentByIdProvider(docId).future,
        ))?.folderId;
      } on Object {
        startedFrom = null;
      }
    }
    if (!mounted) return;
    ref
        .read(saveFolderProvider(toolSaveFlow(jobKey)).notifier)
        .start(startedFrom);
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(jobProvider(jobKey));
    void reset() => ref.read(jobProvider(jobKey).notifier).reset();

    final body = switch (job) {
      JobIdle() => _Form(
        description: description,
        children: [
          ...children,
          if (widget.showSaveFolder)
            SaveFolderField(flow: toolSaveFlow(jobKey)),
        ],
      ),
      JobRunning(:final progress, :final label) => ProgressPanel(
        label: label,
        progress: progress,
      ),
      JobFailed(:final failure) => FailureView(
        failure,
        onRetry: reset,
        actions: {
          FailureAction.pickDifferentFile: reset,
          FailureAction.useFewerPages: reset,
          FailureAction.lowerQuality: reset,
          FailureAction.changeLanguage: reset,
          FailureAction.adjustCorners: reset,
          FailureAction.runOcr: () {
            reset();
            unawaited(context.push(Routes.tool(ToolId.ocr)));
          },
          FailureAction.freeStorage: () => context.go(Routes.settings),
          ...failureActions,
        },
      ),
      JobNotice(:final message) => _Notice(message: message, onBack: reset),
      JobDone(:final documents) => ResultSheet(
        documents: documents,
        summary: doneSummary?.call(documents),
        onStartOver: reset,
      ),
    };

    return PopScope(
      canPop: job is! JobRunning,
      child: Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: AnimatedSwitcher(duration: Motion.medium, child: body),
        // While the user is choosing options only (never while a job runs
        // or on its result): the main button, and under it, well apart,
        // the ad banner on the tools the placement policy allows
        // (ADR-0013; empty everywhere else).
        bottomNavigationBar: job is JobIdle
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (primaryLabel != null)
                    SafeArea(
                      minimum: const EdgeInsets.fromLTRB(
                        Space.gutter,
                        Space.x2,
                        Space.gutter,
                        Space.x3,
                      ),
                      child: FilledButton.icon(
                        onPressed: onPrimary,
                        icon: Icon(primaryIcon ?? Icons.check_rounded),
                        label: Text(primaryLabel!),
                      ),
                    ),
                  AdBannerSlot(
                    gapAbove: primaryLabel == null
                        ? 0
                        : AdPlacementPolicy.bannerButtonGap,
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.description, required this.children});

  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.x2,
      Space.gutter,
      Space.x8,
    ),
    children: [
      Text(
        description,
        style: context.text.bodyLarge?.copyWith(
          color: context.ds.textSecondary,
        ),
      ),
      const SizedBox(height: Space.x3),
      const Align(alignment: Alignment.centerLeft, child: OfflineBadge()),
      const SizedBox(height: Space.x5),
      for (final c in children) ...[c, const SizedBox(height: Space.x5)],
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(Space.x8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const IconBadge(Icons.info_outline_rounded, size: 72),
          const SizedBox(height: Space.x5),
          Text(
            'Nothing to save',
            style: context.text.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.x2),
          Text(
            message,
            style: context.text.bodyMedium?.copyWith(
              color: context.ds.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.x6),
          OutlinedButton(
            onPressed: onBack,
            child: const Text('Back to options'),
          ),
        ],
      ),
    ),
  );
}

/// Titled group of choice chips.
class ChoiceGroup<T> extends StatelessWidget {
  const ChoiceGroup({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    super.key,
    this.hint,
  });

  final String label;
  final String? hint;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: context.text.titleSmall),
      if (hint != null)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            hint!,
            style: context.text.bodySmall?.copyWith(
              color: context.ds.textSecondary,
            ),
          ),
        ),
      const SizedBox(height: Space.x2),
      Wrap(
        spacing: Space.x2,
        runSpacing: Space.x2,
        children: [
          for (final v in values)
            ChoiceChip(
              label: Text(labelOf(v)),
              selected: v == selected,
              onSelected: (_) => onSelected(v),
            ),
        ],
      ),
    ],
  );
}

/// File name field used by tools that produce one document.
class OutputNameField extends StatelessWidget {
  const OutputNameField({required this.controller, super.key});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('File name', style: context.text.titleSmall),
      const SizedBox(height: Space.x2),
      TextField(
        controller: controller,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.edit_outlined),
        ),
      ),
    ],
  );
}
