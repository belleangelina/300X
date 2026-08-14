import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/storage/app_database.dart';

final Provider<ForumLocalRepository> forumLocalRepositoryProvider =
    Provider<ForumLocalRepository>(
      (Ref ref) => ForumLocalRepository(ref.watch(appDatabaseProvider)),
    );

class ForumCacheSnapshot {
  const ForumCacheSnapshot({required this.payload, required this.updatedAt});

  final Map<String, dynamic> payload;
  final DateTime updatedAt;
}

class ForumReadPosition {
  const ForumReadPosition({
    required this.userId,
    required this.threadId,
    required this.page,
    required this.floor,
    required this.updatedAt,
    this.postId,
  });

  final int userId;
  final int threadId;
  final int? postId;
  final int page;
  final int floor;
  final DateTime updatedAt;
}

class ForumLocalRepository {
  ForumLocalRepository(this._database);

  static const int maximumCacheEntriesPerAccount = 80;

  final AppDatabase _database;

  Future<void> saveCache({
    required int userId,
    required String key,
    required Map<String, dynamic> payload,
    DateTime? updatedAt,
  }) async {
    _checkUserId(userId);
    final String normalizedKey = _checkKey(key);
    await _database
        .into(_database.forumCaches)
        .insertOnConflictUpdate(
          ForumCachesCompanion.insert(
            accountKey: _accountKey(userId),
            cacheKey: normalizedKey,
            payloadJson: jsonEncode(payload),
            updatedAt: updatedAt ?? DateTime.now(),
          ),
        );
    await _prune(userId);
  }

  Future<bool> saveCacheIfCurrent({
    required int userId,
    required String key,
    required Map<String, dynamic> payload,
    required bool Function() isCurrent,
    DateTime? updatedAt,
  }) async {
    try {
      await _database.transaction(() async {
        if (!isCurrent()) {
          throw const _ForumCacheWriteSuperseded();
        }
        await saveCache(
          userId: userId,
          key: key,
          payload: payload,
          updatedAt: updatedAt,
        );
        if (!isCurrent()) {
          throw const _ForumCacheWriteSuperseded();
        }
      });
      return true;
    } on _ForumCacheWriteSuperseded {
      return false;
    }
  }

  Future<ForumCacheSnapshot?> loadCache({
    required int userId,
    required String key,
  }) async {
    _checkUserId(userId);
    final ForumCache? row =
        await (_database.select(_database.forumCaches)..where(
              (ForumCaches table) =>
                  table.accountKey.equals(_accountKey(userId)) &
                  table.cacheKey.equals(_checkKey(key)),
            ))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(row.payloadJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return ForumCacheSnapshot(payload: decoded, updatedAt: row.updatedAt);
    } on FormatException {
      return null;
    }
  }

  Future<void> deleteCache({required int userId, required String key}) {
    _checkUserId(userId);
    return (_database.delete(_database.forumCaches)..where(
          (ForumCaches table) =>
              table.accountKey.equals(_accountKey(userId)) &
              table.cacheKey.equals(_checkKey(key)),
        ))
        .go();
  }

  Future<void> deleteCachesByPrefix({
    required int userId,
    required String prefix,
  }) {
    _checkUserId(userId);
    final String normalizedPrefix = _checkKey(prefix);
    return (_database.delete(_database.forumCaches)..where(
          (ForumCaches table) =>
              table.accountKey.equals(_accountKey(userId)) &
              table.cacheKey.like('$normalizedPrefix%'),
        ))
        .go();
  }

  Future<void> saveReadPosition(ForumReadPosition position) {
    _checkUserId(position.userId);
    if (position.threadId <= 0 || position.page <= 0 || position.floor < 0) {
      throw ArgumentError('主题、页码和楼层位置无效');
    }
    return _database
        .into(_database.forumReadAnchors)
        .insertOnConflictUpdate(
          ForumReadAnchorsCompanion.insert(
            accountKey: _accountKey(position.userId),
            tid: position.threadId,
            pid: Value<int?>(position.postId),
            page: position.page,
            floor: position.floor,
            updatedAt: position.updatedAt,
          ),
        );
  }

  Future<ForumReadPosition?> loadReadPosition({
    required int userId,
    required int threadId,
  }) async {
    _checkUserId(userId);
    if (threadId <= 0) {
      throw ArgumentError.value(threadId, 'threadId');
    }
    final ForumReadAnchor? row =
        await (_database.select(_database.forumReadAnchors)..where(
              (ForumReadAnchors table) =>
                  table.accountKey.equals(_accountKey(userId)) &
                  table.tid.equals(threadId),
            ))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return ForumReadPosition(
      userId: userId,
      threadId: row.tid,
      postId: row.pid,
      page: row.page,
      floor: row.floor,
      updatedAt: row.updatedAt,
    );
  }

  Future<void> clearAccount(int userId) {
    _checkUserId(userId);
    final String accountKey = _accountKey(userId);
    return _database.transaction(() async {
      await (_database.delete(_database.forumCaches)
            ..where((ForumCaches table) => table.accountKey.equals(accountKey)))
          .go();
      await (_database.delete(_database.forumDrafts)
            ..where((ForumDrafts table) => table.accountKey.equals(accountKey)))
          .go();
      await (_database.delete(_database.forumReadAnchors)..where(
            (ForumReadAnchors table) => table.accountKey.equals(accountKey),
          ))
          .go();
    });
  }

  Future<void> _prune(int userId) async {
    final List<ForumCache> rows =
        await (_database.select(_database.forumCaches)
              ..where(
                (ForumCaches table) =>
                    table.accountKey.equals(_accountKey(userId)),
              )
              ..orderBy(<OrderClauseGenerator<ForumCaches>>[
                (ForumCaches table) => OrderingTerm.desc(table.updatedAt),
              ]))
            .get();
    if (rows.length <= maximumCacheEntriesPerAccount) {
      return;
    }
    final List<String> staleKeys = rows
        .skip(maximumCacheEntriesPerAccount)
        .map((ForumCache row) => row.cacheKey)
        .toList(growable: false);
    await (_database.delete(_database.forumCaches)..where(
          (ForumCaches table) =>
              table.accountKey.equals(_accountKey(userId)) &
              table.cacheKey.isIn(staleKeys),
        ))
        .go();
  }

  String _accountKey(int userId) => 'uid:$userId';

  String _checkKey(String key) {
    final String value = key.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(key, 'key', '缓存键不能为空');
    }
    return value;
  }

  void _checkUserId(int userId) {
    if (userId <= 0) {
      throw ArgumentError.value(userId, 'userId');
    }
  }
}

class _ForumCacheWriteSuperseded implements Exception {
  const _ForumCacheWriteSuperseded();
}
