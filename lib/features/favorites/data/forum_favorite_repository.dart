import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/favorites/data/favorite_work_policy.dart';
import 'package:x300/features/favorites/data/forum_favorite_parser.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/library/data/work_aggregator.dart';
import 'package:x300/features/library/domain/library_models.dart';

final Provider<ForumFavoriteRepository> forumFavoriteRepositoryProvider =
    Provider<ForumFavoriteRepository>(
        (Ref ref) => ForumFavoriteRepository(
            ref.watch(forumClientProvider),
        ),
    );

class ForumFavoriteRepository
{
    ForumFavoriteRepository(
        this._client, [
        this._parser = const ForumFavoriteParser(),
        this._aggregator = const WorkAggregator(),
        this._workPolicy = const FavoriteWorkPolicy(),
    ]);

    final ForumClient _client;
    final ForumFavoriteParser _parser;
    final WorkAggregator _aggregator;
    final FavoriteWorkPolicy _workPolicy;

    Future<CloudFavoritePage> loadInitial() async
    {
        return _loadPage(_favoriteListUri());
    }

    Future<CloudFavoritePage> loadNext(CloudFavoritePage cursor) async
    {
        final Uri? uri = cursor.nextPageUri;
        if (uri == null)
        {
            return cursor;
        }
        return _loadPage(uri);
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

    Future<List<CloudFavoriteRecord>> findForWork(Work work) async
    {
        final Set<int> threadIds = _workPolicy.sourceTids(work);
        final List<CloudFavoriteRecord> records = await _loadAllRecords();
        return records
            .where(
                (CloudFavoriteRecord value) =>
                    threadIds.contains(value.threadId),
            )
            .toList(growable: false);
    }

    Future<List<CloudFavoriteRecord>> addWork(Work work) async
    {
        final List<CloudFavoriteRecord> existing = await findForWork(work);
        if (existing.isNotEmpty)
        {
            return existing;
        }
        final SourceThread target = _workPolicy.anchor(work);
        final Uri dialogUri = ForumClient.baseUri.resolve(
            'home.php?mod=spacecp&ac=favorite&type=thread&'
            'id=${target.tid}&mobile=2',
        );
        final Response<String> dialogResponse = await _client.getText(
            dialogUri,
            referer: target.uri.toString(),
        );
        final ForumFavoriteForm form = _parser.parseActionForm(
            dialogResponse.data ?? '',
            dialogResponse.realUri,
        );
        final Response<String> response = await _client.postForm(
            form.actionUri,
            fields: form.fields,
            referer: dialogResponse.realUri.toString(),
        );
        _parser.ensureSubmissionSession(response.data ?? '');

        final List<CloudFavoriteRecord> confirmed = await findForWork(work);
        if (confirmed.isEmpty)
        {
            throw const ForumParseException('论坛未确认收藏成功');
        }
        return confirmed;
    }

    Future<void> removeWork(
        Work work,
        List<CloudFavoriteRecord> records,
    ) async
    {
        final Set<int> allowedThreadIds = _workPolicy.sourceTids(work);
        final Map<int, CloudFavoriteRecord> knownRecords =
            <int, CloudFavoriteRecord>{
                for (final CloudFavoriteRecord record in records)
                    record.favoriteId: record,
                for (final CloudFavoriteRecord record
                    in await _loadAllRecords())
                    record.favoriteId: record,
            };
        final List<CloudFavoriteRecord> targets = knownRecords.values
            .where(
                (CloudFavoriteRecord value) =>
                    allowedThreadIds.contains(value.threadId),
            )
            .toList(growable: false);
        for (final CloudFavoriteRecord record in targets)
        {
            final Response<String> dialogResponse = await _client.getText(
                record.deleteDialogUri,
                referer: _favoriteListUri().toString(),
            );
            final ForumFavoriteForm form = _parser.parseActionForm(
                dialogResponse.data ?? '',
                dialogResponse.realUri,
            );
            final Response<String> response = await _client.postForm(
                form.actionUri,
                fields: form.fields,
                referer: dialogResponse.realUri.toString(),
            );
            _parser.ensureSubmissionSession(response.data ?? '');
        }

        final Set<int> remainingIds = (await _loadAllRecords())
            .map((CloudFavoriteRecord value) => value.favoriteId)
            .toSet();
        if (targets.any(
            (CloudFavoriteRecord value) =>
                remainingIds.contains(value.favoriteId),
        ))
        {
            throw const ForumParseException('论坛未确认取消收藏成功');
        }
    }

    Future<CloudFavoritePage> _loadPage(Uri uri) async
    {
        final Response<String> response = await _client.getText(uri);
        final ForumFavoriteListPage page = _parser.parseList(
            response.data ?? '',
            response.realUri,
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
                    final Response<String> metadataResponse =
                        await _client.getText(
                            _metadataUri(record.threadId),
                            referer: record.threadUri.toString(),
                        );
                    final SourceThread? sourceThread =
                        _parser.parseThreadMetadata(
                            metadataResponse.data ?? '',
                            record,
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
        while (uri != null && visited.add(uri) && visited.length <= 100)
        {
            final Response<String> response = await _client.getText(uri);
            final ForumFavoriteListPage page = _parser.parseList(
                response.data ?? '',
                response.realUri,
            );
            records.addAll(page.records);
            uri = page.nextPageUri;
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
}
