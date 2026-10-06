/// In-memory sliding-window rate limiter (one process; put a shared store
/// behind this interface before running more than one instance).
class RateLimiter {
  RateLimiter({
    required this.max,
    required this.window,
    DateTime Function()? now,
    this.maxKeys = 100000,
  }) : _now = now ?? DateTime.now;

  /// Requests allowed per [window] and key.
  final int max;
  final Duration window;

  /// Memory bound: when exceeded, idle keys are dropped.
  final int maxKeys;
  final DateTime Function() _now;
  final _hits = <String, List<int>>{};

  /// Records a request for [key]. Returns null when it is allowed, or how
  /// long to wait when it is not (a refused request is not recorded).
  Duration? check(String key) {
    final now = _now().millisecondsSinceEpoch;
    final cutoff = now - window.inMilliseconds;
    final hits = _hits.putIfAbsent(key, () => [])
      ..removeWhere((t) => t <= cutoff);
    if (hits.length >= max) {
      return Duration(milliseconds: hits.first - cutoff);
    }
    hits.add(now);
    if (_hits.length > maxKeys) _prune(cutoff);
    return null;
  }

  void _prune(int cutoff) =>
      _hits.removeWhere((_, hits) => hits.isEmpty || hits.last <= cutoff);
}

/// The limits the HTTP layer applies. Defaults suit a small deployment;
/// tests pass tighter ones.
class RateLimits {
  RateLimits({
    DateTime Function()? now,
    int perIpPerMinute = 120,
    int perDevicePerMinute = 30,
    int checkoutsPerDevicePer10Min = 6,
    int newDevicesPerIpPerHour = 30,
    int webhooksPerIpPerMinute = 600,
  }) : ip = RateLimiter(
         max: perIpPerMinute,
         window: const Duration(minutes: 1),
         now: now,
       ),
       device = RateLimiter(
         max: perDevicePerMinute,
         window: const Duration(minutes: 1),
         now: now,
       ),
       checkout = RateLimiter(
         max: checkoutsPerDevicePer10Min,
         window: const Duration(minutes: 10),
         now: now,
       ),
       newDevice = RateLimiter(
         max: newDevicesPerIpPerHour,
         window: const Duration(hours: 1),
         now: now,
       ),
       webhook = RateLimiter(
         max: webhooksPerIpPerMinute,
         window: const Duration(minutes: 1),
         now: now,
       );

  /// Every `/v1` request, per client IP.
  final RateLimiter ip;

  /// Every `/v1` request that names a device, per device hash.
  final RateLimiter device;

  /// `POST /v1/checkout`, per device hash.
  final RateLimiter checkout;

  /// First-time registrations (new trials), per client IP. Generous by
  /// default: many phones share one address behind carrier NAT.
  final RateLimiter newDevice;

  /// `POST /webhooks/180-pay`, per client IP.
  final RateLimiter webhook;
}
