import 'dart:typed_data';

import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/authenticator.dart';

// Ports for the offline 2FA authenticator (PRD Module 2).

/// Small key/value store backed by the platform keystore (Android Keystore /
/// iOS Keychain). The only place authenticator secrets and recovery codes are
/// persisted. Implementations must never log keys or values.
abstract interface class SecretStore {
  /// `null` when [key] has no value.
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Every key currently stored (used to purge orphans).
  Future<Set<String>> keys();
}

/// Authenticator accounts: metadata in SQLite, secrets in a [SecretStore].
abstract interface class AuthenticatorRepository {
  /// Accounts ordered by `sortOrder`, then creation time.
  Stream<List<OtpAccount>> watchAccounts();

  /// Stores [account]'s secret in secure storage, then its metadata. The
  /// secret is validated first ([FailureCode.invalidSecretKey]).
  Future<Result<OtpAccount>> add(NewOtpAccount account);

  Future<Result<void>> rename(
    String id, {
    required String label,
    String? issuer,
  });

  /// HOTP only: advances the moving factor and returns the new counter.
  Future<Result<int>> incrementCounter(String id);

  /// Deletes the account and wipes its secret and recovery codes.
  Future<Result<void>> remove(String id);

  /// The raw shared secret ([FailureCode.secretUnavailable] if missing).
  Future<Result<Uint8List>> readSecret(OtpAccount account);

  Future<Result<List<RecoveryCode>>> readRecoveryCodes(OtpAccount account);
  Future<Result<void>> saveRecoveryCodes(
    OtpAccount account,
    List<RecoveryCode> codes,
  );
}

/// One-time password maths and `otpauth://` parsing. Pure and synchronous;
/// implemented by `engine_authenticator`.
abstract interface class OtpCodec {
  /// Decodes a Base32 secret (spaces, lowercase and missing padding are
  /// tolerated). [FailureCode.invalidSecretKey] on bad input.
  Result<Uint8List> decodeSecret(String base32);

  /// Canonical Base32 (uppercase, no spaces, no padding) or a failure.
  Result<String> normalizeSecret(String base32);

  /// Code for [counter] (RFC 4226).
  String hotp(
    Uint8List secret, {
    required int counter,
    int digits = 6,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  });

  /// Code for the time step containing [at] (RFC 6238).
  String totp(
    Uint8List secret, {
    required DateTime at,
    int period = 30,
    int digits = 6,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
  });

  /// Parses an `otpauth://totp/...` or `otpauth://hotp/...` URI.
  /// [FailureCode.invalidOtpUri] (or [FailureCode.invalidSecretKey]) on bad
  /// input.
  Result<NewOtpAccount> parseUri(String uri);
}
