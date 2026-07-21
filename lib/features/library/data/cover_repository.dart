import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/data/title_normalizer.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

final Provider<CoverLoadCoordinator> coverLoadCoordinatorProvider =
        Provider<CoverLoadCoordinator>((Ref ref)
        {
            final CoverLoadCoordinator coordinator = CoverLoadCoordinator();
            ref.onDispose(coordinator.dispose);
            return coordinator;
        });

final Provider<CoverRepository> coverRepositoryProvider =
        Provider<CoverRepository>((Ref ref)
        {
            final CoverRepository repository = CoverRepository(
                ref.watch(appDatabaseProvider),
                ref.watch(forumLibraryRepositoryProvider),
                ref.watch(forumClientProvider),
                loadCoordinator: ref.watch(coverLoadCoordinatorProvider),
            );
            ref.onDispose(repository.dispose);
            return repository;
        });

enum CoverEntryStatus
{
    provisional,
    finalCover,
    confirmedEmpty,
    retryableFailure,
}

class CoverRequest
{
    const CoverRequest({
        required this.work,
        this.finalized = false,
        this.entryTid,
    });

    final Work work;
    final bool finalized;
    final int? entryTid;

    int get sourceTid => entryTid ?? work.primarySourceTid;

    String get cacheKey => finalized
            ? _workCoverKey(work.kind, work.id)
            : _sourceCoverKey(work.kind, sourceTid);

    @override
    bool operator ==(Object other)
    {
        return other is CoverRequest && other.cacheKey == cacheKey;
    }

    @override
    int get hashCode => cacheKey.hashCode;
}

class CoverLoadCoordinator
{
    final Set<int> _activePointers = <int>{};
    final Map<Object, _ActiveCoverScroll> _activeScrolls =
            <Object, _ActiveCoverScroll>{};
    final Map<String, int> _demands = <String, int>{};
    final Map<String, int> _unclaimedDemandStarts = <String, int>{};
    final Set<void Function()> _listeners = <void Function()>{};
    final Set<void Function(String)> _demandReleasedListeners =
            <void Function(String)>{};
    int _criticalOperations = 0;
    bool _disposed = false;

    bool get paused => _activePointers.isNotEmpty ||
            _activeScrolls.isNotEmpty ||
            _criticalOperations > 0;

    void beginCriticalOperation()
    {
        if (_disposed)
        {
            return;
        }
        final bool wasPaused = paused;
        _criticalOperations++;
        if (!wasPaused)
        {
            _notifyListeners();
        }
    }

    void endCriticalOperation()
    {
        if (_disposed || _criticalOperations == 0)
        {
            return;
        }
        final bool wasPaused = paused;
        _criticalOperations--;
        if (wasPaused != paused)
        {
            _notifyListeners();
        }
    }

    void retain(CoverRequest request)
    {
        final String key = _operationKey(request, force: false);
        _demands.update(key, (int value) => value + 1, ifAbsent: () => 1);
        _unclaimedDemandStarts.update(
            key,
            (int value) => value + 1,
            ifAbsent: () => 1,
        );
    }

    void release(CoverRequest request)
    {
        final String key = _operationKey(request, force: false);
        final int count = _demands[key] ?? 0;
        if (count == 0)
        {
            return;
        }
        if (count <= 1)
        {
            _demands.remove(key);
            _unclaimedDemandStarts.remove(key);
            _notifyDemandReleased(key);
        }
        else
        {
            _demands[key] = count - 1;
        }
    }

    bool claimDemandStart(String operationKey)
    {
        final int count = _unclaimedDemandStarts[operationKey] ?? 0;
        if (count == 0)
        {
            return false;
        }
        if (count == 1)
        {
            _unclaimedDemandStarts.remove(operationKey);
        }
        else
        {
            _unclaimedDemandStarts[operationKey] = count - 1;
        }
        return true;
    }

    bool hasDemand(String operationKey)
    {
        return (_demands[operationKey] ?? 0) > 0;
    }

    void pointerDown(int pointer)
    {
        final bool wasPaused = paused;
        _activePointers.add(pointer);
        if (!wasPaused)
        {
            _notifyListeners();
        }
    }

    void pointerUp(int pointer)
    {
        final bool wasPaused = paused;
        _activePointers.remove(pointer);
        if (wasPaused != paused)
        {
            _notifyListeners();
        }
    }

    void scrollActive(Object scrollable)
    {
        final bool wasPaused = paused;
        final _ActiveCoverScroll active = _activeScrolls.putIfAbsent(
            scrollable,
            _ActiveCoverScroll.new,
        );
        active.timer?.cancel();
        active.timer = Timer(
            const Duration(milliseconds: 500),
            () => scrollIdle(scrollable),
        );
        if (!wasPaused)
        {
            _notifyListeners();
        }
    }

    void scrollEnded(Object scrollable)
    {
        final _ActiveCoverScroll? active = _activeScrolls[scrollable];
        if (active == null)
        {
            return;
        }
        active.timer?.cancel();
        active.timer = Timer(
            const Duration(milliseconds: 150),
            () => scrollIdle(scrollable),
        );
    }

    void scrollIdle(Object scrollable)
    {
        final bool wasPaused = paused;
        _activeScrolls.remove(scrollable)?.timer?.cancel();
        if (wasPaused != paused)
        {
            _notifyListeners();
        }
    }

    void addListener(void Function() listener)
    {
        _listeners.add(listener);
    }

    void removeListener(void Function() listener)
    {
        _listeners.remove(listener);
    }

    void addDemandReleasedListener(void Function(String) listener)
    {
        _demandReleasedListeners.add(listener);
    }

    void removeDemandReleasedListener(void Function(String) listener)
    {
        _demandReleasedListeners.remove(listener);
    }

    void dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        for (final _ActiveCoverScroll active in _activeScrolls.values)
        {
            active.timer?.cancel();
        }
        _activeScrolls.clear();
        _activePointers.clear();
        _criticalOperations = 0;
        _demands.clear();
        _unclaimedDemandStarts.clear();
        _listeners.clear();
        _demandReleasedListeners.clear();
    }

    void _notifyListeners()
    {
        if (_disposed)
        {
            return;
        }
        for (final void Function() listener
                in _listeners.toList(growable: false))
        {
            listener();
        }
    }

    void _notifyDemandReleased(String operationKey)
    {
        if (_disposed)
        {
            return;
        }
        for (final void Function(String) listener
                in _demandReleasedListeners.toList(growable: false))
        {
            listener(operationKey);
        }
    }
}

class _ActiveCoverScroll
{
    Timer? timer;
}

typedef CoverImageValidator = Future<bool> Function(Uint8List bytes);

class CoverRepository
{
    static const int defaultMaximumCacheBytes = 256 * 1024 * 1024;
    static const int defaultTargetCacheBytes = 128 * 1024 * 1024;

    CoverRepository(
        this._database,
        this._libraryRepository,
        this._client, {
        Future<Directory> Function()? cacheDirectory,
        int maximumConcurrentLoads = 3,
        this.maximumCacheBytes = defaultMaximumCacheBytes,
        this.targetCacheBytes = defaultTargetCacheBytes,
        CoverImageValidator? imageValidator,
        DateTime Function()? now,
        CoverLoadCoordinator? loadCoordinator,
    })  : assert(targetCacheBytes < maximumCacheBytes),
          _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory,
          _loadGate = _LoadGate(maximumConcurrentLoads),
          _imageValidator = imageValidator ?? _validateCoverBytes,
          _now = now ?? DateTime.now,
          _loadCoordinator = loadCoordinator ?? CoverLoadCoordinator(),
          _ownsLoadCoordinator = loadCoordinator == null
    {
        _loadCoordinator.addListener(_syncLoadCoordinator);
        _loadCoordinator.addDemandReleasedListener(_cancelUndemandedOperation);
        _syncLoadCoordinator();
    }

    final AppDatabase _database;
    final ForumLibraryRepository _libraryRepository;
    final ForumClient _client;
    final Future<Directory> Function() _cacheDirectory;
    final _LoadGate _loadGate;
    final int maximumCacheBytes;
    final int targetCacheBytes;
    final CoverImageValidator _imageValidator;
    final DateTime Function() _now;
    final CoverLoadCoordinator _loadCoordinator;
    final bool _ownsLoadCoordinator;
    final TitleNormalizer _titleNormalizer = const TitleNormalizer();
    final Map<String, _PendingCoverOperation> _pending =
            <String, _PendingCoverOperation>{};
    final Map<String, Uri?> _memory = <String, Uri?>{};
    final Map<String, String> _memoryAliases = <String, String>{};
    int? _cachedSizeBytes;

    Uri? peek(CoverRequest request)
    {
        String key = request.cacheKey;
        if (!request.finalized)
        {
            key = _memoryAliases[_aliasMemoryKey(
                request.work.kind,
                request.sourceTid,
            )] ?? key;
        }
        return _memory[key];
    }

    void clearMemory()
    {
        _memory.clear();
        _memoryAliases.clear();
    }

    Future<void> clear() async
    {
        clearMemory();
        final Directory root = await _cacheRoot();
        if (await root.exists())
        {
            await root.delete(recursive: true);
        }
        _cachedSizeBytes = 0;
    }

    Future<void> maintainCache() async
    {
        final Directory root = await _cacheRoot();
        if (!await root.exists())
        {
            _cachedSizeBytes = 0;
            return;
        }
        final List<CoverCache> legacy = await _database
            .select(_database.coverCaches)
            .get();
        final List<CoverEntry> entries = await _database
            .select(_database.coverEntries)
            .get();
        final Set<String> referencedPaths = <String>{
            ...legacy.map((CoverCache value) => value.filePath),
            ...entries.map((CoverEntry value) => value.filePath),
        }
            .where((String value) => value.isNotEmpty)
            .map(path.normalize)
            .toSet();
        final DateTime orphanBefore = _now().subtract(
            const Duration(days: 1),
        );
        final List<_CoverCacheFile> files = <_CoverCacheFile>[];
        int totalBytes = 0;
        await for (final FileSystemEntity entity in root.list())
        {
            if (entity is! File)
            {
                continue;
            }
            try
            {
                final FileStat stat = await entity.stat();
                final String normalizedPath = path.normalize(entity.path);
                final bool damaged = stat.size <= 0;
                final bool staleOrphan =
                        !referencedPaths.contains(normalizedPath) &&
                        stat.modified.isBefore(orphanBefore);
                if (damaged || staleOrphan)
                {
                    await entity.delete();
                    _forgetFile(entity.path);
                    continue;
                }
                totalBytes += stat.size;
                files.add(_CoverCacheFile(
                    file: entity,
                    size: stat.size,
                    modifiedAt: stat.modified,
                ));
            }
            on FileSystemException
            {
                continue;
            }
        }
        if (totalBytes > maximumCacheBytes)
        {
            files.sort(
                (_CoverCacheFile left, _CoverCacheFile right) =>
                    left.modifiedAt.compareTo(right.modifiedAt),
            );
            for (final _CoverCacheFile entry in files)
            {
                if (totalBytes <= targetCacheBytes)
                {
                    break;
                }
                try
                {
                    await entry.file.delete();
                    totalBytes -= entry.size;
                    _forgetFile(entry.file.path);
                }
                on FileSystemException
                {
                    continue;
                }
            }
        }
        _cachedSizeBytes = totalBytes;
    }

    Future<int> cacheSizeBytes() async
    {
        final int? cached = _cachedSizeBytes;
        if (cached != null)
        {
            return cached;
        }
        final Directory root = await _cacheRoot();
        if (!await root.exists())
        {
            _cachedSizeBytes = 0;
            return 0;
        }
        int totalBytes = 0;
        await for (final FileSystemEntity entity in root.list())
        {
            if (entity is! File)
            {
                continue;
            }
            try
            {
                totalBytes += await entity.length();
            }
            on FileSystemException
            {
                continue;
            }
        }
        _cachedSizeBytes = totalBytes;
        return totalBytes;
    }

    Future<Uri?> resolve(
        Work work, {
        bool finalize = false,
        int? entryTid,
        bool force = false,
    })
    {
        final CoverRequest request = CoverRequest(
            work: work,
            finalized: finalize,
            entryTid: entryTid,
        );
        final String operationKey = _operationKey(request, force: force);
        final bool demandBound = !force &&
                _loadCoordinator.claimDemandStart(operationKey);
        final _PendingCoverOperation? pending = _pending[operationKey];
        if (pending != null && !pending.cancelled)
        {
            if (!demandBound)
            {
                pending.persistent = true;
            }
            return pending.future;
        }
        final _PendingCoverOperation operation = _PendingCoverOperation(
            operationKey,
            persistent: !demandBound,
        );
        late final Future<Uri?> future;
        future = _runOperation(request, force: force, operation: operation)
                .whenComplete(()
        {
            if (identical(_pending[operationKey], operation))
            {
                _pending.remove(operationKey);
            }
        });
        operation.future = future;
        _pending[operationKey] = operation;
        return future;
    }

    void dispose()
    {
        _loadCoordinator.removeListener(_syncLoadCoordinator);
        _loadCoordinator.removeDemandReleasedListener(
            _cancelUndemandedOperation,
        );
        if (_ownsLoadCoordinator)
        {
            _loadCoordinator.dispose();
        }
    }

    Future<void> reportBroken(CoverRequest request, Uri uri) async
    {
        final String key = await _resolvedKey(request);
        final CoverEntry? entry = await _entry(key);
        if (entry == null || entry.filePath != uri.toFilePath())
        {
            return;
        }
        await _deleteFile(entry.filePath);
        await _saveFailure(
            key: key,
            kind: request.work.kind,
            sourceTid: entry.sourceTid,
            previous: null,
        );
        _memory.remove(key);
    }

    Future<Uri?> _runOperation(
        CoverRequest request, {
        required bool force,
        required _PendingCoverOperation operation,
    }) async
    {
        try
        {
            _throwIfCancelled(operation);
            return await _resolveRequest(
                request,
                force: force,
                operation: operation,
            );
        } on _CoverLoadCancelled
        {
            return peek(request);
        }
    }

    void _syncLoadCoordinator()
    {
        _loadGate.setPaused(_loadCoordinator.paused);
    }

    void _cancelUndemandedOperation(String operationKey)
    {
        final _PendingCoverOperation? operation = _pending[operationKey];
        if (operation != null &&
                !operation.persistent &&
                !_loadCoordinator.hasDemand(operationKey))
        {
            operation.cancelled = true;
            _loadGate.cancel(operation);
        }
    }

    void _throwIfCancelled(_PendingCoverOperation operation)
    {
        if (operation.cancelled)
        {
            throw const _CoverLoadCancelled();
        }
    }

    Future<Uri?> _resolveRequest(
        CoverRequest request, {
        required bool force,
        required _PendingCoverOperation operation,
    })
    {
        return request.finalized
                ? _resolveFinal(
                        request,
                        force: force,
                        operation: operation,
                    )
                : _resolveSourceRequest(
                        request,
                        force: force,
                        operation: operation,
                    );
    }

    Future<Uri?> _resolveSourceRequest(
        CoverRequest request, {
        required bool force,
        required _PendingCoverOperation operation,
    }) async
    {
        _throwIfCancelled(operation);
        final LibraryKind kind = request.work.kind;
        final int tid = request.sourceTid;
        final String sourceKey = _sourceCoverKey(kind, tid);
        final SourceThread source = _sourceForTid(request.work, tid);
        if (!force)
        {
            final String? aliasKey = await _aliasKey(kind, tid);
            if (aliasKey != null)
            {
                final _ExistingCover aliased = await _existing(aliasKey);
                if (aliased.handled)
                {
                    _remember(aliasKey, aliased.uri);
                    _rememberAlias(kind, tid, aliasKey);
                    return aliased.uri;
                }
                if (aliasKey != sourceKey)
                {
                    final _ExistingCover sourceExisting = await _existing(
                        sourceKey,
                    );
                    final _ProbeResult result = sourceExisting.handled
                            ? sourceExisting.uri == null
                                    ? const _ProbeResult(_ProbeOutcome.noImage)
                                    : _ProbeResult.success(
                                            sourceExisting.uri!,
                                            sourceExisting.entry!,
                                        )
                            : await _loadSource(
                                    source,
                                    key: sourceKey,
                                    previous: sourceExisting,
                                    forceReload: false,
                                    operation: operation,
                                );
                    if (result.outcome == _ProbeOutcome.success)
                    {
                        final CoverEntry sourceEntry = result.entry!;
                        await _saveEntry(
                            key: aliasKey,
                            kind: kind,
                            status: CoverEntryStatus.finalCover,
                            imageUri: sourceEntry.imageUri,
                            filePath: sourceEntry.filePath,
                            sourceTid: tid,
                        );
                        _remember(aliasKey, result.uri);
                        return result.uri;
                    }
                    return aliased.uri;
                }
            }
        }

        _ExistingCover existing = await _existing(sourceKey, force: force);
        if (existing.handled)
        {
            _remember(sourceKey, existing.uri);
            await _saveAlias(kind, tid, sourceKey);
            return existing.uri;
        }
        if (existing.entry == null)
        {
            final Uri? legacy = await _importLegacy(
                legacyWorkId: request.work.id,
                key: sourceKey,
                kind: kind,
                status: CoverEntryStatus.provisional,
                sourceTid: tid,
            );
            if (legacy != null)
            {
                await _saveAlias(kind, tid, sourceKey);
                return legacy;
            }
            existing = await _existing(sourceKey, force: force);
        }

        final _ProbeResult result = await _loadSource(
            source,
            key: sourceKey,
            previous: existing,
            forceReload: force,
            operation: operation,
        );
        await _saveAlias(kind, tid, sourceKey);
        return result.uri ?? existing.uri;
    }

    Future<Uri?> _resolveFinal(
        CoverRequest request, {
        required bool force,
        required _PendingCoverOperation operation,
    }) async
    {
        _throwIfCancelled(operation);
        final Work work = request.work;
        final String finalKey = request.cacheKey;
        _ExistingCover existing = await _existing(finalKey, force: force);
        if (existing.handled)
        {
            _remember(finalKey, existing.uri);
            await _saveFinalAliases(work, finalKey);
            return existing.uri;
        }
        if (existing.entry == null)
        {
            final Uri? legacy = await _importLegacy(
                legacyWorkId: work.id,
                key: finalKey,
                kind: work.kind,
                status: CoverEntryStatus.finalCover,
            );
            if (legacy != null)
            {
                await _saveFinalAliases(work, finalKey);
                return legacy;
            }
            existing = await _existing(finalKey, force: force);
        }

        bool retryableFailure = false;
        final List<SourceThread> candidates = _finalCandidates(
            work,
            request.entryTid,
        );
        for (final SourceThread candidate in candidates)
        {
            _throwIfCancelled(operation);
            final String sourceKey = _sourceCoverKey(work.kind, candidate.tid);
            final _ExistingCover sourceExisting = await _existing(
                sourceKey,
                force: force,
            );
            final _ProbeResult result;
            if (sourceExisting.handled)
            {
                if (sourceExisting.uri != null)
                {
                    result = _ProbeResult.success(
                        sourceExisting.uri!,
                        sourceExisting.entry!,
                    );
                } else if (_status(sourceExisting.entry!.status) ==
                        CoverEntryStatus.retryableFailure)
                {
                    result = const _ProbeResult(
                        _ProbeOutcome.retryableFailure,
                    );
                } else
                {
                    result = const _ProbeResult(_ProbeOutcome.noImage);
                }
            } else
            {
                result = await _loadSource(
                    candidate,
                    key: sourceKey,
                    previous: sourceExisting,
                    forceReload: force,
                    operation: operation,
                );
            }
            if (result.outcome == _ProbeOutcome.success)
            {
                final CoverEntry sourceEntry = result.entry!;
                await _saveEntry(
                    key: finalKey,
                    kind: work.kind,
                    status: CoverEntryStatus.finalCover,
                    imageUri: sourceEntry.imageUri,
                    filePath: sourceEntry.filePath,
                    sourceTid: candidate.tid,
                );
                await _saveFinalAliases(work, finalKey);
                _remember(finalKey, result.uri);
                return result.uri;
            }
            if (result.outcome == _ProbeOutcome.retryableFailure)
            {
                retryableFailure = true;
            }
        }

        if (existing.uri != null)
        {
            if (retryableFailure)
            {
                await _saveFailure(
                    key: finalKey,
                    kind: work.kind,
                    sourceTid: existing.entry?.sourceTid,
                    previous: existing.entry,
                );
            }
            _remember(finalKey, existing.uri);
            await _saveFinalAliases(work, finalKey);
            return existing.uri;
        }
        if (retryableFailure)
        {
            await _saveFailure(
                key: finalKey,
                kind: work.kind,
                previous: existing.entry,
            );
        } else
        {
            await _saveEntry(
                key: finalKey,
                kind: work.kind,
                status: CoverEntryStatus.confirmedEmpty,
                imageUri: '',
                filePath: '',
            );
            _remember(finalKey, null);
        }
        await _saveFinalAliases(work, finalKey);
        return null;
    }

    Future<_ProbeResult> _loadSource(
        SourceThread source, {
        required String key,
        required _ExistingCover previous,
        required bool forceReload,
        required _PendingCoverOperation operation,
    }) async
    {
        final bool acquired = await _loadGate.acquire(operation);
        if (!acquired)
        {
            throw const _CoverLoadCancelled();
        }
        try
        {
            await _waitUntilRunnable(operation);
            ForumThreadPage page = await _libraryRepository.loadThread(
                source,
                forceReload: forceReload,
            );
            await _waitUntilRunnable(operation);
            PostImageBlock? image = _selectCoverImage(
                page,
                source.board.kind,
            );
            if (image == null && page.originalPosterUri != null)
            {
                await _waitUntilRunnable(operation);
                page = await _libraryRepository.loadThread(
                    source,
                    includeAllOriginalPosterPosts: true,
                    forceReload: forceReload,
                    maximumOriginalPosterPages: 1,
                );
                await _waitUntilRunnable(operation);
                image = _selectCoverImage(page, source.board.kind);
            }
            if (image == null)
            {
                if (previous.uri == null)
                {
                    await _saveEntry(
                        key: key,
                        kind: source.board.kind,
                        status: CoverEntryStatus.confirmedEmpty,
                        imageUri: '',
                        filePath: '',
                        sourceTid: source.tid,
                    );
                    _remember(key, null);
                }
                return const _ProbeResult(_ProbeOutcome.noImage);
            }

            await _waitUntilRunnable(operation);
            final Uint8List bytes = await _client.getBytes(
                image.uri,
                referer: page.uri.toString(),
            );
            await _waitUntilRunnable(operation);
            if (bytes.isEmpty || !await _imageValidator(bytes))
            {
                await _saveFailure(
                    key: key,
                    kind: source.board.kind,
                    sourceTid: source.tid,
                    previous: previous.entry,
                );
                return const _ProbeResult(_ProbeOutcome.retryableFailure);
            }
            await _waitUntilRunnable(operation);
            final File target = await _storeImage(key, image.uri, bytes);
            await _saveEntry(
                key: key,
                kind: source.board.kind,
                status: CoverEntryStatus.provisional,
                imageUri: image.uri.toString(),
                filePath: target.path,
                sourceTid: source.tid,
            );
            final CoverEntry entry = (await _entry(key))!;
            _remember(key, target.uri);
            return _ProbeResult.success(target.uri, entry);
        } on _CoverLoadCancelled
        {
            rethrow;
        } on Object
        {
            await _saveFailure(
                key: key,
                kind: source.board.kind,
                sourceTid: source.tid,
                previous: previous.entry,
            );
            return const _ProbeResult(_ProbeOutcome.retryableFailure);
        }
        finally
        {
            _loadGate.release();
        }
    }

    Future<void> _waitUntilRunnable(_PendingCoverOperation operation) async
    {
        if (!await _loadGate.checkpoint(operation))
        {
            throw const _CoverLoadCancelled();
        }
    }

    Future<_ExistingCover> _existing(
        String key, {
        bool force = false,
    }) async
    {
        final CoverEntry? entry = await _entry(key);
        if (entry == null)
        {
            return const _ExistingCover();
        }
        final Uri? uri = await _entryUri(entry);
        final CoverEntryStatus status = _status(entry.status);
        if (force)
        {
            return _ExistingCover(entry: entry, uri: uri);
        }
        if ((status == CoverEntryStatus.provisional ||
                    status == CoverEntryStatus.finalCover) &&
                uri != null)
        {
            return _ExistingCover(entry: entry, uri: uri, handled: true);
        }
        if (status == CoverEntryStatus.confirmedEmpty)
        {
            return _ExistingCover(entry: entry, handled: true);
        }
        if (status == CoverEntryStatus.retryableFailure)
        {
            final DateTime? nextRetryAt = entry.nextRetryAt;
            if (nextRetryAt != null && _now().isBefore(nextRetryAt))
            {
                return _ExistingCover(entry: entry, uri: uri, handled: true);
            }
        }
        return _ExistingCover(entry: entry, uri: uri);
    }

    Future<CoverEntry?> _entry(String key)
    {
        return (_database.select(_database.coverEntries)
              ..where((CoverEntries row) => row.coverKey.equals(key)))
            .getSingleOrNull();
    }

    Future<Uri?> _entryUri(CoverEntry entry) async
    {
        if (entry.filePath.isEmpty)
        {
            return null;
        }
        final File file = File(entry.filePath);
        final FileStat stat = await file.stat();
        if (stat.type != FileSystemEntityType.file || stat.size == 0)
        {
            return null;
        }
        await _touchIfStale(file, stat.modified);
        return file.uri;
    }

    Future<void> _saveEntry({
        required String key,
        required LibraryKind kind,
        required CoverEntryStatus status,
        required String imageUri,
        required String filePath,
        int? sourceTid,
        int retryCount = 0,
        DateTime? nextRetryAt,
    }) async
    {
        await _database.into(_database.coverEntries).insertOnConflictUpdate(
            CoverEntriesCompanion.insert(
                coverKey: key,
                libraryKind: kind.name,
                status: status.name,
                imageUri: imageUri,
                filePath: filePath,
                sourceTid: Value<int?>(sourceTid),
                retryCount: Value<int>(retryCount),
                nextRetryAt: Value<DateTime?>(nextRetryAt),
                updatedAt: _now(),
            ),
        );
    }

    Future<void> _saveFailure({
        required String key,
        required LibraryKind kind,
        required CoverEntry? previous,
        int? sourceTid,
    })
    {
        final int retryCount = (previous?.retryCount ?? 0) + 1;
        return _saveEntry(
            key: key,
            kind: kind,
            status: CoverEntryStatus.retryableFailure,
            imageUri: previous?.imageUri ?? '',
            filePath: previous?.filePath ?? '',
            sourceTid: sourceTid ?? previous?.sourceTid,
            retryCount: retryCount,
            nextRetryAt: _now().add(_retryDelay(retryCount)),
        );
    }

    Duration _retryDelay(int retryCount)
    {
        return switch (retryCount)
        {
            1 => const Duration(minutes: 5),
            2 => const Duration(hours: 1),
            _ => const Duration(hours: 24),
        };
    }

    Future<String?> _aliasKey(LibraryKind kind, int tid) async
    {
        final CoverAliase? alias = await (_database.select(
            _database.coverAliases,
        )..where(
            (CoverAliases row) =>
                    row.libraryKind.equals(kind.name) & row.tid.equals(tid),
        )).getSingleOrNull();
        return alias?.coverKey;
    }

    Future<String> _resolvedKey(CoverRequest request) async
    {
        if (request.finalized)
        {
            return request.cacheKey;
        }
        return await _aliasKey(request.work.kind, request.sourceTid) ??
                request.cacheKey;
    }

    Future<void> _saveAlias(
        LibraryKind kind,
        int tid,
        String coverKey,
    ) async
    {
        await _database.into(_database.coverAliases).insertOnConflictUpdate(
            CoverAliasesCompanion.insert(
                libraryKind: kind.name,
                tid: tid,
                coverKey: coverKey,
            ),
        );
        _rememberAlias(kind, tid, coverKey);
    }

    Future<void> _saveFinalAliases(Work work, String coverKey) async
    {
        final Set<int> tids = <int>{
            ...work.sourceThreads.map((SourceThread value) => value.tid),
            ...work.chapters.map((Chapter value) => value.sourceTid),
            ...work.directories.expand(
                (WorkDirectory value) => value.sourceTids,
            ),
            ...work.directories.expand(
                (WorkDirectory value) =>
                        value.chapters.map((Chapter chapter) => chapter.sourceTid),
            ),
        };
        await _database.transaction(() async
        {
            for (final int tid in tids)
            {
                await _database.into(_database.coverAliases).insertOnConflictUpdate(
                    CoverAliasesCompanion.insert(
                        libraryKind: work.kind.name,
                        tid: tid,
                        coverKey: coverKey,
                    ),
                );
            }
        });
        for (final int tid in tids)
        {
            _rememberAlias(work.kind, tid, coverKey);
        }
    }

    Future<Uri?> _importLegacy({
        required String legacyWorkId,
        required String key,
        required LibraryKind kind,
        required CoverEntryStatus status,
        int? sourceTid,
    }) async
    {
        final CoverCache? cached = await (_database.select(
            _database.coverCaches,
        )..where((CoverCaches row) => row.workId.equals(legacyWorkId)))
            .getSingleOrNull();
        if (cached == null)
        {
            return null;
        }
        await (_database.delete(_database.coverCaches)
              ..where((CoverCaches row) => row.workId.equals(legacyWorkId)))
            .go();
        if (cached.filePath.isEmpty)
        {
            return null;
        }
        final File file = File(cached.filePath);
        if (!await file.exists() || await file.length() == 0)
        {
            return null;
        }
        await _saveEntry(
            key: key,
            kind: kind,
            status: status,
            imageUri: cached.imageUri,
            filePath: cached.filePath,
            sourceTid: sourceTid,
        );
        _remember(key, file.uri);
        return file.uri;
    }

    List<SourceThread> _finalCandidates(Work work, int? entryTid)
    {
        final Map<int, SourceThread> sources = <int, SourceThread>{
            for (final SourceThread source in work.sourceThreads) source.tid: source,
        };
        for (final Chapter chapter in work.chapters)
        {
            sources.putIfAbsent(
                chapter.sourceTid,
                () => SourceThread(
                    tid: chapter.sourceTid,
                    board: work.primaryBoard,
                    title: chapter.title,
                    uri: chapter.sourceUri,
                ),
            );
        }

        final List<SourceThread> result = <SourceThread>[];
        final Set<int> seen = <int>{};
        void add(SourceThread? source)
        {
            if (source != null && seen.add(source.tid) && result.length < 3)
            {
                result.add(source);
            }
        }

        final List<SourceThread> roots = work.sourceThreads.where((
            SourceThread source,
        )
        {
            final StructuredTitle title = _titleNormalizer.analyze(source.title);
            return !title.hasChapterMarker &&
                    (work.kind != LibraryKind.novel ||
                            title.novelEdition != NovelEdition.book);
        }).toList(growable: true)
            ..sort(_compareSourceAge);
        add(roots.firstOrNull);

        final List<Chapter> ordered = <Chapter>[...work.chapters]
            ..sort((Chapter left, Chapter right)
            {
                if (work.kind == LibraryKind.novel)
                {
                    final int edition = (left.novelEdition ?? NovelEdition.serial)
                            .index
                            .compareTo(
                                (right.novelEdition ?? NovelEdition.serial).index,
                            );
                    if (edition != 0)
                    {
                        return edition;
                    }
                    final int volume = (left.volumeOrder ?? double.infinity)
                            .compareTo(right.volumeOrder ?? double.infinity);
                    if (volume != 0)
                    {
                        return volume;
                    }
                }
                return (left.order ?? double.infinity)
                        .compareTo(right.order ?? double.infinity);
            });
        for (final Chapter chapter in ordered)
        {
            if (chapter.order != null && chapter.order! >= 800000)
            {
                continue;
            }
            add(sources[chapter.sourceTid]);
            break;
        }
        add(sources[entryTid ?? work.primarySourceTid]);
        for (final SourceThread source in sources.values)
        {
            add(source);
            if (result.length >= 3)
            {
                break;
            }
        }
        return result;
    }

    int _compareSourceAge(SourceThread left, SourceThread right)
    {
        final DateTime? leftTime = left.postedAt;
        final DateTime? rightTime = right.postedAt;
        if (leftTime != null && rightTime != null)
        {
            final int result = leftTime.compareTo(rightTime);
            if (result != 0)
            {
                return result;
            }
        } else if (leftTime != null)
        {
            return -1;
        } else if (rightTime != null)
        {
            return 1;
        }
        return left.tid.compareTo(right.tid);
    }

    SourceThread _sourceForTid(Work work, int tid)
    {
        for (final SourceThread source in work.sourceThreads)
        {
            if (source.tid == tid)
            {
                return source;
            }
        }
        for (final Chapter chapter in work.chapters)
        {
            if (chapter.sourceTid == tid)
            {
                return SourceThread(
                    tid: tid,
                    board: work.primaryBoard,
                    title: chapter.title,
                    uri: chapter.sourceUri,
                );
            }
        }
        return work.primarySourceThread;
    }

    Future<File> _storeImage(
        String key,
        Uri imageUri,
        Uint8List bytes,
    ) async
    {
        final Directory root = await _cacheRoot();
        await root.create(recursive: true);
        final String contentHash = sha256.convert(bytes).toString();
        final String extension = _safeExtension(imageUri);
        final File target = File(path.join(root.path, '$contentHash$extension'));
        if (await target.exists() && await target.length() > 0)
        {
            return target;
        }
        final String operationHash = sha256
                .convert('$key\n$imageUri'.codeUnits)
                .toString()
                .substring(0, 12);
        final File partial = File('${target.path}.$operationHash.part');
        await partial.writeAsBytes(bytes, flush: true);
        if (await target.exists())
        {
            await partial.delete();
        } else
        {
            await partial.rename(target.path);
            _cachedSizeBytes = null;
        }
        return target;
    }

    Future<Directory> _cacheRoot() async
    {
        return Directory(
            path.join((await _cacheDirectory()).path, 'covers'),
        );
    }

    void _forgetFile(String filePath)
    {
        _memory.removeWhere(
            (String _, Uri? cached) => cached != null &&
                    cached.scheme == 'file' &&
                    cached.toFilePath() == filePath,
        );
    }

    Future<void> _touchIfStale(File file, DateTime modifiedAt) async
    {
        try
        {
            final DateTime now = _now();
            if (now.difference(modifiedAt) >= const Duration(days: 1))
            {
                await file.setLastModified(now);
            }
        }
        on FileSystemException
        {
            return;
        }
    }

    PostImageBlock? _selectCoverImage(
        ForumThreadPage page,
        LibraryKind kind,
    )
    {
        final SourcePost? firstPost = page.originalPost;
        final PostImageBlock? firstImage = firstPost?.blocks
                .whereType<PostImageBlock>()
                .firstOrNull;
        if (firstImage != null)
        {
            return firstImage;
        }
        if (kind != LibraryKind.novel)
        {
            return page.posts
                    .where((SourcePost post) => post.isOriginalPoster)
                    .expand((SourcePost post) => post.blocks)
                    .whereType<PostImageBlock>()
                    .firstOrNull;
        }
        for (final SourcePost post in page.posts.where(
            (SourcePost value) => value.isOriginalPoster &&
                    !identical(value, firstPost),
        ))
        {
            for (int index = 0; index < post.blocks.length; index++)
            {
                final PostContentBlock block = post.blocks[index];
                if (block is PostImageBlock &&
                        _hasNovelCoverContext(post.blocks, index, block.alt))
                {
                    return block;
                }
            }
        }
        return null;
    }

    bool _hasNovelCoverContext(
        List<PostContentBlock> blocks,
        int imageIndex,
        String alt,
    )
    {
        final List<String> context = <String>[alt];
        if (imageIndex > 0 && blocks[imageIndex - 1] is PostTextBlock)
        {
            final String text = (blocks[imageIndex - 1] as PostTextBlock).text;
            context.add(
                text.length <= 160 ? text : text.substring(text.length - 160),
            );
        }
        if (imageIndex + 1 < blocks.length &&
                blocks[imageIndex + 1] is PostTextBlock)
        {
            final String text = (blocks[imageIndex + 1] as PostTextBlock).text;
            context.add(text.length <= 160 ? text : text.substring(0, 160));
        }
        final String value = context.join(' ').toLowerCase();
        if (RegExp(
            r'图文无关|圖文無關|表情|截图|截圖|晒图|曬圖|'
            r'闲聊|閒聊|梗图|梗圖|聊天|吐槽|感想',
        ).hasMatch(value))
        {
            return false;
        }
        return RegExp(
            r'封面|书影|書影|封绘|封繪|彩插|插图|插圖|'
            r'cover|illustration',
            caseSensitive: false,
        ).hasMatch(value);
    }

    String _safeExtension(Uri uri)
    {
        final String extension = path.extension(uri.path).toLowerCase();
        return const <String>{'.jpg', '.jpeg', '.png', '.webp', '.gif'}
                .contains(extension)
                ? extension
                : '.img';
    }

    void _remember(String key, Uri? uri)
    {
        _memory[key] = uri;
    }

    void _rememberAlias(LibraryKind kind, int tid, String coverKey)
    {
        _memoryAliases[_aliasMemoryKey(kind, tid)] = coverKey;
    }

    Future<void> _deleteFile(String filePath) async
    {
        if (filePath.isEmpty)
        {
            return;
        }
        final File file = File(filePath);
        if (await file.exists())
        {
            await file.delete();
        }
    }

    CoverEntryStatus _status(String value)
    {
        return CoverEntryStatus.values.firstWhere(
            (CoverEntryStatus status) => status.name == value,
            orElse: () => CoverEntryStatus.retryableFailure,
        );
    }
}

class _ExistingCover
{
    const _ExistingCover({
        this.entry,
        this.uri,
        this.handled = false,
    });

    final CoverEntry? entry;
    final Uri? uri;
    final bool handled;
}

class _CoverCacheFile
{
    const _CoverCacheFile({
        required this.file,
        required this.size,
        required this.modifiedAt,
    });

    final File file;
    final int size;
    final DateTime modifiedAt;
}

enum _ProbeOutcome { success, noImage, retryableFailure }

class _ProbeResult
{
    const _ProbeResult(this.outcome, {this.uri, this.entry});

    const _ProbeResult.success(Uri uri, CoverEntry entry)
        : this(_ProbeOutcome.success, uri: uri, entry: entry);

    final _ProbeOutcome outcome;
    final Uri? uri;
    final CoverEntry? entry;
}

class _PendingCoverOperation
{
    _PendingCoverOperation(this.key, {required this.persistent});

    final String key;
    bool persistent;
    bool cancelled = false;
    late final Future<Uri?> future;
}

class _CoverLoadCancelled implements Exception
{
    const _CoverLoadCancelled();
}

class _LoadWaiter
{
    _LoadWaiter(this.operation);

    final _PendingCoverOperation operation;
    final Completer<bool> completer = Completer<bool>();
}

class _LoadGate
{
    _LoadGate(this.maximumConcurrentLoads)
        : assert(maximumConcurrentLoads > 0);

    final int maximumConcurrentLoads;
    int _activeLoads = 0;
    bool _paused = false;
    final Queue<_LoadWaiter> _waiting = Queue<_LoadWaiter>();
    final Queue<_LoadWaiter> _pausedOperations = Queue<_LoadWaiter>();

    Future<bool> acquire(_PendingCoverOperation operation)
    {
        if (operation.cancelled)
        {
            return Future<bool>.value(false);
        }
        if (!_paused && _activeLoads < maximumConcurrentLoads)
        {
            _activeLoads++;
            return Future<bool>.value(true);
        }
        final _LoadWaiter waiter = _LoadWaiter(operation);
        _waiting.add(waiter);
        return waiter.completer.future;
    }

    Future<bool> checkpoint(_PendingCoverOperation operation)
    {
        if (operation.cancelled)
        {
            return Future<bool>.value(false);
        }
        if (!_paused)
        {
            return Future<bool>.value(true);
        }
        final _LoadWaiter waiter = _LoadWaiter(operation);
        _pausedOperations.add(waiter);
        return waiter.completer.future;
    }

    void setPaused(bool value)
    {
        if (_paused == value)
        {
            return;
        }
        _paused = value;
        if (_paused)
        {
            return;
        }
        while (_pausedOperations.isNotEmpty)
        {
            final _LoadWaiter waiter = _pausedOperations.removeFirst();
            waiter.completer.complete(!waiter.operation.cancelled);
        }
        _drain();
    }

    void cancel(_PendingCoverOperation operation)
    {
        operation.cancelled = true;
        _completeCancelled(_waiting, operation);
        _completeCancelled(_pausedOperations, operation);
    }

    void release()
    {
        if (_activeLoads > 0)
        {
            _activeLoads--;
        }
        _drain();
    }

    void _drain()
    {
        while (!_paused &&
                _activeLoads < maximumConcurrentLoads &&
                _waiting.isNotEmpty)
        {
            final _LoadWaiter waiter = _waiting.removeFirst();
            if (waiter.operation.cancelled)
            {
                waiter.completer.complete(false);
                continue;
            }
            _activeLoads++;
            waiter.completer.complete(true);
        }
    }

    void _completeCancelled(
        Queue<_LoadWaiter> queue,
        _PendingCoverOperation operation,
    )
    {
        final List<_LoadWaiter> cancelled = queue
                .where(
                    (_LoadWaiter waiter) =>
                            identical(waiter.operation, operation),
                )
                .toList(growable: false);
        for (final _LoadWaiter waiter in cancelled)
        {
            queue.remove(waiter);
            waiter.completer.complete(false);
        }
    }
}

Future<bool> _validateCoverBytes(Uint8List bytes) async
{
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try
    {
        buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        final int width = descriptor.width;
        final int height = descriptor.height;
        if (width <= 96 || height <= 96)
        {
            return false;
        }
        codec = await descriptor.instantiateCodec(
            targetWidth: width >= height && width > 256 ? 256 : null,
            targetHeight: height > width && height > 256 ? 256 : null,
        );
        final ui.FrameInfo frame = await codec.getNextFrame();
        frame.image.dispose();
        return true;
    } on Object
    {
        return false;
    }
    finally
    {
        codec?.dispose();
        descriptor?.dispose();
        buffer?.dispose();
    }
}

String _sourceCoverKey(LibraryKind kind, int tid)
{
    return 'cover:${kind.name}:source:$tid';
}

String _operationKey(CoverRequest request, {required bool force})
{
    return '${request.cacheKey}|force=$force';
}

String _workCoverKey(LibraryKind kind, String workId)
{
    return 'cover:${kind.name}:work:$workId';
}

String _aliasMemoryKey(LibraryKind kind, int tid)
{
    return '${kind.name}:$tid';
}
