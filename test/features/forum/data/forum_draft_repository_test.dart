import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/forum/data/forum_draft_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

class _MockForumClient extends Mock implements ForumClient {}

void main()
{
    late AppDatabase database;
    late _MockForumClient client;

    setUp(()
    {
        database = AppDatabase(NativeDatabase.memory());
        client = _MockForumClient();
        when(() => client.withActiveAccount<void>(101, any()))
            .thenAnswer((Invocation invocation) =>
                (invocation.positionalArguments[1]
                    as Future<void> Function())());
        when(() => client.withActiveAccount<ForumActionDraft?>(101, any()))
            .thenAnswer((Invocation invocation) =>
                (invocation.positionalArguments[1]
                    as Future<ForumActionDraft?> Function())());
        when(() => client.withActiveAccount<List<ForumActionDraft>>(101, any()))
            .thenAnswer((Invocation invocation) =>
                (invocation.positionalArguments[1]
                    as Future<List<ForumActionDraft>> Function())());
    });

    tearDown(() => database.close());

    test('动态用户字段按 uid 往返且不保存临时表单字段', () async
    {
        final ForumDraftRepository repository = ForumDraftRepository(
            database,
            client,
            101,
        );
        final DateTime updatedAt = DateTime.utc(2026, 8, 13, 1);
        await repository.save('new-thread:30', ForumActionDraft(
            userId: 101,
            kind: ForumActionKind.newThread,
            target: const ForumActionTarget(boardId: 30),
            values: const <String, List<String>>{
                'subject': <String>['测试标题'],
                'message': <String>['草稿正文'],
                'typeid': <String>['7'],
                'tags[]': <String>['a', 'b'],
            },
            updatedAt: updatedAt,
        ));

        final ForumActionDraft? restored =
            await repository.load('new-thread:30');
        expect(restored?.userId, 101);
        expect(restored?.kind, ForumActionKind.newThread);
        expect(restored?.target.boardId, 30);
        expect(restored?.values['typeid'], <String>['7']);
        expect(restored?.values['tags[]'], <String>['a', 'b']);
        expect(restored?.updatedAt.toUtc(), updatedAt);
        final ForumDraft row =
            await database.select(database.forumDrafts).getSingle();
        expect(row.attachmentsJson, isNot(contains('formhash')));
    });

    test('账号不匹配与敏感字段 fail closed', () async
    {
        final ForumDraftRepository repository = ForumDraftRepository(
            database,
            client,
            101,
        );
        expect(
            () => ForumActionDraft(
                userId: 101,
                kind: ForumActionKind.reply,
                target: const ForumActionTarget(threadId: 20),
                values: const <String, List<String>>{
                    'formhash': <String>['secret'],
                },
                updatedAt: DateTime.now(),
            ),
            throwsArgumentError,
        );
        expect(
            () => repository.save('reply:20', ForumActionDraft(
                    userId: 202,
                    kind: ForumActionKind.reply,
                    target: const ForumActionTarget(threadId: 20),
                    values: const <String, List<String>>{
                        'message': <String>['正文'],
                    },
                    updatedAt: DateTime.now(),
                )),
            throwsStateError,
        );
        expect(await database.select(database.forumDrafts).get(), isEmpty);
    });

    test('列表排序、删除和账号租约生效', () async
    {
        final ForumDraftRepository repository = ForumDraftRepository(
            database,
            client,
            101,
        );
        for (final int threadId in <int>[1, 2])
        {
            await repository.save('reply:$threadId', ForumActionDraft(
                userId: 101,
                kind: ForumActionKind.reply,
                target: ForumActionTarget(threadId: threadId),
                values: <String, List<String>>{
                    'message': <String>['正文 $threadId'],
                },
                updatedAt: DateTime.utc(2026, 8, 13, threadId),
            ));
        }
        expect(
            (await repository.list())
                .map((ForumActionDraft value) => value.target.threadId),
            <int?>[2, 1],
        );
        await repository.delete('reply:1', userId: 101);
        expect((await repository.list()).single.target.threadId, 2);
        verify(() => client.withActiveAccount<void>(101, any())).called(3);

        expect(
            () => repository.delete('reply:2', userId: 202),
            throwsStateError,
        );
    });
}
