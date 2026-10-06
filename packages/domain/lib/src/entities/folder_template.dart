import 'package:meta/meta.dart';

/// Icon keys a folder can use. The UI maps each key to an icon; unknown keys
/// fall back to the plain folder icon, so the list can grow safely.
abstract final class FolderIcons {
  static const folder = 'folder';
  static const badge = 'badge';
  static const school = 'school';
  static const medical = 'medical';
  static const car = 'car';
  static const receipt = 'receipt';
  static const home = 'home';
  static const travel = 'travel';
  static const work = 'work';
  static const family = 'family';
  static const bank = 'bank';
  static const pets = 'pets';
  static const star = 'star';
  static const heart = 'heart';

  static const all = [
    folder,
    badge,
    school,
    medical,
    car,
    receipt,
    home,
    travel,
    work,
    family,
    bank,
    pets,
    star,
    heart,
  ];
}

/// Colour keys a folder can use (mapped to theme-aware colours by the UI).
abstract final class FolderColors {
  static const blue = 'blue';
  static const purple = 'purple';
  static const red = 'red';
  static const teal = 'teal';
  static const amber = 'amber';
  static const green = 'green';
  static const orange = 'orange';
  static const pink = 'pink';
  static const slate = 'slate';

  static const all = [
    blue,
    purple,
    red,
    teal,
    amber,
    green,
    orange,
    pink,
    slate,
  ];
}

/// A suggested folder offered by the "+" menu. Templates are data: edit
/// [FolderTemplate.all] to change what's offered. Labels are deliberately
/// country-neutral.
@immutable
class FolderTemplate {
  const FolderTemplate({
    required this.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.color,
    this.subfolders = const [],
  });

  /// Stable id stored on created folders (`folders.template_key`). The first
  /// six match `DocumentCategory.name` so vault-category documents can be
  /// filed into the matching folder.
  final String key;
  final String label;

  /// One line describing what goes inside.
  final String hint;

  /// [FolderIcons] key.
  final String icon;

  /// [FolderColors] key.
  final String color;

  /// Subfolder names suggested first when adding a folder inside one made
  /// from this template. Only suggestions; nothing is created automatically.
  final List<String> subfolders;

  static const all = <FolderTemplate>[
    FolderTemplate(
      key: 'ids',
      label: 'IDs & Proofs',
      hint: 'Identity cards, passport, driving licence',
      icon: FolderIcons.badge,
      color: FolderColors.blue,
      subfolders: ['Identity cards', 'Passport', 'Driving licence'],
    ),
    FolderTemplate(
      key: 'education',
      label: 'Education & Career',
      hint: 'Certificates, marksheets, resume, offer letters',
      icon: FolderIcons.school,
      color: FolderColors.purple,
      subfolders: ['Certificates', 'Marksheets', 'Resume', 'Offer letters'],
    ),
    FolderTemplate(
      key: 'medical',
      label: 'Medical & Health',
      hint: 'Prescriptions, reports, insurance cards',
      icon: FolderIcons.medical,
      color: FolderColors.red,
      subfolders: ['Prescriptions', 'Reports', 'Insurance', 'Vaccinations'],
    ),
    FolderTemplate(
      key: 'vehicles',
      label: 'Vehicles & Insurance',
      hint: 'Registration, insurance, service records',
      icon: FolderIcons.car,
      color: FolderColors.teal,
      subfolders: ['Registration', 'Insurance', 'Service records'],
    ),
    FolderTemplate(
      key: 'tax',
      label: 'Tax & Receipts',
      hint: 'Tax returns, salary slips, bills, receipts',
      icon: FolderIcons.receipt,
      color: FolderColors.amber,
      subfolders: ['Tax returns', 'Salary slips', 'Bills & receipts'],
    ),
    FolderTemplate(
      key: 'home',
      label: 'Home & Legal',
      hint: 'Rent agreement, property papers, utility bills',
      icon: FolderIcons.home,
      color: FolderColors.green,
      subfolders: ['Rent & lease', 'Property', 'Utility bills'],
    ),
    FolderTemplate(
      key: 'travel',
      label: 'Travel',
      hint: 'Tickets, bookings, visas',
      icon: FolderIcons.travel,
      color: FolderColors.orange,
      subfolders: ['Tickets', 'Bookings', 'Visas'],
    ),
    FolderTemplate(
      key: 'work',
      label: 'Work',
      hint: 'Contracts, payslips, projects',
      icon: FolderIcons.work,
      color: FolderColors.slate,
      subfolders: ['Contracts', 'Payslips', 'Projects'],
    ),
  ];

  static FolderTemplate? byKey(String? key) {
    for (final t in all) {
      if (t.key == key) return t;
    }
    return null;
  }
}
