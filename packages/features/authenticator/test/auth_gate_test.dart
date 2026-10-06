import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_authenticator/src/auth_gate.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// App Lock that just unlocked the app (like the engine right after the
/// lock gate's prompt).
class _RecentLock implements AppLock, AppLockSession {
  bool recent = true;
  int prompts = 0;

  @override
  bool get isAuthenticating => false;

  @override
  bool recentlyAuthenticated({
    Duration within = AppLockSession.defaultRecentWindow,
  }) => recent;

  @override
  Future<EngineCapability> capability() async =>
      const EngineCapability(available: true, worksOffline: true);

  @override
  Future<Result<bool>> authenticate(String reason) async {
    prompts++;
    return const Ok(true);
  }
}

void main() {
  testWidgets('a fresh App Lock unlock satisfies the reveal gate', (
    tester,
  ) async {
    final lock = _RecentLock();
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appLockProvider.overrideWithValue(lock)],
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );
    expect((await authenticateUser(ref, 'Show codes')).valueOrNull, isTrue);
    expect(lock.prompts, 0, reason: 'no double prompt after unlocking');

    // Recovery codes always ask again.
    await authenticateUser(ref, 'Show recovery codes', acceptRecent: false);
    expect(lock.prompts, 1);

    // Not recent: prompts.
    lock.recent = false;
    await authenticateUser(ref, 'Show codes');
    expect(lock.prompts, 2);
  });
}
