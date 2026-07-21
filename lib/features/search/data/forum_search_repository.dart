import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/features/library/data/work_aggregator.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/search/data/forum_search_parser.dart';
import 'package:x300/features/search/domain/search_models.dart';

final Provider<ForumSearchRepository> forumSearchRepositoryProvider =
    Provider<ForumSearchRepository>(
        (Ref ref) => ForumSearchRepository(
            ref.watch(forumClientProvider),
        ),
    );

class ForumSearchRepository
{
    ForumSearchRepository(
        this._client, [
        this._parser = const ForumSearchParser(),
        this._aggregator = const WorkAggregator(),
    ]);

    final ForumClient _client;
    final ForumSearchParser _parser;
    final WorkAggregator _aggregator;

    Future<ForumSearchPage> search({
        required String keyword,
        required LibraryKind kind,
    }) async
    {
        final String normalizedKeyword = keyword.trim();
        if (normalizedKeyword.isEmpty)
        {
            throw ArgumentError.value(keyword, 'keyword', '搜索词不能为空');
        }
        final Uri formUri = ForumClient.baseUri.resolve(
            'search.php?mod=forum&mobile=2',
        );
        final Response<String> formResponse = await _client.getText(formUri);
        final ForumSearchForm form = await _parseForm(
            formResponse.data ?? '',
            formResponse.realUri,
        );
        final Uri actionUri = form.actionUri.replace(
            queryParameters: <String, dynamic>{
                ...form.actionUri.queryParameters,
                'mod': 'forum',
                'mobile': '2',
            },
        );
        final List<String> boardIds = (kind == LibraryKind.comic
                ? const <ForumBoard>[ForumBoard.comic]
                : const <ForumBoard>[
                    ForumBoard.literature,
                    ForumBoard.lightNovel,
                ])
            .map((ForumBoard board) => board.fid.toString())
            .toList(growable: false);
        final Response<String> response = await _client.postForm(
            actionUri,
            referer: formResponse.realUri.toString(),
            fields: <String, dynamic>{
                'formhash': form.formHash,
                'srchtxt': normalizedKeyword,
                'seltableid': '0',
                'srchuname': '',
                'srchfilter': 'all',
                'srchfrom': '0',
                'before': '',
                'orderby': 'lastpost',
                'ascdesc': 'desc',
                'srchfid[]': boardIds,
                'searchsubmit': 'yes',
            },
        );
        return _parseResults(
            response.data ?? '',
            response.realUri,
            kind,
        );
    }

    Future<ForumSearchPage> loadNext(ForumSearchPage cursor) async
    {
        final Uri? uri = cursor.nextPageUri;
        if (uri == null)
        {
            return cursor;
        }
        final Response<String> response = await _client.getText(uri);
        return _parseResults(
            response.data ?? '',
            response.realUri,
            cursor.kind,
        );
    }

    Future<ForumSearchForm> _parseForm(String html, Uri pageUri)
    {
        final ForumSearchParser parser = _parser;
        return Isolate.run(
            () => parser.parseForm(html, pageUri),
            debugName: 'x300-forum-search-form-parser',
        );
    }

    Future<ForumSearchPage> _parseResults(
        String html,
        Uri pageUri,
        LibraryKind kind,
    )
    {
        final ForumSearchParser parser = _parser;
        return Isolate.run(
            () => parser.parseResults(html, pageUri, kind),
            debugName: 'x300-forum-search-result-parser',
        );
    }

    List<Work> aggregateThreads(List<SourceThread> sourceThreads)
    {
        return _aggregator.aggregate(sourceThreads);
    }
}
