import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_authenticator/src/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks for biometrics / device credential through the app's [AppLock]
/// (the system prompt offers PIN, pattern or password as a fallback).
///
/// `Ok(true)` also when the device has no biometric or credential support:
/// the caller shows secrets directly with a hint in that case (see
/// [authCapabilityProvider]). `Ok(false)` = cancelled.
///
/// With [acceptRecent], an unlock in the last few seconds (e.g. App Lock
/// just unlocked the app) counts, so the user isn't prompted twice in a row.
Future<Result<bool>> authenticateUser(
  WidgetRef ref,
  String reason, {
  bool acceptRecent = true,
}) async {
  final capability = await ref.read(authCapabilityProvider.future);
  if (!capability.available) return const Ok(true);
  final lock = ref.read(appLockProvider);
  if (acceptRecent && lock.recentlyAuthenticated()) return const Ok(true);
  return await lock.authenticate(reason);
}
