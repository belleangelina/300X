import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/credential_store.dart';
import 'package:x300/features/auth/data/auth_repository.dart';
import 'package:x300/features/auth/domain/auth_models.dart';

class _MockForumClient extends Mock implements ForumClient
{
}

class _MockCredentialStore extends Mock implements CredentialStore
{
}

void main()
{
    registerFallbackValue(
        const StoredCredentials(username: 'fallback', password: 'fallback'),
    );

    late _MockForumClient client;
    late _MockCredentialStore credentials;
    late AuthRepository repository;

    setUp(()
    {
        client = _MockForumClient();
        credentials = _MockCredentialStore();
        repository = AuthRepository(client, credentials);
        when(
            () => client.getText(
                AuthRepository.verificationUri,
                retryCount: 1,
            ),
        ).thenThrow(const ForumConnectionException('离线'));
    });

    test('已成功保存凭据时离线启动可进入本地界面', () async
    {
        when(credentials.read).thenAnswer(
            (_) async => const StoredCredentials(
                username: 'offline-user',
                password: 'saved-after-success',
            ),
        );

        final AuthState state = await repository.restoreSession();

        expect(state.status, AuthStatus.authenticated);
        expect(state.username, 'offline-user');
    });

    test('从未成功登录时连接失败仍进入登录页', () async
    {
        when(credentials.read).thenAnswer((_) async => null);

        final AuthState state = await repository.restoreSession();

        expect(state.status, AuthStatus.unauthenticated);
        expect(state.message, '暂时无法连接论坛，请检查网络后重试登录');
    });

    test('恢复有效会话时带回当前账号头像', () async
    {
        when(credentials.read).thenAnswer(
            (_) async => const StoredCredentials(
                username: 'avatar-user',
                password: 'saved-password',
            ),
        );
        when(
            () => client.getText(
                AuthRepository.verificationUri,
                retryCount: 1,
            ),
        ).thenAnswer((_) async => _response(
            '''
                <html>
                    <head>
                        <script>var discuz_uid = '471581';</script>
                    </head>
                    <body id="forum" class="pg_forumdisplay"></body>
                </html>
            ''',
            AuthRepository.verificationUri,
        ));

        final AuthState state = await repository.restoreSession();

        expect(state.status, AuthStatus.authenticated);
        expect(state.username, 'avatar-user');
        expect(
            state.avatarUri.toString(),
            'https://bbs.yamibo.com/uc_server/avatar.php?uid=471581&size=middle',
        );
    });

    test('无法解析登录挑战时只提供 WebView 兜底状态', () async
    {
        when(
            () => client.getText(
                AuthRepository.loginUri,
                retryCount: 1,
            ),
        ).thenAnswer((_) async => Response<String>(
            requestOptions: RequestOptions(
                path: AuthRepository.loginUri.toString(),
            ),
            data: '''
                <html><body>
                    <form id="loginform" action="javascript:void(0)">
                        <div class="slider-challenge"></div>
                    </form>
                </body></html>
            ''',
        ));

        final AuthState state = await repository.login(
            username: 'user',
            password: 'password',
        );

        expect(state.status, AuthStatus.unauthenticated);
        expect(state.webFallbackAvailable, isTrue);
        expect(state.message, contains('账号或密码字段'));
        verifyNever(
            () => client.postForm(
                any(),
                fields: any(named: 'fields'),
            ),
        );
    });

    test('WebView Cookie 同步后仍由受限版块确认登录', () async
    {
        when(
            () => client.getText(
                AuthRepository.verificationUri,
                retryCount: 1,
            ),
        ).thenAnswer((_) async => Response<String>(
            requestOptions: RequestOptions(
                path: AuthRepository.verificationUri.toString(),
            ),
            data: '''
                <html><head>
                    <script>var discuz_uid = '471581';</script>
                </head><body id="forum" class="pg_forumdisplay">
                    <div class="threadlist"></div>
                </body></html>
            ''',
        ));

        final AuthState state = await repository.completeWebLogin();

        expect(state.status, AuthStatus.authenticated);
        expect(state.avatarUri, isNotNull);
    });

    test('WebView 登录状态未同步时显示精简提示', () async
    {
        when(
            () => client.getText(
                AuthRepository.verificationUri,
                retryCount: 1,
            ),
        ).thenAnswer((_) async => _response(
            '<html><body><form id="loginform"></form></body></html>',
            AuthRepository.verificationUri,
        ));

        final AuthState state = await repository.completeWebLogin();

        expect(state.status, AuthStatus.unauthenticated);
        expect(state.message, '未检测到登录状态，请重试');
    });

    test('账号密码错误后只提交一次且不保存凭据', () async
    {
        final Uri action = ForumClient.baseUri.resolve(
            'member.php?mod=logging&action=login&loginsubmit=yes&mobile=2',
        );
        when(
            () => client.getText(
                AuthRepository.loginUri,
                retryCount: 1,
            ),
        ).thenAnswer((_) async => _response(
            _loginForm(action: action, formHash: 'first-hash'),
            AuthRepository.loginUri,
        ));
        when(
            () => client.postForm(
                action,
                fields: any(named: 'fields'),
                referer: AuthRepository.loginUri.toString(),
            ),
        ).thenAnswer((_) async => _response(
            '${_loginForm(action: action, formHash: 'second-hash')}'
            '<div class="tip">密码错误</div>',
            action,
        ));
        when(
            () => client.getText(
                AuthRepository.verificationUri,
                retryCount: 1,
            ),
        ).thenAnswer((_) async => _response(
            '<html><body><form id="loginform"></form></body></html>',
            AuthRepository.verificationUri,
        ));

        final AuthState state = await repository.login(
            username: 'wrong-user',
            password: 'wrong-password',
        );

        expect(state.status, AuthStatus.unauthenticated);
        expect(state.message, '密码错误');
        verify(
            () => client.postForm(
                action,
                fields: any(named: 'fields'),
                referer: AuthRepository.loginUri.toString(),
            ),
        ).called(1);
        verifyNever(() => credentials.write(any()));
    });

    test('刷新验证码复用客户端并读取新的图片挑战', () async
    {
        final Uri action = ForumClient.baseUri.resolve(
            'member.php?mod=logging&action=login&mobile=2',
        );
        final Uri image = ForumClient.baseUri.resolve(
            'misc.php?mod=seccode&update=2',
        );
        when(
            () => client.getText(
                AuthRepository.loginUri,
                retryCount: 1,
            ),
        ).thenAnswer((_) async => _response(
            _captchaForm(
                action: action,
                formHash: 'refreshed-hash',
                image: image,
            ),
            AuthRepository.loginUri,
        ));
        when(
            () => client.getBytes(
                image,
                referer: AuthRepository.loginUri.toString(),
            ),
        ).thenAnswer(
            (_) async => Uint8List.fromList(<int>[8, 6, 7, 5]),
        );

        final AuthState state = await repository.refreshCaptcha();

        expect(state.status, AuthStatus.captchaRequired);
        expect(state.captcha!.imageBytes, <int>[8, 6, 7, 5]);
        verify(
            () => client.getBytes(
                image,
                referer: AuthRepository.loginUri.toString(),
            ),
        ).called(1);
    });

    test('Cookie 失效后使用已保存凭据安全重登', () async
    {
        final Uri action = ForumClient.baseUri.resolve(
            'member.php?mod=logging&action=login&loginsubmit=yes&mobile=2',
        );
        when(credentials.read).thenAnswer(
            (_) async => const StoredCredentials(
                username: 'saved-user',
                password: 'saved-password',
            ),
        );
        when(
            () => client.getText(
                AuthRepository.verificationUri,
                retryCount: 1,
            ),
        ).thenAnswer((_) async => _response(
            '<html><body><form id="loginform"></form></body></html>',
            AuthRepository.verificationUri,
        ));
        when(
            () => client.getText(
                AuthRepository.loginUri,
                retryCount: 1,
            ),
        ).thenAnswer((_) async => _response(
            _loginForm(action: action, formHash: 'restored-hash'),
            AuthRepository.loginUri,
        ));
        when(
            () => client.postForm(
                action,
                fields: any(named: 'fields'),
                referer: AuthRepository.loginUri.toString(),
            ),
        ).thenAnswer((_) async => _response(
            '<html><body>'
            '<a href="member.php?mod=logging&action=logout">退出</a>'
            '</body></html>',
            action,
        ));
        when(() => credentials.write(any())).thenAnswer((_) async {});

        final AuthState state = await repository.restoreSession();

        expect(state.status, AuthStatus.authenticated);
        expect(state.username, 'saved-user');
        final StoredCredentials stored = verify(
            () => credentials.write(captureAny()),
        ).captured.single as StoredCredentials;
        expect(stored.username, 'saved-user');
        expect(stored.password, 'saved-password');
        verify(
            () => client.postForm(
                action,
                fields: any(named: 'fields'),
                referer: AuthRepository.loginUri.toString(),
            ),
        ).called(1);
    });

    test('退出依次清理凭据和论坛 Cookie', () async
    {
        when(credentials.clear).thenAnswer((_) async {});
        when(client.clearSession).thenAnswer((_) async {});

        await repository.logout();

        verifyInOrder(<dynamic Function()>[
            () => credentials.clear(),
            () => client.clearSession(),
        ]);
    });
}

Response<String> _response(String html, Uri uri)
{
    return Response<String>(
        requestOptions: RequestOptions(path: uri.toString()),
        data: html,
    );
}

String _loginForm({required Uri action, required String formHash})
{
    return '''
        <html><body>
            <form id="loginform" action="$action">
                <input type="hidden" name="formhash" value="$formHash" />
                <input type="text" name="username" />
                <input type="password" name="password" />
            </form>
        </body></html>
    ''';
}

String _captchaForm({
    required Uri action,
    required String formHash,
    required Uri image,
})
{
    return '''
        <html><body>
            <form id="loginform" action="$action">
                <input type="hidden" name="formhash" value="$formHash" />
                <input type="hidden" name="seccodehash" value="challenge" />
                <input type="text" name="username" />
                <input type="password" name="password" />
                <input type="text" name="seccodeverify" />
                <img src="$image" />
            </form>
        </body></html>
    ''';
}
