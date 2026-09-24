import 'dart:math' as math;

import 'package:docscan_design_system/docscan_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    group('$name theme meets WCAG AA', () {
      final s = theme.colorScheme;
      final ds = theme.extension<DsColors>()!;

      final pairs = <String, (Color, Color, double)>{
        'text on surface': (s.onSurface, s.surface, 4.5),
        'text on canvas': (s.onSurface, ds.canvas, 4.5),
        'secondary text on surface': (ds.textSecondary, s.surface, 4.5),
        'secondary text on canvas': (ds.textSecondary, ds.canvas, 4.5),
        'on primary': (s.onPrimary, s.primary, 4.5),
        'primary on surface (links/icons)': (s.primary, s.surface, 3),
        'on error': (s.onError, s.error, 4.5),
        'error on surface': (s.error, s.surface, 4.5),
        'success on success container': (ds.success, ds.successContainer, 4.5),
        'on primary container': (s.onPrimaryContainer, s.primaryContainer, 4.5),
        'snackbar text': (s.onInverseSurface, s.inverseSurface, 4.5),
      };

      for (final MapEntry(key: label, value: (fg, bg, min)) in pairs.entries) {
        test(label, () {
          expect(
            contrast(fg, bg),
            greaterThanOrEqualTo(min),
            reason: '$label contrast too low',
          );
        });
      }
    });
  }

  testWidgets('shared widgets render in both themes at 2x text', (
    tester,
  ) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: ListView(
                children: [
                  HeroAction(
                    icon: Icons.document_scanner_rounded,
                    title: 'Scan a document',
                    subtitle: 'Auto edge detection',
                    onTap: () {},
                  ),
                  const OfflineBadge(),
                  const FidelityNote(
                    label: 'Extracts content',
                    explanation: 'Layout may change.',
                    limitations: ['Images are not kept'],
                  ),
                  const SizedBox(
                    height: 400,
                    child: EmptyState(
                      icon: Icons.folder_rounded,
                      title: 'No files yet',
                      message: 'Scan something to get started.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Scan a document'), findsOneWidget);
    }
  });

  test('formatBytes and formatRelativeDate', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    final now = DateTime(2026, 9, 24, 12);
    expect(formatRelativeDate(now, now: now), 'Just now');
    expect(formatRelativeDate(DateTime(2026, 9, 23, 9), now: now), 'Yesterday');
    expect(formatRelativeDate(DateTime(2026, 3, 12), now: now), '12 Mar 2026');
  });
}
