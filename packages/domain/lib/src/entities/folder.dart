import 'package:docscan_domain/src/entities/document.dart';
import 'package:docscan_domain/src/entities/folder_template.dart';
import 'package:meta/meta.dart';

/// How a folder is protected (optional, on top of App Lock).
///
/// A lock is an access gate: it hides the folder's contents in the UI until
/// the user authenticates. Files are not encrypted by it.
enum FolderLockMode {
  /// No extra protection.
  none,

  /// The phone's biometrics / screen lock (the App Lock prompt).
  device,

  /// A 4–8 digit PIN for this folder; only a salted hash is stored, in the
  /// platform keystore.
  pin,
}

/// What happens to a folder's contents when it is deleted.
enum FolderDeleteMode {
  /// Subfolders and files are deleted too.
  deleteContents,

  /// Subfolders and files move up to the deleted folder's parent.
  moveContentsToParent,
}

/// A user-created folder. Folders nest without a depth limit ([parentId]
/// `null` = top level of the vault).
@immutable
class Folder {
  const Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    DateTime? updatedAt,
    this.parentId,
    this.icon,
    this.color,
    this.templateKey,
    this.sortOrder = 0,
    this.lockMode = FolderLockMode.none,
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? parentId;

  /// [FolderIcons] key; `null` = the default folder icon.
  final String? icon;

  /// [FolderColors] key; `null` = the theme's accent.
  final String? color;

  /// [FolderTemplate.key] this folder was created from, if any.
  final String? templateKey;
  final int sortOrder;
  final FolderLockMode lockMode;

  bool get isLocked => lockMode != FolderLockMode.none;

  Folder copyWith({
    String? name,
    String? parentId,
    bool clearParent = false,
    String? icon,
    String? color,
    String? templateKey,
    int? sortOrder,
    FolderLockMode? lockMode,
    DateTime? updatedAt,
  }) => Folder(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    parentId: clearParent ? null : parentId ?? this.parentId,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    templateKey: templateKey ?? this.templateKey,
    sortOrder: sortOrder ?? this.sortOrder,
    lockMode: lockMode ?? this.lockMode,
  );

  @override
  bool operator ==(Object other) =>
      other is Folder &&
      other.id == id &&
      other.name == name &&
      other.parentId == parentId &&
      other.icon == icon &&
      other.color == color &&
      other.templateKey == templateKey &&
      other.sortOrder == sortOrder &&
      other.lockMode == lockMode &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    parentId,
    icon,
    color,
    templateKey,
    sortOrder,
    lockMode,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'Folder($id)';
}

/// Recursive totals for a folder (itself plus every visible subfolder).
@immutable
class FolderStats {
  const FolderStats({this.folders = 0, this.documents = 0});

  static const empty = FolderStats();

  final int folders;
  final int documents;

  bool get isEmpty => folders == 0 && documents == 0;

  @override
  bool operator ==(Object other) =>
      other is FolderStats &&
      other.folders == folders &&
      other.documents == documents;

  @override
  int get hashCode => Object.hash(folders, documents);
}

/// One level of the vault: subfolders first, then files.
@immutable
class FolderContents {
  const FolderContents({required this.folders, required this.documents});

  static const empty = FolderContents(folders: [], documents: []);

  final List<Folder> folders;
  final List<Document> documents;

  bool get isEmpty => folders.isEmpty && documents.isEmpty;
}

/// Folder name rules, shared by the UI (inline validation) and the
/// repository (last line of defence).
abstract final class FolderNames {
  static const maxLength = 60;

  /// Normalizes whitespace: trims and collapses runs of spaces.
  static String clean(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Returns an error message, or `null` when [raw] is a valid name next to
  /// [siblingNames] (compared case-insensitively).
  static String? validate(String raw, Iterable<String> siblingNames) {
    final name = clean(raw);
    if (name.isEmpty) return 'Enter a folder name';
    if (name.length > maxLength) {
      return 'Use $maxLength characters or fewer';
    }
    if (RegExp(r'[\x00-\x1F]').hasMatch(name)) {
      return 'Remove special characters';
    }
    final lower = name.toLowerCase();
    if (siblingNames.any((s) => s.toLowerCase() == lower)) {
      return 'A folder with this name already exists here';
    }
    return null;
  }
}

/// In-memory view of every folder, for path, subtree and lock questions.
/// Cheap to build: a vault has at most a few hundred folders.
class FolderTree {
  FolderTree(Iterable<Folder> folders)
    : _byId = {for (final f in folders) f.id: f} {
    for (final f in _byId.values) {
      // A parent that no longer exists is treated as the top level.
      final parent = _byId.containsKey(f.parentId) ? f.parentId : null;
      (_children[parent] ??= []).add(f);
    }
    for (final list in _children.values) {
      list.sort(compareFolders);
    }
  }

  final Map<String, Folder> _byId;
  final Map<String?, List<Folder>> _children = {};

  static int compareFolders(Folder a, Folder b) {
    final order = a.sortOrder.compareTo(b.sortOrder);
    if (order != 0) return order;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  Iterable<Folder> get all => _byId.values;

  Folder? operator [](String? id) => id == null ? null : _byId[id];

  bool contains(String? id) => id != null && _byId.containsKey(id);

  /// Direct subfolders of [parentId] (`null` = top level), sorted.
  List<Folder> children(String? parentId) =>
      _children[contains(parentId) ? parentId : null] ?? const [];

  /// Top level → [id] inclusive. Empty when [id] is unknown. Cycles (which
  /// the repository prevents) are cut rather than looping.
  List<Folder> pathTo(String? id) {
    final path = <Folder>[];
    final seen = <String>{};
    var current = this[id];
    while (current != null && seen.add(current.id)) {
      path.add(current);
      current = this[current.parentId];
    }
    return path.reversed.toList();
  }

  /// True when [id] is [ancestorId] or lies anywhere below it.
  bool isWithin(String id, String ancestorId) =>
      pathTo(id).any((f) => f.id == ancestorId);

  /// [id] and every folder below it.
  Set<String> subtreeIds(String id) {
    final out = <String>{};
    void visit(String fid) {
      if (!out.add(fid)) return;
      for (final c in _children[fid] ?? const <Folder>[]) {
        visit(c.id);
      }
    }

    if (contains(id)) visit(id);
    return out;
  }

  /// Locked folders on the path to [id] (inclusive), outermost first.
  List<Folder> locksOnPath(String? id) => [
    for (final f in pathTo(id))
      if (f.isLocked) f,
  ];

  /// Whether [id] can be opened given the folders unlocked this session:
  /// every locked folder on its path must be unlocked. Subfolders without
  /// their own lock inherit access from an unlocked ancestor.
  bool isAccessible(String? id, Set<String> unlocked) =>
      locksOnPath(id).every((f) => unlocked.contains(f.id));

  /// Folders whose *contents* are hidden: every folder at or below a locked
  /// folder that isn't unlocked. The locked folder itself stays visible (by
  /// name) in its parent.
  Set<String> hiddenContentIds(Set<String> unlocked) {
    final out = <String>{};
    for (final f in _byId.values) {
      if (f.isLocked && !unlocked.contains(f.id)) out.addAll(subtreeIds(f.id));
    }
    return out;
  }

  /// Recursive stats per folder. [directCounts] maps a folder id to the
  /// number of documents directly inside it. Content of folders in [hidden]
  /// is not counted towards any ancestor, so a count never reveals what a
  /// locked folder holds.
  Map<String, FolderStats> stats(
    Map<String?, int> directCounts, {
    Set<String> hidden = const {},
  }) {
    final out = <String, FolderStats>{};
    final visiting = <String>{};
    FolderStats visit(Folder f) {
      final cached = out[f.id];
      if (cached != null) return cached;
      // Defensive: a cycle (prevented by the repository) counts as empty.
      if (!visiting.add(f.id)) return FolderStats.empty;
      var folders = 0;
      var documents = directCounts[f.id] ?? 0;
      for (final c in _children[f.id] ?? const <Folder>[]) {
        folders++;
        if (hidden.contains(c.id)) continue;
        final s = visit(c);
        folders += s.folders;
        documents += s.documents;
      }
      return out[f.id] = FolderStats(folders: folders, documents: documents);
    }

    _byId.values.forEach(visit);
    return out;
  }
}
