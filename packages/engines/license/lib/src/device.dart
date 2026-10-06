import 'dart:convert';

import 'package:crypto/crypto.dart';

/// App-specific salt for [hashDeviceId]. Changing it makes every device
/// look new to the server (and would hand out new trials): don't.
const deviceIdSalt = 'idsnap.device.v1';

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// The only device identifier that ever leaves the phone: a salted SHA-256
/// of the platform device ID, as 64 lowercase hex characters. The raw ID
/// stays on the device.
String hashDeviceId(String rawId, {String salt = deviceIdSalt}) =>
    sha256.convert(utf8.encode('$salt:$rawId')).toString();

/// Whether [value] has the shape of [hashDeviceId] output.
bool isDeviceHash(String value) => _hex64.hasMatch(value);
