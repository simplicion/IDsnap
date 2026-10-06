import 'dart:math';

import 'package:engine_billing/src/billing_storage.dart';
import 'package:engine_license/engine_license.dart';
import 'package:flutter/services.dart';

/// The device's licence identity: a salted SHA-256 of a platform ID that
/// survives reinstalling, so a reinstall never gets a new free day. Only
/// the hash is stored or sent.
abstract interface class DeviceIdentity {
  /// 64 lowercase hex characters.
  Future<String> deviceHash();
}

/// Reads the raw ID from the native side (channel `idsnap/device_id`,
/// method `deviceId`):
///
/// - Android: `Settings.Secure.ANDROID_ID`. Survives uninstall/reinstall;
///   scoped per app signing key, user and device (factory reset changes it).
/// - iOS: a random UUID kept in the Keychain (survives reinstall), falling
///   back to `identifierForVendor`.
///
/// If the platform can't answer, a random ID is generated and kept in
/// secure storage. That fallback does NOT survive a reinstall on Android.
class PlatformDeviceIdentity implements DeviceIdentity {
  PlatformDeviceIdentity(
    this._storage, {
    MethodChannel channel = const MethodChannel(channelName),
    Random? random,
  }) : _channel = channel,
       _random = random ?? Random.secure();

  static const channelName = 'idsnap/device_id';
  static const _hashKey = 'licence.device_hash';
  static const _fallbackKey = 'licence.fallback_device_id';

  final BillingStorage _storage;
  final MethodChannel _channel;
  final Random _random;
  String? _cached;

  @override
  Future<String> deviceHash() async {
    final cached = _cached;
    if (cached != null) return cached;
    String? raw;
    try {
      raw = await _channel.invokeMethod<String>('deviceId');
    } on Object {
      raw = null;
    }
    if (raw == null || raw.trim().isEmpty || raw == '9774d56d682e549c') {
      // (That constant is the well-known ANDROID_ID of some old emulators.)
      raw = await _fallbackId();
    }
    final hash = hashDeviceId(raw.trim());
    _cached = hash;
    try {
      await _storage.write(_hashKey, hash);
    } on Object {
      // Only an optimisation for diagnostics; nothing reads it back.
    }
    return hash;
  }

  Future<String> _fallbackId() async {
    try {
      final stored = await _storage.read(_fallbackKey);
      if (stored != null && stored.isNotEmpty) return stored;
    } on Object {
      // Generate a new one below.
    }
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    try {
      await _storage.write(_fallbackKey, id);
    } on Object {
      // In memory for this session.
    }
    return id;
  }
}

/// A fixed identity, for tests and unsupported platforms.
class FixedDeviceIdentity implements DeviceIdentity {
  FixedDeviceIdentity(String rawId) : _hash = hashDeviceId(rawId);

  final String _hash;

  @override
  Future<String> deviceHash() async => _hash;
}
