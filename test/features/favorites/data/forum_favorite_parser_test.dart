import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/favorites/data/forum_favorite_parser.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/library/domain/library_models.dart';

void main()
{
    const ForumFavoriteParser parser = ForumFavoriteParser();
    final Uri pageUri = Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=space&do=favorite&view=me&'
        'type=thread&mobile=2',
    );

    test('解析收藏记录、favid 和分页', ()
    {
        const String html = '''
            <html><body id="home" class="pg_space">
                <div class="findbox"><ul>
                    <li class="sclist">
                        <a href="home.php?mod=spacecp&amp;ac=favorite&amp;op=delete&amp;favid=71&amp;mobile=2" class="dialog mdel">删除</a>
                        <a href="forum.php?mod=viewthread&amp;tid=101&amp;mobile=2">作品一</a>
                    </li>
                    <li class="sclist">
                        <a href="home.php?mod=spacecp&amp;ac=favorite&amp;op=delete&amp;favid=72&amp;mobile=2">删除</a>
                        <a href="forum.php?mod=viewthread&amp;tid=102&amp;mobile=2">作品二</a>
                    </li>
                </ul></div>
                <div class="pg">
                    <strong>1</strong>
                    <label><input name="custompage" value="1" /><span title="共 3 页">1 / 3</span></label>
                    <a class="nxt" href="home.php?mod=space&amp;do=favorite&amp;type=thread&amp;page=2&amp;mobile=2">下一页</a>
                </div>
            </body></html>
        ''';
        final ForumFavoriteListPage page = parser.parseList(html, pageUri);

        expect(page.records, hasLength(2));
        expect(page.records.first.favoriteId, 71);
        expect(page.records.first.threadId, 101);
        expect(page.records.first.title, '作品一');
        expect(page.currentPage, 1);
        expect(page.totalPages, 3);
        expect(page.nextPageUri?.queryParameters['page'], '2');
    });

    test('移动 API 元数据只映射受支持板块', ()
    {
        final CloudFavoriteRecord record = CloudFavoriteRecord(
            favoriteId: 71,
            threadId: 101,
            title: '作品 第一章',
            threadUri: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101&mobile=2',
            ),
            deleteDialogUri: Uri.parse(
                'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&op=delete&favid=71&mobile=2',
            ),
        );
        const String supported = '''
            {
                "Variables": {
                    "thread": {
                        "tid": "101",
                        "fid": "49",
                        "typeid": "3",
                        "subject": "作品 第一章",
                        "author": "作者",
                        "lastpost": "2026-7-10 16:30",
                        "views": "1200",
                        "replies": "8"
                    }
                }
            }
        ''';
        const String unsupported = '''
            {
                "Variables": {
                    "thread": {
                        "tid": "101",
                        "fid": "5"
                    }
                }
            }
        ''';

        final SourceThread? thread = parser.parseThreadMetadata(
            supported,
            record,
        );
        expect(thread, isNotNull);
        expect(thread!.board, ForumBoard.literature);
        expect(thread.views, 1200);
        expect(thread.replies, 8);
        expect(parser.parseThreadMetadata(unsupported, record), isNull);
    });

    test('解析添加和删除确认表单必要字段', ()
    {
        const String addHtml = '''
            <html><body><form action="home.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=101&amp;mobile=2">
                <input type="hidden" name="favoritesubmit" value="true" />
                <input type="hidden" name="referer" value="forum.php" />
                <input type="hidden" name="formhash" value="hash-add" />
                <textarea name="description"></textarea>
            </form></body></html>
        ''';
        const String deleteHtml = '''
            <html><body><form action="home.php?mod=spacecp&amp;ac=favorite&amp;op=delete&amp;favid=71&amp;mobile=2">
                <input type="hidden" name="deletesubmit" value="true" />
                <input type="hidden" name="formhash" value="hash-delete" />
            </form></body></html>
        ''';

        final ForumFavoriteForm add = parser.parseActionForm(
            addHtml,
            pageUri,
        );
        final ForumFavoriteForm delete = parser.parseActionForm(
            deleteHtml,
            pageUri,
        );

        expect(add.fields['favoritesubmit'], 'true');
        expect(add.fields['formhash'], 'hash-add');
        expect(add.fields['description'], '');
        expect(delete.fields['deletesubmit'], 'true');
        expect(delete.fields['formhash'], 'hash-delete');
    });
}
