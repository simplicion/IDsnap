import 'dart:math' as math;
import 'dart:typed_data';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_authenticator/src/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Seconds before rollover when the ring turns to the error colour.
const warningSeconds = 5;

/// Remaining time in the current TOTP step, synced to wall-clock boundaries
/// (steps start at multiples of [period] seconds since the Unix epoch).
({double fraction, int seconds}) remainingInStep(DateTime now, int period) {
  final periodMs = period * 1000;
  final into = now.millisecondsSinceEpoch % periodMs;
  final leftMs = periodMs - into;
  return (fraction: leftMs / periodMs, seconds: (leftMs / 1000).ceil());
}

/// Circular countdown for one TOTP period.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    required this.fraction,
    required this.seconds,
    super.key,
    this.size = 32,
  });

  /// Remaining fraction of the step, 0..1.
  final double fraction;
  final int seconds;
  final double size;

  bool get warning => seconds <= warningSeconds;

  @override
  Widget build(BuildContext context) {
    final color = warning ? context.colors.error : context.colors.primary;
    return Semantics(
      label: '$seconds seconds left',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: RingPainter(
            fraction: fraction,
            color: color,
            track: context.ds.border,
          ),
          child: Center(
            child: Text(
              '$seconds',
              style: context.text.labelSmall?.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RingPainter extends CustomPainter {
  const RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0, 1),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

/// One account row: issuer/label, current code, countdown ring (TOTP) or a
/// "next code" button (HOTP).
class AccountTile extends ConsumerWidget {
  const AccountTile({
    required this.account,
    required this.now,
    required this.revealed,
    required this.onCopy,
    required this.onReveal,
    required this.onOpen,
    super.key,
  });

  final OtpAccount account;
  final ValueNotifier<DateTime> now;
  final bool revealed;
  final ValueChanged<String> onCopy;
  final VoidCallback onReveal;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secret = ref.watch(otpSecretProvider(account));
    final codec = ref.watch(otpCodecProvider);
    final hidden = '•' * account.digits;
    return secret.when(
      loading: () => _frame(context, code: groupCode(hidden), trailing: null),
      error: (e, _) => _broken(
        context,
        const AppFailure(
          FailureCode.unknown,
          heading: "Code couldn't be shown",
          message: 'Close and reopen Authenticator to try again.',
        ),
      ),
      data: (result) => result.fold(
        (bytes) => ValueListenableBuilder<DateTime>(
          valueListenable: now,
          builder: (context, at, _) {
            final code = revealed ? _code(codec, bytes, at) : hidden;
            return _frame(
              context,
              code: groupCode(code),
              onTap: revealed ? () => onCopy(code) : onReveal,
              trailing: account.type == OtpType.totp
                  ? Builder(
                      builder: (context) {
                        final r = remainingInStep(at, account.period);
                        return CountdownRing(
                          fraction: r.fraction,
                          seconds: r.seconds,
                        );
                      },
                    )
                  : _NextCodeButton(account: account, enabled: revealed),
            );
          },
        ),
        (failure) => _broken(context, failure),
      ),
    );
  }

  String _code(OtpCodec codec, Uint8List bytes, DateTime at) =>
      account.type == OtpType.totp
      ? codec.totp(
          bytes,
          at: at,
          period: account.period,
          digits: account.digits,
          algorithm: account.algorithm,
        )
      : codec.hotp(
          bytes,
          counter: account.counter,
          digits: account.digits,
          algorithm: account.algorithm,
        );

  Widget _frame(
    BuildContext context, {
    required String code,
    required Widget? trailing,
    VoidCallback? onTap,
  }) {
    final subtitle = account.subtitle;
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.x1,
      ),
      child: InkWell(
        borderRadius: Radii.cardAll,
        onTap: onTap,
        onLongPress: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.x4,
            Space.x3,
            Space.x1,
            Space.x3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.title,
                      style: context.text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: context.text.bodySmall?.copyWith(
                          color: context.ds.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: Space.x1),
                    Semantics(
                      label: revealed ? null : 'Code hidden',
                      child: Text(
                        code,
                        key: ValueKey('code-${account.id}'),
                        style: context.text.headlineSmall?.copyWith(
                          color: context.colors.primary,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
              IconButton(
                tooltip: 'Account options',
                onPressed: onOpen,
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _broken(BuildContext context, AppFailure failure) => Card(
    margin: const EdgeInsets.symmetric(
      horizontal: Space.gutter,
      vertical: Space.x1,
    ),
    child: ListTile(
      leading: Icon(Icons.key_off_rounded, color: context.colors.error),
      title: Text(account.title),
      subtitle: Text('${failure.title}. ${failure.recovery}'),
      trailing: IconButton(
        tooltip: 'Account options',
        onPressed: onOpen,
        icon: const Icon(Icons.more_vert_rounded),
      ),
      onTap: onOpen,
    ),
  );
}

class _NextCodeButton extends ConsumerStatefulWidget {
  const _NextCodeButton({required this.account, required this.enabled});

  final OtpAccount account;
  final bool enabled;

  @override
  ConsumerState<_NextCodeButton> createState() => _NextCodeButtonState();
}

class _NextCodeButtonState extends ConsumerState<_NextCodeButton> {
  bool _busy = false;

  Future<void> _next() async {
    setState(() => _busy = true);
    final r = await ref
        .read(authenticatorRepositoryProvider)
        .incrementCounter(widget.account.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r case Err(:final failure)) showFailureSnack(context, failure);
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Next code',
    onPressed: widget.enabled && !_busy ? _next : null,
    icon: const Icon(Icons.refresh_rounded),
  );
}
