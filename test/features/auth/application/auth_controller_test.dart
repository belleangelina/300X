import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_repository.dart';
import 'package:x300/features/auth/domain/auth_models.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  test('网页登录身份复核异常会向页面传播且保留错误状态', () async {
    final _MockAuthRepository repository = _MockAuthRepository();
    when(repository.restoreSession).thenAnswer(
      (_) async => const AuthState.unauthenticated(),
    );
    when(repository.completeWebLogin).thenThrow(
      const ForumConnectionException('身份复核失败'),
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    await expectLater(
      container.read(authControllerProvider.notifier).completeWebLogin(),
      throwsA(isA<ForumConnectionException>()),
    );

    expect(container.read(authControllerProvider).hasError, isTrue);
  });

  test('网页登录身份复核成功会把结果返回调用页面', () async {
    final _MockAuthRepository repository = _MockAuthRepository();
    when(repository.restoreSession).thenAnswer(
      (_) async => const AuthState.unauthenticated(),
    );
    when(repository.completeWebLogin).thenAnswer(
      (_) async => const AuthState.authenticated('已登录', userId: 42),
    );
    final ProviderContainer container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);

    final AuthState result = await container
        .read(authControllerProvider.notifier)
        .completeWebLogin();

    expect(result.status, AuthStatus.authenticated);
    expect(result.userId, 42);
  });
}
