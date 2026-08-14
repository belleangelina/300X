import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/features/auth/application/auth_controller.dart';
import 'package:x300/features/auth/data/auth_repository.dart';
import 'package:x300/features/auth/domain/auth_models.dart';
import 'package:x300/features/community/data/community_repository.dart';
import 'package:x300/features/community/domain/community_models.dart';
import 'package:x300/features/community/presentation/community_pages.dart';
import 'package:x300/features/favorites/data/raw_favorite_repository.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/favorites/presentation/raw_favorites_page.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockRawFavoriteRepository extends Mock
    implements RawFavoriteRepository {}

void main() {
  testWidgets('通知页提示已读副作用并按返回 URI 连续翻页', (WidgetTester tester) async {
    final _FakeCommunityRepository repository = _FakeCommunityRepository();
    final Uri firstUri = _uri('home.php?mod=space&do=notice&mobile=2');
    final Uri secondUri = _uri('home.php?mod=space&do=notice&page=2&mobile=2');
    repository.notices[firstUri] = CommunityNoticePage(
      items: <CommunityNotice>[
        for (int index = 1; index <= 24; index++) _notice(index),
      ],
      categories: const <CommunityNoticeCategory>[
        CommunityNoticeCategory(key: 'post', label: '帖子'),
      ],
      cursor: CommunityPageCursor(
        sourceUri: firstUri,
        currentPage: 1,
        totalPages: 2,
        nextPageUri: secondUri,
      ),
    );
    repository.notices[secondUri] = CommunityNoticePage(
      items: <CommunityNotice>[_notice(99)],
      categories: const <CommunityNoticeCategory>[
        CommunityNoticeCategory(key: 'post', label: '帖子'),
      ],
      cursor: CommunityPageCursor(
        sourceUri: secondUri,
        currentPage: 2,
        totalPages: 2,
        previousPageUri: firstUri,
      ),
    );

    await tester.pumpWidget(
      _app(repository, CommunityNoticesScreen(uri: firstUri)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('服务端标记已读'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('community-notice-1')),
      findsOneWidget,
    );
    await tester.fling(find.byType(ListView), const Offset(0, -4000), 2500);
    await tester.pumpAndSettle();

    expect(repository.noticeRequests, <Uri>[firstUri, secondUri]);
    expect(
      find.byKey(const ValueKey<String>('community-notice-99')),
      findsOneWidget,
    );
  });

  testWidgets('私信列表和会话只显示当前响应确认的写入入口', (WidgetTester tester) async {
    final _FakeCommunityRepository repository = _FakeCommunityRepository();
    final Uri listUri = _uri('home.php?mod=space&do=pm&mobile=2');
    final Uri noticesUri = _uri('home.php?mod=space&do=notice&mobile=2');
    final Uri threadUri = _uri(
      'home.php?mod=space&do=pm&subop=view&touid=77&mobile=2',
    );
    repository.pmLists[listUri] = CommunityPmListPage(
      items: <CommunityPmConversation>[
        CommunityPmConversation(
          peerUserId: 77,
          peerUsername: '用户A',
          preview: '[已脱敏]预览',
          timeLabel: '[时间]',
          uri: threadUri,
          unread: true,
        ),
      ],
      cursor: CommunityPageCursor(
        sourceUri: listUri,
        currentPage: 1,
        totalPages: 1,
      ),
      navigation: <CommunitySectionLink>[
        CommunitySectionLink(
          kind: CommunitySectionKind.messages,
          label: '私信',
          uri: listUri,
          selected: true,
        ),
        CommunitySectionLink(
          kind: CommunitySectionKind.notices,
          label: '通知',
          uri: noticesUri,
        ),
      ],
      composeUri: _uri('home.php?mod=spacecp&ac=pm&mobile=2'),
    );
    repository.notices[noticesUri] = CommunityNoticePage(
      items: <CommunityNotice>[_notice(8)],
      categories: const <CommunityNoticeCategory>[
        CommunityNoticeCategory(key: 'post', label: '帖子'),
      ],
      cursor: CommunityPageCursor(
        sourceUri: noticesUri,
        currentPage: 1,
        totalPages: 1,
      ),
    );
    repository.pmThreads[threadUri] = CommunityPmThreadPage(
      peerUserId: 77,
      messages: const <CommunityPmMessage>[
        CommunityPmMessage(
          message: '[已脱敏]会话正文',
          timeLabel: '[时间]',
          sentByViewer: false,
        ),
      ],
      cursor: CommunityPageCursor(
        sourceUri: threadUri,
        currentPage: 1,
        totalPages: 1,
      ),
      hasSendCapability: true,
    );

    await tester.pumpWidget(
      _app(repository, CommunityMessagesScreen(uri: listUri)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('community-pm-compose')),
      findsOneWidget,
    );
    await tester.tap(find.text('用户A'));
    await tester.pumpAndSettle();

    expect(find.text('[已脱敏]会话正文'), findsOneWidget);
    expect(find.textContaining('打开会话可能'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('community-pm-reply')),
      findsOneWidget,
    );
    expect(repository.pmThreadRequests, <Uri>[threadUri]);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('通知'));
    await tester.pumpAndSettle();
    expect(find.text('通知 8'), findsOneWidget);
    expect(repository.noticeRequests, <Uri>[noticesUri]);
  });

  testWidgets('个人资料只启用已支持的动态入口', (WidgetTester tester) async {
    final _FakeCommunityRepository repository = _FakeCommunityRepository();
    final Uri profileUri = _uri(
      'home.php?mod=space&do=profile&uid=42&mobile=2',
    );
    final Uri topicsUri = _uri(
      'home.php?mod=space&do=thread&view=me&uid=42&mobile=2',
    );
    final Uri repliesUri = _uri(
      'home.php?mod=space&do=thread&view=me&uid=42&type=reply&mobile=2',
    );
    final Uri unsupportedUri = _uri('plugin.php?id=entry&mobile=2');
    repository.profiles[profileUri] = CommunityProfile(
      userId: 42,
      username: '用户B',
      sourceUri: profileUri,
      entries: <CommunityProfileEntry>[
        CommunityProfileEntry(
          label: '主题',
          uri: topicsUri,
          kind: CommunityProfileEntryKind.topics,
        ),
        CommunityProfileEntry(
          label: '扩展入口',
          uri: unsupportedUri,
          kind: CommunityProfileEntryKind.unknown,
        ),
      ],
      details: const <String>['[已脱敏]资料'],
    );
    repository.activities[topicsUri] = CommunityActivityPage(
      kind: CommunityActivityKind.topics,
      profileUserId: 42,
      items: <CommunityActivityItem>[
        CommunityActivityItem(
          title: '[已脱敏]主题',
          summary: '[已脱敏]摘要',
          timeLabel: '[时间]',
          target: CommunityTopicTarget(
            threadId: 120,
            uri: _uri('forum.php?mod=viewthread&tid=120&mobile=2'),
          ),
        ),
      ],
      cursor: CommunityPageCursor(
        sourceUri: topicsUri,
        currentPage: 1,
        totalPages: 1,
      ),
      tabs: <CommunityProfileEntry>[
        CommunityProfileEntry(
          label: '主题',
          uri: topicsUri,
          kind: CommunityProfileEntryKind.topics,
        ),
        CommunityProfileEntry(
          label: '回复',
          uri: repliesUri,
          kind: CommunityProfileEntryKind.replies,
        ),
      ],
    );
    repository.activities[repliesUri] = CommunityActivityPage(
      kind: CommunityActivityKind.replies,
      profileUserId: 42,
      items: <CommunityActivityItem>[
        CommunityActivityItem(
          title: '[已脱敏]回复',
          summary: '[已脱敏]回复摘要',
          timeLabel: '[时间]',
          target: CommunityTopicTarget(
            threadId: 120,
            postId: 321,
            uri: _uri(
              'forum.php?mod=redirect&goto=findpost&ptid=120&pid=321&mobile=2',
            ),
          ),
        ),
      ],
      cursor: CommunityPageCursor(
        sourceUri: repliesUri,
        currentPage: 1,
        totalPages: 1,
      ),
      tabs: repository.activities[topicsUri]!.tabs,
    );

    await tester.pumpWidget(
      _app(
        repository,
        CommunityProfileScreen(uri: profileUri, profileUserId: 42),
      ),
    );
    await tester.pumpAndSettle();

    final ListTile unsupported = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '扩展入口'),
    );
    expect(unsupported.enabled, isFalse);
    expect(unsupported.onTap, isNull);
    await tester.tap(find.text('主题').first);
    await tester.pumpAndSettle();

    expect(find.text('[已脱敏]主题'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '回复'));
    await tester.pumpAndSettle();

    expect(find.text('[已脱敏]回复'), findsOneWidget);
    expect(repository.activityRequests, <Uri>[topicsUri, repliesUri]);
  });

  testWidgets('本人资料收藏入口打开原生全部收藏，他人收藏保持禁用', (
    WidgetTester tester,
  ) async {
    final _FakeCommunityRepository repository = _FakeCommunityRepository();
    final _MockRawFavoriteRepository favorites = _MockRawFavoriteRepository();
    final Uri ownUri = _uri('home.php?mod=space&do=profile&uid=42&mobile=2');
    final Uri otherUri = _uri('home.php?mod=space&do=profile&uid=77&mobile=2');
    final Uri favoriteUri = _uri('home.php?mod=space&do=favorite&uid=42&mobile=2');
    final Uri otherFavoriteUri = _uri(
      'home.php?mod=space&do=favorite&uid=77&mobile=2',
    );
    repository.profiles[ownUri] = CommunityProfile(
      userId: 42,
      username: '用户B',
      sourceUri: ownUri,
      entries: <CommunityProfileEntry>[
        CommunityProfileEntry(
          label: '收藏',
          uri: favoriteUri,
          kind: CommunityProfileEntryKind.favorites,
        ),
      ],
      details: const <String>[],
    );
    repository.profiles[otherUri] = CommunityProfile(
      userId: 77,
      username: '用户A',
      sourceUri: otherUri,
      entries: <CommunityProfileEntry>[
        CommunityProfileEntry(
          label: '收藏',
          uri: otherFavoriteUri,
          kind: CommunityProfileEntryKind.favorites,
        ),
      ],
      details: const <String>[],
    );
    when(() => favorites.loadInitial()).thenAnswer(
      (_) async => RawFavoritePage(
        categories: const <RawFavoriteCategory>[],
        items: const <RawFavoriteItem>[],
        selectedCategoryKey: RawFavoriteRepository.allCategoryKey,
        currentPage: 1,
        totalPages: 1,
        sourceUri: favoriteUri,
      ),
    );

    await tester.pumpWidget(
      _app(
        repository,
        CommunityProfileScreen(uri: otherUri, profileUserId: 77),
        rawFavorites: favorites,
      ),
    );
    await tester.pumpAndSettle();
    final ListTile otherTile = tester.widget<ListTile>(
      find.byKey(const ValueKey<String>('community-profile-entry-favorites')),
    );
    expect(otherTile.enabled, isFalse);
    expect(otherTile.onTap, isNull);

    await tester.pumpWidget(
      _app(
        repository,
        CommunityProfileScreen(uri: ownUri, profileUserId: 42),
        rawFavorites: favorites,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('community-profile-entry-favorites')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RawFavoritesPage), findsOneWidget);
    expect(find.text('收藏'), findsWidgets);
  });

  testWidgets('好友页使用服务端分类 URI 切到在线成员和访客', (WidgetTester tester) async {
    final _FakeCommunityRepository repository = _FakeCommunityRepository();
    final Uri friendsUri = _uri('home.php?mod=space&do=friend&mobile=2');
    final Uri onlineUri = _uri(
      'home.php?mod=space&do=friend&type=member&view=online&mobile=2',
    );
    final Uri visitorsUri = _uri(
      'home.php?mod=space&do=friend&view=visitor&uid=42&mobile=2',
    );
    final Uri visitedUri = _uri(
      'home.php?mod=space&do=friend&view=trace&uid=42&mobile=2',
    );
    final List<CommunityPeopleTab> tabs = <CommunityPeopleTab>[
      CommunityPeopleTab(
        kind: CommunityPeopleKind.friends,
        label: '好友',
        uri: friendsUri,
      ),
      CommunityPeopleTab(
        kind: CommunityPeopleKind.online,
        label: '在线',
        uri: onlineUri,
      ),
      CommunityPeopleTab(
        kind: CommunityPeopleKind.visitors,
        label: '访客',
        uri: visitorsUri,
      ),
      CommunityPeopleTab(
        kind: CommunityPeopleKind.visited,
        label: '访问记录',
        uri: visitedUri,
      ),
    ];
    repository.people[friendsUri] = CommunityPeoplePage(
      kind: CommunityPeopleKind.friends,
      people: const <CommunityPerson>[],
      tabs: tabs,
      cursor: CommunityPageCursor(
        sourceUri: friendsUri,
        currentPage: 1,
        totalPages: 1,
      ),
    );
    repository.people[visitorsUri] = CommunityPeoplePage(
      kind: CommunityPeopleKind.visitors,
      people: <CommunityPerson>[
        CommunityPerson(
          profile: CommunityProfileTarget(
            userId: 78,
            username: '访客用户',
            uri: _uri('home.php?mod=space&uid=78&mobile=2'),
          ),
          description: '[已脱敏]来访信息',
        ),
      ],
      tabs: tabs,
      cursor: CommunityPageCursor(
        sourceUri: visitorsUri,
        currentPage: 1,
        totalPages: 1,
      ),
    );
    repository.people[visitedUri] = CommunityPeoplePage(
      kind: CommunityPeopleKind.visited,
      people: const <CommunityPerson>[],
      tabs: tabs,
      cursor: CommunityPageCursor(
        sourceUri: visitedUri,
        currentPage: 1,
        totalPages: 1,
      ),
    );
    repository.people[onlineUri] = CommunityPeoplePage(
      kind: CommunityPeopleKind.online,
      people: <CommunityPerson>[
        CommunityPerson(
          profile: CommunityProfileTarget(
            userId: 77,
            username: '在线用户',
            uri: _uri('home.php?mod=space&uid=77&mobile=2'),
          ),
          description: '[已脱敏]状态',
        ),
      ],
      tabs: tabs,
      cursor: CommunityPageCursor(
        sourceUri: onlineUri,
        currentPage: 1,
        totalPages: 1,
      ),
    );

    await tester.pumpWidget(
      _app(
        repository,
        CommunityPeopleScreen(
          uri: friendsUri,
          kind: CommunityPeopleKind.friends,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('在线'));
    await tester.pumpAndSettle();

    expect(find.text('在线用户'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '访客'));
    await tester.pumpAndSettle();

    expect(find.text('访客用户'), findsOneWidget);
    expect(repository.peopleRequests, <Uri>[
      friendsUri,
      onlineUri,
      visitorsUri,
    ]);
  });
}

Widget _app(
  CommunityRepository repository,
  Widget home, {
  RawFavoriteRepository? rawFavorites,
  int viewerUserId = 42,
}) {
  final _MockAuthRepository auth = _MockAuthRepository();
  when(auth.restoreSession).thenAnswer(
    (_) async => AuthState.authenticated('用户B', userId: viewerUserId),
  );
  return ProviderScope(
    overrides: [
      communityRepositoryProvider.overrideWithValue(repository),
      authRepositoryProvider.overrideWithValue(auth),
      if (rawFavorites != null)
        rawFavoriteRepositoryProvider.overrideWithValue(rawFavorites),
    ],
    child: MaterialApp(home: home),
  );
}

class _FakeCommunityRepository implements CommunityRepository {
  final Map<Uri, CommunityNoticePage> notices = <Uri, CommunityNoticePage>{};
  final Map<Uri, CommunityPmListPage> pmLists = <Uri, CommunityPmListPage>{};
  final Map<Uri, CommunityPmThreadPage> pmThreads =
      <Uri, CommunityPmThreadPage>{};
  final Map<Uri, CommunityProfile> profiles = <Uri, CommunityProfile>{};
  final Map<Uri, CommunityActivityPage> activities =
      <Uri, CommunityActivityPage>{};
  final Map<Uri, CommunityPeoplePage> people = <Uri, CommunityPeoplePage>{};
  final List<Uri> noticeRequests = <Uri>[];
  final List<Uri> pmThreadRequests = <Uri>[];
  final List<Uri> activityRequests = <Uri>[];
  final List<Uri> peopleRequests = <Uri>[];

  @override
  Future<CommunityNoticePage> loadNotices(Uri uri) async {
    noticeRequests.add(uri);
    return notices[uri]!;
  }

  @override
  Future<CommunityPmListPage> loadPmList(Uri uri) async => pmLists[uri]!;

  @override
  Future<CommunityPmThreadPage> loadPmThread(
    Uri uri, {
    required int expectedPeerUserId,
  }) async {
    pmThreadRequests.add(uri);
    final CommunityPmThreadPage page = pmThreads[uri]!;
    expect(page.peerUserId, expectedPeerUserId);
    return page;
  }

  @override
  Future<CommunityProfile> loadProfile(
    Uri uri, {
    required int expectedProfileUserId,
  }) async {
    final CommunityProfile profile = profiles[uri]!;
    expect(profile.userId, expectedProfileUserId);
    return profile;
  }

  @override
  Future<CommunityActivityPage> loadActivity(
    Uri uri, {
    required int expectedProfileUserId,
    required CommunityActivityKind expectedKind,
  }) async {
    activityRequests.add(uri);
    final CommunityActivityPage page = activities[uri]!;
    expect(page.profileUserId, expectedProfileUserId);
    expect(page.kind, expectedKind);
    return page;
  }

  @override
  Future<CommunityPeoplePage> loadPeople(
    Uri uri, {
    required CommunityPeopleKind expectedKind,
  }) async {
    peopleRequests.add(uri);
    final CommunityPeoplePage page = people[uri]!;
    expect(page.kind, expectedKind);
    return page;
  }
}

CommunityNotice _notice(int id) {
  return CommunityNotice(
    id: id,
    category: const CommunityNoticeCategory(key: 'post', label: '帖子'),
    title: '通知 $id',
    message: '[已脱敏]通知内容',
    timeLabel: '[时间]',
  );
}

Uri _uri(String value) => Uri.parse('https://bbs.yamibo.com/$value');
