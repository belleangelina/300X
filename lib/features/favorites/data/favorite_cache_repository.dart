import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/core/storage/work_codec.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';

final Provider<FavoriteCacheRepository> favoriteCacheRepositoryProvider =
    Provider<FavoriteCacheRepository>(
        (Ref ref) => FavoriteCacheRepository(
            ref.watch(appDatabaseProvider),
        ),
    );

class FavoriteCacheSnapshot
{
    const FavoriteCacheSnapshot({
        required this.works,
        required this.updatedAt,
    });

    final List<FavoriteWork> works;
    final DateTime updatedAt;
}

class FavoriteCacheRepository
{
    FavoriteCacheRepository(
        this._database, [
        this._workCodec = const WorkCodec(),
    ]);

    final AppDatabase _database;
    final WorkCodec _workCodec;

    Future<void> save(
        List<FavoriteWork> works, {
        DateTime? updatedAt,
    })
    {
        final DateTime timestamp = updatedAt ?? DateTime.now();
        return _database.transaction(() async
        {
            await _database.delete(_database.favoriteCaches).go();
            for (int index = 0; index < works.length; index++)
            {
                final FavoriteWork value = works[index];
                await _database.into(_database.favoriteCaches).insert(
                    FavoriteCachesCompanion.insert(
                        workId: value.work.id,
                        workJson: _workCodec.encode(value.work),
                        recordsJson: jsonEncode(
                            value.records
                                .map(_encodeRecord)
                                .toList(growable: false),
                        ),
                        updatedAt: timestamp.subtract(
                            Duration(microseconds: index),
                        ),
                    ),
                );
            }
        });
    }

    Future<FavoriteCacheSnapshot?> load() async
    {
        final List<FavoriteCache> rows = await (
            _database.select(_database.favoriteCaches)
                ..orderBy(<OrderClauseGenerator<FavoriteCaches>>[
                    (FavoriteCaches table) =>
                        OrderingTerm.desc(table.updatedAt),
                ])
        ).get();
        if (rows.isEmpty)
        {
            return null;
        }
        final List<FavoriteWork> works = <FavoriteWork>[];
        for (final FavoriteCache row in rows)
        {
            try
            {
                final Object? value = jsonDecode(row.recordsJson);
                if (value is! List<dynamic>)
                {
                    continue;
                }
                works.add(FavoriteWork(
                    work: _workCodec.decode(row.workJson),
                    records: value
                        .whereType<Map<String, dynamic>>()
                        .map(_decodeRecord)
                        .toList(growable: false),
                ));
            }
            on Object
            {
                continue;
            }
        }
        if (works.isEmpty)
        {
            return null;
        }
        return FavoriteCacheSnapshot(
            works: works,
            updatedAt: rows.first.updatedAt,
        );
    }

    Map<String, Object?> _encodeRecord(CloudFavoriteRecord record)
    {
        return <String, Object?>{
            'favoriteId': record.favoriteId,
            'threadId': record.threadId,
            'title': record.title,
            'threadUri': record.threadUri.toString(),
            'deleteDialogUri': record.deleteDialogUri.toString(),
        };
    }

    CloudFavoriteRecord _decodeRecord(Map<String, dynamic> value)
    {
        return CloudFavoriteRecord(
            favoriteId: _integer(value['favoriteId']),
            threadId: _integer(value['threadId']),
            title: value['title']?.toString() ?? '',
            threadUri: Uri.parse(value['threadUri']?.toString() ?? ''),
            deleteDialogUri: Uri.parse(
                value['deleteDialogUri']?.toString() ?? '',
            ),
        );
    }

    int _integer(Object? value)
    {
        return value is int ? value : int.parse(value.toString());
    }
}
