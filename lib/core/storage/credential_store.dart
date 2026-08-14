import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final Provider<CredentialStore> credentialStoreProvider =
    Provider<CredentialStore>(
        (Ref ref)
        {
            throw UnimplementedError(
                'CredentialStore must be overridden at startup.',
            );
        },
    );

class StoredCredentials
{
    const StoredCredentials({
        required this.username,
        required this.password,
        this.userId = 0,
    });

    final String username;
    final String password;
    final int userId;
}

abstract interface class CredentialStore
{
    Future<StoredCredentials?> read();

    Future<void> write(StoredCredentials credentials);

    Future<void> clear();
}

class SecureCredentialStore implements CredentialStore
{
    const SecureCredentialStore([
        this._storage = const FlutterSecureStorage(),
    ]);

    static const String _usernameKey = 'forum_username';
    static const String _passwordKey = 'forum_password';
    static const String _userIdKey = 'forum_user_id';

    final FlutterSecureStorage _storage;

    @override
    Future<StoredCredentials?> read() async
    {
        final String? username = await _storage.read(key: _usernameKey);
        final String? password = await _storage.read(key: _passwordKey);
        final int userId = int.tryParse(
                await _storage.read(key: _userIdKey) ?? '',
            ) ??
            0;
        if (username == null ||
            username.trim().isEmpty ||
            password == null ||
            password.isEmpty)
        {
            return null;
        }
        return StoredCredentials(
            username: username,
            password: password,
            userId: userId,
        );
    }

    @override
    Future<void> write(StoredCredentials credentials) async
    {
        await _storage.write(
            key: _usernameKey,
            value: credentials.username,
        );
        await _storage.write(
            key: _passwordKey,
            value: credentials.password,
        );
        await _storage.write(
            key: _userIdKey,
            value: credentials.userId.toString(),
        );
    }

    @override
    Future<void> clear() async
    {
        await _storage.delete(key: _usernameKey);
        await _storage.delete(key: _passwordKey);
        await _storage.delete(key: _userIdKey);
    }
}
