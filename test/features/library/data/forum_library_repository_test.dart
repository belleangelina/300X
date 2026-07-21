import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/features/library/data/forum_catalog_parser.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/data/forum_thread_parser.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';

class _MockForumClient extends Mock implements ForumClient {}

class _SlowThreadParser extends ForumThreadParser
{
    const _SlowThreadParser();

    @override
    ForumThreadPage parse(
        String html,
        Uri pageUri,
        ForumBoard board, {
        int? expectedTid,
    })
    {
        final Stopwatch stopwatch = Stopwatch()..start();
        while (stopwatch.elapsed < const Duration(milliseconds: 80))
        {
            // 模拟真实大帖 DOM 解析占用的同步 CPU 时间。
        }
        return ForumThreadPage(
            tid: expectedTid ?? 0,
            board: board,
            title: '后台解析结果',
            uri: pageUri,
            posts: const <SourcePost>[],
            currentPage: 1,
            totalPages: 1,
        );
    }
}

void main()
{
    late _MockForumClient client;
    late ForumLibraryRepository repository;
    late List<Uri> requestedUris;

    setUp(()
    {
        client = _MockForumClient();
        repository = ForumLibraryRepository(client);
        requestedUris = <Uri>[];
        when(() => client.getText(any())).thenAnswer((Invocation invocation) async
        {
            final Uri uri = invocation.positionalArguments.single as Uri;
            requestedUris.add(uri);
            final String html;
            if (uri.queryParameters['mod'] == 'forumdisplay')
            {
                html = _catalogPage;
            }
            else if (uri.queryParameters['mod'] == 'tag')
            {
                html = uri.queryParameters['page'] == '2' ? _tagPageTwo : _tagPageOne;
            }
            else if (uri.queryParameters['mod'] == 'redirect')
            {
                html = _ownerPageOne;
            }
            else if (uri.queryParameters['authorid'] == null)
            {
                html = _normalPage;
            }
            else if (uri.queryParameters['page'] == '2')
            {
                html = _ownerPageTwo;
            }
            else
            {
                html = _ownerPageOne;
            }
            return Response<String>(
                requestOptions: RequestOptions(path: uri.toString()),
                data: html,
                statusCode: 200,
            );
        });
    });

    test('详情通过只看楼主分页合并完整楼主正文并复用结果', () async
    {
        final SourceThread thread = SourceThread(
            tid: 10,
            board: ForumBoard.literature,
            title: '测试长篇',
            uri: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10&mobile=2',
            ),
        );

        final ForumThreadPage page = await repository.loadThread(
            thread,
            includeAllOriginalPosterPosts: true,
        );
        final ForumThreadPage reused = await repository.loadChapterPage(
            Chapter(
                id: 'forum-post:10:101',
                title: '第一章',
                sourceUri: thread.uri,
                sourceTid: 10,
                sourcePid: 101,
            ),
            ForumBoard.literature,
        );

        expect(page.posts.map((SourcePost post) => post.pid), <int>[100, 101, 102]);
        expect(
            page.posts.every((SourcePost post) => post.isOriginalPoster),
            isTrue,
        );
        expect(page.totalPages, 2);
        expect(identical(reused, page), isTrue);
        verify(() => client.getText(any())).called(3);
    });

    test('封面补探测只读取指定数量的楼主分页', () async
    {
        final SourceThread thread = SourceThread(
            tid: 10,
            board: ForumBoard.comic,
            title: '测试长篇',
            uri: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10&mobile=2',
            ),
        );

        final ForumThreadPage page = await repository.loadThread(
            thread,
            includeAllOriginalPosterPosts: true,
            maximumOriginalPosterPages: 1,
        );

        expect(page.posts.map((SourcePost post) => post.pid), <int>[100, 101]);
        expect(page.totalPages, 1);
        expect(requestedUris, hasLength(2));
    });

    test('小说首楼已有完整 pid 目录时不再拉取全部楼主分页', () async
    {
        when(() => client.getText(any())).thenAnswer((Invocation invocation) async
        {
            final Uri uri = invocation.positionalArguments.single as Uri;
            requestedUris.add(uri);
            return Response<String>(
                requestOptions: RequestOptions(path: uri.toString()),
                data: _normalNovelDirectoryPage,
                statusCode: 200,
            );
        });
        final SourceThread thread = SourceThread(
            tid: 10,
            board: ForumBoard.lightNovel,
            title: '测试长篇小说',
            uri: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10&mobile=2',
            ),
        );
        final List<(int, int)> progress = <(int, int)>[];

        final ForumThreadPage page = await repository.loadDirectoryThread(
            thread,
            onPageProgress: (int completed, int total) =>
                    progress.add((completed, total)),
        );

        expect(page.originalPost!.links.map((ThreadLink link) => link.pid),
                <int?>[101, 102]);
        expect(progress, <(int, int)>[(1, 1)]);
        expect(requestedUris, hasLength(1));
    });

    test('小说目录不会等待封面提前启动的完整楼主分页', () async
    {
        final Completer<void> ownerRequestStarted = Completer<void>();
        final Completer<void> releaseOwnerRequest = Completer<void>();
        int normalRequestCount = 0;
        when(() => client.getText(any())).thenAnswer((Invocation invocation) async
        {
            final Uri uri = invocation.positionalArguments.single as Uri;
            requestedUris.add(uri);
            late final String html;
            if (uri.queryParameters['authorid'] != null)
            {
                if (!ownerRequestStarted.isCompleted)
                {
                    ownerRequestStarted.complete();
                }
                await releaseOwnerRequest.future;
                html = _ownerPageTwo;
            }
            else
            {
                normalRequestCount++;
                html = normalRequestCount == 1
                        ? _normalPage
                        : _normalNovelDirectoryPage;
            }
            return Response<String>(
                requestOptions: RequestOptions(path: uri.toString()),
                data: html,
                statusCode: 200,
            );
        });
        final SourceThread thread = SourceThread(
            tid: 10,
            board: ForumBoard.lightNovel,
            title: '测试长篇小说',
            uri: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10&mobile=2',
            ),
        );
        final Future<ForumThreadPage> coverLoad = repository.loadThread(
            thread,
            includeAllOriginalPosterPosts: true,
        );
        await ownerRequestStarted.future;

        final ForumThreadPage directory = await repository
                .loadDirectoryThread(thread)
                .timeout(const Duration(seconds: 1));

        expect(directory.originalPost!.links, hasLength(2));
        releaseOwnerRequest.complete();
        await coverLoad;
    });

    test('没有完整帖子缓存时按 pid 跳转只加载目标章节页', () async
    {
        final Chapter chapter = Chapter(
            id: 'forum-post:10:101',
            title: '第一章',
            sourceUri: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost'
                '&ptid=10&pid=101&mobile=2',
            ),
            sourceTid: 10,
            sourcePid: 101,
            sourceEndPid: 102,
        );

        final ForumThreadPage page = await repository.loadChapterPage(
            chapter,
            ForumBoard.lightNovel,
        );

        expect(page.posts.map((SourcePost post) => post.pid), contains(101));
        expect(requestedUris.single.queryParameters['mod'], 'redirect');
    });

    test('帖子 DOM 解析期间主 isolate 仍可处理事件', () async
    {
        final ForumLibraryRepository backgroundRepository =
                ForumLibraryRepository(
                    client,
                    const ForumCatalogParser(),
                    const _SlowThreadParser(),
                );
        final SourceThread thread = SourceThread(
            tid: 10,
            board: ForumBoard.literature,
            title: '测试长篇',
            uri: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10&mobile=2',
            ),
        );
        bool eventLoopTicked = false;

        final Future<ForumThreadPage> load = backgroundRepository.loadThread(
            thread,
        );
        Timer.run(() => eventLoopTicked = true);
        final ForumThreadPage page = await load;

        expect(eventLoopTicked, isTrue);
        expect(page.title, '后台解析结果');
    });

    test('主动刷新会淘汰完整帖子缓存并重新请求', () async
    {
        final SourceThread thread = SourceThread(
            tid: 10,
            board: ForumBoard.literature,
            title: '测试长篇',
            uri: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10&mobile=2',
            ),
        );

        final ForumThreadPage first = await repository.loadThread(
            thread,
            includeAllOriginalPosterPosts: true,
        );
        final ForumThreadPage reused = await repository.loadThread(
            thread,
            includeAllOriginalPosterPosts: true,
        );
        final ForumThreadPage refreshed = await repository.loadThread(
            thread,
            includeAllOriginalPosterPosts: true,
            forceReload: true,
        );

        expect(identical(reused, first), isTrue);
        expect(identical(refreshed, first), isFalse);
        verify(() => client.getText(any())).called(6);
    });

    test('Tag 目录通过普通 GET 拉完分页并复用结果', () async
    {
        final Uri uri = Uri.parse(
            'https://bbs.yamibo.com/misc.php?mod=tag&id=15629&page=2&mobile=2',
        );

        final List<ThreadLink> links = await repository.loadTagDirectory(uri);
        final List<ThreadLink> reused = await repository.loadTagDirectory(uri);

        expect(links.map((ThreadLink link) => link.tid), <int?>[101, 102]);
        expect(identical(reused, links), isTrue);
        expect(requestedUris.first.queryParameters.containsKey('page'), isFalse);
        expect(
            requestedUris
                    .where((Uri value) => value.queryParameters['mod'] == 'tag')
                    .every((Uri value) => value.queryParameters['forcemobile'] == '1'),
            isTrue,
        );
        verify(() => client.getText(any())).called(2);
    });

    test('分类筛选与最新排序组合到同一个目录请求', () async
    {
        final WorkCatalogPage page = await repository.loadCatalog(
            kind: LibraryKind.comic,
            section: CatalogSection.updated,
            typeId: 69,
        );

        expect(requestedUris, hasLength(1));
        expect(requestedUris.single.queryParameters, containsPair('fid', '30'));
        expect(
            requestedUris.single.queryParameters,
            containsPair('filter', 'typeid'),
        );
        expect(
            requestedUris.single.queryParameters,
            containsPair('typeid', '69'),
        );
        expect(
            requestedUris.single.queryParameters,
            containsPair('orderby', 'lastpost'),
        );
        expect(page.sourceThreads, isEmpty);
        expect(page.works, isEmpty);
    });

    test('分类筛选与热度排序组合到同一个目录请求', () async
    {
        await repository.loadCatalog(
            kind: LibraryKind.novel,
            section: CatalogSection.ranking,
            novelSource: NovelSourceFilter.lightNovel,
            typeId: 201,
        );

        expect(requestedUris, hasLength(1));
        expect(requestedUris.single.queryParameters, containsPair('fid', '55'));
        expect(
            requestedUris.single.queryParameters,
            containsPair('filter', 'typeid'),
        );
        expect(
            requestedUris.single.queryParameters,
            containsPair('typeid', '201'),
        );
        expect(
            requestedUris.single.queryParameters,
            containsPair('orderby', 'heats'),
        );
    });
}

final String _normalPage =
        '''
        <html>
        <body id="forum" class="pg_viewthread">
                <div class="view_tit">测试长篇</div>
                <a href="forum.php?mod=viewthread&amp;tid=10&amp;page=1&amp;authorid=88&amp;mobile=2">只看楼主</a>
                ${_post(100, 1, '目录')}
        </body>
        </html>
''';

final String _normalNovelDirectoryPage =
        '''
        <html>
        <body id="forum" class="pg_viewthread">
                <div class="view_tit">测试长篇小说</div>
                <a href="forum.php?mod=viewthread&amp;tid=10&amp;page=1&amp;authorid=88&amp;mobile=2">只看楼主</a>
                ${_post(
                    100,
                    1,
                    '目录<br>'
                    '<a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=10&amp;pid=101">第一章</a><br>'
                    '<a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=10&amp;pid=102">第二章</a>',
                )}
        </body>
        </html>
''';

const String _catalogPage = '''
        <html>
        <body id="forum" class="pg_forumdisplay">
                <div id="dhnavs_li">
                        <a href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=typeid&amp;typeid=69&amp;mobile=2">#長篇連載</a>
                </div>
                <div class="threadlist"><ul>
                        <li class="list">
                                <a href="forum.php?mod=viewthread&amp;tid=519989&amp;mobile=2">
                                        <div class="threadlist_tit"><em>中文百合漫画区漫画汇总</em></div>
                                </a>
                                <div class="threadlist_foot"><ul>
                                        <li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=typeid&amp;typeid=65&amp;mobile=2">#公告</a></li>
                                        <li>100</li><li>20</li>
                                </ul></div>
                        </li>
                </ul></div>
        </body>
        </html>
''';

final String _ownerPageOne =
        '''
        <html>
        <body id="forum" class="pg_viewthread">
                <div class="view_tit">测试长篇</div>
                <a href="forum.php?mod=viewthread&amp;tid=10&amp;page=1&amp;authorid=88&amp;mobile=2">只看楼主</a>
                ${_post(100, 1, '目录')}
                ${_post(101, 2, '第一章正文')}
                <div class="pg">
                        <input name="custompage" value="1" />
                        <a class="last" href="forum.php?mod=viewthread&amp;tid=10&amp;page=2&amp;authorid=88&amp;mobile=2">2</a>
                        <a class="nxt" href="forum.php?mod=viewthread&amp;tid=10&amp;page=2&amp;authorid=88&amp;mobile=2">下一页</a>
                </div>
        </body>
        </html>
''';

final String _ownerPageTwo =
        '''
        <html>
        <body id="forum" class="pg_viewthread">
                <div class="view_tit">测试长篇</div>
                <a href="forum.php?mod=viewthread&amp;tid=10&amp;page=1&amp;authorid=88&amp;mobile=2">只看楼主</a>
                ${_post(102, 3, '第二章正文')}
                <div class="pg">
                        <input name="custompage" value="2" />
                </div>
        </body>
        </html>
''';

final String _tagPageOne = '''
        <html>
        <body class="pg_tag">
                <div class="threadlist">
                        <a href="thread-101-1-1.html"><span class="threadlist_tit">作品 第1话</span></a>
                </div>
                <div class="pg">
                        <a class="nxt" href="misc.php?mod=tag&amp;id=15629&amp;type=thread&amp;page=2">下一页</a>
                </div>
        </body>
        </html>
''';

final String _tagPageTwo = '''
        <html>
        <body class="pg_tag">
                <div class="threadlist">
                        <a href="thread-102-1-1.html"><span class="threadlist_tit">作品 第2话</span></a>
                </div>
        </body>
        </html>
''';

String _post(int pid, int floor, String text)
{
    return '''
                <div class="plc cl" id="pid$pid">
                        <ul class="authi">
                                <li class="mtit"><span class="y">$floor楼</span><span class="z"><a>楼主</a></span></li>
                                <li class="mtime">2026-7-10 09:00</li>
                        </ul>
                        <div class="message">$text</div>
                </div>
        ''';
}
