import 'dart:async';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/features/library/data/chapter_resolver.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/data/long_form_classifier.dart';
import 'package:x300/features/library/data/title_normalizer.dart';
import 'package:x300/features/library/data/work_aggregator.dart';
import 'package:x300/features/library/data/work_anchor_selector.dart';
import 'package:x300/features/library/data/work_index_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';
import 'package:x300/features/search/application/search_cooldown.dart';
import 'package:x300/features/search/data/forum_search_repository.dart';
import 'package:x300/features/search/domain/search_models.dart';

final Provider<WorkIndexCoordinator> workIndexCoordinatorProvider =
        Provider<WorkIndexCoordinator>(
            (Ref ref) => WorkIndexCoordinator(
                ref.watch(workIndexRepositoryProvider),
                ref.watch(forumLibraryRepositoryProvider),
                ref.watch(forumSearchRepositoryProvider),
                ref.watch(searchCooldownProvider),
            ),
        );

typedef WorkIndexProgress = void Function(String message);

class WorkIndexCancellation
{
    bool _cancelled = false;

    bool get isCancelled => _cancelled;

    void cancel()
    {
        _cancelled = true;
    }

    void throwIfCancelled()
    {
        if (_cancelled)
        {
            throw const WorkIndexCancelledException();
        }
    }
}

class WorkIndexCancelledException implements Exception
{
    const WorkIndexCancelledException();

    @override
    String toString()
    {
        return '作品目录解析已取消';
    }
}

class WorkIndexResult
{
    const WorkIndexResult({
        required this.work,
        this.updateAvailable = false,
        this.warning,
    });

    final Work work;
    final bool updateAvailable;
    final String? warning;
}

class WorkIndexCoordinator
{
    WorkIndexCoordinator(
        this._indexRepository,
        this._libraryRepository,
        this._searchRepository,
        this._searchCooldown, [
        this._chapterResolver = const ChapterResolver(),
        this._workAggregator = const WorkAggregator(),
        this._titleNormalizer = const TitleNormalizer(),
        this._longFormClassifier = const LongFormClassifier(),
        this._anchorSelector = const WorkAnchorSelector(),
    ]);

    final WorkIndexRepository _indexRepository;
    final ForumLibraryRepository _libraryRepository;
    final ForumSearchRepository _searchRepository;
    final SearchCooldown _searchCooldown;
    final ChapterResolver _chapterResolver;
    final WorkAggregator _workAggregator;
    final TitleNormalizer _titleNormalizer;
    final LongFormClassifier _longFormClassifier;
    final WorkAnchorSelector _anchorSelector;
    final Map<String, Future<WorkIndexResult>> _ensureTasks =
            <String, Future<WorkIndexResult>>{};
    final Map<String, Future<WorkIndexResult>> _refreshTasks =
            <String, Future<WorkIndexResult>>{};

    Future<WorkIndexRecord?> lookup(Work work) async
    {
        for (final int tid in _sourceTids(work))
        {
            final WorkIndexRecord? record = await _indexRepository.loadBySourceTid(
                tid,
                work.kind,
            );
            if (record != null)
            {
                return _decorateRecord(record, work);
            }
        }
        final String? canonicalKey = _workAggregator.canonicalKeyForWork(work);
        if (canonicalKey != null)
        {
            final WorkIndexRecord? record = await _indexRepository.loadByCanonicalKey(
                canonicalKey,
                work.kind,
            );
            if (record != null)
            {
                return _decorateRecord(record, work);
            }
        }
        final WorkIndexRecord? record = await _indexRepository.loadByWorkId(
            work.id,
            work.kind,
        );
        return record == null ? null : _decorateRecord(record, work);
    }

    Future<WorkIndexResult> ensure(
        Work work, {
        bool allowNewSearch = true,
        WorkIndexProgress? onProgress,
        WorkIndexCancellation? cancellation,
    })
    {
        final String taskKey = '${_taskKey(work)}|ensure=$allowNewSearch'
                '${_cancellationTaskSuffix(cancellation)}';
        final Future<WorkIndexResult>? existing = _ensureTasks[taskKey];
        if (existing != null)
        {
            return existing;
        }
        final Future<WorkIndexResult> task = _ensure(
            work,
            allowNewSearch: allowNewSearch,
            onProgress: onProgress,
            cancellation: cancellation,
        );
        _ensureTasks[taskKey] = task;
        return task.whenComplete(()
        {
            if (identical(_ensureTasks[taskKey], task))
            {
                _ensureTasks.remove(taskKey);
            }
        });
    }

    Future<WorkIndexResult> refresh(
        Work work, {
        WorkIndexProgress? onProgress,
        WorkIndexCancellation? cancellation,
    }) async
    {
        cancellation?.throwIfCancelled();
        final String taskKey = _taskKey(work);
        Future<WorkIndexResult>? ensureTask;
        for (final MapEntry<String, Future<WorkIndexResult>> entry
                in _ensureTasks.entries)
        {
            if (entry.key.startsWith('$taskKey|ensure='))
            {
                ensureTask = entry.value;
                break;
            }
        }
        if (ensureTask != null)
        {
            await ensureTask;
            cancellation?.throwIfCancelled();
        }
        return _runRefreshTask(
            work,
            onProgress: onProgress,
            allowNewSearch: true,
            trustSeedUpdate: false,
            cancellation: cancellation,
        );
    }

    Future<WorkIndexResult> rebuildFromActiveSearch(
        Work work, {
        WorkIndexProgress? onProgress,
        WorkIndexCancellation? cancellation,
    })
    {
        return _runRefreshTask(
            work,
            onProgress: onProgress,
            allowNewSearch: false,
            trustSeedUpdate: true,
            cancellation: cancellation,
        );
    }

    Work? findMatchingWork(Work selected, List<Work> candidates)
    {
        if (selected.kind == LibraryKind.novel)
        {
            final List<Work> matches = candidates
                    .where(
                        (Work candidate) =>
                                _workAggregator.matches(selected, candidate),
                    )
                    .toList(growable: false);
            if (matches.isEmpty)
            {
                return null;
            }
            return _mergeWorks(
                <Work>[selected, ...matches],
                workId: selected.id,
            );
        }
        Work? sharedResult;
        Work? compatibleResult;
        for (final Work candidate in candidates)
        {
            if (!_workAggregator.matches(selected, candidate))
            {
                continue;
            }
            if (_workAggregator.sharesSource(selected, candidate))
            {
                if (sharedResult == null ||
                        _candidateChapterCount(candidate) >
                                _candidateChapterCount(sharedResult))
                {
                    sharedResult = candidate;
                }
            } else if (compatibleResult == null ||
                    _candidateChapterCount(candidate) >
                            _candidateChapterCount(compatibleResult))
            {
                compatibleResult = candidate;
            }
        }
        return sharedResult ?? compatibleResult;
    }

    int _candidateChapterCount(Work work)
    {
        if (work.directories.isEmpty)
        {
            return work.chapters.length;
        }
        return work.directories.fold<int>(
            0,
            (int total, WorkDirectory directory) => total + directory.chapters.length,
        );
    }

    bool shouldCompleteActiveSearch(Work work)
    {
        return work.kind == LibraryKind.novel
                ? work.sourceThreads.any(
                        (SourceThread thread) =>
                                _titleNormalizer.analyze(thread.title).novelEdition ==
                                        NovelEdition.book ||
                                _titleNormalizer
                                        .detectNovelBareVolumeCandidate(thread.title) !=
                                        null,
                    )
                : !_longFormClassifier.isExplicitShortComic(work) &&
                            (_longFormClassifier.isExplicitLongComic(work) ||
                                    work.sourceThreads.length >= 2 &&
                                            _workAggregator.hasStrongChapterMarker(work));
    }

    Future<WorkIndexResult> _ensure(
        Work work, {
        required bool allowNewSearch,
        WorkIndexProgress? onProgress,
        WorkIndexCancellation? cancellation,
    }) async
    {
        cancellation?.throwIfCancelled();
        onProgress?.call('正在检查本机作品索引');
        final WorkIndexRecord? existing = await lookup(work);
        cancellation?.throwIfCancelled();
        if (existing != null)
        {
            final bool updateAvailable = _sourceTids(
                work,
            ).any((int tid) => !_sourceTids(existing.work).contains(tid));
            return WorkIndexResult(
                work: existing.work,
                updateAvailable: updateAvailable,
            );
        }
        return _rebuild(
            work,
            oldRecord: null,
            onProgress: onProgress,
            allowNewSearch: allowNewSearch,
            trustSeedUpdate: false,
            forceThreadReload: false,
            cancellation: cancellation,
        );
    }

    Future<WorkIndexResult> _runRefreshTask(
        Work work, {
        required bool allowNewSearch,
        required bool trustSeedUpdate,
        WorkIndexProgress? onProgress,
        WorkIndexCancellation? cancellation,
    })
    {
        final String taskKey = '${_taskKey(work)}'
                '${_cancellationTaskSuffix(cancellation)}';
        final Future<WorkIndexResult>? existing = _refreshTasks[taskKey];
        if (existing != null)
        {
            return existing;
        }
        final Future<WorkIndexResult> task = () async
        {
            cancellation?.throwIfCancelled();
            final WorkIndexRecord? oldRecord = await lookup(work);
            cancellation?.throwIfCancelled();
            return _rebuild(
                work,
                oldRecord: oldRecord,
                onProgress: onProgress,
                allowNewSearch: allowNewSearch,
                trustSeedUpdate: trustSeedUpdate,
                forceThreadReload: true,
                cancellation: cancellation,
            );
        }();
        _refreshTasks[taskKey] = task;
        return task.whenComplete(()
        {
            if (identical(_refreshTasks[taskKey], task))
            {
                _refreshTasks.remove(taskKey);
            }
        });
    }

    Future<WorkIndexResult> _rebuild(
        Work seed, {
        required WorkIndexRecord? oldRecord,
        required bool allowNewSearch,
        required bool trustSeedUpdate,
        required bool forceThreadReload,
        WorkIndexProgress? onProgress,
        WorkIndexCancellation? cancellation,
    }) async
    {
        cancellation?.throwIfCancelled();
        if (seed.kind == LibraryKind.novel)
        {
            return _rebuildNovel(
                seed,
                oldRecord: oldRecord,
                allowNewSearch: allowNewSearch,
                trustSeedUpdate: trustSeedUpdate,
                forceThreadReload: forceThreadReload,
                onProgress: onProgress,
                cancellation: cancellation,
            );
        }
        Work current = seed;
        Work? searchCandidate;
        Object? searchError;
        Object? threadError;
        bool explicitShort = _longFormClassifier.isExplicitShortComic(seed);
        final bool completeComic = _shouldUseCompleteComicPipeline(
            seed,
            trustSeedUpdate: trustSeedUpdate,
        );

        if (completeComic)
        {
            if (allowNewSearch)
            {
                try
                {
                    searchCandidate = await _searchCompleteWork(
                        seed,
                        onProgress: onProgress,
                        cancellation: cancellation,
                    );
                    cancellation?.throwIfCancelled();
                } on WorkIndexCancelledException
                {
                    rethrow;
                } on Object catch (error)
                {
                    searchError = error;
                }
            } else if (trustSeedUpdate)
            {
                searchCandidate = seed;
            }

            if (oldRecord != null && searchError != null)
            {
                return WorkIndexResult(
                    work: oldRecord.work,
                    warning: '更新未完成，已保留上次作品索引：$searchError',
                );
            }

            final Work completeWork = searchCandidate == null
                    ? seed
                    : _mergeWorks(<Work>[searchCandidate, seed]);
            onProgress?.call('正在按来源解析楼主帖子和帖内目录');
            final _LongComicResolution resolution =
                    await _resolveLongComicDirectories(
                        completeWork,
                        forceReload: forceThreadReload,
                        onProgress: onProgress,
                        cancellation: cancellation,
                    );
            cancellation?.throwIfCancelled();
            current = resolution.work;
            threadError = resolution.error;
            explicitShort = resolution.explicitShort;
        } else
        {
            onProgress?.call('正在解析楼主帖子和帖内目录');
            final _ThreadResolution threadResolution = await _resolveThread(
                seed,
                forceReload: forceThreadReload,
                onProgress: onProgress,
                cancellation: cancellation,
            );
            cancellation?.throwIfCancelled();
            current = threadResolution.work;
            threadError = threadResolution.error;
            explicitShort = threadResolution.explicitShort;
            final bool needsSearch =
                    allowNewSearch &&
                    !explicitShort &&
                    _shouldSearchCrossThread(
                        threadResolution.work,
                        threadResolution.evidence,
                        overrodeShort: threadResolution.overrodeShort,
                    );
            if (needsSearch)
            {
                try
                {
                    searchCandidate = await _searchCompleteWork(
                        threadResolution.work,
                        onProgress: onProgress,
                        cancellation: cancellation,
                    );
                    cancellation?.throwIfCancelled();
                } on WorkIndexCancelledException
                {
                    rethrow;
                } on Object catch (error)
                {
                    searchError = error;
                }
            }

            if (oldRecord != null && searchError != null)
            {
                return WorkIndexResult(
                    work: oldRecord.work,
                    warning: '更新未完成，已保留上次作品索引：$searchError',
                );
            }
            if (searchCandidate != null &&
                    (_longFormClassifier.isExplicitLongComic(current) ||
                            threadResolution.overrodeShort))
            {
                final Work completeWork = _mergeWorks(<Work>[searchCandidate, current]);
                final _LongComicResolution resolution =
                        await _resolveLongComicDirectories(
                            completeWork,
                            forceReload: forceThreadReload,
                            onProgress: onProgress,
                            cancellation: cancellation,
                        );
                cancellation?.throwIfCancelled();
                current = resolution.work;
                threadError ??= resolution.error;
            } else if (searchCandidate != null)
            {
                current = _mergeWorks(<Work>[current, searchCandidate]);
            }
        }

        if (oldRecord != null &&
                threadError != null &&
                searchCandidate == null &&
                !trustSeedUpdate)
        {
            return WorkIndexResult(
                work: oldRecord.work,
                warning: '帖子解析失败，已保留上次作品索引：$threadError',
            );
        }

        final List<Work> versions = explicitShort
                ? <Work>[current]
                : <Work>[if (oldRecord != null) oldRecord.work, seed, current];
        final String canonicalKey =
                _workAggregator.canonicalKeyForWork(searchCandidate ?? current) ??
                oldRecord?.canonicalKey ??
                _fallbackCanonicalKey(seed);
        final String workId = oldRecord?.work.id ?? seed.id;
        final Work merged = _mergeWorks(versions, workId: workId);
        cancellation?.throwIfCancelled();
        onProgress?.call('正在保存作品索引');
        await _indexRepository.save(canonicalKey: canonicalKey, work: merged);
        cancellation?.throwIfCancelled();
        return WorkIndexResult(
            work: merged,
            warning: searchError == null
                    ? threadError == null
                                ? null
                                : '帖子目录暂时无法完整解析，已保存现有目录索引'
                    : '跨帖补全失败，已保存当前目录：$searchError',
        );
    }

    Future<WorkIndexResult> _rebuildNovel(
        Work seed, {
        required WorkIndexRecord? oldRecord,
        required bool allowNewSearch,
        required bool trustSeedUpdate,
        required bool forceThreadReload,
        WorkIndexProgress? onProgress,
        WorkIndexCancellation? cancellation,
    }) async
    {
        cancellation?.throwIfCancelled();
        onProgress?.call('正在解析当前小说主题');
        final SourceThread anchor = _anchorThread(seed);
        final _ThreadResolution initial = await _resolveThread(
            _novelThreadWork(seed, anchor),
            forceReload: forceThreadReload,
            onProgress: onProgress,
            cancellation: cancellation,
        );
        cancellation?.throwIfCancelled();

        Work? searchCandidate;
        Object? searchError;
        if (allowNewSearch &&
                _hasExplicitNovelVolumes(seed, initial.relatedThreads))
        {
            try
            {
                searchCandidate = await _searchCompleteWork(
                    seed,
                    onProgress: onProgress,
                    cancellation: cancellation,
                );
                cancellation?.throwIfCancelled();
            } on WorkIndexCancelledException
            {
                rethrow;
            } on Object catch (error)
            {
                searchError = error;
            }
        } else if (trustSeedUpdate)
        {
            searchCandidate = seed;
        }

        if (oldRecord != null && searchError != null)
        {
            return WorkIndexResult(
                work: oldRecord.work,
                warning: '更新未完成，已保留上次作品索引：$searchError',
            );
        }

        final Work complete = _mergeWorks(<Work>[
            seed,
            initial.work,
            ?searchCandidate,
        ]);
        onProgress?.call('正在逐帖展开小说目录');
        final _NovelWorkResolution resolution = await _resolveNovelDirectories(
            complete,
            anchorTid: anchor.tid,
            initialRelations: initial.relatedThreads,
            preResolved: <int, _ThreadResolution>{anchor.tid: initial},
            forceReload: forceThreadReload,
            onProgress: onProgress,
            cancellation: cancellation,
        );
        cancellation?.throwIfCancelled();
        if (oldRecord != null &&
                resolution.error != null &&
                resolution.work.chapters.isEmpty &&
                !trustSeedUpdate)
        {
            return WorkIndexResult(
                work: oldRecord.work,
                warning: '帖子解析失败，已保留上次作品索引：${resolution.error}',
            );
        }

        final Work merged = _mergeWorks(<Work>[
            if (oldRecord != null) oldRecord.work,
            resolution.work,
        ], workId: oldRecord?.work.id ?? seed.id);
        final String canonicalKey =
                oldRecord?.canonicalKey ??
                _workAggregator.canonicalKeyForWork(searchCandidate ?? seed) ??
                _fallbackCanonicalKey(seed);
        cancellation?.throwIfCancelled();
        onProgress?.call('正在保存作品索引');
        await _indexRepository.save(canonicalKey: canonicalKey, work: merged);
        cancellation?.throwIfCancelled();
        return WorkIndexResult(
            work: merged,
            warning: searchError != null
                    ? '分卷搜索失败，已保存当前目录：$searchError'
                    : resolution.error == null
                            ? null
                            : '部分关联主题暂时无法解析，已保存现有目录',
        );
    }

    bool _hasExplicitNovelVolumes(
        Work work,
        List<ThreadLink> relations,
    )
    {
        for (final SourceThread thread in work.sourceThreads)
        {
            final StructuredTitle title = _titleNormalizer.analyze(thread.title);
            if (title.novelEdition == NovelEdition.book)
            {
                return true;
            }
            if (_titleNormalizer.detectNovelBareVolumeCandidate(thread.title) != null)
            {
                return true;
            }
        }
        for (final ThreadLink relation in relations)
        {
            final StructuredTitle title = _titleNormalizer.analyze(
                '${work.title} ${relation.label}',
            );
            if (title.novelEdition == NovelEdition.book)
            {
                return true;
            }
        }
        return false;
    }

    Work _novelThreadWork(Work work, SourceThread thread)
    {
        final Work standalone = _workAggregator
                .aggregate(<SourceThread>[thread])
                .single;
        return Work(
            id: work.id,
            kind: work.kind,
            title: work.title,
            summary: work.summary,
            author: thread.author,
            typeName: thread.typeName,
            sourceThreads: <SourceThread>[thread],
            chapters: standalone.chapters,
            directories: standalone.directories,
        );
    }

    Future<_NovelWorkResolution> _resolveNovelDirectories(
        Work work, {
        required int anchorTid,
        required List<ThreadLink> initialRelations,
        required Map<int, _ThreadResolution> preResolved,
        required bool forceReload,
        WorkIndexProgress? onProgress,
        WorkIndexCancellation? cancellation,
    }) async
    {
        final SourceThread anchor = work.sourceThreads.firstWhere(
            (SourceThread thread) => thread.tid == anchorTid,
            orElse: () => _anchorThread(work),
        );
        final Map<int, NovelBareVolumeCandidate> promotedVolumes =
                _confirmedNovelVolumeCandidates(work);
        final List<SourceThread> queue = _novelDirectorySources(
            work,
            anchor,
            promotedVolumes.keys.toSet(),
        );
        final Set<int> queuedTids = queue
                .map((SourceThread thread) => thread.tid)
                .toSet();
        final Set<int> trustedTids = <int>{...queuedTids};
        final Map<int, ThreadLink> relationHints = <int, ThreadLink>{};
        final SourceThread fallbackSource = anchor;
        for (final ThreadLink relation in initialRelations)
        {
            final int? tid = relation.tid;
            if (tid == null || !_isNovelBookRelation(work, relation))
            {
                continue;
            }
            relationHints.putIfAbsent(tid, () => relation);
            trustedTids.add(tid);
            if (queuedTids.add(tid))
            {
                queue.add(_novelRelationThread(work, fallbackSource, relation));
            }
        }

        final Map<int, SourceThread> resolvedThreads = <int, SourceThread>{};
        final Map<String, String> owners = <String, String>{};
        final Map<String, Set<int>> tidsByDirectory = <String, Set<int>>{};
        final Map<String, List<List<Chapter>>> chaptersByDirectory =
                <String, List<List<Chapter>>>{};
        final Set<int> attemptedBatchTids = <int>{};
        Object? firstError;
        int cursor = 0;
        while (cursor < queue.length)
        {
            cancellation?.throwIfCancelled();
            onProgress?.call(
                '正在逐帖展开小说目录（${cursor + 1}/${queue.length}）',
            );
            final SourceThread source = queue[cursor++];
            final _ThreadResolution threadResolution =
                    preResolved.remove(source.tid) ??
                    await _resolveThread(
                        _novelThreadWork(work, source),
                        forceReload: forceReload,
                        onProgress: onProgress,
                        cancellation: cancellation,
                    );
            cancellation?.throwIfCancelled();
            firstError ??= threadResolution.error;
            final SourceThread actual = threadResolution.sourceThread ?? source;
            final Work actualWork = _workAggregator
                    .aggregate(<SourceThread>[actual])
                    .single;
            if (!trustedTids.contains(source.tid) &&
                    !_workAggregator.matches(work, actualWork))
            {
                continue;
            }

            for (final ThreadLink relation in threadResolution.relatedThreads)
            {
                final int? tid = relation.tid;
                if (tid == null || !_isNovelBookRelation(work, relation))
                {
                    continue;
                }
                relationHints.putIfAbsent(tid, () => relation);
                trustedTids.add(tid);
                if (queuedTids.add(tid))
                {
                    queue.add(_novelRelationThread(work, actual, relation));
                }
            }

            final List<Chapter> sourceChapters = <Chapter>[
                ...threadResolution.work.chapters,
            ];
            for (final ThreadLink batchLink in threadResolution.batchThreads)
            {
                cancellation?.throwIfCancelled();
                final int? batchTid = batchLink.tid;
                final NumericChapterRange? range =
                        _titleNormalizer.detectNumericChapterRange(batchLink.label);
                if (batchTid == null ||
                        range == null ||
                        !attemptedBatchTids.add(batchTid))
                {
                    continue;
                }
                final SourceThread batchSource = _batchRelationThread(
                    work,
                    actual,
                    batchLink,
                );
                final _ThreadResolution batchResolution = await _resolveThread(
                    _novelThreadWork(work, batchSource),
                    forceReload: forceReload,
                    expandBatchThreads: false,
                    onProgress: onProgress,
                    cancellation: cancellation,
                );
                cancellation?.throwIfCancelled();
                firstError ??= batchResolution.error;
                final List<Chapter> batchChapters = _validatedRangeChapters(
                    batchResolution.work.chapters,
                    batchTid,
                    range,
                );
                if (batchChapters.isEmpty)
                {
                    sourceChapters.add(
                        Chapter(
                            id: 'forum-thread:$batchTid',
                            title: batchLink.label,
                            sourceUri: batchLink.uri,
                            sourceTid: batchTid,
                            order: range.start.toDouble(),
                        ),
                    );
                    continue;
                }

                final SourceThread batchActual =
                        batchResolution.sourceThread ?? batchSource;
                final SourceThread editionSource = _titleNormalizer
                                .analyze(batchActual.title)
                                .novelEdition !=
                            null
                        ? batchActual
                        : _titleNormalizer.analyze(actual.title).novelEdition != null
                                ? actual
                                : batchActual;
                final List<Chapter> decoratedBatchChapters =
                        _decorateNovelChapters(
                            batchChapters,
                            editionSource,
                            null,
                        );
                final Work batchActualWork = _workAggregator
                        .aggregate(<SourceThread>[batchActual])
                        .single;
                final WorkDirectory batchDirectory =
                        batchActualWork.directories.first;
                owners[batchDirectory.id] = batchDirectory.owner;
                tidsByDirectory
                        .putIfAbsent(batchDirectory.id, () => <int>{})
                        .add(batchTid);
                chaptersByDirectory
                        .putIfAbsent(
                            batchDirectory.id,
                            () => <List<Chapter>>[],
                        )
                        .add(decoratedBatchChapters);
                resolvedThreads[batchTid] = batchActual;
            }

            final ThreadLink? hint = relationHints[actual.tid];
            final List<Chapter> chapters = _decorateNovelChapters(
                sourceChapters,
                actual,
                hint,
                promotedVolume: promotedVolumes[actual.tid],
            );
            final WorkDirectory actualDirectory = actualWork.directories.first;
            final String directoryId = actualDirectory.id;
            owners[directoryId] = actualDirectory.owner;
            tidsByDirectory
                    .putIfAbsent(directoryId, () => <int>{})
                    .add(actual.tid);
            chaptersByDirectory
                    .putIfAbsent(directoryId, () => <List<Chapter>>[])
                    .add(chapters);
            resolvedThreads[actual.tid] = actual;
        }

        final List<WorkDirectory> directories = chaptersByDirectory.entries
                .map((MapEntry<String, List<List<Chapter>>> entry)
                {
                    return WorkDirectory(
                        id: entry.key,
                        owner: owners[entry.key] ?? '',
                        sourceTids: (tidsByDirectory[entry.key] ?? <int>{})
                                .toList(growable: false)
                            ..sort(),
                        chapters: _mergeChapterVersions(entry.value),
                    );
                })
                .toList(growable: true)
            ..sort(_compareWorkDirectories);
        final List<Chapter> chapters = directories.isEmpty
                ? const <Chapter>[]
                : _workAggregator.smartNovelChaptersForDirectories(directories);
        return _NovelWorkResolution(
            work: Work(
                id: work.id,
                kind: work.kind,
                title: _novelSeriesTitle(
                    work,
                    anchor,
                    initialRelations,
                ),
                summary: work.summary,
                author: directories.isEmpty ? work.author : directories.first.owner,
                typeName: work.typeName,
                sourceThreads: resolvedThreads.values.toList(growable: false),
                chapters: chapters,
                directories: directories,
            ),
            error: firstError,
        );
    }

    String _novelSeriesTitle(
        Work work,
        SourceThread anchor,
        List<ThreadLink> relations,
    )
    {
        final NovelBareVolumeCandidate? candidate =
                _titleNormalizer.detectNovelAdjacentVolumeCandidate(anchor.title);
        if (candidate == null ||
                !relations.any(
                    (ThreadLink relation) =>
                            relation.tid == anchor.tid &&
                            _isNovelBookRelation(work, relation),
                ))
        {
            return work.title;
        }
        return candidate.displayTitle;
    }

    List<SourceThread> _novelDirectorySources(
        Work work,
        SourceThread anchor,
        Set<int> promotedVolumeTids,
    )
    {
        final List<SourceThread> sources = <SourceThread>[anchor];
        for (final SourceThread thread in work.sourceThreads)
        {
            if (thread.tid == anchor.tid ||
                    _titleNormalizer.analyze(thread.title).novelEdition !=
                            NovelEdition.book &&
                            !promotedVolumeTids.contains(thread.tid))
            {
                continue;
            }
            sources.add(thread);
        }

        if (_titleNormalizer.analyze(anchor.title).novelEdition == NovelEdition.book)
        {
            final List<SourceThread> serialRoots = work.sourceThreads
                    .where((SourceThread thread)
                    {
                        if (thread.tid == anchor.tid)
                        {
                            return false;
                        }
                        final StructuredTitle title = _titleNormalizer.analyze(
                            thread.title,
                        );
                        return title.novelEdition != NovelEdition.book &&
                                !title.hasChapterMarker;
                    })
                    .toList(growable: false);
            final List<SourceThread> explicitSerialRoots = serialRoots
                    .where(
                        (SourceThread thread) => _titleNormalizer
                                .analyze(thread.title)
                                .novelEdition == NovelEdition.serial,
                    )
                    .toList(growable: false);
            final SourceThread? serialRoot = _latestNovelSource(
                explicitSerialRoots.isEmpty ? serialRoots : explicitSerialRoots,
            );
            if (serialRoot != null &&
                    sources.every((SourceThread thread) => thread.tid != serialRoot.tid))
            {
                sources.add(serialRoot);
            }
        }
        return sources;
    }

    Map<int, NovelBareVolumeCandidate> _confirmedNovelVolumeCandidates(Work work)
    {
        final Map<int, NovelBareVolumeCandidate> candidatesByTid =
                <int, NovelBareVolumeCandidate>{};
        final Map<String, Set<int>> tidsByTitleKey = <String, Set<int>>{};
        final Map<String, Set<int>> volumesByTitleKey = <String, Set<int>>{};
        final Set<String> explicitBookKeys = <String>{};
        for (final SourceThread thread in work.sourceThreads)
        {
            final StructuredTitle title = _titleNormalizer.analyze(thread.title);
            if (title.novelEdition == NovelEdition.book &&
                    title.novelTitleKey.isNotEmpty)
            {
                explicitBookKeys.add(title.novelTitleKey);
            }
            final NovelBareVolumeCandidate? candidate =
                    _titleNormalizer.detectNovelBareVolumeCandidate(thread.title) ??
                    _titleNormalizer.detectNovelAdjacentVolumeCandidate(thread.title);
            if (candidate == null)
            {
                continue;
            }
            candidatesByTid[thread.tid] = candidate;
            tidsByTitleKey
                    .putIfAbsent(candidate.titleKey, () => <int>{})
                    .add(thread.tid);
            volumesByTitleKey
                    .putIfAbsent(candidate.titleKey, () => <int>{})
                    .add(candidate.volumeNumber);
        }

        final Map<int, NovelBareVolumeCandidate> result =
                <int, NovelBareVolumeCandidate>{};
        for (final MapEntry<String, Set<int>> entry in tidsByTitleKey.entries)
        {
            if (!explicitBookKeys.contains(entry.key) &&
                    (volumesByTitleKey[entry.key]?.length ?? 0) < 2)
            {
                continue;
            }
            for (final int tid in entry.value)
            {
                result[tid] = candidatesByTid[tid]!;
            }
        }
        return result;
    }

    SourceThread? _latestNovelSource(List<SourceThread> sources)
    {
        if (sources.isEmpty)
        {
            return null;
        }
        return sources.reduce((SourceThread current, SourceThread next)
        {
            return _anchorSelector.compare(next, current) > 0 ? next : current;
        });
    }

    bool _isNovelBookRelation(Work work, ThreadLink relation)
    {
        return _titleNormalizer
                .analyze('${work.title} ${relation.label}')
                .novelEdition == NovelEdition.book;
    }

    SourceThread _novelRelationThread(
        Work work,
        SourceThread source,
        ThreadLink relation,
    )
    {
        return SourceThread(
            tid: relation.tid!,
            board: source.board,
            typeId: source.typeId,
            typeName: source.typeName,
            title: '${work.title} ${relation.label}',
            author: source.author,
            uri: relation.uri,
        );
    }

    List<Chapter> _decorateNovelChapters(
        List<Chapter> chapters,
        SourceThread source,
        ThreadLink? hint, {
        NovelBareVolumeCandidate? promotedVolume,
    })
    {
        final StructuredTitle sourceTitle = _titleNormalizer.analyze(source.title);
        final StructuredTitle? hintTitle = hint == null
                ? null
                : _titleNormalizer.analyze('${sourceTitle.novelDisplayTitle} ${hint.label}');
        final NovelEdition edition = promotedVolume != null
                ? NovelEdition.book
                : sourceTitle.novelEdition ??
                        hintTitle?.novelEdition ??
                        NovelEdition.serial;
        final String volumeTitle = edition == NovelEdition.book
                ? promotedVolume != null
                        ? '第${promotedVolume.volumeNumber}卷'
                        : sourceTitle.volumeTitle.isNotEmpty
                                ? sourceTitle.volumeTitle
                                : hintTitle?.volumeTitle.isNotEmpty == true
                                        ? hintTitle!.volumeTitle
                                        : '单行本'
                : '';
        final double? volumeOrder = edition == NovelEdition.book
                ? promotedVolume?.volumeNumber.toDouble() ??
                        sourceTitle.volumeOrder ??
                        hintTitle?.volumeOrder ??
                        1
                : null;
        return chapters.indexed.map(((int, Chapter) entry)
        {
            final Chapter chapter = entry.$2;
            final bool wholeVolume = edition == NovelEdition.book &&
                    chapters.length == 1 &&
                    chapter.sourcePid == null;
            return Chapter(
                id: chapter.id,
                title: wholeVolume ? '整卷阅读' : chapter.title,
                sourceUri: chapter.sourceUri,
                sourceTid: chapter.sourceTid,
                sourcePid: chapter.sourcePid,
                sourceEndPid: chapter.sourceEndPid,
                sourceStartBlock: chapter.sourceStartBlock,
                sourceEndBlock: chapter.sourceEndBlock,
                order: edition == NovelEdition.book
                        ? _bookChapterOrder(
                                volumeOrder!,
                                chapter.order,
                                entry.$1,
                                wholeVolume,
                            )
                        : chapter.order,
                novelEdition: edition,
                volumeTitle: volumeTitle,
                volumeOrder: volumeOrder,
            );
        }).toList(growable: false);
    }

    double _bookChapterOrder(
        double volumeOrder,
        double? chapterOrder,
        int index,
        bool wholeVolume,
    )
    {
        if (wholeVolume)
        {
            return volumeOrder * 10000;
        }
        if (chapterOrder == null)
        {
            return volumeOrder * 10000 + 7000 + index / 1000;
        }
        if (chapterOrder < 8000)
        {
            return volumeOrder * 10000 + chapterOrder;
        }
        return volumeOrder * 10000 + 8000 +
                (chapterOrder - 800000).clamp(0, 100000) / 100000;
    }

    bool _shouldUseCompleteComicPipeline(
        Work work, {
        required bool trustSeedUpdate,
    })
    {
        if (work.kind != LibraryKind.comic ||
                _longFormClassifier.isExplicitShortComic(work))
        {
            return false;
        }
        return _longFormClassifier.isExplicitLongComic(work) ||
                trustSeedUpdate &&
                        work.sourceThreads.length >= 2 &&
                        _workAggregator.hasStrongChapterMarker(work);
    }

    bool _shouldSearchCrossThread(
        Work work,
        ChapterResolutionEvidence evidence, {
        bool overrodeShort = false,
    })
    {
        if (work.kind == LibraryKind.comic)
        {
            return overrodeShort || _longFormClassifier.isExplicitLongComic(work);
        }
        return work.sourceThreads.any(
            (SourceThread thread) =>
                    _titleNormalizer.analyze(thread.title).novelEdition ==
                    NovelEdition.book,
        );
    }

    Future<_LongComicResolution> _resolveLongComicDirectories(
        Work work, {
        required bool forceReload,
        WorkIndexProgress? onProgress,
        WorkIndexCancellation? cancellation,
    }) async
    {
        cancellation?.throwIfCancelled();
        final List<WorkDirectory> directories = _directoriesForWork(work);
        final Map<int, String> ownerByTid = <int, String>{
            for (final WorkDirectory directory in directories)
                for (final int tid in directory.sourceTids) tid: directory.id,
        };
        final List<Work> resolved = <Work>[];
        final List<List<Chapter>> unattributedVersions = <List<Chapter>>[];
        Work? shortFallback;
        final int anchorTid = _anchorThread(work).tid;
        Object? firstError;
        for (int index = 0; index < directories.length; index++)
        {
            cancellation?.throwIfCancelled();
            onProgress?.call(
                '正在解析来源目录（${index + 1}/${directories.length}）',
            );
            final WorkDirectory directory = directories[index];
            final Set<int> tids = directory.sourceTids.toSet();
            final List<SourceThread> sourceThreads = work.sourceThreads
                    .where((SourceThread thread) => tids.contains(thread.tid))
                    .toList(growable: false);
            if (sourceThreads.isEmpty)
            {
                continue;
            }
            final Work directoryWork = Work(
                id: work.id,
                kind: work.kind,
                title: work.title,
                summary: work.summary,
                author: directory.owner,
                typeName: work.typeName,
                sourceThreads: sourceThreads,
                chapters: directory.chapters,
                directories: <WorkDirectory>[directory],
            );
            final _ThreadResolution resolution = await _resolveThread(
                directoryWork,
                forceReload: forceReload,
                onProgress: onProgress,
                cancellation: cancellation,
            );
            cancellation?.throwIfCancelled();
            firstError ??= resolution.error;
            if (resolution.explicitShort)
            {
                if (shortFallback == null || directory.sourceTids.contains(anchorTid))
                {
                    shortFallback = resolution.work;
                }
                continue;
            }
            final List<Chapter> matchingChapters = resolution.work.chapters
                    .where((Chapter chapter)
                    {
                        final String? knownOwner = ownerByTid[chapter.sourceTid];
                        return knownOwner == directory.id ||
                                knownOwner == null && directories.length == 1;
                    })
                    .toList(growable: false);
            if (directories.length > 1)
            {
                unattributedVersions.add(
                    resolution.work.chapters
                            .where(
                                (Chapter chapter) =>
                                        ownerByTid[chapter.sourceTid] == null,
                            )
                            .toList(growable: false),
                );
            }
            final List<int> matchingSourceTids = <int>{
                ...directory.sourceTids,
                ...matchingChapters.map((Chapter chapter) => chapter.sourceTid),
            }.toList(growable: true)
                ..sort();
            final Work filtered = Work(
                id: resolution.work.id,
                kind: resolution.work.kind,
                title: resolution.work.title,
                summary: resolution.work.summary,
                author: directory.owner,
                typeName: resolution.work.typeName,
                sourceThreads: resolution.work.sourceThreads,
                chapters: matchingChapters,
                directories: <WorkDirectory>[
                    WorkDirectory(
                        id: directory.id,
                        owner: directory.owner,
                        sourceTids: matchingSourceTids,
                        chapters: matchingChapters,
                    ),
                ],
            );
            resolved.add(_mergeWorks(<Work>[directoryWork, filtered]));
        }
        if (unattributedVersions.any((List<Chapter> value) => value.isNotEmpty))
        {
            final List<Chapter> chapters = _mergeChapterVersions(
                unattributedVersions,
            );
            final WorkDirectory directory = WorkDirectory(
                id: 'owner:unattributed',
                owner: '未归属来源',
                sourceTids: chapters
                        .map((Chapter chapter) => chapter.sourceTid)
                        .toSet()
                        .toList(growable: false),
                chapters: chapters,
            );
            resolved.add(
                Work(
                    id: work.id,
                    kind: work.kind,
                    title: work.title,
                    summary: work.summary,
                    author: directory.owner,
                    typeName: work.typeName,
                    sourceThreads: work.sourceThreads,
                    chapters: chapters,
                    directories: <WorkDirectory>[directory],
                ),
            );
        }
        if (resolved.isEmpty && shortFallback != null)
        {
            return _LongComicResolution(
                work: shortFallback,
                error: firstError,
                explicitShort: true,
            );
        }
        return _LongComicResolution(
            work: resolved.isEmpty
                    ? work
                    : _mergeWorks(resolved, workId: work.id),
            error: firstError,
        );
    }

    Future<_ThreadResolution> _resolveThread(
        Work work, {
        required bool forceReload,
        bool expandBatchThreads = true,
        WorkIndexProgress? onProgress,
        WorkIndexCancellation? cancellation,
    }) async
    {
        cancellation?.throwIfCancelled();
        try
        {
            final SourceThread anchor = _anchorThread(work);
            final page = await _libraryRepository.loadDirectoryThread(
                anchor,
                forceReload: forceReload,
                onPageProgress: (int completed, int total)
                {
                    onProgress?.call(
                        total == 1
                                ? '正在解析首楼目录（1/1）'
                                : '正在加载楼主分页（$completed/$total）',
                    );
                },
            );
            cancellation?.throwIfCancelled();
            final SourceThread pageSource = _withThreadPage(anchor, page);
            final Work classifiedWork = _withAnchorSource(
                work,
                pageSource,
            );
            final List<ThreadLink> tagDirectoryLinks = <ThreadLink>[];
            Object? tagDirectoryError;
            final Set<String> directoryUris = page.posts
                    .where((SourcePost post) => post.isOriginalPoster)
                    .expand((SourcePost post) => post.links)
                    .where((ThreadLink link) => link.kind == ThreadLinkKind.directory)
                    .map((ThreadLink link) => link.uri.toString())
                    .toSet();
            for (final String value in directoryUris)
            {
                cancellation?.throwIfCancelled();
                try
                {
                    tagDirectoryLinks.addAll(
                        await _libraryRepository.loadTagDirectory(
                            Uri.parse(value),
                            forceReload: forceReload,
                        ),
                    );
                    cancellation?.throwIfCancelled();
                } on WorkIndexCancelledException
                {
                    rethrow;
                } on Object catch (error)
                {
                    tagDirectoryError ??= error;
                }
            }
            final ChapterResolver chapterResolver = _chapterResolver;
            final ChapterResolution resolution = await Isolate.run(
                _ChapterResolutionTask(
                    chapterResolver,
                    classifiedWork,
                    page,
                    tagDirectoryLinks,
                ).call,
                debugName: 'x300-chapter-resolver',
            );
            cancellation?.throwIfCancelled();
            final bool explicitShort =
                    _longFormClassifier.isExplicitShortComic(classifiedWork);
            final bool overrodeShort =
                    explicitShort &&
                    _chapterResolver.hasStrongComicDirectoryEvidence(
                        classifiedWork,
                        resolution,
                    );
            if (explicitShort && !overrodeShort)
            {
                return _ThreadResolution(
                    work: _singleThreadWork(classifiedWork),
                    evidence: ChapterResolutionEvidence.none,
                    explicitShort: true,
                    sourceThread: pageSource,
                    error: tagDirectoryError,
                );
            }
            Work resolvedWork = _replaceChapters(
                classifiedWork,
                resolution.chapters,
            );
            Object? resolutionError = tagDirectoryError;
            if (expandBatchThreads &&
                    classifiedWork.kind == LibraryKind.comic &&
                    resolution.batchThreads.isNotEmpty)
            {
                final _BatchExpansion expansion = await _expandComicBatchThreads(
                    resolvedWork,
                    pageSource,
                    resolution.batchThreads,
                    forceReload: forceReload,
                    onProgress: onProgress,
                    cancellation: cancellation,
                );
                resolvedWork = expansion.work;
                resolutionError ??= expansion.error;
            }
            return _ThreadResolution(
                work: resolvedWork,
                evidence: resolution.evidence,
                relatedThreads: resolution.relatedThreads,
                batchThreads: resolution.batchThreads,
                sourceThread: pageSource,
                overrodeShort: overrodeShort,
                error: resolutionError,
            );
        } on WorkIndexCancelledException
        {
            rethrow;
        } on Object catch (error)
        {
            return _ThreadResolution(
                work: work,
                evidence: ChapterResolutionEvidence.none,
                sourceThread: _anchorThread(work),
                error: error,
            );
        }
    }

    Future<_BatchExpansion> _expandComicBatchThreads(
        Work work,
        SourceThread source,
        List<ThreadLink> links, {
        required bool forceReload,
        WorkIndexProgress? onProgress,
        WorkIndexCancellation? cancellation,
    }) async
    {
        Work current = work;
        Object? firstError;
        final Set<int> expandedTids = <int>{};
        for (final ThreadLink link in links)
        {
            cancellation?.throwIfCancelled();
            final int? tid = link.tid;
            final NumericChapterRange? range =
                    _titleNormalizer.detectNumericChapterRange(link.label);
            if (tid == null || range == null || !expandedTids.add(tid))
            {
                continue;
            }
            final SourceThread target = _batchRelationThread(current, source, link);
            final Work targetSeed = _workAggregator
                    .aggregate(<SourceThread>[target])
                    .single;
            final _ThreadResolution resolution = await _resolveThread(
                targetSeed,
                forceReload: forceReload,
                expandBatchThreads: false,
                onProgress: onProgress,
                cancellation: cancellation,
            );
            cancellation?.throwIfCancelled();
            firstError ??= resolution.error;
            final List<Chapter> chapters = _validatedRangeChapters(
                resolution.work.chapters,
                tid,
                range,
            );
            if (chapters.isEmpty)
            {
                continue;
            }

            final SourceThread actual = resolution.sourceThread ?? target;
            final Work ownerWork = _workAggregator
                    .aggregate(<SourceThread>[actual])
                    .single;
            final WorkDirectory ownerDirectory = ownerWork.directories.first;
            current = _mergeWorks(<Work>[
                _withoutCoarseBatchChapter(current, tid),
                Work(
                    id: current.id,
                    kind: current.kind,
                    title: current.title,
                    summary: current.summary,
                    author: ownerDirectory.owner,
                    typeName: current.typeName,
                    sourceThreads: <SourceThread>[actual],
                    chapters: chapters,
                    directories: <WorkDirectory>[
                        WorkDirectory(
                            id: ownerDirectory.id,
                            owner: ownerDirectory.owner,
                            sourceTids: <int>[tid],
                            chapters: chapters,
                        ),
                    ],
                ),
            ], workId: current.id);
        }
        return _BatchExpansion(work: current, error: firstError);
    }

    SourceThread _batchRelationThread(
        Work work,
        SourceThread source,
        ThreadLink relation,
    )
    {
        return SourceThread(
            tid: relation.tid!,
            board: source.board,
            typeId: source.typeId,
            typeName: source.typeName,
            title: '${work.title} ${relation.label}',
            author: source.author,
            uri: relation.uri,
        );
    }

    List<Chapter> _validatedRangeChapters(
        List<Chapter> chapters,
        int tid,
        NumericChapterRange range,
    )
    {
        final Map<int, Chapter> chaptersByNumber = <int, Chapter>{};
        for (final Chapter chapter in chapters)
        {
            if (chapter.sourceTid != tid || chapter.sourcePid == null)
            {
                continue;
            }
            final double? order = _titleNormalizer.analyze(chapter.title).chapterOrder;
            if (order == null || order != order.roundToDouble())
            {
                continue;
            }
            final int number = order.toInt();
            if (number >= range.start && number <= range.end)
            {
                chaptersByNumber.putIfAbsent(number, () => chapter);
            }
        }
        for (int number = range.start; number <= range.end; number++)
        {
            if (!chaptersByNumber.containsKey(number))
            {
                return const <Chapter>[];
            }
        }
        return <Chapter>[
            for (int number = range.start; number <= range.end; number++)
                chaptersByNumber[number]!,
        ];
    }

    Work _withoutCoarseBatchChapter(Work work, int tid)
    {
        bool keep(Chapter chapter)
        {
            return chapter.sourceTid != tid || chapter.sourcePid != null;
        }

        final List<WorkDirectory> directories = work.directories
                .map((WorkDirectory directory)
                {
                    return WorkDirectory(
                        id: directory.id,
                        owner: directory.owner,
                        sourceTids: directory.sourceTids,
                        chapters: directory.chapters.where(keep).toList(growable: false),
                    );
                })
                .toList(growable: false);
        return Work(
            id: work.id,
            kind: work.kind,
            title: work.title,
            summary: work.summary,
            author: work.author,
            typeName: work.typeName,
            sourceThreads: work.sourceThreads,
            chapters: work.chapters.where(keep).toList(growable: false),
            directories: directories,
        );
    }

    Work _withAnchorSource(Work work, SourceThread source)
    {
        return Work(
            id: work.id,
            kind: work.kind,
            title: work.title,
            summary: work.summary,
            author: work.author,
            typeName: source.typeName.isEmpty ? work.typeName : source.typeName,
            sourceThreads: work.sourceThreads
                    .map((SourceThread thread)
                    {
                        return thread.tid == source.tid
                                ? source
                                : thread;
                    })
                    .toList(growable: false),
            chapters: work.chapters,
            directories: work.directories,
        );
    }

    SourceThread _withThreadPage(
        SourceThread thread,
        ForumThreadPage page,
    )
    {
        final SourcePost? originalPost = page.originalPost;
        return SourceThread(
            tid: thread.tid,
            board: thread.board,
            typeId: thread.typeId,
            typeName: page.typeName.isEmpty ? thread.typeName : page.typeName,
            title: page.title.isEmpty ? thread.title : page.title,
            summary: thread.summary,
            author: originalPost?.author.trim().isNotEmpty == true
                    ? originalPost!.author
                    : thread.author,
            avatarUri: thread.avatarUri,
            timeLabel: thread.timeLabel,
            postedAt: thread.postedAt,
            views: thread.views,
            replies: thread.replies,
            pinned: thread.pinned,
            administrative: thread.administrative,
            uri: page.uri,
        );
    }

    Work _singleThreadWork(Work work)
    {
        final SourceThread anchor = _anchorThread(work);
        final SourceThread classifiedAnchor = work.typeName.isEmpty
                ? anchor
                : _withTypeName(anchor, work.typeName);
        return _workAggregator.aggregate(<SourceThread>[classifiedAnchor]).single;
    }

    SourceThread _withTypeName(SourceThread thread, String typeName)
    {
        return SourceThread(
            tid: thread.tid,
            board: thread.board,
            typeId: thread.typeId,
            typeName: typeName,
            title: thread.title,
            summary: thread.summary,
            author: thread.author,
            avatarUri: thread.avatarUri,
            timeLabel: thread.timeLabel,
            postedAt: thread.postedAt,
            views: thread.views,
            replies: thread.replies,
            pinned: thread.pinned,
            administrative: thread.administrative,
            uri: thread.uri,
        );
    }

    Future<Work?> _searchCompleteWork(
        Work seed, {
        WorkIndexProgress? onProgress,
        WorkIndexCancellation? cancellation,
    }) async
    {
        await _waitForSearchSlot(onProgress, cancellation);
        cancellation?.throwIfCancelled();
        bool accepted = false;
        try
        {
            final SourceThread anchor = _anchorThread(seed);
            final StructuredTitle structuredTitle = _titleNormalizer.analyze(
                anchor.title,
            );
            final NovelBareVolumeCandidate? bareVolume = seed.kind ==
                            LibraryKind.novel
                    ? _titleNormalizer.detectNovelBareVolumeCandidate(anchor.title)
                    : null;
            final String keyword = seed.kind == LibraryKind.novel
                    ? bareVolume?.displayTitle ?? structuredTitle.novelDisplayTitle
                    : structuredTitle.displayTitle;
            onProgress?.call('正在搜索完整作品目录');
            ForumSearchPage cursor = await _searchRepository.search(
                keyword: keyword,
                kind: seed.kind,
            );
            cancellation?.throwIfCancelled();
            _searchCooldown.accepted();
            accepted = true;
            final List<SourceThread> sourceThreads = <SourceThread>[
                ...cursor.sourceThreads,
            ];
            final Set<int> knownTids = sourceThreads
                    .map((SourceThread thread) => thread.tid)
                    .toSet();
            while (cursor.hasMore)
            {
                cancellation?.throwIfCancelled();
                onProgress?.call(
                    '正在补全搜索目录（${cursor.currentPage}/${cursor.totalPages}）',
                );
                cursor = await _searchRepository.loadNext(cursor);
                cancellation?.throwIfCancelled();
                sourceThreads.addAll(
                    cursor.sourceThreads.where(
                        (SourceThread thread) => knownTids.add(thread.tid),
                    ),
                );
            }
            final List<Work> works = _searchRepository.aggregateThreads(
                sourceThreads,
            );
            if (seed.kind != LibraryKind.novel)
            {
                return findMatchingWork(seed, works);
            }
            final List<Work> matches = works
                    .where((Work candidate) => _workAggregator.matches(seed, candidate))
                    .toList(growable: false);
            if (matches.isEmpty)
            {
                return null;
            }
            return _mergeWorks(<Work>[seed, ...matches], workId: seed.id);
        } on Object
        {
            if (!accepted)
            {
                _searchCooldown.failed();
            }
            rethrow;
        }
    }

    Future<void> _waitForSearchSlot(
        WorkIndexProgress? onProgress,
        WorkIndexCancellation? cancellation,
    ) async
    {
        while (!_searchCooldown.tryBegin())
        {
            cancellation?.throwIfCancelled();
            final String message = _searchCooldown.inFlight
                    ? '正在等待当前论坛搜索完成'
                    : '论坛搜索冷却中，还需 ${_searchCooldown.remainingSeconds} 秒';
            onProgress?.call(message);
            await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        cancellation?.throwIfCancelled();
    }

    SourceThread _anchorThread(Work work)
    {
        return _anchorSelector.select(work);
    }

    Work _replaceChapters(Work work, List<Chapter> chapters)
    {
        final List<WorkDirectory> directories = _replaceDirectoryChapters(
            work,
            chapters,
        );
        return Work(
            id: work.id,
            kind: work.kind,
            title: work.title,
            summary: work.summary,
            author: work.author,
            typeName: work.typeName,
            sourceThreads: work.sourceThreads,
            chapters: work.kind == LibraryKind.novel
                    ? _workAggregator.smartNovelChaptersForDirectories(directories)
                    : _workAggregator.smartChaptersForDirectories(directories),
            directories: directories,
        );
    }

    List<WorkDirectory> _replaceDirectoryChapters(
        Work work,
        List<Chapter> chapters,
    )
    {
        final List<WorkDirectory> directories = <WorkDirectory>[
            ..._directoriesForWork(work),
        ];
        final int anchorTid = _anchorThread(work).tid;
        int index = directories.indexWhere(
            (WorkDirectory directory) => directory.sourceTids.contains(anchorTid),
        );
        if (index < 0)
        {
            index = 0;
        }
        final WorkDirectory current = directories[index];
        directories[index] = WorkDirectory(
            id: current.id,
            owner: current.owner,
            sourceTids: <int>{
                ...current.sourceTids,
                ...chapters.map((Chapter chapter) => chapter.sourceTid),
            }.toList(growable: false),
            chapters: chapters,
        );
        directories.sort(_compareWorkDirectories);
        return directories;
    }

    Work _mergeWorks(List<Work> works, {String? workId})
    {
        final Work preferred = works.last;
        final Map<int, SourceThread> sourceThreads = <int, SourceThread>{};
        final Map<String, List<WorkDirectory>> directoryVersions =
                <String, List<WorkDirectory>>{};
        for (final Work work in works)
        {
            for (final SourceThread thread in work.sourceThreads)
            {
                final SourceThread? current = sourceThreads[thread.tid];
                sourceThreads[thread.tid] = current == null
                        ? thread
                        : _preferSourceThread(current, thread);
            }
            for (final WorkDirectory directory in _directoriesForWork(work))
            {
                directoryVersions
                        .putIfAbsent(directory.id, () => <WorkDirectory>[])
                        .add(directory);
            }
        }
        final List<WorkDirectory> directories =
                directoryVersions.values.map(_mergeDirectories).toList(growable: true)
                    ..sort(_compareWorkDirectories);
        final List<Chapter> mergedChapters = directories.isEmpty
                ? _mergeChapterVersions(
                        works.map((Work work) => work.chapters).toList(growable: false),
                    )
                : preferred.kind == LibraryKind.novel
                        ? _workAggregator.smartNovelChaptersForDirectories(
                            directories,
                        )
                        : _workAggregator.smartChaptersForDirectories(directories);
        return Work(
            id: workId ?? preferred.id,
            kind: preferred.kind,
            title: _latestText(works.map((Work work) => work.title)),
            summary: _latestText(works.map((Work work) => work.summary)),
            author: directories.isEmpty
                    ? _latestText(works.map((Work work) => work.author))
                    : directories.first.owner,
            typeName: _latestText(works.map((Work work) => work.typeName)),
            sourceThreads: sourceThreads.values.toList(growable: false),
            chapters: mergedChapters,
            directories: directories,
        );
    }

    WorkDirectory _mergeDirectories(List<WorkDirectory> versions)
    {
        final Set<int> sourceTids = <int>{};
        for (final WorkDirectory directory in versions)
        {
            sourceTids.addAll(directory.sourceTids);
        }
        return WorkDirectory(
            id: versions.last.id,
            owner: _latestText(
                versions.map((WorkDirectory directory) => directory.owner),
            ),
            sourceTids: sourceTids.toList(growable: false)..sort(),
            chapters: _mergeChapterVersions(
                versions
                        .map((WorkDirectory directory) => directory.chapters)
                        .toList(growable: false),
            ),
        );
    }

    List<Chapter> _mergeChapterVersions(List<List<Chapter>> versions)
    {
        final Map<String, Chapter> chapters = <String, Chapter>{};
        final Map<double, Set<String>> numericChapterKeys = <double, Set<String>>{};
        for (final List<Chapter> version in versions)
        {
            final Set<double> currentOrders = version
                    .where(
                        (Chapter chapter) =>
                                chapter.sourcePid == null &&
                                chapter.order != null &&
                                chapter.order! < 800000,
                    )
                    .map((Chapter chapter) => chapter.order!)
                    .toSet();
            for (final double order in currentOrders)
            {
                final Set<String>? previousKeys = numericChapterKeys[order];
                if (previousKeys != null)
                {
                    for (final String key in previousKeys)
                    {
                        chapters.remove(key);
                    }
                }
                numericChapterKeys[order] = <String>{};
            }
            for (final Chapter chapter in version)
            {
                final String key = _chapterKey(chapter);
                final double? order = chapter.order;
                if (chapter.sourcePid == null && order != null && order < 800000)
                {
                    numericChapterKeys[order]!.add(key);
                }
                chapters[key] = chapter;
            }
        }
        final Set<int> detailedTids = chapters.values
                .where((Chapter chapter) => chapter.sourcePid != null)
                .map((Chapter chapter) => chapter.sourceTid)
                .toSet();
        final List<Chapter> mergedChapters =
                chapters.values
                        .where(
                            (Chapter chapter) =>
                                    chapter.sourcePid != null ||
                                    !detailedTids.contains(chapter.sourceTid),
                        )
                        .toList(growable: true)
                    ..sort(_compareChapters);
        return mergedChapters;
    }

    List<WorkDirectory> _directoriesForWork(Work work)
    {
        if (work.directories.isNotEmpty)
        {
            return work.directories;
        }
        return <WorkDirectory>[
            WorkDirectory(
                id: _fallbackDirectoryId(work.author),
                owner: work.author,
                sourceTids: <int>{
                    ...work.sourceThreads.map((SourceThread thread) => thread.tid),
                    ...work.chapters.map((Chapter chapter) => chapter.sourceTid),
                }.toList(growable: false),
                chapters: work.chapters,
            ),
        ];
    }

    String _fallbackDirectoryId(String owner)
    {
        final String key = owner.trim().toLowerCase();
        return key.isEmpty ? 'owner:unknown' : 'legacy-owner:$key';
    }

    int _compareWorkDirectories(WorkDirectory left, WorkDirectory right)
    {
        if (left.id == 'owner:unattributed' || right.id == 'owner:unattributed')
        {
            if (left.id != right.id)
            {
                return left.id == 'owner:unattributed' ? 1 : -1;
            }
        }
        final List<double> leftMain = left.chapters
                .map((Chapter chapter) => chapter.order)
                .whereType<double>()
                .where((double order) => order < 800000)
                .toList(growable: false);
        final List<double> rightMain = right.chapters
                .map((Chapter chapter) => chapter.order)
                .whereType<double>()
                .where((double order) => order < 800000)
                .toList(growable: false);
        int result = rightMain.length.compareTo(leftMain.length);
        if (result != 0)
        {
            return result;
        }
        final double leftLatest = leftMain.isEmpty
                ? double.negativeInfinity
                : leftMain.reduce((double a, double b) => a > b ? a : b);
        final double rightLatest = rightMain.isEmpty
                ? double.negativeInfinity
                : rightMain.reduce((double a, double b) => a > b ? a : b);
        result = rightLatest.compareTo(leftLatest);
        if (result != 0)
        {
            return result;
        }
        result = right.chapters.length.compareTo(left.chapters.length);
        return result != 0 ? result : left.owner.compareTo(right.owner);
    }

    SourceThread _preferSourceThread(SourceThread current, SourceThread next)
    {
        if (current.typeId != null && next.typeId == null)
        {
            return current;
        }
        if (current.typeName.isNotEmpty && next.typeName.isEmpty)
        {
            return current;
        }
        return next;
    }

    int _compareChapters(Chapter left, Chapter right)
    {
        final double? leftOrder = left.order;
        final double? rightOrder = right.order;
        if (leftOrder != null && rightOrder != null)
        {
            final int result = leftOrder.compareTo(rightOrder);
            if (result != 0)
            {
                return result;
            }
        } else if (leftOrder != null)
        {
            return -1;
        } else if (rightOrder != null)
        {
            return 1;
        }
        final int tidResult = left.sourceTid.compareTo(right.sourceTid);
        if (tidResult != 0)
        {
            return tidResult;
        }
        return (left.sourcePid ?? 0).compareTo(right.sourcePid ?? 0);
    }

    String _latestText(Iterable<String> values)
    {
        for (final String value in values.toList(growable: false).reversed)
        {
            if (value.trim().isNotEmpty)
            {
                return value;
            }
        }
        return '';
    }

    WorkIndexRecord _decorateRecord(WorkIndexRecord record, Work runtimeWork)
    {
        final Map<int, SourceThread> runtimeThreads = <int, SourceThread>{
            for (final SourceThread thread in runtimeWork.sourceThreads)
                thread.tid: thread,
        };
        final Work indexedWork = record.work;
        return WorkIndexRecord(
            canonicalKey: record.canonicalKey,
            updatedAt: record.updatedAt,
            work: Work(
                id: indexedWork.id,
                kind: indexedWork.kind,
                title: _latestText(<String>[indexedWork.title, runtimeWork.title]),
                summary: _latestText(<String>[
                    indexedWork.summary,
                    runtimeWork.summary,
                ]),
                author: _latestText(<String>[indexedWork.author, runtimeWork.author]),
                typeName: _latestText(<String>[
                    indexedWork.typeName,
                    runtimeWork.typeName,
                ]),
                sourceThreads: indexedWork.sourceThreads
                        .map((SourceThread thread) => runtimeThreads[thread.tid] ?? thread)
                        .toList(growable: false),
                chapters: indexedWork.chapters,
                directories: indexedWork.directories,
            ),
        );
    }

    Set<int> _sourceTids(Work work)
    {
        return <int>{
            ...work.sourceThreads.map((SourceThread thread) => thread.tid),
            ...work.chapters.map((Chapter chapter) => chapter.sourceTid),
            ...work.directories.expand(
                (WorkDirectory directory) => directory.sourceTids,
            ),
            ...work.directories.expand(
                (WorkDirectory directory) =>
                        directory.chapters.map((Chapter chapter) => chapter.sourceTid),
            ),
        };
    }

    String _chapterKey(Chapter chapter)
    {
        final String blockRange = chapter.sourceStartBlock == null &&
                chapter.sourceEndBlock == null
                ? ''
                : ':${chapter.sourceStartBlock ?? 0}:'
                        '${chapter.sourceEndBlock ?? -1}';
        return '${chapter.sourceTid}:${chapter.sourcePid ?? 0}$blockRange';
    }

    String _taskKey(Work work)
    {
        return _workAggregator.canonicalKeyForWork(work) ?? work.id;
    }

    String _cancellationTaskSuffix(WorkIndexCancellation? cancellation)
    {
        return cancellation == null
                ? ''
                : '|cancellation=${identityHashCode(cancellation)}';
    }

    String _fallbackCanonicalKey(Work work)
    {
        return '${work.kind.name}|tid=${work.sourceThreads.first.tid}';
    }
}

class _ChapterResolutionTask
{
    const _ChapterResolutionTask(
        this.resolver,
        this.work,
        this.page,
        this.tagDirectoryLinks,
    );

    final ChapterResolver resolver;
    final Work work;
    final ForumThreadPage page;
    final List<ThreadLink> tagDirectoryLinks;

    ChapterResolution call()
    {
        return resolver.resolveWithEvidence(
            work,
            page,
            tagDirectoryLinks: tagDirectoryLinks,
        );
    }
}

class _ThreadResolution
{
    const _ThreadResolution({
        required this.work,
        required this.evidence,
        this.explicitShort = false,
        this.overrodeShort = false,
        this.relatedThreads = const <ThreadLink>[],
        this.batchThreads = const <ThreadLink>[],
        this.sourceThread,
        this.error,
    });

    final Work work;
    final ChapterResolutionEvidence evidence;
    final bool explicitShort;
    final bool overrodeShort;
    final List<ThreadLink> relatedThreads;
    final List<ThreadLink> batchThreads;
    final SourceThread? sourceThread;
    final Object? error;
}

class _BatchExpansion
{
    const _BatchExpansion({required this.work, this.error});

    final Work work;
    final Object? error;
}

class _NovelWorkResolution
{
    const _NovelWorkResolution({required this.work, this.error});

    final Work work;
    final Object? error;
}

class _LongComicResolution
{
    const _LongComicResolution({
        required this.work,
        this.explicitShort = false,
        this.error,
    });

    final Work work;
    final bool explicitShort;
    final Object? error;
}
