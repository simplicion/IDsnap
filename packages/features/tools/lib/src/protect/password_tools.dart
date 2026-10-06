import 'dart:math';

/// Characters for generated passwords: letters and digits that can't be
/// confused when read aloud or retyped (no 0/O, 1/l/I).
const passwordAlphabet =
    'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';

/// A random 16-character password shown as four groups (`abcd-EFGH-…`):
/// 16 × log2(56) ≈ 93 bits of entropy. Only letters, digits and dashes, so
/// it works for both PDFs and ZIPs and is easy to type on a phone.
String generatePassword({Random? random, int groups = 4, int groupSize = 4}) {
  final r = random ?? Random.secure();
  return [
    for (var g = 0; g < groups; g++)
      String.fromCharCodes([
        for (var i = 0; i < groupSize; i++)
          passwordAlphabet.codeUnitAt(r.nextInt(passwordAlphabet.length)),
      ]),
  ].join('-');
}

enum PasswordStrength {
  tooWeak('Too weak'),
  weak('Weak'),
  fair('Fair'),
  strong('Strong'),
  veryStrong('Very strong');

  const PasswordStrength(this.label);
  final String label;

  /// Fraction for the meter.
  double get fill => (index + 1) / PasswordStrength.values.length;

  /// Passwords below [fair] are not accepted for protection.
  bool get acceptable => index >= fair.index;
}

const _common = {
  'password',
  'passw0rd',
  'password1',
  '123456',
  '1234567',
  '12345678',
  '123456789',
  '1234567890',
  'qwerty',
  'qwertyuiop',
  'abc123',
  'letmein',
  'welcome',
  'iloveyou',
  'admin',
  'monkey',
  'dragon',
  'football',
  'india',
  'india123',
  'sunshine',
  'princess',
  'secret',
  '111111',
  '000000',
  'aadhaar',
  'aadhar',
  'pancard',
  'passport',
};

/// A deliberately simple, explainable strength estimate: estimated entropy
/// from length and character variety, penalised for common passwords,
/// repeats and sequences. Returns the level and one hint to improve it.
({PasswordStrength strength, String? hint}) estimatePasswordStrength(
  String password,
) {
  if (password.isEmpty) {
    return (strength: PasswordStrength.tooWeak, hint: null);
  }
  final lower = password.toLowerCase();
  if (_common.contains(lower) ||
      _common.contains(lower.replaceAll(RegExp('[^a-z0-9]'), ''))) {
    return (
      strength: PasswordStrength.tooWeak,
      hint: 'This is one of the most common passwords.',
    );
  }
  if (password.length < 8) {
    return (
      strength: PasswordStrength.tooWeak,
      hint: 'Use at least 8 characters.',
    );
  }
  var pool = 0;
  final hasLower = RegExp('[a-z]').hasMatch(password);
  final hasUpper = RegExp('[A-Z]').hasMatch(password);
  final hasDigit = RegExp('[0-9]').hasMatch(password);
  final hasSymbol = RegExp('[^A-Za-z0-9]').hasMatch(password);
  if (hasLower) pool += 26;
  if (hasUpper) pool += 26;
  if (hasDigit) pool += 10;
  if (hasSymbol) pool += 33;

  // Characters that repeat or continue a sequence add little.
  var effective = 0.0;
  for (var i = 0; i < password.length; i++) {
    final c = password.codeUnitAt(i);
    if (i > 0) {
      final prev = password.codeUnitAt(i - 1);
      if (c == prev || (c - prev).abs() == 1) {
        effective += 0.25;
        continue;
      }
    }
    effective += 1;
  }
  final bits = effective * log(pool) / ln2;
  final strength = bits < 36
      ? PasswordStrength.weak
      : bits < 50
      ? PasswordStrength.fair
      : bits < 70
      ? PasswordStrength.strong
      : PasswordStrength.veryStrong;
  String? hint;
  if (strength.index < PasswordStrength.strong.index) {
    hint = password.length < 12
        ? 'Longer is stronger: try 12 or more characters.'
        : !(hasUpper && hasDigit)
        ? 'Mix in capital letters and numbers.'
        : 'Avoid repeated characters and sequences like "abc" or "123".';
  }
  return (strength: strength, hint: hint);
}

/// Null when [password] only uses characters every unzip app handles.
String? zipPasswordProblem(String password) {
  for (final c in password.codeUnits) {
    if (c < 0x20 || c > 0x7E) {
      return 'For ZIP files, use only English letters, numbers and standard '
          'symbols so every unzip app can open it.';
    }
  }
  return null;
}
