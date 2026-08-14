import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/forum/data/forum_local_repository.dart';

void main() {
  late AppDatabase database;
  late ForumLocalRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = ForumLocalRepository(database);
  });

  tearDown(() => database.close());

  test('论坛缓存严格按 uid 隔离且损坏内容不返回', () async {
    await repository.saveCache(
      userId: 101,
      key: 'forum:v2:index',
      payload: <String, dynamic>{'kind': 'index'},
      updatedAt: DateTime(2026, 8, 12),
    );

    expect(
      (await repository.loadCache(
        userId: 101,
        key: 'forum:v2:index',
      ))?.payload['kind'],
      'index',
    );
    expect(
      await repository.loadCache(userId: 202, key: 'forum:v2:index'),
      isNull,
    );

    await database
        .into(database.forumCaches)
        .insertOnConflictUpdate(
          ForumCachesCompanion.insert(
            accountKey: 'uid:101',
            cacheKey: 'forum:v2:index',
            payloadJson: '{broken',
            updatedAt: DateTime(2026, 8, 13),
          ),
        );
    expect(
      await repository.loadCache(userId: 101, key: 'forum:v2:index'),
      isNull,
    );
  });

  test('阅读位置按账号和 tid 保存并支持账号清理', () async {
    await repository.saveReadPosition(
      ForumReadPosition(
        userId: 101,
        threadId: 501,
        postId: 9001,
        page: 2,
        floor: 31,
        updatedAt: DateTime(2026, 8, 12),
      ),
    );
    await repository.saveCache(
      userId: 101,
      key: 'forum:v2:thread:501',
      payload: <String, dynamic>{'kind': 'thread'},
    );

    final ForumReadPosition? position = await repository.loadReadPosition(
      userId: 101,
      threadId: 501,
    );
    expect(position?.postId, 9001);
    expect(position?.page, 2);
    expect(
      await repository.loadReadPosition(userId: 202, threadId: 501),
      isNull,
    );

    await repository.clearAccount(101);

    expect(
      await repository.loadReadPosition(userId: 101, threadId: 501),
      isNull,
    );
    expect(
      await repository.loadCache(userId: 101, key: 'forum:v2:thread:501'),
      isNull,
    );
  });

  test('每个账号的论坛缓存容量独立裁剪', () async {
    for (
      int index = 0;
      index <= ForumLocalRepository.maximumCacheEntriesPerAccount;
      index++
    ) {
      await repository.saveCache(
        userId: 101,
        key: 'item:$index',
        payload: <String, dynamic>{'index': index},
        updatedAt: DateTime(2026, 8, 12).add(Duration(minutes: index)),
      );
    }

    final List<ForumCache> rows = await (database.select(
      database.forumCaches,
    )..where((ForumCaches table) => table.accountKey.equals('uid:101'))).get();
    expect(rows, hasLength(ForumLocalRepository.maximumCacheEntriesPerAccount));
    expect(
      rows.map((ForumCache row) => row.cacheKey),
      isNot(contains('item:0')),
    );
  });

  test('请求世代在写入期间失效时回滚该次缓存', () async {
    var checks = 0;
    final bool saved = await repository.saveCacheIfCurrent(
      userId: 101,
      key: 'forum:v2:announcement:7',
      payload: const <String, dynamic>{'title': '旧公告'},
      isCurrent: () => ++checks == 1,
    );

    expect(saved, isFalse);
    expect(
      await repository.loadCache(userId: 101, key: 'forum:v2:announcement:7'),
      isNull,
    );
  });

  test('无效 uid 或空缓存键会被拒绝', () async {
    await expectLater(
      repository.saveCache(
        userId: 0,
        key: 'index',
        payload: const <String, dynamic>{},
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.loadCache(userId: 1, key: ' '),
      throwsArgumentError,
    );
  });
}
