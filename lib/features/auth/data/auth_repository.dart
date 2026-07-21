import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/credential_store.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';
import 'package:x300/features/auth/domain/auth_models.dart';

class AuthRepository
{
    AuthRepository(
        this._client,
        this._credentialStore, [
        this._parser = const AuthPageParser(),
    ]);

    static final Uri loginUri = ForumClient.baseUri.resolve(
        'member.php?mod=logging&action=login&mobile=2',
    );
    static final Uri verificationUri = ForumClient.baseUri.resolve(
        'forum.php?mod=forumdisplay&fid=30&mobile=2',
    );

    final ForumClient _client;
    final CredentialStore _credentialStore;
    final AuthPageParser _parser;

    Future<AuthState> restoreSession() async
    {
        final StoredCredentials? credentials =
            await _credentialStore.read();
        try
        {
            final _SessionIdentity? session = await _readValidSession();
            if (session != null)
            {
                return AuthState.authenticated(
                    credentials?.username ?? '已登录',
                    avatarUri: session.avatarUri,
                );
            }
        }
        on ForumConnectionException
        {
            if (credentials != null)
            {
                return AuthState.authenticated(credentials.username);
            }
            return const AuthState.unauthenticated(
                message: '暂时无法连接论坛，请检查网络后重试登录',
            );
        }
        if (credentials == null)
        {
            return const AuthState.unauthenticated();
        }
        return login(
            username: credentials.username,
            password: credentials.password,
        );
    }

    Future<AuthState> login({
        required String username,
        required String password,
        String captcha = '',
    }) async
    {
        final response = await _client.getText(loginUri, retryCount: 1);
        final ParsedAuthPage page;
        try
        {
            page = _parser.parse(
                response.data ?? '',
                response.realUri,
            );
        }
        on ForumParseException catch (error)
        {
            return _webFallbackState(error.message);
        }
        final LoginForm? form = page.form;
        if (form == null)
        {
            final _SessionIdentity? session = page.loggedIn
                ? await _readValidSession()
                : null;
            if (session != null)
            {
                await _credentialStore.write(
                    StoredCredentials(
                        username: username,
                        password: password,
                    ),
                );
                return AuthState.authenticated(
                    username,
                    avatarUri: session.avatarUri,
                );
            }
            return AuthState.unauthenticated(
                message: page.message.isEmpty
                    ? '无法读取论坛登录表单'
                    : page.message,
                webFallbackAvailable: true,
            );
        }

        if (form.requiresCaptcha && captcha.trim().isEmpty)
        {
            return _captchaState(form, loginUri);
        }

        final Map<String, dynamic> fields = <String, dynamic>{
            ...form.fields,
            form.usernameField: username.trim(),
            form.passwordField: password,
            'submit': 'true',
        };
        if (form.captchaField != null)
        {
            fields[form.captchaField!] = captcha.trim();
        }

        final postResponse = await _client.postForm(
            form.action,
            fields: fields,
            referer: loginUri.toString(),
        );
        final ParsedAuthPage resultPage;
        try
        {
            resultPage = _parser.parse(
                postResponse.data ?? '',
                postResponse.realUri,
            );
        }
        on ForumParseException catch (error)
        {
            return _webFallbackState(error.message);
        }

        Uri? avatarUri = _parser.currentUserAvatarUri(
            postResponse.data ?? '',
            postResponse.realUri,
        );
        _SessionIdentity? session;
        if (!resultPage.loggedIn || avatarUri == null)
        {
            try
            {
                session = await _readValidSession();
                avatarUri ??= session?.avatarUri;
            }
            on ForumConnectionException
            {
                if (!resultPage.loggedIn)
                {
                    rethrow;
                }
            }
        }
        if (resultPage.loggedIn || session != null)
        {
            await _credentialStore.write(
                StoredCredentials(
                    username: username.trim(),
                    password: password,
                ),
            );
            return AuthState.authenticated(
                username.trim(),
                avatarUri: avatarUri,
            );
        }

        if (resultPage.form?.requiresCaptcha == true)
        {
            return _captchaState(
                resultPage.form!,
                postResponse.realUri,
                message: resultPage.message,
            );
        }

        return AuthState.unauthenticated(
            message: resultPage.message.isEmpty
                ? '登录失败，请检查账号和密码'
                : resultPage.message,
        );
    }

    Future<AuthState> refreshCaptcha() async
    {
        final response = await _client.getText(loginUri, retryCount: 1);
        final ParsedAuthPage page = _parser.parse(
            response.data ?? '',
            response.realUri,
        );
        final LoginForm? form = page.form;
        if (form?.requiresCaptcha != true)
        {
            return const AuthState.unauthenticated(
                message: '当前登录不再需要验证码，请重新提交',
            );
        }
        return _captchaState(form!, response.realUri);
    }

    Future<void> logout() async
    {
        await _credentialStore.clear();
        await _client.clearSession();
    }

    Future<AuthState> completeWebLogin() async
    {
        final _SessionIdentity? session = await _readValidSession();
        if (session != null)
        {
            return AuthState.authenticated(
                '已登录',
                avatarUri: session.avatarUri,
            );
        }
        return const AuthState.unauthenticated(
            message: '未检测到登录状态，请重试',
            webFallbackAvailable: true,
        );
    }

    Future<_SessionIdentity?> _readValidSession() async
    {
        final response = await _client.getText(
            verificationUri,
            retryCount: 1,
        );
        final String html = response.data ?? '';
        if (!_parser.isForumPage(html))
        {
            return null;
        }
        return _SessionIdentity(
            avatarUri: _parser.currentUserAvatarUri(
                html,
                response.realUri,
            ),
        );
    }

    Future<AuthState> _captchaState(
        LoginForm form,
        Uri referer, {
        String message = '',
    }) async
    {
        final imageBytes = await _client.getBytes(
            form.captchaImage!,
            referer: referer.toString(),
        );
        return AuthState.captchaRequired(
            captcha: CaptchaChallenge(imageBytes: imageBytes),
            message: message.isEmpty ? '请输入验证码后重试' : message,
        );
    }

    AuthState _webFallbackState(String message)
    {
        return AuthState.unauthenticated(
            message: message.isEmpty
                ? '论坛返回了无法识别的登录挑战'
                : message,
            webFallbackAvailable: true,
        );
    }
}

class _SessionIdentity
{
    const _SessionIdentity({required this.avatarUri});

    final Uri? avatarUri;
}
