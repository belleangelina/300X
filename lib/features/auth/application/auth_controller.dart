import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/features/auth/data/auth_repository.dart';
import 'package:x300/features/auth/domain/auth_models.dart';

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
        (Ref ref)
        {
            throw UnimplementedError(
                'AuthRepository must be overridden at startup.',
            );
        },
    );

final AsyncNotifierProvider<AuthController, AuthState>
    authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

final Provider<Uri?> currentUserAvatarUriProvider = Provider<Uri?>(
    (Ref ref) => ref.watch(authControllerProvider).value?.avatarUri,
);

class AuthController extends AsyncNotifier<AuthState>
{
    AuthRepository get _repository => ref.read(authRepositoryProvider);

    @override
    Future<AuthState> build()
    {
        return _repository.restoreSession();
    }

    Future<void> login({
        required String username,
        required String password,
        String captcha = '',
    }) async
    {
        state = const AsyncLoading<AuthState>();
        state = await AsyncValue.guard<AuthState>(
            () => _repository.login(
                username: username,
                password: password,
                captcha: captcha,
            ),
        );
    }

    Future<void> refreshCaptcha() async
    {
        state = const AsyncLoading<AuthState>();
        state = await AsyncValue.guard<AuthState>(
            _repository.refreshCaptcha,
        );
    }

    Future<void> completeWebLogin() async
    {
        state = const AsyncLoading<AuthState>();
        state = await AsyncValue.guard<AuthState>(
            _repository.completeWebLogin,
        );
    }

    Future<void> logout() async
    {
        state = const AsyncLoading<AuthState>();
        await _repository.logout();
        state = const AsyncData<AuthState>(AuthState.unauthenticated());
    }
}
