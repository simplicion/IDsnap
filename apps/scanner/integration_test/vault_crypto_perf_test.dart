import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:docscan_domain/docscan_domain.dart';
import 'package:engine_security/engine_security.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// On-device throughput of vault file encryption (ADR-0010): a 50 MB file
/// must encrypt and decrypt in a few seconds on a mid-range phone, in a
/// background isolate, with the platform AES-GCM.
///
/// Run: `flutter test integration_test/vault_crypto_perf_test.dart -d <id>`
/// (use `--profile` or a release-like build for meaningful numbers).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('50 MB encrypt + decrypt', (tester) async {
    const size = 50 * 1024 * 1024;
    final dir = await (await getTemporaryDirectory()).createTemp('perf');
    addTearDown(() => dir.delete(recursive: true));
    final plain = File('${dir.path}/plain.bin');
    final random = Random(1);
    final block = Uint8List.fromList(
      List.generate(1024 * 1024, (_) => random.nextInt(256)),
    );
    final sink = plain.openWrite();
    for (var i = 0; i < size ~/ block.length; i++) {
      sink.add(block);
    }
    await sink.close();

    final cipher = const AesGcmVaultCrypto().fileCipher(
      VaultKey(id: 1, bytes: Uint8List.fromList(List.generate(32, (i) => i))),
    );
    final sealed = '${dir.path}/sealed.bin';
    final opened = '${dir.path}/opened.bin';

    final enc = Stopwatch()..start();
    await cipher.encryptFile(plain.path, sealed);
    enc.stop();
    final dec = Stopwatch()..start();
    await cipher.decryptFile(sealed, opened);
    dec.stop();

    String rate(Stopwatch s) =>
        '${(50 / (s.elapsedMilliseconds / 1000)).toStringAsFixed(1)} MB/s';
    // Printed for the release checklist.
    // ignore: avoid_print
    print(
      'vault crypto 50 MB: encrypt ${enc.elapsedMilliseconds} ms '
      '(${rate(enc)}), decrypt ${dec.elapsedMilliseconds} ms (${rate(dec)})',
    );
    expect(File(opened).lengthSync(), size);
    expect(
      await File(opened).openRead(0, 4096).first,
      await plain.openRead(0, 4096).first,
    );
    // Target: a few seconds. Fail loudly if the native path isn't in use.
    expect(enc.elapsed, lessThan(const Duration(seconds: 15)));
    expect(dec.elapsed, lessThan(const Duration(seconds: 15)));
  });
}
