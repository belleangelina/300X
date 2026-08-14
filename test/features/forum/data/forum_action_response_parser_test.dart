import 'package:flutter_test/flutter_test.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/data/forum_action_response_parser.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

void main() {
  const ForumActionResponseParser parser = ForumActionResponseParser();

  test('解析服务端明确成功但仍要求回读且不直接允许缓存变更', () {
    final ForumSubmissionResult result = parser.parse(
      '''
      {"Message":{"messageval":"post_newthread_succeed", "messagestr":"主题发布成功"},
       "Variables":{"member_uid":"42", "tid":"101", "pid":"202"}}
      ''',
      _actionUri,
      _prepared,
    );

    expect(result.status, ForumSubmissionStatus.success);
    expect(result.threadId, 101);
    expect(result.postId, 202);
    expect(result.requiresReadback, isTrue);
    expect(result.permitsCacheMutation, isFalse);
  });

  test('分别识别 token 过期、权限拒绝与明确失败', () {
    expect(
      parser
          .parse(
            _message('submit_invalid', 'formhash 已过期'),
            _actionUri,
            _prepared,
          )
          .status,
      ForumSubmissionStatus.tokenExpired,
    );
    expect(
      parser
          .parse(
            _message('group_nopermission', '没有权限回复'),
            _actionUri,
            _prepared,
          )
          .status,
      ForumSubmissionStatus.permissionDenied,
    );
    expect(
      parser
          .parse(
            _message('post_message_empty', '正文不能为空'),
            _actionUri,
            _prepared,
          )
          .status,
      ForumSubmissionStatus.explicitFailure,
    );
  });

  test('无明确结果和版块回读均返回 resultUnknown，表单回显不能冒充成功', () {
    expect(
      parser.parse('{}', _actionUri, _prepared).status,
      ForumSubmissionStatus.resultUnknown,
    );
    final ForumSubmissionResult redirected = parser.parse(
      '<html></html>',
      _readbackUri,
      _prepared,
    );
    expect(redirected.status, ForumSubmissionStatus.resultUnknown);
    expect(redirected.permitsCacheMutation, isFalse);

    expect(
      () => parser.parse(
        '''
        <html><body><form id="postform">
          <textarea name="message">messageval='post_newthread_succeed'</textarea>
        </form></body></html>
        ''',
        _actionUri.replace(
          queryParameters: <String, String>{
            ..._actionUri.queryParameters,
            'inajax': '1',
          },
        ),
        _prepared,
      ),
      throwsA(isA<ForumActionSecurityException>()),
    );

    final ForumSubmissionResult tipFormEcho = parser.parse(
      '''
      <div class="tip"><form id="postform">
        <textarea name="message">主题发布成功</textarea>
      </form></div>
      ''',
      _actionUri,
      _prepared,
    );
    expect(tipFormEcho.status, ForumSubmissionStatus.resultUnknown);
  });

  test('只接受服务端消息容器声明的 HTML 状态码', () {
    final ForumSubmissionResult result = parser.parse(
      '<div id="messagetext" data-message-code="post_newthread_succeed">'
      '主题发布成功</div>',
      _actionUri,
      _prepared,
    );

    expect(result.status, ForumSubmissionStatus.success);
  });

  test('消息容器任一位置含表单控件时不能用 sibling 成功文本或状态码', () {
    final ForumSubmissionResult messageText = parser.parse(
      '''
      <div id="messagetext">
        <p data-message-code="post_newthread_succeed">主题发布成功</p>
        <form><input name="message" value="回显"></form>
      </div>
      ''',
      _actionUri,
      _prepared,
    );
    expect(messageText.status, ForumSubmissionStatus.resultUnknown);

    final ForumSubmissionResult tip = parser.parse(
      '''
      <div class="tip">
        <div class="message">主题发布成功</div>
        <textarea name="message">回显</textarea>
      </div>
      ''',
      _actionUri,
      _prepared,
    );
    expect(tip.status, ForumSubmissionStatus.resultUnknown);
  });

  test('顶层与未登记 JSON 字段中的成功文本不能冒充 Message envelope', () {
    for (final String source in <String>[
      '{"message":"用户内容：成功"}',
      '{"messageval":"post_newthread_succeed","messagestr":"主题发布成功"}',
      '{"code":"success","message":"主题发布成功"}',
      '{"message":{"messageval":"post_newthread_succeed",'
          '"messagestr":"主题发布成功"}}',
      '{"echo":"<div id=\\"messagetext\\" '
          'data-message-code=\\"post_newthread_succeed\\">主题发布成功</div>"}',
      '{"Message":{"messagestr":"<div id=\\"messagetext\\" '
          'data-message-code=\\"post_newthread_succeed\\">用户回显</div>"}}',
    ]) {
      final ForumSubmissionResult result = parser.parse(
        source,
        _actionUri,
        _prepared,
      );
      expect(result.status, ForumSubmissionStatus.resultUnknown);
    }
  });

  test('未知成功样式状态码和自然语言成功文本不会提升为明确成功', () {
    for (final String source in <String>[
      '{"Message":{"messageval":"not_success",'
          '"messagestr":"未能成功提交"}}',
      '{"Message":{"messageval":"unknown_result",'
          '"messagestr":"主题发布成功"}}',
      '<div id="messagetext">未能成功提交</div>',
      '<div id="messagetext">主题发布成功</div>',
    ]) {
      final ForumSubmissionResult result = parser.parse(
        source,
        _actionUri,
        _prepared,
      );
      expect(result.status, ForumSubmissionStatus.resultUnknown);
    }
  });

  test('发主题提交后只接受同源 mobile 新主题跳转', () {
    final ForumSubmissionResult redirected = parser.parse(
      '<html></html>',
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=777&mobile=2',
      ),
      _prepared,
    );
    expect(redirected.status, ForumSubmissionStatus.success);
    expect(redirected.threadId, 777);

    expect(
      () => parser.parse(
        '<html></html>',
        Uri.parse('https://bbs.yamibo.com/forum.php?mod=viewthread&mobile=2'),
        _prepared,
      ),
      throwsA(isA<ForumActionSecurityException>()),
    );

    for (final Uri unsafe in <Uri>[
      Uri.parse(
        'https://evil.example/forum.php?mod=viewthread&tid=777&mobile=2',
      ),
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=777',
      ),
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=777&mobile=2&op=delete',
      ),
    ]) {
      expect(
        () => parser.parse(
          _message('post_newthread_succeed', '主题发布成功'),
          unsafe,
          _prepared,
        ),
        throwsA(isA<ForumActionSecurityException>()),
      );
    }
  });
}

String _message(String code, String message) {
  return '{"Message":{"messageval":"$code", "messagestr":"$message"},'
      '"Variables":{"member_uid":"42"}}';
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
final ForumPreparedAction _prepared = ForumPreparedAction(
  token: 'one-time-token',
  userId: 42,
  request: _request,
  form: DynamicForumForm(
    sourceUri: _entryUri,
    actionUri: _actionUri,
    hiddenFields: const <String, List<String>>{
      'formhash': <String>['memory-only'],
      'fid': <String>['30'],
    },
    submitFields: const <String, List<String>>{
      'topicsubmit': <String>['yes'],
    },
    fields: const <DynamicForumField>[],
    attachmentFields: const <ForumAttachmentField>[],
    preparedAt: DateTime.utc(2026, 8, 13),
  ),
  readback: ForumReadbackDescriptor(
    kind: ForumReadbackKind.boardThreads,
    uri: _readbackUri,
    target: _request.target,
    description: '回读主题',
  ),
);
