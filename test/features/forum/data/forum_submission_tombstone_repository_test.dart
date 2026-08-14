import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

void main() {
  late AppDatabase database;
  late ForumSubmissionTombstoneRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = ForumSubmissionTombstoneRepository(database);
  });

  tearDown(() => database.close());

  test('同账号同操作上下文原子占位且不持久化正文、formhash 或 cookie', () async {
    final String? attemptId = await repository.claim(
      userId: 42,
      prepared: _prepared,
    );
    expect(attemptId, isNotNull);
    expect(await repository.claim(userId: 42, prepared: _prepared), isNull);

    final ForumActionTombstone row = await database
        .select(database.forumActionTombstones)
        .getSingle();
    expect(row.status, ForumSubmissionTombstoneStatus.pending.name);
    expect(row.accountKey, 'uid:42');
    expect(row.draftContext, 'new-thread:30');
    final String persisted = row.toJson().toString();
    expect(persisted, isNot(contains('正文秘密')));
    expect(persisted, isNot(contains('memory-only-formhash')));
    expect(persisted, isNot(contains('cookie')));

    await repository.markAttempted(
      userId: 42,
      prepared: _prepared,
      attemptId: attemptId!,
    );
    expect(
      (await database.select(database.forumActionTombstones).getSingle())
          .status,
      ForumSubmissionTombstoneStatus.attempted.name,
    );
  });

  test('原子封存 attempted 与草稿清理不留可重发窗口', () async {
    final DateTime now = DateTime.utc(2026, 8, 13);
    for (final int userId in <int>[42, 7]) {
      await database
          .into(database.forumDrafts)
          .insert(
            ForumDraftsCompanion.insert(
              draftId: 'community-pm:conversation:77',
              accountKey: 'uid:$userId',
              action: 'communityPm:conversation',
              tid: const Value<int?>(77),
              subject: '用户A',
              message: '未发送正文',
              attachmentsJson: '{}',
              updatedAt: now,
            ),
          );
    }
    const SubmissionTombstoneKey key = SubmissionTombstoneKey(
      action: 'communityPmSend:conversation',
      threadId: 77,
      draftContext: 'community-pm:conversation:77',
    );

    expect(
      await repository.claimAttemptedKey(
        userId: 42,
        key: key,
        deleteDraft: true,
      ),
      isNotNull,
    );

    final ForumActionTombstone row = await database
        .select(database.forumActionTombstones)
        .getSingle();
    expect(row.status, ForumSubmissionTombstoneStatus.attempted.name);
    expect(
      (await database.select(database.forumDrafts).get()).single.accountKey,
      'uid:7',
    );

    await database
        .into(database.forumDrafts)
        .insert(
          ForumDraftsCompanion.insert(
            draftId: 'community-pm:conversation:77',
            accountKey: 'uid:42',
            action: 'communityPm:conversation',
            tid: const Value<int?>(77),
            subject: '用户A',
            message: '新草稿',
            attachmentsJson: '{}',
            updatedAt: now,
          ),
        );
    expect(
      await repository.claimAttemptedKey(
        userId: 42,
        key: key,
        deleteDraft: true,
      ),
      isNull,
    );
    expect(await database.select(database.forumDrafts).get(), hasLength(2));
  });

  test('封存按 uid 隔离，显式人工核对只解除精确账号记录', () async {
    expect(await repository.claim(userId: 42, prepared: _prepared), isNotNull);
    expect(
      await repository.find(
        userId: 7,
        request: _request,
        readback: _readback,
        draftContext: 'new-thread:30',
      ),
      isNull,
    );
    final ForumUnresolvedSubmission unresolved = (await repository.find(
      userId: 42,
      request: _request,
      readback: _readback,
      draftContext: 'new-thread:30',
    ))!;

    expect(await repository.acknowledge(unresolved), isTrue);
    expect(
      await database.select(database.forumActionTombstones).get(),
      isEmpty,
    );
    expect(await repository.acknowledge(unresolved), isFalse);
  });

  test('明确成功时草稿清理与封存解除处于同一事务且不影响其他账号', () async {
    final DateTime now = DateTime.utc(2026, 8, 13);
    for (final int userId in <int>[42, 7]) {
      await database
          .into(database.forumDrafts)
          .insert(
            ForumDraftsCompanion.insert(
              draftId: 'new-thread:30',
              accountKey: 'uid:$userId',
              action: ForumActionKind.newThread.name,
              fid: const Value<int?>(30),
              subject: '标题',
              message: '正文',
              attachmentsJson: '{}',
              updatedAt: now,
            ),
          );
    }
    final String attemptId = (await repository.claim(
      userId: 42,
      prepared: _prepared,
    ))!;
    await repository.markAttempted(
      userId: 42,
      prepared: _prepared,
      attemptId: attemptId,
    );

    await repository.resolveTrustedOutcome(
      userId: 42,
      prepared: _prepared,
      attemptId: attemptId,
      deleteDraft: true,
    );

    expect(
      await database.select(database.forumActionTombstones).get(),
      isEmpty,
    );
    final List<ForumDraft> drafts = await database
        .select(database.forumDrafts)
        .get();
    expect(drafts.single.accountKey, 'uid:7');
  });
}

final Uri _entryUri = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=newthread&fid=30&mobile=2',
);
final Uri _readbackUri = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=30&mobile=2',
);
final ForumActionRequest _request = ForumActionRequest(
  kind: ForumActionKind.newThread,
  target: const ForumActionTarget(boardId: 30),
  entryUri: _entryUri,
  readbackUri: _readbackUri,
);
final ForumReadbackDescriptor _readback = ForumReadbackDescriptor(
  kind: ForumReadbackKind.boardThreads,
  uri: _readbackUri,
  target: _request.target,
  description: '回读版块',
);
final ForumPreparedAction _prepared = ForumPreparedAction(
  token: 'memory-only-token',
  userId: 42,
  request: _request,
  form: DynamicForumForm(
    sourceUri: _entryUri,
    actionUri: _entryUri,
    hiddenFields: const <String, List<String>>{
      'formhash': <String>['memory-only-formhash'],
    },
    submitFields: const <String, List<String>>{},
    fields: const <DynamicForumField>[
      DynamicForumField(
        name: 'message',
        label: '正文',
        type: DynamicForumFieldType.multiline,
        isRequired: true,
        multiple: false,
        initialValues: <String>['正文秘密'],
        options: <DynamicForumFieldOption>[],
      ),
    ],
    attachmentFields: const <ForumAttachmentField>[],
    preparedAt: DateTime.utc(2026, 8, 13),
  ),
  readback: _readback,
  draftContext: 'new-thread:30',
);
