import 'dart:io';

import 'package:docscan_contracts/docscan_contracts.dart';
import 'package:docscan_core/docscan_core.dart';
import 'package:engine_codes/engine_codes.dart';
import 'package:feature_qr/feature_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

Future<void> scan(WidgetTester tester, Harness h, ScannedCode code) async {
  h.scanner.detect(code);
  await settle(tester);
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder.first);
  await tester.tap(finder.first);
  await settle(tester);
}

void main() {
  group('scanning', () {
    testWidgets('a Wi-Fi scan opens its result with the right actions', (
      tester,
    ) async {
      final h = Harness();
      await h.pump(tester);
      expect(find.text('Scan QR / barcode'), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-preview')), findsOneWidget);

      await scan(tester, h, wifiCode);
      expect(find.text('Wi-Fi network'), findsOneWidget);
      expect(find.text('HomeNet'), findsWidgets);
      expect(find.text('Copy password'), findsOneWidget);
      expect(find.text('Copy network name'), findsOneWidget);
      expect(find.text(CodeResultScreen.wifiJoinNote), findsOneWidget);
      // The password stays hidden until revealed.
      expect(find.text('hunter22'), findsNothing);
      await tester.tap(find.byTooltip('Show Password'));
      await settle(tester);
      expect(find.text('hunter22'), findsOneWidget);

      await tapText(tester, 'Copy password');
      expect(h.actions.copied, ['hunter22']);
      expect(h.scanner.controller!.paused.value, isTrue);
    });

    testWidgets('returning resumes the camera and ignores the same code '
        'for a moment', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await scan(tester, h, textCode);
      expect(find.text('Copy text'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      expect(h.scanner.controller!.paused.value, isFalse);
      await scan(tester, h, textCode);
      expect(find.text('Copy text'), findsNothing);
      await scan(tester, h, wifiCode);
      expect(find.text('Wi-Fi network'), findsOneWidget);
    });

    testWidgets('torch toggle drives the scanner controller', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await tester.tap(find.byTooltip('Turn on flashlight'));
      await settle(tester);
      expect(h.scanner.controller!.torch.value, isTrue);
      expect(find.byTooltip('Turn off flashlight'), findsOneWidget);
      h.scanner.controller!.torchAvailable.value = false;
      await settle(tester);
      expect(find.byTooltip('Turn off flashlight'), findsNothing);
    });

    testWidgets('without a camera the picture path is offered', (tester) async {
      final h = Harness(
        scanner: FakeCodeScanner(available: false, imageCodes: [textCode]),
      );
      await h.pump(tester);
      expect(find.byKey(const ValueKey('fake-preview')), findsNothing);
      await tapText(tester, 'Gallery');
      expect(find.text('Copy text'), findsOneWidget);
    });

    testWidgets('a picture with several codes lists every one', (tester) async {
      final h = Harness(
        scanner: FakeCodeScanner(
          imageCodes: const [
            textCode,
            ScannedCode(raw: '9780306406157', symbology: CodeSymbology.ean13),
            ScannedCode(
              raw: 'https://example.com',
              symbology: CodeSymbology.qr,
            ),
          ],
        ),
      );
      await h.pump(tester);
      await tapText(tester, 'Gallery');
      expect(h.scanner.decodedPaths, ['/tmp/codes.png']);
      expect(find.text('3 codes found'), findsOneWidget);
      expect(find.text('Hello there'), findsOneWidget);
      expect(find.text('9780306406157 · EAN-13'), findsOneWidget);
      expect(find.text('https://example.com'), findsOneWidget);

      await tapText(tester, '9780306406157 · EAN-13');
      expect(find.text('Product barcode'), findsOneWidget);
      expect(find.text('Valid'), findsOneWidget);
    });

    testWidgets('files picker is decoded too, empty pictures explain', (
      tester,
    ) async {
      final h = Harness();
      await h.pump(tester);
      await tapText(tester, 'Files');
      expect(h.scanner.decodedPaths, ['/tmp/file.jpg']);
      expect(find.text(QrScanScreen.noCodeInImage), findsOneWidget);
    });
  });

  group('result actions', () {
    testWidgets('suspicious link warns and asks before opening', (
      tester,
    ) async {
      final h = Harness();
      await h.pump(tester);
      await scan(
        tester,
        h,
        const ScannedCode(
          raw: 'http://192.168.0.1/login',
          symbology: CodeSymbology.qr,
        ),
      );
      expect(find.text('Be careful with this link'), findsOneWidget);
      expect(find.text(UrlWarning.ipAddress.title), findsOneWidget);
      await tapText(tester, 'Open in browser');
      expect(find.text('This link looks suspicious'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(h.actions.opened, isEmpty);
      await tapText(tester, 'Open in browser');
      await tester.tap(find.text('Open anyway'));
      await settle(tester);
      expect(h.actions.opened.single.toString(), 'http://192.168.0.1/login');
    });

    testWidgets('safe link opens directly', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await scan(
        tester,
        h,
        const ScannedCode(
          raw: 'https://example.com/a',
          symbology: CodeSymbology.qr,
        ),
      );
      await tapText(tester, 'Open in browser');
      expect(h.actions.opened.single.toString(), 'https://example.com/a');
    });

    testWidgets('contact shares a .vcf; event shares an .ics', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await scan(
        tester,
        h,
        const ScannedCode(
          raw: 'MECARD:N:Lee,Ana;TEL:+15550100;;',
          symbology: CodeSymbology.qr,
        ),
      );
      await tapText(tester, 'Add to contacts');
      expect(h.actions.sharedFiles.single.extension, 'vcf');
      expect(
        String.fromCharCodes(h.actions.sharedFiles.single.bytes),
        contains('TEL:+15550100'),
      );
      await tester.pageBack();
      await settle(tester);
      await scan(
        tester,
        h,
        const ScannedCode(
          raw:
              'BEGIN:VEVENT\nSUMMARY:Party\nDTSTART:20261231T200000Z\nEND:VEVENT',
          symbology: CodeSymbology.qr,
        ),
      );
      await tapText(tester, 'Add to calendar');
      expect(h.actions.sharedFiles.last.extension, 'ics');
    });

    testWidgets('email, phone, SMS and geo launch their apps', (tester) async {
      final cases = {
        'mailto:a@b.co?subject=Hi': ('Write email', 'mailto:a@b.co?subject=Hi'),
        'tel:+15550100': ('Call', 'tel:+15550100'),
        'SMSTO:+1555:Yo': ('Send message', 'sms:+1555?body=Yo'),
        'geo:48.8584,2.2945': (
          'Open in maps',
          'geo:48.8584,2.2945?q=48.8584,2.2945',
        ),
      };
      for (final entry in cases.entries) {
        final h = Harness();
        await h.pump(tester);
        await scan(
          tester,
          h,
          ScannedCode(raw: entry.key, symbology: CodeSymbology.qr),
        );
        await tapText(tester, entry.value.$1);
        expect(h.actions.opened.single.toString(), entry.value.$2);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('payment request is read-only', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await scan(
        tester,
        h,
        const ScannedCode(
          raw: 'upi://pay?pa=shop@bank&pn=Shop&am=10',
          symbology: CodeSymbology.qr,
        ),
      );
      expect(find.text('Payment request'), findsOneWidget);
      expect(find.text(CodeResultScreen.paymentNote), findsOneWidget);
      expect(find.text('Open in browser'), findsNothing);
      expect(find.textContaining('UPI'), findsNothing);
      await tapText(tester, 'Copy payee address');
      expect(h.actions.copied.single, 'shop@bank');
      expect(h.actions.opened, isEmpty);
    });

    testWidgets('otpauth hands off to the Authenticator', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await scan(tester, h, otpCode);
      expect(find.text('Two-step verification key'), findsOneWidget);
      expect(find.textContaining('JBSWY3DPEHPK3PXP'), findsNothing);
      expect(find.text('Save to ID Vault'), findsNothing);
      await tapText(tester, 'Add to Authenticator');
      expect(find.text('Add to Authenticator?'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await settle(tester);
      expect(h.authenticator.added.single.issuer, 'GitHub');
      expect(h.authenticator.added.single.label, 'me@example.com');
      expect(find.text('Authenticator home'), findsOneWidget);
    });

    testWidgets('save to vault writes a text note, confirming sensitive ones', (
      tester,
    ) async {
      final h = Harness();
      await h.pump(tester);
      await scan(tester, h, wifiCode);
      await tapText(tester, 'Save to ID Vault');
      expect(find.text('Save sensitive details?'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await settle(tester);
      // "Save to folder" picker; default = top level.
      await tester.tap(find.text('Save in ID Vault'));
      await settle(tester);
      final note = h.actions.vault.single;
      expect(note.format, DocumentFormat.txt);
      expect(String.fromCharCodes(note.bytes), contains('Password: hunter22'));
      expect(find.text('Saved to ID Vault'), findsOneWidget);
    });

    testWidgets('copy all and share use the plain-text summary', (
      tester,
    ) async {
      final h = Harness();
      await h.pump(tester);
      await scan(tester, h, textCode);
      await tester.tap(find.byTooltip('Copy all'));
      await tester.tap(find.byTooltip('Share'));
      await settle(tester);
      expect(h.actions.copied, ['Hello there']);
      expect(h.actions.sharedText, ['Hello there']);
    });
  });

  group('history', () {
    testWidgets('on by default: plain scans are kept, sensitive ones not', (
      tester,
    ) async {
      final h = Harness();
      await h.pump(tester);
      await scan(tester, h, textCode);
      await tester.pageBack();
      await settle(tester);
      await scan(tester, h, wifiCode);
      await tester.pageBack();
      await settle(tester);
      await scan(tester, h, otpCode);
      expect(h.store.state.entries.map((e) => e.raw), [textCode.raw]);
    });

    testWidgets('off: nothing is kept', (tester) async {
      final h = Harness(history: const QrHistoryState(enabled: false));
      await h.pump(tester);
      await scan(tester, h, textCode);
      expect(h.store.state.entries, isEmpty);
    });

    testWidgets('sensitive allowed: Wi-Fi kept, sign-in keys never', (
      tester,
    ) async {
      final h = Harness(history: const QrHistoryState(includeSensitive: true));
      await h.pump(tester);
      await scan(tester, h, wifiCode);
      await tester.pageBack();
      await settle(tester);
      await scan(tester, h, otpCode);
      expect(h.store.state.entries.map((e) => e.raw), [wifiCode.raw]);
    });

    testWidgets('gallery results are all recorded', (tester) async {
      final h = Harness(
        scanner: FakeCodeScanner(
          imageCodes: const [
            textCode,
            wifiCode,
            ScannedCode(raw: 'second', symbology: CodeSymbology.qr),
          ],
        ),
      );
      await h.pump(tester);
      await tapText(tester, 'Gallery');
      expect(h.store.state.entries.map((e) => e.raw).toSet(), {
        'Hello there',
        'second',
      });
    });

    testWidgets('history screen: open, delete, turn off, clear', (
      tester,
    ) async {
      final h = Harness(
        history: QrHistoryState(
          entries: [
            QrHistoryEntry(
              id: '1',
              raw: 'https://example.com',
              symbology: CodeSymbology.qr,
              kind: CodeKind.url,
              summary: 'https://example.com',
              scannedAt: DateTime(2026),
            ),
            QrHistoryEntry(
              id: '2',
              raw: 'note',
              symbology: CodeSymbology.qr,
              kind: CodeKind.text,
              summary: 'note',
              scannedAt: DateTime(2026),
            ),
          ],
        ),
      );
      await h.pump(tester, location: Routes.qrHistory);
      expect(find.text('Scan history'), findsOneWidget);
      expect(find.text('https://example.com'), findsOneWidget);

      await tapText(tester, 'https://example.com');
      expect(find.text('Open in browser'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);

      await tester.tap(find.byTooltip('Delete').last);
      await settle(tester);
      expect(h.store.state.entries.map((e) => e.id), ['1']);

      await tester.tap(find.byTooltip('Clear all'));
      await settle(tester);
      await tester.tap(find.text('Clear'));
      await settle(tester);
      expect(h.store.state.entries, isEmpty);
      expect(find.text('No scans yet'), findsOneWidget);

      await tester.tap(find.text('Keep scan history'));
      await settle(tester);
      expect(h.store.state.enabled, isFalse);
      expect(find.text('Scan history is off.'), findsOneWidget);
    });

    test('turning off sensitive items removes kept ones', () async {
      final store = MemoryQrHistoryStore(
        const QrHistoryState(includeSensitive: true),
      );
      final container = ProviderContainer(
        overrides: [qrHistoryStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final history = container.read(qrHistoryProvider.notifier);
      await container.read(qrHistoryProvider.future);
      expect(await history.record(wifiCode), isTrue);
      expect(await history.record(textCode), isTrue);
      expect(await history.record(textCode), isTrue);
      expect(store.state.entries.length, 2, reason: 'duplicates move up');
      await history.setIncludeSensitive(include: false);
      expect(store.state.entries.map((e) => e.raw), [textCode.raw]);
      await history.setEnabled(enabled: false);
      expect(store.state.entries, isEmpty);
      expect(await history.record(textCode), isFalse);
    });

    test('JSON file store round trips and survives corruption', () async {
      final dir = await Directory.systemTemp.createTemp('qr_history');
      addTearDown(() => dir.delete(recursive: true));
      final store = JsonFileQrHistoryStore(File('${dir.path}/h/history.json'));
      expect((await store.load()).entries, isEmpty);
      await store.save(
        QrHistoryState(
          includeSensitive: true,
          entries: [
            QrHistoryEntry(
              id: 'x',
              raw: 'WIFI:S:a;;',
              symbology: CodeSymbology.dataMatrix,
              kind: CodeKind.wifi,
              summary: 'a',
              scannedAt: DateTime.utc(2026, 1, 2),
            ),
          ],
        ),
      );
      final back = await store.load();
      expect(back.includeSensitive, isTrue);
      expect(back.entries.single.symbology, CodeSymbology.dataMatrix);
      expect(back.entries.single.kind, CodeKind.wifi);
      expect(back.entries.single.scannedAt, DateTime.utc(2026, 1, 2));
      await store.file.writeAsString('{not json');
      expect((await store.load()).entries, isEmpty);
      await store.file.writeAsString('{"entries":[{"bad":1},"x"]}');
      expect((await store.load()).enabled, isTrue);
    });
  });

  group('generator', () {
    testWidgets('Wi-Fi form previews a QR and exports PNGs', (tester) async {
      final h = Harness();
      await h.pump(tester, location: Routes.qrGenerate);
      expect(
        find.text('Fill in the details to see your QR code.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Wi-Fi'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('qr-field-ssid')),
        'Home',
      );
      await tester.enterText(
        find.byKey(const ValueKey('qr-field-password')),
        'secret',
      );
      await settle(tester);
      expect(find.byType(QrMatrixView), findsOneWidget);

      await tester.tap(find.text('High'));
      await tester.tap(find.text('512 px'));
      await settle(tester);

      await tester.ensureVisible(find.text('Add to ID Vault'));
      await settle(tester);
      await tester.tap(find.text('Add to ID Vault'));
      await settle(tester);
      await tester.tap(find.text('Save in ID Vault'));
      for (var i = 0; i < 5 && h.actions.vault.isEmpty; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
      }
      await settle(tester);
      final png = h.actions.vault.single;
      expect(png.format, DocumentFormat.png);
      expect(png.bytes.sublist(1, 4), 'PNG'.codeUnits);

      await tester.runAsync(() async {
        await tester.tap(find.text('Share PNG'));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await settle(tester);
      expect(h.actions.sharedFiles.single.extension, 'png');
    });

    testWidgets('every type builds a payload from its form', (tester) async {
      final h = Harness();
      await h.pump(tester, location: Routes.qrGenerate);
      final inputs = {
        'Text': {'text': 'hello'},
        'Link': {'url': 'example.com'},
        'Contact': {'given': 'Ana', 'tel': '+1555'},
        'Email': {'to': 'a@b.co'},
        'Phone': {'phone': '+1555'},
        'SMS': {'smsTo': '+1555', 'smsBody': 'hi'},
      };
      for (final entry in inputs.entries) {
        await tester.tap(find.widgetWithText(ChoiceChip, entry.key));
        await settle(tester);
        for (final f in entry.value.entries) {
          await tester.enterText(
            find.byKey(ValueKey('qr-field-${f.key}')),
            f.value,
          );
        }
        await settle(tester);
        expect(find.byType(QrMatrixView), findsOneWidget, reason: entry.key);
      }
    });

    testWidgets('too much data explains the limit', (tester) async {
      final h = Harness();
      await h.pump(tester, location: Routes.qrGenerate);
      await tester.enterText(
        find.byKey(const ValueKey('qr-field-text')),
        List.filled(3000, 'x').join(),
      );
      await tester.tap(find.text('High'));
      await settle(tester);
      expect(find.text(QrGenerateScreen.tooLong), findsOneWidget);
    });
  });

  group('routes', () {
    testWidgets('scanner links to generator and history', (tester) async {
      final h = Harness();
      await h.pump(tester);
      await tester.tap(find.byTooltip('Create QR code'));
      await settle(tester);
      expect(find.text('Create QR code'), findsOneWidget);
      await tester.pageBack();
      await settle(tester);
      await tester.tap(find.byTooltip('Scan history'));
      await settle(tester);
      expect(find.text('Scan history'), findsOneWidget);
    });

    testWidgets('one redirect gates the whole tool', (tester) async {
      final h = Harness();
      await h.pump(
        tester,
        location: Routes.qrGenerate,
        redirect: (context, state) => '/paywall',
      );
      expect(find.text('Paywall'), findsOneWidget);
    });
  });
}
