import 'dart:async';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Toggles the Android secure-window flag / iOS snapshot cover; injected so
/// tests don't need a platform channel. The app passes
/// `SecureWindow().setSecure`.
typedef SecureFlagSetter = Future<void> Function({required bool enabled});

/// True when the last pause was caused by an activity IDSnap opened itself
/// (file picker, camera, share sheet). The app passes
/// `SecureWindow().consumeExternalLaunch`.
typedef ExternalLaunchProbe = Future<bool> Function();

Future<void> _noopSecure({required bool enabled}) async {}

Future<bool> _noExternalLaunch() async => false;

final Stopwatch _uptime = Stopwatch()..start();
Duration _monotonicNow() => _uptime.elapsed;

/// App Lock gate (roadmap B2). When `settings.appLock` is on:
///
/// - Cold start: nothing of the app is painted, focusable or animating until
///   the owner authenticates. The router is built underneath (offstage, with
///   tickers off) so navigation targets wait behind the lock.
/// - Background: re-locks when the app was hidden/paused for at least
///   `lockAfterMinutes` (0 = any time). `inactive` alone (notification shade,
///   permission dialogs, Face ID, split screen) never locks. Pauses caused by
///   a system prompt or by a flow IDSnap opened itself (picker, camera, share
///   sheet) get [excusedGrace] instead, so they never cause a re-lock loop.
///   Time away is the larger of a monotonic clock and the wall clock (the
///   monotonic clock can stop while the phone sleeps).
/// - Privacy: the secure flag is on app-wide, and a cover hides content while
///   the app is not in front.
///
/// This is an access gate, not encryption.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({
    required this.child,
    super.key,
    this.clock = DateTime.now,
    this.elapsed = _monotonicNow,
    this.setSecure = _noopSecure,
    this.externalLaunch = _noExternalLaunch,
  });

  /// Longest trip into a system prompt or an IDSnap-launched flow that still
  /// doesn't re-lock (a multi-page scan can take a few minutes).
  static const excusedGrace = Duration(minutes: 5);

  static const unlockReason = 'Unlock IDSnap';

  static const noScreenLockMessage =
      "Your phone no longer has a screen lock, so IDSnap can't check it's "
      'you. Continue to open IDSnap with App Lock turned off. To use App Lock '
      'again, set a screen lock, then turn it on in Settings.';

  final Widget child;

  /// Wall clock.
  final DateTime Function() clock;

  /// Monotonic time since an arbitrary origin.
  final Duration Function() elapsed;
  final SecureFlagSetter setSecure;
  final ExternalLaunchProbe externalLaunch;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

/// When and how the app left the foreground.
class _Away {
  _Away(this.mono, this.wall, {required this.excused, required this.external});

  final Duration mono;
  final DateTime wall;
  final bool excused;
  final Future<bool> external;
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  /// null until settings have loaded.
  bool? _locked;
  bool _obscured = false;
  bool _authenticating = false;
  bool _promptOnResume = false;
  bool _noScreenLock = false;
  _Away? _away;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Lock required: the setting is on, or settings couldn't be read (fail
  /// closed, but with the no-screen-lock escape hatch).
  bool _required(AsyncValue<AppSettings> s) =>
      s.hasValue ? s.value!.appLock : s.hasError;

  bool get _enabled => _required(ref.read(settingsProvider));

  bool get _promptActive =>
      _authenticating || ref.read(appLockProvider).isAuthenticating;

  bool get _inForeground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) {
      _away = null;
      if (_obscured) setState(() => _obscured = false);
      return;
    }
    switch (state) {
      case AppLifecycleState.inactive:
        // Transient (shade, dialogs, Face ID) or the iOS app-switcher
        // snapshot: cover, but never lock.
        _obscure();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _obscure();
        _away ??= _Away(
          widget.elapsed(),
          widget.clock(),
          excused: _promptActive,
          external: widget.externalLaunch(),
        );
      case AppLifecycleState.resumed:
        unawaited(_onResumed());
      case AppLifecycleState.detached:
        break;
    }
  }

  void _obscure() {
    if (!_obscured) setState(() => _obscured = true);
  }

  Future<void> _onResumed() async {
    final away = _away;
    _away = null;
    var relock = false;
    if (away != null) {
      final excused = away.excused || await away.external;
      if (!mounted) return;
      final monoGone = widget.elapsed() - away.mono;
      final wallGone = widget.clock().difference(away.wall);
      final gone = monoGone > wallGone ? monoGone : wallGone;
      var limit = Duration(
        minutes: ref.read(currentSettingsProvider).lockAfterMinutes,
      );
      if (excused && limit < LockGate.excusedGrace) {
        limit = LockGate.excusedGrace;
      }
      relock = gone >= limit;
    }
    // A newer pause may have arrived while we were waiting.
    if (!mounted || !_inForeground) return;
    final prompt = (relock || _promptOnResume) && !_noScreenLock;
    setState(() {
      _obscured = false;
      if (relock) _locked = true;
      _promptOnResume = false;
    });
    if (prompt && _locked == true) unawaited(_unlock());
  }

  Future<void> _unlock() async {
    // Re-entrancy guard: one prompt at a time (the engine also joins
    // concurrent callers onto the prompt that's on screen).
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    final lock = ref.read(appLockProvider);
    final result = await lock.authenticate(LockGate.unlockReason);
    if (!mounted) return;
    var noScreenLock = false;
    if (!result.isOk) {
      // Did the phone lose its screen lock? Then nobody can ever pass the
      // prompt, so don't lock the owner out of their data.
      final capability = await lock.capability();
      if (!mounted) return;
      noScreenLock = !capability.available;
    }
    setState(() {
      _authenticating = false;
      _away = null;
      result.fold(
        (ok) {
          if (ok) _locked = false;
        },
        (f) {
          _noScreenLock = noScreenLock;
          _error = noScreenLock
              ? LockGate.noScreenLockMessage
              : f.detail ?? '${f.title}. ${f.recovery}';
        },
      );
    });
  }

  /// Escape hatch when the device has no screen lock any more: removing it
  /// required the old screen lock, so the person here already proved they
  /// own the phone. Turns App Lock off and opens the app.
  Future<void> _continueWithoutLock() async {
    await ref
        .read(settingsProvider.notifier)
        .change((s) => s.copyWith(appLock: false));
    if (!mounted) return;
    setState(() {
      _locked = false;
      _noScreenLock = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final decided = settings.hasValue || settings.hasError;
    final required = _required(settings);

    ref.listen(currentSettingsProvider.select((s) => s.appLock), (prev, on) {
      // The initial load is handled below; react only to real toggles.
      if (_locked == null || prev == on) return;
      unawaited(widget.setSecure(enabled: on));
      // Turning the lock on from Settings must not lock you out mid-session.
      if (!on) {
        setState(() {
          _locked = false;
          _error = null;
          _noScreenLock = false;
          _obscured = false;
        });
      }
    });

    // Decide the initial state once settings have loaded.
    if (_locked == null && decided) {
      _locked = required;
      unawaited(widget.setSecure(enabled: required));
      if (required) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Prompting while not in front fails; wait for `resumed`.
          if (_inForeground) {
            unawaited(_unlock());
          } else {
            _promptOnResume = true;
          }
        });
      }
    }

    final showLock = !decided || (required && (_locked ?? true));
    return Stack(
      children: [
        // Kept mounted underneath so state survives locking; while locked it
        // isn't painted, hit-tested, focusable or animating.
        ExcludeFocus(
          excluding: showLock,
          child: TickerMode(
            enabled: !showLock,
            child: Offstage(offstage: showLock, child: widget.child),
          ),
        ),
        if (showLock)
          _LockScreen(
            loading: !decided,
            authenticating: _authenticating,
            error: _error,
            noScreenLock: _noScreenLock,
            onUnlock: _unlock,
            onContinue: _continueWithoutLock,
          )
        else if (required && _obscured)
          const _PrivacyCover(),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({
    required this.loading,
    required this.authenticating,
    required this.error,
    required this.noScreenLock,
    required this.onUnlock,
    required this.onContinue,
  });

  final bool loading;
  final bool authenticating;
  final String? error;
  final bool noScreenLock;
  final VoidCallback onUnlock;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Material(
    color: context.ds.canvas,
    child: SafeArea(
      child: loading
          ? const SizedBox.expand()
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.x8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const IconBadge(Icons.lock_rounded, size: 72),
                    const SizedBox(height: Space.x5),
                    Semantics(
                      header: true,
                      child: Text(
                        'IDSnap is locked',
                        style: context.text.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: Space.x2),
                    Text(
                      'Use your fingerprint, face or screen lock to continue.',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.ds.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: Space.x4),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error!,
                          style: context.text.bodyMedium?.copyWith(
                            color: noScreenLock
                                ? context.colors.onSurface
                                : context.colors.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.x6),
                    if (noScreenLock)
                      FilledButton(
                        onPressed: onContinue,
                        child: const Text('Continue'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: authenticating ? null : onUnlock,
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: const Text('Unlock'),
                      ),
                  ],
                ),
              ),
            ),
    ),
  );
}

/// Shown while the app isn't in front so the switcher preview is blank.
class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) => Material(
    color: context.ds.canvas,
    child: const Center(child: IconBadge(Icons.lock_rounded, size: 72)),
  );
}
