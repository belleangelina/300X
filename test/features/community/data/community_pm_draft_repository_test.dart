import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/community/data/community_pm_draft_repository.dart';
import 'package:x300/features/community/domain/community_pm_action_models.dart';

class _MockForumClient extends Mock implements ForumClient {}

void main() {
  late AppDatabase database;
  late _MockForumClient client;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    client = _MockForumClient();
    when(() => client.withActiveAccount<void>(42, any())).thenAnswer(
      (Invocation invocation) =>
          (invocation.positionalArguments[1] as Future<void> Function())(),
    );
    when(
      () => client.withActiveAccount<CommunityPmDraft?>(42, any()),
    ).thenAnswer(
      (Invocation invocation) =>
          (invocation.positionalArguments[1]
                  as Future<CommunityPmDraft?> Function())(),
    );
  });

  tearDown(() => database.close());

  test('未发送草稿按 uid 和会话目标往返且不包含临时表单字段', () async {
    final CommunityPmDraftRepository repository =
        CommunityPmDraftRepository(database, client, 42);
    final DateTime updatedAt = DateTime.utc(2026, 8, 13, 2);
    await repository.save(
      'community-pm:conversation:77',
      CommunityPmDraft(
        userId: 42,
        context: CommunityPmSendContext.conversation,
        peerUserId: 77,
        username: '用户A',
        message: '未发送正文',
        updatedAt: updatedAt,
      ),
    );

    final CommunityPmDraft? restored = await repository.load(
      'community-pm:conversation:77',
    );
    expect(restored?.userId, 42);
    expect(restored?.peerUserId, 77);
    expect(restored?.message, '未发送正文');
    final ForumDraft row = await database.select(database.forumDrafts).getSingle();
    expect(row.accountKey, 'uid:42');
    expect(row.action, 'communityPm:conversation');
    expect(row.attachmentsJson, isNot(contains('formhash')));
    expect(row.attachmentsJson, isNot(contains('seccode')));
  });

  test('不同账号无权读取且错目标草稿不会写入', () async {
    final CommunityPmDraftRepository repository =
        CommunityPmDraftRepository(database, client, 42);
    expect(
      () => repository.save(
        'community-pm:conversation:77',
        CommunityPmDraft(
          userId: 7,
          context: CommunityPmSendContext.conversation,
          peerUserId: 77,
          username: '用户A',
          message: '正文',
          updatedAt: DateTime.now(),
        ),
      ),
      throwsStateError,
    );
    expect(
      () => repository.save(
        'community-pm:compose',
        CommunityPmDraft(
          userId: 42,
          context: CommunityPmSendContext.compose,
          peerUserId: 77,
          username: '用户A',
          message: '正文',
          updatedAt: DateTime.now(),
        ),
      ),
      throwsStateError,
    );
    expect(await database.select(database.forumDrafts).get(), isEmpty);
  });

  test('删除草稿也受当前账号租约保护', () async {
    final CommunityPmDraftRepository repository =
        CommunityPmDraftRepository(database, client, 42);
    await repository.save(
      'community-pm:compose',
      CommunityPmDraft(
        userId: 42,
        context: CommunityPmSendContext.compose,
        peerUserId: 0,
        username: '用户A',
        message: '正文',
        updatedAt: DateTime.now(),
      ),
    );
    await repository.delete('community-pm:compose');
    expect(await database.select(database.forumDrafts).get(), isEmpty);
    verify(() => client.withActiveAccount<void>(42, any())).called(2);
  });
}
