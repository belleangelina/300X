import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/core/storage/work_codec.dart';
import 'package:x300/features/library/domain/library_models.dart';

final Provider<SearchCacheRepository> searchCacheRepositoryProvider =
    Provider<SearchCacheRepository>(
        (Ref ref) => SearchCacheRepository(
            ref.watch(appDatabaseProvider),
        ),
    );

class SearchCacheSnapshot
{
    const SearchCacheSnapshot({
        required this.works,
        required this.updatedAt,
    });

    final List<Work> works;
    final DateTime updatedAt;
}

class SearchCacheRepository
{
    static const int maximumEntriesPerKind = 50;

    SearchCacheRepository(
        this._database, [
        this._workCodec = const WorkCodec(),
    ]);

    final AppDatabase _database;
    final WorkCodec _workCodec;

    Future<void> save({
        required LibraryKind kind,
        required String keyword,
        required List<Work> works,
        DateTime? updatedAt,
    }) async
    {
        final String normalizedKeyword = _normalize(keyword);
        await _database.into(_database.searchCaches).insertOnConflictUpdate(
            SearchCachesCompanion.insert(
                cacheKey: _key(kind, normalizedKeyword),
                libraryKind: kind.name,
                keyword: normalizedKeyword,
                worksJson: jsonEncode(
                    works
                        .map(_workCodec.encode)
                        .toList(growable: false),
                ),
                updatedAt: updatedAt ?? DateTime.now(),
            ),
        );
    }

    Future<void> prune({LibraryKind? kind}) async
    {
        final Iterable<LibraryKind> kinds = kind == null
                ? LibraryKind.values
                : <LibraryKind>[kind];
        for (final LibraryKind value in kinds)
        {
            final List<SearchCache> rows = await (
                _database.select(_database.searchCaches)
                    ..where(
                        (SearchCaches table) =>
                            table.libraryKind.equals(value.name),
                    )
                    ..orderBy(<OrderClauseGenerator<SearchCaches>>[
                        (SearchCaches table) =>
                            OrderingTerm.desc(table.updatedAt),
                    ])
            ).get();
            if (rows.length <= maximumEntriesPerKind)
            {
                continue;
            }
            final List<String> staleKeys = rows
                .skip(maximumEntriesPerKind)
                .map((SearchCache row) => row.cacheKey)
                .toList(growable: false);
            await (_database.delete(_database.searchCaches)
                  ..where(
                      (SearchCaches table) =>
                          table.cacheKey.isIn(staleKeys),
                  ))
                .go();
        }
    }

    Future<SearchCacheSnapshot?> load({
        required LibraryKind kind,
        required String keyword,
    }) async
    {
        final SearchCache? row = await (
            _database.select(_database.searchCaches)
                ..where(
                    (SearchCaches table) => table.cacheKey.equals(
                        _key(kind, _normalize(keyword)),
                    ),
                )
        ).getSingleOrNull();
        if (row == null)
        {
            return null;
        }
        try
        {
            final Object? value = jsonDecode(row.worksJson);
            if (value is! List<dynamic>)
            {
                return null;
            }
            return SearchCacheSnapshot(
                works: value
                    .whereType<String>()
                    .map(_workCodec.decode)
                    .toList(growable: false),
                updatedAt: row.updatedAt,
            );
        }
        on Object
        {
            return null;
        }
    }

    String _key(LibraryKind kind, String keyword)
    {
        return '${kind.name}:$keyword';
    }

    String _normalize(String keyword)
    {
        return keyword.trim().toLowerCase();
    }
}
