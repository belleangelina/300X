import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_client.dart';

void main() {
  test('相对跳转地址按上一跳逐级补全为绝对 realUri', () async {
    final ForumClient client = _client(
      (RequestOptions options) =>
          ResponseBody.fromString('<html></html>', 200, isRedirect: true)
            ..redirects = <RedirectRecord>[
              RedirectRecord(
                301,
                'GET',
                Uri.parse('/forum.php?mod=redirect&goto=findpost&pid=105'),
              ),
              // 论坛 findpost 实际返回的 Location 就是这种相对地址。
              RedirectRecord(
                301,
                'GET',
                Uri.parse(
                  'forum.php?mod=viewthread&tid=10&page=2&mobile=2#pid105',
                ),
              ),
            ],
    );

    final Response<String> response = await client.getText(
      'forum.php?mod=redirect&goto=findpost&ptid=10&pid=105&mobile=2',
    );

    final List<Uri> locations = response.redirects
        .map((RedirectRecord record) => record.location)
        .toList();
    expect(locations, <Uri>[
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&pid=105',
      ),
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10&page=2&mobile=2#pid105',
      ),
    ]);
    expect(
      response.realUri,
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=10&page=2&mobile=2#pid105',
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
