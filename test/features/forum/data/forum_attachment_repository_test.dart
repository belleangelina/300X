import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/forum_attachment_repository.dart';
import 'package:x300/features/forum/domain/forum_models.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('x300_attachment_test_');
  });

  tearDown(() async {
    await ForumAttachmentRepository.clearAllCaches(
      cacheDirectory: () async => root,
    );
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('账号租约覆盖身份校验、同源跳转和完整流消费，并携 Cookie 与主题 Referer', () async {
    final _AttachmentAdapter adapter = _AttachmentAdapter(
      redirectAid: 7,
      bodies: <int, List<List<int>>>{
        7: <List<int>>[
          <int>[1, 2],
          <int>[3, 4, 5],
        ],
      },
    );
    final ForumClient client = await _client(adapter, root, userId: 101);
    final ForumAttachmentRepository repository = ForumAttachmentRepository(
      client,
      101,
      cacheDirectory: () async => root,
    );
    final List<int> progress = <int>[];

    final ForumDownloadedAttachment result = await repository.download(
      _attachment(7, name: '资料.pdf'),
      topicSourceUri: _topicUri(fragment: 'pid9'),
      onProgress: (int received, int? total) => progress.add(received),
    );

    expect(await result.file.readAsBytes(), <int>[1, 2, 3, 4, 5]);
    expect(result.byteLength, 5);
    expect(result.fileName, '资料.pdf');
    expect(progress, <int>[2, 5]);
    expect(adapter.identityRequests, 1);
    expect(adapter.attachmentRequests, 2);
    for (final RequestOptions request in adapter.requests) {
      expect(
        request.headers[HttpHeaders.cookieHeader]?.toString(),
        contains('session=uid-101'),
      );
    }
    for (final RequestOptions request in adapter.requests.skip(1)) {
      expect(
        request.headers[HttpHeaders.refererHeader],
        _topicUri().toString(),
      );
      expect(request.followRedirects, isFalse);
    }
  });

  test('外域、敏感参数、路径逃逸和附件 fragment 在网络前失败关闭', () async {
    final _AttachmentAdapter adapter = _AttachmentAdapter();
    final ForumClient client = await _client(adapter, root, userId: 101);
    final ForumAttachmentRepository repository = ForumAttachmentRepository(
      client,
      101,
      cacheDirectory: () async => root,
    );
    final List<Uri> invalid = <Uri>[
      Uri.parse('https://example.org/file.zip'),
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=attachment&aid=7&token=secret',
      ),
      Uri.parse('https://bbs.yamibo.com/data/attachment/%2e%2e/secret.pdf'),
      Uri.parse('https://bbs.yamibo.com/data/attachment/a%5cb/secret.pdf'),
      Uri.parse('https://bbs.yamibo.com/forum.php?mod=attachment&aid=7#file'),
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=attachment&aid=7&extra=1',
      ),
    ];

    for (final Uri uri in invalid) {
      expect(
        () => repository.download(
          ForumAttachment(name: '资料', uri: uri),
          topicSourceUri: _topicUri(),
        ),
        throwsA(isA<ForumAttachmentDownloadException>()),
      );
    }
    expect(adapter.requests, isEmpty);
  });

  test('跳往外域或不同附件目标时不发后续请求且不会泄露 Cookie', () async {
    final _AttachmentAdapter adapter = _AttachmentAdapter(
      redirectLocation: Uri.parse('https://example.org/private'),
    );
    final ForumClient client = await _client(adapter, root, userId: 101);
    final ForumAttachmentRepository repository = ForumAttachmentRepository(
      client,
      101,
      cacheDirectory: () async => root,
    );

    await expectLater(
      repository.download(_attachment(7), topicSourceUri: _topicUri()),
      throwsA(isA<ForumConnectionException>()),
    );
    expect(adapter.attachmentRequests, 1);
    expect(
      adapter.requests.where(
        (RequestOptions value) => value.uri.host == 'example.org',
      ),
      isEmpty,
    );
  });

  test('Content-Length 与实际累计分别执行上限和完整性校验并清除临时文件', () async {
    final _AttachmentAdapter declaredTooLarge = _AttachmentAdapter(
      bodies: <int, List<List<int>>>{
        7: <List<int>>[
          <int>[1, 2],
        ],
      },
      declaredLengths: const <int, int>{7: 3},
    );
    final ForumClient firstClient = await _client(
      declaredTooLarge,
      root,
      userId: 101,
    );
    final ForumAttachmentRepository first = ForumAttachmentRepository(
      firstClient,
      101,
      cacheDirectory: () async => root,
      maximumBytes: 2,
    );
    await expectLater(
      first.download(_attachment(7), topicSourceUri: _topicUri()),
      throwsA(isA<ForumAttachmentDownloadException>()),
    );

    final _AttachmentAdapter streamedTooLarge = _AttachmentAdapter(
      identityUserId: 102,
      bodies: <int, List<List<int>>>{
        8: <List<int>>[
          <int>[1, 2],
          <int>[3],
        ],
      },
      omitContentLength: true,
    );
    final Directory secondRoot = Directory(path.join(root.path, 'second'));
    await secondRoot.create();
    final ForumClient secondClient = await _client(
      streamedTooLarge,
      secondRoot,
      userId: 102,
    );
    final ForumAttachmentRepository second = ForumAttachmentRepository(
      secondClient,
      102,
      cacheDirectory: () async => root,
      maximumBytes: 2,
    );
    await expectLater(
      second.download(_attachment(8), topicSourceUri: _topicUri()),
      throwsA(isA<ForumAttachmentDownloadException>()),
    );

    final Directory cache = Directory(
      path.join(root.path, 'forum-attachments'),
    );
    if (await cache.exists()) {
      final List<FileSystemEntity> files = await cache
          .list(recursive: true)
          .toList();
      expect(files.whereType<File>(), isEmpty);
    }
  });

  test('RFC5987 文件名去路径、控制字符、保留名与敏感字段且不持久化令牌', () async {
    final _AttachmentAdapter adapter = _AttachmentAdapter(
      bodies: <int, List<List<int>>>{
        7: <List<int>>[
          <int>[1],
        ],
      },
      dispositions: const <int, String>{
        7: "attachment; filename*=UTF-8'zh'..%2Fformhash%3Dsecret.pdf",
      },
      mimeTypes: const <int, String>{7: 'application/pdf'},
    );
    final ForumClient client = await _client(adapter, root, userId: 101);
    final ForumAttachmentRepository repository = ForumAttachmentRepository(
      client,
      101,
      cacheDirectory: () async => root,
    );

    final ForumDownloadedAttachment result = await repository.download(
      _attachment(7, name: 'token=other.pdf'),
      topicSourceUri: _topicUri(),
    );

    expect(result.fileName, '附件.pdf');
    expect(path.basename(result.file.path), '附件.pdf');
    expect(result.file.path.toLowerCase(), isNot(contains('formhash')));
    expect(result.file.path.toLowerCase(), isNot(contains('token')));
    expect(result.file.path, isNot(contains('secret')));
  });

  test('两个仓库实例同 uid 同目标共享单飞，不会并发写同一临时文件', () async {
    final _AttachmentAdapter adapter = _AttachmentAdapter(
      bodies: <int, List<List<int>>>{
        7: <List<int>>[
          <int>[1, 2, 3],
        ],
      },
    );
    final ForumClient client = await _client(adapter, root, userId: 101);
    final ForumAttachmentRepository first = ForumAttachmentRepository(
      client,
      101,
      cacheDirectory: () async => root,
    );
    final ForumAttachmentRepository second = ForumAttachmentRepository(
      client,
      101,
      cacheDirectory: () async => root,
    );

    final Future<ForumDownloadedAttachment> firstFuture = first.download(
      _attachment(7),
      topicSourceUri: _topicUri(),
    );
    final Future<ForumDownloadedAttachment> secondFuture = second.download(
      _attachment(7),
      topicSourceUri: _topicUri(),
    );
    expect(identical(firstFuture, secondFuture), isTrue);
    final List<ForumDownloadedAttachment> values = await Future.wait(
      <Future<ForumDownloadedAttachment>>[firstFuture, secondFuture],
    );
    expect(values[0].file.path, values[1].file.path);
    expect(adapter.identityRequests, 1);
    expect(adapter.attachmentRequests, 1);
    final Directory account = Directory(
      path.join(root.path, 'forum-attachments', 'uid-101'),
    );
    expect(
      (await account.list(recursive: true).toList()).whereType<File>(),
      hasLength(1),
    );
  });

  test('clear 取消并等待活跃流，返回后旧任务不会重建账号目录', () async {
    final _BlockingAttachmentAdapter adapter = _BlockingAttachmentAdapter();
    final ForumClient client = await _client(adapter, root, userId: 101);
    final ForumAttachmentRepository repository = ForumAttachmentRepository(
      client,
      101,
      cacheDirectory: () async => root,
    );
    final Future<ForumDownloadedAttachment> download = repository.download(
      _attachment(7),
      topicSourceUri: _topicUri(),
    );
    await adapter.streamStarted.future;

    await repository.clear();
    await expectLater(download, throwsA(isA<DioException>()));
    await Future<void>.delayed(Duration.zero);
    expect(
      await Directory(
        path.join(root.path, 'forum-attachments', 'uid-101'),
      ).exists(),
      isFalse,
    );
  });

  test('身份不匹配或附件返回登录 HTML 均失败关闭', () async {
    final _AttachmentAdapter wrongIdentity = _AttachmentAdapter(
      identityUserId: 202,
    );
    final ForumClient firstClient = await _client(
      wrongIdentity,
      root,
      userId: 101,
    );
    final ForumAttachmentRepository first = ForumAttachmentRepository(
      firstClient,
      101,
      cacheDirectory: () async => root,
    );
    await expectLater(
      first.download(_attachment(7), topicSourceUri: _topicUri()),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    expect(wrongIdentity.attachmentRequests, 0);

    final Directory secondRoot = Directory(path.join(root.path, 'html'));
    await secondRoot.create();
    final _AttachmentAdapter loginHtml = _AttachmentAdapter(
      identityUserId: 102,
      bodies: <int, List<List<int>>>{
        8: <List<int>>['<html>login</html>'.codeUnits],
      },
      mimeTypes: const <int, String>{8: 'text/html'},
    );
    final ForumClient secondClient = await _client(
      loginHtml,
      secondRoot,
      userId: 102,
    );
    final ForumAttachmentRepository second = ForumAttachmentRepository(
      secondClient,
      102,
      cacheDirectory: () async => root,
    );
    await expectLater(
      second.download(_attachment(8), topicSourceUri: _topicUri()),
      throwsA(isA<ForumSessionExpiredException>()),
    );
  });
}

ForumAttachment _attachment(int id, {String name = '资料.bin'}) {
  return ForumAttachment(
    id: id,
    name: name,
    uri: Uri.parse('https://bbs.yamibo.com/forum.php?mod=attachment&aid=$id'),
  );
}

Uri _topicUri({String fragment = ''}) {
  return Uri.parse(
    'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=9&mobile=2',
  ).replace(fragment: fragment);
}

Future<ForumClient> _client(
  HttpClientAdapter adapter,
  Directory supportRoot, {
  required int userId,
}) async {
  final ForumClient client = await ForumClient.create(
    userId: userId,
    supportDirectory: supportRoot,
    httpClientAdapter: adapter,
  );
  await client.importCookies(<Cookie>[Cookie('session', 'uid-$userId')]);
  return client;
}

class _AttachmentAdapter implements HttpClientAdapter {
  _AttachmentAdapter({
    this.identityUserId = 101,
    this.redirectAid,
    this.redirectLocation,
    this.bodies = const <int, List<List<int>>>{},
    this.declaredLengths = const <int, int>{},
    this.dispositions = const <int, String>{},
    this.mimeTypes = const <int, String>{},
    this.omitContentLength = false,
  });

  final int identityUserId;
  final int? redirectAid;
  final Uri? redirectLocation;
  final Map<int, List<List<int>>> bodies;
  final Map<int, int> declaredLengths;
  final Map<int, String> dispositions;
  final Map<int, String> mimeTypes;
  final bool omitContentLength;
  final List<RequestOptions> requests = <RequestOptions>[];
  int identityRequests = 0;
  int attachmentRequests = 0;
  bool _redirected = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final int? aid = int.tryParse(options.uri.queryParameters['aid'] ?? '');
    if (aid == null) {
      identityRequests++;
      return ResponseBody.fromString(
        "<script>var discuz_uid = '$identityUserId';</script>",
        HttpStatus.ok,
        headers: <String, List<String>>{
          HttpHeaders.contentTypeHeader: <String>['text/html; charset=utf-8'],
        },
      );
    }
    attachmentRequests++;
    if (!_redirected && (redirectLocation != null || redirectAid == aid)) {
      _redirected = true;
      return ResponseBody.fromBytes(
        const <int>[],
        HttpStatus.found,
        headers: <String, List<String>>{
          HttpHeaders.locationHeader: <String>[
            (redirectLocation ??
                    options.uri.replace(
                      queryParameters: <String, String>{
                        'mod': 'attachment',
                        'aid': '$aid',
                        'mobile': '2',
                      },
                    ))
                .toString(),
          ],
        },
      );
    }
    final List<List<int>> chunks =
        bodies[aid] ??
        <List<int>>[
          <int>[1],
        ];
    final int actualLength = chunks.fold<int>(
      0,
      (int total, List<int> value) => total + value.length,
    );
    final Map<String, List<String>> headers = <String, List<String>>{
      HttpHeaders.contentTypeHeader: <String>[
        mimeTypes[aid] ?? 'application/octet-stream',
      ],
      if (!omitContentLength)
        HttpHeaders.contentLengthHeader: <String>[
          '${declaredLengths[aid] ?? actualLength}',
        ],
      if (dispositions[aid] case final String disposition)
        'content-disposition': <String>[disposition],
    };
    return ResponseBody(
      Stream<Uint8List>.fromIterable(chunks.map(Uint8List.fromList)),
      HttpStatus.ok,
      headers: headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _BlockingAttachmentAdapter implements HttpClientAdapter {
  final Completer<void> streamStarted = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!options.uri.queryParameters.containsKey('aid')) {
      return ResponseBody.fromString(
        "<script>var discuz_uid = '101';</script>",
        HttpStatus.ok,
      );
    }
    final StreamController<Uint8List> controller =
        StreamController<Uint8List>();
    controller.onListen = () {
      streamStarted.complete();
      controller.add(Uint8List.fromList(<int>[1]));
      cancelFuture?.then((_) {
        controller.addError(
          DioException.requestCancelled(
            requestOptions: options,
            reason: 'cancelled',
          ),
        );
        controller.close();
      });
    };
    return ResponseBody(
      controller.stream,
      HttpStatus.ok,
      headers: <String, List<String>>{
        HttpHeaders.contentTypeHeader: <String>['application/octet-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
