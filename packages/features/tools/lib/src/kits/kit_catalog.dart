import 'package:docscan_domain/docscan_domain.dart';
import 'package:feature_tools/src/kits/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bump when any limit, source or item changes.
const kitCatalogVersion = 2;

const _kb = 1024;
const _mb = 1024 * 1024;

/// Published constraints, reviewed by a person on [ApplicationKit.reviewedOn].
/// IDSnap never promises that a portal will accept an upload.
///
/// Labels are term-specific (photo size, portal type), never country
/// names. Ids are stable: saved state and Home shortcuts depend on them.
const List<ApplicationKit> kitCatalog = [
  ApplicationKit(
    id: 'us-visa',
    label: 'Square photo (2 × 2 in)',
    description:
        'Square 2 × 2 in photo, 600–1200 px, under 240 KB, head 50–69 % '
        'of the height.',
    source: 'Published 2 × 2 in digital photo specification',
    reviewedOn: '2026-09-01',
    category: DocumentCategory.ids,
    items: [
      PhotoItem(
        id: 'photo',
        label: 'Square photo',
        preset: CropPreset.passportUs,
        maxBytes: 240 * _kb,
        minPx: 600,
        maxPx: 1200,
        backgroundHint: true,
        hint: 'Plain white or off-white background, face the camera.',
      ),
    ],
  ),
  ApplicationKit(
    id: 'schengen-visa',
    label: 'Passport size photo (35 × 45 mm)',
    description: '35 × 45 mm photo, face 70–80 % of the height.',
    source: 'ICAO Doc 9303 photo guidance for 35 × 45 mm photos',
    reviewedOn: '2026-09-01',
    category: DocumentCategory.ids,
    items: [
      PhotoItem(
        id: 'photo',
        label: 'Passport size photo',
        preset: CropPreset.passportIntl,
        maxBytes: 500 * _kb,
        backgroundHint: true,
        hint: 'Light, plain background. No shadows on the face.',
      ),
    ],
  ),
  ApplicationKit(
    id: 'exam-portal',
    label: 'Exam/portal upload kit',
    description:
        'Photo under 50 KB, signature under 20 KB and documents as one '
        'PDF under 300 KB — the most common limits on exam and admission '
        'portals.',
    source: 'Typical limits on exam & university admission portals',
    reviewedOn: '2026-09-01',
    category: DocumentCategory.education,
    items: [
      PhotoItem(
        id: 'photo',
        label: 'Photograph',
        preset: CropPreset.passportIntl,
        width: 240,
        height: 308,
        maxBytes: 50 * _kb,
        hint: 'Recent photo, light background.',
      ),
      SignatureItem(
        id: 'signature',
        label: 'Signature',
        width: 280,
        height: 120,
        maxBytes: 20 * _kb,
        hint: 'Sign with a dark pen on plain white paper.',
      ),
      DocumentItem(
        id: 'documents',
        label: 'Certificates / marksheets',
        maxBytes: 300 * _kb,
        maxPages: 10,
      ),
    ],
  ),
  ApplicationKit(
    id: 'job-application',
    label: 'Job application kit',
    description:
        'Profile photo under 100 KB and your resume + certificates merged '
        'into one PDF under 2 MB.',
    source: 'Common limits on job portals and HR systems',
    reviewedOn: '2026-09-01',
    category: DocumentCategory.education,
    items: [
      PhotoItem(
        id: 'photo',
        label: 'Profile photo',
        preset: CropPreset.profilePhoto,
        width: 600,
        height: 600,
        maxBytes: 100 * _kb,
      ),
      DocumentItem(
        id: 'documents',
        label: 'Resume & certificates',
        maxBytes: 2 * _mb,
        maxPages: 30,
      ),
    ],
  ),
];

/// User-defined limits for a portal not in the catalog.
///
/// Gap: kept in memory for the session only; persisting custom kits needs a
/// store (planned with the vault settings).
class CustomKitController extends Notifier<ApplicationKit> {
  @override
  ApplicationKit build() => custom(
    preset: CropPreset.passportIntl,
    photoKb: 100,
    signatureKb: 20,
    documentKb: 500,
  );

  void update({
    required CropPreset preset,
    required int photoKb,
    required int? signatureKb,
    required int documentKb,
  }) => state = custom(
    preset: preset,
    photoKb: photoKb,
    signatureKb: signatureKb,
    documentKb: documentKb,
  );

  static ApplicationKit custom({
    required CropPreset preset,
    required int photoKb,
    required int? signatureKb,
    required int documentKb,
  }) => ApplicationKit(
    id: customKitId,
    label: 'Custom kit',
    description: 'Your own limits for any upload form.',
    source: 'Limits you entered',
    reviewedOn: 'your settings',
    items: [
      PhotoItem(
        id: 'photo',
        label: 'Photo',
        preset: preset,
        maxBytes: photoKb * _kb,
      ),
      if (signatureKb != null)
        SignatureItem(
          id: 'signature',
          label: 'Signature',
          width: 280,
          height: 120,
          maxBytes: signatureKb * _kb,
        ),
      DocumentItem(
        id: 'documents',
        label: 'Documents',
        maxBytes: documentKb * _kb,
      ),
    ],
  );
}

const customKitId = 'custom';

final customKitProvider = NotifierProvider<CustomKitController, ApplicationKit>(
  CustomKitController.new,
);

/// Catalog kit or the custom kit; null for unknown ids.
final kitByIdProvider = Provider.family<ApplicationKit?, String>((ref, id) {
  if (id == customKitId) return ref.watch(customKitProvider);
  for (final k in kitCatalog) {
    if (k.id == id) return k;
  }
  return null;
});
