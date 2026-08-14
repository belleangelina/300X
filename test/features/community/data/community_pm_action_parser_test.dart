import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/community/data/community_pm_action_parser.dart';
import 'package:x300/features/community/domain/community_pm_action_models.dart';

void main() {
  const CommunityPmActionParser parser = CommunityPmActionParser();

  test('解析真实移动新私信标准 POST 白名单', () {
    final CommunityPmSendForm form = parser.parse(
      _composeHtml(),
      _composeUri,
      expectedViewerUserId: 42,
      request: _composeRequest,
    );

    expect(form.viewerUserId, 42);
    expect(form.context, CommunityPmSendContext.compose);
    expect(form.peerUserId, 0);
    expect(form.privateMessageId, 0);
    expect(form.actionUri, _composeActionUri);
    expect(form.formHash, 'one-use-secret');
    expect(form.acceptsUsername, isTrue);
    expect(form.fixedFields, <String, String>{
      'pmsubmit': 'yes',
      'referer': 'home.php?mod=space&do=pm&mobile=2',
    });
  });

  test('解析当前会话精确 touid 和 pmid 回复表单', () {
    final CommunityPmSendForm form = parser.parse(
      _conversationHtml(),
      _conversationUri,
      expectedViewerUserId: 42,
      request: _conversationRequest,
    );

    expect(form.context, CommunityPmSendContext.conversation);
    expect(form.peerUserId, 77);
    expect(form.privateMessageId, 123);
    expect(form.acceptsUsername, isFalse);
    expect(form.fixedFields, <String, String>{
      'pmsubmit': 'yes',
      'touid': '77',
    });
  });

  test('外域、桌面页、错 uid 和错 touid 全部拒绝', () {
    expect(
      () => parser.parse(
        _composeHtml(),
        Uri.parse('https://evil.example/home.php?mod=spacecp&ac=pm&mobile=2'),
        expectedViewerUserId: 42,
        request: _composeRequest,
      ),
      throwsA(isA<ForumException>()),
    );
    expect(
      () => parser.validateEntryUri(
        CommunityPmSendRequest(
          context: CommunityPmSendContext.compose,
          entryUri: Uri.parse(
            'https://bbs.yamibo.com/home.php?mod=spacecp&ac=pm',
          ),
        ),
        Uri.parse('https://bbs.yamibo.com/home.php?mod=spacecp&ac=pm'),
      ),
      throwsA(isA<ForumException>()),
    );
    expect(
      () => parser.parse(
        _composeHtml(userId: 7),
        _composeUri,
        expectedViewerUserId: 42,
        request: _composeRequest,
      ),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    expect(
      () => parser.parse(
        _conversationHtml(hiddenPeerUserId: 88),
        _conversationUri,
        expectedViewerUserId: 42,
        request: _conversationRequest,
      ),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('动作多余参数、字段漂移和无效 pmid 均 fail closed', () {
    expect(
      () => parser.parse(
        _composeHtml(actionSuffix: '&extra=1'),
        _composeUri,
        expectedViewerUserId: 42,
        request: _composeRequest,
      ),
      throwsA(isA<ForumParseException>()),
    );
    expect(
      () => parser.parse(
        _composeHtml(extraField: '<input name="subject" value="x">'),
        _composeUri,
        expectedViewerUserId: 42,
        request: _composeRequest,
      ),
      throwsA(isA<ForumParseException>()),
    );
    expect(
      () => parser.parse(
        _composeHtml(referer: 'https://evil.example/home.php?mobile=2'),
        _composeUri,
        expectedViewerUserId: 42,
        request: _composeRequest,
      ),
      throwsA(isA<ForumParseException>()),
    );
    expect(
      () => parser.parse(
        _composeHtml(actionSuffix: '&mobile=1'),
        _composeUri,
        expectedViewerUserId: 42,
        request: _composeRequest,
      ),
      throwsA(isA<ForumParseException>()),
    );
    expect(
      () => parser.parse(
        _conversationHtml(privateMessageId: 0),
        _conversationUri,
        expectedViewerUserId: 42,
        request: _conversationRequest,
      ),
      throwsA(isA<ForumParseException>()),
    );
  });
}

final Uri _composeUri = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=spacecp&ac=pm&mobile=2',
);
final Uri _composeActionUri = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=spacecp&ac=pm&op=send&pmid=0&touid=0&mobile=2',
);
final Uri _conversationUri = Uri.parse(
  'https://bbs.yamibo.com/home.php?mod=space&do=pm&subop=view&touid=77&mobile=2',
);
final CommunityPmSendRequest _composeRequest = CommunityPmSendRequest(
  context: CommunityPmSendContext.compose,
  entryUri: _composeUri,
);
final CommunityPmSendRequest _conversationRequest = CommunityPmSendRequest(
  context: CommunityPmSendContext.conversation,
  entryUri: _conversationUri,
  expectedPeerUserId: 77,
  expectedPeerUsername: '用户A',
);

String _composeHtml({
  int userId = 42,
  String actionSuffix = '',
  String extraField = '',
  String referer = 'home.php?mod=space&amp;do=pm&amp;mobile=2',
}) {
  return '''
<!doctype html><html><body id="home" class="pg_spacecp">
<script>var discuz_uid='$userId';</script>
<form method="post" action="home.php?mod=spacecp&amp;ac=pm&amp;op=send&amp;pmid=0&amp;touid=0&amp;mobile=2$actionSuffix">
  <input type="hidden" name="formhash" value="one-use-secret">
  <input type="text" name="username" value="">
  <textarea name="message"></textarea>
  <input type="hidden" name="referer" value="$referer">
  <input type="hidden" name="pmsubmit" value="yes">
  $extraField
</form>
</body></html>
''';
}

String _conversationHtml({
  int hiddenPeerUserId = 77,
  int privateMessageId = 123,
}) {
  return '''
<!doctype html><html><body id="home" class="pg_space">
<script>var discuz_uid='42';</script>
<div class="msgbox">
<form id="pmform" method="post" action="home.php?mod=spacecp&amp;ac=pm&amp;op=send&amp;pmid=$privateMessageId&amp;pmsubmit=yes&amp;daterange=2&amp;mobile=2">
  <input type="hidden" name="formhash" value="one-use-secret">
  <input type="hidden" name="touid" value="$hiddenPeerUserId">
  <input type="text" name="message" value="">
  <button name="pmsubmit" value="yes">发送</button>
</form>
</div>
</body></html>
''';
}
