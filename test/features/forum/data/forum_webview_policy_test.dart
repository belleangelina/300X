import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_webview_policy.dart';

void main()
{
    const ForumWebViewPolicy policy = ForumWebViewPolicy();

    test('只允许已登记的百合会 HTTPS 移动入口', ()
    {
        expect(
            policy.isRegisteredInitialUri(Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1&mobile=2',
            )),
            isTrue,
        );
        expect(
            policy.isRegisteredInitialUri(Uri.parse(
                'https://bbs.yamibo.com/home.php?mod=space&do=pm&mobile=2',
            )),
            isTrue,
        );
        expect(
            policy.isRegisteredInitialUri(Uri.parse(
                'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=1',
            )),
            isFalse,
        );
        expect(
            policy.isRegisteredInitialUri(Uri.parse(
                'https://bbs.yamibo.com/unknown.php?mobile=2',
            )),
            isFalse,
        );
    });

    test('导航阻止降级、外域、userinfo、mobile=no 和重复模式', ()
    {
        final List<Uri> rejected = <Uri>[
            Uri.parse('http://bbs.yamibo.com/forum.php?mobile=2'),
            Uri.parse('https://evil.example/forum.php?mobile=2'),
            Uri.parse('https://bbs.yamibo.com.evil.example/forum.php?mobile=2'),
            Uri.parse('https://user@bbs.yamibo.com/forum.php?mobile=2'),
            Uri.parse('https://bbs.yamibo.com:444/forum.php?mobile=2'),
            Uri.parse('https://bbs.yamibo.com/forum.php?mobile=no'),
            Uri.parse('https://bbs.yamibo.com/forum.php?mobile=2&mobile=2'),
        ];
        for (final Uri uri in rejected)
        {
            expect(policy.isAllowedNavigation(uri), isFalse, reason: '$uri');
        }
    });

    test('同源移动流程可跟随无 mobile 跳转和 SEO 路由', ()
    {
        expect(
            policy.isAllowedNavigation(Uri.parse(
                'https://bbs.yamibo.com/member.php?mod=logging&action=login',
            )),
            isTrue,
        );
        expect(
            policy.isAllowedNavigation(Uri.parse(
                'https://bbs.yamibo.com/thread-123-1-1.html#pid9',
            )),
            isTrue,
        );
    });

    test('非法初始入口 fail closed', ()
    {
        expect(
            () => policy.requireRegisteredInitialUri(
                Uri.parse('https://evil.example/forum.php?mobile=2'),
            ),
            throwsA(isA<ForumActionSecurityException>()),
        );
    });
}
