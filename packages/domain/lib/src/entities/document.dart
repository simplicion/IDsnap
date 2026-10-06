import 'package:docscan_core/docscan_core.dart';
import 'package:docscan_domain/src/entities/vault.dart';
import 'package:meta/meta.dart';

/// A file in the local library. The display [name] lives in the database; the
/// file on disk is addressed by [relativePath] inside the app's storage.
@immutable
class Document {
  const Document({
    required this.id,
    required this.name,
    required this.format,
    required this.relativePath,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
    this.pageCount,
    this.folderId,
    this.favorite = false,
    this.thumbnailPath,
    this.category,
    this.expiresAt,
    this.slot,
  });

  final String id;
  final String name;
  final DocumentFormat format;
  final String relativePath;
  final int sizeBytes;
  final int? pageCount;
  final String? folderId;
  final bool favorite;
  final String? thumbnailPath;

  /// Vault category; `null` = uncategorized.
  final DocumentCategory? category;

  /// Optional expiry (passports, licences, insurance) for local reminders.
  final DateTime? expiresAt;

  /// [VaultSlot.key] this document fills, if any.
  final String? slot;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get fileName => '$name.${format.extension}';

  Document copyWith({
    String? name,
    int? sizeBytes,
    int? pageCount,
    String? folderId,
    bool clearFolder = false,
    bool? favorite,
    String? thumbnailPath,
    String? relativePath,
    DateTime? updatedAt,
    DocumentCategory? category,
    bool clearCategory = false,
    DateTime? expiresAt,
    bool clearExpiry = false,
    String? slot,
    bool clearSlot = false,
  }) => Document(
    id: id,
    name: name ?? this.name,
    format: format,
    relativePath: relativePath ?? this.relativePath,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    pageCount: pageCount ?? this.pageCount,
    folderId: clearFolder ? null : folderId ?? this.folderId,
    favorite: favorite ?? this.favorite,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    category: clearCategory ? null : category ?? this.category,
    expiresAt: clearExpiry ? null : expiresAt ?? this.expiresAt,
    slot: clearSlot ? null : slot ?? this.slot,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

enum DocumentSort {
  newest('Newest first'),
  oldest('Oldest first'),
  nameAz('Name A–Z'),
  largest('Largest first');

  const DocumentSort(this.label);
  final String label;
}

enum DocumentFilter {
  all('All'),
  pdf('PDFs'),
  images('Images'),
  text('Text'),
  favorites('Favorites');

  const DocumentFilter(this.label);
  final String label;
}

@immutable
class DocumentQuery {
  const DocumentQuery({
    this.search = '',
    this.sort = DocumentSort.newest,
    this.filter = DocumentFilter.all,
    this.folderId,
    this.limit,
    this.category,
  });

  final String search;
  final DocumentSort sort;
  final DocumentFilter filter;

  /// `null` means every folder, except the contents of locked folders
  /// (a lock hides them from global lists such as recents and pickers).
  /// When set, lists exactly that folder's direct documents.
  final String? folderId;
  final int? limit;

  /// `null` means every category.
  final DocumentCategory? category;

  DocumentQuery copyWith({
    String? search,
    DocumentSort? sort,
    DocumentFilter? filter,
    String? folderId,
    bool clearFolder = false,
    DocumentCategory? category,
    bool clearCategory = false,
  }) => DocumentQuery(
    search: search ?? this.search,
    sort: sort ?? this.sort,
    filter: filter ?? this.filter,
    folderId: clearFolder ? null : folderId ?? this.folderId,
    limit: limit,
    category: clearCategory ? null : category ?? this.category,
  );

  @override
  bool operator ==(Object other) =>
      other is DocumentQuery &&
      other.search == search &&
      other.sort == sort &&
      other.filter == filter &&
      other.folderId == folderId &&
      other.limit == limit &&
      other.category == category;

  @override
  int get hashCode =>
      Object.hash(search, sort, filter, folderId, limit, category);
}
