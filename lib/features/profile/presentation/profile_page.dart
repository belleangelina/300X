import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:x300/app/app_colors.dart';
import 'package:x300/app/app_links.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/downloads/presentation/downloads_page.dart';
import 'package:x300/features/favorites/presentation/cloud_favorites_page.dart';
import 'package:x300/features/history/presentation/reading_history_page.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/profile/presentation/about_page.dart';
import 'package:x300/features/reader/data/reader_media_repository.dart';
import 'package:x300/features/settings/application/app_settings_controller.dart';
import 'package:x300/features/settings/domain/app_settings.dart';
import 'package:x300/features/settings/presentation/settings_page.dart';

enum ProfileDetailDestination
{
    novelFavorites,
    novelHistory,
    novelDownloads,
    comicFavorites,
    comicHistory,
    comicDownloads,
    settings,
    about,
}

Widget buildProfileDetailPage(ProfileDetailDestination destination)
{
    return switch (destination)
    {
        ProfileDetailDestination.novelFavorites => const CloudFavoritesPage(
            kind: LibraryKind.novel,
        ),
        ProfileDetailDestination.novelHistory => const ReadingHistoryPage(
            kind: LibraryKind.novel,
        ),
        ProfileDetailDestination.novelDownloads => const DownloadsPage(
            kind: LibraryKind.novel,
        ),
        ProfileDetailDestination.comicFavorites => const CloudFavoritesPage(
            kind: LibraryKind.comic,
        ),
        ProfileDetailDestination.comicHistory => const ReadingHistoryPage(
            kind: LibraryKind.comic,
        ),
        ProfileDetailDestination.comicDownloads => const DownloadsPage(
            kind: LibraryKind.comic,
        ),
        ProfileDetailDestination.settings => const SettingsPage(),
        ProfileDetailDestination.about => const AboutPage(),
    };
}

class ProfilePage extends ConsumerWidget
{
    const ProfilePage({
        required this.username,
        required this.onLogout,
        this.onOpenDetail,
        super.key,
    });

    final String username;
    final VoidCallback onLogout;
    final ValueChanged<ProfileDetailDestination>? onOpenDetail;

    @override
    Widget build(BuildContext context, WidgetRef ref)
    {
        final AppSettings settings = ref.watch(
            appSettingsControllerProvider,
        );
        final Uri? avatarUri = ref.watch(currentUserAvatarUriProvider);
        return Scaffold(
            backgroundColor: Theme.of(context).brightness == Brightness.light
                    ? AppColors.background
                    : null,
            body: SafeArea(
                child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                        ListTile(
                            leading: _ProfileAvatar(uri: avatarUri),
                            title: Text(username),
                            subtitle: const Text('百合会论坛账号'),
                            trailing: IconButton(
                                onPressed: onLogout,
                                icon: const Icon(Remix.logout_box_r_line),
                            ),
                        ),
                        const SizedBox(height: 12),
                        _ProfileCard(
                            key: const Key('profile-novel-card'),
                            children: <Widget>[
                                ListTile(
                                    leading: const Icon(Remix.heart_line),
                                    title: const Text('小说收藏'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openDetail(
                                        context,
                                        ProfileDetailDestination.novelFavorites,
                                    ),
                                ),
                                ListTile(
                                    leading: const Icon(Remix.file_history_line),
                                    title: const Text('小说记录'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openDetail(
                                        context,
                                        ProfileDetailDestination.novelHistory,
                                    ),
                                ),
                                ListTile(
                                    leading: const Icon(Remix.download_line),
                                    title: const Text('小说下载'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openDetail(
                                        context,
                                        ProfileDetailDestination.novelDownloads,
                                    ),
                                ),
                            ],
                        ),
                        const SizedBox(height: 12),
                        _ProfileCard(
                            key: const Key('profile-comic-card'),
                            children: <Widget>[
                                ListTile(
                                    leading: const Icon(Remix.heart_line),
                                    title: const Text('漫画收藏'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openDetail(
                                        context,
                                        ProfileDetailDestination.comicFavorites,
                                    ),
                                ),
                                ListTile(
                                    leading: const Icon(Remix.file_history_line),
                                    title: const Text('漫画记录'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openDetail(
                                        context,
                                        ProfileDetailDestination.comicHistory,
                                    ),
                                ),
                                ListTile(
                                    leading: const Icon(Remix.download_line),
                                    title: const Text('漫画下载'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openDetail(
                                        context,
                                        ProfileDetailDestination.comicDownloads,
                                    ),
                                ),
                            ],
                        ),
                        const SizedBox(height: 12),
                        _ProfileCard(
                            key: const Key('profile-settings-card'),
                            children: <Widget>[
                                ListTile(
                                    leading: Icon(
                                        settings.theme ==
                                                AppThemePreference.dark
                                            ? Remix.moon_line
                                            : Remix.sun_line,
                                    ),
                                    title: const Text('显示主题'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _showTheme(
                                        context,
                                        ref,
                                        settings,
                                    ),
                                ),
                                ListTile(
                                    leading: const Icon(Remix.settings_line),
                                    title: const Text('更多设置'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openDetail(
                                        context,
                                        ProfileDetailDestination.settings,
                                    ),
                                ),
                                ListTile(
                                    leading: const Icon(Remix.github_fill),
                                    title: const Text('开源主页'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openRepository(),
                                ),
                                ListTile(
                                    leading: const Icon(
                                        Remix.information_line,
                                    ),
                                    title: const Text('关于APP'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openDetail(
                                        context,
                                        ProfileDetailDestination.about,
                                    ),
                                ),
                            ],
                        ),
                    ],
                ),
            ),
        );
    }

    void _openDetail(
        BuildContext context,
        ProfileDetailDestination destination,
    )
    {
        final ValueChanged<ProfileDetailDestination>? callback = onOpenDetail;
        if (callback != null)
        {
            callback(destination);
            return;
        }
        Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (BuildContext context) =>
                    buildProfileDetailPage(destination),
            ),
        );
    }

    Future<void> _showTheme(
        BuildContext context,
        WidgetRef ref,
        AppSettings settings,
    ) async
    {
        final AppThemePreference? selected =
            await showDialog<AppThemePreference>(
                context: context,
                builder: (BuildContext context) => SimpleDialog(
                    title: const Text('设置主题'),
                    children: <Widget>[
                        RadioGroup<AppThemePreference>(
                            groupValue: settings.theme,
                            onChanged: (
                                AppThemePreference? selected,
                            ) => Navigator.of(context).pop(selected),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: AppThemePreference.values
                                    .map(
                                        (AppThemePreference value) =>
                                            RadioListTile<
                                                AppThemePreference
                                            >(
                                                title: Text(value.label),
                                                value: value,
                                            ),
                                    )
                                    .toList(growable: false),
                            ),
                        ),
                    ],
                ),
            );
        if (selected != null)
        {
            ref.read(appSettingsControllerProvider.notifier).update(
                settings.copyWith(theme: selected),
            );
        }
    }

    Future<void> _openRepository() async
    {
        await launchUrl(
            Uri.parse(AppLinks.repositoryUrl),
            mode: LaunchMode.externalApplication,
        );
    }
}

class _ProfileAvatar extends ConsumerWidget
{
    const _ProfileAvatar({required this.uri});

    final Uri? uri;

    @override
    Widget build(BuildContext context, WidgetRef ref)
    {
        final Widget fallback = CircleAvatar(
            backgroundColor: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.12),
            child: const Icon(Remix.user_smile_line),
        );
        if (uri == null)
        {
            return fallback;
        }
        final ReaderMediaRepository repository = ref.watch(
            readerMediaRepositoryProvider,
        );
        final Uri? cached = repository.peek(uri!);
        if (cached != null)
        {
            return _image(cached, fallback);
        }
        return FutureBuilder<Uri>(
            future: repository.resolve(
                uri!,
                referer: ForumClient.baseUri.toString(),
            ),
            builder: (BuildContext context, AsyncSnapshot<Uri> snapshot)
            {
                final Uri? resolved = snapshot.data;
                return resolved == null
                    ? fallback
                    : _image(resolved, fallback);
            },
        );
    }

    Widget _image(Uri value, Widget fallback)
    {
        return SizedBox.square(
            dimension: 40,
            child: ClipOval(
                child: Image.file(
                    File.fromUri(value),
                    fit: BoxFit.cover,
                    errorBuilder: (
                        BuildContext context,
                        Object error,
                        StackTrace? stackTrace,
                    ) => fallback,
                ),
            ),
        );
    }
}

class _ProfileCard extends StatelessWidget
{
    const _ProfileCard({required this.children, super.key});

    final List<Widget> children;

    @override
    Widget build(BuildContext context)
    {
        return Material(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            child: Column(children: children),
        );
    }
}
