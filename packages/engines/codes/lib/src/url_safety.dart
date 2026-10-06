import 'package:meta/meta.dart';

/// Reasons to be careful before opening a link from a code.
enum UrlWarning {
  malformed(
    'Unreadable link',
    'The link is not a valid web address.',
    severe: true,
  ),
  dangerousScheme(
    'Not a web page',
    'This link starts an action or opens a file instead of a web page.',
    severe: true,
  ),
  userInfo(
    'Hidden destination',
    'Text before "@" in the address is ignored. The real site is the part '
        'after it.',
    severe: true,
  ),
  punycode(
    'Look-alike address',
    'The address uses encoded international characters ("xn--") that can '
        'imitate a familiar site.',
    severe: true,
  ),
  lookalikeCharacters(
    'Look-alike characters',
    'The address contains non-Latin letters that can look like ordinary ones.',
    severe: true,
  ),
  ipAddress(
    'Numeric address',
    'The link points to a raw IP address instead of a site name.',
    severe: true,
  ),
  mismatchedText(
    'Label does not match the link',
    'The label names a different site from where the link actually goes.',
    severe: true,
  ),
  shortener(
    'Shortened link',
    'A link shortener hides the real destination until it is opened.',
  ),
  unusualPort(
    'Unusual port',
    'The address uses a non-standard port, which ordinary sites rarely do.',
  ),
  insecure(
    'Not encrypted',
    'The link uses http://, so anything you type on the page can be read '
        'by others on the network.',
  );

  const UrlWarning(this.title, this.detail, {this.severe = false});

  final String title;
  final String detail;

  /// Severe warnings suggest a deceptive link; others are cautions.
  final bool severe;
}

@immutable
class UrlSafetyReport {
  const UrlSafetyReport(this.warnings, {this.host});

  static const safe = UrlSafetyReport([]);

  final List<UrlWarning> warnings;

  /// The host the link really goes to (lower-case), when readable.
  final String? host;

  bool get isSuspicious => warnings.any((w) => w.severe);
  bool get hasWarnings => warnings.isNotEmpty;
}

/// Offline heuristics for links found in codes. Nothing is looked up.
abstract final class UrlSafety {
  /// Common link shorteners (the destination is hidden until opened).
  static const shorteners = {
    'bit.ly',
    'bitly.com',
    'bit.do',
    'buff.ly',
    'cutt.ly',
    'dlvr.it',
    'goo.gl',
    'is.gd',
    'lnkd.in',
    'ow.ly',
    'qrco.de',
    'qr.net',
    'rb.gy',
    'rebrand.ly',
    's.id',
    'short.io',
    'shorturl.at',
    't.co',
    't.ly',
    'tiny.cc',
    'tinyurl.com',
    'trib.al',
    'u.to',
    'v.gd',
    'x.co',
    'y2u.be',
    'shorte.st',
    'adf.ly',
    'soo.gd',
    'clck.ru',
    'surl.li',
    'urlz.fr',
    'wp.me',
    'amzn.to',
    'youtu.be',
    'fb.me',
    'forms.gle',
    'linktr.ee',
    'l.ead.me',
    'me-qr.com',
  };

  static final _scheme = RegExp('^([a-zA-Z][a-zA-Z0-9+.-]*):');
  static final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
  static final _numericHost = RegExp(
    r'^(0x[0-9a-f]+|\d+)(\.(0x[0-9a-f]+|\d+))*$',
  );
  static final _domainInText = RegExp(
    r'((?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24})',
  );
  static final _latin = RegExp('[a-z]');

  /// Assesses [url]. [linkText] is the label shown with the link (a
  /// bookmark title, for example) and is compared with the real host.
  static UrlSafetyReport assess(String url, {String? linkText}) {
    final trimmed = url.trim();
    final warnings = <UrlWarning>[];
    final schemeMatch = _scheme.firstMatch(trimmed);
    if (schemeMatch == null) {
      return const UrlSafetyReport([UrlWarning.malformed]);
    }
    final scheme = schemeMatch.group(1)!.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return const UrlSafetyReport([UrlWarning.dangerousScheme]);
    }
    final rest = trimmed.substring(schemeMatch.end);
    if (!rest.startsWith('//')) {
      return const UrlSafetyReport([UrlWarning.malformed]);
    }
    final afterSlashes = rest.substring(2);
    final end = afterSlashes.indexOf(RegExp('[/?#]'));
    var authority = end < 0 ? afterSlashes : afterSlashes.substring(0, end);
    // Backslashes are treated as slashes by browsers.
    final backslash = authority.indexOf(r'\');
    if (backslash >= 0) authority = authority.substring(0, backslash);

    final at = authority.lastIndexOf('@');
    if (at >= 0) {
      warnings.add(UrlWarning.userInfo);
      authority = authority.substring(at + 1);
    }

    String host;
    String? port;
    if (authority.startsWith('[')) {
      final close = authority.indexOf(']');
      host = close < 0 ? authority : authority.substring(0, close + 1);
      final after = close < 0 ? '' : authority.substring(close + 1);
      if (after.startsWith(':')) port = after.substring(1);
    } else {
      final colon = authority.lastIndexOf(':');
      host = colon < 0 ? authority : authority.substring(0, colon);
      if (colon >= 0) port = authority.substring(colon + 1);
    }
    host = host.toLowerCase();
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host.isEmpty) {
      return const UrlSafetyReport([UrlWarning.malformed]);
    }

    if (scheme == 'http') warnings.add(UrlWarning.insecure);

    if (host.startsWith('[') ||
        _ipv4.hasMatch(host) ||
        _numericHost.hasMatch(host)) {
      warnings.add(UrlWarning.ipAddress);
    }
    if (host.split('.').any((label) => label.startsWith('xn--'))) {
      warnings.add(UrlWarning.punycode);
    }
    if (host.runes.any((r) => r > 0x7F)) {
      warnings.add(UrlWarning.lookalikeCharacters);
    }
    final bare = host.startsWith('www.') ? host.substring(4) : host;
    if (shorteners.contains(bare)) warnings.add(UrlWarning.shortener);
    if (port != null && port.isNotEmpty && port != '80' && port != '443') {
      warnings.add(UrlWarning.unusualPort);
    }
    if (linkText != null && _textMismatch(linkText, bare)) {
      warnings.add(UrlWarning.mismatchedText);
    }
    return UrlSafetyReport(warnings, host: host);
  }

  static bool _textMismatch(String text, String host) {
    final lower = text.toLowerCase();
    final domains = _domainInText
        .allMatches(lower)
        .map((m) => m.group(1)!)
        .where((d) => _latin.hasMatch(d.split('.').last))
        .toList();
    if (domains.isEmpty) return false;
    for (var d in domains) {
      if (d.startsWith('www.')) d = d.substring(4);
      if (d == host || host.endsWith('.$d') || d.endsWith('.$host')) {
        return false;
      }
    }
    return true;
  }
}
