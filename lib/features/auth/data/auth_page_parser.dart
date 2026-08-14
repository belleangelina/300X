import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/domain/auth_models.dart';

class AuthPageParser
{
    const AuthPageParser();

    static const String _forumHost = 'bbs.yamibo.com';

    static void requireForumOrigin(
        Uri uri, {
        String label = '论坛认证页面',
    })
    {
        if (uri.scheme != 'https' ||
            uri.host != _forumHost ||
            uri.port != 443 ||
            uri.userInfo.isNotEmpty ||
            uri.fragment.isNotEmpty)
        {
            throw ForumParseException('$label地址不安全');
        }
    }

    static void requireLoginPageUri(Uri uri)
    {
        requireForumOrigin(uri, label: '论坛登录页');
        if (uri.path != '/member.php' ||
            !_hasSingleParameter(uri, 'mod', 'logging') ||
            !_hasSingleParameter(uri, 'action', 'login') ||
            !_hasSingleParameter(uri, 'mobile', '2'))
        {
            throw const ForumParseException('论坛登录页地址无效');
        }
    }

    static void requireLoginActionUri(Uri uri)
    {
        requireForumOrigin(uri, label: '论坛登录表单');
        if (uri.path != '/member.php' ||
            !_hasSingleParameter(uri, 'mod', 'logging') ||
            !_hasSingleParameter(uri, 'action', 'login') ||
            !_hasSingleParameter(uri, 'mobile', '2'))
        {
            throw const ForumParseException('论坛登录表单提交地址无效');
        }
    }

    static void requireCaptchaUri(Uri uri)
    {
        requireForumOrigin(uri, label: '论坛验证码');
        final List<String> actions = uri.queryParametersAll['action'] ??
            const <String>[];
        if (uri.path != '/misc.php' ||
            !_hasSingleParameter(uri, 'mod', 'seccode') ||
            (actions.isNotEmpty &&
                (actions.length != 1 || actions.single != 'update')))
        {
            throw const ForumParseException('论坛验证码地址无效');
        }
    }

    static void requireVerificationUri(Uri uri)
    {
        requireForumOrigin(uri, label: '论坛登录验证页');
        if (uri.path != '/forum.php' ||
            !_hasSingleParameter(uri, 'mod', 'forumdisplay') ||
            !_hasSingleParameter(uri, 'fid', '30') ||
            !_hasSingleParameter(uri, 'mobile', '2'))
        {
            throw const ForumParseException('论坛登录验证页地址无效');
        }
    }

    ParsedAuthPage parse(String html, Uri pageUri)
    {
        requireForumOrigin(pageUri);
        final Document document = html_parser.parse(html);
        final bool loggedIn = _isLoggedIn(document, html);
        final String message = _extractMessage(document);
        final Element? formElement = document.querySelector('form#loginform');

        if (formElement == null)
        {
            return ParsedAuthPage(
                loggedIn: loggedIn,
                message: message,
            );
        }

        final String? actionValue = formElement.attributes['action'];
        if (actionValue == null || actionValue.isEmpty)
        {
            throw const ForumParseException('登录表单缺少提交地址');
        }
        final Uri actionUri;
        try
        {
            actionUri = pageUri.resolve(actionValue);
        }
        on FormatException
        {
            throw const ForumParseException('登录表单提交地址无效');
        }
        requireLoginActionUri(actionUri);
        final String method = formElement.attributes['method']?.toLowerCase() ??
            'get';
        if (method != 'post')
        {
            throw const ForumParseException('登录表单提交方式无效');
        }

        final Map<String, String> fields = <String, String>{};
        for (final Element input in formElement.querySelectorAll('input'))
        {
            final String? name = input.attributes['name'];
            if (name == null || name.isEmpty)
            {
                continue;
            }
            final String type = input.attributes['type']?.toLowerCase() ?? '';
            if (type == 'submit' || type == 'button')
            {
                continue;
            }
            fields[name] = input.attributes['value'] ?? '';
        }

        final Element? usernameInput = formElement.querySelector(
            'input[name="username"], input[name="email"], '
            'input[autocomplete="username"]',
        );
        final Element? passwordInput = formElement.querySelector(
            'input[type="password"]',
        );
        if (usernameInput == null || passwordInput == null)
        {
            throw const ForumParseException('登录表单缺少账号或密码字段');
        }

        final Element? captchaInput = formElement.querySelector(
            'input[name*="seccodeverify"], input[name="captcha"], '
            'input[autocomplete="one-time-code"]',
        );
        final Element? captchaImage = formElement.querySelector(
            'img[src*="seccode"], img[src*="captcha"], '
            '[id^="seccode"] img',
        );
        if (captchaInput != null && captchaImage == null)
        {
            throw const ForumParseException('登录验证码结构无效');
        }

        Uri? captchaImageUri;
        final String? captchaSource = captchaImage?.attributes['src'];
        if (captchaSource != null && captchaSource.isNotEmpty)
        {
            try
            {
                captchaImageUri = pageUri.resolve(captchaSource);
            }
            on FormatException
            {
                throw const ForumParseException('论坛验证码地址无效');
            }
            requireCaptchaUri(captchaImageUri);
        }

        return ParsedAuthPage(
            loggedIn: loggedIn,
            message: message,
            form: LoginForm(
                action: actionUri,
                fields: fields,
                usernameField:
                    usernameInput.attributes['name'] ?? 'username',
                passwordField:
                    passwordInput.attributes['name'] ?? 'password',
                captchaField: captchaInput?.attributes['name'],
                captchaImage: captchaImageUri,
            ),
        );
    }

    bool isForumPage(String html)
    {
        final Document document = html_parser.parse(html);
        final Element? body = document.body;
        return body?.id == 'forum' &&
            body?.classes.contains('pg_forumdisplay') == true &&
            document.querySelector('form#loginform') == null;
    }

    Uri? currentUserAvatarUri(String html, Uri pageUri)
    {
        final int? userId = currentUserId(html);
        if (userId != null)
        {
            return pageUri.resolve(
                'uc_server/avatar.php?uid=$userId&size=middle',
            );
        }
        final Match? profileMatch = RegExp(
            r'\buid=([1-9]\d*)&(?:amp;)?do=profile',
        ).firstMatch(html);
        final String? uid = profileMatch?.group(1);
        if (uid == null)
        {
            return null;
        }
        return pageUri.resolve(
            'uc_server/avatar.php?uid=$uid&size=middle',
        );
    }

    int? currentUserId(String html)
    {
        final int? userId = discuzUserId(html);
        return userId != null && userId > 0 ? userId : null;
    }

    int? discuzUserId(String html)
    {
        final Match? match = RegExp(
            r'''\bdiscuz_uid\s*=\s*['"](\d+)['"]''',
        ).firstMatch(html);
        return int.tryParse(match?.group(1) ?? '');
    }

    static bool _hasSingleParameter(Uri uri, String name, String value)
    {
        final List<String> values = uri.queryParametersAll[name] ??
            const <String>[];
        return values.length == 1 && values.single == value;
    }

    bool _isLoggedIn(Document document, String html)
    {
        return document.querySelector(
                    'a[href*="action=logout"], '
                    'a[href*="mod=logging"][href*="logout"]',
                ) !=
                null ||
            html.contains('登录成功') ||
            html.contains('登錄成功') ||
            html.contains('欢迎您回来') ||
            html.contains('歡迎您回來');
    }

    String _extractMessage(Document document)
    {
        final Element? messageElement = document.querySelector(
            '#messagetext, .alert_info, .tip .message, .tip, '
            '.showmessage, .message',
        );
        return messageElement?.text
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim() ??
            '';
    }
}
