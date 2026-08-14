import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/community/data/community_pm_action_repository.dart';
import 'package:x300/features/community/domain/community_pm_action_models.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';

class _MockForumClient extends Mock implements ForumClient {}

class _MockTombstones extends Mock
    implements ForumSubmissionTombstoneRepository {}

void main() {
  late AppDatabase database;
  late ForumSubmissionTombstoneRepository tombstones;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://bbs.yamibo.com/'));
    registerFallbackValue(
      const SubmissionTombstoneKey(action: 'test', draftContext: 'test'),
    );
  });

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    tombstones = ForumSubmissionTombstoneRepository(database);
  });

  tearDown(() => database.close());

  test('prepare 和一次 POST 全程持有账号租约且只发白名单字段', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_formHtml(), _entryUri));
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).thenAnswer((_) async => _response(_authenticatedResponse, _actionUri));
    final CommunityPmActionRepository repository = CommunityPmActionRepository(
      client,
      42,
      tombstones,
    );

    final CommunityPmPreparedSend prepared = await repository.prepare(_request);
    final CommunityPmSubmissionResult result = await repository.submit(
      prepared,
      message: '只发送一次',
    );

    expect(result.status, CommunityPmSubmissionStatus.resultUnknown);
    expect(result.submissionAttempted, isTrue);
    final Map<String, dynamic> fields =
        verify(
              () => client.postForm(
                _actionUri,
                fields: captureAny(named: 'fields'),
                referer: _entryUri.toString(),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(fields, <String, dynamic>{
      'formhash': 'one-use-secret',
      'pmsubmit': 'yes',
      'touid': '77',
      'message': '只发送一次',
    });
    verify(
      () => client.withActiveAccount<CommunityPmPreparedSend>(42, any()),
    ).called(1);
    verify(
      () => client.withActiveAccount<CommunityPmSubmissionResult>(42, any()),
    ).called(1);
  });

  test('本地校验失败不消费 token，修正后仍只 POST 一次', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_formHtml(), _entryUri));
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    ).thenAnswer((_) async => _response(_authenticatedResponse, _actionUri));
    final CommunityPmActionRepository repository = CommunityPmActionRepository(
      client,
      42,
      tombstones,
    );
    final CommunityPmPreparedSend prepared = await repository.prepare(_request);

    final CommunityPmSubmissionResult invalid = await repository.submit(
      prepared,
      message: '   ',
    );
    final CommunityPmSubmissionResult sent = await repository.submit(
      prepared,
      message: '修正内容',
    );
    final CommunityPmSubmissionResult repeated = await repository.submit(
      prepared,
      message: '不得重发',
    );

    expect(invalid.canRetryPrepared, isTrue);
    expect(invalid.submissionAttempted, isFalse);
    expect(sent.status, CommunityPmSubmissionStatus.resultUnknown);
    expect(repeated.status, CommunityPmSubmissionStatus.explicitFailure);
    verify(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    ).called(1);
  });

  test('并发双击只消费一个 token 并只 POST 一次', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_formHtml(), _entryUri));
    final Completer<Response<String>> response = Completer<Response<String>>();
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    ).thenAnswer((_) => response.future);
    final CommunityPmActionRepository repository = CommunityPmActionRepository(
      client,
      42,
      tombstones,
    );
    final CommunityPmPreparedSend prepared = await repository.prepare(_request);

    final Future<CommunityPmSubmissionResult> first = repository.submit(
      prepared,
      message: '第一次',
    );
    final Future<CommunityPmSubmissionResult> second = repository.submit(
      prepared,
      message: '第二次',
    );
    response.complete(_response(_authenticatedResponse, _actionUri));

    expect((await first).status, CommunityPmSubmissionStatus.resultUnknown);
    expect((await second).status, CommunityPmSubmissionStatus.explicitFailure);
    verify(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    ).called(1);
  });

  test('POST 异常和无法确认的 final 都是结果未知且绝不重发', () async {
    for (final Future<Response<String>> Function() answer
        in <Future<Response<String>> Function()>[
          () async => throw const ForumConnectionException('响应丢失'),
          () async => _response(
            _authenticatedResponse,
            Uri.parse('https://evil.example/home.php?mobile=2'),
          ),
        ]) {
      await database.delete(database.forumActionTombstones).go();
      final _MockForumClient client = _MockForumClient();
      _stubLeases(client);
      when(
        () => client.getText(_entryUri),
      ).thenAnswer((_) async => _response(_formHtml(), _entryUri));
      when(
        () => client.postForm(
          _actionUri,
          fields: any(named: 'fields'),
          referer: any(named: 'referer'),
        ),
      ).thenAnswer((_) => answer());
      final CommunityPmActionRepository repository =
          CommunityPmActionRepository(client, 42, tombstones);
      final CommunityPmPreparedSend prepared = await repository.prepare(
        _request,
      );

      final CommunityPmSubmissionResult first = await repository.submit(
        prepared,
        message: '一次',
      );
      final CommunityPmSubmissionResult second = await repository.submit(
        prepared,
        message: '不得重发',
      );

      expect(first.status, CommunityPmSubmissionStatus.resultUnknown);
      expect(first.submissionAttempted, isTrue);
      expect(second.status, CommunityPmSubmissionStatus.explicitFailure);
      verify(
        () => client.postForm(
          _actionUri,
          fields: any(named: 'fields'),
          referer: any(named: 'referer'),
        ),
      ).called(1);
    }
  });

  test('prepare 拒绝错 uid 和跨域 GET final，不执行 POST', () async {
    final _MockForumClient wrongUserClient = _MockForumClient();
    _stubLeases(wrongUserClient);
    when(
      () => wrongUserClient.getText(_entryUri),
    ).thenAnswer((_) async => _response(_formHtml(userId: 7), _entryUri));
    await expectLater(
      CommunityPmActionRepository(
        wrongUserClient,
        42,
        tombstones,
      ).prepare(_request),
      throwsA(isA<ForumSessionExpiredException>()),
    );

    final _MockForumClient externalClient = _MockForumClient();
    _stubLeases(externalClient);
    when(() => externalClient.getText(_entryUri)).thenAnswer(
      (_) async => _response(
        _formHtml(),
        Uri.parse('https://evil.example/home.php?mobile=2'),
      ),
    );
    await expectLater(
      CommunityPmActionRepository(
        externalClient,
        42,
        tombstones,
      ).prepare(_request),
      throwsA(isA<ForumException>()),
    );
    verifyNever(
      () => externalClient.postForm(
        any(),
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    );
  });

  test('POST 后响应错 uid 仍为结果未知并要求刷新会话', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_formHtml(), _entryUri));
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    ).thenAnswer(
      (_) async => _response(
        _authenticatedResponse.replaceFirst(
          "discuz_uid='42'",
          "discuz_uid='7'",
        ),
        _actionUri,
      ),
    );
    final CommunityPmActionRepository repository = CommunityPmActionRepository(
      client,
      42,
      tombstones,
    );
    final CommunityPmPreparedSend prepared = await repository.prepare(_request);

    final CommunityPmSubmissionResult result = await repository.submit(
      prepared,
      message: '一次',
    );

    expect(result.status, CommunityPmSubmissionStatus.resultUnknown);
    expect(result.submissionAttempted, isTrue);
    expect(result.requiresSessionRefresh, isTrue);
  });

  test('POST 前原子写 attempted 并清草稿，重建后阻断直到人工解除', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_formHtml(), _entryUri));
    final Completer<void> postStarted = Completer<void>();
    final Completer<Response<String>> postResponse =
        Completer<Response<String>>();
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    ).thenAnswer((_) {
      postStarted.complete();
      return postResponse.future;
    });
    await database
        .into(database.forumDrafts)
        .insert(
          ForumDraftsCompanion.insert(
            draftId: 'community-pm:conversation:77',
            accountKey: 'uid:42',
            action: 'communityPm:conversation',
            tid: const Value<int?>(77),
            subject: '用户A',
            message: '不得恢复为可重发草稿',
            attachmentsJson: '{}',
            updatedAt: DateTime.utc(2026, 8, 13),
          ),
        );
    final CommunityPmActionRepository repository = CommunityPmActionRepository(
      client,
      42,
      tombstones,
    );
    final CommunityPmPreparedSend prepared = await repository.prepare(_request);

    final Future<CommunityPmSubmissionResult> submitting = repository.submit(
      prepared,
      message: '只发送一次',
    );
    await postStarted.future;

    final ForumActionTombstone persisted = await database
        .select(database.forumActionTombstones)
        .getSingle();
    expect(persisted.status, 'attempted');
    expect(persisted.accountKey, 'uid:42');
    expect(persisted.tid, 77);
    expect(await database.select(database.forumDrafts).get(), isEmpty);

    postResponse.complete(_response(_authenticatedResponse, _actionUri));
    expect(
      (await submitting).status,
      CommunityPmSubmissionStatus.resultUnknown,
    );

    final CommunityPmActionRepository rebuilt = CommunityPmActionRepository(
      client,
      42,
      tombstones,
    );
    late CommunityPmSubmissionBlockedException blocked;
    try {
      await rebuilt.prepare(_request);
      fail('重建后应被持久化封存阻断');
    } on CommunityPmSubmissionBlockedException catch (error) {
      blocked = error;
    }
    expect(blocked.tombstone.status.name, 'attempted');

    final _MockForumClient otherAccountClient = _MockForumClient();
    _stubLeases(otherAccountClient, userId: 7);
    when(
      () => otherAccountClient.getText(_entryUri),
    ).thenAnswer((_) async => _response(_formHtml(userId: 7), _entryUri));
    final CommunityPmPreparedSend otherAccountPrepared =
        await CommunityPmActionRepository(
          otherAccountClient,
          7,
          tombstones,
        ).prepare(_request);
    expect(otherAccountPrepared.userId, 7);

    await rebuilt.acknowledgeUnresolved(blocked);
    final CommunityPmPreparedSend reread = await rebuilt.prepare(_request);
    expect(reread.userId, 42);
    verify(() => client.getText(_entryUri)).called(2);
    verify(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    ).called(1);
  });

  test('封存事务落盘失败时零 POST', () async {
    final _MockForumClient client = _MockForumClient();
    final _MockTombstones failedTombstones = _MockTombstones();
    _stubLeases(client);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_formHtml(), _entryUri));
    when(
      () => failedTombstones.findKey(userId: 42, key: any(named: 'key')),
    ).thenAnswer((_) async => null);
    when(
      () => failedTombstones.claimAttemptedKey(
        userId: 42,
        key: any(named: 'key'),
        deleteDraft: true,
      ),
    ).thenThrow(StateError('本地持久化失败'));
    final CommunityPmActionRepository repository = CommunityPmActionRepository(
      client,
      42,
      failedTombstones,
    );
    final CommunityPmPreparedSend prepared = await repository.prepare(_request);

    await expectLater(
      repository.submit(prepared, message: '不得发出'),
      throwsStateError,
    );

    verifyNever(
      () => client.postForm(
        any(),
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    );
  });

  test('新私信封存按规范化收件人隔离且不落盘明文', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(
      () => client.getText(_composeEntryUri),
    ).thenAnswer((_) async => _response(_composeFormHtml(), _composeEntryUri));
    when(
      () => client.postForm(
        _composeActionUri,
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    ).thenAnswer(
      (_) async => _response(_authenticatedResponse, _composeActionUri),
    );

    final CommunityPmActionRepository first = CommunityPmActionRepository(
      client,
      42,
      tombstones,
    );
    final CommunityPmPreparedSend firstPrepared = await first.prepare(
      _composeRequest,
    );
    expect(
      (await first.submit(
        firstPrepared,
        message: '给 Alice',
        username: 'Alice',
      )).submissionAttempted,
      isTrue,
    );

    final CommunityPmActionRepository rebuilt = CommunityPmActionRepository(
      client,
      42,
      tombstones,
    );
    final CommunityPmPreparedSend duplicate = await rebuilt.prepare(
      _composeRequest,
    );
    await expectLater(
      rebuilt.submit(duplicate, message: '不得重发', username: '  alice  '),
      throwsA(isA<CommunityPmSubmissionBlockedException>()),
    );

    final CommunityPmPreparedSend otherTarget = await rebuilt.prepare(
      _composeRequest,
    );
    expect(
      (await rebuilt.submit(
        otherTarget,
        message: '给 Bob',
        username: 'Bob',
      )).submissionAttempted,
      isTrue,
    );
    final List<ForumActionTombstone> rows = await database
        .select(database.forumActionTombstones)
        .get();
    expect(rows, hasLength(2));
    expect(
      rows.map((ForumActionTombstone row) => row.contextKey).toSet(),
      hasLength(2),
    );
    final String persisted = rows
        .map((ForumActionTombstone row) => row.toJson())
        .toList()
        .toString()
        .toLowerCase();
    expect(persisted, isNot(contains('alice')));
    expect(persisted, isNot(contains('bob')));
    verify(
      () => client.postForm(
        _composeActionUri,
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    ).called(2);
  });
}

void _stubLeases(_MockForumClient client, {int userId = 42}) {
  when(
    () => client.withActiveAccount<CommunityPmPreparedSend>(userId, any()),
  ).thenAnswer(
    (Invocation invocation) =>
        (invocation.positionalArguments[1]
            as Future<CommunityPmPreparedSend> Function())(),
  );
  when(
    () => client.withActiveAccount<CommunityPmSubmissionResult>(userId, any()),
  ).thenAnswer(
    (Invocation invocation) =>
        (invocation.positionalArguments[1]
            as Future<CommunityPmSubmissionResult> Function())(),
  );
  when(() => client.withActiveAccount<void>(userId, any())).thenAnswer(
    (Invocation invocation) =>
        (invocation.positionalArguments[1] as Future<void> Function())(),
  );
}

Response<String> _response(String source, Uri uri) {
  return Response<String>(
    requestOptions: RequestOptions(path: uri.toString()),
    data: source,
    statusCode: 200,
  );
}

final Uri _entryUri = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=space&do=pm&subop=view&touid=77&mobile=2',
);
final Uri _actionUri = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=spacecp&ac=pm&op=send&pmid=123&pmsubmit=yes&daterange=2&mobile=2',
);
final Uri _composeEntryUri = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=spacecp&ac=pm&mobile=2',
);
final Uri _composeActionUri = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=spacecp&ac=pm&op=send&pmid=0&touid=0&mobile=2',
);
final CommunityPmSendRequest _request = CommunityPmSendRequest(
  context: CommunityPmSendContext.conversation,
  entryUri: _entryUri,
  expectedPeerUserId: 77,
  expectedPeerUsername: '用户A',
);
final CommunityPmSendRequest _composeRequest = CommunityPmSendRequest(
  context: CommunityPmSendContext.compose,
  entryUri: _composeEntryUri,
);

String _formHtml({int userId = 42}) =>
    '''
<!doctype html><html><body id="home" class="pg_space">
<script>var discuz_uid='$userId';</script>
<form id="pmform" method="post" action="$_actionUri">
  <input type="hidden" name="formhash" value="one-use-secret">
  <input type="hidden" name="touid" value="77">
  <input type="text" name="message" value="">
  <button name="pmsubmit" value="yes">发送</button>
</form>
</body></html>
''';

String _composeFormHtml({int userId = 42}) =>
    '''
<!doctype html><html><body id="home" class="pg_spacecp">
<script>var discuz_uid='$userId';</script>
<form method="post" action="$_composeActionUri">
  <input type="hidden" name="formhash" value="one-use-secret">
  <input type="text" name="username" value="">
  <textarea name="message"></textarea>
  <input type="hidden" name="referer" value="home.php?mod=space&amp;do=pm&amp;mobile=2">
  <input type="hidden" name="pmsubmit" value="yes">
</form>
</body></html>
''';

const String _authenticatedResponse = '''
<!doctype html><html><body id="home" class="pg_spacecp">
<script>var discuz_uid='42';</script><div class="showmessage">[已脱敏]</div>
</body></html>
''';
