import 'dart:typed_data';

import 'package:docscan_lab/src/lab_app.dart';
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A light "page" on a dark "desk" — easy for the detector.
Uint8List syntheticDocument() {
  final canvas = img.Image(width: 240, height: 320)
    ..clear(img.ColorRgb8(40, 40, 48));
  img.fillRect(
    canvas,
    x1: 40,
    y1: 50,
    x2: 200,
    y2: 280,
    color: img.ColorRgb8(245, 245, 240),
  );
  img.fillRect(
    canvas,
    x1: 60,
    y1: 80,
    x2: 180,
    y2: 90,
    color: img.ColorRgb8(20, 20, 20),
  );
  return img.encodePng(canvas);
}

void main() {
  testWidgets('shows the empty state before an image is picked', (
    tester,
  ) async {
    await tester.pumpWidget(const LabApp());
    expect(find.text('Engine Lab'), findsOneWidget);
    expect(find.text('Pick a document photo'), findsOneWidget);
  });

  testWidgets('runs detection and filters on a picked image', (tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bytes = syntheticDocument();
    await tester.pumpWidget(LabApp(source: () async => bytes));
    await tester.tap(find.text('Pick an image').first);
    await tester.pump();
    // Engine work runs in background isolates; let it finish in real time.
    for (var i = 0; i < 120; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump();
      if (find.textContaining('Remove shadows').evaluate().isNotEmpty) break;
    }
    expect(find.text('Confidence'), findsOneWidget);
    expect(find.text('240 × 320'), findsOneWidget);
    expect(find.textContaining('Grayscale'), findsWidgets);
  });
}
