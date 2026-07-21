import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x300/app/app_colors.dart';
import 'package:x300/app/app_theme.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/profile/presentation/about_page.dart';
import 'package:x300/features/profile/presentation/profile_page.dart';
import 'package:x300/features/reader/data/reader_media_repository.dart';
import 'package:x300/features/settings/data/app_settings_repository.dart';

class _MockReaderMediaRepository extends Mock
    implements ReaderMediaRepository
{
}

void main()
{
    late AppSettingsRepository settingsRepository;

    setUp(() async
    {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        settingsRepository = AppSettingsRepository(
            await SharedPreferences.getInstance(),
        );
        PackageInfo.setMockInitialValues(
            appName: '300X',
            packageName: 'com.yamibox300',
            version: '1.0.0',
            buildNumber: '1',
            buildSignature: '',
        );
    });

    testWidgets('个人页小说漫画与设置在浅色和深色主题下都有独立卡片', (
        WidgetTester tester,
    ) async
    {
        await tester.pumpWidget(
            _profileApp(settingsRepository, AppTheme.light),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('profile-novel-card')), findsOneWidget);
        expect(find.byKey(const Key('profile-comic-card')), findsOneWidget);
        expect(find.byKey(const Key('profile-settings-card')), findsOneWidget);
        expect(
            find.descendant(
                of: find.byKey(const Key('profile-novel-card')),
                matching: find.text('小说收藏'),
            ),
            findsOneWidget,
        );
        expect(
            find.descendant(
                of: find.byKey(const Key('profile-comic-card')),
                matching: find.text('漫画收藏'),
            ),
            findsOneWidget,
        );
        expect(
            find.descendant(
                of: find.byKey(const Key('profile-settings-card')),
                matching: find.text('开源主页'),
            ),
            findsOneWidget,
        );
        expect(
            find.descendant(
                of: find.byKey(const Key('profile-settings-card')),
                matching: find.text('关于APP'),
            ),
            findsOneWidget,
        );
        expect(_materialsWithColor(tester, Colors.white), greaterThanOrEqualTo(3));
        expect(
            tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
            AppColors.background,
        );

        await tester.pumpWidget(
            _profileApp(settingsRepository, AppTheme.dark),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('profile-novel-card')), findsOneWidget);
        expect(find.byKey(const Key('profile-comic-card')), findsOneWidget);
        expect(find.byKey(const Key('profile-settings-card')), findsOneWidget);
        expect(
            _materialsWithColor(tester, AppColors.cardDark),
            greaterThanOrEqualTo(3),
        );
        expect(AppTheme.dark.scaffoldBackgroundColor, Colors.black);
    });

    testWidgets('配置入口等高且主题入口不重复标注当前模式', (
        WidgetTester tester,
    ) async
    {
        await tester.pumpWidget(
            _profileApp(settingsRepository, AppTheme.light),
        );
        await tester.pumpAndSettle();

        expect(find.text('跟随系统'), findsNothing);
        final List<Finder> entries = <Finder>[
            _tileWithText('小说收藏'),
            _tileWithText('小说记录'),
            _tileWithText('小说下载'),
            _tileWithText('漫画收藏'),
            _tileWithText('漫画记录'),
            _tileWithText('漫画下载'),
            _tileWithText('显示主题'),
            _tileWithText('更多设置'),
            _tileWithText('开源主页'),
            _tileWithText('关于APP'),
        ];
        final double height = tester.getSize(entries.first).height;
        for (final Finder entry in entries.skip(1))
        {
            expect(tester.getSize(entry).height, height);
        }
        expect(find.text('免责声明'), findsNothing);
    });

    testWidgets('账号头像使用当前登录账号地址并复用图片缓存', (
        WidgetTester tester,
    ) async
    {
        final Uri avatarUri = Uri.parse(
            'https://bbs.yamibo.com/uc_server/avatar.php?uid=471581&size=middle',
        );
        final Uri cachedUri = Uri.file('/tmp/page300-profile-avatar.jpg');
        final _MockReaderMediaRepository mediaRepository =
            _MockReaderMediaRepository();
        when(() => mediaRepository.peek(avatarUri)).thenReturn(cachedUri);

        await tester.pumpWidget(
            _profileApp(
                settingsRepository,
                AppTheme.light,
                avatarUri: avatarUri,
                mediaRepository: mediaRepository,
            ),
        );
        await tester.pump();

        expect(find.byType(Image), findsOneWidget);
        verify(() => mediaRepository.peek(avatarUri)).called(1);
        verifyNever(
            () => mediaRepository.resolve(
                avatarUri,
                referer: any(named: 'referer'),
            ),
        );
    });

    testWidgets('关于页合并免责声明且不重复展示开源和参考项目链接', (
        WidgetTester tester,
    ) async
    {
        await tester.pumpWidget(
            const MaterialApp(home: AboutPage()),
        );
        await tester.pumpAndSettle();

        expect(find.text('关于APP'), findsOneWidget);
        expect(find.text('300X'), findsOneWidget);
        expect(find.text('免责声明'), findsOneWidget);
        expect(find.textContaining('不提供、托管或绕过权限'), findsOneWidget);
        expect(find.textContaining('GPL-3.0'), findsOneWidget);
        expect(find.textContaining('开源主页'), findsNothing);
        expect(find.textContaining('flutter_dmzj'), findsNothing);
    });
}

Widget _profileApp(
    AppSettingsRepository settingsRepository,
    ThemeData theme, {
    Uri? avatarUri,
    ReaderMediaRepository? mediaRepository,
})
{
    return ProviderScope(
        overrides: [
            appSettingsRepositoryProvider.overrideWithValue(
                settingsRepository,
            ),
            currentUserAvatarUriProvider.overrideWithValue(avatarUri),
            if (mediaRepository != null)
                readerMediaRepositoryProvider.overrideWithValue(
                    mediaRepository,
                ),
        ],
        child: MaterialApp(
            theme: theme,
            home: ProfilePage(
                username: '测试账号',
                onLogout: _noop,
            ),
        ),
    );
}

Finder _tileWithText(String text)
{
    return find.ancestor(
        of: find.text(text),
        matching: find.byType(ListTile),
    );
}

int _materialsWithColor(WidgetTester tester, Color color)
{
    return tester
        .widgetList<Material>(find.byType(Material))
        .where((Material material) => material.color == color)
        .length;
}

void _noop()
{
}
