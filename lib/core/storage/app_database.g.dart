// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ReadingStatesTable extends ReadingStates
    with TableInfo<$ReadingStatesTable, ReadingState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workIdMeta = const VerificationMeta('workId');
  @override
  late final GeneratedColumn<String> workId = GeneratedColumn<String>(
    'work_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _libraryKindMeta = const VerificationMeta(
    'libraryKind',
  );
  @override
  late final GeneratedColumn<String> libraryKind = GeneratedColumn<String>(
    'library_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workJsonMeta = const VerificationMeta(
    'workJson',
  );
  @override
  late final GeneratedColumn<String> workJson = GeneratedColumn<String>(
    'work_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterIdMeta = const VerificationMeta(
    'chapterId',
  );
  @override
  late final GeneratedColumn<String> chapterId = GeneratedColumn<String>(
    'chapter_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterTitleMeta = const VerificationMeta(
    'chapterTitle',
  );
  @override
  late final GeneratedColumn<String> chapterTitle = GeneratedColumn<String>(
    'chapter_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterIndexMeta = const VerificationMeta(
    'chapterIndex',
  );
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
    'chapter_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
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
    workId,
    libraryKind,
    workJson,
    chapterId,
    chapterTitle,
    chapterIndex,
    position,
    progress,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('work_id')) {
      context.handle(
        _workIdMeta,
        workId.isAcceptableOrUnknown(data['work_id']!, _workIdMeta),
      );
    } else if (isInserting) {
      context.missing(_workIdMeta);
    }
    if (data.containsKey('library_kind')) {
      context.handle(
        _libraryKindMeta,
        libraryKind.isAcceptableOrUnknown(
          data['library_kind']!,
          _libraryKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_libraryKindMeta);
    }
    if (data.containsKey('work_json')) {
      context.handle(
        _workJsonMeta,
        workJson.isAcceptableOrUnknown(data['work_json']!, _workJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_workJsonMeta);
    }
    if (data.containsKey('chapter_id')) {
      context.handle(
        _chapterIdMeta,
        chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta),
      );
    } else if (isInserting) {
      context.missing(_chapterIdMeta);
    }
    if (data.containsKey('chapter_title')) {
      context.handle(
        _chapterTitleMeta,
        chapterTitle.isAcceptableOrUnknown(
          data['chapter_title']!,
          _chapterTitleMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterTitleMeta);
    }
    if (data.containsKey('chapter_index')) {
      context.handle(
        _chapterIndexMeta,
        chapterIndex.isAcceptableOrUnknown(
          data['chapter_index']!,
          _chapterIndexMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterIndexMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    } else if (isInserting) {
      context.missing(_progressMeta);
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
  Set<GeneratedColumn> get $primaryKey => {workId};
  @override
  ReadingState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingState(
      workId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_id'],
      )!,
      libraryKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}library_kind'],
      )!,
      workJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_json'],
      )!,
      chapterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_id'],
      )!,
      chapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_title'],
      )!,
      chapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_index'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ReadingStatesTable createAlias(String alias) {
    return $ReadingStatesTable(attachedDatabase, alias);
  }
}

class ReadingState extends DataClass implements Insertable<ReadingState> {
  final String workId;
  final String libraryKind;
  final String workJson;
  final String chapterId;
  final String chapterTitle;
  final int chapterIndex;
  final int position;
  final double progress;
  final DateTime updatedAt;
  const ReadingState({
    required this.workId,
    required this.libraryKind,
    required this.workJson,
    required this.chapterId,
    required this.chapterTitle,
    required this.chapterIndex,
    required this.position,
    required this.progress,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['work_id'] = Variable<String>(workId);
    map['library_kind'] = Variable<String>(libraryKind);
    map['work_json'] = Variable<String>(workJson);
    map['chapter_id'] = Variable<String>(chapterId);
    map['chapter_title'] = Variable<String>(chapterTitle);
    map['chapter_index'] = Variable<int>(chapterIndex);
    map['position'] = Variable<int>(position);
    map['progress'] = Variable<double>(progress);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ReadingStatesCompanion toCompanion(bool nullToAbsent) {
    return ReadingStatesCompanion(
      workId: Value(workId),
      libraryKind: Value(libraryKind),
      workJson: Value(workJson),
      chapterId: Value(chapterId),
      chapterTitle: Value(chapterTitle),
      chapterIndex: Value(chapterIndex),
      position: Value(position),
      progress: Value(progress),
      updatedAt: Value(updatedAt),
    );
  }

  factory ReadingState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingState(
      workId: serializer.fromJson<String>(json['workId']),
      libraryKind: serializer.fromJson<String>(json['libraryKind']),
      workJson: serializer.fromJson<String>(json['workJson']),
      chapterId: serializer.fromJson<String>(json['chapterId']),
      chapterTitle: serializer.fromJson<String>(json['chapterTitle']),
      chapterIndex: serializer.fromJson<int>(json['chapterIndex']),
      position: serializer.fromJson<int>(json['position']),
      progress: serializer.fromJson<double>(json['progress']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workId': serializer.toJson<String>(workId),
      'libraryKind': serializer.toJson<String>(libraryKind),
      'workJson': serializer.toJson<String>(workJson),
      'chapterId': serializer.toJson<String>(chapterId),
      'chapterTitle': serializer.toJson<String>(chapterTitle),
      'chapterIndex': serializer.toJson<int>(chapterIndex),
      'position': serializer.toJson<int>(position),
      'progress': serializer.toJson<double>(progress),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ReadingState copyWith({
    String? workId,
    String? libraryKind,
    String? workJson,
    String? chapterId,
    String? chapterTitle,
    int? chapterIndex,
    int? position,
    double? progress,
    DateTime? updatedAt,
  }) => ReadingState(
    workId: workId ?? this.workId,
    libraryKind: libraryKind ?? this.libraryKind,
    workJson: workJson ?? this.workJson,
    chapterId: chapterId ?? this.chapterId,
    chapterTitle: chapterTitle ?? this.chapterTitle,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    position: position ?? this.position,
    progress: progress ?? this.progress,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ReadingState copyWithCompanion(ReadingStatesCompanion data) {
    return ReadingState(
      workId: data.workId.present ? data.workId.value : this.workId,
      libraryKind: data.libraryKind.present
          ? data.libraryKind.value
          : this.libraryKind,
      workJson: data.workJson.present ? data.workJson.value : this.workJson,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      chapterTitle: data.chapterTitle.present
          ? data.chapterTitle.value
          : this.chapterTitle,
      chapterIndex: data.chapterIndex.present
          ? data.chapterIndex.value
          : this.chapterIndex,
      position: data.position.present ? data.position.value : this.position,
      progress: data.progress.present ? data.progress.value : this.progress,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingState(')
          ..write('workId: $workId, ')
          ..write('libraryKind: $libraryKind, ')
          ..write('workJson: $workJson, ')
          ..write('chapterId: $chapterId, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('position: $position, ')
          ..write('progress: $progress, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    workId,
    libraryKind,
    workJson,
    chapterId,
    chapterTitle,
    chapterIndex,
    position,
    progress,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingState &&
          other.workId == this.workId &&
          other.libraryKind == this.libraryKind &&
          other.workJson == this.workJson &&
          other.chapterId == this.chapterId &&
          other.chapterTitle == this.chapterTitle &&
          other.chapterIndex == this.chapterIndex &&
          other.position == this.position &&
          other.progress == this.progress &&
          other.updatedAt == this.updatedAt);
}

class ReadingStatesCompanion extends UpdateCompanion<ReadingState> {
  final Value<String> workId;
  final Value<String> libraryKind;
  final Value<String> workJson;
  final Value<String> chapterId;
  final Value<String> chapterTitle;
  final Value<int> chapterIndex;
  final Value<int> position;
  final Value<double> progress;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ReadingStatesCompanion({
    this.workId = const Value.absent(),
    this.libraryKind = const Value.absent(),
    this.workJson = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.position = const Value.absent(),
    this.progress = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingStatesCompanion.insert({
    required String workId,
    required String libraryKind,
    required String workJson,
    required String chapterId,
    required String chapterTitle,
    required int chapterIndex,
    required int position,
    required double progress,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : workId = Value(workId),
       libraryKind = Value(libraryKind),
       workJson = Value(workJson),
       chapterId = Value(chapterId),
       chapterTitle = Value(chapterTitle),
       chapterIndex = Value(chapterIndex),
       position = Value(position),
       progress = Value(progress),
       updatedAt = Value(updatedAt);
  static Insertable<ReadingState> custom({
    Expression<String>? workId,
    Expression<String>? libraryKind,
    Expression<String>? workJson,
    Expression<String>? chapterId,
    Expression<String>? chapterTitle,
    Expression<int>? chapterIndex,
    Expression<int>? position,
    Expression<double>? progress,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (workId != null) 'work_id': workId,
      if (libraryKind != null) 'library_kind': libraryKind,
      if (workJson != null) 'work_json': workJson,
      if (chapterId != null) 'chapter_id': chapterId,
      if (chapterTitle != null) 'chapter_title': chapterTitle,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (position != null) 'position': position,
      if (progress != null) 'progress': progress,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingStatesCompanion copyWith({
    Value<String>? workId,
    Value<String>? libraryKind,
    Value<String>? workJson,
    Value<String>? chapterId,
    Value<String>? chapterTitle,
    Value<int>? chapterIndex,
    Value<int>? position,
    Value<double>? progress,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ReadingStatesCompanion(
      workId: workId ?? this.workId,
      libraryKind: libraryKind ?? this.libraryKind,
      workJson: workJson ?? this.workJson,
      chapterId: chapterId ?? this.chapterId,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      position: position ?? this.position,
      progress: progress ?? this.progress,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workId.present) {
      map['work_id'] = Variable<String>(workId.value);
    }
    if (libraryKind.present) {
      map['library_kind'] = Variable<String>(libraryKind.value);
    }
    if (workJson.present) {
      map['work_json'] = Variable<String>(workJson.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<String>(chapterId.value);
    }
    if (chapterTitle.present) {
      map['chapter_title'] = Variable<String>(chapterTitle.value);
    }
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
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
    return (StringBuffer('ReadingStatesCompanion(')
          ..write('workId: $workId, ')
          ..write('libraryKind: $libraryKind, ')
          ..write('workJson: $workJson, ')
          ..write('chapterId: $chapterId, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('position: $position, ')
          ..write('progress: $progress, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SearchCachesTable extends SearchCaches
    with TableInfo<$SearchCachesTable, SearchCache> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SearchCachesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _libraryKindMeta = const VerificationMeta(
    'libraryKind',
  );
  @override
  late final GeneratedColumn<String> libraryKind = GeneratedColumn<String>(
    'library_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keywordMeta = const VerificationMeta(
    'keyword',
  );
  @override
  late final GeneratedColumn<String> keyword = GeneratedColumn<String>(
    'keyword',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _worksJsonMeta = const VerificationMeta(
    'worksJson',
  );
  @override
  late final GeneratedColumn<String> worksJson = GeneratedColumn<String>(
    'works_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
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
    cacheKey,
    libraryKind,
    keyword,
    worksJson,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'search_caches';
  @override
  VerificationContext validateIntegrity(
    Insertable<SearchCache> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('library_kind')) {
      context.handle(
        _libraryKindMeta,
        libraryKind.isAcceptableOrUnknown(
          data['library_kind']!,
          _libraryKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_libraryKindMeta);
    }
    if (data.containsKey('keyword')) {
      context.handle(
        _keywordMeta,
        keyword.isAcceptableOrUnknown(data['keyword']!, _keywordMeta),
      );
    } else if (isInserting) {
      context.missing(_keywordMeta);
    }
    if (data.containsKey('works_json')) {
      context.handle(
        _worksJsonMeta,
        worksJson.isAcceptableOrUnknown(data['works_json']!, _worksJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_worksJsonMeta);
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
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  SearchCache map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SearchCache(
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      libraryKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}library_kind'],
      )!,
      keyword: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}keyword'],
      )!,
      worksJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}works_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SearchCachesTable createAlias(String alias) {
    return $SearchCachesTable(attachedDatabase, alias);
  }
}

class SearchCache extends DataClass implements Insertable<SearchCache> {
  final String cacheKey;
  final String libraryKind;
  final String keyword;
  final String worksJson;
  final DateTime updatedAt;
  const SearchCache({
    required this.cacheKey,
    required this.libraryKind,
    required this.keyword,
    required this.worksJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['library_kind'] = Variable<String>(libraryKind);
    map['keyword'] = Variable<String>(keyword);
    map['works_json'] = Variable<String>(worksJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SearchCachesCompanion toCompanion(bool nullToAbsent) {
    return SearchCachesCompanion(
      cacheKey: Value(cacheKey),
      libraryKind: Value(libraryKind),
      keyword: Value(keyword),
      worksJson: Value(worksJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory SearchCache.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SearchCache(
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      libraryKind: serializer.fromJson<String>(json['libraryKind']),
      keyword: serializer.fromJson<String>(json['keyword']),
      worksJson: serializer.fromJson<String>(json['worksJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cacheKey': serializer.toJson<String>(cacheKey),
      'libraryKind': serializer.toJson<String>(libraryKind),
      'keyword': serializer.toJson<String>(keyword),
      'worksJson': serializer.toJson<String>(worksJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SearchCache copyWith({
    String? cacheKey,
    String? libraryKind,
    String? keyword,
    String? worksJson,
    DateTime? updatedAt,
  }) => SearchCache(
    cacheKey: cacheKey ?? this.cacheKey,
    libraryKind: libraryKind ?? this.libraryKind,
    keyword: keyword ?? this.keyword,
    worksJson: worksJson ?? this.worksJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SearchCache copyWithCompanion(SearchCachesCompanion data) {
    return SearchCache(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      libraryKind: data.libraryKind.present
          ? data.libraryKind.value
          : this.libraryKind,
      keyword: data.keyword.present ? data.keyword.value : this.keyword,
      worksJson: data.worksJson.present ? data.worksJson.value : this.worksJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SearchCache(')
          ..write('cacheKey: $cacheKey, ')
          ..write('libraryKind: $libraryKind, ')
          ..write('keyword: $keyword, ')
          ..write('worksJson: $worksJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(cacheKey, libraryKind, keyword, worksJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SearchCache &&
          other.cacheKey == this.cacheKey &&
          other.libraryKind == this.libraryKind &&
          other.keyword == this.keyword &&
          other.worksJson == this.worksJson &&
          other.updatedAt == this.updatedAt);
}

class SearchCachesCompanion extends UpdateCompanion<SearchCache> {
  final Value<String> cacheKey;
  final Value<String> libraryKind;
  final Value<String> keyword;
  final Value<String> worksJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SearchCachesCompanion({
    this.cacheKey = const Value.absent(),
    this.libraryKind = const Value.absent(),
    this.keyword = const Value.absent(),
    this.worksJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SearchCachesCompanion.insert({
    required String cacheKey,
    required String libraryKind,
    required String keyword,
    required String worksJson,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : cacheKey = Value(cacheKey),
       libraryKind = Value(libraryKind),
       keyword = Value(keyword),
       worksJson = Value(worksJson),
       updatedAt = Value(updatedAt);
  static Insertable<SearchCache> custom({
    Expression<String>? cacheKey,
    Expression<String>? libraryKind,
    Expression<String>? keyword,
    Expression<String>? worksJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (libraryKind != null) 'library_kind': libraryKind,
      if (keyword != null) 'keyword': keyword,
      if (worksJson != null) 'works_json': worksJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SearchCachesCompanion copyWith({
    Value<String>? cacheKey,
    Value<String>? libraryKind,
    Value<String>? keyword,
    Value<String>? worksJson,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SearchCachesCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      libraryKind: libraryKind ?? this.libraryKind,
      keyword: keyword ?? this.keyword,
      worksJson: worksJson ?? this.worksJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (libraryKind.present) {
      map['library_kind'] = Variable<String>(libraryKind.value);
    }
    if (keyword.present) {
      map['keyword'] = Variable<String>(keyword.value);
    }
    if (worksJson.present) {
      map['works_json'] = Variable<String>(worksJson.value);
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
    return (StringBuffer('SearchCachesCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('libraryKind: $libraryKind, ')
          ..write('keyword: $keyword, ')
          ..write('worksJson: $worksJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FavoriteCachesTable extends FavoriteCaches
    with TableInfo<$FavoriteCachesTable, FavoriteCache> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoriteCachesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<int> userId = GeneratedColumn<int>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workIdMeta = const VerificationMeta('workId');
  @override
  late final GeneratedColumn<String> workId = GeneratedColumn<String>(
    'work_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workJsonMeta = const VerificationMeta(
    'workJson',
  );
  @override
  late final GeneratedColumn<String> workJson = GeneratedColumn<String>(
    'work_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordsJsonMeta = const VerificationMeta(
    'recordsJson',
  );
  @override
  late final GeneratedColumn<String> recordsJson = GeneratedColumn<String>(
    'records_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
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
    userId,
    workId,
    workJson,
    recordsJson,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'favorite_caches';
  @override
  VerificationContext validateIntegrity(
    Insertable<FavoriteCache> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('work_id')) {
      context.handle(
        _workIdMeta,
        workId.isAcceptableOrUnknown(data['work_id']!, _workIdMeta),
      );
    } else if (isInserting) {
      context.missing(_workIdMeta);
    }
    if (data.containsKey('work_json')) {
      context.handle(
        _workJsonMeta,
        workJson.isAcceptableOrUnknown(data['work_json']!, _workJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_workJsonMeta);
    }
    if (data.containsKey('records_json')) {
      context.handle(
        _recordsJsonMeta,
        recordsJson.isAcceptableOrUnknown(
          data['records_json']!,
          _recordsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordsJsonMeta);
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
  Set<GeneratedColumn> get $primaryKey => {userId, workId};
  @override
  FavoriteCache map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FavoriteCache(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}user_id'],
      )!,
      workId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_id'],
      )!,
      workJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_json'],
      )!,
      recordsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}records_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FavoriteCachesTable createAlias(String alias) {
    return $FavoriteCachesTable(attachedDatabase, alias);
  }
}

class FavoriteCache extends DataClass implements Insertable<FavoriteCache> {
  final int userId;
  final String workId;
  final String workJson;
  final String recordsJson;
  final DateTime updatedAt;
  const FavoriteCache({
    required this.userId,
    required this.workId,
    required this.workJson,
    required this.recordsJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<int>(userId);
    map['work_id'] = Variable<String>(workId);
    map['work_json'] = Variable<String>(workJson);
    map['records_json'] = Variable<String>(recordsJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  FavoriteCachesCompanion toCompanion(bool nullToAbsent) {
    return FavoriteCachesCompanion(
      userId: Value(userId),
      workId: Value(workId),
      workJson: Value(workJson),
      recordsJson: Value(recordsJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory FavoriteCache.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FavoriteCache(
      userId: serializer.fromJson<int>(json['userId']),
      workId: serializer.fromJson<String>(json['workId']),
      workJson: serializer.fromJson<String>(json['workJson']),
      recordsJson: serializer.fromJson<String>(json['recordsJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<int>(userId),
      'workId': serializer.toJson<String>(workId),
      'workJson': serializer.toJson<String>(workJson),
      'recordsJson': serializer.toJson<String>(recordsJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  FavoriteCache copyWith({
    int? userId,
    String? workId,
    String? workJson,
    String? recordsJson,
    DateTime? updatedAt,
  }) => FavoriteCache(
    userId: userId ?? this.userId,
    workId: workId ?? this.workId,
    workJson: workJson ?? this.workJson,
    recordsJson: recordsJson ?? this.recordsJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  FavoriteCache copyWithCompanion(FavoriteCachesCompanion data) {
    return FavoriteCache(
      userId: data.userId.present ? data.userId.value : this.userId,
      workId: data.workId.present ? data.workId.value : this.workId,
      workJson: data.workJson.present ? data.workJson.value : this.workJson,
      recordsJson: data.recordsJson.present
          ? data.recordsJson.value
          : this.recordsJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FavoriteCache(')
          ..write('userId: $userId, ')
          ..write('workId: $workId, ')
          ..write('workJson: $workJson, ')
          ..write('recordsJson: $recordsJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(userId, workId, workJson, recordsJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FavoriteCache &&
          other.userId == this.userId &&
          other.workId == this.workId &&
          other.workJson == this.workJson &&
          other.recordsJson == this.recordsJson &&
          other.updatedAt == this.updatedAt);
}

class FavoriteCachesCompanion extends UpdateCompanion<FavoriteCache> {
  final Value<int> userId;
  final Value<String> workId;
  final Value<String> workJson;
  final Value<String> recordsJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const FavoriteCachesCompanion({
    this.userId = const Value.absent(),
    this.workId = const Value.absent(),
    this.workJson = const Value.absent(),
    this.recordsJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FavoriteCachesCompanion.insert({
    required int userId,
    required String workId,
    required String workJson,
    required String recordsJson,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       workId = Value(workId),
       workJson = Value(workJson),
       recordsJson = Value(recordsJson),
       updatedAt = Value(updatedAt);
  static Insertable<FavoriteCache> custom({
    Expression<int>? userId,
    Expression<String>? workId,
    Expression<String>? workJson,
    Expression<String>? recordsJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (workId != null) 'work_id': workId,
      if (workJson != null) 'work_json': workJson,
      if (recordsJson != null) 'records_json': recordsJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FavoriteCachesCompanion copyWith({
    Value<int>? userId,
    Value<String>? workId,
    Value<String>? workJson,
    Value<String>? recordsJson,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return FavoriteCachesCompanion(
      userId: userId ?? this.userId,
      workId: workId ?? this.workId,
      workJson: workJson ?? this.workJson,
      recordsJson: recordsJson ?? this.recordsJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<int>(userId.value);
    }
    if (workId.present) {
      map['work_id'] = Variable<String>(workId.value);
    }
    if (workJson.present) {
      map['work_json'] = Variable<String>(workJson.value);
    }
    if (recordsJson.present) {
      map['records_json'] = Variable<String>(recordsJson.value);
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
    return (StringBuffer('FavoriteCachesCompanion(')
          ..write('userId: $userId, ')
          ..write('workId: $workId, ')
          ..write('workJson: $workJson, ')
          ..write('recordsJson: $recordsJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DownloadTasksTable extends DownloadTasks
    with TableInfo<$DownloadTasksTable, DownloadTask> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DownloadTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workIdMeta = const VerificationMeta('workId');
  @override
  late final GeneratedColumn<String> workId = GeneratedColumn<String>(
    'work_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _libraryKindMeta = const VerificationMeta(
    'libraryKind',
  );
  @override
  late final GeneratedColumn<String> libraryKind = GeneratedColumn<String>(
    'library_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workJsonMeta = const VerificationMeta(
    'workJson',
  );
  @override
  late final GeneratedColumn<String> workJson = GeneratedColumn<String>(
    'work_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterJsonMeta = const VerificationMeta(
    'chapterJson',
  );
  @override
  late final GeneratedColumn<String> chapterJson = GeneratedColumn<String>(
    'chapter_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedItemsMeta = const VerificationMeta(
    'completedItems',
  );
  @override
  late final GeneratedColumn<int> completedItems = GeneratedColumn<int>(
    'completed_items',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalItemsMeta = const VerificationMeta(
    'totalItems',
  );
  @override
  late final GeneratedColumn<int> totalItems = GeneratedColumn<int>(
    'total_items',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directoryPathMeta = const VerificationMeta(
    'directoryPath',
  );
  @override
  late final GeneratedColumn<String> directoryPath = GeneratedColumn<String>(
    'directory_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    false,
    type: DriftSqlType.string,
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
    taskId,
    workId,
    libraryKind,
    workJson,
    chapterJson,
    status,
    completedItems,
    totalItems,
    directoryPath,
    payloadJson,
    errorMessage,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'download_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<DownloadTask> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('work_id')) {
      context.handle(
        _workIdMeta,
        workId.isAcceptableOrUnknown(data['work_id']!, _workIdMeta),
      );
    } else if (isInserting) {
      context.missing(_workIdMeta);
    }
    if (data.containsKey('library_kind')) {
      context.handle(
        _libraryKindMeta,
        libraryKind.isAcceptableOrUnknown(
          data['library_kind']!,
          _libraryKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_libraryKindMeta);
    }
    if (data.containsKey('work_json')) {
      context.handle(
        _workJsonMeta,
        workJson.isAcceptableOrUnknown(data['work_json']!, _workJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_workJsonMeta);
    }
    if (data.containsKey('chapter_json')) {
      context.handle(
        _chapterJsonMeta,
        chapterJson.isAcceptableOrUnknown(
          data['chapter_json']!,
          _chapterJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_chapterJsonMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('completed_items')) {
      context.handle(
        _completedItemsMeta,
        completedItems.isAcceptableOrUnknown(
          data['completed_items']!,
          _completedItemsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_completedItemsMeta);
    }
    if (data.containsKey('total_items')) {
      context.handle(
        _totalItemsMeta,
        totalItems.isAcceptableOrUnknown(data['total_items']!, _totalItemsMeta),
      );
    } else if (isInserting) {
      context.missing(_totalItemsMeta);
    }
    if (data.containsKey('directory_path')) {
      context.handle(
        _directoryPathMeta,
        directoryPath.isAcceptableOrUnknown(
          data['directory_path']!,
          _directoryPathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_directoryPathMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_errorMessageMeta);
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
  Set<GeneratedColumn> get $primaryKey => {taskId};
  @override
  DownloadTask map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DownloadTask(
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      workId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_id'],
      )!,
      libraryKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}library_kind'],
      )!,
      workJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_json'],
      )!,
      chapterJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_json'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      completedItems: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_items'],
      )!,
      totalItems: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_items'],
      )!,
      directoryPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}directory_path'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DownloadTasksTable createAlias(String alias) {
    return $DownloadTasksTable(attachedDatabase, alias);
  }
}

class DownloadTask extends DataClass implements Insertable<DownloadTask> {
  final String taskId;
  final String workId;
  final String libraryKind;
  final String workJson;
  final String chapterJson;
  final String status;
  final int completedItems;
  final int totalItems;
  final String directoryPath;
  final String payloadJson;
  final String errorMessage;
  final DateTime updatedAt;
  const DownloadTask({
    required this.taskId,
    required this.workId,
    required this.libraryKind,
    required this.workJson,
    required this.chapterJson,
    required this.status,
    required this.completedItems,
    required this.totalItems,
    required this.directoryPath,
    required this.payloadJson,
    required this.errorMessage,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['task_id'] = Variable<String>(taskId);
    map['work_id'] = Variable<String>(workId);
    map['library_kind'] = Variable<String>(libraryKind);
    map['work_json'] = Variable<String>(workJson);
    map['chapter_json'] = Variable<String>(chapterJson);
    map['status'] = Variable<String>(status);
    map['completed_items'] = Variable<int>(completedItems);
    map['total_items'] = Variable<int>(totalItems);
    map['directory_path'] = Variable<String>(directoryPath);
    map['payload_json'] = Variable<String>(payloadJson);
    map['error_message'] = Variable<String>(errorMessage);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DownloadTasksCompanion toCompanion(bool nullToAbsent) {
    return DownloadTasksCompanion(
      taskId: Value(taskId),
      workId: Value(workId),
      libraryKind: Value(libraryKind),
      workJson: Value(workJson),
      chapterJson: Value(chapterJson),
      status: Value(status),
      completedItems: Value(completedItems),
      totalItems: Value(totalItems),
      directoryPath: Value(directoryPath),
      payloadJson: Value(payloadJson),
      errorMessage: Value(errorMessage),
      updatedAt: Value(updatedAt),
    );
  }

  factory DownloadTask.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DownloadTask(
      taskId: serializer.fromJson<String>(json['taskId']),
      workId: serializer.fromJson<String>(json['workId']),
      libraryKind: serializer.fromJson<String>(json['libraryKind']),
      workJson: serializer.fromJson<String>(json['workJson']),
      chapterJson: serializer.fromJson<String>(json['chapterJson']),
      status: serializer.fromJson<String>(json['status']),
      completedItems: serializer.fromJson<int>(json['completedItems']),
      totalItems: serializer.fromJson<int>(json['totalItems']),
      directoryPath: serializer.fromJson<String>(json['directoryPath']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      errorMessage: serializer.fromJson<String>(json['errorMessage']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'taskId': serializer.toJson<String>(taskId),
      'workId': serializer.toJson<String>(workId),
      'libraryKind': serializer.toJson<String>(libraryKind),
      'workJson': serializer.toJson<String>(workJson),
      'chapterJson': serializer.toJson<String>(chapterJson),
      'status': serializer.toJson<String>(status),
      'completedItems': serializer.toJson<int>(completedItems),
      'totalItems': serializer.toJson<int>(totalItems),
      'directoryPath': serializer.toJson<String>(directoryPath),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'errorMessage': serializer.toJson<String>(errorMessage),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DownloadTask copyWith({
    String? taskId,
    String? workId,
    String? libraryKind,
    String? workJson,
    String? chapterJson,
    String? status,
    int? completedItems,
    int? totalItems,
    String? directoryPath,
    String? payloadJson,
    String? errorMessage,
    DateTime? updatedAt,
  }) => DownloadTask(
    taskId: taskId ?? this.taskId,
    workId: workId ?? this.workId,
    libraryKind: libraryKind ?? this.libraryKind,
    workJson: workJson ?? this.workJson,
    chapterJson: chapterJson ?? this.chapterJson,
    status: status ?? this.status,
    completedItems: completedItems ?? this.completedItems,
    totalItems: totalItems ?? this.totalItems,
    directoryPath: directoryPath ?? this.directoryPath,
    payloadJson: payloadJson ?? this.payloadJson,
    errorMessage: errorMessage ?? this.errorMessage,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DownloadTask copyWithCompanion(DownloadTasksCompanion data) {
    return DownloadTask(
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      workId: data.workId.present ? data.workId.value : this.workId,
      libraryKind: data.libraryKind.present
          ? data.libraryKind.value
          : this.libraryKind,
      workJson: data.workJson.present ? data.workJson.value : this.workJson,
      chapterJson: data.chapterJson.present
          ? data.chapterJson.value
          : this.chapterJson,
      status: data.status.present ? data.status.value : this.status,
      completedItems: data.completedItems.present
          ? data.completedItems.value
          : this.completedItems,
      totalItems: data.totalItems.present
          ? data.totalItems.value
          : this.totalItems,
      directoryPath: data.directoryPath.present
          ? data.directoryPath.value
          : this.directoryPath,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DownloadTask(')
          ..write('taskId: $taskId, ')
          ..write('workId: $workId, ')
          ..write('libraryKind: $libraryKind, ')
          ..write('workJson: $workJson, ')
          ..write('chapterJson: $chapterJson, ')
          ..write('status: $status, ')
          ..write('completedItems: $completedItems, ')
          ..write('totalItems: $totalItems, ')
          ..write('directoryPath: $directoryPath, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    taskId,
    workId,
    libraryKind,
    workJson,
    chapterJson,
    status,
    completedItems,
    totalItems,
    directoryPath,
    payloadJson,
    errorMessage,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DownloadTask &&
          other.taskId == this.taskId &&
          other.workId == this.workId &&
          other.libraryKind == this.libraryKind &&
          other.workJson == this.workJson &&
          other.chapterJson == this.chapterJson &&
          other.status == this.status &&
          other.completedItems == this.completedItems &&
          other.totalItems == this.totalItems &&
          other.directoryPath == this.directoryPath &&
          other.payloadJson == this.payloadJson &&
          other.errorMessage == this.errorMessage &&
          other.updatedAt == this.updatedAt);
}

class DownloadTasksCompanion extends UpdateCompanion<DownloadTask> {
  final Value<String> taskId;
  final Value<String> workId;
  final Value<String> libraryKind;
  final Value<String> workJson;
  final Value<String> chapterJson;
  final Value<String> status;
  final Value<int> completedItems;
  final Value<int> totalItems;
  final Value<String> directoryPath;
  final Value<String> payloadJson;
  final Value<String> errorMessage;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const DownloadTasksCompanion({
    this.taskId = const Value.absent(),
    this.workId = const Value.absent(),
    this.libraryKind = const Value.absent(),
    this.workJson = const Value.absent(),
    this.chapterJson = const Value.absent(),
    this.status = const Value.absent(),
    this.completedItems = const Value.absent(),
    this.totalItems = const Value.absent(),
    this.directoryPath = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DownloadTasksCompanion.insert({
    required String taskId,
    required String workId,
    required String libraryKind,
    required String workJson,
    required String chapterJson,
    required String status,
    required int completedItems,
    required int totalItems,
    required String directoryPath,
    required String payloadJson,
    required String errorMessage,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : taskId = Value(taskId),
       workId = Value(workId),
       libraryKind = Value(libraryKind),
       workJson = Value(workJson),
       chapterJson = Value(chapterJson),
       status = Value(status),
       completedItems = Value(completedItems),
       totalItems = Value(totalItems),
       directoryPath = Value(directoryPath),
       payloadJson = Value(payloadJson),
       errorMessage = Value(errorMessage),
       updatedAt = Value(updatedAt);
  static Insertable<DownloadTask> custom({
    Expression<String>? taskId,
    Expression<String>? workId,
    Expression<String>? libraryKind,
    Expression<String>? workJson,
    Expression<String>? chapterJson,
    Expression<String>? status,
    Expression<int>? completedItems,
    Expression<int>? totalItems,
    Expression<String>? directoryPath,
    Expression<String>? payloadJson,
    Expression<String>? errorMessage,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (taskId != null) 'task_id': taskId,
      if (workId != null) 'work_id': workId,
      if (libraryKind != null) 'library_kind': libraryKind,
      if (workJson != null) 'work_json': workJson,
      if (chapterJson != null) 'chapter_json': chapterJson,
      if (status != null) 'status': status,
      if (completedItems != null) 'completed_items': completedItems,
      if (totalItems != null) 'total_items': totalItems,
      if (directoryPath != null) 'directory_path': directoryPath,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (errorMessage != null) 'error_message': errorMessage,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DownloadTasksCompanion copyWith({
    Value<String>? taskId,
    Value<String>? workId,
    Value<String>? libraryKind,
    Value<String>? workJson,
    Value<String>? chapterJson,
    Value<String>? status,
    Value<int>? completedItems,
    Value<int>? totalItems,
    Value<String>? directoryPath,
    Value<String>? payloadJson,
    Value<String>? errorMessage,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return DownloadTasksCompanion(
      taskId: taskId ?? this.taskId,
      workId: workId ?? this.workId,
      libraryKind: libraryKind ?? this.libraryKind,
      workJson: workJson ?? this.workJson,
      chapterJson: chapterJson ?? this.chapterJson,
      status: status ?? this.status,
      completedItems: completedItems ?? this.completedItems,
      totalItems: totalItems ?? this.totalItems,
      directoryPath: directoryPath ?? this.directoryPath,
      payloadJson: payloadJson ?? this.payloadJson,
      errorMessage: errorMessage ?? this.errorMessage,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (workId.present) {
      map['work_id'] = Variable<String>(workId.value);
    }
    if (libraryKind.present) {
      map['library_kind'] = Variable<String>(libraryKind.value);
    }
    if (workJson.present) {
      map['work_json'] = Variable<String>(workJson.value);
    }
    if (chapterJson.present) {
      map['chapter_json'] = Variable<String>(chapterJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (completedItems.present) {
      map['completed_items'] = Variable<int>(completedItems.value);
    }
    if (totalItems.present) {
      map['total_items'] = Variable<int>(totalItems.value);
    }
    if (directoryPath.present) {
      map['directory_path'] = Variable<String>(directoryPath.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
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
    return (StringBuffer('DownloadTasksCompanion(')
          ..write('taskId: $taskId, ')
          ..write('workId: $workId, ')
          ..write('libraryKind: $libraryKind, ')
          ..write('workJson: $workJson, ')
          ..write('chapterJson: $chapterJson, ')
          ..write('status: $status, ')
          ..write('completedItems: $completedItems, ')
          ..write('totalItems: $totalItems, ')
          ..write('directoryPath: $directoryPath, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CoverCachesTable extends CoverCaches
    with TableInfo<$CoverCachesTable, CoverCache> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoverCachesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _workIdMeta = const VerificationMeta('workId');
  @override
  late final GeneratedColumn<String> workId = GeneratedColumn<String>(
    'work_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMarkerMeta = const VerificationMeta(
    'sourceMarker',
  );
  @override
  late final GeneratedColumn<String> sourceMarker = GeneratedColumn<String>(
    'source_marker',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imageUriMeta = const VerificationMeta(
    'imageUri',
  );
  @override
  late final GeneratedColumn<String> imageUri = GeneratedColumn<String>(
    'image_uri',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
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
    workId,
    sourceMarker,
    imageUri,
    filePath,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cover_caches';
  @override
  VerificationContext validateIntegrity(
    Insertable<CoverCache> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('work_id')) {
      context.handle(
        _workIdMeta,
        workId.isAcceptableOrUnknown(data['work_id']!, _workIdMeta),
      );
    } else if (isInserting) {
      context.missing(_workIdMeta);
    }
    if (data.containsKey('source_marker')) {
      context.handle(
        _sourceMarkerMeta,
        sourceMarker.isAcceptableOrUnknown(
          data['source_marker']!,
          _sourceMarkerMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourceMarkerMeta);
    }
    if (data.containsKey('image_uri')) {
      context.handle(
        _imageUriMeta,
        imageUri.isAcceptableOrUnknown(data['image_uri']!, _imageUriMeta),
      );
    } else if (isInserting) {
      context.missing(_imageUriMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
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
  Set<GeneratedColumn> get $primaryKey => {workId};
  @override
  CoverCache map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoverCache(
      workId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_id'],
      )!,
      sourceMarker: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_marker'],
      )!,
      imageUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_uri'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CoverCachesTable createAlias(String alias) {
    return $CoverCachesTable(attachedDatabase, alias);
  }
}

class CoverCache extends DataClass implements Insertable<CoverCache> {
  final String workId;
  final String sourceMarker;
  final String imageUri;
  final String filePath;
  final DateTime updatedAt;
  const CoverCache({
    required this.workId,
    required this.sourceMarker,
    required this.imageUri,
    required this.filePath,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['work_id'] = Variable<String>(workId);
    map['source_marker'] = Variable<String>(sourceMarker);
    map['image_uri'] = Variable<String>(imageUri);
    map['file_path'] = Variable<String>(filePath);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CoverCachesCompanion toCompanion(bool nullToAbsent) {
    return CoverCachesCompanion(
      workId: Value(workId),
      sourceMarker: Value(sourceMarker),
      imageUri: Value(imageUri),
      filePath: Value(filePath),
      updatedAt: Value(updatedAt),
    );
  }

  factory CoverCache.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoverCache(
      workId: serializer.fromJson<String>(json['workId']),
      sourceMarker: serializer.fromJson<String>(json['sourceMarker']),
      imageUri: serializer.fromJson<String>(json['imageUri']),
      filePath: serializer.fromJson<String>(json['filePath']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'workId': serializer.toJson<String>(workId),
      'sourceMarker': serializer.toJson<String>(sourceMarker),
      'imageUri': serializer.toJson<String>(imageUri),
      'filePath': serializer.toJson<String>(filePath),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CoverCache copyWith({
    String? workId,
    String? sourceMarker,
    String? imageUri,
    String? filePath,
    DateTime? updatedAt,
  }) => CoverCache(
    workId: workId ?? this.workId,
    sourceMarker: sourceMarker ?? this.sourceMarker,
    imageUri: imageUri ?? this.imageUri,
    filePath: filePath ?? this.filePath,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CoverCache copyWithCompanion(CoverCachesCompanion data) {
    return CoverCache(
      workId: data.workId.present ? data.workId.value : this.workId,
      sourceMarker: data.sourceMarker.present
          ? data.sourceMarker.value
          : this.sourceMarker,
      imageUri: data.imageUri.present ? data.imageUri.value : this.imageUri,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoverCache(')
          ..write('workId: $workId, ')
          ..write('sourceMarker: $sourceMarker, ')
          ..write('imageUri: $imageUri, ')
          ..write('filePath: $filePath, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(workId, sourceMarker, imageUri, filePath, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoverCache &&
          other.workId == this.workId &&
          other.sourceMarker == this.sourceMarker &&
          other.imageUri == this.imageUri &&
          other.filePath == this.filePath &&
          other.updatedAt == this.updatedAt);
}

class CoverCachesCompanion extends UpdateCompanion<CoverCache> {
  final Value<String> workId;
  final Value<String> sourceMarker;
  final Value<String> imageUri;
  final Value<String> filePath;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CoverCachesCompanion({
    this.workId = const Value.absent(),
    this.sourceMarker = const Value.absent(),
    this.imageUri = const Value.absent(),
    this.filePath = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CoverCachesCompanion.insert({
    required String workId,
    required String sourceMarker,
    required String imageUri,
    required String filePath,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : workId = Value(workId),
       sourceMarker = Value(sourceMarker),
       imageUri = Value(imageUri),
       filePath = Value(filePath),
       updatedAt = Value(updatedAt);
  static Insertable<CoverCache> custom({
    Expression<String>? workId,
    Expression<String>? sourceMarker,
    Expression<String>? imageUri,
    Expression<String>? filePath,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (workId != null) 'work_id': workId,
      if (sourceMarker != null) 'source_marker': sourceMarker,
      if (imageUri != null) 'image_uri': imageUri,
      if (filePath != null) 'file_path': filePath,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CoverCachesCompanion copyWith({
    Value<String>? workId,
    Value<String>? sourceMarker,
    Value<String>? imageUri,
    Value<String>? filePath,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CoverCachesCompanion(
      workId: workId ?? this.workId,
      sourceMarker: sourceMarker ?? this.sourceMarker,
      imageUri: imageUri ?? this.imageUri,
      filePath: filePath ?? this.filePath,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (workId.present) {
      map['work_id'] = Variable<String>(workId.value);
    }
    if (sourceMarker.present) {
      map['source_marker'] = Variable<String>(sourceMarker.value);
    }
    if (imageUri.present) {
      map['image_uri'] = Variable<String>(imageUri.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
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
    return (StringBuffer('CoverCachesCompanion(')
          ..write('workId: $workId, ')
          ..write('sourceMarker: $sourceMarker, ')
          ..write('imageUri: $imageUri, ')
          ..write('filePath: $filePath, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CoverEntriesTable extends CoverEntries
    with TableInfo<$CoverEntriesTable, CoverEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoverEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _coverKeyMeta = const VerificationMeta(
    'coverKey',
  );
  @override
  late final GeneratedColumn<String> coverKey = GeneratedColumn<String>(
    'cover_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _libraryKindMeta = const VerificationMeta(
    'libraryKind',
  );
  @override
  late final GeneratedColumn<String> libraryKind = GeneratedColumn<String>(
    'library_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _imageUriMeta = const VerificationMeta(
    'imageUri',
  );
  @override
  late final GeneratedColumn<String> imageUri = GeneratedColumn<String>(
    'image_uri',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceTidMeta = const VerificationMeta(
    'sourceTid',
  );
  @override
  late final GeneratedColumn<int> sourceTid = GeneratedColumn<int>(
    'source_tid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(0),
  );
  static const VerificationMeta _nextRetryAtMeta = const VerificationMeta(
    'nextRetryAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextRetryAt = GeneratedColumn<DateTime>(
    'next_retry_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
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
    coverKey,
    libraryKind,
    status,
    imageUri,
    filePath,
    sourceTid,
    retryCount,
    nextRetryAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cover_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CoverEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cover_key')) {
      context.handle(
        _coverKeyMeta,
        coverKey.isAcceptableOrUnknown(data['cover_key']!, _coverKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_coverKeyMeta);
    }
    if (data.containsKey('library_kind')) {
      context.handle(
        _libraryKindMeta,
        libraryKind.isAcceptableOrUnknown(
          data['library_kind']!,
          _libraryKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_libraryKindMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('image_uri')) {
      context.handle(
        _imageUriMeta,
        imageUri.isAcceptableOrUnknown(data['image_uri']!, _imageUriMeta),
      );
    } else if (isInserting) {
      context.missing(_imageUriMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('source_tid')) {
      context.handle(
        _sourceTidMeta,
        sourceTid.isAcceptableOrUnknown(data['source_tid']!, _sourceTidMeta),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('next_retry_at')) {
      context.handle(
        _nextRetryAtMeta,
        nextRetryAt.isAcceptableOrUnknown(
          data['next_retry_at']!,
          _nextRetryAtMeta,
        ),
      );
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
  Set<GeneratedColumn> get $primaryKey => {coverKey};
  @override
  CoverEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoverEntry(
      coverKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_key'],
      )!,
      libraryKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}library_kind'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      imageUri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_uri'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      sourceTid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_tid'],
      ),
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      nextRetryAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_retry_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CoverEntriesTable createAlias(String alias) {
    return $CoverEntriesTable(attachedDatabase, alias);
  }
}

class CoverEntry extends DataClass implements Insertable<CoverEntry> {
  final String coverKey;
  final String libraryKind;
  final String status;
  final String imageUri;
  final String filePath;
  final int? sourceTid;
  final int retryCount;
  final DateTime? nextRetryAt;
  final DateTime updatedAt;
  const CoverEntry({
    required this.coverKey,
    required this.libraryKind,
    required this.status,
    required this.imageUri,
    required this.filePath,
    this.sourceTid,
    required this.retryCount,
    this.nextRetryAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cover_key'] = Variable<String>(coverKey);
    map['library_kind'] = Variable<String>(libraryKind);
    map['status'] = Variable<String>(status);
    map['image_uri'] = Variable<String>(imageUri);
    map['file_path'] = Variable<String>(filePath);
    if (!nullToAbsent || sourceTid != null) {
      map['source_tid'] = Variable<int>(sourceTid);
    }
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || nextRetryAt != null) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CoverEntriesCompanion toCompanion(bool nullToAbsent) {
    return CoverEntriesCompanion(
      coverKey: Value(coverKey),
      libraryKind: Value(libraryKind),
      status: Value(status),
      imageUri: Value(imageUri),
      filePath: Value(filePath),
      sourceTid: sourceTid == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceTid),
      retryCount: Value(retryCount),
      nextRetryAt: nextRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRetryAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CoverEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoverEntry(
      coverKey: serializer.fromJson<String>(json['coverKey']),
      libraryKind: serializer.fromJson<String>(json['libraryKind']),
      status: serializer.fromJson<String>(json['status']),
      imageUri: serializer.fromJson<String>(json['imageUri']),
      filePath: serializer.fromJson<String>(json['filePath']),
      sourceTid: serializer.fromJson<int?>(json['sourceTid']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      nextRetryAt: serializer.fromJson<DateTime?>(json['nextRetryAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'coverKey': serializer.toJson<String>(coverKey),
      'libraryKind': serializer.toJson<String>(libraryKind),
      'status': serializer.toJson<String>(status),
      'imageUri': serializer.toJson<String>(imageUri),
      'filePath': serializer.toJson<String>(filePath),
      'sourceTid': serializer.toJson<int?>(sourceTid),
      'retryCount': serializer.toJson<int>(retryCount),
      'nextRetryAt': serializer.toJson<DateTime?>(nextRetryAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CoverEntry copyWith({
    String? coverKey,
    String? libraryKind,
    String? status,
    String? imageUri,
    String? filePath,
    Value<int?> sourceTid = const Value.absent(),
    int? retryCount,
    Value<DateTime?> nextRetryAt = const Value.absent(),
    DateTime? updatedAt,
  }) => CoverEntry(
    coverKey: coverKey ?? this.coverKey,
    libraryKind: libraryKind ?? this.libraryKind,
    status: status ?? this.status,
    imageUri: imageUri ?? this.imageUri,
    filePath: filePath ?? this.filePath,
    sourceTid: sourceTid.present ? sourceTid.value : this.sourceTid,
    retryCount: retryCount ?? this.retryCount,
    nextRetryAt: nextRetryAt.present ? nextRetryAt.value : this.nextRetryAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CoverEntry copyWithCompanion(CoverEntriesCompanion data) {
    return CoverEntry(
      coverKey: data.coverKey.present ? data.coverKey.value : this.coverKey,
      libraryKind: data.libraryKind.present
          ? data.libraryKind.value
          : this.libraryKind,
      status: data.status.present ? data.status.value : this.status,
      imageUri: data.imageUri.present ? data.imageUri.value : this.imageUri,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      sourceTid: data.sourceTid.present ? data.sourceTid.value : this.sourceTid,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      nextRetryAt: data.nextRetryAt.present
          ? data.nextRetryAt.value
          : this.nextRetryAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoverEntry(')
          ..write('coverKey: $coverKey, ')
          ..write('libraryKind: $libraryKind, ')
          ..write('status: $status, ')
          ..write('imageUri: $imageUri, ')
          ..write('filePath: $filePath, ')
          ..write('sourceTid: $sourceTid, ')
          ..write('retryCount: $retryCount, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    coverKey,
    libraryKind,
    status,
    imageUri,
    filePath,
    sourceTid,
    retryCount,
    nextRetryAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoverEntry &&
          other.coverKey == this.coverKey &&
          other.libraryKind == this.libraryKind &&
          other.status == this.status &&
          other.imageUri == this.imageUri &&
          other.filePath == this.filePath &&
          other.sourceTid == this.sourceTid &&
          other.retryCount == this.retryCount &&
          other.nextRetryAt == this.nextRetryAt &&
          other.updatedAt == this.updatedAt);
}

class CoverEntriesCompanion extends UpdateCompanion<CoverEntry> {
  final Value<String> coverKey;
  final Value<String> libraryKind;
  final Value<String> status;
  final Value<String> imageUri;
  final Value<String> filePath;
  final Value<int?> sourceTid;
  final Value<int> retryCount;
  final Value<DateTime?> nextRetryAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CoverEntriesCompanion({
    this.coverKey = const Value.absent(),
    this.libraryKind = const Value.absent(),
    this.status = const Value.absent(),
    this.imageUri = const Value.absent(),
    this.filePath = const Value.absent(),
    this.sourceTid = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CoverEntriesCompanion.insert({
    required String coverKey,
    required String libraryKind,
    required String status,
    required String imageUri,
    required String filePath,
    this.sourceTid = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : coverKey = Value(coverKey),
       libraryKind = Value(libraryKind),
       status = Value(status),
       imageUri = Value(imageUri),
       filePath = Value(filePath),
       updatedAt = Value(updatedAt);
  static Insertable<CoverEntry> custom({
    Expression<String>? coverKey,
    Expression<String>? libraryKind,
    Expression<String>? status,
    Expression<String>? imageUri,
    Expression<String>? filePath,
    Expression<int>? sourceTid,
    Expression<int>? retryCount,
    Expression<DateTime>? nextRetryAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (coverKey != null) 'cover_key': coverKey,
      if (libraryKind != null) 'library_kind': libraryKind,
      if (status != null) 'status': status,
      if (imageUri != null) 'image_uri': imageUri,
      if (filePath != null) 'file_path': filePath,
      if (sourceTid != null) 'source_tid': sourceTid,
      if (retryCount != null) 'retry_count': retryCount,
      if (nextRetryAt != null) 'next_retry_at': nextRetryAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CoverEntriesCompanion copyWith({
    Value<String>? coverKey,
    Value<String>? libraryKind,
    Value<String>? status,
    Value<String>? imageUri,
    Value<String>? filePath,
    Value<int?>? sourceTid,
    Value<int>? retryCount,
    Value<DateTime?>? nextRetryAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CoverEntriesCompanion(
      coverKey: coverKey ?? this.coverKey,
      libraryKind: libraryKind ?? this.libraryKind,
      status: status ?? this.status,
      imageUri: imageUri ?? this.imageUri,
      filePath: filePath ?? this.filePath,
      sourceTid: sourceTid ?? this.sourceTid,
      retryCount: retryCount ?? this.retryCount,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (coverKey.present) {
      map['cover_key'] = Variable<String>(coverKey.value);
    }
    if (libraryKind.present) {
      map['library_kind'] = Variable<String>(libraryKind.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (imageUri.present) {
      map['image_uri'] = Variable<String>(imageUri.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (sourceTid.present) {
      map['source_tid'] = Variable<int>(sourceTid.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (nextRetryAt.present) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt.value);
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
    return (StringBuffer('CoverEntriesCompanion(')
          ..write('coverKey: $coverKey, ')
          ..write('libraryKind: $libraryKind, ')
          ..write('status: $status, ')
          ..write('imageUri: $imageUri, ')
          ..write('filePath: $filePath, ')
          ..write('sourceTid: $sourceTid, ')
          ..write('retryCount: $retryCount, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CoverAliasesTable extends CoverAliases
    with TableInfo<$CoverAliasesTable, CoverAliase> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoverAliasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _libraryKindMeta = const VerificationMeta(
    'libraryKind',
  );
  @override
  late final GeneratedColumn<String> libraryKind = GeneratedColumn<String>(
    'library_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tidMeta = const VerificationMeta('tid');
  @override
  late final GeneratedColumn<int> tid = GeneratedColumn<int>(
    'tid',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverKeyMeta = const VerificationMeta(
    'coverKey',
  );
  @override
  late final GeneratedColumn<String> coverKey = GeneratedColumn<String>(
    'cover_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES cover_entries (cover_key) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [libraryKind, tid, coverKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cover_aliases';
  @override
  VerificationContext validateIntegrity(
    Insertable<CoverAliase> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('library_kind')) {
      context.handle(
        _libraryKindMeta,
        libraryKind.isAcceptableOrUnknown(
          data['library_kind']!,
          _libraryKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_libraryKindMeta);
    }
    if (data.containsKey('tid')) {
      context.handle(
        _tidMeta,
        tid.isAcceptableOrUnknown(data['tid']!, _tidMeta),
      );
    } else if (isInserting) {
      context.missing(_tidMeta);
    }
    if (data.containsKey('cover_key')) {
      context.handle(
        _coverKeyMeta,
        coverKey.isAcceptableOrUnknown(data['cover_key']!, _coverKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_coverKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {libraryKind, tid};
  @override
  CoverAliase map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoverAliase(
      libraryKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}library_kind'],
      )!,
      tid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tid'],
      )!,
      coverKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_key'],
      )!,
    );
  }

  @override
  $CoverAliasesTable createAlias(String alias) {
    return $CoverAliasesTable(attachedDatabase, alias);
  }
}

class CoverAliase extends DataClass implements Insertable<CoverAliase> {
  final String libraryKind;
  final int tid;
  final String coverKey;
  const CoverAliase({
    required this.libraryKind,
    required this.tid,
    required this.coverKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['library_kind'] = Variable<String>(libraryKind);
    map['tid'] = Variable<int>(tid);
    map['cover_key'] = Variable<String>(coverKey);
    return map;
  }

  CoverAliasesCompanion toCompanion(bool nullToAbsent) {
    return CoverAliasesCompanion(
      libraryKind: Value(libraryKind),
      tid: Value(tid),
      coverKey: Value(coverKey),
    );
  }

  factory CoverAliase.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoverAliase(
      libraryKind: serializer.fromJson<String>(json['libraryKind']),
      tid: serializer.fromJson<int>(json['tid']),
      coverKey: serializer.fromJson<String>(json['coverKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'libraryKind': serializer.toJson<String>(libraryKind),
      'tid': serializer.toJson<int>(tid),
      'coverKey': serializer.toJson<String>(coverKey),
    };
  }

  CoverAliase copyWith({String? libraryKind, int? tid, String? coverKey}) =>
      CoverAliase(
        libraryKind: libraryKind ?? this.libraryKind,
        tid: tid ?? this.tid,
        coverKey: coverKey ?? this.coverKey,
      );
  CoverAliase copyWithCompanion(CoverAliasesCompanion data) {
    return CoverAliase(
      libraryKind: data.libraryKind.present
          ? data.libraryKind.value
          : this.libraryKind,
      tid: data.tid.present ? data.tid.value : this.tid,
      coverKey: data.coverKey.present ? data.coverKey.value : this.coverKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoverAliase(')
          ..write('libraryKind: $libraryKind, ')
          ..write('tid: $tid, ')
          ..write('coverKey: $coverKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(libraryKind, tid, coverKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoverAliase &&
          other.libraryKind == this.libraryKind &&
          other.tid == this.tid &&
          other.coverKey == this.coverKey);
}

class CoverAliasesCompanion extends UpdateCompanion<CoverAliase> {
  final Value<String> libraryKind;
  final Value<int> tid;
  final Value<String> coverKey;
  final Value<int> rowid;
  const CoverAliasesCompanion({
    this.libraryKind = const Value.absent(),
    this.tid = const Value.absent(),
    this.coverKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CoverAliasesCompanion.insert({
    required String libraryKind,
    required int tid,
    required String coverKey,
    this.rowid = const Value.absent(),
  }) : libraryKind = Value(libraryKind),
       tid = Value(tid),
       coverKey = Value(coverKey);
  static Insertable<CoverAliase> custom({
    Expression<String>? libraryKind,
    Expression<int>? tid,
    Expression<String>? coverKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (libraryKind != null) 'library_kind': libraryKind,
      if (tid != null) 'tid': tid,
      if (coverKey != null) 'cover_key': coverKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CoverAliasesCompanion copyWith({
    Value<String>? libraryKind,
    Value<int>? tid,
    Value<String>? coverKey,
    Value<int>? rowid,
  }) {
    return CoverAliasesCompanion(
      libraryKind: libraryKind ?? this.libraryKind,
      tid: tid ?? this.tid,
      coverKey: coverKey ?? this.coverKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (libraryKind.present) {
      map['library_kind'] = Variable<String>(libraryKind.value);
    }
    if (tid.present) {
      map['tid'] = Variable<int>(tid.value);
    }
    if (coverKey.present) {
      map['cover_key'] = Variable<String>(coverKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CoverAliasesCompanion(')
          ..write('libraryKind: $libraryKind, ')
          ..write('tid: $tid, ')
          ..write('coverKey: $coverKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkIndexesTable extends WorkIndexes
    with TableInfo<$WorkIndexesTable, WorkIndex> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkIndexesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _canonicalKeyMeta = const VerificationMeta(
    'canonicalKey',
  );
  @override
  late final GeneratedColumn<String> canonicalKey = GeneratedColumn<String>(
    'canonical_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workIdMeta = const VerificationMeta('workId');
  @override
  late final GeneratedColumn<String> workId = GeneratedColumn<String>(
    'work_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _libraryKindMeta = const VerificationMeta(
    'libraryKind',
  );
  @override
  late final GeneratedColumn<String> libraryKind = GeneratedColumn<String>(
    'library_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workJsonMeta = const VerificationMeta(
    'workJson',
  );
  @override
  late final GeneratedColumn<String> workJson = GeneratedColumn<String>(
    'work_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resolverVersionMeta = const VerificationMeta(
    'resolverVersion',
  );
  @override
  late final GeneratedColumn<int> resolverVersion = GeneratedColumn<int>(
    'resolver_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(1),
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
    canonicalKey,
    workId,
    libraryKind,
    workJson,
    resolverVersion,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'work_indexes';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkIndex> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('canonical_key')) {
      context.handle(
        _canonicalKeyMeta,
        canonicalKey.isAcceptableOrUnknown(
          data['canonical_key']!,
          _canonicalKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_canonicalKeyMeta);
    }
    if (data.containsKey('work_id')) {
      context.handle(
        _workIdMeta,
        workId.isAcceptableOrUnknown(data['work_id']!, _workIdMeta),
      );
    } else if (isInserting) {
      context.missing(_workIdMeta);
    }
    if (data.containsKey('library_kind')) {
      context.handle(
        _libraryKindMeta,
        libraryKind.isAcceptableOrUnknown(
          data['library_kind']!,
          _libraryKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_libraryKindMeta);
    }
    if (data.containsKey('work_json')) {
      context.handle(
        _workJsonMeta,
        workJson.isAcceptableOrUnknown(data['work_json']!, _workJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_workJsonMeta);
    }
    if (data.containsKey('resolver_version')) {
      context.handle(
        _resolverVersionMeta,
        resolverVersion.isAcceptableOrUnknown(
          data['resolver_version']!,
          _resolverVersionMeta,
        ),
      );
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
  Set<GeneratedColumn> get $primaryKey => {canonicalKey};
  @override
  WorkIndex map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkIndex(
      canonicalKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_key'],
      )!,
      workId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_id'],
      )!,
      libraryKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}library_kind'],
      )!,
      workJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}work_json'],
      )!,
      resolverVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}resolver_version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WorkIndexesTable createAlias(String alias) {
    return $WorkIndexesTable(attachedDatabase, alias);
  }
}

class WorkIndex extends DataClass implements Insertable<WorkIndex> {
  final String canonicalKey;
  final String workId;
  final String libraryKind;
  final String workJson;
  final int resolverVersion;
  final DateTime updatedAt;
  const WorkIndex({
    required this.canonicalKey,
    required this.workId,
    required this.libraryKind,
    required this.workJson,
    required this.resolverVersion,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['canonical_key'] = Variable<String>(canonicalKey);
    map['work_id'] = Variable<String>(workId);
    map['library_kind'] = Variable<String>(libraryKind);
    map['work_json'] = Variable<String>(workJson);
    map['resolver_version'] = Variable<int>(resolverVersion);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WorkIndexesCompanion toCompanion(bool nullToAbsent) {
    return WorkIndexesCompanion(
      canonicalKey: Value(canonicalKey),
      workId: Value(workId),
      libraryKind: Value(libraryKind),
      workJson: Value(workJson),
      resolverVersion: Value(resolverVersion),
      updatedAt: Value(updatedAt),
    );
  }

  factory WorkIndex.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkIndex(
      canonicalKey: serializer.fromJson<String>(json['canonicalKey']),
      workId: serializer.fromJson<String>(json['workId']),
      libraryKind: serializer.fromJson<String>(json['libraryKind']),
      workJson: serializer.fromJson<String>(json['workJson']),
      resolverVersion: serializer.fromJson<int>(json['resolverVersion']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'canonicalKey': serializer.toJson<String>(canonicalKey),
      'workId': serializer.toJson<String>(workId),
      'libraryKind': serializer.toJson<String>(libraryKind),
      'workJson': serializer.toJson<String>(workJson),
      'resolverVersion': serializer.toJson<int>(resolverVersion),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  WorkIndex copyWith({
    String? canonicalKey,
    String? workId,
    String? libraryKind,
    String? workJson,
    int? resolverVersion,
    DateTime? updatedAt,
  }) => WorkIndex(
    canonicalKey: canonicalKey ?? this.canonicalKey,
    workId: workId ?? this.workId,
    libraryKind: libraryKind ?? this.libraryKind,
    workJson: workJson ?? this.workJson,
    resolverVersion: resolverVersion ?? this.resolverVersion,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WorkIndex copyWithCompanion(WorkIndexesCompanion data) {
    return WorkIndex(
      canonicalKey: data.canonicalKey.present
          ? data.canonicalKey.value
          : this.canonicalKey,
      workId: data.workId.present ? data.workId.value : this.workId,
      libraryKind: data.libraryKind.present
          ? data.libraryKind.value
          : this.libraryKind,
      workJson: data.workJson.present ? data.workJson.value : this.workJson,
      resolverVersion: data.resolverVersion.present
          ? data.resolverVersion.value
          : this.resolverVersion,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkIndex(')
          ..write('canonicalKey: $canonicalKey, ')
          ..write('workId: $workId, ')
          ..write('libraryKind: $libraryKind, ')
          ..write('workJson: $workJson, ')
          ..write('resolverVersion: $resolverVersion, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    canonicalKey,
    workId,
    libraryKind,
    workJson,
    resolverVersion,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkIndex &&
          other.canonicalKey == this.canonicalKey &&
          other.workId == this.workId &&
          other.libraryKind == this.libraryKind &&
          other.workJson == this.workJson &&
          other.resolverVersion == this.resolverVersion &&
          other.updatedAt == this.updatedAt);
}

class WorkIndexesCompanion extends UpdateCompanion<WorkIndex> {
  final Value<String> canonicalKey;
  final Value<String> workId;
  final Value<String> libraryKind;
  final Value<String> workJson;
  final Value<int> resolverVersion;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const WorkIndexesCompanion({
    this.canonicalKey = const Value.absent(),
    this.workId = const Value.absent(),
    this.libraryKind = const Value.absent(),
    this.workJson = const Value.absent(),
    this.resolverVersion = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkIndexesCompanion.insert({
    required String canonicalKey,
    required String workId,
    required String libraryKind,
    required String workJson,
    this.resolverVersion = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : canonicalKey = Value(canonicalKey),
       workId = Value(workId),
       libraryKind = Value(libraryKind),
       workJson = Value(workJson),
       updatedAt = Value(updatedAt);
  static Insertable<WorkIndex> custom({
    Expression<String>? canonicalKey,
    Expression<String>? workId,
    Expression<String>? libraryKind,
    Expression<String>? workJson,
    Expression<int>? resolverVersion,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (canonicalKey != null) 'canonical_key': canonicalKey,
      if (workId != null) 'work_id': workId,
      if (libraryKind != null) 'library_kind': libraryKind,
      if (workJson != null) 'work_json': workJson,
      if (resolverVersion != null) 'resolver_version': resolverVersion,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkIndexesCompanion copyWith({
    Value<String>? canonicalKey,
    Value<String>? workId,
    Value<String>? libraryKind,
    Value<String>? workJson,
    Value<int>? resolverVersion,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return WorkIndexesCompanion(
      canonicalKey: canonicalKey ?? this.canonicalKey,
      workId: workId ?? this.workId,
      libraryKind: libraryKind ?? this.libraryKind,
      workJson: workJson ?? this.workJson,
      resolverVersion: resolverVersion ?? this.resolverVersion,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (canonicalKey.present) {
      map['canonical_key'] = Variable<String>(canonicalKey.value);
    }
    if (workId.present) {
      map['work_id'] = Variable<String>(workId.value);
    }
    if (libraryKind.present) {
      map['library_kind'] = Variable<String>(libraryKind.value);
    }
    if (workJson.present) {
      map['work_json'] = Variable<String>(workJson.value);
    }
    if (resolverVersion.present) {
      map['resolver_version'] = Variable<int>(resolverVersion.value);
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
    return (StringBuffer('WorkIndexesCompanion(')
          ..write('canonicalKey: $canonicalKey, ')
          ..write('workId: $workId, ')
          ..write('libraryKind: $libraryKind, ')
          ..write('workJson: $workJson, ')
          ..write('resolverVersion: $resolverVersion, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkIndexSourcesTable extends WorkIndexSources
    with TableInfo<$WorkIndexSourcesTable, WorkIndexSource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkIndexSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _tidMeta = const VerificationMeta('tid');
  @override
  late final GeneratedColumn<int> tid = GeneratedColumn<int>(
    'tid',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _canonicalKeyMeta = const VerificationMeta(
    'canonicalKey',
  );
  @override
  late final GeneratedColumn<String> canonicalKey = GeneratedColumn<String>(
    'canonical_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES work_indexes (canonical_key) ON DELETE CASCADE',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [tid, canonicalKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'work_index_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkIndexSource> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('tid')) {
      context.handle(
        _tidMeta,
        tid.isAcceptableOrUnknown(data['tid']!, _tidMeta),
      );
    }
    if (data.containsKey('canonical_key')) {
      context.handle(
        _canonicalKeyMeta,
        canonicalKey.isAcceptableOrUnknown(
          data['canonical_key']!,
          _canonicalKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_canonicalKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {tid};
  @override
  WorkIndexSource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkIndexSource(
      tid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tid'],
      )!,
      canonicalKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_key'],
      )!,
    );
  }

  @override
  $WorkIndexSourcesTable createAlias(String alias) {
    return $WorkIndexSourcesTable(attachedDatabase, alias);
  }
}

class WorkIndexSource extends DataClass implements Insertable<WorkIndexSource> {
  final int tid;
  final String canonicalKey;
  const WorkIndexSource({required this.tid, required this.canonicalKey});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['tid'] = Variable<int>(tid);
    map['canonical_key'] = Variable<String>(canonicalKey);
    return map;
  }

  WorkIndexSourcesCompanion toCompanion(bool nullToAbsent) {
    return WorkIndexSourcesCompanion(
      tid: Value(tid),
      canonicalKey: Value(canonicalKey),
    );
  }

  factory WorkIndexSource.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkIndexSource(
      tid: serializer.fromJson<int>(json['tid']),
      canonicalKey: serializer.fromJson<String>(json['canonicalKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'tid': serializer.toJson<int>(tid),
      'canonicalKey': serializer.toJson<String>(canonicalKey),
    };
  }

  WorkIndexSource copyWith({int? tid, String? canonicalKey}) => WorkIndexSource(
    tid: tid ?? this.tid,
    canonicalKey: canonicalKey ?? this.canonicalKey,
  );
  WorkIndexSource copyWithCompanion(WorkIndexSourcesCompanion data) {
    return WorkIndexSource(
      tid: data.tid.present ? data.tid.value : this.tid,
      canonicalKey: data.canonicalKey.present
          ? data.canonicalKey.value
          : this.canonicalKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkIndexSource(')
          ..write('tid: $tid, ')
          ..write('canonicalKey: $canonicalKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(tid, canonicalKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkIndexSource &&
          other.tid == this.tid &&
          other.canonicalKey == this.canonicalKey);
}

class WorkIndexSourcesCompanion extends UpdateCompanion<WorkIndexSource> {
  final Value<int> tid;
  final Value<String> canonicalKey;
  const WorkIndexSourcesCompanion({
    this.tid = const Value.absent(),
    this.canonicalKey = const Value.absent(),
  });
  WorkIndexSourcesCompanion.insert({
    this.tid = const Value.absent(),
    required String canonicalKey,
  }) : canonicalKey = Value(canonicalKey);
  static Insertable<WorkIndexSource> custom({
    Expression<int>? tid,
    Expression<String>? canonicalKey,
  }) {
    return RawValuesInsertable({
      if (tid != null) 'tid': tid,
      if (canonicalKey != null) 'canonical_key': canonicalKey,
    });
  }

  WorkIndexSourcesCompanion copyWith({
    Value<int>? tid,
    Value<String>? canonicalKey,
  }) {
    return WorkIndexSourcesCompanion(
      tid: tid ?? this.tid,
      canonicalKey: canonicalKey ?? this.canonicalKey,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (tid.present) {
      map['tid'] = Variable<int>(tid.value);
    }
    if (canonicalKey.present) {
      map['canonical_key'] = Variable<String>(canonicalKey.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkIndexSourcesCompanion(')
          ..write('tid: $tid, ')
          ..write('canonicalKey: $canonicalKey')
          ..write(')'))
        .toString();
  }
}

class $ForumCachesTable extends ForumCaches
    with TableInfo<$ForumCachesTable, ForumCache> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ForumCachesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountKeyMeta = const VerificationMeta(
    'accountKey',
  );
  @override
  late final GeneratedColumn<String> accountKey = GeneratedColumn<String>(
    'account_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
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
    accountKey,
    cacheKey,
    payloadJson,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'forum_caches';
  @override
  VerificationContext validateIntegrity(
    Insertable<ForumCache> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_key')) {
      context.handle(
        _accountKeyMeta,
        accountKey.isAcceptableOrUnknown(data['account_key']!, _accountKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_accountKeyMeta);
    }
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
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
  Set<GeneratedColumn> get $primaryKey => {accountKey, cacheKey};
  @override
  ForumCache map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ForumCache(
      accountKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_key'],
      )!,
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ForumCachesTable createAlias(String alias) {
    return $ForumCachesTable(attachedDatabase, alias);
  }
}

class ForumCache extends DataClass implements Insertable<ForumCache> {
  final String accountKey;
  final String cacheKey;
  final String payloadJson;
  final DateTime updatedAt;
  const ForumCache({
    required this.accountKey,
    required this.cacheKey,
    required this.payloadJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_key'] = Variable<String>(accountKey);
    map['cache_key'] = Variable<String>(cacheKey);
    map['payload_json'] = Variable<String>(payloadJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ForumCachesCompanion toCompanion(bool nullToAbsent) {
    return ForumCachesCompanion(
      accountKey: Value(accountKey),
      cacheKey: Value(cacheKey),
      payloadJson: Value(payloadJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory ForumCache.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ForumCache(
      accountKey: serializer.fromJson<String>(json['accountKey']),
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountKey': serializer.toJson<String>(accountKey),
      'cacheKey': serializer.toJson<String>(cacheKey),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ForumCache copyWith({
    String? accountKey,
    String? cacheKey,
    String? payloadJson,
    DateTime? updatedAt,
  }) => ForumCache(
    accountKey: accountKey ?? this.accountKey,
    cacheKey: cacheKey ?? this.cacheKey,
    payloadJson: payloadJson ?? this.payloadJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ForumCache copyWithCompanion(ForumCachesCompanion data) {
    return ForumCache(
      accountKey: data.accountKey.present
          ? data.accountKey.value
          : this.accountKey,
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ForumCache(')
          ..write('accountKey: $accountKey, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountKey, cacheKey, payloadJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ForumCache &&
          other.accountKey == this.accountKey &&
          other.cacheKey == this.cacheKey &&
          other.payloadJson == this.payloadJson &&
          other.updatedAt == this.updatedAt);
}

class ForumCachesCompanion extends UpdateCompanion<ForumCache> {
  final Value<String> accountKey;
  final Value<String> cacheKey;
  final Value<String> payloadJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ForumCachesCompanion({
    this.accountKey = const Value.absent(),
    this.cacheKey = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ForumCachesCompanion.insert({
    required String accountKey,
    required String cacheKey,
    required String payloadJson,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : accountKey = Value(accountKey),
       cacheKey = Value(cacheKey),
       payloadJson = Value(payloadJson),
       updatedAt = Value(updatedAt);
  static Insertable<ForumCache> custom({
    Expression<String>? accountKey,
    Expression<String>? cacheKey,
    Expression<String>? payloadJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountKey != null) 'account_key': accountKey,
      if (cacheKey != null) 'cache_key': cacheKey,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ForumCachesCompanion copyWith({
    Value<String>? accountKey,
    Value<String>? cacheKey,
    Value<String>? payloadJson,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ForumCachesCompanion(
      accountKey: accountKey ?? this.accountKey,
      cacheKey: cacheKey ?? this.cacheKey,
      payloadJson: payloadJson ?? this.payloadJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountKey.present) {
      map['account_key'] = Variable<String>(accountKey.value);
    }
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
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
    return (StringBuffer('ForumCachesCompanion(')
          ..write('accountKey: $accountKey, ')
          ..write('cacheKey: $cacheKey, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ForumDraftsTable extends ForumDrafts
    with TableInfo<$ForumDraftsTable, ForumDraft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ForumDraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _draftIdMeta = const VerificationMeta(
    'draftId',
  );
  @override
  late final GeneratedColumn<String> draftId = GeneratedColumn<String>(
    'draft_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountKeyMeta = const VerificationMeta(
    'accountKey',
  );
  @override
  late final GeneratedColumn<String> accountKey = GeneratedColumn<String>(
    'account_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fidMeta = const VerificationMeta('fid');
  @override
  late final GeneratedColumn<int> fid = GeneratedColumn<int>(
    'fid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tidMeta = const VerificationMeta('tid');
  @override
  late final GeneratedColumn<int> tid = GeneratedColumn<int>(
    'tid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pidMeta = const VerificationMeta('pid');
  @override
  late final GeneratedColumn<int> pid = GeneratedColumn<int>(
    'pid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
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
    draftId,
    accountKey,
    action,
    fid,
    tid,
    pid,
    subject,
    message,
    attachmentsJson,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'forum_drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ForumDraft> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('draft_id')) {
      context.handle(
        _draftIdMeta,
        draftId.isAcceptableOrUnknown(data['draft_id']!, _draftIdMeta),
      );
    } else if (isInserting) {
      context.missing(_draftIdMeta);
    }
    if (data.containsKey('account_key')) {
      context.handle(
        _accountKeyMeta,
        accountKey.isAcceptableOrUnknown(data['account_key']!, _accountKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_accountKeyMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('fid')) {
      context.handle(
        _fidMeta,
        fid.isAcceptableOrUnknown(data['fid']!, _fidMeta),
      );
    }
    if (data.containsKey('tid')) {
      context.handle(
        _tidMeta,
        tid.isAcceptableOrUnknown(data['tid']!, _tidMeta),
      );
    }
    if (data.containsKey('pid')) {
      context.handle(
        _pidMeta,
        pid.isAcceptableOrUnknown(data['pid']!, _pidMeta),
      );
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attachmentsJsonMeta);
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
  Set<GeneratedColumn> get $primaryKey => {accountKey, draftId};
  @override
  ForumDraft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ForumDraft(
      draftId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}draft_id'],
      )!,
      accountKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_key'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      fid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fid'],
      ),
      tid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tid'],
      ),
      pid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pid'],
      ),
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      )!,
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ForumDraftsTable createAlias(String alias) {
    return $ForumDraftsTable(attachedDatabase, alias);
  }
}

class ForumDraft extends DataClass implements Insertable<ForumDraft> {
  final String draftId;
  final String accountKey;
  final String action;
  final int? fid;
  final int? tid;
  final int? pid;
  final String subject;
  final String message;
  final String attachmentsJson;
  final DateTime updatedAt;
  const ForumDraft({
    required this.draftId,
    required this.accountKey,
    required this.action,
    this.fid,
    this.tid,
    this.pid,
    required this.subject,
    required this.message,
    required this.attachmentsJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['draft_id'] = Variable<String>(draftId);
    map['account_key'] = Variable<String>(accountKey);
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || fid != null) {
      map['fid'] = Variable<int>(fid);
    }
    if (!nullToAbsent || tid != null) {
      map['tid'] = Variable<int>(tid);
    }
    if (!nullToAbsent || pid != null) {
      map['pid'] = Variable<int>(pid);
    }
    map['subject'] = Variable<String>(subject);
    map['message'] = Variable<String>(message);
    map['attachments_json'] = Variable<String>(attachmentsJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ForumDraftsCompanion toCompanion(bool nullToAbsent) {
    return ForumDraftsCompanion(
      draftId: Value(draftId),
      accountKey: Value(accountKey),
      action: Value(action),
      fid: fid == null && nullToAbsent ? const Value.absent() : Value(fid),
      tid: tid == null && nullToAbsent ? const Value.absent() : Value(tid),
      pid: pid == null && nullToAbsent ? const Value.absent() : Value(pid),
      subject: Value(subject),
      message: Value(message),
      attachmentsJson: Value(attachmentsJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory ForumDraft.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ForumDraft(
      draftId: serializer.fromJson<String>(json['draftId']),
      accountKey: serializer.fromJson<String>(json['accountKey']),
      action: serializer.fromJson<String>(json['action']),
      fid: serializer.fromJson<int?>(json['fid']),
      tid: serializer.fromJson<int?>(json['tid']),
      pid: serializer.fromJson<int?>(json['pid']),
      subject: serializer.fromJson<String>(json['subject']),
      message: serializer.fromJson<String>(json['message']),
      attachmentsJson: serializer.fromJson<String>(json['attachmentsJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'draftId': serializer.toJson<String>(draftId),
      'accountKey': serializer.toJson<String>(accountKey),
      'action': serializer.toJson<String>(action),
      'fid': serializer.toJson<int?>(fid),
      'tid': serializer.toJson<int?>(tid),
      'pid': serializer.toJson<int?>(pid),
      'subject': serializer.toJson<String>(subject),
      'message': serializer.toJson<String>(message),
      'attachmentsJson': serializer.toJson<String>(attachmentsJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ForumDraft copyWith({
    String? draftId,
    String? accountKey,
    String? action,
    Value<int?> fid = const Value.absent(),
    Value<int?> tid = const Value.absent(),
    Value<int?> pid = const Value.absent(),
    String? subject,
    String? message,
    String? attachmentsJson,
    DateTime? updatedAt,
  }) => ForumDraft(
    draftId: draftId ?? this.draftId,
    accountKey: accountKey ?? this.accountKey,
    action: action ?? this.action,
    fid: fid.present ? fid.value : this.fid,
    tid: tid.present ? tid.value : this.tid,
    pid: pid.present ? pid.value : this.pid,
    subject: subject ?? this.subject,
    message: message ?? this.message,
    attachmentsJson: attachmentsJson ?? this.attachmentsJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ForumDraft copyWithCompanion(ForumDraftsCompanion data) {
    return ForumDraft(
      draftId: data.draftId.present ? data.draftId.value : this.draftId,
      accountKey: data.accountKey.present
          ? data.accountKey.value
          : this.accountKey,
      action: data.action.present ? data.action.value : this.action,
      fid: data.fid.present ? data.fid.value : this.fid,
      tid: data.tid.present ? data.tid.value : this.tid,
      pid: data.pid.present ? data.pid.value : this.pid,
      subject: data.subject.present ? data.subject.value : this.subject,
      message: data.message.present ? data.message.value : this.message,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ForumDraft(')
          ..write('draftId: $draftId, ')
          ..write('accountKey: $accountKey, ')
          ..write('action: $action, ')
          ..write('fid: $fid, ')
          ..write('tid: $tid, ')
          ..write('pid: $pid, ')
          ..write('subject: $subject, ')
          ..write('message: $message, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    draftId,
    accountKey,
    action,
    fid,
    tid,
    pid,
    subject,
    message,
    attachmentsJson,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ForumDraft &&
          other.draftId == this.draftId &&
          other.accountKey == this.accountKey &&
          other.action == this.action &&
          other.fid == this.fid &&
          other.tid == this.tid &&
          other.pid == this.pid &&
          other.subject == this.subject &&
          other.message == this.message &&
          other.attachmentsJson == this.attachmentsJson &&
          other.updatedAt == this.updatedAt);
}

class ForumDraftsCompanion extends UpdateCompanion<ForumDraft> {
  final Value<String> draftId;
  final Value<String> accountKey;
  final Value<String> action;
  final Value<int?> fid;
  final Value<int?> tid;
  final Value<int?> pid;
  final Value<String> subject;
  final Value<String> message;
  final Value<String> attachmentsJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ForumDraftsCompanion({
    this.draftId = const Value.absent(),
    this.accountKey = const Value.absent(),
    this.action = const Value.absent(),
    this.fid = const Value.absent(),
    this.tid = const Value.absent(),
    this.pid = const Value.absent(),
    this.subject = const Value.absent(),
    this.message = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ForumDraftsCompanion.insert({
    required String draftId,
    required String accountKey,
    required String action,
    this.fid = const Value.absent(),
    this.tid = const Value.absent(),
    this.pid = const Value.absent(),
    required String subject,
    required String message,
    required String attachmentsJson,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : draftId = Value(draftId),
       accountKey = Value(accountKey),
       action = Value(action),
       subject = Value(subject),
       message = Value(message),
       attachmentsJson = Value(attachmentsJson),
       updatedAt = Value(updatedAt);
  static Insertable<ForumDraft> custom({
    Expression<String>? draftId,
    Expression<String>? accountKey,
    Expression<String>? action,
    Expression<int>? fid,
    Expression<int>? tid,
    Expression<int>? pid,
    Expression<String>? subject,
    Expression<String>? message,
    Expression<String>? attachmentsJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (draftId != null) 'draft_id': draftId,
      if (accountKey != null) 'account_key': accountKey,
      if (action != null) 'action': action,
      if (fid != null) 'fid': fid,
      if (tid != null) 'tid': tid,
      if (pid != null) 'pid': pid,
      if (subject != null) 'subject': subject,
      if (message != null) 'message': message,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ForumDraftsCompanion copyWith({
    Value<String>? draftId,
    Value<String>? accountKey,
    Value<String>? action,
    Value<int?>? fid,
    Value<int?>? tid,
    Value<int?>? pid,
    Value<String>? subject,
    Value<String>? message,
    Value<String>? attachmentsJson,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ForumDraftsCompanion(
      draftId: draftId ?? this.draftId,
      accountKey: accountKey ?? this.accountKey,
      action: action ?? this.action,
      fid: fid ?? this.fid,
      tid: tid ?? this.tid,
      pid: pid ?? this.pid,
      subject: subject ?? this.subject,
      message: message ?? this.message,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (draftId.present) {
      map['draft_id'] = Variable<String>(draftId.value);
    }
    if (accountKey.present) {
      map['account_key'] = Variable<String>(accountKey.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (fid.present) {
      map['fid'] = Variable<int>(fid.value);
    }
    if (tid.present) {
      map['tid'] = Variable<int>(tid.value);
    }
    if (pid.present) {
      map['pid'] = Variable<int>(pid.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
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
    return (StringBuffer('ForumDraftsCompanion(')
          ..write('draftId: $draftId, ')
          ..write('accountKey: $accountKey, ')
          ..write('action: $action, ')
          ..write('fid: $fid, ')
          ..write('tid: $tid, ')
          ..write('pid: $pid, ')
          ..write('subject: $subject, ')
          ..write('message: $message, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ForumReadAnchorsTable extends ForumReadAnchors
    with TableInfo<$ForumReadAnchorsTable, ForumReadAnchor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ForumReadAnchorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountKeyMeta = const VerificationMeta(
    'accountKey',
  );
  @override
  late final GeneratedColumn<String> accountKey = GeneratedColumn<String>(
    'account_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tidMeta = const VerificationMeta('tid');
  @override
  late final GeneratedColumn<int> tid = GeneratedColumn<int>(
    'tid',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pidMeta = const VerificationMeta('pid');
  @override
  late final GeneratedColumn<int> pid = GeneratedColumn<int>(
    'pid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageMeta = const VerificationMeta('page');
  @override
  late final GeneratedColumn<int> page = GeneratedColumn<int>(
    'page',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _floorMeta = const VerificationMeta('floor');
  @override
  late final GeneratedColumn<int> floor = GeneratedColumn<int>(
    'floor',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
    accountKey,
    tid,
    pid,
    page,
    floor,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'forum_read_anchors';
  @override
  VerificationContext validateIntegrity(
    Insertable<ForumReadAnchor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_key')) {
      context.handle(
        _accountKeyMeta,
        accountKey.isAcceptableOrUnknown(data['account_key']!, _accountKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_accountKeyMeta);
    }
    if (data.containsKey('tid')) {
      context.handle(
        _tidMeta,
        tid.isAcceptableOrUnknown(data['tid']!, _tidMeta),
      );
    } else if (isInserting) {
      context.missing(_tidMeta);
    }
    if (data.containsKey('pid')) {
      context.handle(
        _pidMeta,
        pid.isAcceptableOrUnknown(data['pid']!, _pidMeta),
      );
    }
    if (data.containsKey('page')) {
      context.handle(
        _pageMeta,
        page.isAcceptableOrUnknown(data['page']!, _pageMeta),
      );
    } else if (isInserting) {
      context.missing(_pageMeta);
    }
    if (data.containsKey('floor')) {
      context.handle(
        _floorMeta,
        floor.isAcceptableOrUnknown(data['floor']!, _floorMeta),
      );
    } else if (isInserting) {
      context.missing(_floorMeta);
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
  Set<GeneratedColumn> get $primaryKey => {accountKey, tid};
  @override
  ForumReadAnchor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ForumReadAnchor(
      accountKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_key'],
      )!,
      tid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tid'],
      )!,
      pid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pid'],
      ),
      page: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page'],
      )!,
      floor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}floor'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ForumReadAnchorsTable createAlias(String alias) {
    return $ForumReadAnchorsTable(attachedDatabase, alias);
  }
}

class ForumReadAnchor extends DataClass implements Insertable<ForumReadAnchor> {
  final String accountKey;
  final int tid;
  final int? pid;
  final int page;
  final int floor;
  final DateTime updatedAt;
  const ForumReadAnchor({
    required this.accountKey,
    required this.tid,
    this.pid,
    required this.page,
    required this.floor,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_key'] = Variable<String>(accountKey);
    map['tid'] = Variable<int>(tid);
    if (!nullToAbsent || pid != null) {
      map['pid'] = Variable<int>(pid);
    }
    map['page'] = Variable<int>(page);
    map['floor'] = Variable<int>(floor);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ForumReadAnchorsCompanion toCompanion(bool nullToAbsent) {
    return ForumReadAnchorsCompanion(
      accountKey: Value(accountKey),
      tid: Value(tid),
      pid: pid == null && nullToAbsent ? const Value.absent() : Value(pid),
      page: Value(page),
      floor: Value(floor),
      updatedAt: Value(updatedAt),
    );
  }

  factory ForumReadAnchor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ForumReadAnchor(
      accountKey: serializer.fromJson<String>(json['accountKey']),
      tid: serializer.fromJson<int>(json['tid']),
      pid: serializer.fromJson<int?>(json['pid']),
      page: serializer.fromJson<int>(json['page']),
      floor: serializer.fromJson<int>(json['floor']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountKey': serializer.toJson<String>(accountKey),
      'tid': serializer.toJson<int>(tid),
      'pid': serializer.toJson<int?>(pid),
      'page': serializer.toJson<int>(page),
      'floor': serializer.toJson<int>(floor),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ForumReadAnchor copyWith({
    String? accountKey,
    int? tid,
    Value<int?> pid = const Value.absent(),
    int? page,
    int? floor,
    DateTime? updatedAt,
  }) => ForumReadAnchor(
    accountKey: accountKey ?? this.accountKey,
    tid: tid ?? this.tid,
    pid: pid.present ? pid.value : this.pid,
    page: page ?? this.page,
    floor: floor ?? this.floor,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ForumReadAnchor copyWithCompanion(ForumReadAnchorsCompanion data) {
    return ForumReadAnchor(
      accountKey: data.accountKey.present
          ? data.accountKey.value
          : this.accountKey,
      tid: data.tid.present ? data.tid.value : this.tid,
      pid: data.pid.present ? data.pid.value : this.pid,
      page: data.page.present ? data.page.value : this.page,
      floor: data.floor.present ? data.floor.value : this.floor,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ForumReadAnchor(')
          ..write('accountKey: $accountKey, ')
          ..write('tid: $tid, ')
          ..write('pid: $pid, ')
          ..write('page: $page, ')
          ..write('floor: $floor, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(accountKey, tid, pid, page, floor, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ForumReadAnchor &&
          other.accountKey == this.accountKey &&
          other.tid == this.tid &&
          other.pid == this.pid &&
          other.page == this.page &&
          other.floor == this.floor &&
          other.updatedAt == this.updatedAt);
}

class ForumReadAnchorsCompanion extends UpdateCompanion<ForumReadAnchor> {
  final Value<String> accountKey;
  final Value<int> tid;
  final Value<int?> pid;
  final Value<int> page;
  final Value<int> floor;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ForumReadAnchorsCompanion({
    this.accountKey = const Value.absent(),
    this.tid = const Value.absent(),
    this.pid = const Value.absent(),
    this.page = const Value.absent(),
    this.floor = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ForumReadAnchorsCompanion.insert({
    required String accountKey,
    required int tid,
    this.pid = const Value.absent(),
    required int page,
    required int floor,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : accountKey = Value(accountKey),
       tid = Value(tid),
       page = Value(page),
       floor = Value(floor),
       updatedAt = Value(updatedAt);
  static Insertable<ForumReadAnchor> custom({
    Expression<String>? accountKey,
    Expression<int>? tid,
    Expression<int>? pid,
    Expression<int>? page,
    Expression<int>? floor,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountKey != null) 'account_key': accountKey,
      if (tid != null) 'tid': tid,
      if (pid != null) 'pid': pid,
      if (page != null) 'page': page,
      if (floor != null) 'floor': floor,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ForumReadAnchorsCompanion copyWith({
    Value<String>? accountKey,
    Value<int>? tid,
    Value<int?>? pid,
    Value<int>? page,
    Value<int>? floor,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ForumReadAnchorsCompanion(
      accountKey: accountKey ?? this.accountKey,
      tid: tid ?? this.tid,
      pid: pid ?? this.pid,
      page: page ?? this.page,
      floor: floor ?? this.floor,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountKey.present) {
      map['account_key'] = Variable<String>(accountKey.value);
    }
    if (tid.present) {
      map['tid'] = Variable<int>(tid.value);
    }
    if (pid.present) {
      map['pid'] = Variable<int>(pid.value);
    }
    if (page.present) {
      map['page'] = Variable<int>(page.value);
    }
    if (floor.present) {
      map['floor'] = Variable<int>(floor.value);
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
    return (StringBuffer('ForumReadAnchorsCompanion(')
          ..write('accountKey: $accountKey, ')
          ..write('tid: $tid, ')
          ..write('pid: $pid, ')
          ..write('page: $page, ')
          ..write('floor: $floor, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ForumActionTombstonesTable extends ForumActionTombstones
    with TableInfo<$ForumActionTombstonesTable, ForumActionTombstone> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ForumActionTombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _accountKeyMeta = const VerificationMeta(
    'accountKey',
  );
  @override
  late final GeneratedColumn<String> accountKey = GeneratedColumn<String>(
    'account_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contextKeyMeta = const VerificationMeta(
    'contextKey',
  );
  @override
  late final GeneratedColumn<String> contextKey = GeneratedColumn<String>(
    'context_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptIdMeta = const VerificationMeta(
    'attemptId',
  );
  @override
  late final GeneratedColumn<String> attemptId = GeneratedColumn<String>(
    'attempt_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fidMeta = const VerificationMeta('fid');
  @override
  late final GeneratedColumn<int> fid = GeneratedColumn<int>(
    'fid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tidMeta = const VerificationMeta('tid');
  @override
  late final GeneratedColumn<int> tid = GeneratedColumn<int>(
    'tid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pidMeta = const VerificationMeta('pid');
  @override
  late final GeneratedColumn<int> pid = GeneratedColumn<int>(
    'pid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _favoriteIdMeta = const VerificationMeta(
    'favoriteId',
  );
  @override
  late final GeneratedColumn<int> favoriteId = GeneratedColumn<int>(
    'favorite_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _draftContextMeta = const VerificationMeta(
    'draftContext',
  );
  @override
  late final GeneratedColumn<String> draftContext = GeneratedColumn<String>(
    'draft_context',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
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
    accountKey,
    contextKey,
    attemptId,
    action,
    fid,
    tid,
    pid,
    favoriteId,
    draftContext,
    status,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'forum_action_tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<ForumActionTombstone> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('account_key')) {
      context.handle(
        _accountKeyMeta,
        accountKey.isAcceptableOrUnknown(data['account_key']!, _accountKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_accountKeyMeta);
    }
    if (data.containsKey('context_key')) {
      context.handle(
        _contextKeyMeta,
        contextKey.isAcceptableOrUnknown(data['context_key']!, _contextKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_contextKeyMeta);
    }
    if (data.containsKey('attempt_id')) {
      context.handle(
        _attemptIdMeta,
        attemptId.isAcceptableOrUnknown(data['attempt_id']!, _attemptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_attemptIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('fid')) {
      context.handle(
        _fidMeta,
        fid.isAcceptableOrUnknown(data['fid']!, _fidMeta),
      );
    }
    if (data.containsKey('tid')) {
      context.handle(
        _tidMeta,
        tid.isAcceptableOrUnknown(data['tid']!, _tidMeta),
      );
    }
    if (data.containsKey('pid')) {
      context.handle(
        _pidMeta,
        pid.isAcceptableOrUnknown(data['pid']!, _pidMeta),
      );
    }
    if (data.containsKey('favorite_id')) {
      context.handle(
        _favoriteIdMeta,
        favoriteId.isAcceptableOrUnknown(data['favorite_id']!, _favoriteIdMeta),
      );
    }
    if (data.containsKey('draft_context')) {
      context.handle(
        _draftContextMeta,
        draftContext.isAcceptableOrUnknown(
          data['draft_context']!,
          _draftContextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_draftContextMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
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
  Set<GeneratedColumn> get $primaryKey => {accountKey, contextKey};
  @override
  ForumActionTombstone map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ForumActionTombstone(
      accountKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_key'],
      )!,
      contextKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context_key'],
      )!,
      attemptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attempt_id'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      fid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fid'],
      ),
      tid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tid'],
      ),
      pid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pid'],
      ),
      favoriteId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}favorite_id'],
      ),
      draftContext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}draft_context'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
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
  $ForumActionTombstonesTable createAlias(String alias) {
    return $ForumActionTombstonesTable(attachedDatabase, alias);
  }
}

class ForumActionTombstone extends DataClass
    implements Insertable<ForumActionTombstone> {
  final String accountKey;
  final String contextKey;
  final String attemptId;
  final String action;
  final int? fid;
  final int? tid;
  final int? pid;
  final int? favoriteId;
  final String draftContext;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ForumActionTombstone({
    required this.accountKey,
    required this.contextKey,
    required this.attemptId,
    required this.action,
    this.fid,
    this.tid,
    this.pid,
    this.favoriteId,
    required this.draftContext,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['account_key'] = Variable<String>(accountKey);
    map['context_key'] = Variable<String>(contextKey);
    map['attempt_id'] = Variable<String>(attemptId);
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || fid != null) {
      map['fid'] = Variable<int>(fid);
    }
    if (!nullToAbsent || tid != null) {
      map['tid'] = Variable<int>(tid);
    }
    if (!nullToAbsent || pid != null) {
      map['pid'] = Variable<int>(pid);
    }
    if (!nullToAbsent || favoriteId != null) {
      map['favorite_id'] = Variable<int>(favoriteId);
    }
    map['draft_context'] = Variable<String>(draftContext);
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ForumActionTombstonesCompanion toCompanion(bool nullToAbsent) {
    return ForumActionTombstonesCompanion(
      accountKey: Value(accountKey),
      contextKey: Value(contextKey),
      attemptId: Value(attemptId),
      action: Value(action),
      fid: fid == null && nullToAbsent ? const Value.absent() : Value(fid),
      tid: tid == null && nullToAbsent ? const Value.absent() : Value(tid),
      pid: pid == null && nullToAbsent ? const Value.absent() : Value(pid),
      favoriteId: favoriteId == null && nullToAbsent
          ? const Value.absent()
          : Value(favoriteId),
      draftContext: Value(draftContext),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ForumActionTombstone.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ForumActionTombstone(
      accountKey: serializer.fromJson<String>(json['accountKey']),
      contextKey: serializer.fromJson<String>(json['contextKey']),
      attemptId: serializer.fromJson<String>(json['attemptId']),
      action: serializer.fromJson<String>(json['action']),
      fid: serializer.fromJson<int?>(json['fid']),
      tid: serializer.fromJson<int?>(json['tid']),
      pid: serializer.fromJson<int?>(json['pid']),
      favoriteId: serializer.fromJson<int?>(json['favoriteId']),
      draftContext: serializer.fromJson<String>(json['draftContext']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'accountKey': serializer.toJson<String>(accountKey),
      'contextKey': serializer.toJson<String>(contextKey),
      'attemptId': serializer.toJson<String>(attemptId),
      'action': serializer.toJson<String>(action),
      'fid': serializer.toJson<int?>(fid),
      'tid': serializer.toJson<int?>(tid),
      'pid': serializer.toJson<int?>(pid),
      'favoriteId': serializer.toJson<int?>(favoriteId),
      'draftContext': serializer.toJson<String>(draftContext),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ForumActionTombstone copyWith({
    String? accountKey,
    String? contextKey,
    String? attemptId,
    String? action,
    Value<int?> fid = const Value.absent(),
    Value<int?> tid = const Value.absent(),
    Value<int?> pid = const Value.absent(),
    Value<int?> favoriteId = const Value.absent(),
    String? draftContext,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => ForumActionTombstone(
    accountKey: accountKey ?? this.accountKey,
    contextKey: contextKey ?? this.contextKey,
    attemptId: attemptId ?? this.attemptId,
    action: action ?? this.action,
    fid: fid.present ? fid.value : this.fid,
    tid: tid.present ? tid.value : this.tid,
    pid: pid.present ? pid.value : this.pid,
    favoriteId: favoriteId.present ? favoriteId.value : this.favoriteId,
    draftContext: draftContext ?? this.draftContext,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ForumActionTombstone copyWithCompanion(ForumActionTombstonesCompanion data) {
    return ForumActionTombstone(
      accountKey: data.accountKey.present
          ? data.accountKey.value
          : this.accountKey,
      contextKey: data.contextKey.present
          ? data.contextKey.value
          : this.contextKey,
      attemptId: data.attemptId.present ? data.attemptId.value : this.attemptId,
      action: data.action.present ? data.action.value : this.action,
      fid: data.fid.present ? data.fid.value : this.fid,
      tid: data.tid.present ? data.tid.value : this.tid,
      pid: data.pid.present ? data.pid.value : this.pid,
      favoriteId: data.favoriteId.present
          ? data.favoriteId.value
          : this.favoriteId,
      draftContext: data.draftContext.present
          ? data.draftContext.value
          : this.draftContext,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ForumActionTombstone(')
          ..write('accountKey: $accountKey, ')
          ..write('contextKey: $contextKey, ')
          ..write('attemptId: $attemptId, ')
          ..write('action: $action, ')
          ..write('fid: $fid, ')
          ..write('tid: $tid, ')
          ..write('pid: $pid, ')
          ..write('favoriteId: $favoriteId, ')
          ..write('draftContext: $draftContext, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    accountKey,
    contextKey,
    attemptId,
    action,
    fid,
    tid,
    pid,
    favoriteId,
    draftContext,
    status,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ForumActionTombstone &&
          other.accountKey == this.accountKey &&
          other.contextKey == this.contextKey &&
          other.attemptId == this.attemptId &&
          other.action == this.action &&
          other.fid == this.fid &&
          other.tid == this.tid &&
          other.pid == this.pid &&
          other.favoriteId == this.favoriteId &&
          other.draftContext == this.draftContext &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ForumActionTombstonesCompanion
    extends UpdateCompanion<ForumActionTombstone> {
  final Value<String> accountKey;
  final Value<String> contextKey;
  final Value<String> attemptId;
  final Value<String> action;
  final Value<int?> fid;
  final Value<int?> tid;
  final Value<int?> pid;
  final Value<int?> favoriteId;
  final Value<String> draftContext;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ForumActionTombstonesCompanion({
    this.accountKey = const Value.absent(),
    this.contextKey = const Value.absent(),
    this.attemptId = const Value.absent(),
    this.action = const Value.absent(),
    this.fid = const Value.absent(),
    this.tid = const Value.absent(),
    this.pid = const Value.absent(),
    this.favoriteId = const Value.absent(),
    this.draftContext = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ForumActionTombstonesCompanion.insert({
    required String accountKey,
    required String contextKey,
    required String attemptId,
    required String action,
    this.fid = const Value.absent(),
    this.tid = const Value.absent(),
    this.pid = const Value.absent(),
    this.favoriteId = const Value.absent(),
    required String draftContext,
    required String status,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : accountKey = Value(accountKey),
       contextKey = Value(contextKey),
       attemptId = Value(attemptId),
       action = Value(action),
       draftContext = Value(draftContext),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ForumActionTombstone> custom({
    Expression<String>? accountKey,
    Expression<String>? contextKey,
    Expression<String>? attemptId,
    Expression<String>? action,
    Expression<int>? fid,
    Expression<int>? tid,
    Expression<int>? pid,
    Expression<int>? favoriteId,
    Expression<String>? draftContext,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (accountKey != null) 'account_key': accountKey,
      if (contextKey != null) 'context_key': contextKey,
      if (attemptId != null) 'attempt_id': attemptId,
      if (action != null) 'action': action,
      if (fid != null) 'fid': fid,
      if (tid != null) 'tid': tid,
      if (pid != null) 'pid': pid,
      if (favoriteId != null) 'favorite_id': favoriteId,
      if (draftContext != null) 'draft_context': draftContext,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ForumActionTombstonesCompanion copyWith({
    Value<String>? accountKey,
    Value<String>? contextKey,
    Value<String>? attemptId,
    Value<String>? action,
    Value<int?>? fid,
    Value<int?>? tid,
    Value<int?>? pid,
    Value<int?>? favoriteId,
    Value<String>? draftContext,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ForumActionTombstonesCompanion(
      accountKey: accountKey ?? this.accountKey,
      contextKey: contextKey ?? this.contextKey,
      attemptId: attemptId ?? this.attemptId,
      action: action ?? this.action,
      fid: fid ?? this.fid,
      tid: tid ?? this.tid,
      pid: pid ?? this.pid,
      favoriteId: favoriteId ?? this.favoriteId,
      draftContext: draftContext ?? this.draftContext,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (accountKey.present) {
      map['account_key'] = Variable<String>(accountKey.value);
    }
    if (contextKey.present) {
      map['context_key'] = Variable<String>(contextKey.value);
    }
    if (attemptId.present) {
      map['attempt_id'] = Variable<String>(attemptId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (fid.present) {
      map['fid'] = Variable<int>(fid.value);
    }
    if (tid.present) {
      map['tid'] = Variable<int>(tid.value);
    }
    if (pid.present) {
      map['pid'] = Variable<int>(pid.value);
    }
    if (favoriteId.present) {
      map['favorite_id'] = Variable<int>(favoriteId.value);
    }
    if (draftContext.present) {
      map['draft_context'] = Variable<String>(draftContext.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
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
    return (StringBuffer('ForumActionTombstonesCompanion(')
          ..write('accountKey: $accountKey, ')
          ..write('contextKey: $contextKey, ')
          ..write('attemptId: $attemptId, ')
          ..write('action: $action, ')
          ..write('fid: $fid, ')
          ..write('tid: $tid, ')
          ..write('pid: $pid, ')
          ..write('favoriteId: $favoriteId, ')
          ..write('draftContext: $draftContext, ')
          ..write('status: $status, ')
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
  late final $ReadingStatesTable readingStates = $ReadingStatesTable(this);
  late final $SearchCachesTable searchCaches = $SearchCachesTable(this);
  late final $FavoriteCachesTable favoriteCaches = $FavoriteCachesTable(this);
  late final $DownloadTasksTable downloadTasks = $DownloadTasksTable(this);
  late final $CoverCachesTable coverCaches = $CoverCachesTable(this);
  late final $CoverEntriesTable coverEntries = $CoverEntriesTable(this);
  late final $CoverAliasesTable coverAliases = $CoverAliasesTable(this);
  late final $WorkIndexesTable workIndexes = $WorkIndexesTable(this);
  late final $WorkIndexSourcesTable workIndexSources = $WorkIndexSourcesTable(
    this,
  );
  late final $ForumCachesTable forumCaches = $ForumCachesTable(this);
  late final $ForumDraftsTable forumDrafts = $ForumDraftsTable(this);
  late final $ForumReadAnchorsTable forumReadAnchors = $ForumReadAnchorsTable(
    this,
  );
  late final $ForumActionTombstonesTable forumActionTombstones =
      $ForumActionTombstonesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    readingStates,
    searchCaches,
    favoriteCaches,
    downloadTasks,
    coverCaches,
    coverEntries,
    coverAliases,
    workIndexes,
    workIndexSources,
    forumCaches,
    forumDrafts,
    forumReadAnchors,
    forumActionTombstones,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'cover_entries',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('cover_aliases', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'work_indexes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('work_index_sources', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$ReadingStatesTableCreateCompanionBuilder =
    ReadingStatesCompanion Function({
      required String workId,
      required String libraryKind,
      required String workJson,
      required String chapterId,
      required String chapterTitle,
      required int chapterIndex,
      required int position,
      required double progress,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ReadingStatesTableUpdateCompanionBuilder =
    ReadingStatesCompanion Function({
      Value<String> workId,
      Value<String> libraryKind,
      Value<String> workJson,
      Value<String> chapterId,
      Value<String> chapterTitle,
      Value<int> chapterIndex,
      Value<int> position,
      Value<double> progress,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ReadingStatesTableFilterComposer
    extends Composer<_$AppDatabase, $ReadingStatesTable> {
  $$ReadingStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workJson => $composableBuilder(
    column: $table.workJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReadingStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $ReadingStatesTable> {
  $$ReadingStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workJson => $composableBuilder(
    column: $table.workJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReadingStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReadingStatesTable> {
  $$ReadingStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get workId =>
      $composableBuilder(column: $table.workId, builder: (column) => column);

  GeneratedColumn<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get workJson =>
      $composableBuilder(column: $table.workJson, builder: (column) => column);

  GeneratedColumn<String> get chapterId =>
      $composableBuilder(column: $table.chapterId, builder: (column) => column);

  GeneratedColumn<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ReadingStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReadingStatesTable,
          ReadingState,
          $$ReadingStatesTableFilterComposer,
          $$ReadingStatesTableOrderingComposer,
          $$ReadingStatesTableAnnotationComposer,
          $$ReadingStatesTableCreateCompanionBuilder,
          $$ReadingStatesTableUpdateCompanionBuilder,
          (
            ReadingState,
            BaseReferences<_$AppDatabase, $ReadingStatesTable, ReadingState>,
          ),
          ReadingState,
          PrefetchHooks Function()
        > {
  $$ReadingStatesTableTableManager(_$AppDatabase db, $ReadingStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadingStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> workId = const Value.absent(),
                Value<String> libraryKind = const Value.absent(),
                Value<String> workJson = const Value.absent(),
                Value<String> chapterId = const Value.absent(),
                Value<String> chapterTitle = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingStatesCompanion(
                workId: workId,
                libraryKind: libraryKind,
                workJson: workJson,
                chapterId: chapterId,
                chapterTitle: chapterTitle,
                chapterIndex: chapterIndex,
                position: position,
                progress: progress,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String workId,
                required String libraryKind,
                required String workJson,
                required String chapterId,
                required String chapterTitle,
                required int chapterIndex,
                required int position,
                required double progress,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ReadingStatesCompanion.insert(
                workId: workId,
                libraryKind: libraryKind,
                workJson: workJson,
                chapterId: chapterId,
                chapterTitle: chapterTitle,
                chapterIndex: chapterIndex,
                position: position,
                progress: progress,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReadingStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReadingStatesTable,
      ReadingState,
      $$ReadingStatesTableFilterComposer,
      $$ReadingStatesTableOrderingComposer,
      $$ReadingStatesTableAnnotationComposer,
      $$ReadingStatesTableCreateCompanionBuilder,
      $$ReadingStatesTableUpdateCompanionBuilder,
      (
        ReadingState,
        BaseReferences<_$AppDatabase, $ReadingStatesTable, ReadingState>,
      ),
      ReadingState,
      PrefetchHooks Function()
    >;
typedef $$SearchCachesTableCreateCompanionBuilder =
    SearchCachesCompanion Function({
      required String cacheKey,
      required String libraryKind,
      required String keyword,
      required String worksJson,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SearchCachesTableUpdateCompanionBuilder =
    SearchCachesCompanion Function({
      Value<String> cacheKey,
      Value<String> libraryKind,
      Value<String> keyword,
      Value<String> worksJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SearchCachesTableFilterComposer
    extends Composer<_$AppDatabase, $SearchCachesTable> {
  $$SearchCachesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get keyword => $composableBuilder(
    column: $table.keyword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get worksJson => $composableBuilder(
    column: $table.worksJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SearchCachesTableOrderingComposer
    extends Composer<_$AppDatabase, $SearchCachesTable> {
  $$SearchCachesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get keyword => $composableBuilder(
    column: $table.keyword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get worksJson => $composableBuilder(
    column: $table.worksJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SearchCachesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SearchCachesTable> {
  $$SearchCachesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get keyword =>
      $composableBuilder(column: $table.keyword, builder: (column) => column);

  GeneratedColumn<String> get worksJson =>
      $composableBuilder(column: $table.worksJson, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SearchCachesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SearchCachesTable,
          SearchCache,
          $$SearchCachesTableFilterComposer,
          $$SearchCachesTableOrderingComposer,
          $$SearchCachesTableAnnotationComposer,
          $$SearchCachesTableCreateCompanionBuilder,
          $$SearchCachesTableUpdateCompanionBuilder,
          (
            SearchCache,
            BaseReferences<_$AppDatabase, $SearchCachesTable, SearchCache>,
          ),
          SearchCache,
          PrefetchHooks Function()
        > {
  $$SearchCachesTableTableManager(_$AppDatabase db, $SearchCachesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SearchCachesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SearchCachesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SearchCachesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> cacheKey = const Value.absent(),
                Value<String> libraryKind = const Value.absent(),
                Value<String> keyword = const Value.absent(),
                Value<String> worksJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SearchCachesCompanion(
                cacheKey: cacheKey,
                libraryKind: libraryKind,
                keyword: keyword,
                worksJson: worksJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cacheKey,
                required String libraryKind,
                required String keyword,
                required String worksJson,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SearchCachesCompanion.insert(
                cacheKey: cacheKey,
                libraryKind: libraryKind,
                keyword: keyword,
                worksJson: worksJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SearchCachesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SearchCachesTable,
      SearchCache,
      $$SearchCachesTableFilterComposer,
      $$SearchCachesTableOrderingComposer,
      $$SearchCachesTableAnnotationComposer,
      $$SearchCachesTableCreateCompanionBuilder,
      $$SearchCachesTableUpdateCompanionBuilder,
      (
        SearchCache,
        BaseReferences<_$AppDatabase, $SearchCachesTable, SearchCache>,
      ),
      SearchCache,
      PrefetchHooks Function()
    >;
typedef $$FavoriteCachesTableCreateCompanionBuilder =
    FavoriteCachesCompanion Function({
      required int userId,
      required String workId,
      required String workJson,
      required String recordsJson,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$FavoriteCachesTableUpdateCompanionBuilder =
    FavoriteCachesCompanion Function({
      Value<int> userId,
      Value<String> workId,
      Value<String> workJson,
      Value<String> recordsJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$FavoriteCachesTableFilterComposer
    extends Composer<_$AppDatabase, $FavoriteCachesTable> {
  $$FavoriteCachesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workJson => $composableBuilder(
    column: $table.workJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordsJson => $composableBuilder(
    column: $table.recordsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FavoriteCachesTableOrderingComposer
    extends Composer<_$AppDatabase, $FavoriteCachesTable> {
  $$FavoriteCachesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workJson => $composableBuilder(
    column: $table.workJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordsJson => $composableBuilder(
    column: $table.recordsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FavoriteCachesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FavoriteCachesTable> {
  $$FavoriteCachesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get workId =>
      $composableBuilder(column: $table.workId, builder: (column) => column);

  GeneratedColumn<String> get workJson =>
      $composableBuilder(column: $table.workJson, builder: (column) => column);

  GeneratedColumn<String> get recordsJson => $composableBuilder(
    column: $table.recordsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$FavoriteCachesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FavoriteCachesTable,
          FavoriteCache,
          $$FavoriteCachesTableFilterComposer,
          $$FavoriteCachesTableOrderingComposer,
          $$FavoriteCachesTableAnnotationComposer,
          $$FavoriteCachesTableCreateCompanionBuilder,
          $$FavoriteCachesTableUpdateCompanionBuilder,
          (
            FavoriteCache,
            BaseReferences<_$AppDatabase, $FavoriteCachesTable, FavoriteCache>,
          ),
          FavoriteCache,
          PrefetchHooks Function()
        > {
  $$FavoriteCachesTableTableManager(
    _$AppDatabase db,
    $FavoriteCachesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FavoriteCachesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FavoriteCachesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FavoriteCachesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> userId = const Value.absent(),
                Value<String> workId = const Value.absent(),
                Value<String> workJson = const Value.absent(),
                Value<String> recordsJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FavoriteCachesCompanion(
                userId: userId,
                workId: workId,
                workJson: workJson,
                recordsJson: recordsJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int userId,
                required String workId,
                required String workJson,
                required String recordsJson,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => FavoriteCachesCompanion.insert(
                userId: userId,
                workId: workId,
                workJson: workJson,
                recordsJson: recordsJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FavoriteCachesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FavoriteCachesTable,
      FavoriteCache,
      $$FavoriteCachesTableFilterComposer,
      $$FavoriteCachesTableOrderingComposer,
      $$FavoriteCachesTableAnnotationComposer,
      $$FavoriteCachesTableCreateCompanionBuilder,
      $$FavoriteCachesTableUpdateCompanionBuilder,
      (
        FavoriteCache,
        BaseReferences<_$AppDatabase, $FavoriteCachesTable, FavoriteCache>,
      ),
      FavoriteCache,
      PrefetchHooks Function()
    >;
typedef $$DownloadTasksTableCreateCompanionBuilder =
    DownloadTasksCompanion Function({
      required String taskId,
      required String workId,
      required String libraryKind,
      required String workJson,
      required String chapterJson,
      required String status,
      required int completedItems,
      required int totalItems,
      required String directoryPath,
      required String payloadJson,
      required String errorMessage,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$DownloadTasksTableUpdateCompanionBuilder =
    DownloadTasksCompanion Function({
      Value<String> taskId,
      Value<String> workId,
      Value<String> libraryKind,
      Value<String> workJson,
      Value<String> chapterJson,
      Value<String> status,
      Value<int> completedItems,
      Value<int> totalItems,
      Value<String> directoryPath,
      Value<String> payloadJson,
      Value<String> errorMessage,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$DownloadTasksTableFilterComposer
    extends Composer<_$AppDatabase, $DownloadTasksTable> {
  $$DownloadTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workJson => $composableBuilder(
    column: $table.workJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterJson => $composableBuilder(
    column: $table.chapterJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedItems => $composableBuilder(
    column: $table.completedItems,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalItems => $composableBuilder(
    column: $table.totalItems,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get directoryPath => $composableBuilder(
    column: $table.directoryPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DownloadTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $DownloadTasksTable> {
  $$DownloadTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workJson => $composableBuilder(
    column: $table.workJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterJson => $composableBuilder(
    column: $table.chapterJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedItems => $composableBuilder(
    column: $table.completedItems,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalItems => $composableBuilder(
    column: $table.totalItems,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get directoryPath => $composableBuilder(
    column: $table.directoryPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DownloadTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $DownloadTasksTable> {
  $$DownloadTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get workId =>
      $composableBuilder(column: $table.workId, builder: (column) => column);

  GeneratedColumn<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get workJson =>
      $composableBuilder(column: $table.workJson, builder: (column) => column);

  GeneratedColumn<String> get chapterJson => $composableBuilder(
    column: $table.chapterJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get completedItems => $composableBuilder(
    column: $table.completedItems,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalItems => $composableBuilder(
    column: $table.totalItems,
    builder: (column) => column,
  );

  GeneratedColumn<String> get directoryPath => $composableBuilder(
    column: $table.directoryPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DownloadTasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DownloadTasksTable,
          DownloadTask,
          $$DownloadTasksTableFilterComposer,
          $$DownloadTasksTableOrderingComposer,
          $$DownloadTasksTableAnnotationComposer,
          $$DownloadTasksTableCreateCompanionBuilder,
          $$DownloadTasksTableUpdateCompanionBuilder,
          (
            DownloadTask,
            BaseReferences<_$AppDatabase, $DownloadTasksTable, DownloadTask>,
          ),
          DownloadTask,
          PrefetchHooks Function()
        > {
  $$DownloadTasksTableTableManager(_$AppDatabase db, $DownloadTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DownloadTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DownloadTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DownloadTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> taskId = const Value.absent(),
                Value<String> workId = const Value.absent(),
                Value<String> libraryKind = const Value.absent(),
                Value<String> workJson = const Value.absent(),
                Value<String> chapterJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> completedItems = const Value.absent(),
                Value<int> totalItems = const Value.absent(),
                Value<String> directoryPath = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> errorMessage = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DownloadTasksCompanion(
                taskId: taskId,
                workId: workId,
                libraryKind: libraryKind,
                workJson: workJson,
                chapterJson: chapterJson,
                status: status,
                completedItems: completedItems,
                totalItems: totalItems,
                directoryPath: directoryPath,
                payloadJson: payloadJson,
                errorMessage: errorMessage,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String taskId,
                required String workId,
                required String libraryKind,
                required String workJson,
                required String chapterJson,
                required String status,
                required int completedItems,
                required int totalItems,
                required String directoryPath,
                required String payloadJson,
                required String errorMessage,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DownloadTasksCompanion.insert(
                taskId: taskId,
                workId: workId,
                libraryKind: libraryKind,
                workJson: workJson,
                chapterJson: chapterJson,
                status: status,
                completedItems: completedItems,
                totalItems: totalItems,
                directoryPath: directoryPath,
                payloadJson: payloadJson,
                errorMessage: errorMessage,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DownloadTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DownloadTasksTable,
      DownloadTask,
      $$DownloadTasksTableFilterComposer,
      $$DownloadTasksTableOrderingComposer,
      $$DownloadTasksTableAnnotationComposer,
      $$DownloadTasksTableCreateCompanionBuilder,
      $$DownloadTasksTableUpdateCompanionBuilder,
      (
        DownloadTask,
        BaseReferences<_$AppDatabase, $DownloadTasksTable, DownloadTask>,
      ),
      DownloadTask,
      PrefetchHooks Function()
    >;
typedef $$CoverCachesTableCreateCompanionBuilder =
    CoverCachesCompanion Function({
      required String workId,
      required String sourceMarker,
      required String imageUri,
      required String filePath,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CoverCachesTableUpdateCompanionBuilder =
    CoverCachesCompanion Function({
      Value<String> workId,
      Value<String> sourceMarker,
      Value<String> imageUri,
      Value<String> filePath,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CoverCachesTableFilterComposer
    extends Composer<_$AppDatabase, $CoverCachesTable> {
  $$CoverCachesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceMarker => $composableBuilder(
    column: $table.sourceMarker,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUri => $composableBuilder(
    column: $table.imageUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CoverCachesTableOrderingComposer
    extends Composer<_$AppDatabase, $CoverCachesTable> {
  $$CoverCachesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceMarker => $composableBuilder(
    column: $table.sourceMarker,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUri => $composableBuilder(
    column: $table.imageUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CoverCachesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CoverCachesTable> {
  $$CoverCachesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get workId =>
      $composableBuilder(column: $table.workId, builder: (column) => column);

  GeneratedColumn<String> get sourceMarker => $composableBuilder(
    column: $table.sourceMarker,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imageUri =>
      $composableBuilder(column: $table.imageUri, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CoverCachesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CoverCachesTable,
          CoverCache,
          $$CoverCachesTableFilterComposer,
          $$CoverCachesTableOrderingComposer,
          $$CoverCachesTableAnnotationComposer,
          $$CoverCachesTableCreateCompanionBuilder,
          $$CoverCachesTableUpdateCompanionBuilder,
          (
            CoverCache,
            BaseReferences<_$AppDatabase, $CoverCachesTable, CoverCache>,
          ),
          CoverCache,
          PrefetchHooks Function()
        > {
  $$CoverCachesTableTableManager(_$AppDatabase db, $CoverCachesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoverCachesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CoverCachesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CoverCachesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> workId = const Value.absent(),
                Value<String> sourceMarker = const Value.absent(),
                Value<String> imageUri = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CoverCachesCompanion(
                workId: workId,
                sourceMarker: sourceMarker,
                imageUri: imageUri,
                filePath: filePath,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String workId,
                required String sourceMarker,
                required String imageUri,
                required String filePath,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CoverCachesCompanion.insert(
                workId: workId,
                sourceMarker: sourceMarker,
                imageUri: imageUri,
                filePath: filePath,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CoverCachesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CoverCachesTable,
      CoverCache,
      $$CoverCachesTableFilterComposer,
      $$CoverCachesTableOrderingComposer,
      $$CoverCachesTableAnnotationComposer,
      $$CoverCachesTableCreateCompanionBuilder,
      $$CoverCachesTableUpdateCompanionBuilder,
      (
        CoverCache,
        BaseReferences<_$AppDatabase, $CoverCachesTable, CoverCache>,
      ),
      CoverCache,
      PrefetchHooks Function()
    >;
typedef $$CoverEntriesTableCreateCompanionBuilder =
    CoverEntriesCompanion Function({
      required String coverKey,
      required String libraryKind,
      required String status,
      required String imageUri,
      required String filePath,
      Value<int?> sourceTid,
      Value<int> retryCount,
      Value<DateTime?> nextRetryAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CoverEntriesTableUpdateCompanionBuilder =
    CoverEntriesCompanion Function({
      Value<String> coverKey,
      Value<String> libraryKind,
      Value<String> status,
      Value<String> imageUri,
      Value<String> filePath,
      Value<int?> sourceTid,
      Value<int> retryCount,
      Value<DateTime?> nextRetryAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$CoverEntriesTableReferences
    extends BaseReferences<_$AppDatabase, $CoverEntriesTable, CoverEntry> {
  $$CoverEntriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CoverAliasesTable, List<CoverAliase>>
  _coverAliasesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.coverAliases,
    aliasName: 'cover_entries__cover_key__cover_aliases__cover_key',
  );

  $$CoverAliasesTableProcessedTableManager get coverAliasesRefs {
    final manager = $$CoverAliasesTableTableManager($_db, $_db.coverAliases)
        .filter(
          (f) =>
              f.coverKey.coverKey.sqlEquals($_itemColumn<String>('cover_key')!),
        );

    final cache = $_typedResult.readTableOrNull(_coverAliasesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CoverEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $CoverEntriesTable> {
  $$CoverEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get coverKey => $composableBuilder(
    column: $table.coverKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUri => $composableBuilder(
    column: $table.imageUri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sourceTid => $composableBuilder(
    column: $table.sourceTid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> coverAliasesRefs(
    Expression<bool> Function($$CoverAliasesTableFilterComposer f) f,
  ) {
    final $$CoverAliasesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.coverKey,
      referencedTable: $db.coverAliases,
      getReferencedColumn: (t) => t.coverKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CoverAliasesTableFilterComposer(
            $db: $db,
            $table: $db.coverAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CoverEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CoverEntriesTable> {
  $$CoverEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get coverKey => $composableBuilder(
    column: $table.coverKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUri => $composableBuilder(
    column: $table.imageUri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sourceTid => $composableBuilder(
    column: $table.sourceTid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CoverEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CoverEntriesTable> {
  $$CoverEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get coverKey =>
      $composableBuilder(column: $table.coverKey, builder: (column) => column);

  GeneratedColumn<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get imageUri =>
      $composableBuilder(column: $table.imageUri, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<int> get sourceTid =>
      $composableBuilder(column: $table.sourceTid, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> coverAliasesRefs<T extends Object>(
    Expression<T> Function($$CoverAliasesTableAnnotationComposer a) f,
  ) {
    final $$CoverAliasesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.coverKey,
      referencedTable: $db.coverAliases,
      getReferencedColumn: (t) => t.coverKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CoverAliasesTableAnnotationComposer(
            $db: $db,
            $table: $db.coverAliases,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CoverEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CoverEntriesTable,
          CoverEntry,
          $$CoverEntriesTableFilterComposer,
          $$CoverEntriesTableOrderingComposer,
          $$CoverEntriesTableAnnotationComposer,
          $$CoverEntriesTableCreateCompanionBuilder,
          $$CoverEntriesTableUpdateCompanionBuilder,
          (CoverEntry, $$CoverEntriesTableReferences),
          CoverEntry,
          PrefetchHooks Function({bool coverAliasesRefs})
        > {
  $$CoverEntriesTableTableManager(_$AppDatabase db, $CoverEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoverEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CoverEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CoverEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> coverKey = const Value.absent(),
                Value<String> libraryKind = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> imageUri = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<int?> sourceTid = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<DateTime?> nextRetryAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CoverEntriesCompanion(
                coverKey: coverKey,
                libraryKind: libraryKind,
                status: status,
                imageUri: imageUri,
                filePath: filePath,
                sourceTid: sourceTid,
                retryCount: retryCount,
                nextRetryAt: nextRetryAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String coverKey,
                required String libraryKind,
                required String status,
                required String imageUri,
                required String filePath,
                Value<int?> sourceTid = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<DateTime?> nextRetryAt = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CoverEntriesCompanion.insert(
                coverKey: coverKey,
                libraryKind: libraryKind,
                status: status,
                imageUri: imageUri,
                filePath: filePath,
                sourceTid: sourceTid,
                retryCount: retryCount,
                nextRetryAt: nextRetryAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CoverEntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({coverAliasesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (coverAliasesRefs) db.coverAliases],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (coverAliasesRefs)
                    await $_getPrefetchedData<
                      CoverEntry,
                      $CoverEntriesTable,
                      CoverAliase
                    >(
                      currentTable: table,
                      referencedTable: $$CoverEntriesTableReferences
                          ._coverAliasesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CoverEntriesTableReferences(
                            db,
                            table,
                            p0,
                          ).coverAliasesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.coverKey == item.coverKey,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CoverEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CoverEntriesTable,
      CoverEntry,
      $$CoverEntriesTableFilterComposer,
      $$CoverEntriesTableOrderingComposer,
      $$CoverEntriesTableAnnotationComposer,
      $$CoverEntriesTableCreateCompanionBuilder,
      $$CoverEntriesTableUpdateCompanionBuilder,
      (CoverEntry, $$CoverEntriesTableReferences),
      CoverEntry,
      PrefetchHooks Function({bool coverAliasesRefs})
    >;
typedef $$CoverAliasesTableCreateCompanionBuilder =
    CoverAliasesCompanion Function({
      required String libraryKind,
      required int tid,
      required String coverKey,
      Value<int> rowid,
    });
typedef $$CoverAliasesTableUpdateCompanionBuilder =
    CoverAliasesCompanion Function({
      Value<String> libraryKind,
      Value<int> tid,
      Value<String> coverKey,
      Value<int> rowid,
    });

final class $$CoverAliasesTableReferences
    extends BaseReferences<_$AppDatabase, $CoverAliasesTable, CoverAliase> {
  $$CoverAliasesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CoverEntriesTable _coverKeyTable(_$AppDatabase db) => db.coverEntries
      .createAlias('cover_aliases__cover_key__cover_entries__cover_key');

  $$CoverEntriesTableProcessedTableManager get coverKey {
    final $_column = $_itemColumn<String>('cover_key')!;

    final manager = $$CoverEntriesTableTableManager(
      $_db,
      $_db.coverEntries,
    ).filter((f) => f.coverKey.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_coverKeyTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CoverAliasesTableFilterComposer
    extends Composer<_$AppDatabase, $CoverAliasesTable> {
  $$CoverAliasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tid => $composableBuilder(
    column: $table.tid,
    builder: (column) => ColumnFilters(column),
  );

  $$CoverEntriesTableFilterComposer get coverKey {
    final $$CoverEntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.coverKey,
      referencedTable: $db.coverEntries,
      getReferencedColumn: (t) => t.coverKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CoverEntriesTableFilterComposer(
            $db: $db,
            $table: $db.coverEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CoverAliasesTableOrderingComposer
    extends Composer<_$AppDatabase, $CoverAliasesTable> {
  $$CoverAliasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tid => $composableBuilder(
    column: $table.tid,
    builder: (column) => ColumnOrderings(column),
  );

  $$CoverEntriesTableOrderingComposer get coverKey {
    final $$CoverEntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.coverKey,
      referencedTable: $db.coverEntries,
      getReferencedColumn: (t) => t.coverKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CoverEntriesTableOrderingComposer(
            $db: $db,
            $table: $db.coverEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CoverAliasesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CoverAliasesTable> {
  $$CoverAliasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tid =>
      $composableBuilder(column: $table.tid, builder: (column) => column);

  $$CoverEntriesTableAnnotationComposer get coverKey {
    final $$CoverEntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.coverKey,
      referencedTable: $db.coverEntries,
      getReferencedColumn: (t) => t.coverKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CoverEntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.coverEntries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CoverAliasesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CoverAliasesTable,
          CoverAliase,
          $$CoverAliasesTableFilterComposer,
          $$CoverAliasesTableOrderingComposer,
          $$CoverAliasesTableAnnotationComposer,
          $$CoverAliasesTableCreateCompanionBuilder,
          $$CoverAliasesTableUpdateCompanionBuilder,
          (CoverAliase, $$CoverAliasesTableReferences),
          CoverAliase,
          PrefetchHooks Function({bool coverKey})
        > {
  $$CoverAliasesTableTableManager(_$AppDatabase db, $CoverAliasesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CoverAliasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CoverAliasesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CoverAliasesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> libraryKind = const Value.absent(),
                Value<int> tid = const Value.absent(),
                Value<String> coverKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CoverAliasesCompanion(
                libraryKind: libraryKind,
                tid: tid,
                coverKey: coverKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String libraryKind,
                required int tid,
                required String coverKey,
                Value<int> rowid = const Value.absent(),
              }) => CoverAliasesCompanion.insert(
                libraryKind: libraryKind,
                tid: tid,
                coverKey: coverKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CoverAliasesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({coverKey = false}) {
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
                    if (coverKey) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.coverKey,
                                referencedTable: $$CoverAliasesTableReferences
                                    ._coverKeyTable(db),
                                referencedColumn: $$CoverAliasesTableReferences
                                    ._coverKeyTable(db)
                                    .coverKey,
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

typedef $$CoverAliasesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CoverAliasesTable,
      CoverAliase,
      $$CoverAliasesTableFilterComposer,
      $$CoverAliasesTableOrderingComposer,
      $$CoverAliasesTableAnnotationComposer,
      $$CoverAliasesTableCreateCompanionBuilder,
      $$CoverAliasesTableUpdateCompanionBuilder,
      (CoverAliase, $$CoverAliasesTableReferences),
      CoverAliase,
      PrefetchHooks Function({bool coverKey})
    >;
typedef $$WorkIndexesTableCreateCompanionBuilder =
    WorkIndexesCompanion Function({
      required String canonicalKey,
      required String workId,
      required String libraryKind,
      required String workJson,
      Value<int> resolverVersion,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$WorkIndexesTableUpdateCompanionBuilder =
    WorkIndexesCompanion Function({
      Value<String> canonicalKey,
      Value<String> workId,
      Value<String> libraryKind,
      Value<String> workJson,
      Value<int> resolverVersion,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$WorkIndexesTableReferences
    extends BaseReferences<_$AppDatabase, $WorkIndexesTable, WorkIndex> {
  $$WorkIndexesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$WorkIndexSourcesTable, List<WorkIndexSource>>
  _workIndexSourcesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.workIndexSources,
    aliasName: 'work_indexes__canonical_key__work_index_sources__canonical_key',
  );

  $$WorkIndexSourcesTableProcessedTableManager get workIndexSourcesRefs {
    final manager =
        $$WorkIndexSourcesTableTableManager($_db, $_db.workIndexSources).filter(
          (f) => f.canonicalKey.canonicalKey.sqlEquals(
            $_itemColumn<String>('canonical_key')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _workIndexSourcesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$WorkIndexesTableFilterComposer
    extends Composer<_$AppDatabase, $WorkIndexesTable> {
  $$WorkIndexesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get canonicalKey => $composableBuilder(
    column: $table.canonicalKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workJson => $composableBuilder(
    column: $table.workJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get resolverVersion => $composableBuilder(
    column: $table.resolverVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> workIndexSourcesRefs(
    Expression<bool> Function($$WorkIndexSourcesTableFilterComposer f) f,
  ) {
    final $$WorkIndexSourcesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.canonicalKey,
      referencedTable: $db.workIndexSources,
      getReferencedColumn: (t) => t.canonicalKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkIndexSourcesTableFilterComposer(
            $db: $db,
            $table: $db.workIndexSources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WorkIndexesTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkIndexesTable> {
  $$WorkIndexesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get canonicalKey => $composableBuilder(
    column: $table.canonicalKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workId => $composableBuilder(
    column: $table.workId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workJson => $composableBuilder(
    column: $table.workJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get resolverVersion => $composableBuilder(
    column: $table.resolverVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkIndexesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkIndexesTable> {
  $$WorkIndexesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get canonicalKey => $composableBuilder(
    column: $table.canonicalKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get workId =>
      $composableBuilder(column: $table.workId, builder: (column) => column);

  GeneratedColumn<String> get libraryKind => $composableBuilder(
    column: $table.libraryKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get workJson =>
      $composableBuilder(column: $table.workJson, builder: (column) => column);

  GeneratedColumn<int> get resolverVersion => $composableBuilder(
    column: $table.resolverVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> workIndexSourcesRefs<T extends Object>(
    Expression<T> Function($$WorkIndexSourcesTableAnnotationComposer a) f,
  ) {
    final $$WorkIndexSourcesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.canonicalKey,
      referencedTable: $db.workIndexSources,
      getReferencedColumn: (t) => t.canonicalKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkIndexSourcesTableAnnotationComposer(
            $db: $db,
            $table: $db.workIndexSources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$WorkIndexesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorkIndexesTable,
          WorkIndex,
          $$WorkIndexesTableFilterComposer,
          $$WorkIndexesTableOrderingComposer,
          $$WorkIndexesTableAnnotationComposer,
          $$WorkIndexesTableCreateCompanionBuilder,
          $$WorkIndexesTableUpdateCompanionBuilder,
          (WorkIndex, $$WorkIndexesTableReferences),
          WorkIndex,
          PrefetchHooks Function({bool workIndexSourcesRefs})
        > {
  $$WorkIndexesTableTableManager(_$AppDatabase db, $WorkIndexesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkIndexesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkIndexesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkIndexesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> canonicalKey = const Value.absent(),
                Value<String> workId = const Value.absent(),
                Value<String> libraryKind = const Value.absent(),
                Value<String> workJson = const Value.absent(),
                Value<int> resolverVersion = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkIndexesCompanion(
                canonicalKey: canonicalKey,
                workId: workId,
                libraryKind: libraryKind,
                workJson: workJson,
                resolverVersion: resolverVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String canonicalKey,
                required String workId,
                required String libraryKind,
                required String workJson,
                Value<int> resolverVersion = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => WorkIndexesCompanion.insert(
                canonicalKey: canonicalKey,
                workId: workId,
                libraryKind: libraryKind,
                workJson: workJson,
                resolverVersion: resolverVersion,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$WorkIndexesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({workIndexSourcesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (workIndexSourcesRefs) db.workIndexSources,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (workIndexSourcesRefs)
                    await $_getPrefetchedData<
                      WorkIndex,
                      $WorkIndexesTable,
                      WorkIndexSource
                    >(
                      currentTable: table,
                      referencedTable: $$WorkIndexesTableReferences
                          ._workIndexSourcesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$WorkIndexesTableReferences(
                            db,
                            table,
                            p0,
                          ).workIndexSourcesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.canonicalKey == item.canonicalKey,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$WorkIndexesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorkIndexesTable,
      WorkIndex,
      $$WorkIndexesTableFilterComposer,
      $$WorkIndexesTableOrderingComposer,
      $$WorkIndexesTableAnnotationComposer,
      $$WorkIndexesTableCreateCompanionBuilder,
      $$WorkIndexesTableUpdateCompanionBuilder,
      (WorkIndex, $$WorkIndexesTableReferences),
      WorkIndex,
      PrefetchHooks Function({bool workIndexSourcesRefs})
    >;
typedef $$WorkIndexSourcesTableCreateCompanionBuilder =
    WorkIndexSourcesCompanion Function({
      Value<int> tid,
      required String canonicalKey,
    });
typedef $$WorkIndexSourcesTableUpdateCompanionBuilder =
    WorkIndexSourcesCompanion Function({
      Value<int> tid,
      Value<String> canonicalKey,
    });

final class $$WorkIndexSourcesTableReferences
    extends
        BaseReferences<_$AppDatabase, $WorkIndexSourcesTable, WorkIndexSource> {
  $$WorkIndexSourcesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $WorkIndexesTable _canonicalKeyTable(_$AppDatabase db) =>
      db.workIndexes.createAlias(
        'work_index_sources__canonical_key__work_indexes__canonical_key',
      );

  $$WorkIndexesTableProcessedTableManager get canonicalKey {
    final $_column = $_itemColumn<String>('canonical_key')!;

    final manager = $$WorkIndexesTableTableManager(
      $_db,
      $_db.workIndexes,
    ).filter((f) => f.canonicalKey.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_canonicalKeyTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$WorkIndexSourcesTableFilterComposer
    extends Composer<_$AppDatabase, $WorkIndexSourcesTable> {
  $$WorkIndexSourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get tid => $composableBuilder(
    column: $table.tid,
    builder: (column) => ColumnFilters(column),
  );

  $$WorkIndexesTableFilterComposer get canonicalKey {
    final $$WorkIndexesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.canonicalKey,
      referencedTable: $db.workIndexes,
      getReferencedColumn: (t) => t.canonicalKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkIndexesTableFilterComposer(
            $db: $db,
            $table: $db.workIndexes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WorkIndexSourcesTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkIndexSourcesTable> {
  $$WorkIndexSourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get tid => $composableBuilder(
    column: $table.tid,
    builder: (column) => ColumnOrderings(column),
  );

  $$WorkIndexesTableOrderingComposer get canonicalKey {
    final $$WorkIndexesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.canonicalKey,
      referencedTable: $db.workIndexes,
      getReferencedColumn: (t) => t.canonicalKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkIndexesTableOrderingComposer(
            $db: $db,
            $table: $db.workIndexes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WorkIndexSourcesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkIndexSourcesTable> {
  $$WorkIndexSourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get tid =>
      $composableBuilder(column: $table.tid, builder: (column) => column);

  $$WorkIndexesTableAnnotationComposer get canonicalKey {
    final $$WorkIndexesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.canonicalKey,
      referencedTable: $db.workIndexes,
      getReferencedColumn: (t) => t.canonicalKey,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkIndexesTableAnnotationComposer(
            $db: $db,
            $table: $db.workIndexes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WorkIndexSourcesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorkIndexSourcesTable,
          WorkIndexSource,
          $$WorkIndexSourcesTableFilterComposer,
          $$WorkIndexSourcesTableOrderingComposer,
          $$WorkIndexSourcesTableAnnotationComposer,
          $$WorkIndexSourcesTableCreateCompanionBuilder,
          $$WorkIndexSourcesTableUpdateCompanionBuilder,
          (WorkIndexSource, $$WorkIndexSourcesTableReferences),
          WorkIndexSource,
          PrefetchHooks Function({bool canonicalKey})
        > {
  $$WorkIndexSourcesTableTableManager(
    _$AppDatabase db,
    $WorkIndexSourcesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkIndexSourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkIndexSourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkIndexSourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> tid = const Value.absent(),
                Value<String> canonicalKey = const Value.absent(),
              }) => WorkIndexSourcesCompanion(
                tid: tid,
                canonicalKey: canonicalKey,
              ),
          createCompanionCallback:
              ({
                Value<int> tid = const Value.absent(),
                required String canonicalKey,
              }) => WorkIndexSourcesCompanion.insert(
                tid: tid,
                canonicalKey: canonicalKey,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$WorkIndexSourcesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({canonicalKey = false}) {
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
                    if (canonicalKey) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.canonicalKey,
                                referencedTable:
                                    $$WorkIndexSourcesTableReferences
                                        ._canonicalKeyTable(db),
                                referencedColumn:
                                    $$WorkIndexSourcesTableReferences
                                        ._canonicalKeyTable(db)
                                        .canonicalKey,
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

typedef $$WorkIndexSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorkIndexSourcesTable,
      WorkIndexSource,
      $$WorkIndexSourcesTableFilterComposer,
      $$WorkIndexSourcesTableOrderingComposer,
      $$WorkIndexSourcesTableAnnotationComposer,
      $$WorkIndexSourcesTableCreateCompanionBuilder,
      $$WorkIndexSourcesTableUpdateCompanionBuilder,
      (WorkIndexSource, $$WorkIndexSourcesTableReferences),
      WorkIndexSource,
      PrefetchHooks Function({bool canonicalKey})
    >;
typedef $$ForumCachesTableCreateCompanionBuilder =
    ForumCachesCompanion Function({
      required String accountKey,
      required String cacheKey,
      required String payloadJson,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ForumCachesTableUpdateCompanionBuilder =
    ForumCachesCompanion Function({
      Value<String> accountKey,
      Value<String> cacheKey,
      Value<String> payloadJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ForumCachesTableFilterComposer
    extends Composer<_$AppDatabase, $ForumCachesTable> {
  $$ForumCachesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ForumCachesTableOrderingComposer
    extends Composer<_$AppDatabase, $ForumCachesTable> {
  $$ForumCachesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ForumCachesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ForumCachesTable> {
  $$ForumCachesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ForumCachesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ForumCachesTable,
          ForumCache,
          $$ForumCachesTableFilterComposer,
          $$ForumCachesTableOrderingComposer,
          $$ForumCachesTableAnnotationComposer,
          $$ForumCachesTableCreateCompanionBuilder,
          $$ForumCachesTableUpdateCompanionBuilder,
          (
            ForumCache,
            BaseReferences<_$AppDatabase, $ForumCachesTable, ForumCache>,
          ),
          ForumCache,
          PrefetchHooks Function()
        > {
  $$ForumCachesTableTableManager(_$AppDatabase db, $ForumCachesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ForumCachesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ForumCachesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ForumCachesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountKey = const Value.absent(),
                Value<String> cacheKey = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ForumCachesCompanion(
                accountKey: accountKey,
                cacheKey: cacheKey,
                payloadJson: payloadJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountKey,
                required String cacheKey,
                required String payloadJson,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ForumCachesCompanion.insert(
                accountKey: accountKey,
                cacheKey: cacheKey,
                payloadJson: payloadJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ForumCachesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ForumCachesTable,
      ForumCache,
      $$ForumCachesTableFilterComposer,
      $$ForumCachesTableOrderingComposer,
      $$ForumCachesTableAnnotationComposer,
      $$ForumCachesTableCreateCompanionBuilder,
      $$ForumCachesTableUpdateCompanionBuilder,
      (
        ForumCache,
        BaseReferences<_$AppDatabase, $ForumCachesTable, ForumCache>,
      ),
      ForumCache,
      PrefetchHooks Function()
    >;
typedef $$ForumDraftsTableCreateCompanionBuilder =
    ForumDraftsCompanion Function({
      required String draftId,
      required String accountKey,
      required String action,
      Value<int?> fid,
      Value<int?> tid,
      Value<int?> pid,
      required String subject,
      required String message,
      required String attachmentsJson,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ForumDraftsTableUpdateCompanionBuilder =
    ForumDraftsCompanion Function({
      Value<String> draftId,
      Value<String> accountKey,
      Value<String> action,
      Value<int?> fid,
      Value<int?> tid,
      Value<int?> pid,
      Value<String> subject,
      Value<String> message,
      Value<String> attachmentsJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ForumDraftsTableFilterComposer
    extends Composer<_$AppDatabase, $ForumDraftsTable> {
  $$ForumDraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get draftId => $composableBuilder(
    column: $table.draftId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fid => $composableBuilder(
    column: $table.fid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tid => $composableBuilder(
    column: $table.tid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ForumDraftsTableOrderingComposer
    extends Composer<_$AppDatabase, $ForumDraftsTable> {
  $$ForumDraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get draftId => $composableBuilder(
    column: $table.draftId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fid => $composableBuilder(
    column: $table.fid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tid => $composableBuilder(
    column: $table.tid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ForumDraftsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ForumDraftsTable> {
  $$ForumDraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get draftId =>
      $composableBuilder(column: $table.draftId, builder: (column) => column);

  GeneratedColumn<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<int> get fid =>
      $composableBuilder(column: $table.fid, builder: (column) => column);

  GeneratedColumn<int> get tid =>
      $composableBuilder(column: $table.tid, builder: (column) => column);

  GeneratedColumn<int> get pid =>
      $composableBuilder(column: $table.pid, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ForumDraftsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ForumDraftsTable,
          ForumDraft,
          $$ForumDraftsTableFilterComposer,
          $$ForumDraftsTableOrderingComposer,
          $$ForumDraftsTableAnnotationComposer,
          $$ForumDraftsTableCreateCompanionBuilder,
          $$ForumDraftsTableUpdateCompanionBuilder,
          (
            ForumDraft,
            BaseReferences<_$AppDatabase, $ForumDraftsTable, ForumDraft>,
          ),
          ForumDraft,
          PrefetchHooks Function()
        > {
  $$ForumDraftsTableTableManager(_$AppDatabase db, $ForumDraftsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ForumDraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ForumDraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ForumDraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> draftId = const Value.absent(),
                Value<String> accountKey = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<int?> fid = const Value.absent(),
                Value<int?> tid = const Value.absent(),
                Value<int?> pid = const Value.absent(),
                Value<String> subject = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<String> attachmentsJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ForumDraftsCompanion(
                draftId: draftId,
                accountKey: accountKey,
                action: action,
                fid: fid,
                tid: tid,
                pid: pid,
                subject: subject,
                message: message,
                attachmentsJson: attachmentsJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String draftId,
                required String accountKey,
                required String action,
                Value<int?> fid = const Value.absent(),
                Value<int?> tid = const Value.absent(),
                Value<int?> pid = const Value.absent(),
                required String subject,
                required String message,
                required String attachmentsJson,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ForumDraftsCompanion.insert(
                draftId: draftId,
                accountKey: accountKey,
                action: action,
                fid: fid,
                tid: tid,
                pid: pid,
                subject: subject,
                message: message,
                attachmentsJson: attachmentsJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ForumDraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ForumDraftsTable,
      ForumDraft,
      $$ForumDraftsTableFilterComposer,
      $$ForumDraftsTableOrderingComposer,
      $$ForumDraftsTableAnnotationComposer,
      $$ForumDraftsTableCreateCompanionBuilder,
      $$ForumDraftsTableUpdateCompanionBuilder,
      (
        ForumDraft,
        BaseReferences<_$AppDatabase, $ForumDraftsTable, ForumDraft>,
      ),
      ForumDraft,
      PrefetchHooks Function()
    >;
typedef $$ForumReadAnchorsTableCreateCompanionBuilder =
    ForumReadAnchorsCompanion Function({
      required String accountKey,
      required int tid,
      Value<int?> pid,
      required int page,
      required int floor,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ForumReadAnchorsTableUpdateCompanionBuilder =
    ForumReadAnchorsCompanion Function({
      Value<String> accountKey,
      Value<int> tid,
      Value<int?> pid,
      Value<int> page,
      Value<int> floor,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ForumReadAnchorsTableFilterComposer
    extends Composer<_$AppDatabase, $ForumReadAnchorsTable> {
  $$ForumReadAnchorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tid => $composableBuilder(
    column: $table.tid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get floor => $composableBuilder(
    column: $table.floor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ForumReadAnchorsTableOrderingComposer
    extends Composer<_$AppDatabase, $ForumReadAnchorsTable> {
  $$ForumReadAnchorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tid => $composableBuilder(
    column: $table.tid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get floor => $composableBuilder(
    column: $table.floor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ForumReadAnchorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ForumReadAnchorsTable> {
  $$ForumReadAnchorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get tid =>
      $composableBuilder(column: $table.tid, builder: (column) => column);

  GeneratedColumn<int> get pid =>
      $composableBuilder(column: $table.pid, builder: (column) => column);

  GeneratedColumn<int> get page =>
      $composableBuilder(column: $table.page, builder: (column) => column);

  GeneratedColumn<int> get floor =>
      $composableBuilder(column: $table.floor, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ForumReadAnchorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ForumReadAnchorsTable,
          ForumReadAnchor,
          $$ForumReadAnchorsTableFilterComposer,
          $$ForumReadAnchorsTableOrderingComposer,
          $$ForumReadAnchorsTableAnnotationComposer,
          $$ForumReadAnchorsTableCreateCompanionBuilder,
          $$ForumReadAnchorsTableUpdateCompanionBuilder,
          (
            ForumReadAnchor,
            BaseReferences<
              _$AppDatabase,
              $ForumReadAnchorsTable,
              ForumReadAnchor
            >,
          ),
          ForumReadAnchor,
          PrefetchHooks Function()
        > {
  $$ForumReadAnchorsTableTableManager(
    _$AppDatabase db,
    $ForumReadAnchorsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ForumReadAnchorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ForumReadAnchorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ForumReadAnchorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> accountKey = const Value.absent(),
                Value<int> tid = const Value.absent(),
                Value<int?> pid = const Value.absent(),
                Value<int> page = const Value.absent(),
                Value<int> floor = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ForumReadAnchorsCompanion(
                accountKey: accountKey,
                tid: tid,
                pid: pid,
                page: page,
                floor: floor,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountKey,
                required int tid,
                Value<int?> pid = const Value.absent(),
                required int page,
                required int floor,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ForumReadAnchorsCompanion.insert(
                accountKey: accountKey,
                tid: tid,
                pid: pid,
                page: page,
                floor: floor,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ForumReadAnchorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ForumReadAnchorsTable,
      ForumReadAnchor,
      $$ForumReadAnchorsTableFilterComposer,
      $$ForumReadAnchorsTableOrderingComposer,
      $$ForumReadAnchorsTableAnnotationComposer,
      $$ForumReadAnchorsTableCreateCompanionBuilder,
      $$ForumReadAnchorsTableUpdateCompanionBuilder,
      (
        ForumReadAnchor,
        BaseReferences<_$AppDatabase, $ForumReadAnchorsTable, ForumReadAnchor>,
      ),
      ForumReadAnchor,
      PrefetchHooks Function()
    >;
typedef $$ForumActionTombstonesTableCreateCompanionBuilder =
    ForumActionTombstonesCompanion Function({
      required String accountKey,
      required String contextKey,
      required String attemptId,
      required String action,
      Value<int?> fid,
      Value<int?> tid,
      Value<int?> pid,
      Value<int?> favoriteId,
      required String draftContext,
      required String status,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ForumActionTombstonesTableUpdateCompanionBuilder =
    ForumActionTombstonesCompanion Function({
      Value<String> accountKey,
      Value<String> contextKey,
      Value<String> attemptId,
      Value<String> action,
      Value<int?> fid,
      Value<int?> tid,
      Value<int?> pid,
      Value<int?> favoriteId,
      Value<String> draftContext,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ForumActionTombstonesTableFilterComposer
    extends Composer<_$AppDatabase, $ForumActionTombstonesTable> {
  $$ForumActionTombstonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contextKey => $composableBuilder(
    column: $table.contextKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fid => $composableBuilder(
    column: $table.fid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tid => $composableBuilder(
    column: $table.tid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get favoriteId => $composableBuilder(
    column: $table.favoriteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get draftContext => $composableBuilder(
    column: $table.draftContext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
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

class $$ForumActionTombstonesTableOrderingComposer
    extends Composer<_$AppDatabase, $ForumActionTombstonesTable> {
  $$ForumActionTombstonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contextKey => $composableBuilder(
    column: $table.contextKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fid => $composableBuilder(
    column: $table.fid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tid => $composableBuilder(
    column: $table.tid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pid => $composableBuilder(
    column: $table.pid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get favoriteId => $composableBuilder(
    column: $table.favoriteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get draftContext => $composableBuilder(
    column: $table.draftContext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
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

class $$ForumActionTombstonesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ForumActionTombstonesTable> {
  $$ForumActionTombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get accountKey => $composableBuilder(
    column: $table.accountKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contextKey => $composableBuilder(
    column: $table.contextKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attemptId =>
      $composableBuilder(column: $table.attemptId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<int> get fid =>
      $composableBuilder(column: $table.fid, builder: (column) => column);

  GeneratedColumn<int> get tid =>
      $composableBuilder(column: $table.tid, builder: (column) => column);

  GeneratedColumn<int> get pid =>
      $composableBuilder(column: $table.pid, builder: (column) => column);

  GeneratedColumn<int> get favoriteId => $composableBuilder(
    column: $table.favoriteId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get draftContext => $composableBuilder(
    column: $table.draftContext,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ForumActionTombstonesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ForumActionTombstonesTable,
          ForumActionTombstone,
          $$ForumActionTombstonesTableFilterComposer,
          $$ForumActionTombstonesTableOrderingComposer,
          $$ForumActionTombstonesTableAnnotationComposer,
          $$ForumActionTombstonesTableCreateCompanionBuilder,
          $$ForumActionTombstonesTableUpdateCompanionBuilder,
          (
            ForumActionTombstone,
            BaseReferences<
              _$AppDatabase,
              $ForumActionTombstonesTable,
              ForumActionTombstone
            >,
          ),
          ForumActionTombstone,
          PrefetchHooks Function()
        > {
  $$ForumActionTombstonesTableTableManager(
    _$AppDatabase db,
    $ForumActionTombstonesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ForumActionTombstonesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ForumActionTombstonesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ForumActionTombstonesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> accountKey = const Value.absent(),
                Value<String> contextKey = const Value.absent(),
                Value<String> attemptId = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<int?> fid = const Value.absent(),
                Value<int?> tid = const Value.absent(),
                Value<int?> pid = const Value.absent(),
                Value<int?> favoriteId = const Value.absent(),
                Value<String> draftContext = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ForumActionTombstonesCompanion(
                accountKey: accountKey,
                contextKey: contextKey,
                attemptId: attemptId,
                action: action,
                fid: fid,
                tid: tid,
                pid: pid,
                favoriteId: favoriteId,
                draftContext: draftContext,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String accountKey,
                required String contextKey,
                required String attemptId,
                required String action,
                Value<int?> fid = const Value.absent(),
                Value<int?> tid = const Value.absent(),
                Value<int?> pid = const Value.absent(),
                Value<int?> favoriteId = const Value.absent(),
                required String draftContext,
                required String status,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ForumActionTombstonesCompanion.insert(
                accountKey: accountKey,
                contextKey: contextKey,
                attemptId: attemptId,
                action: action,
                fid: fid,
                tid: tid,
                pid: pid,
                favoriteId: favoriteId,
                draftContext: draftContext,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ForumActionTombstonesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ForumActionTombstonesTable,
      ForumActionTombstone,
      $$ForumActionTombstonesTableFilterComposer,
      $$ForumActionTombstonesTableOrderingComposer,
      $$ForumActionTombstonesTableAnnotationComposer,
      $$ForumActionTombstonesTableCreateCompanionBuilder,
      $$ForumActionTombstonesTableUpdateCompanionBuilder,
      (
        ForumActionTombstone,
        BaseReferences<
          _$AppDatabase,
          $ForumActionTombstonesTable,
          ForumActionTombstone
        >,
      ),
      ForumActionTombstone,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ReadingStatesTableTableManager get readingStates =>
      $$ReadingStatesTableTableManager(_db, _db.readingStates);
  $$SearchCachesTableTableManager get searchCaches =>
      $$SearchCachesTableTableManager(_db, _db.searchCaches);
  $$FavoriteCachesTableTableManager get favoriteCaches =>
      $$FavoriteCachesTableTableManager(_db, _db.favoriteCaches);
  $$DownloadTasksTableTableManager get downloadTasks =>
      $$DownloadTasksTableTableManager(_db, _db.downloadTasks);
  $$CoverCachesTableTableManager get coverCaches =>
      $$CoverCachesTableTableManager(_db, _db.coverCaches);
  $$CoverEntriesTableTableManager get coverEntries =>
      $$CoverEntriesTableTableManager(_db, _db.coverEntries);
  $$CoverAliasesTableTableManager get coverAliases =>
      $$CoverAliasesTableTableManager(_db, _db.coverAliases);
  $$WorkIndexesTableTableManager get workIndexes =>
      $$WorkIndexesTableTableManager(_db, _db.workIndexes);
  $$WorkIndexSourcesTableTableManager get workIndexSources =>
      $$WorkIndexSourcesTableTableManager(_db, _db.workIndexSources);
  $$ForumCachesTableTableManager get forumCaches =>
      $$ForumCachesTableTableManager(_db, _db.forumCaches);
  $$ForumDraftsTableTableManager get forumDrafts =>
      $$ForumDraftsTableTableManager(_db, _db.forumDrafts);
  $$ForumReadAnchorsTableTableManager get forumReadAnchors =>
      $$ForumReadAnchorsTableTableManager(_db, _db.forumReadAnchors);
  $$ForumActionTombstonesTableTableManager get forumActionTombstones =>
      $$ForumActionTombstonesTableTableManager(_db, _db.forumActionTombstones);
}
