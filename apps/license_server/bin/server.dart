import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:engine_license/engine_license.dart';
import 'package:license_server/license_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

/// Starts the licence server. All configuration comes from environment
/// variables (see .env.example and README.md).
Future<void> main() async {
  final ServerConfig config;
  try {
    config = ServerConfig.fromEnv(Platform.environment);
  } on ConfigException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
    return;
  }

  void log(String event, Map<String, Object?> fields) => stdout.writeln(
    jsonEncode({
      'ts': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      for (final f in fields.entries)
        if (f.value != null) f.key: '${f.value}',
    }),
  );

  final store = LicenceStore.open(config.databasePath);
  final signer = await LicenceSigner.fromEncodedSeed(config.signingKey);
  final service = LicenceService(
    config: config,
    store: store,
    gateway: OneEightyPayGateway(config),
    signer: signer,
    log: log,
  );
  final server = await shelf_io.serve(
    buildHandler(service, trustProxy: config.trustProxy),
    InternetAddress.anyIPv4,
    config.port,
  );
  log('started', {
    'port': server.port,
    'checkoutMode': config.checkoutMode.name,
    // The public key is public: print it so the operator can check that
    // the app build uses the matching IDSNAP_LICENSE_PUBLIC_KEY.
    'publicKey': encodeLicenceKey(signer.publicKey),
    'devKey': isDevLicencePrivateKey(config.signingKey),
  });

  Future<void> stop() async {
    await server.close();
    store.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => unawaited(stop()));
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => unawaited(stop()));
  }
}
