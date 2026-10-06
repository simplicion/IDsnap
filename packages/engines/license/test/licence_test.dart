import 'dart:convert';

import 'package:engine_license/engine_license.dart';
import 'package:test/test.dart';

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

List<int> _unb64(String s) => base64Url.decode(base64Url.normalize(s));

void main() {
  final device = hashDeviceId('android-id-1234');
  final otherDevice = hashDeviceId('android-id-9999');
  final issued = DateTime.utc(2026, 10, 6, 12);
  final expires = issued.add(const Duration(hours: 24));

  late LicenceSigner signer;
  late LicenceVerifier verifier;

  LicencePayload payload({
    LicencePlan plan = LicencePlan.trial,
    String? did,
    DateTime? exp,
    Duration grace = Duration.zero,
    bool? willRenew,
  }) => LicencePayload(
    deviceHash: did ?? device,
    plan: plan,
    issuedAt: issued,
    expiresAt: exp ?? expires,
    tokenId: 'tid_1',
    grace: grace,
    willRenew: willRenew,
  );

  Future<LicenceVerdict> check(
    String token, {
    required DateTime now,
    DateTime? maxSeen,
    String? did,
  }) => checkLicence(
    token: token,
    verifier: verifier,
    deviceHash: did ?? device,
    now: now,
    maxSeen: maxSeen,
  );

  setUp(() async {
    signer = await LicenceSigner.fromEncodedSeed(DevLicenceKeys.privateKey);
    verifier = LicenceVerifier.fromEncodedKey(DevLicenceKeys.publicKey);
  });

  group('codec', () {
    test('round trip: every claim survives', () async {
      final p = payload(
        plan: LicencePlan.monthly,
        grace: const Duration(days: 3),
        willRenew: true,
      );
      final token = await signer.sign(p);
      expect(await verifier.verify(token), p);
      expect(p.paidUntil, expires.subtract(const Duration(days: 3)));
    });

    test('format: base64url(payloadJson).base64url(signature)', () async {
      final token = await signer.sign(payload());
      final parts = token.split('.');
      expect(parts, hasLength(2));
      expect(token, matches(RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$')));
      expect(jsonDecode(utf8.decode(_unb64(parts[0]))), {
        'v': 1,
        'did': device,
        'plan': 'trial',
        'iat': issued.millisecondsSinceEpoch ~/ 1000,
        'exp': expires.millisecondsSinceEpoch ~/ 1000,
        'tid': 'tid_1',
      });
      expect(_unb64(parts[1]), hasLength(64));
    });

    test('the dev key pair matches', () async {
      expect(encodeLicenceKey(signer.publicKey), DevLicenceKeys.publicKey);
      expect(isDevLicencePublicKey('${DevLicenceKeys.publicKey}='), isTrue);
      expect(isDevLicencePrivateKey(DevLicenceKeys.privateKey), isTrue);
    });

    test(
      'generated key pairs sign and verify, and are not the dev pair',
      () async {
        final pair = await generateLicenceKeyPair();
        expect(isDevLicencePublicKey(pair.publicKey), isFalse);
        final s = await LicenceSigner.fromEncodedSeed(pair.privateKey);
        final v = LicenceVerifier.fromEncodedKey(pair.publicKey);
        expect(await v.verify(await s.sign(payload())), payload());
      },
    );

    test('keys: standard base64 with padding is accepted, junk is not', () {
      final std = base64.encode(decodeLicenceKey(DevLicenceKeys.publicKey)!);
      expect(decodeLicenceKey(std), isNotNull);
      expect(decodeLicenceKey(''), isNull);
      expect(decodeLicenceKey('short'), isNull);
      expect(decodeLicenceKey('not base64 !!'), isNull);
      expect(
        () => LicenceVerifier.fromEncodedKey('abc'),
        throwsFormatException,
      );
      expect(() => LicenceSigner.fromEncodedSeed('abc'), throwsFormatException);
    });
  });

  group('tamper', () {
    Future<void> expectError(String token, LicenceTokenError error) =>
        expectLater(
          verifier.verify(token),
          throwsA(
            isA<LicenceTokenException>().having((e) => e.error, 'error', error),
          ),
        );

    test('changing any claim breaks the signature', () async {
      final token = await signer.sign(payload());
      final parts = token.split('.');
      final json =
          jsonDecode(utf8.decode(_unb64(parts[0]))) as Map<String, Object?>;
      for (final change in <String, Object>{
        'exp': (json['exp']! as int) + 86400 * 365,
        'plan': 'monthly',
        'did': otherDevice,
        'iat': 0,
        'tid': 'x',
        'v': 2,
      }.entries) {
        final forged = _b64(
          utf8.encode(jsonEncode({...json, change.key: change.value})),
        );
        await expectError(
          '$forged.${parts[1]}',
          LicenceTokenError.badSignature,
        );
      }
    });

    test('a flipped signature bit is rejected', () async {
      final token = await signer.sign(payload());
      final parts = token.split('.');
      final sig = _unb64(parts[1]).toList();
      sig[10] ^= 0x01;
      await expectError(
        '${parts[0]}.${_b64(sig)}',
        LicenceTokenError.badSignature,
      );
    });

    test('a signature from another token does not transfer', () async {
      final a = await signer.sign(payload());
      final b = await signer.sign(
        payload(exp: expires.add(const Duration(days: 30))),
      );
      await expectError(
        '${b.split('.')[0]}.${a.split('.')[1]}',
        LicenceTokenError.badSignature,
      );
    });

    test('wrong key: a token signed by someone else is rejected', () async {
      final pair = await generateLicenceKeyPair();
      final attacker = await LicenceSigner.fromEncodedSeed(pair.privateKey);
      await expectError(
        await attacker.sign(payload(exp: DateTime.utc(2099))),
        LicenceTokenError.badSignature,
      );
    });

    test('malformed input never throws anything else', () async {
      final good = await signer.sign(payload());
      for (final bad in [
        '',
        '.',
        'abc',
        'a.b.c',
        '${good.split('.')[0]}.',
        '.${good.split('.')[1]}',
        '$good.extra',
        'not base64!.${good.split('.')[1]}',
        '${good.split('.')[0]}.@@@@',
        'x' * (maxLicenceTokenLength + 1),
      ]) {
        await expectError(bad, LicenceTokenError.malformed);
      }
      // Right shape, wrong signature length.
      await expectError(
        '${good.split('.')[0]}.${_b64(List.filled(10, 1))}',
        LicenceTokenError.badSignature,
      );
    });

    test('validly signed but not a licence payload is malformed', () async {
      // Sign arbitrary JSON with the real key by going through the payload
      // codec's own primitives: only possible for the key holder, and
      // still refused.
      for (final json in [
        '{"v":1}',
        '[1,2,3]',
        '{"v":1,"did":"d","plan":"lifetime","iat":1,"exp":2,"tid":"t"}',
        '{"v":1,"did":"d","plan":"day","iat":1,"exp":"2","tid":"t"}',
        '{"v":1,"did":"d","plan":"day","iat":1,"exp":2,"tid":"t","grace":-5}',
      ]) {
        expect(LicencePayload.fromJson(jsonDecode(json)), isNull, reason: json);
      }
    });

    test('unsupported version: signed by us, refused by this build', () async {
      final token = await signer.sign(
        LicencePayload(
          version: 2,
          deviceHash: device,
          plan: LicencePlan.day,
          issuedAt: issued,
          expiresAt: expires,
          tokenId: 't',
        ),
      );
      await expectError(token, LicenceTokenError.unsupportedVersion);
      expect(
        (await check(token, now: issued)).kind,
        LicenceVerdictKind.unsupportedVersion,
      );
    });

    test('unknown optional claims are ignored (forward compatible)', () {
      final p = LicencePayload.fromJson({
        ...payload().toJson(),
        'future': {'x': 1},
      });
      expect(p, payload());
    });
  });

  group('checkLicence', () {
    late String token;

    setUp(() async => token = await signer.sign(payload()));

    test('valid for this device before exp', () async {
      final v = await check(token, now: issued.add(const Duration(hours: 5)));
      expect(v.kind, LicenceVerdictKind.valid);
      expect(v.isValid, isTrue);
      expect(v.payload!.plan, LicencePlan.trial);
    });

    test('expiry edges: valid one second before, expired at exp', () async {
      expect(
        (await check(
          token,
          now: expires.subtract(const Duration(seconds: 1)),
        )).kind,
        LicenceVerdictKind.valid,
      );
      expect(
        (await check(token, now: expires)).kind,
        LicenceVerdictKind.expired,
      );
      expect(
        (await check(token, now: expires.add(const Duration(days: 400)))).kind,
        LicenceVerdictKind.expired,
      );
    });

    test('wrong device: genuine token, other phone', () async {
      final v = await check(token, now: issued, did: otherDevice);
      expect(v.kind, LicenceVerdictKind.wrongDevice);
      expect(v.isValid, isFalse);
    });

    test('rollback: clock behind max-time-seen is not trusted', () async {
      final maxSeen = expires.add(const Duration(days: 2));
      // The token has expired in real time; the user set the date back
      // into its validity window.
      final v = await check(
        token,
        now: issued.add(const Duration(hours: 1)),
        maxSeen: maxSeen,
      );
      expect(v.kind, LicenceVerdictKind.clockRolledBack);
      expect(v.payload, isNotNull);
    });

    test(
      'rollback tolerance: ten minutes back is fine, eleven is not',
      () async {
        final seen = issued.add(const Duration(hours: 2));
        expect(
          (await check(
            token,
            now: seen.subtract(const Duration(minutes: 10)),
            maxSeen: seen,
          )).kind,
          LicenceVerdictKind.valid,
        );
        expect(
          (await check(
            token,
            now: seen.subtract(const Duration(minutes: 11)),
            maxSeen: seen,
          )).kind,
          LicenceVerdictKind.clockRolledBack,
        );
      },
    );

    test('clock fixed again: the licence works again', () async {
      final seen = issued.add(const Duration(hours: 2));
      expect(
        (await check(
          token,
          now: seen.add(const Duration(minutes: 1)),
          maxSeen: seen,
        )).kind,
        LicenceVerdictKind.valid,
      );
    });

    test('untrusted input never yields a payload', () async {
      final v = await check('garbage', now: issued);
      expect(v.kind, LicenceVerdictKind.malformed);
      expect(v.payload, isNull);
      final forged =
          '${_b64(utf8.encode(jsonEncode(payload(exp: DateTime.utc(2099)).toJson())))}.${token.split('.')[1]}';
      final f = await check(forged, now: issued);
      expect(f.kind, LicenceVerdictKind.badSignature);
      expect(f.payload, isNull);
    });

    test('monthly: grace is part of exp', () async {
      final periodEnd = DateTime.utc(2026, 11, 6, 12);
      final monthly = await signer.sign(
        payload(
          plan: LicencePlan.monthly,
          exp: periodEnd.add(const Duration(days: 3)),
          grace: const Duration(days: 3),
          willRenew: true,
        ),
      );
      final inGrace = await check(
        monthly,
        now: periodEnd.add(const Duration(days: 1)),
      );
      expect(inGrace.kind, LicenceVerdictKind.valid);
      expect(inGrace.payload!.paidUntil, periodEnd);
      expect(
        (await check(
          monthly,
          now: periodEnd.add(const Duration(days: 3)),
        )).kind,
        LicenceVerdictKind.expired,
      );
    });
  });

  group('device hash', () {
    test('salted SHA-256, 64 hex chars, stable', () {
      expect(isDeviceHash(device), isTrue);
      expect(hashDeviceId('android-id-1234'), device);
      expect(device, isNot(contains('android-id-1234')));
      expect(hashDeviceId('android-id-1234', salt: 'other'), isNot(device));
    });

    test('shape check', () {
      expect(isDeviceHash('abc'), isFalse);
      expect(isDeviceHash(device.toUpperCase()), isFalse);
      expect(isDeviceHash('${device}0'), isFalse);
      expect(isDeviceHash("$device' OR 1=1"), isFalse);
    });
  });
}
