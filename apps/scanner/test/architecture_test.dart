// Documents never leave the device (ADR-0008 as amended by ADR-0012 and
// ADR-0013). Exactly two things may use the network:
//  - the Google Mobile Ads SDK, linked ONLY by engine_ads (free build);
//  - the licence client in engine_billing (paid licence build; never
//    constructed in the free build).
// IDSnap's own code makes no network calls in the free build: engine_ads
// itself contains no HTTP or socket code, only calls into the SDK. This
// test fails if any other app package gains an HTTP client, a socket, a
// network dependency or an ads SDK, and if an ad widget is used outside the
// screens the placement policy names. Opening a URL in the browser with
// url_launcher is a hand-off to another app, not a connection, and stays
// allowed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Packages allowed to contain network code of their own.
const _allowedPackages = {
  'packages/engines/billing', // HttpLicenceClient (licence server only)
  'packages/engines/license', // pure codec today; shared with the server
};

/// The only package allowed to depend on an ads SDK. It is NOT in
/// [_allowedPackages]: it may call the SDK, not open connections itself.
const _adsPackage = 'packages/engines/ads';

final _adsDependency = RegExp(
  r'^\s{2}(google_mobile_ads|gma_mediation_\w+|facebook_audience_network|'
  r'unity_ads\w*|applovin_max|ironsource\w*|appodeal\w*|startapp\w*)\s*:',
  multiLine: true,
);

/// Source files that may place an ad (ADR-0013). Everything else is a
/// forbidden area by default; the policy in
/// packages/contracts/lib/src/ad_placement.dart then decides per route.
const _adWidgetFiles = {
  // The widgets themselves.
  'packages/contracts/lib/src/ad_widgets.dart',
  // Banner + native: Home tab, Tools tab.
  'packages/features/home/lib/src/home_screen.dart',
  'packages/features/tools/lib/src/tools_screen.dart',
  // Banner: tool option forms, kits hub, conversion list, QR generator.
  'packages/features/tools/lib/src/common/tool_scaffold.dart',
  'packages/features/tools/lib/src/kits/kits_hub_screen.dart',
  'packages/features/tools/lib/src/screens/convert_screen.dart',
  'packages/features/qr/lib/src/generate_screen.dart',
  // Native + interstitial: the saved-file panel of a finished job.
  'packages/features/tools/lib/src/common/result_sheet.dart',
  // Native: QR scan history.
  'packages/features/qr/lib/src/history_screen.dart',
};

final _adWidgetUse = RegExp(
  r'\b(AdBannerSlot|AdNativeSlot)\s*\(|\bmaybeShowResultInterstitial\s*\(',
);

/// Feature folders that must never show or request an ad. (Settings may
/// only reopen the consent form: "Ad privacy choices".)
const _adFreePackages = {
  'packages/features/library', // ID Vault, folders, document viewer
  'packages/features/authenticator',
  'packages/features/notes',
  'packages/features/scan', // scanner, ID card, passport photo
  'packages/features/settings',
  'packages/features/paywall',
};

/// Network APIs nobody else may use.
final _forbidden = <String, RegExp>{
  'package:http': RegExp(r'''import\s+['"]package:http/'''),
  'package:dio': RegExp(r'''import\s+['"]package:dio/'''),
  'package:web_socket_channel': RegExp(
    r'''import\s+['"]package:web_socket_channel/''',
  ),
  'package:grpc': RegExp(r'''import\s+['"]package:grpc/'''),
  'dart:io HttpClient': RegExp(r'\bHttpClient\s*\('),
  'dart:io HttpServer': RegExp(r'\bHttpServer\s*\.'),
  'dart:io sockets': RegExp(
    r'\b(Socket|RawSocket|SecureSocket|RawSecureSocket|RawDatagramSocket|ServerSocket)\s*\.',
  ),
  'dart:io WebSocket': RegExp(r'\bWebSocket\s*\.'),
};

final _networkDependency = RegExp(
  r'^\s{2}(http|dio|web_socket_channel|grpc|firebase_\w+|sentry\w*|google_fonts)\s*:',
  multiLine: true,
);

Directory get _repo {
  var dir = Directory.current;
  while (!File('${dir.path}/melos.yaml').existsSync() &&
      !(File('${dir.path}/pubspec.yaml').existsSync() &&
          File(
            '${dir.path}/pubspec.yaml',
          ).readAsStringSync().contains('workspace:'))) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('repo root not found');
    dir = parent;
  }
  return dir;
}

/// Every app package that ships in the IDSnap app.
List<Directory> _shippedPackages(Directory repo) {
  final roots = [
    Directory('${repo.path}/apps/scanner'),
    for (final group in ['packages', 'packages/engines', 'packages/features'])
      ...Directory('${repo.path}/$group').listSync().whereType<Directory>(),
  ];
  return roots
      .where((d) => File('${d.path}/pubspec.yaml').existsSync())
      .toList();
}

String _rel(Directory repo, String path) =>
    path.substring(repo.path.length + 1).replaceAll(r'\', '/');

void main() {
  final repo = _repo;
  final packages = _shippedPackages(repo);

  test('finds the packages to check', () {
    final names = packages.map((d) => _rel(repo, d.path)).toSet();
    expect(names, containsAll(_allowedPackages));
    expect(names, contains('apps/scanner'));
    expect(names, contains('packages/features/library'));
  });

  test('only engine_ads links an ads SDK', () {
    final violations = <String>[];
    var found = false;
    for (final pkg in packages) {
      final name = _rel(repo, pkg.path);
      final pubspec = File('${pkg.path}/pubspec.yaml').readAsStringSync();
      final deps = pubspec.split(RegExp('^dev_dependencies:', multiLine: true));
      for (final m in _adsDependency.allMatches(deps.first)) {
        if (name == _adsPackage) {
          found = true;
        } else {
          violations.add('$name depends on ${m.group(1)}');
        }
      }
    }
    expect(found, isTrue, reason: 'engine_ads should depend on the ads SDK');
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('ad widgets appear only in the screens the policy names', () {
    final violations = <String>[];
    final used = <String>{};
    for (final pkg in packages) {
      final name = _rel(repo, pkg.path);
      final lib = Directory('${pkg.path}/lib');
      if (!lib.existsSync()) continue;
      for (final file in lib.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        final rel = _rel(repo, file.path);
        if (_adWidgetUse.hasMatch(source)) {
          used.add(rel);
          if (!_adWidgetFiles.contains(rel)) {
            violations.add('$rel places an ad but is not on the allowlist');
          }
        }
        if (_adFreePackages.contains(name) &&
            RegExp(
              'AdNative|AdBanner|takeNative|buildBanner|resolveBannerHeight|'
              '[sS]howInterstitial|loadInterstitial',
            ).hasMatch(source)) {
          violations.add('$rel is in an ad-free area but shows ads');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
    // The allowlist has no stale entries.
    expect(used, _adWidgetFiles);
  });

  test('no network code outside the licence client', () {
    final violations = <String>[];
    for (final pkg in packages) {
      final name = _rel(repo, pkg.path);
      if (_allowedPackages.contains(name)) continue;
      final lib = Directory('${pkg.path}/lib');
      if (!lib.existsSync()) continue;
      for (final file in lib.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        for (final MapEntry(key: what, value: pattern) in _forbidden.entries) {
          if (pattern.hasMatch(source)) {
            violations.add('${_rel(repo, file.path)} uses $what');
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('no network dependency outside the licence client', () {
    final violations = <String>[];
    for (final pkg in packages) {
      final name = _rel(repo, pkg.path);
      if (_allowedPackages.contains(name)) continue;
      final pubspec = File('${pkg.path}/pubspec.yaml').readAsStringSync();
      final deps = pubspec.split(RegExp('^dev_dependencies:', multiLine: true));
      for (final m in _networkDependency.allMatches(deps.first)) {
        violations.add('$name depends on ${m.group(1)}');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('the detector actually detects', () {
    for (final sample in [
      "import 'package:http/http.dart' as http;",
      'final c = HttpClient();',
      'await Socket.connect(host, 80);',
      'await WebSocket.connect(url);',
    ]) {
      expect(
        _forbidden.values.any((p) => p.hasMatch(sample)),
        isTrue,
        reason: sample,
      );
    }
    expect(
      _forbidden.values.any(
        (p) => p.hasMatch("import 'package:url_launcher/url_launcher.dart';"),
      ),
      isFalse,
    );
  });
}
