import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/src/feedback.dart';
import 'package:docscan_design_system/src/support.dart';
import 'package:docscan_design_system/src/tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Section title with optional trailing action ("See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.x6,
      Space.x2,
      Space.x2,
    ),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: context.text.titleMedium),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

/// Rounded tinted icon used by tool tiles, file rows and empty states.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.color, this.size = 44});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.colors.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: c, size: size * 0.52),
    );
  }
}

/// Grid tile for a tool: icon, title, one-line description.
class ToolTile extends StatelessWidget {
  const ToolTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
    this.color,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;
  final String? badge;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Space.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(icon, color: color),
                const Spacer(),
                if (badge != null) Pill(badge!),
              ],
            ),
            const SizedBox(height: Space.x3),
            Text(
              title,
              style: context.text.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Space.x1),
            Text(
              subtitle,
              style: context.text.bodySmall?.copyWith(
                color: context.ds.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Small rounded label, e.g. "Offline", "Beta".
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.icon, this.color, this.background});

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.colors.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? context.colors.secondaryContainer,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          // Long labels in narrow spaces (e.g. a Wrap in a card) ellipsize
          // instead of overflowing.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Works offline" reassurance badge.
class OfflineBadge extends StatelessWidget {
  const OfflineBadge({super.key, this.label = 'Works offline'});

  final String label;

  @override
  Widget build(BuildContext context) => Pill(
    label,
    icon: Icons.cloud_off_rounded,
    color: context.ds.success,
    background: context.ds.successContainer,
  );
}

/// Explains conversion fidelity next to an action (PRD §8 fidelity labels).
class FidelityNote extends StatelessWidget {
  const FidelityNote({
    required this.label,
    required this.explanation,
    super.key,
    this.limitations = const [],
  });

  final String label;
  final String explanation;
  final List<String> limitations;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(Space.x4),
    decoration: BoxDecoration(
      color: context.ds.warningContainer.withValues(alpha: 0.6),
      borderRadius: Radii.cardAll,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: context.ds.warning, size: 20),
        const SizedBox(width: Space.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.text.titleSmall),
              const SizedBox(height: 2),
              Text(explanation, style: context.text.bodySmall),
              for (final l in limitations)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• $l',
                    style: context.text.bodySmall?.copyWith(
                      color: context.ds.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Friendly empty state with one clear next action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(Space.x8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBadge(icon, size: 72),
          const SizedBox(height: Space.x5),
          Text(
            title,
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
          if (actionLabel != null) ...[
            const SizedBox(height: Space.x6),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Recoverable error panel: title, recovery hint, retry.
/// Explains a failure — what happened, why, and the next step — with a
/// primary action button for [AppFailure.nextAction] when the screen supplies
/// a handler in [actions] (or [onRetry] for [FailureAction.retry]).
///
/// Unexpected failures also offer "Copy error details" (redacted
/// diagnostics: failure code and exception type — never paths or content).
/// Debug builds show the diagnostics inline.
class FailureView extends StatelessWidget {
  const FailureView(
    this.failure, {
    super.key,
    this.onRetry,
    this.actions = const {},
  });

  final AppFailure failure;
  final VoidCallback? onRetry;

  /// Handlers for next actions this screen can perform (e.g. runOcr opens
  /// the OCR tool, pickDifferentFile clears the input).
  final Map<FailureAction, VoidCallback> actions;

  VoidCallback? _handler(FailureAction a) =>
      a == FailureAction.retry ? actions[a] ?? onRetry : actions[a];

  @override
  Widget build(BuildContext context) {
    final next = failure.nextAction;
    final primary = next == FailureAction.none ? null : _handler(next);
    final showRetry =
        onRetry != null && next != FailureAction.retry && primary != onRetry;
    final unexpected =
        failure.code == FailureCode.unknown ||
        failure.code == FailureCode.conversionFailed;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(
              Icons.error_outline_rounded,
              color: context.colors.error,
              size: 64,
            ),
            const SizedBox(height: Space.x4),
            Semantics(
              liveRegion: true,
              child: Text(
                failure.title,
                style: context.text.titleLarge,
                textAlign: TextAlign.center,
              ),
            ),
            if (failure.detail != null) ...[
              const SizedBox(height: Space.x1),
              Text(
                failure.detail!,
                style: context.text.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: Space.x2),
            Text(
              failure.recovery,
              style: context.text.bodyMedium?.copyWith(
                color: context.ds.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.x5),
            if (primary != null)
              FilledButton(onPressed: primary, child: Text(next.label)),
            if (showRetry) ...[
              const SizedBox(height: Space.x2),
              OutlinedButton(
                onPressed: onRetry,
                child: Text(FailureAction.retry.label),
              ),
            ],
            if (unexpected) ...[
              const SizedBox(height: Space.x2),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: failure.diagnostics),
                  );
                  if (context.mounted) {
                    showAppSnack(context, 'Error details copied');
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy error details'),
              ),
            ],
            if ((unexpected ||
                    failure.nextAction == FailureAction.contactSupport) &&
                SupportContact.available) ...[
              const SizedBox(height: Space.x1),
              TextButton.icon(
                onPressed: () =>
                    SupportContact.contact(context, failure: failure),
                icon: const Icon(Icons.mail_outline_rounded, size: 18),
                label: Text(FailureAction.contactSupport.label),
              ),
            ],
            if (kDebugMode) ...[
              const SizedBox(height: Space.x3),
              SelectableText(
                failure.diagnostics,
                style: context.text.bodySmall?.copyWith(
                  color: context.ds.textSecondary,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Progress panel for long operations. Shows determinate progress only when
/// real progress is known (DESIGN: never fake progress).
class ProgressPanel extends StatelessWidget {
  const ProgressPanel({
    required this.label,
    super.key,
    this.progress,
    this.onCancel,
  });

  final String label;
  final double? progress;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.x8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
            ),
          ),
          const SizedBox(height: Space.x5),
          Text(
            label,
            style: context.text.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (progress != null) ...[
            const SizedBox(height: Space.x1),
            Text(
              '${(progress! * 100).round()}%',
              style: context.text.bodyMedium?.copyWith(
                color: context.ds.textSecondary,
              ),
            ),
          ],
          if (onCancel != null) ...[
            const SizedBox(height: Space.x5),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
          ],
        ],
      ),
    ),
  );
}

/// Icon + color for a file format. Color is always paired with the icon/label.
({IconData icon, Color color}) formatVisual(
  BuildContext context,
  DocumentFormat f,
) {
  final ds = context.ds;
  return switch (f) {
    DocumentFormat.pdf => (icon: Icons.picture_as_pdf_rounded, color: ds.pdf),
    _ when f.isImage => (icon: Icons.image_rounded, color: ds.image),
    DocumentFormat.docx => (icon: Icons.description_rounded, color: ds.text),
    DocumentFormat.xlsx ||
    DocumentFormat.csv => (icon: Icons.table_chart_rounded, color: ds.office),
    DocumentFormat.pptx => (icon: Icons.slideshow_rounded, color: ds.pdf),
    _ => (icon: Icons.article_rounded, color: ds.text),
  };
}

/// Primary call to action card (e.g. "Scan a document").
class HeroAction extends StatelessWidget {
  const HeroAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: scheme.primary,
        borderRadius: const BorderRadius.all(Radius.circular(Radii.sheet)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.x5),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: scheme.onPrimary, size: 30),
                ),
                const SizedBox(width: Space.x4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: context.text.titleLarge?.copyWith(
                          color: scheme.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: context.text.bodyMedium?.copyWith(
                          color: scheme.onPrimary.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, color: scheme.onPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
