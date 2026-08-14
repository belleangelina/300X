import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_page_classifier.dart';

void main()
{
    const ForumOriginPolicy policy = ForumOriginPolicy();
    const ForumPageClassifier classifier = ForumPageClassifier();

    group('ForumOriginPolicy', ()
    {
        test('仅允许论坛同源 HTTPS', ()
        {
            expect(
                policy.isAllowed(Uri.parse('https://bbs.yamibo.com/forum.php')),
                isTrue,
            );
            expect(
                policy.isAllowed(Uri.parse('http://bbs.yamibo.com/forum.php')),
                isFalse,
            );
            expect(
                policy.isAllowed(Uri.parse('https://evil.example/forum.php')),
                isFalse,
            );
            expect(
                policy.isAllowed(
                    Uri.parse('https://user@bbs.yamibo.com/forum.php'),
                ),
                isFalse,
            );
        });

        test('移动读取链接必须自带 mobile=2', ()
        {
            final Uri source = Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=30&mobile=2',
            );
            expect(
                policy.resolveMobile(
                    source,
                    'forum.php?mod=forumdisplay&fid=30&page=2&mobile=2',
                ),
                isNotNull,
            );
            expect(
                policy.resolveMobile(
                    source,
                    'forum.php?mod=forumdisplay&fid=30&page=2',
                ),
                isNull,
            );
            expect(
                policy.resolveMobile(
                    source,
                    'forum.php?mod=forumdisplay&fid=30&mobile=2&mobile=2',
                ),
                isNull,
            );
            expect(
                policy.resolveAllowed(
                    source,
                    'home.php?mod=spacecp&ac=favorite&id=30',
                ),
                isNotNull,
            );
        });
    });

    group('ForumPageClassifier', ()
    {
        final Uri boardUri = Uri.parse(
            'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=30&mobile=2',
        );

        test('识别移动版块页', ()
        {
            final ForumPageClassification result = classifier.classify(
                '<html><body id="forum" class="pg_forumdisplay"></body></html>',
                boardUri,
            );

            expect(result.kind, ForumMobilePageKind.board);
        });

        test('登录页明确报告会话失效', ()
        {
            expect(
                () => classifier.classify(
                    '<html><body class="pg_logging">'
                    '<form id="loginform"></form></body></html>',
                    boardUri,
                ),
                throwsA(isA<ForumSessionExpiredException>()),
            );
        });

        test('拒绝伪装 mobile=2 的电脑版回退', ()
        {
            expect(
                () => classifier.classify(
                    '<html><body id="nv_forum" class="pg_forumdisplay">'
                    '<div id="hd"></div></body></html>',
                    boardUri,
                ),
                throwsA(
                    isA<ForumParseException>().having(
                        (ForumParseException value) => value.message,
                        'message',
                        contains('电脑版'),
                    ),
                ),
            );
        });

        test('拒绝缺少 mobile=2 的有效版块标识', ()
        {
            expect(
                () => classifier.classify(
                    '<html><body id="forum" class="pg_forumdisplay"></body></html>',
                    Uri.parse(
                        'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=30',
                    ),
                ),
                throwsA(isA<ForumParseException>()),
            );
        });
    });
}
