import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/common/job.dart';
import 'package:feature_tools/src/common/result_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Standard tool layout: header with description + offline badge, a
/// scrollable form, and a sticky primary button. While the tool's job runs
/// or finishes, the form is replaced by progress / error / result panels.
class ToolScaffold extends ConsumerWidget {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobProvider(jobKey));
    void reset() => ref.read(jobProvider(jobKey).notifier).reset();

    final body = switch (job) {
      JobIdle() => _Form(description: description, children: children),
      JobRunning(:final progress, :final label) => ProgressPanel(
        label: label,
        progress: progress,
      ),
      JobFailed(:final failure) => FailureView(failure, onRetry: reset),
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
        bottomNavigationBar: job is JobIdle && primaryLabel != null
            ? SafeArea(
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
