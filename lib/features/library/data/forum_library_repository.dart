import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/library/data/forum_catalog_parser.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';
import 'package:x300/features/library/data/forum_tag_directory_parser.dart';
import 'package:x300/features/library/data/forum_thread_parser.dart';
import 'package:x300/features/library/data/work_aggregator.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

final Provider<ForumLibraryRepository> forumLibraryRepositoryProvider =
        Provider<ForumLibraryRepository>(
            (Ref ref) => ForumLibraryRepository(ref.watch(forumClientProvider)),
        );

typedef ForumThreadLoadProgress = void Function(int completed, int total);

typedef WorkCatalogQuery = ({
    LibraryKind kind,
    CatalogSection section,
    NovelSourceFilter novelSource,
    int page,
    int? typeId,
});

final workCatalogProvider =
        FutureProvider.family<WorkCatalogPage, WorkCatalogQuery>((
            Ref ref,
            WorkCatalogQuery query,
        )
        {
            return ref
                    .watch(forumLibraryRepositoryProvider)
                    .loadCatalog(
                        kind: query.kind,
                        section: query.section,
                        novelSource: query.novelSource,
                        page: query.page,
                        typeId: query.typeId,
                    );
        });

class ForumLibraryRepository
{
    static const int _maxTagDirectoryPages = 100;

    ForumLibraryRepository(
        this._client, [
        this._catalogParser = const ForumCatalogParser(),
        this._threadParser = const ForumThreadParser(),
        this._aggregator = const WorkAggregator(),
        this._tagDirectoryParser = const ForumTagDirectoryParser(),
    ]);

    final ForumClient _client;
    final ForumCatalogParser _catalogParser;
    final ForumThreadParser _threadParser;
    final WorkAggregator _aggregator;
    final ForumTagDirectoryParser _tagDirectoryParser;
    final Map<int, Future<ForumThreadPage>> _fullThreadLoads =
            <int, Future<ForumThreadPage>>{};
    final Map<int, ForumThreadPage> _completedFullThreads =
            <int, ForumThreadPage>{};
    final Map<String, Future<List<ThreadLink>>> _tagDirectoryLoads =
            <String, Future<List<ThreadLink>>>{};

    Future<WorkCatalogPage> loadCatalog({
        required LibraryKind kind,
        required CatalogSection section,
        NovelSourceFilter novelSource = NovelSourceFilter.all,
        int page = 1,
        int? typeId,
    }) async
    {
        final List<ForumBoard> boards = kind == LibraryKind.comic
                ? const <ForumBoard>[ForumBoard.comic]
                : novelSource.boards;
        final List<ForumCatalogPage> loadedPages = await Future.wait(
            boards.map(
                (ForumBoard board) => _loadBoard(
                    board: board,
                    section: section,
                    page: page,
                    typeId: typeId,
                ),
            ),
        );
        final Map<ForumBoard, ForumCatalogPage> pages =
                <ForumBoard, ForumCatalogPage>{
                    for (final ForumCatalogPage value in loadedPages) value.board: value,
                };
        final List<SourceThread> sourceThreads = _mergeThreads(
            loadedPages,
            section,
        );
        final List<ForumCategory> categories = loadedPages
                .expand((ForumCatalogPage value) => value.categories)
                .toList(growable: false);

        return WorkCatalogPage(
            works: _aggregator.aggregate(sourceThreads),
            sourceThreads: sourceThreads,
            categories: categories,
            pages: pages,
        );
    }

    Future<WorkCatalogPage> loadNextCatalog({
        required WorkCatalogPage cursor,
        required CatalogSection section,
    }) async
    {
        final List<ForumCatalogPage> loadedPages = await Future.wait(
            cursor.pages.values
                    .where((ForumCatalogPage page) => page.nextPageUri != null)
                    .map((ForumCatalogPage page) async
                    {
                        final Response<String> response = await _client.getText(
                            page.nextPageUri!,
                        );
                        return _parseCatalog(
                            response.data ?? '',
                            response.realUri,
                            page.board,
                        );
                    }),
        );
        final List<SourceThread> sourceThreads = _mergeThreads(
            loadedPages,
            section,
        );
        return WorkCatalogPage(
            works: _aggregator.aggregate(sourceThreads),
            sourceThreads: sourceThreads,
            categories: loadedPages
                    .expand((ForumCatalogPage value) => value.categories)
                    .toList(growable: false),
            pages: <ForumBoard, ForumCatalogPage>{
                for (final ForumCatalogPage value in loadedPages) value.board: value,
            },
        );
    }

    List<Work> aggregateThreads(List<SourceThread> sourceThreads)
    {
        return _aggregator.aggregate(sourceThreads);
    }

    Future<ForumThreadPage> loadThread(
        SourceThread thread, {
        bool includeAllOriginalPosterPosts = false,
        bool forceReload = false,
        int? maximumOriginalPosterPages,
    }) async
    {
        if (!includeAllOriginalPosterPosts)
        {
            return _loadThreadPage(_withMobile(thread.uri), thread.board, thread.tid);
        }

        if (maximumOriginalPosterPages != null)
        {
            if (maximumOriginalPosterPages < 1)
            {
                throw ArgumentError.value(
                    maximumOriginalPosterPages,
                    'maximumOriginalPosterPages',
                );
            }
            return _loadFullThread(
                thread,
                maximumPages: maximumOriginalPosterPages,
            );
        }

        return _loadFullThreadCached(
            thread,
            forceReload: forceReload,
        );
    }

    Future<ForumThreadPage> loadDirectoryThread(
        SourceThread thread, {
        bool forceReload = false,
        ForumThreadLoadProgress? onPageProgress,
    }) async
    {
        if (forceReload)
        {
            _invalidateFullThread(thread.tid);
        }
        final ForumThreadPage? completed = _completedFullThreads[thread.tid];
        if (completed != null)
        {
            onPageProgress?.call(completed.totalPages, completed.totalPages);
            return completed;
        }
        final Future<ForumThreadPage>? existing = _fullThreadLoads[thread.tid];
        if (thread.board.kind != LibraryKind.novel && existing != null)
        {
            final ForumThreadPage page = await existing;
            onPageProgress?.call(page.totalPages, page.totalPages);
            return page;
        }
        final ForumThreadPage initial = await _loadThreadPage(
            _threadUri(thread.tid),
            thread.board,
            thread.tid,
        );
        if (_hasCompleteNovelDirectory(thread, initial))
        {
            onPageProgress?.call(1, 1);
            return initial;
        }
        if (existing != null)
        {
            final ForumThreadPage page = await existing;
            onPageProgress?.call(page.totalPages, page.totalPages);
            return page;
        }
        return _loadFullThreadCached(
            thread,
            forceReload: forceReload,
            initialPage: initial,
            onPageProgress: onPageProgress,
        );
    }

    Future<ForumThreadPage> _loadFullThreadCached(
        SourceThread thread, {
        required bool forceReload,
        ForumThreadPage? initialPage,
        ForumThreadLoadProgress? onPageProgress,
    }) async
    {
        if (forceReload)
        {
            _invalidateFullThread(thread.tid);
        }
        final ForumThreadPage? completed = _completedFullThreads[thread.tid];
        if (completed != null)
        {
            onPageProgress?.call(completed.totalPages, completed.totalPages);
            return completed;
        }
        final Future<ForumThreadPage>? existing = _fullThreadLoads[thread.tid];
        if (existing != null)
        {
            final ForumThreadPage page = await existing;
            onPageProgress?.call(page.totalPages, page.totalPages);
            return page;
        }
        final Future<ForumThreadPage> future = _loadFullThread(
            thread,
            initialPage: initialPage,
            onPageProgress: onPageProgress,
        );
        _fullThreadLoads[thread.tid] = future;
        try
        {
            final ForumThreadPage page = await future;
            if (identical(_fullThreadLoads[thread.tid], future))
            {
                _completedFullThreads[thread.tid] = page;
            }
            return page;
        }
        on Object
        {
            if (identical(_fullThreadLoads[thread.tid], future))
            {
                _fullThreadLoads.remove(thread.tid);
            }
            rethrow;
        }
    }

    Future<ForumThreadPage> loadChapterPage(
        Chapter chapter,
        ForumBoard board, {
        bool forceReload = false,
    }) async
    {
        if (forceReload)
        {
            _invalidateFullThread(chapter.sourceTid);
        }
        final ForumThreadPage? completed =
                _completedFullThreads[chapter.sourceTid];
        if (!forceReload && completed != null)
        {
            return completed;
        }
        final Future<ForumThreadPage>? existing = _fullThreadLoads[chapter.sourceTid];
        if (!forceReload && chapter.sourcePid == null && existing != null)
        {
            return existing;
        }
        if (chapter.sourcePid != null)
        {
            final Uri uri = ForumClient.baseUri.resolve(
                'forum.php?mod=redirect&goto=findpost&ptid='
                '${chapter.sourceTid}&pid=${chapter.sourcePid}&mobile=2',
            );
            return _loadThreadPage(uri, board, chapter.sourceTid);
        }
        return loadThread(
            SourceThread(
                tid: chapter.sourceTid,
                board: board,
                title: chapter.title,
                uri: _threadUri(chapter.sourceTid),
            ),
            includeAllOriginalPosterPosts: true,
            forceReload: forceReload,
        );
    }

    void _invalidateFullThread(int tid)
    {
        _fullThreadLoads.remove(tid);
        _completedFullThreads.remove(tid);
    }

    Future<List<ThreadLink>> loadTagDirectory(
        Uri directoryUri, {
        bool forceReload = false,
    }) async
    {
        final Uri uri = _tagDirectoryUri(directoryUri, firstPage: true);
        final String key = uri.queryParameters['id']!;
        if (forceReload)
        {
            _tagDirectoryLoads.remove(key);
        }
        final Future<List<ThreadLink>>? existing = _tagDirectoryLoads[key];
        if (existing != null)
        {
            return existing;
        }
        final Future<List<ThreadLink>> future = _loadTagDirectory(uri);
        _tagDirectoryLoads[key] = future;
        try
        {
            return await future;
        }
        on Object
        {
            if (identical(_tagDirectoryLoads[key], future))
            {
                _tagDirectoryLoads.remove(key);
            }
            rethrow;
        }
    }

    Future<ForumThreadPage> _loadFullThread(
        SourceThread thread, {
        ForumThreadPage? initialPage,
        ForumThreadLoadProgress? onPageProgress,
        int? maximumPages,
    }) async
    {
        final ForumThreadPage initial = initialPage ??
                await _loadThreadPage(
                    _threadUri(thread.tid),
                    thread.board,
                    thread.tid,
                );
        final Uri? originalPosterUri = initial.originalPosterUri;
        if (originalPosterUri == null)
        {
            return initial;
        }

        final List<ForumThreadPage> pages = <ForumThreadPage>[];
        final Set<String> loadedUris = <String>{};
        Uri? nextUri = originalPosterUri;
        while (nextUri != null &&
                (maximumPages == null || pages.length < maximumPages) &&
                loadedUris.add(nextUri.toString()))
        {
            final ForumThreadPage page = await _loadThreadPage(
                nextUri,
                thread.board,
                thread.tid,
            );
            pages.add(page);
            onPageProgress?.call(pages.length, page.totalPages);
            final Uri? candidate = page.nextPageUri;
            if (candidate == null ||
                    candidate.host != ForumClient.baseUri.host ||
                    queryInt(candidate, 'tid') != thread.tid)
            {
                nextUri = null;
            }
            else
            {
                nextUri = _withMobile(candidate);
            }
        }

        final Map<int, SourcePost> posts = <int, SourcePost>{};
        for (final ForumThreadPage page in pages)
        {
            for (final SourcePost post in page.posts)
            {
                if (post.isOriginalPoster)
                {
                    posts.putIfAbsent(post.pid, () => post);
                }
            }
        }
        return ForumThreadPage(
            tid: initial.tid,
            board: initial.board,
            title: initial.title,
            uri: initial.uri,
            posts: posts.values.toList(growable: false),
            currentPage: 1,
            totalPages: pages.length,
            typeName: initial.typeName,
            originalPosterUri: originalPosterUri,
        );
    }

    bool _hasCompleteNovelDirectory(
        SourceThread thread,
        ForumThreadPage page,
    )
    {
        if (thread.board.kind != LibraryKind.novel)
        {
            return false;
        }
        final SourcePost? originalPost = page.originalPost;
        if (originalPost == null)
        {
            return false;
        }
        if (originalPost.links.any(
            (ThreadLink link) => link.kind == ThreadLinkKind.directory,
        ))
        {
            return true;
        }
        final List<ThreadLink> chapterLinks = originalPost.links
                .where(
                    (ThreadLink link) => link.kind == ThreadLinkKind.chapter &&
                            link.tid == thread.tid &&
                            link.pid != null,
                )
                .toList(growable: false);
        final Set<int> chapterPids = chapterLinks
                .map((ThreadLink link) => link.pid!)
                .toSet();
        return chapterLinks.length >= 2 &&
                chapterPids.length == chapterLinks.length;
    }

    Future<List<ThreadLink>> _loadTagDirectory(Uri initialUri) async
    {
        final Map<int, ThreadLink> links = <int, ThreadLink>{};
        final Set<String> loadedUris = <String>{};
        Uri? nextUri = initialUri;
        while (nextUri != null &&
                loadedUris.length < _maxTagDirectoryPages &&
                loadedUris.add(nextUri.toString()))
        {
            final Response<String> response = await _client.getText(nextUri);
            if (!_isSameTagDirectory(response.realUri, initialUri))
            {
                throw const ForumParseException('论坛作品目录跳转地址无效');
            }
            final ForumTagDirectoryPage page = await _parseTagDirectory(
                response.data ?? '',
                response.realUri,
            );
            for (final ThreadLink link in page.links)
            {
                if (link.tid != null)
                {
                    links.putIfAbsent(link.tid!, () => link);
                }
            }
            nextUri = page.nextPageUri == null
                    ? null
                    : _tagDirectoryUri(page.nextPageUri!);
        }
        if (nextUri != null && loadedUris.length >= _maxTagDirectoryPages)
        {
            throw const ForumParseException('论坛作品目录分页过多');
        }
        return links.values.toList(growable: false);
    }

    bool _isSameTagDirectory(Uri uri, Uri initialUri)
    {
        return uri.scheme == ForumClient.baseUri.scheme &&
                uri.host == ForumClient.baseUri.host &&
                uri.port == ForumClient.baseUri.port &&
                uri.path == initialUri.path &&
                uri.queryParameters['mod'] == 'tag' &&
                uri.queryParameters['id'] == initialUri.queryParameters['id'];
    }

    Future<ForumThreadPage> _loadThreadPage(
        Uri uri,
        ForumBoard board,
        int expectedTid,
    ) async
    {
        final Response<String> response = await _client.getText(uri);
        return _parseThread(
            response.data ?? '',
            response.realUri,
            board,
            expectedTid: expectedTid,
        );
    }

    Uri _threadUri(int tid)
    {
        return ForumClient.baseUri.replace(
            path: 'forum.php',
            queryParameters: <String, String>{
                'mod': 'viewthread',
                'tid': tid.toString(),
                'page': '1',
                'mobile': '2',
            },
        );
    }

    Uri _tagDirectoryUri(Uri uri, {bool firstPage = false})
    {
        final String? id = uri.queryParameters['id'];
        if (uri.scheme != ForumClient.baseUri.scheme ||
                uri.host != ForumClient.baseUri.host ||
                uri.port != ForumClient.baseUri.port ||
                !uri.path.endsWith('/misc.php') ||
                uri.queryParameters['mod'] != 'tag' ||
                id == null ||
                id.isEmpty)
        {
            throw const ForumParseException('论坛作品目录地址无效');
        }
        final Map<String, dynamic> queryParameters = <String, dynamic>{
            ...uri.queryParameters,
            'mod': 'tag',
            'id': id,
            'type': 'thread',
            'mobile': '2',
            'forcemobile': '1',
        };
        if (firstPage)
        {
            queryParameters.remove('page');
        }
        return uri.replace(queryParameters: queryParameters);
    }

    Future<ForumCatalogPage> _loadBoard({
        required ForumBoard board,
        required CatalogSection section,
        required int page,
        required int? typeId,
    }) async
    {
        final Uri uri = _catalogUri(
            board: board,
            section: section,
            page: page,
            typeId: typeId,
        );
        final Response<String> response = await _client.getText(uri);
        return _parseCatalog(response.data ?? '', response.realUri, board);
    }

    Future<ForumCatalogPage> _parseCatalog(
        String html,
        Uri pageUri,
        ForumBoard board,
    )
    {
        final ForumCatalogParser parser = _catalogParser;
        return Isolate.run(
            () => parser.parse(html, pageUri, board),
            debugName: 'x300-forum-catalog-parser',
        );
    }

    Future<ForumThreadPage> _parseThread(
        String html,
        Uri pageUri,
        ForumBoard board, {
        required int expectedTid,
    })
    {
        final ForumThreadParser parser = _threadParser;
        return Isolate.run(
            () => parser.parse(
                html,
                pageUri,
                board,
                expectedTid: expectedTid,
            ),
            debugName: 'x300-forum-thread-parser',
        );
    }

    Future<ForumTagDirectoryPage> _parseTagDirectory(
        String html,
        Uri pageUri,
    )
    {
        final ForumTagDirectoryParser parser = _tagDirectoryParser;
        return Isolate.run(
            () => parser.parse(html, pageUri),
            debugName: 'x300-forum-tag-directory-parser',
        );
    }

    Uri _catalogUri({
        required ForumBoard board,
        required CatalogSection section,
        required int page,
        required int? typeId,
    })
    {
        final Map<String, dynamic> query = <String, dynamic>{
            'mod': 'forumdisplay',
            'fid': board.fid.toString(),
            'mobile': '2',
            if (page > 1) 'page': page.toString(),
        };
        if (typeId != null)
        {
            query.addAll(<String, dynamic>{
                'filter': 'typeid',
                'typeid': typeId.toString(),
                if (section == CatalogSection.updated) 'orderby': 'lastpost',
                if (section == CatalogSection.ranking) 'orderby': 'heats',
            });
        }
        else
        {
            switch (section)
            {
                case CatalogSection.recommended:
                    query.addAll(<String, dynamic>{'filter': 'digest', 'digest': '1'});
                case CatalogSection.updated:
                    query.addAll(<String, dynamic>{
                        'filter': 'lastpost',
                        'orderby': 'lastpost',
                    });
                case CatalogSection.categories:
                    break;
                case CatalogSection.ranking:
                    query.addAll(<String, dynamic>{'filter': 'heat', 'orderby': 'heats'});
            }
        }
        return ForumClient.baseUri.replace(
            path: 'forum.php',
            queryParameters: query,
        );
    }

    Uri _withMobile(Uri uri)
    {
        return uri.replace(
            queryParameters: <String, dynamic>{...uri.queryParameters, 'mobile': '2'},
        );
    }

    List<SourceThread> _mergeThreads(
        List<ForumCatalogPage> pages,
        CatalogSection section,
    )
    {
        final List<List<SourceThread>> sources = pages
                .map(
                    (ForumCatalogPage page) => page.threads
                            .where((SourceThread value) => !value.administrative)
                            .toList(growable: false),
                )
                .toList(growable: false);
        if (sources.length == 1)
        {
            return sources.single;
        }

        final List<SourceThread> interleaved = <SourceThread>[];
        final int maxLength = sources.fold<int>(
            0,
            (int current, List<SourceThread> value) =>
                    value.length > current ? value.length : current,
        );
        for (int index = 0; index < maxLength; index++)
        {
            for (final List<SourceThread> source in sources)
            {
                if (index < source.length)
                {
                    interleaved.add(source[index]);
                }
            }
        }
        if (section == CatalogSection.updated)
        {
            interleaved.sort((SourceThread left, SourceThread right)
            {
                final DateTime? leftTime = left.postedAt;
                final DateTime? rightTime = right.postedAt;
                if (leftTime == null || rightTime == null)
                {
                    return 0;
                }
                return rightTime.compareTo(leftTime);
            });
        }
        return interleaved;
    }
}
