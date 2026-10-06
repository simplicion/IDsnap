import 'package:docscan_domain/src/entities/folder.dart';
import 'package:meta/meta.dart';

/// Starting points for a secure note. Labels are generic on purpose (no
/// country-specific fields).
enum NoteTemplate {
  custom('Blank note', ''),
  wifi('Wi-Fi password', 'Network name: \nPassword: \nSecurity: WPA2/WPA3\n'),
  bankAccount(
    'Bank account',
    'Bank: \nAccount holder: \nAccount number: \nBranch / routing code: \n'
        'SWIFT / BIC: \n',
  ),
  cardPin(
    'Card PIN hint',
    'Card: \nLast 4 digits: \nPIN hint (never the PIN itself): \n',
  ),
  recovery(
    'Recovery info',
    'Service: \nRecovery email / phone: \nRecovery codes:\n- [ ] \n- [ ] \n',
  ),
  licence('Licence / serial key', 'Product: \nLicence key: \nPurchased: \n');

  const NoteTemplate(this.label, this.body);

  final String label;

  /// Pre-filled body.
  final String body;

  static NoteTemplate byName(String? name) =>
      values.asNameMap()[name] ?? NoteTemplate.custom;
}

/// A secure note (stored in the SQLCipher database).
@immutable
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.tag,
    this.template = NoteTemplate.custom,
    this.pinned = false,
    this.lockMode = FolderLockMode.none,
  });

  final String id;
  final String title;

  /// Plain text; lines starting with `- [ ] ` / `- [x] ` are checklist items.
  final String body;

  /// Optional category / folder tag.
  final String? tag;
  final NoteTemplate template;
  final bool pinned;
  final FolderLockMode lockMode;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isLocked => lockMode != FolderLockMode.none;

  /// Title shown in lists ("Untitled note" when empty).
  String get displayTitle => title.trim().isEmpty ? 'Untitled note' : title;

  /// First non-empty body line for list previews (never for locked notes).
  String get preview {
    if (isLocked) return '';
    for (final line in body.split('\n')) {
      final t = ChecklistLine.parse(line)?.text ?? line.trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  Note copyWith({
    String? title,
    String? body,
    String? tag,
    bool clearTag = false,
    NoteTemplate? template,
    bool? pinned,
    FolderLockMode? lockMode,
    DateTime? updatedAt,
  }) => Note(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    tag: clearTag ? null : tag ?? this.tag,
    template: template ?? this.template,
    pinned: pinned ?? this.pinned,
    lockMode: lockMode ?? this.lockMode,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.title == title &&
      other.body == body &&
      other.tag == tag &&
      other.template == template &&
      other.pinned == pinned &&
      other.lockMode == lockMode &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    body,
    tag,
    template,
    pinned,
    lockMode,
    createdAt,
    updatedAt,
  );
}

/// One `- [ ] text` / `- [x] text` line.
@immutable
class ChecklistLine {
  const ChecklistLine({required this.checked, required this.text});

  static final _pattern = RegExp(r'^\s*[-*] \[( |x|X)\] ?(.*)$');

  final bool checked;
  final String text;

  static ChecklistLine? parse(String line) {
    final m = _pattern.firstMatch(line);
    if (m == null) return null;
    return ChecklistLine(checked: m.group(1) != ' ', text: m.group(2)!.trim());
  }

  String format() => '- [${checked ? 'x' : ' '}] $text';

  /// [body] with the checklist item on line [lineIndex] toggled.
  static String toggle(String body, int lineIndex) {
    final lines = body.split('\n');
    if (lineIndex < 0 || lineIndex >= lines.length) return body;
    final item = parse(lines[lineIndex]);
    if (item == null) return body;
    lines[lineIndex] = ChecklistLine(
      checked: !item.checked,
      text: item.text,
    ).format();
    return lines.join('\n');
  }
}
