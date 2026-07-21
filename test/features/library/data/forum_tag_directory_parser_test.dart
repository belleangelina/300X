import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/library/data/forum_tag_directory_parser.dart';
import 'package:x300/features/library/domain/thread_models.dart';

void main()
{
    const ForumTagDirectoryParser parser = ForumTagDirectoryParser();

    test('解析移动版和桌面版主题链接并保留 Tag 分页', ()
    {
        final Uri uri = Uri.parse(
            'https://bbs.yamibo.com/misc.php?mod=tag&id=15629&type=thread&mobile=2',
        );
        const String html = '''
                        <html>
                        <body class="pg_tag">
                                <div class="threadlist">
                                        <a href="thread-101-1-1.html"><span class="threadlist_tit">作品 第1话</span></a>
                                </div>
                                <table class="tl">
                                        <tr><th><a class="xst" href="forum.php?mod=viewthread&amp;tid=102">作品 第2话</a></th></tr>
                                </table>
                                <a href="thread-999-1-1.html">论坛公告</a>
                                <div class="pg">
                                        <a class="nxt" href="misc.php?mod=tag&amp;id=15629&amp;type=thread&amp;page=2">下一页</a>
                                </div>
                        </body>
                        </html>
                ''';

        final ForumTagDirectoryPage page = parser.parse(html, uri);

        expect(page.links.map((ThreadLink link) => link.tid), <int?>[101, 102]);
        expect(page.links.first.label, '作品 第1话');
        expect(page.nextPageUri?.queryParameters['page'], '2');
    });

    test('拒绝降级到 HTTP 的下一页', ()
    {
        final Uri uri = Uri.parse(
            'https://bbs.yamibo.com/misc.php?mod=tag&id=15629&type=thread',
        );
        const String html = '''
                        <html>
                        <body class="pg_tag">
                                <div class="threadlist">
                                        <a href="thread-101-1-1.html">作品 第1话</a>
                                </div>
                                <div class="pg">
                                        <a class="nxt" href="http://bbs.yamibo.com/misc.php?mod=tag&amp;id=15629&amp;page=2">下一页</a>
                                </div>
                        </body>
                        </html>
                ''';

        final ForumTagDirectoryPage page = parser.parse(html, uri);

        expect(page.nextPageUri, isNull);
    });
}
