import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_client.dart';
import 'package:x300/core/network/forum_exceptions.dart';

void main() {
  test('HTTP 错误显示中文状态而不是 Dio 英文说明', () async {
    final ForumClient client = _client(
      (RequestOptions options) => ResponseBody.fromString('not found', 404),
    );

    await expectLater(
      client.getText('forum.php?mod=viewthread&tid=1', retryCount: 0),
      throwsA(
        isA<ForumConnectionException>().having(
          (ForumConnectionException error) => error.message,
          'message',
          '论坛返回异常（HTTP 404），请稍后重试',
        ),
      ),
    );
  });

  test('连接超时和连接失败使用中文网络提示', () async {
    final ForumClient timeoutClient = _client(
      (RequestOptions options) => throw DioException.connectionTimeout(
        timeout: const Duration(seconds: 20),
        requestOptions: options,
      ),
    );
    final ForumClient offlineClient = _client(
      (RequestOptions options) => throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection refused',
      ),
    );

    await expectLater(
      timeoutClient.getText('forum.php', retryCount: 0),
      throwsA(
        isA<ForumConnectionException>().having(
          (ForumConnectionException error) => error.message,
          'message',
          '连接百合会论坛超时，请稍后重试',
        ),
      ),
    );
    await expectLater(
      offlineClient.getBytes('data/attachment/forum/page.jpg'),
      throwsA(
        isA<ForumConnectionException>().having(
          (ForumConnectionException error) => error.message,
          'message',
          '加载论坛图片失败，请检查网络连接',
        ),
      ),
    );
  });
}

ForumClient _client(ResponseBody Function(RequestOptions options) respond) {
  final Dio dio = Dio(BaseOptions(baseUrl: ForumClient.baseUri.toString()))
    ..httpClientAdapter = _Adapter(respond);
  return ForumClient.forTesting(dio, CookieJar());
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}
