import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/search/data/forum_search_parser.dart';
import 'package:x300/features/search/domain/search_models.dart';

void main()
{
    const ForumSearchParser parser = ForumSearchParser();

    test('解析搜索表单地址和 formhash', ()
    {
        final String html = '''
            <html><body class="pg_search">
                <form method="post" action="search.php?mod=forum">
                    <input type="hidden" name="formhash" value="hash123" />
                    <input name="srchtxt" />
                </form>
            </body></html>
        ''';
        final ForumSearchForm form = parser.parseForm(
            html,
            Uri.parse('https://bbs.yamibo.com/search.php?mod=forum&mobile=2'),
        );

        expect(form.formHash, 'hash123');
        expect(form.actionUri.host, 'bbs.yamibo.com');
        expect(form.actionUri.queryParameters['mod'], 'forum');
    });

    test('小说结果只接收两个小说板块并保留 searchid 分页', ()
    {
        final String html = '''
            <html><body id="search" class="pg_forum">
                <form class="searchform">
                    <input name="srchtxt" value="测试作品" />
                </form>
                <div class="threadlist_box">
                    <div class="threadlist"><ul>
                        ${_threadHtml(101, 49, '文学作品 第一章')}
                        ${_threadHtml(102, 55, '译文作品 第二卷')}
                        ${_threadHtml(103, 30, '漫画作品 第三话')}
                    </ul></div>
                </div>
                <div class="pg">
                    <strong>1</strong>
                    <a class="last" href="search.php?mod=forum&amp;searchid=456&amp;page=4&amp;mobile=2">4</a>
                    <a class="nxt" href="search.php?mod=forum&amp;searchid=456&amp;page=2&amp;mobile=2">下一页</a>
                </div>
            </body></html>
        ''';
        final ForumSearchPage page = parser.parseResults(
            html,
            Uri.parse(
                'https://bbs.yamibo.com/search.php?mod=forum&searchid=456&mobile=2',
            ),
            LibraryKind.novel,
        );

        expect(page.keyword, '测试作品');
        expect(page.searchId, '456');
        expect(page.sourceThreads, hasLength(2));
        expect(
            page.sourceThreads.map((SourceThread value) => value.board),
            <ForumBoard>[
                ForumBoard.literature,
                ForumBoard.lightNovel,
            ],
        );
        expect(page.currentPage, 1);
        expect(page.totalPages, 4);
        expect(page.nextPageUri?.queryParameters['searchid'], '456');
        expect(page.nextPageUri?.queryParameters['page'], '2');
    });

    test('未返回 searchid 时透传论坛限流消息', ()
    {
        const String html = '''
            <html><body class="pg_forum">
                <div id="messagetext"><p>两次搜索间隔少于 10 秒</p></div>
            </body></html>
        ''';

        expect(
            () => parser.parseResults(
                html,
                Uri.parse('https://bbs.yamibo.com/search.php?mod=forum&mobile=2'),
                LibraryKind.comic,
            ),
            throwsA(
                isA<ForumParseException>().having(
                    (ForumParseException value) => value.message,
                    'message',
                    contains('10 秒'),
                ),
            ),
        );
    });

    test('搜索结果剔除公告和版务主题', ()
    {
        final String html = '''
            <html><body id="search" class="pg_forum">
                <div class="threadlist_box">
                    <div class="threadlist"><ul>
                        ${_threadHtml(101, 30, '普通漫画 第1话')}
                        ${_threadHtml(102, 30, '漫画区公告')}
                        ${_threadHtml(103, 30, '关联任务帖——漫画整理任务帖')}
                    </ul></div>
                </div>
            </body></html>
        ''';

        final ForumSearchPage page = parser.parseResults(
            html,
            Uri.parse(
                'https://bbs.yamibo.com/search.php?mod=forum&searchid=789&mobile=2',
            ),
            LibraryKind.comic,
        );

        expect(page.sourceThreads.map((SourceThread thread) => thread.tid), <int>[
            101,
        ]);
    });
}

String _threadHtml(int tid, int fid, String title)
{
    return '''
        <li class="list">
            <div class="threadlist_top">
                <div class="muser"><a class="mmc">作者</a></div>
                <span class="mtime">2026-7-10 16:30</span>
            </div>
            <a href="forum.php?mod=viewthread&amp;tid=$tid&amp;mobile=2">
                <div class="threadlist_tit"><em>$title</em></div>
            </a>
            <div class="threadlist_mes">摘要</div>
            <div class="threadlist_foot"><ul>
                <li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=$fid&amp;mobile=2">板块</a></li>
                <li>123</li><li>4</li>
            </ul></div>
        </li>
    ''';
}
