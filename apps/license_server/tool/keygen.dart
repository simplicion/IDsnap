import 'dart:io';

import 'package:engine_license/engine_license.dart';

/// Prints a fresh Ed25519 licence key pair.
///
///     dart run tool/keygen.dart
///
/// LICENSE_SIGNING_KEY is the server's secret (environment variable only:
/// never commit it, never put it in the app). IDSNAP_LICENSE_PUBLIC_KEY is
/// public and goes into the app build with --dart-define.
Future<void> main() async {
  final pair = await generateLicenceKeyPair();
  stdout
    ..writeln("# Server secret. Store it in your host's secret manager.")
    ..writeln('LICENSE_SIGNING_KEY=${pair.privateKey}')
    ..writeln()
    ..writeln('# Public. Pass it to every release build of the app:')
    ..writeln(
      '#   flutter build apk --release '
      '--dart-define=IDSNAP_LICENSE_PUBLIC_KEY=${pair.publicKey} '
      '--dart-define=IDSNAP_LICENSE_URL=https://<your server>',
    )
    ..writeln('IDSNAP_LICENSE_PUBLIC_KEY=${pair.publicKey}');
}
