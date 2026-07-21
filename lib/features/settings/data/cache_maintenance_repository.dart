import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/reader/data/reader_media_repository.dart';
import 'package:x300/features/search/data/search_cache_repository.dart';

final Provider<CacheMaintenanceRepository> cacheMaintenanceRepositoryProvider =
    Provider<CacheMaintenanceRepository>(
        (Ref ref) => CacheMaintenanceRepository(
            ref.watch(appDatabaseProvider),
            ref.watch(coverRepositoryProvider),
            ref.watch(readerMediaRepositoryProvider),
            ref.watch(searchCacheRepositoryProvider),
        ),
    );

class CacheUsageSnapshot
{
    const CacheUsageSnapshot({
        required this.temporaryBytes,
        required this.coverBytes,
    });

    final int temporaryBytes;
    final int coverBytes;
}

class CacheMaintenanceRepository
{
    CacheMaintenanceRepository(
        this._database, [
        this._coverRepository,
        this._readerMediaRepository,
        this._searchCacheRepository,
    ]);

    final AppDatabase _database;
    final CoverRepository? _coverRepository;
    final ReaderMediaRepository? _readerMediaRepository;
    final SearchCacheRepository? _searchCacheRepository;
    bool _automaticMaintenanceStarted = false;

    Future<void> maintainAutomatically() async
    {
        if (_automaticMaintenanceStarted)
        {
            return;
        }
        _automaticMaintenanceStarted = true;
        await _bestEffort(_readerMediaRepository?.maintainCache);
        await _bestEffort(_coverRepository?.maintainCache);
        await _bestEffort(_searchCacheRepository?.prune);
    }

    Future<CacheUsageSnapshot> measureUsage() async
    {
        final List<int> sizes = await Future.wait<int>(<Future<int>>[
            _readerMediaRepository?.cacheSizeBytes() ?? Future<int>.value(0),
            _coverRepository?.cacheSizeBytes() ?? Future<int>.value(0),
        ]);
        return CacheUsageSnapshot(
            temporaryBytes: sizes[0],
            coverBytes: sizes[1],
        );
    }

    Future<void> clearTemporaryCaches() async
    {
        await _database.transaction(() async
        {
            await _database.delete(_database.searchCaches).go();
            await _database.delete(_database.favoriteCaches).go();
        });
        await _readerMediaRepository?.clear();
    }

    Future<void> clearCoverCaches() async
    {
        final List<CoverCache> covers = await _database
            .select(_database.coverCaches)
            .get();
        final List<CoverEntry> entries = await _database
            .select(_database.coverEntries)
            .get();
        final Set<String> filePaths = <String>{
            ...covers.map((CoverCache value) => value.filePath),
            ...entries.map((CoverEntry value) => value.filePath),
        }..remove('');
        for (final String filePath in filePaths)
        {
            final File file = File(filePath);
            if (await file.exists())
            {
                await file.delete();
            }
        }
        await _coverRepository?.clear();
        await _database.transaction(() async
        {
            await _database.delete(_database.coverAliases).go();
            await _database.delete(_database.coverEntries).go();
            await _database.delete(_database.coverCaches).go();
        });
    }

    Future<void> clearAccountCaches() async
    {
        await clearTemporaryCaches();
        await clearCoverCaches();
    }

    Future<void> _bestEffort(Future<void> Function()? action) async
    {
        if (action == null)
        {
            return;
        }
        try
        {
            await action();
        }
        on Object
        {
            return;
        }
    }
}
