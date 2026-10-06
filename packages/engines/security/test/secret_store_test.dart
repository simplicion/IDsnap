import 'package:engine_security/engine_security.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('read, write, delete and list keys', () async {
    FlutterSecureStorage.setMockInitialValues({'existing': 'v'});
    final store = SecureStorageSecretStore();
    expect(await store.read('existing'), 'v');
    expect(await store.read('missing'), isNull);
    await store.write('otp.a', 'SECRET');
    expect(await store.read('otp.a'), 'SECRET');
    expect(await store.keys(), {'existing', 'otp.a'});
    await store.delete('otp.a');
    expect(await store.keys(), {'existing'});
  });

  test('keychain items stay on this device and errors never wipe data', () {
    expect(
      SecureStorageSecretStore.ios.accessibility,
      KeychainAccessibility.first_unlock_this_device,
    );
    expect(SecureStorageSecretStore.ios.synchronizable, isFalse);
    expect(SecureStorageSecretStore.android.toMap()['resetOnError'], 'false');
  });
}
