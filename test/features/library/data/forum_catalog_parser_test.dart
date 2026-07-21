import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/library/data/forum_catalog_parser.dart';
import 'package:x300/features/library/domain/library_models.dart';

void main()
{
    const ForumCatalogParser parser = ForumCatalogParser();
    final Uri pageUri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=30&page=2&mobile=2',
    );

    test('解析分类、普通主题、置顶和分页', ()
    {
        const String html = '''
            <html>
            <body id="forum" class="pg_forumdisplay">
                <div id="dhnavs_li">
                    <ul class="swiper-wrapper">
                        <li><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=typeid&amp;typeid=65&amp;mobile=2">汉化</a></li>
                    </ul>
                </div>
                <div class="threadlist"><ul>
                    <li class="list_top">
                        <a href="forum.php?mod=viewthread&amp;tid=99&amp;mobile=2"><span class="micon">置顶</span><em>版规公告</em></a>
                    </li>
                    <li class="list">
                        <div class="threadlist_top cl">
                            <a class="mimg"><img src="avatar/example.jpg" /></a>
                            <div class="muser"><a class="mmc">译者甲</a><span class="mtime">2026-7-10 08:32</span></div>
                        </div>
                        <a href="forum.php?mod=viewthread&amp;tid=123&amp;mobile=2"><div class="threadlist_tit"><span class="micon digest">精华</span><em>作品 第12话</em></div></a>
                        <div class="threadlist_mes">章节摘要</div>
                        <div class="threadlist_foot"><ul>
                            <li class="mr"><a href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=typeid&amp;typeid=65&amp;mobile=2">汉化</a></li>
                            <li>1.2万</li><li>34</li>
                        </ul></div>
                    </li>
                </ul></div>
                <div class="pg">
                    <strong>2</strong>
                    <a href="forum.php?mod=forumdisplay&amp;fid=30&amp;page=5&amp;mobile=2" class="last">5</a>
                    <label><input name="custompage" value="2" /><span title="共 5 页">2 / 5</span></label>
                    <a href="forum.php?mod=forumdisplay&amp;fid=30&amp;page=3&amp;mobile=2" class="nxt">下一页</a>
                </div>
            </body>
            </html>
        ''';

        final ForumCatalogPage page = parser.parse(
            html,
            pageUri,
            ForumBoard.comic,
        );

        expect(page.categories, hasLength(1));
        expect(page.categories.single.typeId, 65);
        expect(page.pinnedThreads.single.tid, 99);
        expect(page.pinnedThreads.single.administrative, isTrue);
        expect(page.threads, hasLength(1));
        expect(page.threads.single.tid, 123);
        expect(page.threads.single.title, '作品 第12话');
        expect(page.threads.single.typeName, '汉化');
        expect(page.threads.single.views, 12000);
        expect(page.threads.single.replies, 34);
        expect(page.threads.single.postedAt, DateTime(2026, 7, 10, 8, 32));
        expect(page.currentPage, 2);
        expect(page.totalPages, 5);
        expect(page.nextPageUri?.queryParameters['page'], '3');
    });

    test('登录页明确报告会话失效', ()
    {
        const String html = '''
            <html><body class="pg_logging"><form id="loginform"></form></body></html>
        ''';

        expect(
            () => parser.parse(html, pageUri, ForumBoard.comic),
            throwsA(isA<ForumSessionExpiredException>()),
        );
    });

    test('#公告 分类主题标记为行政帖子', ()
    {
        const String html = '''
            <html>
            <body id="forum" class="pg_forumdisplay">
                <div id="dhnavs_li">
                    <a href="forum.php?mod=forumdisplay&amp;fid=30&amp;filter=typeid&amp;typeid=65&amp;mobile=2">#公告</a>
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

        final ForumCatalogPage page = parser.parse(
            html,
            pageUri,
            ForumBoard.comic,
        );

        expect(page.categories, isEmpty);
        expect(page.threads.single.typeName, '#公告');
        expect(page.threads.single.administrative, isTrue);
    });
}
