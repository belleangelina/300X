import 'dart:io';

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
        if (_client.hasPendingWebIdentity)
        {
            try
            {
                return await completeWebLogin();
            }
            on ForumConnectionException
            {
                return const AuthState.unauthenticated(
                    message: '网页登录状态待确认，请联网后重试',
                );
            }
        }
        if (credentials == null &&
            !await _client.hasPotentialLoginSession())
        {
            return const AuthState.unauthenticated();
        }
        final _SessionIdentity? session;
        try
        {
            session = await _readValidSession();
        }
        on ForumConnectionException
        {
            if (credentials != null && credentials.userId > 0)
            {
                await _activateSession(credentials.userId);
                return AuthState.authenticated(
                    credentials.username,
                    userId: credentials.userId,
                );
            }
            return const AuthState.unauthenticated(
                message: '暂时无法连接论坛，请检查网络后重试登录',
            );
        }
        if (session != null)
        {
            await _activateSession(session.userId);
            String username = '已登录';
            if (credentials != null &&
                (credentials.userId == 0 ||
                    credentials.userId == session.userId))
            {
                username = credentials.username;
                if (credentials.userId == 0)
                {
                    await _credentialStore.write(StoredCredentials(
                        username: credentials.username,
                        password: credentials.password,
                        userId: session.userId,
                    ));
                }
            }
            else if (credentials != null)
            {
                await _credentialStore.clear();
            }
            return AuthState.authenticated(
                username,
                userId: session.userId,
                avatarUri: session.avatarUri,
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
            AuthPageParser.requireLoginPageUri(response.realUri);
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
                await _activateSession(session.userId);
                await _credentialStore.write(
                    StoredCredentials(
                        username: username,
                        password: password,
                        userId: session.userId,
                    ),
                );
                return AuthState.authenticated(
                    username,
                    userId: session.userId,
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
            return _captchaState(form, response.realUri);
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

        try
        {
            AuthPageParser.requireLoginActionUri(form.action);
        }
        on ForumParseException catch (error)
        {
            return _webFallbackState(error.message);
        }
        final postResponse = await _client.postForm(
            form.action,
            fields: fields,
            referer: response.realUri.toString(),
        );
        final ParsedAuthPage resultPage;
        try
        {
            AuthPageParser.requireForumOrigin(
                postResponse.realUri,
                label: '论坛登录结果页',
            );
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
        int? userId = _parser.currentUserId(postResponse.data ?? '');
        _SessionIdentity? session;
        if (!resultPage.loggedIn || avatarUri == null || userId == null)
        {
            try
            {
                session = await _readValidSession();
                avatarUri ??= session?.avatarUri;
                userId ??= session?.userId;
            }
            on ForumConnectionException
            {
                if (!resultPage.loggedIn)
                {
                    rethrow;
                }
            }
        }
        if ((userId ?? 0) > 0)
        {
            await _activateSession(userId ?? 0);
            await _credentialStore.write(
                StoredCredentials(
                    username: username.trim(),
                    password: password,
                    userId: userId ?? 0,
                ),
            );
            return AuthState.authenticated(
                username.trim(),
                userId: userId ?? 0,
                avatarUri: avatarUri,
            );
        }

        if (resultPage.loggedIn)
        {
            return const AuthState.unauthenticated(
                message: '无法确认论坛账号身份，请重新登录',
                webFallbackAvailable: true,
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
        AuthPageParser.requireLoginPageUri(response.realUri);
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

    Future<AuthState> completeWebLogin({
        List<Cookie>? cookies,
        int? expectedIdentityGeneration,
        ForumWebSessionTransitionReservation? reservation,
    }) async
    {
        if (cookies != null)
        {
            return _client.transitionWebSession<AuthState>(
                cookies: cookies,
                verify: _verifyPendingWebSession,
                expectedIdentityGeneration: expectedIdentityGeneration,
                reservation: reservation,
            );
        }
        if (_client.hasPendingWebIdentity)
        {
            return _client.resumePendingWebSession<AuthState>(
                verify: _verifyPendingWebSession,
            );
        }
        final _SessionIdentity? session = await _readValidSession();
        if (session != null)
        {
            await _activateSession(session.userId);
            final StoredCredentials? credentials =
                await _credentialStore.read();
            if (credentials != null &&
                credentials.userId != session.userId)
            {
                await _credentialStore.clear();
            }
            return AuthState.authenticated(
                '已登录',
                userId: session.userId,
                avatarUri: session.avatarUri,
            );
        }
        await _credentialStore.clear();
        await _client.clearSession();
        return const AuthState.unauthenticated(
            message: '未检测到登录状态，请重试',
            webFallbackAvailable: true,
        );
    }

    Future<ForumWebSessionVerification<AuthState>>
        _verifyPendingWebSession() async
    {
        final _SessionIdentity? session = await _readValidSession();
        if (session != null)
        {
            final StoredCredentials? credentials =
                await _credentialStore.read();
            if (credentials != null &&
                credentials.userId != session.userId)
            {
                await _credentialStore.clear();
            }
            return ForumWebSessionVerification<AuthState>(
                userId: session.userId,
                value: AuthState.authenticated(
                    '已登录',
                    userId: session.userId,
                    avatarUri: session.avatarUri,
                ),
            );
        }
        await _credentialStore.clear();
        return const ForumWebSessionVerification<AuthState>(
            userId: 0,
            value: AuthState.unauthenticated(
                message: '未检测到登录状态，请重试',
                webFallbackAvailable: true,
            ),
        );
    }

    Future<void> _activateSession(int userId)
    {
        return _client.activateAccount(
            userId,
            migrateCurrentCookies: _client.activeUserId != userId,
        );
    }

    Future<_SessionIdentity?> _readValidSession() async
    {
        final response = await _client.getText(
            verificationUri,
            retryCount: 1,
        );
        AuthPageParser.requireVerificationUri(response.realUri);
        final String html = response.data ?? '';
        if (!_parser.isForumPage(html))
        {
            return null;
        }
        final int? userId = _parser.currentUserId(html);
        if (userId == null)
        {
            return null;
        }
        return _SessionIdentity(
            userId: userId,
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
        AuthPageParser.requireLoginPageUri(referer);
        AuthPageParser.requireLoginActionUri(form.action);
        AuthPageParser.requireCaptchaUri(form.captchaImage!);
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
    const _SessionIdentity({
        required this.userId,
        required this.avatarUri,
    });

    final int userId;
    final Uri? avatarUri;
}
