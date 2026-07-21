import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/domain/auth_models.dart';

class AuthPageParser
{
    const AuthPageParser();

    ParsedAuthPage parse(String html, Uri pageUri)
    {
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

        Uri? captchaImageUri;
        final String? captchaSource = captchaImage?.attributes['src'];
        if (captchaSource != null && captchaSource.isNotEmpty)
        {
            captchaImageUri = pageUri.resolve(captchaSource);
        }

        return ParsedAuthPage(
            loggedIn: loggedIn,
            message: message,
            form: LoginForm(
                action: pageUri.resolve(actionValue),
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
        final Match? scriptMatch = RegExp(
            r'''\bdiscuz_uid\s*=\s*['"]([1-9]\d*)['"]''',
        ).firstMatch(html);
        final Match? profileMatch = RegExp(
            r'\buid=([1-9]\d*)&(?:amp;)?do=profile',
        ).firstMatch(html);
        final String? uid = (scriptMatch ?? profileMatch)?.group(1);
        if (uid == null)
        {
            return null;
        }
        return pageUri.resolve(
            'uc_server/avatar.php?uid=$uid&size=middle',
        );
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
