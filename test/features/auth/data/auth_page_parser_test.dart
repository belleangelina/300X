import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';

void main()
{
    const AuthPageParser parser = AuthPageParser();
    final Uri loginUri = Uri.parse(
        'https://bbs.yamibo.com/member.php?mod=logging&action=login&mobile=2',
    );

    group('AuthPageParser', ()
    {
        test('解析普通 Discuz 登录表单', ()
        {
            const String html = '''
                <html>
                <body id="member" class="pg_logging">
                    <form id="loginform" method="post"
                        action="member.php?mod=logging&amp;action=login&amp;loginsubmit=yes&amp;loginhash=abc&amp;mobile=2">
                        <input type="hidden" name="formhash" value="hash123" />
                        <input type="hidden" name="referer" value="https://bbs.yamibo.com/" />
                        <input type="hidden" name="fastloginfield" value="username" />
                        <input type="text" name="username" />
                        <input type="password" name="password" />
                    </form>
                </body>
                </html>
            ''';

            final page = parser.parse(html, loginUri);

            expect(page.loggedIn, isFalse);
            expect(page.form, isNotNull);
            expect(page.form!.fields['formhash'], 'hash123');
            expect(page.form!.usernameField, 'username');
            expect(page.form!.passwordField, 'password');
            expect(page.form!.requiresCaptcha, isFalse);
            expect(
                page.form!.action.toString(),
                contains('loginsubmit=yes'),
            );
        });

        test('解析连续失败后出现的图片验证码', ()
        {
            const String html = '''
                <html>
                <body>
                    <div class="tip"><div class="message">请输入验证码</div></div>
                    <form id="loginform" method="post" action="member.php?mod=logging">
                        <input type="hidden" name="formhash" value="newhash" />
                        <input type="hidden" name="seccodehash" value="codehash" />
                        <input type="text" name="username" />
                        <input type="password" name="password" />
                        <input type="text" name="seccodeverify" />
                        <span id="seccode_codehash">
                            <img src="misc.php?mod=seccode&amp;update=1" />
                        </span>
                    </form>
                </body>
                </html>
            ''';

            final page = parser.parse(html, loginUri);

            expect(page.message, '请输入验证码');
            expect(page.form!.requiresCaptcha, isTrue);
            expect(page.form!.captchaField, 'seccodeverify');
            expect(
                page.form!.captchaImage.toString(),
                contains('misc.php?mod=seccode'),
            );
        });

        test('识别登录成功提示', ()
        {
            const String html = '''
                <html><body><div class="tip">欢迎您回来，登录成功</div></body></html>
            ''';

            final page = parser.parse(html, loginUri);

            expect(page.loggedIn, isTrue);
        });

        test('识别已登录的版块页面', ()
        {
            const String html = '''
                <html>
                    <body id="forum" class="pg_forumdisplay">
                        <a href="member.php?mod=logging&amp;action=logout">退出</a>
                        <div class="threadlist"></div>
                    </body>
                </html>
            ''';

            expect(parser.isForumPage(html), isTrue);
        });

        test('登录页不能误判为有效版块', ()
        {
            const String html = '''
                <html>
                    <body id="forum" class="pg_forumdisplay">
                        <form id="loginform"></form>
                    </body>
                </html>
            ''';

            expect(parser.isForumPage(html), isFalse);
        });

        test('从已登录页面提取当前账号头像而不是帖子作者头像', ()
        {
            const String html = '''
                <html>
                    <head>
                        <script>
                            var discuz_uid = '471581';
                        </script>
                    </head>
                    <body id="forum" class="pg_forumdisplay">
                        <img src="uc_server/avatar.php?uid=20112" />
                    </body>
                </html>
            ''';

            expect(
                parser.currentUserAvatarUri(html, loginUri).toString(),
                'https://bbs.yamibo.com/uc_server/avatar.php?uid=471581&size=middle',
            );
        });

        test('访客页面没有当前账号头像', ()
        {
            const String html = '''
                <html><body><img src="avatar/post-owner.jpg" /></body></html>
            ''';

            expect(parser.currentUserAvatarUri(html, loginUri), isNull);
        });
    });
}
