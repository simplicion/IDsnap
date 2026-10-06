import 'package:meta/meta.dart';

/// Legacy vault categories (roadmap Feature B1). The vault UI is now driven
/// by user-created folders (`Folder`, `FolderTemplate`); categories remain on
/// documents for backward compatibility. A document given a category while
/// it has no folder is filed into the top-level folder made from the
/// template with the same key (`FolderTemplate.key == name`), if one exists.
enum DocumentCategory {
  ids('IDs & Proofs', 'National ID, passport, driving licence, tax ID'),
  education('Education & Career', 'Degrees, marksheets, certificates, resume'),
  medical('Medical & Health', 'Prescriptions, reports, insurance cards'),
  vehicles('Vehicles & Insurance', 'Registration, insurance, service records'),
  tax('Tax & Receipts', 'Tax returns, salary slips, bills, receipts'),
  home('Home & Legal', 'Rent agreement, property papers, utility bills');

  const DocumentCategory(this.label, this.hint);

  final String label;
  final String hint;
}

/// What an empty-state slot starts when tapped.
enum SlotCapture { idCard, twoPageScan, scan }

/// A suggested document "slot" shown in an empty category
/// ("Tap to add your Passport").
@immutable
class VaultSlot {
  const VaultSlot(this.key, this.label, this.category, this.capture);

  /// Stable id stored on the document (`documents.slot`).
  final String key;
  final String label;
  final DocumentCategory category;
  final SlotCapture capture;

  static const all = <VaultSlot>[
    VaultSlot(
      'national_id',
      'National ID',
      DocumentCategory.ids,
      SlotCapture.idCard,
    ),
    VaultSlot(
      'passport',
      'Passport',
      DocumentCategory.ids,
      SlotCapture.twoPageScan,
    ),
    VaultSlot(
      'driving_licence',
      'Driving licence',
      DocumentCategory.ids,
      SlotCapture.idCard,
    ),
    VaultSlot(
      'tax_id',
      'Tax ID card',
      DocumentCategory.ids,
      SlotCapture.idCard,
    ),
    VaultSlot(
      'degree',
      'Degree certificate',
      DocumentCategory.education,
      SlotCapture.scan,
    ),
    VaultSlot(
      'marksheets',
      'Marksheets',
      DocumentCategory.education,
      SlotCapture.scan,
    ),
    VaultSlot('resume', 'Resume', DocumentCategory.education, SlotCapture.scan),
    VaultSlot(
      'insurance_card',
      'Health insurance card',
      DocumentCategory.medical,
      SlotCapture.idCard,
    ),
    VaultSlot(
      'prescription',
      'Prescription',
      DocumentCategory.medical,
      SlotCapture.scan,
    ),
    VaultSlot(
      'vehicle_rc',
      'Vehicle registration',
      DocumentCategory.vehicles,
      SlotCapture.idCard,
    ),
    VaultSlot(
      'vehicle_insurance',
      'Vehicle insurance',
      DocumentCategory.vehicles,
      SlotCapture.scan,
    ),
    VaultSlot(
      'tax_return',
      'Tax return',
      DocumentCategory.tax,
      SlotCapture.scan,
    ),
    VaultSlot(
      'rent_agreement',
      'Rent agreement',
      DocumentCategory.home,
      SlotCapture.scan,
    ),
  ];

  static List<VaultSlot> forCategory(DocumentCategory c) => [
    for (final s in all)
      if (s.category == c) s,
  ];

  static VaultSlot? byKey(String? key) {
    for (final s in all) {
      if (s.key == key) return s;
    }
    return null;
  }
}
