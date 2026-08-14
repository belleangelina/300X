import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/forum/data/forum_action_repository.dart';
import 'package:x300/features/forum/data/forum_action_response_parser.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

class _MockForumClient extends Mock implements ForumClient {}

class _ThrowingResponseParser extends ForumActionResponseParser {
  const _ThrowingResponseParser();

  @override
  ForumSubmissionResult parse(
    String source,
    Uri responseUri,
    ForumPreparedAction prepared,
  ) {
    throw const ForumParseException('响应模板漂移');
  }
}

class _FailingClaimTombstoneRepository
    extends ForumSubmissionTombstoneRepository {
  _FailingClaimTombstoneRepository(super.database);

  @override
  Future<String?> claimAttempted({
    required int userId,
    required ForumPreparedAction prepared,
  }) {
    throw StateError('磁盘写入失败');
  }
}

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

  test('prepare 的入口、GET final 与精确 uid 均绑定同一账号租约', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client, 42);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    final ForumActionRepository repository = ForumActionRepository(
      client,
      42,
      tombstones,
    );

    final ForumPreparedAction prepared = await repository.prepare(_request);

    expect(prepared.userId, 42);
    expect(prepared.form.formHash, 'one-use-secret');
    verify(
      () => client.withActiveAccount<ForumPreparedAction>(42, any()),
    ).called(1);
    verify(() => client.getText(_entryUri)).called(1);
  });

  test('prepare 拒绝外域 GET final 和错 uid', () async {
    final _MockForumClient externalClient = _MockForumClient();
    _stubPrepareLease(externalClient, 42);
    when(() => externalClient.getText(_entryUri)).thenAnswer(
      (_) async => _response(
        _newThreadForm(),
        Uri.parse('https://evil.example/forum.php?mobile=2'),
      ),
    );
    await expectLater(
      ForumActionRepository(externalClient, 42, tombstones).prepare(_request),
      throwsA(isA<ForumActionSecurityException>()),
    );

    final _MockForumClient wrongUserClient = _MockForumClient();
    _stubPrepareLease(wrongUserClient, 42);
    when(
      () => wrongUserClient.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(userId: 7), _entryUri));
    await expectLater(
      ForumActionRepository(wrongUserClient, 42, tombstones).prepare(_request),
      throwsA(isA<ForumSessionExpiredException>()),
    );
  });

  test('只提交表单声明字段，服务端成功仍要求回读且不直接改缓存', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client, 42);
    _stubSubmitLease(client, 42);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).thenAnswer((_) async => _response(_successJson, _actionUri));
    final ForumActionRepository repository = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction prepared = await repository.prepare(_request);

    final ForumSubmissionResult result = await repository.submit(
      prepared,
      <String, Object?>{..._values('新主题'), 'typeid': '7'},
    );

    expect(result.status, ForumSubmissionStatus.success);
    expect(result.requiresReadback, isTrue);
    expect(result.permitsCacheMutation, isFalse);
    final Map<String, dynamic> fields =
        verify(
              () => client.postForm(
                _actionUri,
                fields: captureAny(named: 'fields'),
                referer: _entryUri.toString(),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(fields, containsPair('formhash', 'one-use-secret'));
    expect(fields, containsPair('custom_hidden', 'kept'));
    expect(fields, containsPair('topicsubmit', 'yes'));
    expect(fields, containsPair('subject', '测试主题'));
    expect(fields, containsPair('message', '新主题'));
    expect(fields, isNot(contains('not_declared')));
    verify(
      () => client.withActiveAccount<ForumSubmissionResult>(42, any()),
    ).called(1);
  });

  test('未知调用字段与未验证附件 fail closed，且不会 POST', () async {
    final _MockForumClient unknownClient = _MockForumClient();
    _stubPrepareLease(unknownClient, 42);
    _stubSubmitLease(unknownClient, 42);
    when(
      () => unknownClient.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    final ForumActionRepository unknownRepository = ForumActionRepository(
      unknownClient,
      42,
      tombstones,
    );
    final ForumPreparedAction unknownPrepared = await unknownRepository.prepare(
      _request,
    );
    final ForumSubmissionResult unknown = await unknownRepository.submit(
      unknownPrepared,
      <String, Object?>{..._values('正文'), 'not_declared': 'attack'},
    );
    expect(unknown.status, ForumSubmissionStatus.explicitFailure);
    verifyNever(
      () => unknownClient.postForm(
        any(),
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    );

    final _MockForumClient attachmentClient = _MockForumClient();
    _stubPrepareLease(attachmentClient, 42);
    _stubSubmitLease(attachmentClient, 42);
    when(
      () => attachmentClient.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    final ForumActionRepository attachmentRepository = ForumActionRepository(
      attachmentClient,
      42,
      tombstones,
    );
    final ForumPreparedAction attachmentPrepared = await attachmentRepository
        .prepare(_request);
    final ForumSubmissionResult attachment = await attachmentRepository.submit(
      attachmentPrepared,
      _values('正文'),
      attachments: const <ForumAttachmentSelection>[
        ForumAttachmentSelection(
          fieldName: 'Filedata',
          fileName: 'test.png',
          localPath: '/tmp/test.png',
          length: 10,
        ),
      ],
    );
    expect(attachment.status, ForumSubmissionStatus.explicitFailure);
    expect(attachment.message, contains('尚未完成真实移动端验证'));
    verifyNever(
      () => attachmentClient.postForm(
        any(),
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    );
  });

  test('本地校验失败不消费 token，修正输入后才原子消费并 POST', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client, 42);
    _stubSubmitLease(client, 42);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).thenAnswer((_) async => _response(_successJson, _actionUri));
    final ForumActionRepository repository = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction prepared = await repository.prepare(_request);

    final ForumSubmissionResult invalid = await repository.submit(
      prepared,
      <String, Object?>{'message': '缺主题'},
    );
    expect(invalid.status, ForumSubmissionStatus.explicitFailure);
    expect(invalid.submissionAttempted, isFalse);
    expect(invalid.canRetryPrepared, isTrue);
    verifyNever(
      () => client.postForm(
        any(),
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    );

    final ForumSubmissionResult corrected = await repository.submit(
      prepared,
      _values('修正后只提交一次'),
    );
    expect(corrected.status, ForumSubmissionStatus.success);
    expect(corrected.submissionAttempted, isTrue);
    expect(corrected.canRetryPrepared, isFalse);
    verify(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).called(1);
  });

  test('双击同一个 prepared token 只 POST 一次', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client, 42);
    _stubSubmitLease(client, 42);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    final Completer<Response<String>> response = Completer<Response<String>>();
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).thenAnswer((_) => response.future);
    final ForumActionRepository repository = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction prepared = await repository.prepare(_request);

    final Future<ForumSubmissionResult> first = repository.submit(
      prepared,
      _values('一次'),
    );
    final Future<ForumSubmissionResult> second = repository.submit(
      prepared,
      _values('二次'),
    );
    response.complete(_response(_successJson, _actionUri));

    expect((await first).status, ForumSubmissionStatus.success);
    expect((await second).status, ForumSubmissionStatus.explicitFailure);
    verify(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).called(1);
  });

  test('连接丢失返回 resultUnknown 且 token 消耗后绝不重发', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client, 42);
    _stubSubmitLease(client, 42);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).thenThrow(const ForumConnectionException('响应丢失'));
    final ForumActionRepository repository = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction prepared = await repository.prepare(_request);

    final ForumSubmissionResult first = await repository.submit(
      prepared,
      _values('只发一次'),
    );
    final ForumSubmissionResult second = await repository.submit(
      prepared,
      _values('不得重发'),
    );

    expect(first.status, ForumSubmissionStatus.resultUnknown);
    expect(first.requiresReadback, isTrue);
    expect(second.status, ForumSubmissionStatus.explicitFailure);
    verify(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).called(1);
  });

  test('提交超时返回 resultUnknown 且不会重发', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client, 42);
    _stubSubmitLease(client, 42);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).thenThrow(TimeoutException('timeout'));
    final ForumActionRepository repository = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction prepared = await repository.prepare(_request);

    final ForumSubmissionResult first = await repository.submit(
      prepared,
      _values('超时也只提交一次'),
    );
    final ForumSubmissionResult second = await repository.submit(
      prepared,
      _values('不得重发'),
    );

    expect(first.status, ForumSubmissionStatus.resultUnknown);
    expect(first.submissionAttempted, isTrue);
    expect(second.status, ForumSubmissionStatus.explicitFailure);
    verify(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).called(1);
  });

  test('POST final 外域和响应错 uid 均为 resultUnknown，且不会重发', () async {
    final _MockForumClient externalClient = _MockForumClient();
    _stubPrepareLease(externalClient, 42);
    _stubSubmitLease(externalClient, 42);
    when(
      () => externalClient.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    when(
      () => externalClient.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).thenAnswer(
      (_) async => _response(_successJson, Uri.parse('https://evil.example/')),
    );
    final ForumActionRepository externalRepository = ForumActionRepository(
      externalClient,
      42,
      tombstones,
    );
    final ForumPreparedAction externalPrepared = await externalRepository
        .prepare(_request);
    final ForumSubmissionResult external = await externalRepository.submit(
      externalPrepared,
      _values('正文'),
    );
    expect(external.status, ForumSubmissionStatus.resultUnknown);
    expect(external.submissionAttempted, isTrue);
    expect(
      (await externalRepository.submit(
        externalPrepared,
        _values('不得重发'),
      )).status,
      ForumSubmissionStatus.explicitFailure,
    );
    await database.delete(database.forumActionTombstones).go();

    final _MockForumClient wrongUserClient = _MockForumClient();
    _stubPrepareLease(wrongUserClient, 42);
    _stubSubmitLease(wrongUserClient, 42);
    when(
      () => wrongUserClient.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    when(
      () => wrongUserClient.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).thenAnswer(
      (_) async =>
          _response(_successJson.replaceFirst('"42"', '"7"'), _actionUri),
    );
    final ForumActionRepository wrongUserRepository = ForumActionRepository(
      wrongUserClient,
      42,
      tombstones,
    );
    final ForumPreparedAction wrongUserPrepared = await wrongUserRepository
        .prepare(_request);
    final ForumSubmissionResult wrongUser = await wrongUserRepository.submit(
      wrongUserPrepared,
      _values('正文'),
    );
    expect(wrongUser.status, ForumSubmissionStatus.resultUnknown);
    expect(wrongUser.submissionAttempted, isTrue);
    expect(wrongUser.requiresSessionRefresh, isTrue);
    verify(
      () => wrongUserClient.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).called(1);
  });

  test('POST 后响应模板漂移统一为 resultUnknown 且 token 已消费', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client, 42);
    _stubSubmitLease(client, 42);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).thenAnswer((_) async => _response(_identityHtml, _actionUri));
    final ForumActionRepository repository = ForumActionRepository(
      client,
      42,
      tombstones,
      responseParser: const _ThrowingResponseParser(),
    );
    final ForumPreparedAction prepared = await repository.prepare(_request);

    final ForumSubmissionResult drifted = await repository.submit(
      prepared,
      _values('模板漂移'),
    );
    expect(drifted.status, ForumSubmissionStatus.resultUnknown);
    expect(drifted.submissionAttempted, isTrue);
    expect(
      (await repository.submit(prepared, _values('不得重发'))).status,
      ForumSubmissionStatus.explicitFailure,
    );
    verify(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).called(1);
  });

  test('仓库重建与旧账号切换都不能复用旧 prepared token', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client, 42);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    final ForumActionRepository oldRepository = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction prepared = await oldRepository.prepare(_request);

    final ForumSubmissionResult rebuilt = await ForumActionRepository(
      client,
      42,
      tombstones,
    ).submit(prepared, _values('不能提交'));
    final ForumSubmissionResult switched = await ForumActionRepository(
      client,
      7,
      tombstones,
    ).submit(prepared, _values('不能提交'));

    expect(rebuilt.status, ForumSubmissionStatus.explicitFailure);
    expect(switched.status, ForumSubmissionStatus.explicitFailure);
    verifyNever(
      () => client.postForm(
        any(),
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    );
  });

  test('账号 lease 拒绝旧 uid 时不发 GET，回读也完整占用单个 lease', () async {
    final _MockForumClient staleClient = _MockForumClient();
    when(
      () => staleClient.withActiveAccount<ForumPreparedAction>(42, any()),
    ).thenThrow(const ForumSessionExpiredException());
    await expectLater(
      Future<ForumPreparedAction>.sync(
        () => ForumActionRepository(staleClient, 42, tombstones).prepare(
          _request,
        ),
      ),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    verifyNever(() => staleClient.getText(any()));

    final _MockForumClient readbackClient = _MockForumClient();
    _stubReadbackLease(readbackClient, 42);
    when(
      () => readbackClient.getText(_readbackUri),
    ).thenAnswer((_) async => _response(_identityHtml, _readbackUri));
    final ForumReadbackReceipt receipt = await ForumActionRepository(
      readbackClient,
      42,
      tombstones,
    ).readback(_readback);
    expect(receipt.userId, 42);
    expect(receipt.sourceUri, _readbackUri);
    expect(receipt.contentDigest, hasLength(64));
    expect(receipt.contentDigest, isNot(contains('discuz_uid')));
    verify(
      () => readbackClient.withActiveAccount<ForumReadbackReceipt>(42, any()),
    ).called(1);
  });

  test('封存落盘失败时零 POST', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client, 42);
    _stubSubmitLease(client, 42);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    final ForumActionRepository repository = ForumActionRepository(
      client,
      42,
      _FailingClaimTombstoneRepository(database),
    );
    final ForumPreparedAction prepared = await repository.prepare(_request);

    await expectLater(
      repository.submit(prepared, _values('不会发送')),
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

  test('POST 可能发出后仓库重建仍被持久封存阻断，人工核对后才允许重新读取', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client, 42);
    _stubSubmitLease(client, 42);
    _stubReadbackLease(client, 42);
    _stubVoidLease(client, 42);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    when(
      () => client.getText(_readbackUri),
    ).thenAnswer((_) async => _response(_identityHtml, _readbackUri));
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).thenThrow(const ForumConnectionException('响应丢失'));
    final ForumActionRepository first = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction prepared = await first.prepare(_request);
    expect(
      (await first.submit(prepared, _values('只允许发一次'))).status,
      ForumSubmissionStatus.resultUnknown,
    );

    final ForumActionRepository rebuilt = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    ForumUnresolvedSubmission? unresolved;
    try {
      await rebuilt.prepare(_request);
      fail('进程重建后不应重新读取可提交表单');
    } on ForumSubmissionBlockedException catch (error) {
      unresolved = error.submission;
    }
    expect(unresolved.status, ForumSubmissionTombstoneStatus.attempted);
    verify(() => client.getText(_entryUri)).called(1);

    await rebuilt.readbackUnresolved(unresolved);
    await rebuilt.acknowledgeUnresolved(unresolved);
    expect((await rebuilt.prepare(_request)).userId, 42);
    verify(() => client.getText(_entryUri)).called(1);
  });

  test('跨仓库并发提交由数据库复合主键原子阻断为一次 POST', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client, 42);
    _stubSubmitLease(client, 42);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    final Completer<void> postStarted = Completer<void>();
    final Completer<Response<String>> postResponse = Completer<Response<String>>();
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).thenAnswer((_) {
      if (!postStarted.isCompleted) {
        postStarted.complete();
      }
      return postResponse.future;
    });
    final ForumActionRepository first = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumActionRepository second = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction firstPrepared = await first.prepare(_request);
    final ForumPreparedAction secondPrepared = await second.prepare(_request);

    final Future<ForumSubmissionResult> firstResult = first.submit(
      firstPrepared,
      _values('同一操作'),
    );
    await postStarted.future;
    await expectLater(
      second.submit(secondPrepared, _values('同一操作')),
      throwsA(isA<ForumSubmissionBlockedException>()),
    );
    postResponse.complete(_response(_successJson, _actionUri));
    expect((await firstResult).status, ForumSubmissionStatus.success);
    verify(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).called(1);
  });

  test('明确成功在返回 UI 前原子清理草稿与封存，重建不会恢复旧正文', () async {
    final _MockForumClient client = _MockForumClient();
    _stubPrepareLease(client, 42);
    _stubSubmitLease(client, 42);
    when(
      () => client.getText(_entryUri),
    ).thenAnswer((_) async => _response(_newThreadForm(), _entryUri));
    when(
      () => client.postForm(
        _actionUri,
        fields: any(named: 'fields'),
        referer: _entryUri.toString(),
      ),
    ).thenAnswer((_) async => _response(_successJson, _actionUri));
    await database.into(database.forumDrafts).insert(
      ForumDraftsCompanion.insert(
        draftId: 'new-thread:30',
        accountKey: 'uid:42',
        action: ForumActionKind.newThread.name,
        fid: const Value<int?>(30),
        subject: '旧标题',
        message: '旧正文',
        attachmentsJson: '{}',
        updatedAt: DateTime.utc(2026, 8, 13),
      ),
    );
    final ForumActionRepository repository = ForumActionRepository(
      client,
      42,
      tombstones,
    );
    final ForumPreparedAction prepared = await repository.prepare(_request);

    expect(
      (await repository.submit(prepared, _values('明确成功'))).status,
      ForumSubmissionStatus.success,
    );
    expect(await database.select(database.forumDrafts).get(), isEmpty);
    expect(await database.select(database.forumActionTombstones).get(), isEmpty);
    expect(
      (await ForumActionRepository(client, 42, tombstones).prepare(_request))
          .userId,
      42,
    );
  });
}

void _stubPrepareLease(_MockForumClient client, int userId) {
  when(
    () => client.withActiveAccount<ForumPreparedAction>(userId, any()),
  ).thenAnswer((Invocation invocation) {
    final Future<ForumPreparedAction> Function() operation =
        invocation.positionalArguments[1]
            as Future<ForumPreparedAction> Function();
    return operation();
  });
}

void _stubSubmitLease(_MockForumClient client, int userId) {
  when(
    () => client.withActiveAccount<ForumSubmissionResult>(userId, any()),
  ).thenAnswer((Invocation invocation) {
    final Future<ForumSubmissionResult> Function() operation =
        invocation.positionalArguments[1]
            as Future<ForumSubmissionResult> Function();
    return operation();
  });
}

void _stubReadbackLease(_MockForumClient client, int userId) {
  when(
    () => client.withActiveAccount<ForumReadbackReceipt>(userId, any()),
  ).thenAnswer((Invocation invocation) {
    final Future<ForumReadbackReceipt> Function() operation =
        invocation.positionalArguments[1]
            as Future<ForumReadbackReceipt> Function();
    return operation();
  });
}

void _stubVoidLease(_MockForumClient client, int userId) {
  when(
    () => client.withActiveAccount<void>(userId, any()),
  ).thenAnswer((Invocation invocation) {
    final Future<void> Function() operation =
        invocation.positionalArguments[1] as Future<void> Function();
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

final Uri _entryUri = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=newthread&fid=30&mobile=2',
);
final Uri _actionUri = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=newthread&fid=30&topicsubmit=yes&mobile=2',
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
  description: '回读主题',
);

const String _identityHtml = '''
  <html><body><script>var discuz_uid = '42';</script></body></html>
''';
const String _successJson = '''
  {"Message":{"messageval":"post_newthread_succeed","messagestr":"主题发布成功"},
   "Variables":{"member_uid":"42","tid":"101","pid":"202"}}
''';

Map<String, Object?> _values(String message) {
  return <String, Object?>{'subject': '测试主题', 'message': message};
}

String _newThreadForm({int userId = 42}) {
  return '''
    <html><body class="pg_post">
      <script>var discuz_uid = '$userId';</script>
      <form id="postform" method="post"
        action="forum.php?mod=post&amp;action=newthread&amp;fid=30&amp;topicsubmit=yes&amp;mobile=2">
        <input type="hidden" name="formhash" value="one-use-secret" />
        <input type="hidden" name="fid" value="30" />
        <input type="hidden" name="custom_hidden" value="kept" />
        <label for="subject">主题</label>
        <input id="subject" name="subject" required />
        <label for="message">正文</label>
        <textarea id="message" name="message" required></textarea>
        <select name="typeid">
          <option value="0">请选择</option>
          <option value="7">交流</option>
        </select>
        <input type="file" name="Filedata" multiple />
        <button type="submit" name="topicsubmit" value="yes">发帖</button>
      </form>
    </body></html>
  ''';
}
