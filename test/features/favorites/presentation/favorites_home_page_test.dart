import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/favorites/data/favorite_cache_repository.dart';
import 'package:x300/features/favorites/data/forum_favorite_repository.dart';
import 'package:x300/features/favorites/data/raw_favorite_repository.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/favorites/presentation/favorites_home_page.dart';
import 'package:x300/features/library/domain/library_models.dart';

class _MockForumFavoriteRepository extends Mock
    implements ForumFavoriteRepository
{
}

class _MockFavoriteCacheRepository extends Mock
    implements FavoriteCacheRepository
{
}

class _MockRawFavoriteRepository extends Mock
    implements RawFavoriteRepository
{
}

void main()
{
    setUpAll(()
    {
        registerFallbackValue(<CloudFavoriteEntry>[]);
        registerFallbackValue(<FavoriteWork>[]);
    });

    testWidgets('收藏主入口固定漫画小说全部且嵌入页不显示旧底栏', (
        WidgetTester tester,
    ) async
    {
        final _MockForumFavoriteRepository repository =
            _MockForumFavoriteRepository();
        final _MockFavoriteCacheRepository cacheRepository =
            _MockFavoriteCacheRepository();
        final FavoritesHomeController controller = FavoritesHomeController();
        var allRefreshes = 0;
        when(repository.loadInitial).thenAnswer(
            (_) async => const CloudFavoritePage(
                entries: <CloudFavoriteEntry>[],
                ignoredCount: 0,
                currentPage: 1,
                totalPages: 1,
            ),
        );
        when(() => repository.aggregateEntries(any()))
            .thenReturn(<FavoriteWork>[]);
        when(() => cacheRepository.save(any())).thenAnswer((_) async {});

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    forumFavoriteRepositoryProvider.overrideWithValue(
                        repository,
                    ),
                    favoriteCacheRepositoryProvider.overrideWithValue(
                        cacheRepository,
                    ),
                ],
                child: MaterialApp(
                    home: FavoritesHomePage(
                        authState: const AuthState.authenticated(
                            '测试账号',
                            userId: 100,
                        ),
                        onLogin: _noop,
                        onOpenWork: (Work work) {},
                        controller: controller,
                        allFavoritesBuilder: (BuildContext context) =>
                            const Center(
                                key: Key('all-favorites-content'),
                                child: Text('原始收藏内容'),
                            ),
                        onRefreshAll: () async => allRefreshes++,
                    ),
                ),
            ),
        );
        await tester.pumpAndSettle();

        final List<String?> tabs = tester
            .widgetList<Tab>(find.byType(Tab))
            .map((Tab value) => value.text)
            .toList(growable: false);
        expect(tabs, <String?>['漫画', '小说', '全部']);
        expect(
            find.byKey(const Key('favorite-result-mode-bottom-bar')),
            findsNothing,
        );

        await tester.tap(find.text('全部'));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const Key('all-favorites-content')),
            findsOneWidget,
        );
        await controller.scrollToTopAndRefresh();
        expect(allRefreshes, 1);
    });

    testWidgets('未登录收藏页保留三页签并只提示登录', (
        WidgetTester tester,
    ) async
    {
        var loginRequests = 0;
        await tester.pumpWidget(
            MaterialApp(
                home: FavoritesHomePage(
                    authState: const AuthState.unauthenticated(),
                    onLogin: () => loginRequests++,
                    onOpenWork: (Work work) {},
                ),
            ),
        );

        expect(find.text('漫画'), findsOneWidget);
        expect(find.text('小说'), findsOneWidget);
        expect(find.text('全部'), findsOneWidget);
        expect(find.text('登录后查看收藏'), findsOneWidget);
        await tester.tap(find.text('登录'));
        expect(loginRequests, 1);
    });

    testWidgets('全部页签默认接入原生原始收藏并接受主页刷新', (
        WidgetTester tester,
    ) async
    {
        final _MockForumFavoriteRepository repository =
            _MockForumFavoriteRepository();
        final _MockFavoriteCacheRepository cacheRepository =
            _MockFavoriteCacheRepository();
        final _MockRawFavoriteRepository rawRepository =
            _MockRawFavoriteRepository();
        final FavoritesHomeController controller = FavoritesHomeController();
        when(repository.loadInitial).thenAnswer(
            (_) async => const CloudFavoritePage(
                entries: <CloudFavoriteEntry>[],
                ignoredCount: 0,
                currentPage: 1,
                totalPages: 1,
            ),
        );
        when(() => repository.aggregateEntries(any()))
            .thenReturn(<FavoriteWork>[]);
        when(() => cacheRepository.save(any())).thenAnswer((_) async {});
        when(() => rawRepository.loadInitial()).thenAnswer(
            (_) async => RawFavoritePage(
                categories: <RawFavoriteCategory>[
                    RawFavoriteCategory(
                        key: 'thread',
                        label: '主题',
                        uri: Uri.parse(
                            'https://bbs.yamibo.com/home.php?'
                            'mod=space&do=favorite&type=thread&mobile=2',
                        ),
                    ),
                ],
                items: const <RawFavoriteItem>[
                    RawFavoriteItem(
                        favoriteId: 71,
                        categoryKey: 'thread',
                        title: '默认原始收藏',
                        targetKind: RawFavoriteTargetKind.thread,
                        threadId: 501,
                    ),
                ],
                selectedCategoryKey: RawFavoriteRepository.allCategoryKey,
                currentPage: 1,
                totalPages: 1,
                sourceUri: Uri.parse(
                    'https://bbs.yamibo.com/home.php?'
                    'mod=space&do=favorite&mobile=2',
                ),
            ),
        );

        await tester.pumpWidget(
            ProviderScope(
                overrides: [
                    forumFavoriteRepositoryProvider.overrideWithValue(
                        repository,
                    ),
                    favoriteCacheRepositoryProvider.overrideWithValue(
                        cacheRepository,
                    ),
                    rawFavoriteRepositoryProvider.overrideWithValue(
                        rawRepository,
                    ),
                ],
                child: MaterialApp(
                    home: FavoritesHomePage(
                        authState: const AuthState.authenticated(
                            '测试账号',
                            userId: 100,
                        ),
                        onLogin: _noop,
                        onOpenWork: (Work work) {},
                        controller: controller,
                    ),
                ),
            ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('全部'));
        await tester.pumpAndSettle();

        expect(find.text('默认原始收藏'), findsOneWidget);
        await controller.scrollToTopAndRefresh();
        await tester.pumpAndSettle();
        verify(() => rawRepository.loadInitial()).called(2);
    });
}

void _noop()
{
}
