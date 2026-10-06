import 'package:docscan_domain/docscan_domain.dart';
import 'package:test/test.dart';

/// Country names that must not appear in user-visible preset or vault labels
/// (product rule: presets are named by size term, never by country).
final _countries = RegExp(
  r'\b(US|USA|UK|EU|India|Indian|China|Chinese|Canada|Canadian|Schengen|'
  r'Australia|Aadhaar|PAN|Green Card|American|British)\b',
);

/// Visa programmes and third-party brands: presets are named by size term.
final _programs = RegExp(r'\b(visa|visas|LinkedIn)\b', caseSensitive: false);

void main() {
  group('crop presets', () {
    test('labels and descriptions are country-neutral', () {
      for (final p in CropPreset.all) {
        expect(p.label, isNot(matches(_countries)), reason: p.id);
        expect(p.description ?? '', isNot(matches(_countries)), reason: p.id);
      }
    });

    test('labels and descriptions name no visa programme or brand', () {
      for (final p in CropPreset.all) {
        expect(p.label, isNot(matches(_programs)), reason: p.id);
        expect(p.description ?? '', isNot(matches(_programs)), reason: p.id);
      }
    });

    test('persisted ids are unique and stable', () {
      final ids = [for (final p in CropPreset.all) p.id];
      expect(ids.toSet(), hasLength(ids.length));
      expect(
        ids,
        containsAll([
          'passport_35x45',
          'passport_us',
          'visa_33x48',
          'passport_canada',
          'stamp_20x25',
          'id_30x40',
        ]),
      );
    });

    test('term-based sizes keep their dimensions', () {
      expect(CropPreset.passportIntl.label, 'Passport size photo');
      expect(CropPreset.passportIntl.sizeLabel, '35 × 45 mm');
      expect(CropPreset.passportUs.label, 'Square photo');
      expect(CropPreset.passportUs.sizeLabel, '2 × 2 in');
      expect(CropPreset.idPhoto.sizeLabel, '30 × 40 mm');
      expect(CropPreset.stampSize.sizeLabel, '20 × 25 mm');
    });
  });

  test('vault slots and categories are country-neutral', () {
    for (final s in VaultSlot.all) {
      expect(s.label, isNot(matches(_countries)), reason: s.key);
    }
    for (final c in DocumentCategory.values) {
      expect('${c.label} ${c.hint}', isNot(matches(_countries)));
    }
    expect(VaultSlot.byKey('tax_id')?.label, 'Tax ID card');
  });

  test('page sizes are country-neutral', () {
    for (final s in PdfPageSize.values) {
      expect(s.label, isNot(matches(_countries)), reason: s.name);
    }
  });
}
