import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/favorites/data/forum_favorite_parser.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
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
            <html><head><script>var discuz_uid = '42';</script></head>
            <body id="home" class="pg_space">
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
        final ForumFavoriteListPage page = parser.parseList(
            html,
            pageUri,
            expectedUserId: 42,
        );

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
                    "member_uid": "42",
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
                    "member_uid": "42",
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
            apiUri: _metadataUri(101),
            expectedUserId: 42,
        );
        expect(thread, isNotNull);
        expect(thread!.board, ForumBoard.literature);
        expect(thread.views, 1200);
        expect(thread.replies, 8);
        expect(
            parser.parseThreadMetadata(
                unsupported,
                record,
                apiUri: _metadataUri(101),
                expectedUserId: 42,
            ),
            isNull,
        );
    });

    test('解析添加和删除确认表单必要字段', ()
    {
        const String addHtml = '''
            <html><head><script>var discuz_uid = '42';</script></head><body>
            <form method="post" action="home.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=101&amp;spaceuid=42&amp;mobile=2">
                <input type="hidden" name="favoritesubmit" value="true" />
                <input type="hidden" name="referer" value="forum.php" />
                <input type="hidden" name="formhash" value="hash-add" />
                <textarea name="description"></textarea>
            </form></body></html>
        ''';
        const String deleteHtml = '''
            <html><head><script>var discuz_uid = '42';</script></head><body>
            <form method="post" action="home.php?mod=spacecp&amp;ac=favorite&amp;op=delete&amp;favid=71&amp;mobile=2">
                <input type="hidden" name="deletesubmit" value="true" />
                <input type="hidden" name="formhash" value="hash-delete" />
            </form></body></html>
        ''';

        final ForumFavoriteForm add = parser.parseActionForm(
            addHtml,
            _addActionUri(101),
            expectedUserId: 42,
            expectedThreadId: 101,
        );
        final ForumFavoriteForm delete = parser.parseActionForm(
            deleteHtml,
            _deleteActionUri(71),
            expectedUserId: 42,
            expectedFavoriteId: 71,
        );

        expect(add.fields['favoritesubmit'], 'true');
        expect(add.fields['formhash'], 'hash-add');
        expect(add.fields['description'], '');
        expect(delete.fields['deletesubmit'], 'true');
        expect(delete.fields['formhash'], 'hash-delete');
    });

    test('列表、移动 API 和动作页都拒绝其他 uid', ()
    {
        const String listHtml = '''
            <html><head><script>var discuz_uid = '7';</script></head>
            <body id="home" class="pg_space"><div class="findbox"></div></body>
            </html>
        ''';
        final CloudFavoriteRecord record = CloudFavoriteRecord(
            favoriteId: 71,
            threadId: 101,
            title: '作品',
            threadUri: Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101&mobile=2',
            ),
            deleteDialogUri: _deleteActionUri(71),
        );

        expect(
            () => parser.parseList(
                listHtml,
                pageUri,
                expectedUserId: 42,
            ),
            throwsA(isA<ForumSessionExpiredException>()),
        );
        expect(
            () => parser.parseThreadMetadata(
                '{"Variables":{"member_uid":"7","thread":{"tid":"101","fid":"49"}}}',
                record,
                apiUri: _metadataUri(101),
                expectedUserId: 42,
            ),
            throwsA(isA<ForumSessionExpiredException>()),
        );
    });

    test('动作表单拒绝非 HTTPS、错目标并移除 URI 中的 formhash', ()
    {
        const String html = '''
            <html><head><script>var discuz_uid = '42';</script></head><body>
            <form method="post" action="home.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=101&amp;formhash=query-secret&amp;mobile=2">
                <input type="hidden" name="favoritesubmit" value="true" />
                <input type="hidden" name="formhash" value="field-secret" />
            </form></body></html>
        ''';
        final ForumFavoriteForm form = parser.parseActionForm(
            html,
            _addActionUri(101),
            expectedUserId: 42,
            expectedThreadId: 101,
        );

        expect(form.actionUri.queryParameters, isNot(contains('formhash')));
        expect(form.fields['formhash'], 'field-secret');
        expect(
            () => parser.parseActionForm(
                html,
                Uri.parse(
                    'http://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&type=thread&id=101&mobile=2',
                ),
                expectedUserId: 42,
                expectedThreadId: 101,
            ),
            throwsA(isA<ForumActionSecurityException>()),
        );
        expect(
            () => parser.parseActionForm(
                html,
                _addActionUri(102),
                expectedUserId: 42,
                expectedThreadId: 101,
            ),
            throwsA(isA<ForumActionSecurityException>()),
        );
    });

    test('动作表单拒绝重复、数组别名和冲突路由目标载荷', ()
    {
        const String prefix = '''
            <html><head><script>var discuz_uid = '42';</script></head><body>
            <form method="post" action="home.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=101&amp;mobile=2">
                <input type="hidden" name="favoritesubmit" value="true" />
                <input type="hidden" name="formhash" value="hash" />
        ''';
        const String suffix = '</form></body></html>';
        for (final String malicious in const <String>[
            '<input type="hidden" name="formhash" value="second" />',
            '<input type="hidden" name="formhash[x]" value="second" />',
            '<input type="hidden" name="uid[]" value="7" />',
            '<input type="hidden" name="referer[x]" value="evil" />',
            '<input type="hidden" name="action" value="delete" />',
            '<input type="hidden" name="op" value="delete" />',
            '<input type="hidden" name="favid" value="999" />',
            '<input type="hidden" name="id" value="999" />',
            '<input type="hidden" name="deletesubmit" value="true" />',
        ])
        {
            expect(
                () => parser.parseActionForm(
                    '$prefix$malicious$suffix',
                    _addActionUri(101),
                    expectedUserId: 42,
                    expectedThreadId: 101,
                ),
                throwsA(anyOf(
                    isA<ForumActionSecurityException>(),
                    isA<ForumParseException>(),
                )),
                reason: malicious,
            );
        }
        expect(
            () => parser.parseActionForm(
                '$prefix$suffix',
                Uri.parse(
                    '${_addActionUri(101)}&action%5B%5D=delete',
                ),
                expectedUserId: 42,
                expectedThreadId: 101,
            ),
            throwsA(isA<ForumActionSecurityException>()),
        );
        expect(
            () => parser.parseActionForm(
                '''
                <html><head><script>var discuz_uid = '42';</script></head><body>
                <form method="post" action="home.php?mod=spacecp&amp;ac=favorite&amp;op=delete&amp;favid=71&amp;type=forum&amp;mobile=2">
                    <input type="hidden" name="deletesubmit" value="true" />
                    <input type="hidden" name="formhash" value="hash" />
                </form></body></html>
                ''',
                Uri.parse('${_deleteActionUri(71)}&type=forum'),
                expectedUserId: 42,
                expectedFavoriteId: 71,
            ),
            throwsA(isA<ForumActionSecurityException>()),
        );
    });

    test('提交最终页必须保留移动路由和当前 uid', ()
    {
        const String currentIdentity = '''
            <html><head><script>var discuz_uid = '42';</script></head>
            <body class="pg_space"></body></html>
        ''';
        parser.ensureSubmissionSession(
            currentIdentity,
            _addActionUri(101),
            expectedUserId: 42,
            expectedThreadId: 101,
        );

        expect(
            () => parser.ensureSubmissionSession(
                currentIdentity.replaceFirst(
                    "discuz_uid = '42'",
                    "discuz_uid = '7'",
                ),
                _addActionUri(101),
                expectedUserId: 42,
                expectedThreadId: 101,
            ),
            throwsA(isA<ForumSessionExpiredException>()),
        );
        expect(
            () => parser.ensureSubmissionSession(
                currentIdentity,
                Uri.parse(
                    'https://bbs.yamibo.com/member.php?mod=logging&mobile=2',
                ),
                expectedUserId: 42,
                expectedThreadId: 101,
            ),
            throwsA(isA<ForumActionSecurityException>()),
        );
    });
}

Uri _metadataUri(int threadId)
{
    return Uri.parse(
        'https://bbs.yamibo.com/api/mobile/index.php?version=4&module=viewthread&tid=$threadId',
    );
}

Uri _addActionUri(int threadId)
{
    return Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&type=thread&id=$threadId&mobile=2',
    );
}

Uri _deleteActionUri(int favoriteId)
{
    return Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&op=delete&favid=$favoriteId&mobile=2',
    );
}
