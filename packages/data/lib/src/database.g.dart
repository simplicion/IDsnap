// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $DocumentsTable extends Documents
    with TableInfo<$DocumentsTable, DocumentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _folderIdMeta = const VerificationMeta(
    'folderId',
  );
  @override
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
    'folder_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _thumbnailPathMeta = const VerificationMeta(
    'thumbnailPath',
  );
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
    'thumbnail_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<String> slot = GeneratedColumn<String>(
    'slot',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    format,
    relativePath,
    sizeBytes,
    pageCount,
    folderId,
    favorite,
    thumbnailPath,
    createdAt,
    updatedAt,
    category,
    expiresAt,
    slot,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<DocumentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    }
    if (data.containsKey('folder_id')) {
      context.handle(
        _folderIdMeta,
        folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
        _thumbnailPathMeta,
        thumbnailPath.isAcceptableOrUnknown(
          data['thumbnail_path']!,
          _thumbnailPathMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DocumentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DocumentRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      ),
      folderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_id'],
      ),
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      thumbnailPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumbnail_path'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slot'],
      ),
    );
  }

  @override
  $DocumentsTable createAlias(String alias) {
    return $DocumentsTable(attachedDatabase, alias);
  }
}

class DocumentRow extends DataClass implements Insertable<DocumentRow> {
  final String id;
  final String name;
  final String format;
  final String relativePath;
  final int sizeBytes;
  final int? pageCount;
  final String? folderId;
  final bool favorite;
  final String? thumbnailPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? category;
  final DateTime? expiresAt;
  final String? slot;
  const DocumentRow({
    required this.id,
    required this.name,
    required this.format,
    required this.relativePath,
    required this.sizeBytes,
    this.pageCount,
    this.folderId,
    required this.favorite,
    this.thumbnailPath,
    required this.createdAt,
    required this.updatedAt,
    this.category,
    this.expiresAt,
    this.slot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['format'] = Variable<String>(format);
    map['relative_path'] = Variable<String>(relativePath);
    map['size_bytes'] = Variable<int>(sizeBytes);
    if (!nullToAbsent || pageCount != null) {
      map['page_count'] = Variable<int>(pageCount);
    }
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<String>(folderId);
    }
    map['favorite'] = Variable<bool>(favorite);
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    if (!nullToAbsent || slot != null) {
      map['slot'] = Variable<String>(slot);
    }
    return map;
  }

  DocumentsCompanion toCompanion(bool nullToAbsent) {
    return DocumentsCompanion(
      id: Value(id),
      name: Value(name),
      format: Value(format),
      relativePath: Value(relativePath),
      sizeBytes: Value(sizeBytes),
      pageCount: pageCount == null && nullToAbsent
          ? const Value.absent()
          : Value(pageCount),
      folderId: folderId == null && nullToAbsent
          ? const Value.absent()
          : Value(folderId),
      favorite: Value(favorite),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      slot: slot == null && nullToAbsent ? const Value.absent() : Value(slot),
    );
  }

  factory DocumentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DocumentRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      format: serializer.fromJson<String>(json['format']),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      pageCount: serializer.fromJson<int?>(json['pageCount']),
      folderId: serializer.fromJson<String?>(json['folderId']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      category: serializer.fromJson<String?>(json['category']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      slot: serializer.fromJson<String?>(json['slot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'format': serializer.toJson<String>(format),
      'relativePath': serializer.toJson<String>(relativePath),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'pageCount': serializer.toJson<int?>(pageCount),
      'folderId': serializer.toJson<String?>(folderId),
      'favorite': serializer.toJson<bool>(favorite),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'category': serializer.toJson<String?>(category),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'slot': serializer.toJson<String?>(slot),
    };
  }

  DocumentRow copyWith({
    String? id,
    String? name,
    String? format,
    String? relativePath,
    int? sizeBytes,
    Value<int?> pageCount = const Value.absent(),
    Value<String?> folderId = const Value.absent(),
    bool? favorite,
    Value<String?> thumbnailPath = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<String?> category = const Value.absent(),
    Value<DateTime?> expiresAt = const Value.absent(),
    Value<String?> slot = const Value.absent(),
  }) => DocumentRow(
    id: id ?? this.id,
    name: name ?? this.name,
    format: format ?? this.format,
    relativePath: relativePath ?? this.relativePath,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    pageCount: pageCount.present ? pageCount.value : this.pageCount,
    folderId: folderId.present ? folderId.value : this.folderId,
    favorite: favorite ?? this.favorite,
    thumbnailPath: thumbnailPath.present
        ? thumbnailPath.value
        : this.thumbnailPath,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    category: category.present ? category.value : this.category,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    slot: slot.present ? slot.value : this.slot,
  );
  DocumentRow copyWithCompanion(DocumentsCompanion data) {
    return DocumentRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      format: data.format.present ? data.format.value : this.format,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      category: data.category.present ? data.category.value : this.category,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      slot: data.slot.present ? data.slot.value : this.slot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DocumentRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('format: $format, ')
          ..write('relativePath: $relativePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('pageCount: $pageCount, ')
          ..write('folderId: $folderId, ')
          ..write('favorite: $favorite, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('category: $category, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('slot: $slot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    format,
    relativePath,
    sizeBytes,
    pageCount,
    folderId,
    favorite,
    thumbnailPath,
    createdAt,
    updatedAt,
    category,
    expiresAt,
    slot,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DocumentRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.format == this.format &&
          other.relativePath == this.relativePath &&
          other.sizeBytes == this.sizeBytes &&
          other.pageCount == this.pageCount &&
          other.folderId == this.folderId &&
          other.favorite == this.favorite &&
          other.thumbnailPath == this.thumbnailPath &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.category == this.category &&
          other.expiresAt == this.expiresAt &&
          other.slot == this.slot);
}

class DocumentsCompanion extends UpdateCompanion<DocumentRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> format;
  final Value<String> relativePath;
  final Value<int> sizeBytes;
  final Value<int?> pageCount;
  final Value<String?> folderId;
  final Value<bool> favorite;
  final Value<String?> thumbnailPath;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<String?> category;
  final Value<DateTime?> expiresAt;
  final Value<String?> slot;
  final Value<int> rowid;
  const DocumentsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.format = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.folderId = const Value.absent(),
    this.favorite = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.category = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.slot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DocumentsCompanion.insert({
    required String id,
    required String name,
    required String format,
    required String relativePath,
    required int sizeBytes,
    this.pageCount = const Value.absent(),
    this.folderId = const Value.absent(),
    this.favorite = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.category = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.slot = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       format = Value(format),
       relativePath = Value(relativePath),
       sizeBytes = Value(sizeBytes),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DocumentRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? format,
    Expression<String>? relativePath,
    Expression<int>? sizeBytes,
    Expression<int>? pageCount,
    Expression<String>? folderId,
    Expression<bool>? favorite,
    Expression<String>? thumbnailPath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<String>? category,
    Expression<DateTime>? expiresAt,
    Expression<String>? slot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (format != null) 'format': format,
      if (relativePath != null) 'relative_path': relativePath,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (pageCount != null) 'page_count': pageCount,
      if (folderId != null) 'folder_id': folderId,
      if (favorite != null) 'favorite': favorite,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (category != null) 'category': category,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (slot != null) 'slot': slot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DocumentsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? format,
    Value<String>? relativePath,
    Value<int>? sizeBytes,
    Value<int?>? pageCount,
    Value<String?>? folderId,
    Value<bool>? favorite,
    Value<String?>? thumbnailPath,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<String?>? category,
    Value<DateTime?>? expiresAt,
    Value<String?>? slot,
    Value<int>? rowid,
  }) {
    return DocumentsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      format: format ?? this.format,
      relativePath: relativePath ?? this.relativePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      pageCount: pageCount ?? this.pageCount,
      folderId: folderId ?? this.folderId,
      favorite: favorite ?? this.favorite,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      category: category ?? this.category,
      expiresAt: expiresAt ?? this.expiresAt,
      slot: slot ?? this.slot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<String>(folderId.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (slot.present) {
      map['slot'] = Variable<String>(slot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('format: $format, ')
          ..write('relativePath: $relativePath, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('pageCount: $pageCount, ')
          ..write('folderId: $folderId, ')
          ..write('favorite: $favorite, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('category: $category, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('slot: $slot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FoldersTable extends Folders with TableInfo<$FoldersTable, FolderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _systemKeyMeta = const VerificationMeta(
    'systemKey',
  );
  @override
  late final GeneratedColumn<String> systemKey = GeneratedColumn<String>(
    'system_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES folders (id)',
    ),
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _templateKeyMeta = const VerificationMeta(
    'templateKey',
  );
  @override
  late final GeneratedColumn<String> templateKey = GeneratedColumn<String>(
    'template_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lockModeMeta = const VerificationMeta(
    'lockMode',
  );
  @override
  late final GeneratedColumn<String> lockMode = GeneratedColumn<String>(
    'lock_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    createdAt,
    systemKey,
    parentId,
    icon,
    color,
    templateKey,
    sortOrder,
    lockMode,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders';
  @override
  VerificationContext validateIntegrity(
    Insertable<FolderRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('system_key')) {
      context.handle(
        _systemKeyMeta,
        systemKey.isAcceptableOrUnknown(data['system_key']!, _systemKeyMeta),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('template_key')) {
      context.handle(
        _templateKeyMeta,
        templateKey.isAcceptableOrUnknown(
          data['template_key']!,
          _templateKeyMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('lock_mode')) {
      context.handle(
        _lockModeMeta,
        lockMode.isAcceptableOrUnknown(data['lock_mode']!, _lockModeMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FolderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FolderRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      systemKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}system_key'],
      ),
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      ),
      templateKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_key'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      lockMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lock_mode'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $FoldersTable createAlias(String alias) {
    return $FoldersTable(attachedDatabase, alias);
  }
}

class FolderRow extends DataClass implements Insertable<FolderRow> {
  final String id;
  final String name;
  final DateTime createdAt;
  final String? systemKey;

  /// Parent folder (`null` = top level). The repository cascades deletes
  /// and prevents cycles.
  final String? parentId;

  /// `FolderIcons` key; `null` = default icon.
  final String? icon;

  /// `FolderColors` key; `null` = theme accent.
  final String? color;

  /// `FolderTemplate.key` the folder was created from.
  final String? templateKey;
  final int sortOrder;

  /// `FolderLockMode.name`. A PIN's salted hash lives in the platform
  /// keystore, never here.
  final String lockMode;
  final DateTime? updatedAt;
  const FolderRow({
    required this.id,
    required this.name,
    required this.createdAt,
    this.systemKey,
    this.parentId,
    this.icon,
    this.color,
    this.templateKey,
    required this.sortOrder,
    required this.lockMode,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || systemKey != null) {
      map['system_key'] = Variable<String>(systemKey);
    }
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    if (!nullToAbsent || icon != null) {
      map['icon'] = Variable<String>(icon);
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<String>(color);
    }
    if (!nullToAbsent || templateKey != null) {
      map['template_key'] = Variable<String>(templateKey);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['lock_mode'] = Variable<String>(lockMode);
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  FoldersCompanion toCompanion(bool nullToAbsent) {
    return FoldersCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
      systemKey: systemKey == null && nullToAbsent
          ? const Value.absent()
          : Value(systemKey),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      icon: icon == null && nullToAbsent ? const Value.absent() : Value(icon),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      templateKey: templateKey == null && nullToAbsent
          ? const Value.absent()
          : Value(templateKey),
      sortOrder: Value(sortOrder),
      lockMode: Value(lockMode),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory FolderRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FolderRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      systemKey: serializer.fromJson<String?>(json['systemKey']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      icon: serializer.fromJson<String?>(json['icon']),
      color: serializer.fromJson<String?>(json['color']),
      templateKey: serializer.fromJson<String?>(json['templateKey']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      lockMode: serializer.fromJson<String>(json['lockMode']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'systemKey': serializer.toJson<String?>(systemKey),
      'parentId': serializer.toJson<String?>(parentId),
      'icon': serializer.toJson<String?>(icon),
      'color': serializer.toJson<String?>(color),
      'templateKey': serializer.toJson<String?>(templateKey),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'lockMode': serializer.toJson<String>(lockMode),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  FolderRow copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    Value<String?> systemKey = const Value.absent(),
    Value<String?> parentId = const Value.absent(),
    Value<String?> icon = const Value.absent(),
    Value<String?> color = const Value.absent(),
    Value<String?> templateKey = const Value.absent(),
    int? sortOrder,
    String? lockMode,
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => FolderRow(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
    systemKey: systemKey.present ? systemKey.value : this.systemKey,
    parentId: parentId.present ? parentId.value : this.parentId,
    icon: icon.present ? icon.value : this.icon,
    color: color.present ? color.value : this.color,
    templateKey: templateKey.present ? templateKey.value : this.templateKey,
    sortOrder: sortOrder ?? this.sortOrder,
    lockMode: lockMode ?? this.lockMode,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  FolderRow copyWithCompanion(FoldersCompanion data) {
    return FolderRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      systemKey: data.systemKey.present ? data.systemKey.value : this.systemKey,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      icon: data.icon.present ? data.icon.value : this.icon,
      color: data.color.present ? data.color.value : this.color,
      templateKey: data.templateKey.present
          ? data.templateKey.value
          : this.templateKey,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      lockMode: data.lockMode.present ? data.lockMode.value : this.lockMode,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FolderRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('systemKey: $systemKey, ')
          ..write('parentId: $parentId, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('templateKey: $templateKey, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('lockMode: $lockMode, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    createdAt,
    systemKey,
    parentId,
    icon,
    color,
    templateKey,
    sortOrder,
    lockMode,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FolderRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.systemKey == this.systemKey &&
          other.parentId == this.parentId &&
          other.icon == this.icon &&
          other.color == this.color &&
          other.templateKey == this.templateKey &&
          other.sortOrder == this.sortOrder &&
          other.lockMode == this.lockMode &&
          other.updatedAt == this.updatedAt);
}

class FoldersCompanion extends UpdateCompanion<FolderRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<String?> systemKey;
  final Value<String?> parentId;
  final Value<String?> icon;
  final Value<String?> color;
  final Value<String?> templateKey;
  final Value<int> sortOrder;
  final Value<String> lockMode;
  final Value<DateTime?> updatedAt;
  final Value<int> rowid;
  const FoldersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.systemKey = const Value.absent(),
    this.parentId = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.templateKey = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.lockMode = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoldersCompanion.insert({
    required String id,
    required String name,
    required DateTime createdAt,
    this.systemKey = const Value.absent(),
    this.parentId = const Value.absent(),
    this.icon = const Value.absent(),
    this.color = const Value.absent(),
    this.templateKey = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.lockMode = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<FolderRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
    Expression<String>? systemKey,
    Expression<String>? parentId,
    Expression<String>? icon,
    Expression<String>? color,
    Expression<String>? templateKey,
    Expression<int>? sortOrder,
    Expression<String>? lockMode,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (systemKey != null) 'system_key': systemKey,
      if (parentId != null) 'parent_id': parentId,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (templateKey != null) 'template_key': templateKey,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (lockMode != null) 'lock_mode': lockMode,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoldersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
    Value<String?>? systemKey,
    Value<String?>? parentId,
    Value<String?>? icon,
    Value<String?>? color,
    Value<String?>? templateKey,
    Value<int>? sortOrder,
    Value<String>? lockMode,
    Value<DateTime?>? updatedAt,
    Value<int>? rowid,
  }) {
    return FoldersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      systemKey: systemKey ?? this.systemKey,
      parentId: parentId ?? this.parentId,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      templateKey: templateKey ?? this.templateKey,
      sortOrder: sortOrder ?? this.sortOrder,
      lockMode: lockMode ?? this.lockMode,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (systemKey.present) {
      map['system_key'] = Variable<String>(systemKey.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (templateKey.present) {
      map['template_key'] = Variable<String>(templateKey.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (lockMode.present) {
      map['lock_mode'] = Variable<String>(lockMode.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('systemKey: $systemKey, ')
          ..write('parentId: $parentId, ')
          ..write('icon: $icon, ')
          ..write('color: $color, ')
          ..write('templateKey: $templateKey, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('lockMode: $lockMode, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TotpAccountsTable extends TotpAccounts
    with TableInfo<$TotpAccountsTable, TotpAccountRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TotpAccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _issuerMeta = const VerificationMeta('issuer');
  @override
  late final GeneratedColumn<String> issuer = GeneratedColumn<String>(
    'issuer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _secretKeyIdMeta = const VerificationMeta(
    'secretKeyId',
  );
  @override
  late final GeneratedColumn<String> secretKeyId = GeneratedColumn<String>(
    'secret_key_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _digitsMeta = const VerificationMeta('digits');
  @override
  late final GeneratedColumn<int> digits = GeneratedColumn<int>(
    'digits',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(6),
  );
  static const VerificationMeta _periodMeta = const VerificationMeta('period');
  @override
  late final GeneratedColumn<int> period = GeneratedColumn<int>(
    'period',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(30),
  );
  static const VerificationMeta _algorithmMeta = const VerificationMeta(
    'algorithm',
  );
  @override
  late final GeneratedColumn<String> algorithm = GeneratedColumn<String>(
    'algorithm',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('sha1'),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('totp'),
  );
  static const VerificationMeta _counterMeta = const VerificationMeta(
    'counter',
  );
  @override
  late final GeneratedColumn<int> counter = GeneratedColumn<int>(
    'counter',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    label,
    issuer,
    secretKeyId,
    digits,
    period,
    algorithm,
    type,
    counter,
    sortOrder,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'totp_accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<TotpAccountRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('issuer')) {
      context.handle(
        _issuerMeta,
        issuer.isAcceptableOrUnknown(data['issuer']!, _issuerMeta),
      );
    }
    if (data.containsKey('secret_key_id')) {
      context.handle(
        _secretKeyIdMeta,
        secretKeyId.isAcceptableOrUnknown(
          data['secret_key_id']!,
          _secretKeyIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_secretKeyIdMeta);
    }
    if (data.containsKey('digits')) {
      context.handle(
        _digitsMeta,
        digits.isAcceptableOrUnknown(data['digits']!, _digitsMeta),
      );
    }
    if (data.containsKey('period')) {
      context.handle(
        _periodMeta,
        period.isAcceptableOrUnknown(data['period']!, _periodMeta),
      );
    }
    if (data.containsKey('algorithm')) {
      context.handle(
        _algorithmMeta,
        algorithm.isAcceptableOrUnknown(data['algorithm']!, _algorithmMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('counter')) {
      context.handle(
        _counterMeta,
        counter.isAcceptableOrUnknown(data['counter']!, _counterMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TotpAccountRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TotpAccountRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      issuer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}issuer'],
      ),
      secretKeyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}secret_key_id'],
      )!,
      digits: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}digits'],
      )!,
      period: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}period'],
      )!,
      algorithm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}algorithm'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      counter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}counter'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $TotpAccountsTable createAlias(String alias) {
    return $TotpAccountsTable(attachedDatabase, alias);
  }
}

class TotpAccountRow extends DataClass implements Insertable<TotpAccountRow> {
  final String id;
  final String label;
  final String? issuer;

  /// flutter_secure_storage key of the Base32 secret.
  final String secretKeyId;
  final int digits;
  final int period;
  final String algorithm;

  /// `totp` or `hotp`.
  final String type;

  /// HOTP moving factor (unused for TOTP).
  final int counter;
  final int sortOrder;
  final DateTime createdAt;
  const TotpAccountRow({
    required this.id,
    required this.label,
    this.issuer,
    required this.secretKeyId,
    required this.digits,
    required this.period,
    required this.algorithm,
    required this.type,
    required this.counter,
    required this.sortOrder,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['label'] = Variable<String>(label);
    if (!nullToAbsent || issuer != null) {
      map['issuer'] = Variable<String>(issuer);
    }
    map['secret_key_id'] = Variable<String>(secretKeyId);
    map['digits'] = Variable<int>(digits);
    map['period'] = Variable<int>(period);
    map['algorithm'] = Variable<String>(algorithm);
    map['type'] = Variable<String>(type);
    map['counter'] = Variable<int>(counter);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  TotpAccountsCompanion toCompanion(bool nullToAbsent) {
    return TotpAccountsCompanion(
      id: Value(id),
      label: Value(label),
      issuer: issuer == null && nullToAbsent
          ? const Value.absent()
          : Value(issuer),
      secretKeyId: Value(secretKeyId),
      digits: Value(digits),
      period: Value(period),
      algorithm: Value(algorithm),
      type: Value(type),
      counter: Value(counter),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
    );
  }

  factory TotpAccountRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TotpAccountRow(
      id: serializer.fromJson<String>(json['id']),
      label: serializer.fromJson<String>(json['label']),
      issuer: serializer.fromJson<String?>(json['issuer']),
      secretKeyId: serializer.fromJson<String>(json['secretKeyId']),
      digits: serializer.fromJson<int>(json['digits']),
      period: serializer.fromJson<int>(json['period']),
      algorithm: serializer.fromJson<String>(json['algorithm']),
      type: serializer.fromJson<String>(json['type']),
      counter: serializer.fromJson<int>(json['counter']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'label': serializer.toJson<String>(label),
      'issuer': serializer.toJson<String?>(issuer),
      'secretKeyId': serializer.toJson<String>(secretKeyId),
      'digits': serializer.toJson<int>(digits),
      'period': serializer.toJson<int>(period),
      'algorithm': serializer.toJson<String>(algorithm),
      'type': serializer.toJson<String>(type),
      'counter': serializer.toJson<int>(counter),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  TotpAccountRow copyWith({
    String? id,
    String? label,
    Value<String?> issuer = const Value.absent(),
    String? secretKeyId,
    int? digits,
    int? period,
    String? algorithm,
    String? type,
    int? counter,
    int? sortOrder,
    DateTime? createdAt,
  }) => TotpAccountRow(
    id: id ?? this.id,
    label: label ?? this.label,
    issuer: issuer.present ? issuer.value : this.issuer,
    secretKeyId: secretKeyId ?? this.secretKeyId,
    digits: digits ?? this.digits,
    period: period ?? this.period,
    algorithm: algorithm ?? this.algorithm,
    type: type ?? this.type,
    counter: counter ?? this.counter,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
  );
  TotpAccountRow copyWithCompanion(TotpAccountsCompanion data) {
    return TotpAccountRow(
      id: data.id.present ? data.id.value : this.id,
      label: data.label.present ? data.label.value : this.label,
      issuer: data.issuer.present ? data.issuer.value : this.issuer,
      secretKeyId: data.secretKeyId.present
          ? data.secretKeyId.value
          : this.secretKeyId,
      digits: data.digits.present ? data.digits.value : this.digits,
      period: data.period.present ? data.period.value : this.period,
      algorithm: data.algorithm.present ? data.algorithm.value : this.algorithm,
      type: data.type.present ? data.type.value : this.type,
      counter: data.counter.present ? data.counter.value : this.counter,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TotpAccountRow(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('issuer: $issuer, ')
          ..write('secretKeyId: $secretKeyId, ')
          ..write('digits: $digits, ')
          ..write('period: $period, ')
          ..write('algorithm: $algorithm, ')
          ..write('type: $type, ')
          ..write('counter: $counter, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    label,
    issuer,
    secretKeyId,
    digits,
    period,
    algorithm,
    type,
    counter,
    sortOrder,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TotpAccountRow &&
          other.id == this.id &&
          other.label == this.label &&
          other.issuer == this.issuer &&
          other.secretKeyId == this.secretKeyId &&
          other.digits == this.digits &&
          other.period == this.period &&
          other.algorithm == this.algorithm &&
          other.type == this.type &&
          other.counter == this.counter &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt);
}

class TotpAccountsCompanion extends UpdateCompanion<TotpAccountRow> {
  final Value<String> id;
  final Value<String> label;
  final Value<String?> issuer;
  final Value<String> secretKeyId;
  final Value<int> digits;
  final Value<int> period;
  final Value<String> algorithm;
  final Value<String> type;
  final Value<int> counter;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const TotpAccountsCompanion({
    this.id = const Value.absent(),
    this.label = const Value.absent(),
    this.issuer = const Value.absent(),
    this.secretKeyId = const Value.absent(),
    this.digits = const Value.absent(),
    this.period = const Value.absent(),
    this.algorithm = const Value.absent(),
    this.type = const Value.absent(),
    this.counter = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TotpAccountsCompanion.insert({
    required String id,
    required String label,
    this.issuer = const Value.absent(),
    required String secretKeyId,
    this.digits = const Value.absent(),
    this.period = const Value.absent(),
    this.algorithm = const Value.absent(),
    this.type = const Value.absent(),
    this.counter = const Value.absent(),
    this.sortOrder = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       label = Value(label),
       secretKeyId = Value(secretKeyId),
       createdAt = Value(createdAt);
  static Insertable<TotpAccountRow> custom({
    Expression<String>? id,
    Expression<String>? label,
    Expression<String>? issuer,
    Expression<String>? secretKeyId,
    Expression<int>? digits,
    Expression<int>? period,
    Expression<String>? algorithm,
    Expression<String>? type,
    Expression<int>? counter,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (label != null) 'label': label,
      if (issuer != null) 'issuer': issuer,
      if (secretKeyId != null) 'secret_key_id': secretKeyId,
      if (digits != null) 'digits': digits,
      if (period != null) 'period': period,
      if (algorithm != null) 'algorithm': algorithm,
      if (type != null) 'type': type,
      if (counter != null) 'counter': counter,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TotpAccountsCompanion copyWith({
    Value<String>? id,
    Value<String>? label,
    Value<String?>? issuer,
    Value<String>? secretKeyId,
    Value<int>? digits,
    Value<int>? period,
    Value<String>? algorithm,
    Value<String>? type,
    Value<int>? counter,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return TotpAccountsCompanion(
      id: id ?? this.id,
      label: label ?? this.label,
      issuer: issuer ?? this.issuer,
      secretKeyId: secretKeyId ?? this.secretKeyId,
      digits: digits ?? this.digits,
      period: period ?? this.period,
      algorithm: algorithm ?? this.algorithm,
      type: type ?? this.type,
      counter: counter ?? this.counter,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (issuer.present) {
      map['issuer'] = Variable<String>(issuer.value);
    }
    if (secretKeyId.present) {
      map['secret_key_id'] = Variable<String>(secretKeyId.value);
    }
    if (digits.present) {
      map['digits'] = Variable<int>(digits.value);
    }
    if (period.present) {
      map['period'] = Variable<int>(period.value);
    }
    if (algorithm.present) {
      map['algorithm'] = Variable<String>(algorithm.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (counter.present) {
      map['counter'] = Variable<int>(counter.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TotpAccountsCompanion(')
          ..write('id: $id, ')
          ..write('label: $label, ')
          ..write('issuer: $issuer, ')
          ..write('secretKeyId: $secretKeyId, ')
          ..write('digits: $digits, ')
          ..write('period: $period, ')
          ..write('algorithm: $algorithm, ')
          ..write('type: $type, ')
          ..write('counter: $counter, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NotesTable extends Notes with TableInfo<$NotesTable, NoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _tagMeta = const VerificationMeta('tag');
  @override
  late final GeneratedColumn<String> tag = GeneratedColumn<String>(
    'tag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _templateMeta = const VerificationMeta(
    'template',
  );
  @override
  late final GeneratedColumn<String> template = GeneratedColumn<String>(
    'template',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('custom'),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lockModeMeta = const VerificationMeta(
    'lockMode',
  );
  @override
  late final GeneratedColumn<String> lockMode = GeneratedColumn<String>(
    'lock_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    body,
    tag,
    template,
    pinned,
    lockMode,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('tag')) {
      context.handle(
        _tagMeta,
        tag.isAcceptableOrUnknown(data['tag']!, _tagMeta),
      );
    }
    if (data.containsKey('template')) {
      context.handle(
        _templateMeta,
        template.isAcceptableOrUnknown(data['template']!, _templateMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('lock_mode')) {
      context.handle(
        _lockModeMeta,
        lockMode.isAcceptableOrUnknown(data['lock_mode']!, _lockModeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      tag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag'],
      ),
      template: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      lockMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lock_mode'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }
}

class NoteRow extends DataClass implements Insertable<NoteRow> {
  final String id;
  final String title;

  /// Plain text; `- [ ] ` / `- [x] ` lines are checklist items.
  final String body;

  /// Optional category / folder tag.
  final String? tag;

  /// `NoteTemplate.name`.
  final String template;
  final bool pinned;

  /// `FolderLockMode.name`. A PIN's salted hash lives in the keystore.
  final String lockMode;
  final DateTime createdAt;
  final DateTime updatedAt;
  const NoteRow({
    required this.id,
    required this.title,
    required this.body,
    this.tag,
    required this.template,
    required this.pinned,
    required this.lockMode,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || tag != null) {
      map['tag'] = Variable<String>(tag);
    }
    map['template'] = Variable<String>(template);
    map['pinned'] = Variable<bool>(pinned);
    map['lock_mode'] = Variable<String>(lockMode);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      title: Value(title),
      body: Value(body),
      tag: tag == null && nullToAbsent ? const Value.absent() : Value(tag),
      template: Value(template),
      pinned: Value(pinned),
      lockMode: Value(lockMode),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory NoteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      tag: serializer.fromJson<String?>(json['tag']),
      template: serializer.fromJson<String>(json['template']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      lockMode: serializer.fromJson<String>(json['lockMode']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'tag': serializer.toJson<String?>(tag),
      'template': serializer.toJson<String>(template),
      'pinned': serializer.toJson<bool>(pinned),
      'lockMode': serializer.toJson<String>(lockMode),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  NoteRow copyWith({
    String? id,
    String? title,
    String? body,
    Value<String?> tag = const Value.absent(),
    String? template,
    bool? pinned,
    String? lockMode,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => NoteRow(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    tag: tag.present ? tag.value : this.tag,
    template: template ?? this.template,
    pinned: pinned ?? this.pinned,
    lockMode: lockMode ?? this.lockMode,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  NoteRow copyWithCompanion(NotesCompanion data) {
    return NoteRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      tag: data.tag.present ? data.tag.value : this.tag,
      template: data.template.present ? data.template.value : this.template,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      lockMode: data.lockMode.present ? data.lockMode.value : this.lockMode,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('tag: $tag, ')
          ..write('template: $template, ')
          ..write('pinned: $pinned, ')
          ..write('lockMode: $lockMode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

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
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.body == this.body &&
          other.tag == this.tag &&
          other.template == this.template &&
          other.pinned == this.pinned &&
          other.lockMode == this.lockMode &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class NotesCompanion extends UpdateCompanion<NoteRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> body;
  final Value<String?> tag;
  final Value<String> template;
  final Value<bool> pinned;
  final Value<String> lockMode;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.tag = const Value.absent(),
    this.template = const Value.absent(),
    this.pinned = const Value.absent(),
    this.lockMode = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotesCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.tag = const Value.absent(),
    this.template = const Value.absent(),
    this.pinned = const Value.absent(),
    this.lockMode = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<NoteRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? body,
    Expression<String>? tag,
    Expression<String>? template,
    Expression<bool>? pinned,
    Expression<String>? lockMode,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (tag != null) 'tag': tag,
      if (template != null) 'template': template,
      if (pinned != null) 'pinned': pinned,
      if (lockMode != null) 'lock_mode': lockMode,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotesCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? body,
    Value<String?>? tag,
    Value<String>? template,
    Value<bool>? pinned,
    Value<String>? lockMode,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return NotesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      tag: tag ?? this.tag,
      template: template ?? this.template,
      pinned: pinned ?? this.pinned,
      lockMode: lockMode ?? this.lockMode,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (tag.present) {
      map['tag'] = Variable<String>(tag.value);
    }
    if (template.present) {
      map['template'] = Variable<String>(template.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (lockMode.present) {
      map['lock_mode'] = Variable<String>(lockMode.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('tag: $tag, ')
          ..write('template: $template, ')
          ..write('pinned: $pinned, ')
          ..write('lockMode: $lockMode, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DocumentsTable documents = $DocumentsTable(this);
  late final $FoldersTable folders = $FoldersTable(this);
  late final $TotpAccountsTable totpAccounts = $TotpAccountsTable(this);
  late final $NotesTable notes = $NotesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    documents,
    folders,
    totpAccounts,
    notes,
  ];
}

typedef $$DocumentsTableCreateCompanionBuilder =
    DocumentsCompanion Function({
      required String id,
      required String name,
      required String format,
      required String relativePath,
      required int sizeBytes,
      Value<int?> pageCount,
      Value<String?> folderId,
      Value<bool> favorite,
      Value<String?> thumbnailPath,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<String?> category,
      Value<DateTime?> expiresAt,
      Value<String?> slot,
      Value<int> rowid,
    });
typedef $$DocumentsTableUpdateCompanionBuilder =
    DocumentsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> format,
      Value<String> relativePath,
      Value<int> sizeBytes,
      Value<int?> pageCount,
      Value<String?> folderId,
      Value<bool> favorite,
      Value<String?> thumbnailPath,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<String?> category,
      Value<DateTime?> expiresAt,
      Value<String?> slot,
      Value<int> rowid,
    });

class $$DocumentsTableFilterComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DocumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderId => $composableBuilder(
    column: $table.folderId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DocumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DocumentsTable> {
  $$DocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<String> get folderId =>
      $composableBuilder(column: $table.folderId, builder: (column) => column);

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
    column: $table.thumbnailPath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<String> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);
}

class $$DocumentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DocumentsTable,
          DocumentRow,
          $$DocumentsTableFilterComposer,
          $$DocumentsTableOrderingComposer,
          $$DocumentsTableAnnotationComposer,
          $$DocumentsTableCreateCompanionBuilder,
          $$DocumentsTableUpdateCompanionBuilder,
          (
            DocumentRow,
            BaseReferences<_$AppDatabase, $DocumentsTable, DocumentRow>,
          ),
          DocumentRow,
          PrefetchHooks Function()
        > {
  $$DocumentsTableTableManager(_$AppDatabase db, $DocumentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<int?> pageCount = const Value.absent(),
                Value<String?> folderId = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<String?> slot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocumentsCompanion(
                id: id,
                name: name,
                format: format,
                relativePath: relativePath,
                sizeBytes: sizeBytes,
                pageCount: pageCount,
                folderId: folderId,
                favorite: favorite,
                thumbnailPath: thumbnailPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                category: category,
                expiresAt: expiresAt,
                slot: slot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String format,
                required String relativePath,
                required int sizeBytes,
                Value<int?> pageCount = const Value.absent(),
                Value<String?> folderId = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<String?> thumbnailPath = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<String?> category = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<String?> slot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocumentsCompanion.insert(
                id: id,
                name: name,
                format: format,
                relativePath: relativePath,
                sizeBytes: sizeBytes,
                pageCount: pageCount,
                folderId: folderId,
                favorite: favorite,
                thumbnailPath: thumbnailPath,
                createdAt: createdAt,
                updatedAt: updatedAt,
                category: category,
                expiresAt: expiresAt,
                slot: slot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DocumentsTable, DocumentRow>(table),
                  BaseReferences<_$AppDatabase, $DocumentsTable, DocumentRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DocumentsTable,
      DocumentRow,
      $$DocumentsTableFilterComposer,
      $$DocumentsTableOrderingComposer,
      $$DocumentsTableAnnotationComposer,
      $$DocumentsTableCreateCompanionBuilder,
      $$DocumentsTableUpdateCompanionBuilder,
      (
        DocumentRow,
        BaseReferences<_$AppDatabase, $DocumentsTable, DocumentRow>,
      ),
      DocumentRow,
      PrefetchHooks Function()
    >;
typedef $$FoldersTableCreateCompanionBuilder =
    FoldersCompanion Function({
      required String id,
      required String name,
      required DateTime createdAt,
      Value<String?> systemKey,
      Value<String?> parentId,
      Value<String?> icon,
      Value<String?> color,
      Value<String?> templateKey,
      Value<int> sortOrder,
      Value<String> lockMode,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });
typedef $$FoldersTableUpdateCompanionBuilder =
    FoldersCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<DateTime> createdAt,
      Value<String?> systemKey,
      Value<String?> parentId,
      Value<String?> icon,
      Value<String?> color,
      Value<String?> templateKey,
      Value<int> sortOrder,
      Value<String> lockMode,
      Value<DateTime?> updatedAt,
      Value<int> rowid,
    });

final class $$FoldersTableReferences
    extends BaseReferences<_$AppDatabase, $FoldersTable, FolderRow> {
  $$FoldersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FoldersTable _parentIdTable(_$AppDatabase db) =>
      db.folders.createAlias('folders__parent_id__folders__id');

  $$FoldersTableProcessedTableManager? get parentId {
    final $_column = $_itemColumn<String>('parent_id');
    if ($_column == null) return null;
    final manager = $$FoldersTableTableManager(
      $_db,
      $_db.folders,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FoldersTableFilterComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get systemKey => $composableBuilder(
    column: $table.systemKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get templateKey => $composableBuilder(
    column: $table.templateKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lockMode => $composableBuilder(
    column: $table.lockMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$FoldersTableFilterComposer get parentId {
    final $$FoldersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableFilterComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoldersTableOrderingComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get systemKey => $composableBuilder(
    column: $table.systemKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get templateKey => $composableBuilder(
    column: $table.templateKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lockMode => $composableBuilder(
    column: $table.lockMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$FoldersTableOrderingComposer get parentId {
    final $$FoldersTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableOrderingComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoldersTableAnnotationComposer
    extends Composer<_$AppDatabase, $FoldersTable> {
  $$FoldersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get systemKey =>
      $composableBuilder(column: $table.systemKey, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get templateKey => $composableBuilder(
    column: $table.templateKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<String> get lockMode =>
      $composableBuilder(column: $table.lockMode, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$FoldersTableAnnotationComposer get parentId {
    final $$FoldersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.parentId,
      referencedTable: $db.folders,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FoldersTableAnnotationComposer(
            $db: $db,
            $table: $db.folders,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FoldersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FoldersTable,
          FolderRow,
          $$FoldersTableFilterComposer,
          $$FoldersTableOrderingComposer,
          $$FoldersTableAnnotationComposer,
          $$FoldersTableCreateCompanionBuilder,
          $$FoldersTableUpdateCompanionBuilder,
          (FolderRow, $$FoldersTableReferences),
          FolderRow,
          PrefetchHooks Function({bool parentId})
        > {
  $$FoldersTableTableManager(_$AppDatabase db, $FoldersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoldersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoldersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoldersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> systemKey = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<String?> templateKey = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> lockMode = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
                systemKey: systemKey,
                parentId: parentId,
                icon: icon,
                color: color,
                templateKey: templateKey,
                sortOrder: sortOrder,
                lockMode: lockMode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required DateTime createdAt,
                Value<String?> systemKey = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String?> icon = const Value.absent(),
                Value<String?> color = const Value.absent(),
                Value<String?> templateKey = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<String> lockMode = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoldersCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
                systemKey: systemKey,
                parentId: parentId,
                icon: icon,
                color: color,
                templateKey: templateKey,
                sortOrder: sortOrder,
                lockMode: lockMode,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FoldersTable, FolderRow>(table),
                  $$FoldersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({parentId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (parentId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.parentId,
                                referencedTable: $$FoldersTableReferences
                                    ._parentIdTable(db),
                                referencedColumn: $$FoldersTableReferences
                                    ._parentIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FoldersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FoldersTable,
      FolderRow,
      $$FoldersTableFilterComposer,
      $$FoldersTableOrderingComposer,
      $$FoldersTableAnnotationComposer,
      $$FoldersTableCreateCompanionBuilder,
      $$FoldersTableUpdateCompanionBuilder,
      (FolderRow, $$FoldersTableReferences),
      FolderRow,
      PrefetchHooks Function({bool parentId})
    >;
typedef $$TotpAccountsTableCreateCompanionBuilder =
    TotpAccountsCompanion Function({
      required String id,
      required String label,
      Value<String?> issuer,
      required String secretKeyId,
      Value<int> digits,
      Value<int> period,
      Value<String> algorithm,
      Value<String> type,
      Value<int> counter,
      Value<int> sortOrder,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$TotpAccountsTableUpdateCompanionBuilder =
    TotpAccountsCompanion Function({
      Value<String> id,
      Value<String> label,
      Value<String?> issuer,
      Value<String> secretKeyId,
      Value<int> digits,
      Value<int> period,
      Value<String> algorithm,
      Value<String> type,
      Value<int> counter,
      Value<int> sortOrder,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$TotpAccountsTableFilterComposer
    extends Composer<_$AppDatabase, $TotpAccountsTable> {
  $$TotpAccountsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get issuer => $composableBuilder(
    column: $table.issuer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get secretKeyId => $composableBuilder(
    column: $table.secretKeyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get digits => $composableBuilder(
    column: $table.digits,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get algorithm => $composableBuilder(
    column: $table.algorithm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get counter => $composableBuilder(
    column: $table.counter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TotpAccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $TotpAccountsTable> {
  $$TotpAccountsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get issuer => $composableBuilder(
    column: $table.issuer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get secretKeyId => $composableBuilder(
    column: $table.secretKeyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get digits => $composableBuilder(
    column: $table.digits,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get period => $composableBuilder(
    column: $table.period,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get algorithm => $composableBuilder(
    column: $table.algorithm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get counter => $composableBuilder(
    column: $table.counter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TotpAccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TotpAccountsTable> {
  $$TotpAccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get issuer =>
      $composableBuilder(column: $table.issuer, builder: (column) => column);

  GeneratedColumn<String> get secretKeyId => $composableBuilder(
    column: $table.secretKeyId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get digits =>
      $composableBuilder(column: $table.digits, builder: (column) => column);

  GeneratedColumn<int> get period =>
      $composableBuilder(column: $table.period, builder: (column) => column);

  GeneratedColumn<String> get algorithm =>
      $composableBuilder(column: $table.algorithm, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get counter =>
      $composableBuilder(column: $table.counter, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TotpAccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TotpAccountsTable,
          TotpAccountRow,
          $$TotpAccountsTableFilterComposer,
          $$TotpAccountsTableOrderingComposer,
          $$TotpAccountsTableAnnotationComposer,
          $$TotpAccountsTableCreateCompanionBuilder,
          $$TotpAccountsTableUpdateCompanionBuilder,
          (
            TotpAccountRow,
            BaseReferences<_$AppDatabase, $TotpAccountsTable, TotpAccountRow>,
          ),
          TotpAccountRow,
          PrefetchHooks Function()
        > {
  $$TotpAccountsTableTableManager(_$AppDatabase db, $TotpAccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TotpAccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TotpAccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TotpAccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String?> issuer = const Value.absent(),
                Value<String> secretKeyId = const Value.absent(),
                Value<int> digits = const Value.absent(),
                Value<int> period = const Value.absent(),
                Value<String> algorithm = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> counter = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TotpAccountsCompanion(
                id: id,
                label: label,
                issuer: issuer,
                secretKeyId: secretKeyId,
                digits: digits,
                period: period,
                algorithm: algorithm,
                type: type,
                counter: counter,
                sortOrder: sortOrder,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String label,
                Value<String?> issuer = const Value.absent(),
                required String secretKeyId,
                Value<int> digits = const Value.absent(),
                Value<int> period = const Value.absent(),
                Value<String> algorithm = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> counter = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => TotpAccountsCompanion.insert(
                id: id,
                label: label,
                issuer: issuer,
                secretKeyId: secretKeyId,
                digits: digits,
                period: period,
                algorithm: algorithm,
                type: type,
                counter: counter,
                sortOrder: sortOrder,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TotpAccountsTable, TotpAccountRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $TotpAccountsTable,
                    TotpAccountRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TotpAccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TotpAccountsTable,
      TotpAccountRow,
      $$TotpAccountsTableFilterComposer,
      $$TotpAccountsTableOrderingComposer,
      $$TotpAccountsTableAnnotationComposer,
      $$TotpAccountsTableCreateCompanionBuilder,
      $$TotpAccountsTableUpdateCompanionBuilder,
      (
        TotpAccountRow,
        BaseReferences<_$AppDatabase, $TotpAccountsTable, TotpAccountRow>,
      ),
      TotpAccountRow,
      PrefetchHooks Function()
    >;
typedef $$NotesTableCreateCompanionBuilder =
    NotesCompanion Function({
      required String id,
      Value<String> title,
      Value<String> body,
      Value<String?> tag,
      Value<String> template,
      Value<bool> pinned,
      Value<String> lockMode,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$NotesTableUpdateCompanionBuilder =
    NotesCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> body,
      Value<String?> tag,
      Value<String> template,
      Value<bool> pinned,
      Value<String> lockMode,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$NotesTableFilterComposer extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get template => $composableBuilder(
    column: $table.template,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lockMode => $composableBuilder(
    column: $table.lockMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NotesTableOrderingComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tag => $composableBuilder(
    column: $table.tag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get template => $composableBuilder(
    column: $table.template,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lockMode => $composableBuilder(
    column: $table.lockMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get tag =>
      $composableBuilder(column: $table.tag, builder: (column) => column);

  GeneratedColumn<String> get template =>
      $composableBuilder(column: $table.template, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<String> get lockMode =>
      $composableBuilder(column: $table.lockMode, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$NotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotesTable,
          NoteRow,
          $$NotesTableFilterComposer,
          $$NotesTableOrderingComposer,
          $$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (NoteRow, BaseReferences<_$AppDatabase, $NotesTable, NoteRow>),
          NoteRow,
          PrefetchHooks Function()
        > {
  $$NotesTableTableManager(_$AppDatabase db, $NotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> tag = const Value.absent(),
                Value<String> template = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<String> lockMode = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion(
                id: id,
                title: title,
                body: body,
                tag: tag,
                template: template,
                pinned: pinned,
                lockMode: lockMode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> tag = const Value.absent(),
                Value<String> template = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<String> lockMode = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion.insert(
                id: id,
                title: title,
                body: body,
                tag: tag,
                template: template,
                pinned: pinned,
                lockMode: lockMode,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NotesTable, NoteRow>(table),
                  BaseReferences<_$AppDatabase, $NotesTable, NoteRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotesTable,
      NoteRow,
      $$NotesTableFilterComposer,
      $$NotesTableOrderingComposer,
      $$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (NoteRow, BaseReferences<_$AppDatabase, $NotesTable, NoteRow>),
      NoteRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DocumentsTableTableManager get documents =>
      $$DocumentsTableTableManager(_db, _db.documents);
  $$FoldersTableTableManager get folders =>
      $$FoldersTableTableManager(_db, _db.folders);
  $$TotpAccountsTableTableManager get totpAccounts =>
      $$TotpAccountsTableTableManager(_db, _db.totpAccounts);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
}
