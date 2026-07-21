import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/storage/credential_store.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_repository.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';

class AppDependencies
{
    AppDependencies._({
        required this.client,
        required this.credentialStore,
        required this.authRepository,
        required this.settingsRepository,
    });

    final ForumClient client;
    final CredentialStore credentialStore;
    final AuthRepository authRepository;
    final AppSettingsRepository settingsRepository;

    Widget buildScope(Widget child)
    {
        return ProviderScope(
            overrides: [
                forumClientProvider.overrideWithValue(client),
                credentialStoreProvider.overrideWithValue(credentialStore),
                authRepositoryProvider.overrideWithValue(authRepository),
                appSettingsRepositoryProvider.overrideWithValue(
                    settingsRepository,
                ),
            ],
            child: child,
        );
    }

    static Future<AppDependencies> create() async
    {
        final ForumClient client = await ForumClient.create();
        const CredentialStore credentialStore = SecureCredentialStore();
        final AuthRepository authRepository = AuthRepository(
            client,
            credentialStore,
        );
        final SharedPreferences preferences =
            await SharedPreferences.getInstance();
        final AppSettingsRepository settingsRepository =
            AppSettingsRepository(preferences);

        return AppDependencies._(
            client: client,
            credentialStore: credentialStore,
            authRepository: authRepository,
            settingsRepository: settingsRepository,
        );
    }
}
