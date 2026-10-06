import 'package:feature_authenticator/src/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps Android `FLAG_SECURE` on (no screenshots, blank app-switcher
/// thumbnail) while [child] is on screen. "On screen" follows [TickerMode],
/// which go_router and Navigator turn off for inactive tabs and covered
/// routes, so switching to another tab drops the flag again.
class SecureScope extends ConsumerStatefulWidget {
  const SecureScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<SecureScope> createState() => _SecureScopeState();
}

class _SecureScopeState extends ConsumerState<SecureScope> {
  SecureFlagController? _controller;
  bool _holding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= ref.read(secureFlagControllerProvider);
    _update(active: TickerMode.valuesOf(context).enabled);
  }

  void _update({required bool active}) {
    if (active == _holding) return;
    _holding = active;
    if (active) {
      _controller!.acquire();
    } else {
      _controller!.release();
    }
  }

  @override
  void dispose() {
    if (_holding) _controller!.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
