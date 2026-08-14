import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/core/storage/app_database.dart';
import 'package:x300/features/favorites/data/forum_board_favorite_repository.dart';
import 'package:x300/features/favorites/domain/raw_favorite_models.dart';
import 'package:x300/features/forum/data/forum_submission_tombstone_repository.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';

class _MockForumClient extends Mock implements ForumClient {}

void main() {
  late AppDatabase database;
  late ForumSubmissionTombstoneRepository tombstones;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    tombstones = ForumSubmissionTombstoneRepository(database);
  });

  tearDown(() => database.close());

  test('添加先封存再发 GET，失败后重建只回读且不重复业务 GET', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    var listCalls = 0;
    when(() => client.getText(ForumBoardFavoriteRepository.listUri)).thenAnswer(
      (_) async => _response(
        _listHtml(items: const <RawFavoriteItem>[], page: 1, totalPages: 1),
        ForumBoardFavoriteRepository.listUri,
      ),
    );
    when(
      () => client.getText(_addUri, referer: _boardUri.toString()),
    ).thenAnswer((_) async {
      expect(
        await database.select(database.forumActionTombstones).get(),
        hasLength(1),
      );
      listCalls++;
      throw const ForumConnectionException('响应丢失');
    });
    final ForumBoardFavoriteRepository repository =
        ForumBoardFavoriteRepository(client, 42, tombstones);

    final ForumBoardFavoriteBlockedException blocked = await _captureBlocked(
      repository.add(boardId: 30, entryUri: _addUri, refererUri: _boardUri),
    );
    expect(blocked.record.key.boardId, 30);
    expect(blocked.record.key.favoriteId, isNull);

    final ForumBoardFavoriteRepository rebuilt =
        ForumBoardFavoriteRepository(client, 42, tombstones);
    await expectLater(
      rebuilt.add(boardId: 30, entryUri: _addUri, refererUri: _boardUri),
      throwsA(isA<ForumBoardFavoriteBlockedException>()),
    );
    verify(
      () => client.getText(_addUri, referer: _boardUri.toString()),
    ).called(1);
    expect(listCalls, 1);
  });

  test('并发实例对 GET 即突变的添加只允许一个请求', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(() => client.getText(ForumBoardFavoriteRepository.listUri)).thenAnswer(
      (_) async => _response(
        _listHtml(items: const <RawFavoriteItem>[], page: 1, totalPages: 1),
        ForumBoardFavoriteRepository.listUri,
      ),
    );
    final Completer<Response<String>> response = Completer<Response<String>>();
    final Completer<void> started = Completer<void>();
    when(
      () => client.getText(_addUri, referer: _boardUri.toString()),
    ).thenAnswer((_) {
      if (!started.isCompleted) {
        started.complete();
      }
      return response.future;
    });
    final ForumBoardFavoriteRepository first =
        ForumBoardFavoriteRepository(client, 42, tombstones);
    final ForumBoardFavoriteRepository second =
        ForumBoardFavoriteRepository(client, 42, tombstones);

    final Future<ForumBoardFavoriteBlockedException> firstResult =
        _captureBlocked(
          first.add(boardId: 30, entryUri: _addUri, refererUri: _boardUri),
        );
    await started.future;
    final Future<ForumBoardFavoriteBlockedException> secondResult =
        _captureBlocked(
          second.add(boardId: 30, entryUri: _addUri, refererUri: _boardUri),
        );
    response.completeError(const ForumConnectionException('响应丢失'));

    await Future.wait(<Future<Object>>[firstResult, secondResult]);
    verify(
      () => client.getText(_addUri, referer: _boardUri.toString()),
    ).called(1);
    expect(
      await database.select(database.forumActionTombstones).get(),
      hasLength(1),
    );
  });

  test('取消确认页可以并发读取，但跨实例只允许一个 POST', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(() => client.getText(ForumBoardFavoriteRepository.listUri)).thenAnswer(
      (_) async => _response(
        _listHtml(items: <RawFavoriteItem>[_boardItem], page: 1, totalPages: 1),
        ForumBoardFavoriteRepository.listUri,
      ),
    );
    when(
      () => client.getText(_deleteEntry, referer: ForumBoardFavoriteRepository.listUri.toString()),
    ).thenAnswer((_) async => _response(_deleteFormHtml, _deleteEntry));
    final Completer<Response<String>> response = Completer<Response<String>>();
    final Completer<void> started = Completer<void>();
    when(
      () => client.postForm(
        _deleteAction,
        fields: any(named: 'fields'),
        referer: _deleteEntry.toString(),
      ),
    ).thenAnswer((_) {
      if (!started.isCompleted) {
        started.complete();
      }
      return response.future;
    });
    final ForumBoardFavoriteRepository first =
        ForumBoardFavoriteRepository(client, 42, tombstones);
    final ForumBoardFavoriteRepository second =
        ForumBoardFavoriteRepository(client, 42, tombstones);

    final Future<ForumBoardFavoriteBlockedException> firstResult =
        _captureBlocked(first.remove(_boardItem));
    await started.future;
    final Future<ForumBoardFavoriteBlockedException> secondResult =
        _captureBlocked(second.remove(_boardItem));
    response.completeError(const ForumConnectionException('响应丢失'));
    await Future.wait(<Future<Object>>[firstResult, secondResult]);

    verify(
      () => client.postForm(
        _deleteAction,
        fields: any(named: 'fields'),
        referer: _deleteEntry.toString(),
      ),
    ).called(1);
    expect(
      await database.select(database.forumActionTombstones).get(),
      hasLength(1),
    );
  });

  test('添加严格绑定 handlekey、board、身份，unknown 封存可回读解除', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    var listCalls = 0;
    when(() => client.getText(ForumBoardFavoriteRepository.listUri)).thenAnswer(
      (_) async {
        listCalls++;
        return _response(
          _listHtml(
            items: listCalls < 3 ? const <RawFavoriteItem>[] : <RawFavoriteItem>[_boardItem],
            page: 1,
            totalPages: 1,
          ),
          ForumBoardFavoriteRepository.listUri,
        );
      },
    );
    when(
      () => client.getText(_addUri, referer: _boardUri.toString()),
    ).thenAnswer(
      (_) async => _response(_identityHtml, _addUri),
    );
    final ForumBoardFavoriteRepository repository =
        ForumBoardFavoriteRepository(client, 42, tombstones);

    final ForumBoardFavoriteBlockedException blocked = await _captureBlocked(
      repository.add(boardId: 30, entryUri: _addUri, refererUri: _boardUri),
    );
    expect(await repository.readback(blocked), isTrue);
    expect(await database.select(database.forumActionTombstones).get(), isEmpty);

    await expectLater(
      repository.add(
        boardId: 30,
        entryUri: _addUri.replace(
          queryParameters: <String, String>{
            ..._addUri.queryParameters,
            'id': '31',
          },
        ),
        refererUri: _boardUri,
      ),
      throwsA(isA<ForumActionSecurityException>()),
    );
  });

  test('添加请求发出后的 handlekey 或目标漂移保留 unknown 封存', () async {
    for (final Uri finalUri in <Uri>[
      _addUri.replace(
        queryParameters: <String, String>{
          ..._addUri.queryParameters,
          'handlekey': 'changed-control',
        },
      ),
      _addUri.replace(
        queryParameters: <String, String>{
          ..._addUri.queryParameters,
          'id': '31',
        },
      ),
    ]) {
      final _MockForumClient client = _MockForumClient();
      _stubLeases(client);
      when(() => client.getText(ForumBoardFavoriteRepository.listUri)).thenAnswer(
        (_) async => _response(
          _listHtml(items: const <RawFavoriteItem>[], page: 1, totalPages: 1),
          ForumBoardFavoriteRepository.listUri,
        ),
      );
      when(
        () => client.getText(_addUri, referer: _boardUri.toString()),
      ).thenAnswer((_) async => _response(_identityHtml, finalUri));
      final ForumBoardFavoriteRepository repository =
          ForumBoardFavoriteRepository(
            client,
            42,
            tombstones,
          );

      await expectLater(
        repository.add(boardId: 30, entryUri: _addUri, refererUri: _boardUri),
        throwsA(isA<ForumBoardFavoriteBlockedException>()),
      );
      final List<ForumActionTombstone> records =
          await database.select(database.forumActionTombstones).get();
      expect(records, hasLength(1));
      final SubmissionTombstoneRecord record = (await tombstones.findKey(
        userId: 42,
        key: const SubmissionTombstoneKey(
          action: 'favoriteBoard',
          boardId: 30,
          draftContext: '',
        ),
      ))!;
      expect(await tombstones.acknowledgeKey(record), isTrue);
    }
  });

  test('添加最终页 uid 漂移抛 sessionExpired 且保留封存', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(() => client.getText(ForumBoardFavoriteRepository.listUri)).thenAnswer(
      (_) async => _response(
        _listHtml(items: const <RawFavoriteItem>[], page: 1, totalPages: 1),
        ForumBoardFavoriteRepository.listUri,
      ),
    );
    when(
      () => client.getText(_addUri, referer: _boardUri.toString()),
    ).thenAnswer(
      (_) async => _response(
        _identityHtml.replaceFirst("discuz_uid = '42'", "discuz_uid = '99'"),
        _addUri,
      ),
    );
    final ForumBoardFavoriteRepository repository =
        ForumBoardFavoriteRepository(client, 42, tombstones);

    await expectLater(
      repository.add(boardId: 30, entryUri: _addUri, refererUri: _boardUri),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    expect(
      await database.select(database.forumActionTombstones).get(),
      hasLength(1),
    );
  });

  test('完整读取带 uid 的多页列表后才确认添加结果', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    final Uri secondUri = ForumBoardFavoriteRepository.listUri.replace(
      queryParameters: <String, String>{
        ...ForumBoardFavoriteRepository.listUri.queryParameters,
        'uid': '42',
        'page': '2',
      },
    );
    var secondCalls = 0;
    when(() => client.getText(ForumBoardFavoriteRepository.listUri)).thenAnswer(
      (_) async => _response(
        _listHtml(
          items: const <RawFavoriteItem>[],
          page: 1,
          totalPages: 2,
          nextUri: secondUri,
        ),
        ForumBoardFavoriteRepository.listUri,
      ),
    );
    when(() => client.getText(secondUri)).thenAnswer(
      (_) async {
        secondCalls++;
        return _response(
          _listHtml(
            items: secondCalls == 1
                ? const <RawFavoriteItem>[]
                : <RawFavoriteItem>[_boardItem],
            page: 2,
            totalPages: 2,
          ),
          secondUri,
        );
      },
    );
    when(
      () => client.getText(_addUri, referer: _boardUri.toString()),
    ).thenAnswer((_) async => _response(_identityHtml, _addUri));
    final ForumBoardFavoriteRepository repository =
        ForumBoardFavoriteRepository(client, 42, tombstones);

    expect(
      await repository.add(
        boardId: 30,
        entryUri: _addUri,
        refererUri: _boardUri,
      ),
      isTrue,
    );
    verify(() => client.getText(secondUri)).called(2);
    expect(await database.select(database.forumActionTombstones).get(), isEmpty);
  });

  test('取消先确认唯一表单，再封存后 POST；值原样提交不猜 marker', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    var listCalls = 0;
    when(() => client.getText(ForumBoardFavoriteRepository.listUri)).thenAnswer(
      (_) async {
        listCalls++;
        return _response(
          _listHtml(
            items: listCalls == 1 ? <RawFavoriteItem>[_boardItem] : const <RawFavoriteItem>[],
            page: 1,
            totalPages: 1,
          ),
          ForumBoardFavoriteRepository.listUri,
        );
      },
    );
    final String formWithOpaqueWhitespace = _deleteFormHtml
        .replaceFirst(
          'value="opaque-hidden-marker"',
          'value="  opaque-hidden-marker  "',
        )
        .replaceFirst(
          'value="opaque-form-token"',
          'value=" opaque-form-token "',
        )
        .replaceFirst(
          'value="opaque-button-marker"',
          'value=" opaque-button-marker  "',
        );
    when(
      () => client.getText(_deleteEntry, referer: ForumBoardFavoriteRepository.listUri.toString()),
    ).thenAnswer(
      (_) async => _response(formWithOpaqueWhitespace, _deleteEntry),
    );
    when(
      () => client.postForm(
        _deleteAction,
        fields: any(named: 'fields'),
        referer: _deleteEntry.toString(),
      ),
    ).thenAnswer((Invocation invocation) async {
      expect(
        await database.select(database.forumActionTombstones).get(),
        hasLength(1),
      );
      final Map<String, Object> fields = invocation.namedArguments[#fields]
          as Map<String, Object>;
      expect(fields, <String, Object>{
        'referer': 'home.php?mod=space&do=favorite&type=forum&uid=42&mobile=2',
        'deletesubmit': '  opaque-hidden-marker  ',
        'formhash': ' opaque-form-token ',
        'deletesubmitbtn': ' opaque-button-marker  ',
      });
      return _response(_identityHtml, _deleteAction);
    });
    final ForumBoardFavoriteRepository repository =
        ForumBoardFavoriteRepository(client, 42, tombstones);

    expect(await repository.remove(_boardItem), isTrue);
    expect(await database.select(database.forumActionTombstones).get(), isEmpty);
  });

  test('确认页漂移或 claim 失败不会发送取消 POST', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    when(() => client.getText(ForumBoardFavoriteRepository.listUri)).thenAnswer(
      (_) async => _response(
        _listHtml(items: <RawFavoriteItem>[_boardItem], page: 1, totalPages: 1),
        ForumBoardFavoriteRepository.listUri,
      ),
    );
    when(
      () => client.getText(_deleteEntry, referer: ForumBoardFavoriteRepository.listUri.toString()),
    ).thenAnswer(
      (_) async => _response(
        _deleteFormHtml.replaceFirst(
          'favoriteform_71',
          'favoriteform_72',
        ),
        _deleteEntry,
      ),
    );
    final ForumBoardFavoriteRepository repository =
        ForumBoardFavoriteRepository(client, 42, tombstones);

    await expectLater(
      repository.remove(_boardItem),
      throwsA(isA<ForumParseException>()),
    );
    verifyNever(
      () => client.postForm(
        any(),
        fields: any(named: 'fields'),
        referer: any(named: 'referer'),
      ),
    );
    expect(await database.select(database.forumActionTombstones).get(), isEmpty);
  });

  test('取消确认表单的 action、字段、形状或 referer 漂移时零 POST', () async {
    final List<String> invalidForms = <String>[
      _deleteFormHtml.replaceFirst('type=forum', 'type=thread'),
      _deleteFormHtml.replaceFirst(
        '<input type="hidden" name="formhash" value="opaque-form-token">',
        '<input type="hidden" name="formhash" value="opaque-form-token"><input type="hidden" name="unexpected" value="x">',
      ),
      _deleteFormHtml.replaceFirst(
        '<input type="submit" name="deletesubmitbtn" value="opaque-button-marker">',
        '<button name="deletesubmitbtn" value="opaque-button-marker">取消</button>',
      ),
      _deleteFormHtml.replaceFirst(
        'home.php?mod=space&amp;do=favorite&amp;type=forum&amp;uid=42&amp;mobile=2',
        'https://evil.example/favorites',
      ),
      _deleteFormHtml.replaceFirst(
        'home.php?mod=space&amp;do=favorite&amp;type=forum&amp;uid=42&amp;mobile=2',
        'home.php?mod=spacecp&amp;ac=favorite&amp;type=forum&amp;id=30&amp;handlekey=opaque&amp;mobile=2',
      ),
      _deleteFormHtml.replaceFirst('uid=42', 'uid=99'),
      _deleteFormHtml.replaceFirst(
        'name="deletesubmit" value="opaque-hidden-marker"',
        'name="deletesubmit" value=""',
      ),
    ];
    for (final String source in invalidForms) {
      final _MockForumClient client = _MockForumClient();
      _stubLeases(client);
      when(() => client.getText(ForumBoardFavoriteRepository.listUri)).thenAnswer(
        (_) async => _response(
          _listHtml(items: <RawFavoriteItem>[_boardItem], page: 1, totalPages: 1),
          ForumBoardFavoriteRepository.listUri,
        ),
      );
      when(
        () => client.getText(_deleteEntry, referer: ForumBoardFavoriteRepository.listUri.toString()),
      ).thenAnswer((_) async => _response(source, _deleteEntry));
      final ForumBoardFavoriteRepository repository =
          ForumBoardFavoriteRepository(client, 42, tombstones);

      await expectLater(
        repository.remove(_boardItem),
        throwsA(isA<ForumException>()),
      );
      verifyNever(
        () => client.postForm(
          any(),
          fields: any(named: 'fields'),
          referer: any(named: 'referer'),
        ),
      );
    }
  });

  test('伪造或重复的 raw delete URI 在任何网络前失败', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    final ForumBoardFavoriteRepository repository =
        ForumBoardFavoriteRepository(client, 42, tombstones);
    final RawFavoriteItem invalid = RawFavoriteItem(
      favoriteId: 71,
      categoryKey: 'forum',
      title: '伪造版块',
      targetKind: RawFavoriteTargetKind.board,
      targetUri: _boardUri,
      deleteDialogUri: Uri.parse(
        'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&op=delete&favid=71&favid=72&mobile=2',
      ),
      boardId: 30,
    );

    await expectLater(
      repository.remove(invalid),
      throwsA(isA<ForumActionSecurityException>()),
    );
    verifyNever(() => client.getText(any(), referer: any(named: 'referer')));
  });

  test('写请求后的 sessionExpired 原样抛出但保留封存', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    var listCalls = 0;
    when(() => client.getText(ForumBoardFavoriteRepository.listUri)).thenAnswer(
      (_) async {
        listCalls++;
        return _response(
          _listHtml(
            items: listCalls == 1 ? <RawFavoriteItem>[_boardItem] : const <RawFavoriteItem>[],
            page: 1,
            totalPages: 1,
          ),
          ForumBoardFavoriteRepository.listUri,
        );
      },
    );
    when(
      () => client.getText(_deleteEntry, referer: ForumBoardFavoriteRepository.listUri.toString()),
    ).thenAnswer((_) async => _response(_deleteFormHtml, _deleteEntry));
    when(
      () => client.postForm(
        _deleteAction,
        fields: any(named: 'fields'),
        referer: _deleteEntry.toString(),
      ),
    ).thenAnswer((_) async => _response('<html><body>login</body></html>', _deleteAction));
    final ForumBoardFavoriteRepository repository =
        ForumBoardFavoriteRepository(client, 42, tombstones);

    await expectLater(
      repository.remove(_boardItem),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    expect(
      await database.select(database.forumActionTombstones).get(),
      hasLength(1),
    );
  });

  test('取消响应丢失后回读确认或人工解除都不会再次 POST', () async {
    final _MockForumClient client = _MockForumClient();
    _stubLeases(client);
    var listCalls = 0;
    when(() => client.getText(ForumBoardFavoriteRepository.listUri)).thenAnswer(
      (_) async {
        listCalls++;
        return _response(
          _listHtml(
            items: listCalls == 1 ? <RawFavoriteItem>[_boardItem] : const <RawFavoriteItem>[],
            page: 1,
            totalPages: 1,
          ),
          ForumBoardFavoriteRepository.listUri,
        );
      },
    );
    when(
      () => client.getText(_deleteEntry, referer: ForumBoardFavoriteRepository.listUri.toString()),
    ).thenAnswer((_) async => _response(_deleteFormHtml, _deleteEntry));
    var postCalls = 0;
    when(
      () => client.postForm(
        _deleteAction,
        fields: any(named: 'fields'),
        referer: _deleteEntry.toString(),
      ),
    ).thenAnswer((_) {
      postCalls++;
      throw const ForumConnectionException('响应丢失');
    });
    final ForumBoardFavoriteRepository repository =
        ForumBoardFavoriteRepository(client, 42, tombstones);

    final ForumBoardFavoriteBlockedException blocked = await _captureBlocked(
      repository.remove(_boardItem),
    );
    expect(await repository.readback(blocked), isTrue);
    expect(postCalls, 1);

    final ForumBoardFavoriteBlockedException manual = await _seedBlockedRemove(
      tombstones,
    );
    await repository.acknowledge(manual);
    expect(postCalls, 1);
    expect(await database.select(database.forumActionTombstones).get(), isEmpty);
  });

  test('账号 lease 在任何网络前拒绝失效账号', () async {
    final _MockForumClient client = _MockForumClient();
    when(
      () => client.withActiveAccount<bool>(42, any()),
    ).thenThrow(const ForumSessionExpiredException());
    final ForumBoardFavoriteRepository repository =
        ForumBoardFavoriteRepository(client, 42, tombstones);

    expect(
      () => repository.add(
        boardId: 30,
        entryUri: _addUri,
        refererUri: _boardUri,
      ),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    verifyNever(() => client.getText(any(), referer: any(named: 'referer')));
  });
}

void _stubLeases(_MockForumClient client) {
  when(() => client.withActiveAccount<bool>(42, any())).thenAnswer((invocation) {
    final Future<bool> Function() operation = invocation.positionalArguments[1]
        as Future<bool> Function();
    return operation();
  });
  when(() => client.withActiveAccount<void>(42, any())).thenAnswer((invocation) {
    final Future<void> Function() operation = invocation.positionalArguments[1]
        as Future<void> Function();
    return operation();
  });
}

Future<ForumBoardFavoriteBlockedException> _captureBlocked(
  Future<bool> operation,
) async {
  try {
    await operation;
  } on ForumBoardFavoriteBlockedException catch (error) {
    return error;
  }
  throw StateError('expected blocked exception');
}

Future<ForumBoardFavoriteBlockedException> _seedBlockedRemove(
  ForumSubmissionTombstoneRepository tombstones,
) async {
  const SubmissionTombstoneKey key = SubmissionTombstoneKey(
    action: 'removeFavorite',
    boardId: 30,
    favoriteId: 71,
    draftContext: '',
  );
  await tombstones.claimAttemptedKey(
    userId: 42,
    key: key,
    deleteDraft: false,
  );
  final SubmissionTombstoneRecord record = (await tombstones.findKey(
    userId: 42,
    key: key,
  ))!;
  return ForumBoardFavoriteBlockedException(
    record: record,
    boardId: 30,
    favoriteId: 71,
    shouldBeFavorite: false,
  );
}

Response<String> _response(String data, Uri uri) {
  return Response<String>(
    data: data,
    requestOptions: RequestOptions(path: uri.toString()),
    statusCode: 200,
  );
}

String _listHtml({
  required List<RawFavoriteItem> items,
  required int page,
  required int totalPages,
  Uri? nextUri,
}) {
  final String rows = items.map((RawFavoriteItem item) => '''
    <li class="sclist">
      <a href="${item.deleteDialogUri}">删除</a>
      <h4><a href="${item.targetUri}">${item.title}</a></h4>
    </li>
  ''').join();
  return '''
    <html><body id="home" class="pg_space">
      <script>var discuz_uid = '42';</script>
      <a class="a" href="home.php?mod=space&amp;do=favorite&amp;view=me&amp;type=forum&amp;uid=42&amp;mobile=2">版块</a>
      <div class="findbox"><ul>$rows</ul></div>
      ${totalPages > 1 ? '''
        <div class="pg">
          <strong>$page</strong>
          <label><input name="custompage" value="$page"><span title="共 $totalPages 页"></span></label>
          ${nextUri == null ? '' : '<a class="nxt" href="$nextUri">下一页</a>'}
        </div>
      ''' : ''}
    </body></html>
  ''';
}

const String _identityHtml = '''
  <html><body id="home" class="pg_spacecp">
    <script>var discuz_uid = '42';</script>
  </body></html>
''';

const String _deleteFormHtml = '''
  <html><body id="home" class="pg_spacecp">
    <script>var discuz_uid = '42';</script>
    <form id="favoriteform_71" method="post"
      action="home.php?mod=spacecp&amp;ac=favorite&amp;op=delete&amp;favid=71&amp;type=forum&amp;mobile=2">
      <input type="hidden" name="referer" value="home.php?mod=space&amp;do=favorite&amp;type=forum&amp;uid=42&amp;mobile=2">
      <input type="hidden" name="deletesubmit" value="opaque-hidden-marker">
      <input type="hidden" name="formhash" value="opaque-form-token">
      <input type="submit" name="deletesubmitbtn" value="opaque-button-marker">
    </form>
  </body></html>
''';

final Uri _boardUri = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=30&mobile=2',
);
final Uri _addUri = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&type=forum&id=30&handlekey=opaque-board-control&mobile=2',
);
final Uri _deleteEntry = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&op=delete&favid=71&mobile=2',
);
final Uri _deleteAction = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&op=delete&favid=71&type=forum&mobile=2',
);
final RawFavoriteItem _boardItem = RawFavoriteItem(
  favoriteId: 71,
  categoryKey: 'forum',
  title: '版块收藏',
  targetKind: RawFavoriteTargetKind.board,
  targetUri: _boardUri,
  deleteDialogUri: _deleteEntry,
  boardId: 30,
);
