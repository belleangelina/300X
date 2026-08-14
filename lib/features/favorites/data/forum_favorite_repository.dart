import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/favorites/data/favorite_work_policy.dart';
import 'package:x300/features/favorites/data/forum_favorite_parser.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';
import 'package:x300/features/library/data/work_aggregator.dart';
import 'package:x300/features/library/domain/library_models.dart';

final Provider<ForumFavoriteRepository> forumFavoriteRepositoryProvider =
    Provider<ForumFavoriteRepository>(
        (Ref ref) => ForumFavoriteRepository(
            ref.watch(forumClientProvider),
            ref.watch(authControllerProvider).value?.userId ?? 0,
            ForumSubmissionTombstoneRepository(
                ref.watch(appDatabaseProvider),
            ),
        ),
    );

class ForumFavoriteReadbackResult
{
    const ForumFavoriteReadbackResult({
        required this.records,
        required this.trustedOutcomeConfirmed,
    });

    final List<CloudFavoriteRecord> records;
    final bool trustedOutcomeConfirmed;
}

class ForumFavoriteRepository
{
    ForumFavoriteRepository(
        this._client,
        this._userId,
        this._tombstones, [
        this._parser = const ForumFavoriteParser(),
        this._aggregator = const WorkAggregator(),
        this._workPolicy = const FavoriteWorkPolicy(),
    ]);

    final ForumClient _client;
    final int _userId;
    final ForumSubmissionTombstoneRepository _tombstones;
    final ForumFavoriteParser _parser;
    final WorkAggregator _aggregator;
    final FavoriteWorkPolicy _workPolicy;

    Future<CloudFavoritePage> loadInitial()
    {
        return _withActiveAccount(() => _loadPage(_favoriteListUri()));
    }

    Future<CloudFavoritePage> loadNext(CloudFavoritePage cursor)
    {
        return _withActiveAccount(() async
        {
            final Uri? uri = cursor.nextPageUri;
            if (uri == null)
            {
                return cursor;
            }
            return _loadPage(uri);
        });
    }

    List<FavoriteWork> aggregateEntries(List<CloudFavoriteEntry> entries)
    {
        final List<Work> works = _aggregator.aggregate(
            entries
                .map((CloudFavoriteEntry value) => value.sourceThread)
                .toList(growable: false),
        );
        final Map<int, CloudFavoriteRecord> recordsByTid =
            <int, CloudFavoriteRecord>{
                for (final CloudFavoriteEntry entry in entries)
                    entry.sourceThread.tid: entry.record,
            };
        return works.map((Work work)
        {
            final List<CloudFavoriteRecord> records = work.sourceThreads
                .map(
                    (SourceThread thread) => recordsByTid[thread.tid],
                )
                .whereType<CloudFavoriteRecord>()
                .toList(growable: false);
            return FavoriteWork(work: work, records: records);
        }).toList(growable: false);
    }

    Future<List<CloudFavoriteRecord>> findForWork(Work work)
    {
        return _withActiveAccount(() => _findForWork(work));
    }

    Future<List<CloudFavoriteRecord>> _findForWork(Work work) async
    {
        final Set<int> threadIds = _workPolicy.sourceTids(work);
        final List<CloudFavoriteRecord> records = await _loadAllRecords();
        final List<CloudFavoriteRecord> matching = records
            .where(
                (CloudFavoriteRecord value) =>
                    threadIds.contains(value.threadId),
            )
            .toList(growable: false);
        await _reconcileFavoriteTombstones(records);
        return matching;
    }

    Future<List<CloudFavoriteRecord>> addWork(Work work)
    {
        return _withActiveAccount(() => _addWork(work));
    }

    Future<List<CloudFavoriteRecord>> _addWork(Work work) async
    {
        final SourceThread target = _workPolicy.anchor(work);
        final Uri dialogUri = ForumClient.baseUri.resolve(
            'home.php?mod=spacecp&ac=favorite&type=thread&'
            'id=${target.tid}&mobile=2',
        );
        final ForumActionRequest request = _favoriteRequest(
            kind: ForumActionKind.favoriteThread,
            threadId: target.tid,
            entryUri: dialogUri,
        );
        final String context = _favoriteContext();
        final List<CloudFavoriteRecord> existing = await _findForWork(work);
        if (existing.isNotEmpty)
        {
            return existing;
        }
        await _throwIfUnresolved(request, context);
        final Response<String> dialogResponse = await _client.getText(
            dialogUri,
            referer: target.uri.toString(),
        );
        final ForumFavoriteForm form = _parser.parseActionForm(
            dialogResponse.data ?? '',
            dialogResponse.realUri,
            expectedUserId: _userId,
            expectedThreadId: target.tid,
        );
        final String attemptId = await _claim(request, context);
        try
        {
            final Response<String> response = await _client.postForm(
                form.actionUri,
                fields: form.fields,
                referer: dialogResponse.realUri.toString(),
            );
            _parser.ensureSubmissionSession(
                response.data ?? '',
                response.realUri,
                expectedUserId: _userId,
                expectedThreadId: target.tid,
            );
            final List<CloudFavoriteRecord> confirmed =
                await _findForWork(work);
            if (confirmed.isEmpty)
            {
                throw const ForumParseException('论坛未确认收藏成功');
            }
            return confirmed;
        }
        on Object
        {
            throw _unknown(request, context, attemptId);
        }
    }

    Future<void> removeWork(
        Work work,
        List<CloudFavoriteRecord> records,
    )
    {
        return _withActiveAccount(() => _removeWork(work, records));
    }

    Future<void> acknowledgeUnresolved(
        ForumUnresolvedSubmission submission,
    )
    {
        return _withActiveAccount(() async
        {
            _validateUnresolved(submission);
            if (!await _tombstones.acknowledge(submission))
            {
                throw StateError('收藏提交封存记录已变化，请先重新回读');
            }
        });
    }

    Future<ForumFavoriteReadbackResult> readbackUnresolved(
        ForumUnresolvedSubmission submission,
        Work work,
    )
    {
        return _withActiveAccount(() async
        {
            _validateUnresolved(submission, work: work);
            final Set<int> workThreadIds = _workPolicy.sourceTids(work);
            final List<CloudFavoriteRecord> allRecords =
                await _loadAllRecords();
            final List<CloudFavoriteRecord> matching = allRecords
                .where(
                    (CloudFavoriteRecord value) =>
                        workThreadIds.contains(value.threadId),
                )
                .toList(growable: false);
            final bool confirmed = switch (submission.request.kind)
            {
                ForumActionKind.favoriteThread => matching.any(
                    (CloudFavoriteRecord value) =>
                        value.threadId == submission.request.target.threadId,
                ),
                ForumActionKind.removeFavorite => !allRecords.any(
                    (CloudFavoriteRecord value) =>
                        value.favoriteId ==
                            submission.request.target.favoriteId,
                ),
                _ => false,
            };
            if (confirmed && !await _tombstones.acknowledge(submission))
            {
                final ForumUnresolvedSubmission? current =
                    await _tombstones.find(
                        userId: _userId,
                        request: submission.request,
                        readback: submission.readback,
                        draftContext: submission.draftContext,
                    );
                if (current != null)
                {
                    throw StateError('收藏提交封存记录已变化，请重新回读');
                }
            }
            return ForumFavoriteReadbackResult(
                records: matching,
                trustedOutcomeConfirmed: confirmed,
            );
        });
    }

    Future<void> _removeWork(
        Work work,
        List<CloudFavoriteRecord> records,
    ) async
    {
        final String context = _favoriteContext();
        final Set<int> allowedThreadIds = _workPolicy.sourceTids(work);
        final Map<int, CloudFavoriteRecord> knownRecords =
            <int, CloudFavoriteRecord>{
                for (final CloudFavoriteRecord record
                    in await _findForWork(work))
                    record.favoriteId: record,
            };
        final List<CloudFavoriteRecord> targets = knownRecords.values
            .where(
                (CloudFavoriteRecord value) =>
                    allowedThreadIds.contains(value.threadId),
            )
            .toList(growable: false);
        if (targets.isEmpty)
        {
            return;
        }
        for (final CloudFavoriteRecord record in targets)
        {
            final ForumActionRequest request = _favoriteRequest(
                kind: ForumActionKind.removeFavorite,
                threadId: record.threadId,
                favoriteId: record.favoriteId,
                entryUri: record.deleteDialogUri,
            );
            await _throwIfUnresolved(request, context);
            final Response<String> dialogResponse = await _client.getText(
                record.deleteDialogUri,
                referer: _favoriteListUri().toString(),
            );
            final ForumFavoriteForm form = _parser.parseActionForm(
                dialogResponse.data ?? '',
                dialogResponse.realUri,
                expectedUserId: _userId,
                expectedThreadId: record.threadId,
                expectedFavoriteId: record.favoriteId,
            );
            final String attemptId = await _claim(request, context);
            try
            {
                final Response<String> response = await _client.postForm(
                    form.actionUri,
                    fields: form.fields,
                    referer: dialogResponse.realUri.toString(),
                );
                _parser.ensureSubmissionSession(
                    response.data ?? '',
                    response.realUri,
                    expectedUserId: _userId,
                    expectedThreadId: record.threadId,
                    expectedFavoriteId: record.favoriteId,
                );
                final Set<int> remainingIds = (await _findForWork(work))
                    .map((CloudFavoriteRecord value) => value.favoriteId)
                    .toSet();
                if (remainingIds.contains(record.favoriteId))
                {
                    throw const ForumParseException(
                        '论坛未确认取消收藏成功',
                    );
                }
            }
            on Object
            {
                throw _unknown(request, context, attemptId);
            }
        }
    }

    Future<void> _throwIfUnresolved(
        ForumActionRequest request,
        String context,
    ) async
    {
        final ForumReadbackDescriptor readback = _favoriteReadback(request);
        final ForumUnresolvedSubmission? unresolved = await _tombstones.find(
            userId: _userId,
            request: request,
            readback: readback,
            draftContext: context,
        );
        if (unresolved != null)
        {
            throw ForumSubmissionBlockedException(unresolved);
        }
    }

    Future<String> _claim(
        ForumActionRequest request,
        String context,
    ) async
    {
        final String? attemptId = await _tombstones.claimAttemptedKey(
            userId: _userId,
            key: SubmissionTombstoneKey(
                action: request.kind.name,
                boardId: request.target.boardId,
                threadId: request.target.threadId,
                postId: request.target.postId,
                favoriteId: request.target.favoriteId,
                draftContext: context,
            ),
            deleteDraft: false,
        );
        if (attemptId == null)
        {
            await _throwIfUnresolved(request, context);
            throw StateError('论坛收藏提交封存冲突');
        }
        return attemptId;
    }

    ForumSubmissionBlockedException _unknown(
        ForumActionRequest request,
        String context,
        String attemptId,
    )
    {
        return ForumSubmissionBlockedException(
            ForumUnresolvedSubmission(
                attemptId: attemptId,
                userId: _userId,
                request: request,
                readback: _favoriteReadback(request),
                status: ForumSubmissionTombstoneStatus.attempted,
                recordedAt: DateTime.now().toUtc(),
                draftContext: context,
            ),
        );
    }

    void _validateUnresolved(
        ForumUnresolvedSubmission submission, {
        Work? work,
    })
    {
        final ForumActionRequest request = submission.request;
        final ForumActionTarget target = request.target;
        final bool validKind = switch (request.kind)
        {
            ForumActionKind.favoriteThread => target.favoriteId == null,
            ForumActionKind.removeFavorite =>
                (target.favoriteId ?? 0) > 0,
            _ => false,
        };
        final bool validTarget = (target.threadId ?? 0) > 0 &&
            target.boardId == null &&
            target.postId == null;
        final bool validReadback =
            request.readbackUri == _favoriteListUri() &&
            submission.readback.kind == ForumReadbackKind.threadFavorites &&
            submission.readback.uri == _favoriteListUri() &&
            _sameTarget(submission.readback.target, target);
        final bool belongsToWork = work == null ||
            _workPolicy.sourceTids(work).contains(target.threadId);
        if (submission.userId != _userId ||
            submission.draftContext.isNotEmpty ||
            !validKind ||
            !validTarget ||
            !validReadback ||
            !belongsToWork)
        {
            throw StateError('收藏提交封存不属于当前账号或作品');
        }
    }

    bool _sameTarget(ForumActionTarget first, ForumActionTarget second)
    {
        return first.boardId == second.boardId &&
            first.threadId == second.threadId &&
            first.postId == second.postId &&
            first.favoriteId == second.favoriteId;
    }

    Future<void> _reconcileFavoriteTombstones(
        List<CloudFavoriteRecord> records,
    ) async
    {
        const String context = '';
        final Set<int> threadIds = records
            .map((CloudFavoriteRecord value) => value.threadId)
            .toSet();
        final Set<int> favoriteIds = records
            .map((CloudFavoriteRecord value) => value.favoriteId)
            .toSet();
        final List<ForumSubmissionTombstoneSnapshot> snapshots =
            await _tombstones.listContext(
                userId: _userId,
                draftContext: context,
            );
        for (final ForumSubmissionTombstoneSnapshot snapshot in snapshots)
        {
            final bool confirmed = switch (snapshot.kind)
            {
                ForumActionKind.favoriteThread =>
                    threadIds.contains(snapshot.target.threadId),
                ForumActionKind.removeFavorite =>
                    snapshot.target.favoriteId != null &&
                    !favoriteIds.contains(snapshot.target.favoriteId),
                _ => false,
            };
            if (confirmed)
            {
                await _tombstones.resolveSnapshot(snapshot);
            }
        }
    }

    ForumActionRequest _favoriteRequest({
        required ForumActionKind kind,
        required int threadId,
        int? favoriteId,
        required Uri entryUri,
    })
    {
        return ForumActionRequest(
            kind: kind,
            target: ForumActionTarget(
                threadId: threadId,
                favoriteId: favoriteId,
            ),
            entryUri: entryUri,
            readbackUri: _favoriteListUri(),
        );
    }

    ForumReadbackDescriptor _favoriteReadback(ForumActionRequest request)
    {
        return ForumReadbackDescriptor(
            kind: ForumReadbackKind.threadFavorites,
            uri: request.readbackUri,
            target: request.target,
            description: '刷新主题收藏列表，人工核对目标记录后再决定是否解除防重复封存',
        );
    }

    String _favoriteContext() => '';

    Future<CloudFavoritePage> _loadPage(Uri uri) async
    {
        final Response<String> response = await _client.getText(uri);
        final ForumFavoriteListPage page = _parser.parseList(
            response.data ?? '',
            response.realUri,
            expectedUserId: _userId,
        );
        final List<CloudFavoriteEntry?> resolved =
            List<CloudFavoriteEntry?>.filled(page.records.length, null);
        int nextIndex = 0;
        int ignoredCount = 0;

        Future<void> worker() async
        {
            while (true)
            {
                final int index = nextIndex++;
                if (index >= page.records.length)
                {
                    return;
                }
                final CloudFavoriteRecord record = page.records[index];
                try
                {
                    final Uri metadataUri = _metadataUri(record.threadId);
                    final Response<String> metadataResponse =
                        await _client.getText(
                            metadataUri,
                            referer: record.threadUri.toString(),
                        );
                    final SourceThread? sourceThread =
                        _parser.parseThreadMetadata(
                            metadataResponse.data ?? '',
                            record,
                            apiUri: metadataResponse.realUri,
                            expectedUserId: _userId,
                        );
                    if (sourceThread == null)
                    {
                        ignoredCount++;
                        continue;
                    }
                    resolved[index] = CloudFavoriteEntry(
                        record: record,
                        sourceThread: sourceThread,
                    );
                }
                on ForumSessionExpiredException
                {
                    rethrow;
                }
                on ForumActionSecurityException
                {
                    rethrow;
                }
                on Object
                {
                    ignoredCount++;
                }
            }
        }

        await Future.wait(
            List<Future<void>>.generate(
                math.min(4, page.records.length),
                (int index) => worker(),
            ),
        );
        return CloudFavoritePage(
            entries: resolved.whereType<CloudFavoriteEntry>().toList(
                growable: false,
            ),
            ignoredCount: ignoredCount,
            currentPage: page.currentPage,
            totalPages: page.totalPages,
            nextPageUri: page.nextPageUri,
        );
    }

    Future<List<CloudFavoriteRecord>> _loadAllRecords() async
    {
        final List<CloudFavoriteRecord> records = <CloudFavoriteRecord>[];
        final Set<Uri> visited = <Uri>{};
        Uri? uri = _favoriteListUri();
        int expectedPage = 1;
        int? totalPages;
        while (uri != null)
        {
            if (!visited.add(uri) || visited.length > 100)
            {
                throw const ForumParseException('收藏列表分页不完整，不能作为提交结果依据');
            }
            final Response<String> response = await _client.getText(uri);
            final ForumFavoriteListPage page = _parser.parseList(
                response.data ?? '',
                response.realUri,
                expectedUserId: _userId,
            );
            totalPages ??= page.totalPages;
            if (page.currentPage != expectedPage ||
                page.totalPages != totalPages ||
                page.totalPages < page.currentPage ||
                (page.currentPage < page.totalPages) !=
                    (page.nextPageUri != null))
            {
                throw const ForumParseException(
                    '收藏列表分页不完整，不能作为提交结果依据',
                );
            }
            records.addAll(page.records);
            uri = page.nextPageUri;
            expectedPage++;
        }
        return records;
    }

    Uri _favoriteListUri()
    {
        return ForumClient.baseUri.resolve(
            'home.php?mod=space&do=favorite&view=me&type=thread&mobile=2',
        );
    }

    Uri _metadataUri(int threadId)
    {
        return ForumClient.baseUri.resolve(
            'api/mobile/index.php?version=4&module=viewthread&tid=$threadId',
        );
    }

    Future<T> _withActiveAccount<T>(Future<T> Function() operation)
    {
        if (_userId <= 0)
        {
            throw const ForumSessionExpiredException();
        }
        return _client.withActiveAccount(_userId, operation);
    }
}
