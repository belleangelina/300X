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

  test('回复只提交已声明正文且未知结果按 tid 阻断移版换页重发', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client);
    _stubSubmitLease(client);
    when(() => client.getText(_replyEntry)).thenAnswer(
      (_) async => _response(_replyForm(), _replyEntry),
    );
    when(
      () => client.postForm(
        _replyAction,
        fields: any(named: 'fields'),
        referer: _replyEntry.toString(),
      ),
    ).thenAnswer(
      (_) async => _response(
        '''{"Message":{"messageval":"post_reply_succeed","messagestr":"回复成功"},"Variables":{"member_uid":"42"}}''',
        _replyAction,
      ),
    );
    final ForumActionRepository first = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction prepared = await first.prepare(_replyRequest);

    final ForumSubmissionResult result = await first.submit(
      prepared,
      <String, Object?>{'message': '仅此一次'},
    );

    expect(result.status, ForumSubmissionStatus.resultUnknown);
    expect(result.submissionAttempted, isTrue);
    final Map<Object?, Object?> payload = verify(
      () => client.postForm(
        _replyAction,
        fields: captureAny(named: 'fields'),
        referer: _replyEntry.toString(),
      ),
    ).captured.single as Map<Object?, Object?>;
    expect(payload['message'], '仅此一次');
    expect(payload['replysubmit'], 'yes');
    expect(payload, isNot(contains('Filedata')));

    final Uri nextPageEntry = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=31&tid=101&page=3&reppost=303&mobile=2',
    );
    final ForumActionRequest nextPageRequest = ForumActionRequest(
      kind: ForumActionKind.reply,
      target: const ForumActionTarget(boardId: 31, threadId: 101),
      entryUri: nextPageEntry,
      readbackUri: _readback,
    );
    final ForumActionRepository rebuilt = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    await expectLater(
      rebuilt.prepare(nextPageRequest),
      throwsA(
        isA<ForumSubmissionBlockedException>().having(
          (ForumSubmissionBlockedException error) =>
              error.submission.draftContext,
          'draftContext',
          'reply:101',
        ),
      ),
    );
    verifyNever(() => client.getText(nextPageEntry));
  });

  test('引用回复未知结果按 pid 阻断辅助版块主题漂移后的重发', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client);
    _stubSubmitLease(client);
    when(() => client.getText(_quoteEntry)).thenAnswer(
      (_) async => _response(_quoteForm(), _quoteEntry),
    );
    when(
      () => client.postForm(
        _quoteAction,
        fields: any(named: 'fields'),
        referer: _quoteEntry.toString(),
      ),
    ).thenAnswer(
      (_) async => _response(
        '''{"Message":{"messageval":"post_reply_succeed","messagestr":"回复成功"},"Variables":{"member_uid":"42"}}''',
        _quoteAction,
      ),
    );
    final ForumActionRepository first = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction prepared = await first.prepare(_quoteRequest);

    final ForumSubmissionResult result = await first.submit(
      prepared,
      <String, Object?>{'message': '引用一次'},
    );

    expect(result.status, ForumSubmissionStatus.resultUnknown);
    final Map<Object?, Object?> payload = verify(
      () => client.postForm(
        _quoteAction,
        fields: captureAny(named: 'fields'),
        referer: _quoteEntry.toString(),
      ),
    ).captured.single as Map<Object?, Object?>;
    expect(payload['message'], '引用一次');
    expect(payload['replysubmit'], 'yes');
    expect(payload, isNot(contains('Filedata')));

    final Uri movedEntry = Uri.parse(
      'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=31&tid=102&page=3&repquote=202&extra=page%3D3&mobile=2',
    );
    final ForumActionRequest movedRequest = ForumActionRequest(
      kind: ForumActionKind.quoteReply,
      target: const ForumActionTarget(
        boardId: 31,
        threadId: 102,
        postId: 202,
      ),
      entryUri: movedEntry,
      readbackUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=102&mobile=2',
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
          'quote-reply:202',
        ),
      ),
    );
    verifyNever(() => client.getText(movedEntry));
  });
}

void _stubPrepareLease(_MockForumClient client) {
  when(
    () => client.withActiveAccount<ForumPreparedAction>(42, any()),
  ).thenAnswer((Invocation invocation) {
    final Future<ForumPreparedAction> Function() operation =
        invocation.positionalArguments[1]
            as Future<ForumPreparedAction> Function();
    return operation();
  });
}

void _stubSubmitLease(_MockForumClient client) {
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

final Uri _replyEntry = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=30&tid=101&page=2&reppost=202&mobile=2',
);
final Uri _replyAction = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=30&tid=101&replysubmit=yes&extra=&mobile=2',
);
final Uri _quoteEntry = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=30&tid=101&page=2&repquote=202&extra=page%3D2&mobile=2',
);
final Uri _quoteAction = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=30&tid=101&replysubmit=yes&extra=page%3D2&mobile=2',
);
final Uri _readback = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101&mobile=2',
);
final ForumActionRequest _replyRequest = ForumActionRequest(
  kind: ForumActionKind.reply,
  target: const ForumActionTarget(boardId: 30, threadId: 101),
  entryUri: _replyEntry,
  readbackUri: _readback,
);
final ForumActionRequest _quoteRequest = ForumActionRequest(
  kind: ForumActionKind.quoteReply,
  target: const ForumActionTarget(boardId: 30, threadId: 101, postId: 202),
  entryUri: _quoteEntry,
  readbackUri: _readback,
);

String _replyForm() {
  return '''
    <html><body id="forum" class="pg_post">
      <script>var discuz_uid = '42';</script>
      <form id="postform" method="post"
        action="forum.php?mod=post&amp;action=reply&amp;fid=30&amp;tid=101&amp;replysubmit=yes&amp;extra=&amp;mobile=2">
        <input type="hidden" name="formhash" value="memory-only" />
        <input type="hidden" name="reppid" value="202" />
        <input type="hidden" name="reppost" value="202" />
        <textarea id="needmessage" name="message"></textarea>
        <input id="filedata" type="file" name="Filedata" multiple />
        <input id="attfiledata" type="file" name="Filedata" multiple />
        <input type="hidden" name="replysubmit" value="yes" />
        <button id="postsubmit">回复</button>
      </form>
    </body></html>
  ''';
}

String _quoteForm() {
  return _replyForm().replaceFirst(
    'replysubmit=yes&amp;extra=&amp;mobile=2',
    'replysubmit=yes&amp;extra=page%3D2&amp;mobile=2',
  );
}
