import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/favorites/data/forum_favorite_repository.dart';
import 'package:x300/features/favorites/domain/favorite_models.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';
import 'package:x300/features/library/domain/library_models.dart';

class _MockForumClient extends Mock implements ForumClient
{
}

class _FailingFavoriteTombstones
    extends ForumSubmissionTombstoneRepository
{
    _FailingFavoriteTombstones(super.database);

    @override
    Future<String?> claimAttemptedKey({
        required int userId,
        required SubmissionTombstoneKey key,
        required bool deleteDraft,
    })
    {
        throw StateError('磁盘写入失败');
    }
}

void main()
{
    late AppDatabase database;
    late ForumSubmissionTombstoneRepository tombstones;

    setUp(()
    {
        database = AppDatabase(NativeDatabase.memory());
        tombstones = ForumSubmissionTombstoneRepository(database);
    });

    tearDown(() => database.close());

    test('同作品跨帖收藏聚合为一个作品并保留全部云端记录', ()
    {
        final ForumFavoriteRepository repository = ForumFavoriteRepository(
            _MockForumClient(),
            42,
            tombstones,
        );
        final List<CloudFavoriteEntry> entries = <CloudFavoriteEntry>[
            _entry(tid: 501, favoriteId: 9001, title: '测试作品 第1章'),
            _entry(tid: 502, favoriteId: 9002, title: '测试作品 第2章'),
        ];

        final List<FavoriteWork> works = repository.aggregateEntries(entries);

        expect(works, hasLength(1));
        expect(works.single.work.chapters, hasLength(2));
        expect(
            works.single.records
                .map((CloudFavoriteRecord value) => value.favoriteId),
            <int>[9001, 9002],
        );
    });

    test('未登录时在发起网络请求前明确失败', ()
    {
        final _MockForumClient client = _MockForumClient();
        final ForumFavoriteRepository repository = ForumFavoriteRepository(
            client,
            0,
            tombstones,
        );

        expect(
            () => repository.loadInitial(),
            throwsA(isA<ForumSessionExpiredException>()),
        );
        verifyNever(() => client.getText(any()));
    });

    test('列表与元数据解析完整绑定一个 uid 租约', () async
    {
        final _MockForumClient client = _MockForumClient();
        _stubPageLease(client);
        final ForumFavoriteRepository repository = ForumFavoriteRepository(
            client,
            42,
            tombstones,
        );
        when(() => client.getText(_listUri)).thenAnswer(
            (_) async => _response(_listHtml(includeRecord: true), _listUri),
        );
        when(
            () => client.getText(
                _metadataUri(101),
                referer: _threadUri(101).toString(),
            ),
        ).thenAnswer(
            (_) async => _response(_metadataJson(101), _metadataUri(101)),
        );

        final CloudFavoritePage page = await repository.loadInitial();

        expect(page.entries.single.record.favoriteId, 71);
        expect(page.entries.single.sourceThread.tid, 101);
        verify(
            () => client.withActiveAccount<CloudFavoritePage>(42, any()),
        ).called(1);
    });

    test('添加收藏的检查、表单提交与回读只占用一个 uid 租约', () async
    {
        final _MockForumClient client = _MockForumClient();
        _stubRecordLease(client);
        final ForumFavoriteRepository repository = ForumFavoriteRepository(
            client,
            42,
            tombstones,
        );
        var listCalls = 0;
        when(() => client.getText(_listUri)).thenAnswer((_) async
        {
            return _response(
                _listHtml(includeRecord: listCalls++ > 0),
                _listUri,
            );
        });
        when(
            () => client.getText(
                _addDialogUri(101),
                referer: _threadUri(101).toString(),
            ),
        ).thenAnswer(
            (_) async => _response(_addFormHtml(101), _addDialogUri(101)),
        );
        when(
            () => client.postForm(
                _addFormUri(101),
                fields: any(named: 'fields'),
                referer: _addDialogUri(101).toString(),
            ),
        ).thenAnswer(
            (_) async => _response(_identityHtml, _addFormUri(101)),
        );
        final Work work = _work(101);

        final List<CloudFavoriteRecord> records = await repository.addWork(
            work,
        );

        expect(records.single.favoriteId, 71);
        verify(
            () => client.withActiveAccount<List<CloudFavoriteRecord>>(
                42,
                any(),
            ),
        ).called(1);
        verify(() => client.getText(_listUri)).called(2);
        final Map<String, dynamic> fields = verify(
            () => client.postForm(
                _addFormUri(101),
                fields: captureAny(named: 'fields'),
                referer: _addDialogUri(101).toString(),
            ),
        ).captured.single as Map<String, dynamic>;
        expect(fields['formhash'], 'transient-secret');
        expect(
            await database.select(database.forumActionTombstones).get(),
            isEmpty,
        );
    });

    test('列表 uid 不一致时不会继续请求主题元数据', () async
    {
        final _MockForumClient client = _MockForumClient();
        _stubPageLease(client);
        final ForumFavoriteRepository repository = ForumFavoriteRepository(
            client,
            42,
            tombstones,
        );
        when(() => client.getText(_listUri)).thenAnswer(
            (_) async => _response(
                _listHtml(includeRecord: true).replaceFirst(
                    "discuz_uid = '42'",
                    "discuz_uid = '7'",
                ),
                _listUri,
            ),
        );

        await expectLater(
            repository.loadInitial(),
            throwsA(isA<ForumSessionExpiredException>()),
        );
        verifyNever(
            () => client.getText(
                _metadataUri(101),
                referer: any(named: 'referer'),
            ),
        );
    });

    test('取消收藏只信任当前 uid 列表记录且完整占用一个租约', () async
    {
        final _MockForumClient client = _MockForumClient();
        _stubVoidLease(client);
        final ForumFavoriteRepository repository = ForumFavoriteRepository(
            client,
            42,
            tombstones,
        );
        when(() => client.getText(_listUri)).thenAnswer(
            (_) async => _response(_listHtml(includeRecord: false), _listUri),
        );
        final Uri untrustedUri = Uri.parse(
            'https://attacker.invalid/delete?favid=71',
        );

        await repository.removeWork(
            _work(101),
            <CloudFavoriteRecord>[
                CloudFavoriteRecord(
                    favoriteId: 71,
                    threadId: 101,
                    title: '不可信调用参数',
                    threadUri: _threadUri(101),
                    deleteDialogUri: untrustedUri,
                ),
            ],
        );

        verify(
            () => client.withActiveAccount<void>(42, any()),
        ).called(1);
        verify(() => client.getText(_listUri)).called(1);
        verifyNever(
            () => client.getText(
                untrustedUri,
                referer: any(named: 'referer'),
            ),
        );
    });

    test('添加收藏 POST 丢响应后重建仍阻断，列表回读确认后自动解除', () async
    {
        final _MockForumClient client = _MockForumClient();
        _stubRecordLease(client);
        var listCalls = 0;
        when(() => client.getText(_listUri)).thenAnswer((_) async
        {
            listCalls++;
            return _response(
                _listHtml(includeRecord: listCalls >= 3),
                _listUri,
            );
        });
        when(
            () => client.getText(
                _addDialogUri(101),
                referer: _threadUri(101).toString(),
            ),
        ).thenAnswer(
            (_) async => _response(_addFormHtml(101), _addDialogUri(101)),
        );
        when(
            () => client.postForm(
                _addFormUri(101),
                fields: any(named: 'fields'),
                referer: _addDialogUri(101).toString(),
            ),
        ).thenThrow(const ForumConnectionException('响应丢失'));
        final ForumFavoriteRepository first = ForumFavoriteRepository(
            client,
            42,
            tombstones,
        );

        await expectLater(
            first.addWork(_work(101)),
            throwsA(
                isA<ForumSubmissionBlockedException>().having(
                    (ForumSubmissionBlockedException value) => value.message,
                    'message',
                    contains('结果未知'),
                ),
            ),
        );
        expect(
            (await database.select(database.forumActionTombstones).getSingle())
                .status,
            ForumSubmissionTombstoneStatus.attempted.name,
        );

        final ForumFavoriteRepository rebuilt = ForumFavoriteRepository(
            client,
            42,
            tombstones,
        );
        await expectLater(
            rebuilt.addWork(_work(101)),
            throwsA(isA<ForumSubmissionBlockedException>()),
        );
        verify(
            () => client.postForm(
                _addFormUri(101),
                fields: any(named: 'fields'),
                referer: _addDialogUri(101).toString(),
            ),
        ).called(1);
        clearInteractions(client);

        final List<CloudFavoriteRecord> confirmed =
            await rebuilt.addWork(_work(101));
        expect(confirmed.single.threadId, 101);
        expect(
            await database.select(database.forumActionTombstones).get(),
            isEmpty,
        );
        verifyNever(
            () => client.postForm(
                _addFormUri(101),
                fields: any(named: 'fields'),
                referer: _addDialogUri(101).toString(),
            ),
        );
    });

    test('添加收藏封存落盘失败时零 POST', () async
    {
        final _MockForumClient client = _MockForumClient();
        _stubRecordLease(client);
        when(() => client.getText(_listUri)).thenAnswer(
            (_) async => _response(_listHtml(includeRecord: false), _listUri),
        );
        when(
            () => client.getText(
                _addDialogUri(101),
                referer: _threadUri(101).toString(),
            ),
        ).thenAnswer(
            (_) async => _response(_addFormHtml(101), _addDialogUri(101)),
        );
        final ForumFavoriteRepository repository = ForumFavoriteRepository(
            client,
            42,
            _FailingFavoriteTombstones(database),
        );

        await expectLater(
            repository.addWork(_work(101)),
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

    test('结果未确认时回读保留封存，人工解除本身零 POST', () async
    {
        final _MockForumClient client = _MockForumClient();
        _stubRecordLease(client);
        _stubReadbackLease(client);
        _stubVoidLease(client);
        when(() => client.getText(_listUri)).thenAnswer(
            (_) async => _response(_listHtml(includeRecord: false), _listUri),
        );
        when(
            () => client.getText(
                _addDialogUri(101),
                referer: _threadUri(101).toString(),
            ),
        ).thenAnswer(
            (_) async => _response(_addFormHtml(101), _addDialogUri(101)),
        );
        when(
            () => client.postForm(
                _addFormUri(101),
                fields: any(named: 'fields'),
                referer: _addDialogUri(101).toString(),
            ),
        ).thenThrow(const ForumConnectionException('响应丢失'));
        final ForumFavoriteRepository repository = ForumFavoriteRepository(
            client,
            42,
            tombstones,
        );
        ForumUnresolvedSubmission? unresolved;
        try
        {
            await repository.addWork(_work(101));
        }
        on ForumSubmissionBlockedException catch (error)
        {
            unresolved = error.submission;
        }
        expect(unresolved, isNotNull);

        final ForumFavoriteReadbackResult result =
            await repository.readbackUnresolved(unresolved!, _work(101));
        expect(result.trustedOutcomeConfirmed, isFalse);
        expect(result.records, isEmpty);
        expect(
            await database.select(database.forumActionTombstones).get(),
            hasLength(1),
        );

        clearInteractions(client);
        await repository.acknowledgeUnresolved(unresolved);
        expect(
            await database.select(database.forumActionTombstones).get(),
            isEmpty,
        );
        verifyNever(
            () => client.postForm(
                any(),
                fields: any(named: 'fields'),
                referer: any(named: 'referer'),
            ),
        );
        verifyNever(() => client.getText(any()));
    });

    test('完整列表回读确认收藏已存在时自动解除封存且不再 POST', () async
    {
        final _MockForumClient client = _MockForumClient();
        _stubRecordLease(client);
        _stubReadbackLease(client);
        var listCalls = 0;
        when(() => client.getText(_listUri)).thenAnswer((_) async
        {
            return _response(
                _listHtml(includeRecord: listCalls++ > 0),
                _listUri,
            );
        });
        when(
            () => client.getText(
                _addDialogUri(101),
                referer: _threadUri(101).toString(),
            ),
        ).thenAnswer(
            (_) async => _response(_addFormHtml(101), _addDialogUri(101)),
        );
        when(
            () => client.postForm(
                _addFormUri(101),
                fields: any(named: 'fields'),
                referer: _addDialogUri(101).toString(),
            ),
        ).thenThrow(const ForumConnectionException('响应丢失'));
        final ForumFavoriteRepository repository = ForumFavoriteRepository(
            client,
            42,
            tombstones,
        );
        ForumUnresolvedSubmission? unresolved;
        try
        {
            await repository.addWork(_work(101));
        }
        on ForumSubmissionBlockedException catch (error)
        {
            unresolved = error.submission;
        }

        clearInteractions(client);
        final ForumFavoriteReadbackResult result =
            await repository.readbackUnresolved(unresolved!, _work(101));
        expect(result.trustedOutcomeConfirmed, isTrue);
        expect(result.records.single.threadId, 101);
        expect(
            await database.select(database.forumActionTombstones).get(),
            isEmpty,
        );
        verifyNever(
            () => client.postForm(
                any(),
                fields: any(named: 'fields'),
                referer: any(named: 'referer'),
            ),
        );
    });

    test('回读分页声称有后页但缺少下一页时保留封存', () async
    {
        final _MockForumClient client = _MockForumClient();
        _stubRecordLease(client);
        _stubReadbackLease(client);
        var listCalls = 0;
        when(() => client.getText(_listUri)).thenAnswer((_) async
        {
            return _response(
                listCalls++ == 0
                    ? _listHtml(includeRecord: false)
                    : _truncatedListHtml(),
                _listUri,
            );
        });
        when(
            () => client.getText(
                _addDialogUri(101),
                referer: _threadUri(101).toString(),
            ),
        ).thenAnswer(
            (_) async => _response(_addFormHtml(101), _addDialogUri(101)),
        );
        when(
            () => client.postForm(
                _addFormUri(101),
                fields: any(named: 'fields'),
                referer: _addDialogUri(101).toString(),
            ),
        ).thenThrow(const ForumConnectionException('响应丢失'));
        final ForumFavoriteRepository repository = ForumFavoriteRepository(
            client,
            42,
            tombstones,
        );
        ForumUnresolvedSubmission? unresolved;
        try
        {
            await repository.addWork(_work(101));
        }
        on ForumSubmissionBlockedException catch (error)
        {
            unresolved = error.submission;
        }

        await expectLater(
            repository.readbackUnresolved(unresolved!, _work(101)),
            throwsA(
                isA<ForumParseException>().having(
                    (ForumParseException value) => value.message,
                    'message',
                    contains('分页不完整'),
                ),
            ),
        );
        expect(
            await database.select(database.forumActionTombstones).get(),
            hasLength(1),
        );
    });

    test('两个 legacy 收藏仓库并发确认由数据库原子 claim 限制为一次 POST', () async
    {
        final _MockForumClient client = _MockForumClient();
        _stubRecordLease(client);
        when(() => client.getText(_listUri)).thenAnswer(
            (_) async => _response(_listHtml(includeRecord: false), _listUri),
        );
        final Completer<void> bothDialogsStarted = Completer<void>();
        final Completer<void> releaseDialogs = Completer<void>();
        var dialogCalls = 0;
        when(
            () => client.getText(
                _addDialogUri(101),
                referer: _threadUri(101).toString(),
            ),
        ).thenAnswer((_) async
        {
            dialogCalls++;
            if (dialogCalls == 2)
            {
                bothDialogsStarted.complete();
            }
            await releaseDialogs.future;
            return _response(_addFormHtml(101), _addDialogUri(101));
        });
        final Completer<void> postStarted = Completer<void>();
        final Completer<Response<String>> postResponse =
            Completer<Response<String>>();
        when(
            () => client.postForm(
                _addFormUri(101),
                fields: any(named: 'fields'),
                referer: _addDialogUri(101).toString(),
            ),
        ).thenAnswer((_) {
            postStarted.complete();
            return postResponse.future;
        });
        final ForumFavoriteRepository first = ForumFavoriteRepository(
            client,
            42,
            tombstones,
        );
        final ForumFavoriteRepository second = ForumFavoriteRepository(
            client,
            42,
            tombstones,
        );
        Future<Object> capture(Future<List<CloudFavoriteRecord>> operation)
            async
        {
            try
            {
                return await operation;
            }
            on Object catch (error)
            {
                return error;
            }
        }

        final Future<Object> firstResult = capture(first.addWork(_work(101)));
        final Future<Object> secondResult = capture(second.addWork(_work(101)));
        await bothDialogsStarted.future;
        releaseDialogs.complete();
        await postStarted.future;
        postResponse.complete(_response(_identityHtml, _addFormUri(101)));
        final List<Object> results = await Future.wait<Object>(
            <Future<Object>>[firstResult, secondResult],
        );

        expect(
            results.whereType<ForumSubmissionBlockedException>(),
            hasLength(2),
        );
        verify(
            () => client.postForm(
                _addFormUri(101),
                fields: any(named: 'fields'),
                referer: _addDialogUri(101).toString(),
            ),
        ).called(1);
        expect(
            await database.select(database.forumActionTombstones).get(),
            hasLength(1),
        );
    });

    test('多记录取消逐项封存，第二项未知后重建不重复第一项或第二项', () async
    {
        final _MockForumClient client = _MockForumClient();
        _stubVoidLease(client);
        _stubRecordLease(client);
        var listCalls = 0;
        when(() => client.getText(_listUri)).thenAnswer((_) async
        {
            listCalls++;
            final List<(int, int)> records = switch (listCalls)
            {
                1 => <(int, int)>[(101, 71), (102, 72)],
                2 || 3 => <(int, int)>[(102, 72)],
                _ => const <(int, int)>[],
            };
            return _response(_listHtmlRecords(records), _listUri);
        });
        for (final int favoriteId in <int>[71, 72])
        {
            when(
                () => client.getText(
                    _deleteDialogUri(favoriteId),
                    referer: _listUri.toString(),
                ),
            ).thenAnswer(
                (_) async => _response(
                    _deleteFormHtml(favoriteId),
                    _deleteDialogUri(favoriteId),
                ),
            );
        }
        when(
            () => client.postForm(
                _deleteDialogUri(71),
                fields: any(named: 'fields'),
                referer: _deleteDialogUri(71).toString(),
            ),
        ).thenAnswer(
            (_) async => _response(_identityHtml, _deleteDialogUri(71)),
        );
        when(
            () => client.postForm(
                _deleteDialogUri(72),
                fields: any(named: 'fields'),
                referer: _deleteDialogUri(72).toString(),
            ),
        ).thenThrow(const ForumConnectionException('第二项响应丢失'));
        final Work work = _workWithThreads(<int>[101, 102]);
        final ForumFavoriteRepository first = ForumFavoriteRepository(
            client,
            42,
            tombstones,
        );

        await expectLater(
            first.removeWork(work, const <CloudFavoriteRecord>[]),
            throwsA(isA<ForumSubmissionBlockedException>()),
        );
        final List<ForumActionTombstone> sealed =
            await database.select(database.forumActionTombstones).get();
        expect(sealed, hasLength(1));
        expect(sealed.single.favoriteId, 72);

        final ForumFavoriteRepository rebuilt = ForumFavoriteRepository(
            client,
            42,
            tombstones,
        );
        await expectLater(
            rebuilt.removeWork(work, const <CloudFavoriteRecord>[]),
            throwsA(isA<ForumSubmissionBlockedException>()),
        );
        verify(
            () => client.postForm(
                _deleteDialogUri(71),
                fields: any(named: 'fields'),
                referer: _deleteDialogUri(71).toString(),
            ),
        ).called(1);
        verify(
            () => client.postForm(
                _deleteDialogUri(72),
                fields: any(named: 'fields'),
                referer: _deleteDialogUri(72).toString(),
            ),
        ).called(1);

        expect(await rebuilt.findForWork(work), isEmpty);
        expect(
            await database.select(database.forumActionTombstones).get(),
            isEmpty,
        );
    });
}

final Uri _listUri = Uri.parse(
    'https://bbs.yamibo.com/home.php?mod=space&do=favorite&view=me&type=thread&mobile=2',
);

void _stubPageLease(_MockForumClient client)
{
    when(
        () => client.withActiveAccount<CloudFavoritePage>(42, any()),
    ).thenAnswer((Invocation invocation)
    {
        final Future<CloudFavoritePage> Function() operation =
            invocation.positionalArguments[1]
                as Future<CloudFavoritePage> Function();
        return operation();
    });
}

void _stubRecordLease(_MockForumClient client)
{
    when(
        () => client.withActiveAccount<List<CloudFavoriteRecord>>(42, any()),
    ).thenAnswer((Invocation invocation)
    {
        final Future<List<CloudFavoriteRecord>> Function() operation =
            invocation.positionalArguments[1]
                as Future<List<CloudFavoriteRecord>> Function();
        return operation();
    });
}

void _stubVoidLease(_MockForumClient client)
{
    when(
        () => client.withActiveAccount<void>(42, any()),
    ).thenAnswer((Invocation invocation)
    {
        final Future<void> Function() operation =
            invocation.positionalArguments[1] as Future<void> Function();
        return operation();
    });
}

void _stubReadbackLease(_MockForumClient client)
{
    when(
        () => client.withActiveAccount<ForumFavoriteReadbackResult>(42, any()),
    ).thenAnswer((Invocation invocation)
    {
        final Future<ForumFavoriteReadbackResult> Function() operation =
            invocation.positionalArguments[1]
                as Future<ForumFavoriteReadbackResult> Function();
        return operation();
    });
}

Response<String> _response(String body, Uri uri)
{
    return Response<String>(
        requestOptions: RequestOptions(path: uri.toString()),
        data: body,
        statusCode: 200,
    );
}

String _listHtml({required bool includeRecord})
{
    return _listHtmlRecords(
        includeRecord ? const <(int, int)>[(101, 71)] : const <(int, int)>[],
    );
}

String _listHtmlRecords(List<(int, int)> records)
{
    return '''
        <html><head><script>var discuz_uid = '42';</script></head>
        <body id="home" class="pg_space"><div class="findbox"><ul>
            ${records.map(((int, int) value) => '''
            <li class="sclist">
                <a href="home.php?mod=spacecp&amp;ac=favorite&amp;op=delete&amp;favid=${value.$2}&amp;mobile=2">删除</a>
                <a href="forum.php?mod=viewthread&amp;tid=${value.$1}&amp;mobile=2">测试作品</a>
            </li>
            ''').join()}
        </ul></div></body></html>
    ''';
}

String _truncatedListHtml()
{
    return '''
        <html><head><script>var discuz_uid = '42';</script></head>
        <body id="home" class="pg_space">
            <div class="findbox"><ul></ul></div>
            <div class="pg">
                <strong>1</strong>
                <label><input name="custompage" value="1" />
                    <span title="共 2 页">1 / 2</span></label>
            </div>
        </body></html>
    ''';
}

String _metadataJson(int threadId)
{
    return '''
        {"Variables":{"member_uid":"42","thread":{
            "tid":"$threadId","fid":"49","subject":"测试作品"
        }}}
    ''';
}

const String _identityHtml = '''
    <html><head><script>var discuz_uid = '42';</script></head>
    <body id="home" class="pg_space"></body></html>
''';

String _addFormHtml(int threadId)
{
    return '''
        <html><head><script>var discuz_uid = '42';</script></head><body>
        <form method="post" action="${_addFormUri(threadId)}">
            <input type="hidden" name="favoritesubmit" value="true" />
            <input type="hidden" name="formhash" value="transient-secret" />
        </form></body></html>
    ''';
}

String _deleteFormHtml(int favoriteId)
{
    return '''
        <html><head><script>var discuz_uid = '42';</script></head><body>
        <form method="post" action="${_deleteDialogUri(favoriteId)}">
            <input type="hidden" name="deletesubmit" value="true" />
            <input type="hidden" name="formhash" value="transient-delete" />
        </form></body></html>
    ''';
}

Uri _threadUri(int threadId)
{
    return Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$threadId&mobile=2',
    );
}

Uri _metadataUri(int threadId)
{
    return Uri.parse(
        'https://bbs.yamibo.com/api/mobile/index.php?version=4&module=viewthread&tid=$threadId',
    );
}

Uri _addDialogUri(int threadId)
{
    return Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&type=thread&id=$threadId&mobile=2',
    );
}

Uri _addFormUri(int threadId)
{
    return Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&type=thread&id=$threadId&spaceuid=42&mobile=2',
    );
}

Uri _deleteDialogUri(int favoriteId)
{
    return Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&op=delete&favid=$favoriteId&mobile=2',
    );
}

Work _work(int threadId)
{
    final SourceThread thread = SourceThread(
        tid: threadId,
        board: ForumBoard.literature,
        title: '测试作品',
        uri: _threadUri(threadId),
    );
    return Work(
        id: 'novel:$threadId',
        kind: LibraryKind.novel,
        title: thread.title,
        sourceThreads: <SourceThread>[thread],
        chapters: <Chapter>[
            Chapter(
                id: 'novel:$threadId:1',
                title: '正文',
                sourceUri: thread.uri,
                sourceTid: threadId,
            ),
        ],
    );
}

Work _workWithThreads(List<int> threadIds)
{
    final List<SourceThread> threads = threadIds.map((int threadId) =>
        SourceThread(
            tid: threadId,
            board: ForumBoard.literature,
            title: '测试作品',
            uri: _threadUri(threadId),
        ),
    ).toList(growable: false);
    return Work(
        id: 'novel:multi',
        kind: LibraryKind.novel,
        title: '测试作品',
        sourceThreads: threads,
        chapters: threadIds.map((int threadId) => Chapter(
            id: 'novel:$threadId:1',
            title: '正文',
            sourceUri: _threadUri(threadId),
            sourceTid: threadId,
        )).toList(growable: false),
    );
}

CloudFavoriteEntry _entry({
    required int tid,
    required int favoriteId,
    required String title,
})
{
    final Uri threadUri = Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=$tid&mobile=2',
    );
    return CloudFavoriteEntry(
        record: CloudFavoriteRecord(
            favoriteId: favoriteId,
            threadId: tid,
            title: title,
            threadUri: threadUri,
            deleteDialogUri: Uri.parse(
                'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&favid=$favoriteId',
            ),
        ),
        sourceThread: SourceThread(
            tid: tid,
            board: ForumBoard.literature,
            typeId: 49,
            title: title,
            uri: threadUri,
        ),
    );
}
