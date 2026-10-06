import 'package:engine_security/engine_security.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(SecureWindow.channelName);
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('channel name matches the native hosts', () {
    // MainActivity.kt and AppDelegate.swift register this exact name.
    expect(SecureWindow.channelName, 'docscan/secure_window');
  });

  test(
    'setSecure and consumeExternalLaunch speak the native protocol',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'consumeExternalLaunch' ? true : null;
      });
      const w = SecureWindow(null, true);
      await w.setSecure(enabled: true);
      expect(await w.consumeExternalLaunch(), isTrue);
      expect(calls.map((c) => c.method), [
        'setSecure',
        'consumeExternalLaunch',
      ]);
      expect(calls.first.arguments, {'enabled': true});
    },
  );

  test('missing host implementation is harmless', () async {
    const w = SecureWindow(null, true);
    await w.setSecure(enabled: true);
    expect(await w.consumeExternalLaunch(), isFalse);
  });

  test('unsupported platforms never call the channel', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    const w = SecureWindow(null, false);
    await w.setSecure(enabled: true);
    expect(await w.consumeExternalLaunch(), isFalse);
    expect(calls, isEmpty);
  });
}
