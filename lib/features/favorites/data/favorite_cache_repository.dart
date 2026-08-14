import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/core/storage/work_codec.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';

final Provider<FavoriteCacheRepository> favoriteCacheRepositoryProvider =
    Provider<FavoriteCacheRepository>(
      (Ref ref) => FavoriteCacheRepository(
        ref.watch(appDatabaseProvider),
        ref.watch(authControllerProvider).value?.userId ?? 0,
        client: ref.watch(forumClientProvider),
      ),
    );

class FavoriteCacheSnapshot {
  const FavoriteCacheSnapshot({required this.works, required this.updatedAt});

  final List<FavoriteWork> works;
  final DateTime updatedAt;
}

class FavoriteCacheRepository {
  FavoriteCacheRepository(
    this._database,
    this._userId, {
    this._workCodec = const WorkCodec(),
    this._client,
  });

  final AppDatabase _database;
  final int _userId;
  final WorkCodec _workCodec;
  final ForumClient? _client;

  Future<void> save(List<FavoriteWork> works, {DateTime? updatedAt}) {
    _checkUserId();
    final DateTime timestamp = updatedAt ?? DateTime.now();
    return _withActiveAccount(
      () => _database.transaction(() async {
        await (_database.delete(
          _database.favoriteCaches,
        )..where((FavoriteCaches table) => table.userId.equals(_userId))).go();
        for (int index = 0; index < works.length; index++) {
          final FavoriteWork value = works[index];
          await _database
              .into(_database.favoriteCaches)
              .insert(
                FavoriteCachesCompanion.insert(
                  userId: _userId,
                  workId: value.work.id,
                  workJson: _workCodec.encode(value.work),
                  recordsJson: jsonEncode(
                    value.records.map(_encodeRecord).toList(growable: false),
                  ),
                  updatedAt: timestamp.subtract(Duration(microseconds: index)),
                ),
              );
        }
      }),
    );
  }

  Future<FavoriteCacheSnapshot?> load() async {
    _checkUserId();
    final List<FavoriteCache> rows = await _withActiveAccount(
      () =>
          (_database.select(_database.favoriteCaches)
                ..where((FavoriteCaches table) => table.userId.equals(_userId))
                ..orderBy(<OrderClauseGenerator<FavoriteCaches>>[
                  (FavoriteCaches table) => OrderingTerm.desc(table.updatedAt),
                ]))
              .get(),
    );
    if (rows.isEmpty) {
      return null;
    }
    final List<FavoriteWork> works = <FavoriteWork>[];
    for (final FavoriteCache row in rows) {
      try {
        final Object? value = jsonDecode(row.recordsJson);
        if (value is! List<dynamic>) {
          continue;
        }
        works.add(
          FavoriteWork(
            work: _workCodec.decode(row.workJson),
            records: value
                .whereType<Map<String, dynamic>>()
                .map(_decodeRecord)
                .toList(growable: false),
          ),
        );
      } on Object {
        continue;
      }
    }
    if (works.isEmpty) {
      return null;
    }
    return FavoriteCacheSnapshot(works: works, updatedAt: rows.first.updatedAt);
  }

  Future<void> clear() {
    _checkUserId();
    return _withActiveAccount(
      () => (_database.delete(
        _database.favoriteCaches,
      )..where((FavoriteCaches table) => table.userId.equals(_userId))).go(),
    );
  }

  Map<String, Object?> _encodeRecord(CloudFavoriteRecord record) {
    return <String, Object?>{
      'favoriteId': record.favoriteId,
      'threadId': record.threadId,
      'title': record.title,
      'threadUri': record.threadUri.toString(),
      'deleteDialogUri': _withoutFormHash(record.deleteDialogUri).toString(),
    };
  }

  Uri _withoutFormHash(Uri uri) {
    if (!uri.queryParameters.containsKey('formhash')) {
      return uri;
    }
    return uri.replace(
      queryParameters: <String, String>{
        for (final MapEntry<String, String> entry
            in uri.queryParameters.entries)
          if (entry.key != 'formhash') entry.key: entry.value,
      },
    );
  }

  CloudFavoriteRecord _decodeRecord(Map<String, dynamic> value) {
    return CloudFavoriteRecord(
      favoriteId: _integer(value['favoriteId']),
      threadId: _integer(value['threadId']),
      title: value['title']?.toString() ?? '',
      threadUri: Uri.parse(value['threadUri']?.toString() ?? ''),
      deleteDialogUri: Uri.parse(value['deleteDialogUri']?.toString() ?? ''),
    );
  }

  int _integer(Object? value) {
    return value is int ? value : int.parse(value.toString());
  }

  void _checkUserId() {
    if (_userId <= 0) {
      throw StateError('收藏缓存缺少有效账号');
    }
  }

  Future<T> _withActiveAccount<T>(Future<T> Function() operation) {
    final ForumClient? client = _client;
    return client == null
        ? operation()
        : client.withActiveAccount(_userId, operation);
  }
}
