/// IDSnap licence tokens: `base64url(payloadJson).base64url(signature)`,
/// signed with Ed25519 by apps/license_server and verified offline by the
/// app, which ships only the public key. Pure Dart, no I/O
/// (docs/adr/0012-180pay-licence-server.md).
library;

export 'src/check.dart';
export 'src/codec.dart';
export 'src/device.dart';
export 'src/keys.dart';
export 'src/payload.dart';
