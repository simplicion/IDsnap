import 'package:engine_codes/engine_codes.dart';
import 'package:test/test.dart';

List<UrlWarning> warn(String url, {String? text}) =>
    UrlSafety.assess(url, linkText: text).warnings;

void main() {
  test('ordinary https link has no warnings', () {
    final r = UrlSafety.assess('https://www.example.com/a?b=c#d');
    expect(r.warnings, isEmpty);
    expect(r.isSuspicious, isFalse);
    expect(r.host, 'www.example.com');
  });

  test('http is a caution, not severe', () {
    expect(warn('http://example.com'), [UrlWarning.insecure]);
    expect(UrlSafety.assess('http://example.com').isSuspicious, isFalse);
  });

  test('punycode hosts', () {
    expect(warn('https://xn--pypal-4ve.com/'), contains(UrlWarning.punycode));
    expect(UrlSafety.assess('https://xn--pypal-4ve.com').isSuspicious, isTrue);
  });

  test('non-Latin look-alike characters', () {
    // Cyrillic "а" in place of Latin "a".
    expect(
      warn('https://pаypal.com/login'),
      contains(UrlWarning.lookalikeCharacters),
    );
  });

  test('IP address hosts (v4, v6, numeric forms)', () {
    expect(warn('http://192.168.1.10/admin'), contains(UrlWarning.ipAddress));
    expect(warn('https://[2001:db8::1]:8443/'), contains(UrlWarning.ipAddress));
    expect(
      warn('https://[2001:db8::1]:8443/'),
      contains(UrlWarning.unusualPort),
    );
    expect(warn('http://3232235777/'), contains(UrlWarning.ipAddress));
    expect(warn('http://0x7f.1/'), contains(UrlWarning.ipAddress));
  });

  test('URL shorteners', () {
    expect(warn('https://bit.ly/3abc'), [UrlWarning.shortener]);
    expect(warn('https://www.tinyurl.com/x'), [UrlWarning.shortener]);
    expect(warn('https://notbit.ly.example.com'), isEmpty);
  });

  test('user-info trick hides the real host', () {
    final r = UrlSafety.assess('https://mybank.com@evil.example/login');
    expect(r.warnings, contains(UrlWarning.userInfo));
    expect(r.host, 'evil.example');
  });

  test('mismatched link text', () {
    expect(
      warn('https://evil.example/x', text: 'Sign in at mybank.com'),
      contains(UrlWarning.mismatchedText),
    );
    expect(warn('https://login.mybank.com/x', text: 'mybank.com'), isEmpty);
    expect(warn('https://mybank.com/x', text: 'www.mybank.com'), isEmpty);
    expect(warn('https://a.example/x', text: 'Our menu'), isEmpty);
  });

  test('non-web schemes and malformed links', () {
    expect(warn('javascript:alert(1)'), [UrlWarning.dangerousScheme]);
    expect(warn('intent://scan/#Intent;end'), [UrlWarning.dangerousScheme]);
    expect(warn('data:text/html,hi'), [UrlWarning.dangerousScheme]);
    expect(warn('file:///etc/passwd'), [UrlWarning.dangerousScheme]);
    expect(warn('example.com'), [UrlWarning.malformed]);
    expect(warn('https:example.com'), [UrlWarning.malformed]);
    expect(warn('https://'), [UrlWarning.malformed]);
    expect(warn(''), [UrlWarning.malformed]);
  });

  test('backslash authority tricks resolve to the real host', () {
    final r = UrlSafety.assess(r'https://evil.example\@good.com/');
    expect(r.host, 'evil.example');
  });

  test('parsed links carry their report', () {
    final u = CodeParser.parse('https://bit.ly/x') as UrlContent;
    expect(u.safety.warnings, [UrlWarning.shortener]);
    expect(u.canOpen, isTrue);
  });

  test('every warning has user-facing text', () {
    for (final w in UrlWarning.values) {
      expect(w.title, isNotEmpty);
      expect(w.detail, isNotEmpty);
    }
  });
}
