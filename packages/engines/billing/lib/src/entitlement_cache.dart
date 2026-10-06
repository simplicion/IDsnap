import 'dart:convert';

import 'package:engine_billing/src/billing_storage.dart';
import 'package:flutter/foundation.dart';

enum CachedKind {
  monthly,
  lifetime,

  /// The store confirmed the monthly plan is gone (kept so the UI can say
  /// "your plan ended" rather than "your trial ended").
  lapsed,
}

/// The last purchase the store confirmed and this device verified. Lets the
/// app unlock Pro offline and at cold start, before the store answers.
@immutable
class CachedEntitlement {
  const CachedEntitlement({
    required this.kind,
    required this.verifiedAt,
    this.expiresAt,
    this.willRenew = false,
  });

  final CachedKind kind;

  /// When the store last confirmed it.
  final DateTime verifiedAt;

  /// Monthly: end of the current billing period (estimated from the
  /// purchase time; the store API doesn't expose it on-device).
  final DateTime? expiresAt;
  final bool willRenew;

  Map<String, Object?> toJson() => {
    'v': 1,
    'kind': kind.name,
    'verifiedAt': verifiedAt.millisecondsSinceEpoch,
    if (expiresAt != null) 'expiresAt': expiresAt!.millisecondsSinceEpoch,
    'willRenew': willRenew,
  };

  static CachedEntitlement? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final kind = CachedKind.values.asNameMap()[json['kind']];
    final verified = json['verifiedAt'];
    final expires = json['expiresAt'];
    if (kind == null || verified is! int) return null;
    return CachedEntitlement(
      kind: kind,
      verifiedAt: DateTime.fromMillisecondsSinceEpoch(verified, isUtc: true),
      expiresAt: expires is int
          ? DateTime.fromMillisecondsSinceEpoch(expires, isUtc: true)
          : null,
      willRenew: json['willRenew'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CachedEntitlement &&
      other.kind == kind &&
      other.verifiedAt == verifiedAt &&
      other.expiresAt == expiresAt &&
      other.willRenew == willRenew;

  @override
  int get hashCode => Object.hash(kind, verifiedAt, expiresAt, willRenew);
}

/// Persists [CachedEntitlement] in [BillingStorage].
class EntitlementCacheStore {
  EntitlementCacheStore(this._storage);

  static const key = 'billing.entitlement';

  final BillingStorage _storage;

  Future<CachedEntitlement?> load() async {
    try {
      final raw = await _storage.read(key);
      return raw == null ? null : CachedEntitlement.fromJson(jsonDecode(raw));
    } on Object {
      return null;
    }
  }

  Future<void> save(CachedEntitlement? value) async {
    try {
      if (value == null) {
        await _storage.delete(key);
      } else {
        await _storage.write(key, jsonEncode(value.toJson()));
      }
    } on Object {
      // The in-memory copy still applies for this session.
    }
  }
}
