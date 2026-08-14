import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/forum/data/forum_action_repository.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

class _MockForumClient extends Mock implements ForumClient {}

void main() {
  late AppDatabase database;
  late ForumSubmissionTombstoneRepository tombstones;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://bbs.yamibo.com/'));
  });

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    tombstones = ForumSubmissionTombstoneRepository(database);
  });

  tearDown(() => database.close());

  test('编辑只提交声明字段，成功样式响应仍为 unknown 并按楼层回读', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(() => client.getText(_entry)).thenAnswer(
      (_) async => _response(_editForm(), _entry),
    );
    when(
      () => client.postForm(
        _action,
        fields: any(named: 'fields'),
        referer: _entry.toString(),
      ),
    ).thenAnswer(
      (_) async => _response(
        '''{"Message":{"messageval":"post_edit_succeed","messagestr":"已保存"},"Variables":{"member_uid":"42"}}''',
        _action,
      ),
    );
    final ForumActionRepository repository = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction prepared = await repository.prepare(_request);

    final ForumSubmissionResult result = await repository.submit(
      prepared,
      <String, Object?>{'message': '修改后的正文'},
    );

    expect(result.status, ForumSubmissionStatus.resultUnknown);
    expect(result.submissionAttempted, isTrue);
    expect(result.readback.kind, ForumReadbackKind.post);
    expect(result.readback.uri, _readback);
    final Map<Object?, Object?> payload = verify(
      () => client.postForm(
        _action,
        fields: captureAny(named: 'fields'),
        referer: _entry.toString(),
      ),
    ).captured.single as Map<Object?, Object?>;
    expect(payload['fid'], '30');
    expect(payload['tid'], '101');
    expect(payload['pid'], '202');
    expect(payload['page'], '2');
    expect(payload['editsubmit'], 'yes');
    expect(payload['subject'], '原主题');
    expect(payload['message'], '修改后的正文');
    expect(payload, isNot(contains('Filedata')));
    expect(
      await tombstones.find(
        userId: 42,
        request: _request,
        readback: prepared.readback,
        draftContext: prepared.draftContext,
      ),
      isNotNull,
    );
  });

  test('编辑 message 必填且附件在 claim 前 fail closed，修正后仍可提交', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(() => client.getText(_entry)).thenAnswer(
      (_) async => _response(_editForm(), _entry),
    );
    when(
      () => client.postForm(
        _action,
        fields: any(named: 'fields'),
        referer: _entry.toString(),
      ),
    ).thenAnswer(
      (_) async => _response(
        '''{"Message":{"messageval":"post_edit_succeed"},"Variables":{"member_uid":"42"}}''',
        _action,
      ),
    );
    final ForumActionRepository repository = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction prepared = await repository.prepare(_request);

    final ForumSubmissionResult empty = await repository.submit(
      prepared,
      <String, Object?>{'subject': '', 'message': '   '},
    );
    expect(empty.status, ForumSubmissionStatus.explicitFailure);
    expect(empty.submissionAttempted, isFalse);
    expect(empty.canRetryPrepared, isTrue);

    final ForumSubmissionResult attachment = await repository.submit(
      prepared,
      const <String, Object?>{'subject': '', 'message': '正文'},
      attachments: const <ForumAttachmentSelection>[
        ForumAttachmentSelection(
          fieldName: 'Filedata',
          fileName: 'image.png',
          localPath: '/tmp/image.png',
          length: 10,
        ),
      ],
    );
    expect(attachment.status, ForumSubmissionStatus.explicitFailure);
    expect(attachment.submissionAttempted, isFalse);
    expect(attachment.canRetryPrepared, isTrue);

    final ForumSubmissionResult suppliedFile = await repository.submit(
      prepared,
      const <String, Object?>{
        'subject': '',
        'message': '正文',
        'Filedata': '/tmp/image.png',
      },
    );
    expect(suppliedFile.status, ForumSubmissionStatus.explicitFailure);
    expect(suppliedFile.submissionAttempted, isFalse);

    expect(
      await tombstones.find(
        userId: 42,
        request: _request,
        readback: prepared.readback,
        draftContext: prepared.draftContext,
      ),
      isNull,
    );
    verifyNever(
      () => client.postForm(
        any(),
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    );

    final ForumSubmissionResult corrected = await repository.submit(
      prepared,
      const <String, Object?>{'subject': '', 'message': '正文'},
    );
    expect(corrected.status, ForumSubmissionStatus.resultUnknown);
    verify(
      () => client.postForm(
        _action,
        fields: any(named: 'fields'),
        referer: _entry.toString(),
      ),
    ).called(1);
  });

  test('同一 pid 的多个 prepared 与仓库重建都只能 POST 一次', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(() => client.getText(_entry)).thenAnswer(
      (_) async => _response(_editForm(), _entry),
    );
    when(
      () => client.postForm(
        _action,
        fields: any(named: 'fields'),
        referer: _entry.toString(),
      ),
    ).thenAnswer(
      (_) async => _response(
        '''{"Message":{"messageval":"post_edit_succeed"},"Variables":{"member_uid":"42"}}''',
        _action,
      ),
    );
    final ForumActionRepository repository = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction first = await repository.prepare(_request);
    final ForumPreparedAction second = await repository.prepare(_request);

    expect(
      (await repository.submit(
        first,
        const <String, Object?>{'subject': '', 'message': '只改一次'},
      )).status,
      ForumSubmissionStatus.resultUnknown,
    );
    await expectLater(
      repository.submit(
        second,
        const <String, Object?>{'subject': '', 'message': '不得再改'},
      ),
      throwsA(isA<ForumSubmissionBlockedException>()),
    );
    verify(
      () => client.postForm(
        _action,
        fields: any(named: 'fields'),
        referer: _entry.toString(),
      ),
    ).called(1);

    final Uri movedEntry = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=31&tid=102&pid=202&page=3&mobile=2',
    );
    final ForumActionRequest movedRequest = ForumActionRequest(
      kind: ForumActionKind.editPost,
      target: const ForumActionTarget(
        boardId: 31,
        threadId: 102,
        postId: 202,
      ),
      entryUri: movedEntry,
      readbackUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&pid=202&ptid=102&mobile=2',
      ),
    );
    final ForumActionRepository rebuilt = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    await expectLater(
      rebuilt.prepare(movedRequest),
      throwsA(
        isA<ForumSubmissionBlockedException>().having(
          (ForumSubmissionBlockedException error) =>
              error.submission.draftContext,
          'draftContext',
          'edit-post:202',
        ),
      ),
    );
    verifyNever(() => client.getText(movedEntry));
  });

  test('服务端明确失败可解除封存且不被误判成功', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(() => client.getText(_entry)).thenAnswer(
      (_) async => _response(_editForm(), _entry),
    );
    when(
      () => client.postForm(
        _action,
        fields: any(named: 'fields'),
        referer: _entry.toString(),
      ),
    ).thenAnswer(
      (_) async => _response(
        '''{"Message":{"messageval":"post_edit_message_invalid"},"Variables":{"member_uid":"42"}}''',
        _action,
      ),
    );
    final ForumActionRepository repository = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction prepared = await repository.prepare(_request);

    final ForumSubmissionResult result = await repository.submit(
      prepared,
      const <String, Object?>{'subject': '', 'message': '正文'},
    );

    expect(result.status, ForumSubmissionStatus.explicitFailure);
    expect(result.status, isNot(ForumSubmissionStatus.success));
    expect(
      await tombstones.find(
        userId: 42,
        request: _request,
        readback: prepared.readback,
        draftContext: prepared.draftContext,
      ),
      isNull,
    );
    expect(await repository.prepare(_request), isA<ForumPreparedAction>());
    verify(() => client.getText(_entry)).called(2);
  });
}

void _stubLeases(_MockForumClient client) {
  when(
    () => client.withActiveAccount<ForumPreparedAction>(42, any()),
  ).thenAnswer((Invocation invocation) {
    final Future<ForumPreparedAction> Function() operation =
        invocation.positionalArguments[1]
            as Future<ForumPreparedAction> Function();
    return operation();
  });
  when(
    () => client.withActiveAccount<ForumSubmissionResult>(42, any()),
  ).thenAnswer((Invocation invocation) {
    final Future<ForumSubmissionResult> Function() operation =
        invocation.positionalArguments[1]
            as Future<ForumSubmissionResult> Function();
    return operation();
  });
}

Response<String> _response(String source, Uri uri) {
  return Response<String>(
    requestOptions: RequestOptions(path: uri.toString()),
    data: source,
    statusCode: 200,
  );
}

final Uri _entry = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=30&tid=101&pid=202&page=2&mobile=2',
);
final Uri _action = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=edit&editsubmit=yes&extra=&mobile=2',
);
final Uri _readback = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&pid=202&ptid=101&mobile=2',
);
final ForumActionRequest _request = ForumActionRequest(
  kind: ForumActionKind.editPost,
  target: const ForumActionTarget(boardId: 30, threadId: 101, postId: 202),
  entryUri: _entry,
  readbackUri: _readback,
);

String _editForm() {
  return '''
    <html><body id="forum" class="pg_post">
      <script>var discuz_uid = '42';</script>
      <form id="postform" method="post" enctype="multipart/form-data"
        action="forum.php?mod=post&amp;action=edit&amp;editsubmit=yes&amp;extra=&amp;mobile=2">
        <input type="hidden" name="formhash" value="memory-only" />
        <input type="hidden" name="posttime" value="1" />
        <input type="hidden" name="fid" value="30" />
        <input type="hidden" name="tid" value="101" />
        <input type="hidden" name="pid" value="202" />
        <input type="hidden" name="page" value="2" />
        <input type="text" name="subject" value="原主题" />
        <textarea name="message">原正文</textarea>
        <input id="filedata" type="file" name="Filedata" multiple />
        <input id="attfiledata" type="file" name="Filedata" multiple />
        <input type="checkbox" name="usesig" value="1" checked />
        <input type="hidden" name="editsubmit" value="yes" />
        <button id="postsubmit">保存</button>
      </form>
    </body></html>
  ''';
}
