import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/dynamic_forum_form_parser.dart';
import 'package:x300/features/forum/data/forum_action_contract.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

void main() {
  const DynamicForumFormParser parser = DynamicForumFormParser();

  test('仅启用已盘点到标准 POST form 的七类操作', () {
    expect(ForumActionContract.verifiedKinds, <ForumActionKind>{
      ForumActionKind.newThread,
      ForumActionKind.reply,
      ForumActionKind.quoteReply,
      ForumActionKind.editPost,
      ForumActionKind.favoriteThread,
      ForumActionKind.removeFavorite,
      ForumActionKind.shareThread,
    });
    expect(
      ForumActionKind.values
          .where(
            (ForumActionKind kind) =>
                !ForumActionContract.verifiedKinds.contains(kind),
          )
          .toSet()
          .containsAll(<ForumActionKind>[
            ForumActionKind.deletePost,
            ForumActionKind.vote,
            ForumActionKind.comment,
            ForumActionKind.rate,
            ForumActionKind.report,
            ForumActionKind.favoriteBoard,
          ]),
      isTrue,
    );
  });

  test('四类已验证操作都能解析对应真实移动标准 form 形状', () {
    final List<(ForumActionRequest, String, Set<String>)> cases =
        <(ForumActionRequest, String, Set<String>)>[
          (_newThreadRequest, _newThreadForm(), const <String>{'topicsubmit'}),
          (
            _favoriteThreadRequest,
            _favoriteThreadForm(),
            const <String>{'favoritesubmit', 'favoritesubmit_btn'},
          ),
          (
            _removeFavoriteRequest,
            _removeFavoriteForm(),
            const <String>{'deletesubmit'},
          ),
          (
            _shareThreadRequest,
            _shareThreadForm(),
            const <String>{'sharesubmit', 'sharesubmit_btn'},
          ),
        ];

    for (final (ForumActionRequest request, String source, Set<String> markers)
        in cases) {
      final DynamicForumForm form = parser.parse(
        source,
        request.entryUri,
        expectedUserId: 42,
        request: request,
      );
      expect(
        <String>{...form.hiddenFields.keys, ...form.submitFields.keys},
        containsAll(markers),
        reason: request.kind.name,
      );
    }
  });

  test('解析真实移动 form 实际声明的动态字段并隔离附件接口', () {
    final DynamicForumForm form = parser.parse(
      _newThreadForm(),
      _newThreadEntry,
      expectedUserId: 42,
      request: _newThreadRequest,
    );

    expect(form.actionUri, _newThreadAction);
    expect(form.formHash, 'memory-only-token');
    expect(form.hiddenFields['custom_hidden'], <String>['kept']);
    expect(form.submitFields['topicsubmit'], <String>['yes']);
    expect(form.fieldByName('subject')?.isRequired, isTrue);
    expect(form.fieldByName('message')?.isRequired, isTrue);
    expect(form.fieldByName('typeid')?.options, hasLength(2));
    expect(form.fieldByName('tags[]')?.initialValues, <String>['comic']);
    expect(
      form.fieldByName('future_widget')?.type,
      DynamicForumFieldType.unsupported,
    );
    expect(form.attachmentFields.single.fieldName, 'Filedata');
    expect(form.attachmentFields.single.allowedExtensions, <String>[
      '.jpg',
      '.png',
    ]);
    expect(form.attachmentUploadVerified, isFalse);
  });

  test('拒绝外域 action、错目标 action 与错 uid', () {
    expect(
      () => parser.parse(
        _newThreadForm(action: 'https://evil.example/submit'),
        _newThreadEntry,
        expectedUserId: 42,
        request: _newThreadRequest,
      ),
      throwsA(isA<ForumActionSecurityException>()),
    );
    expect(
      () => parser.parse(
        _newThreadForm(
          action: 'forum.php?mod=post&action=newthread&fid=999&mobile=2',
        ),
        _newThreadEntry,
        expectedUserId: 42,
        request: _newThreadRequest,
      ),
      throwsA(isA<ForumActionSecurityException>()),
    );
    expect(
      () => parser.parse(
        _newThreadForm(
          action:
              'forum.php?mod=post&action=newthread&fid=30&topicsubmit=yes&mobile=2&spaceuid=7',
        ),
        _newThreadEntry,
        expectedUserId: 42,
        request: _newThreadRequest,
      ),
      throwsA(isA<ForumSessionExpiredException>()),
    );
    expect(
      () => parser.parse(
        _newThreadForm(
          action: 'api/mobile/index.php?version=4&module=newthread&fid=30',
        ),
        _newThreadEntry,
        expectedUserId: 42,
        request: _newThreadRequest,
      ),
      throwsA(isA<ForumActionSecurityException>()),
    );
    expect(
      () => parser.parse(
        _newThreadForm(userId: 7),
        _newThreadEntry,
        expectedUserId: 42,
        request: _newThreadRequest,
      ),
      throwsA(isA<ForumSessionExpiredException>()),
    );
  });

  test('验证码结构不完整时 fail closed，完整结构仅保留内存描述', () {
    final String incomplete = _newThreadForm().replaceFirst(
      '<textarea name="message" required maxlength="200">draft</textarea>',
      '<input name="seccodeverify" required />'
          '<textarea name="message" required maxlength="200">draft</textarea>',
    );
    expect(
      () => parser.parse(
        incomplete,
        _newThreadEntry,
        expectedUserId: 42,
        request: _newThreadRequest,
      ),
      throwsA(isA<ForumParseException>()),
    );

    final String complete = _newThreadForm()
        .replaceFirst(
          '<input type="hidden" name="custom_hidden" value="kept" />',
          '<input type="hidden" name="custom_hidden" value="kept" />'
              '<input type="hidden" name="seccodehash" value="hash-1" />',
        )
        .replaceFirst(
          '<textarea name="message" required maxlength="200">draft</textarea>',
          '<input name="seccodeverify" required />'
              '<img src="misc.php?mod=seccode&update=1" />'
              '<textarea name="message" required maxlength="200">draft</textarea>',
        );
    final DynamicForumForm form = parser.parse(
      complete,
      _newThreadEntry,
      expectedUserId: 42,
      request: _newThreadRequest,
    );

    expect(form.captcha?.fieldName, 'seccodeverify');
    expect(form.captcha?.hashFieldName, 'seccodehash');
    expect(form.captcha?.imageUri.host, 'bbs.yamibo.com');

    final String unsupportedQuestion = _newThreadForm().replaceFirst(
      '<textarea name="message" required maxlength="200">draft</textarea>',
      '<input name="secanswer" required />'
          '<textarea name="message" required maxlength="200">draft</textarea>',
    );
    expect(
      () => parser.parse(
        unsupportedQuestion,
        _newThreadEntry,
        expectedUserId: 42,
        request: _newThreadRequest,
      ),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('隐藏字段不能与动态字段重名覆盖已校验载荷', () {
    final String collision = _newThreadForm().replaceFirst(
      '<input type="text" name="subject" required />',
      '<input type="hidden" name="subject" value="hidden" />'
          '<input type="text" name="subject" required />',
    );
    expect(
      () => parser.parse(
        collision,
        _newThreadEntry,
        expectedUserId: 42,
        request: _newThreadRequest,
      ),
      throwsA(
        isA<ForumParseException>().having(
          (ForumParseException error) => error.message,
          'message',
          contains('字段角色冲突'),
        ),
      ),
    );
  });

  test('隐藏路由、错目标和其他操作提交标记不能改变已验证动作', () {
    for (final String injected in <String>[
      '<input type="hidden" name="action" value="edit" />',
      '<input type="hidden" name="op" value="delete" />',
      '<input type="hidden" name="pid" value="999" />',
      '<input type="hidden" name="fid" value="999" />',
      '<input type="hidden" name="fid" value="30" />',
      '<input type="hidden" name="replysubmit" value="yes" />',
      '<input type="hidden" name="topicsubmit" value="" />',
      '<input type="hidden" name="topicsubmit" value="yes" />'
          '<input type="hidden" name="topicsubmit" value="yes" />',
      '<input type="hidden" name="uid[]" value="42" />',
      '<input type="hidden" name="fid[]" value="30" />',
    ]) {
      final String source = _newThreadForm().replaceFirst(
        '<input type="hidden" name="custom_hidden" value="kept" />',
        '<input type="hidden" name="custom_hidden" value="kept" />$injected',
      );
      expect(
        () => parser.parse(
          source,
          _newThreadEntry,
          expectedUserId: 42,
          request: _newThreadRequest,
        ),
        throwsA(isA<ForumActionSecurityException>()),
        reason: injected,
      );
    }

    final String duplicateUid = _newThreadForm().replaceFirst(
      '<input type="hidden" name="custom_hidden" value="kept" />',
      '<input type="hidden" name="custom_hidden" value="kept" />'
          '<input type="hidden" name="uid" value="42" />'
          '<input type="hidden" name="uid" value="42" />',
    );
    expect(
      () => parser.parse(
        duplicateUid,
        _newThreadEntry,
        expectedUserId: 42,
        request: _newThreadRequest,
      ),
      throwsA(isA<ForumSessionExpiredException>()),
    );
  });

  test('账号与目标保留字段不能作为用户可编辑字段进入载荷', () {
    for (final String reserved in <String>['uid', 'spaceuid', 'fid', 'id[]']) {
      final String collision = _newThreadForm().replaceFirst(
        '<input type="text" name="subject" required />',
        '<input type="text" name="$reserved" value="999" />'
        '<input type="text" name="subject" required />',
      );

      expect(
        () => parser.parse(
          collision,
          _newThreadEntry,
          expectedUserId: 42,
          request: _newThreadRequest,
        ),
        throwsA(isA<ForumActionSecurityException>()),
        reason: reserved,
      );
    }
  });

  test('可编辑字段的 PHP 数组别名不能覆盖保留传输字段', () {
    for (final String name in const <String>[
      'uid[x]',
      'fid[foo]',
      'formhash[0]',
      'action[]',
    ]) {
      expect(
        () => parser.parse(
          _newThreadForm(
            extraField: '<input type="text" name="$name" value="x" />',
          ),
          _newThreadRequest.entryUri,
          expectedUserId: 42,
          request: _newThreadRequest,
        ),
        throwsA(isA<ForumActionSecurityException>()),
        reason: name,
      );
    }
  });

  test('操作地址中的 PHP 数组别名不能绕过路由和目标校验', () {
    for (final String alias in <String>[
      '&action%5B%5D=edit',
      '&fid%5B%5D=999',
      '&mobile%5B%5D=2',
    ]) {
      expect(
        () => parser.parse(
          _newThreadForm(action: '$_newThreadAction$alias'),
          _newThreadEntry,
          expectedUserId: 42,
          request: _newThreadRequest,
        ),
        throwsA(isA<ForumActionSecurityException>()),
        reason: alias,
      );
    }
  });

  test('操作地址不能夹带其他路由目标或提交参数', () {
    final ForumActionRequest malicious = ForumActionRequest(
      kind: ForumActionKind.newThread,
      target: _newThreadRequest.target,
      entryUri: Uri.parse(
        '$_newThreadEntry&op=delete&tid=1&tid=2&deletesubmit=1',
      ),
      readbackUri: _newThreadRequest.readbackUri,
    );
    expect(
      () => parser.parse(
        _newThreadForm(),
        malicious.entryUri,
        expectedUserId: 42,
        request: malicious,
      ),
      throwsA(isA<ForumActionSecurityException>()),
    );
    expect(
      () => parser.parse(
        _newThreadForm(
          action: '$_newThreadAction&op=delete&pid=9',
        ),
        _newThreadRequest.entryUri,
        expectedUserId: 42,
        request: _newThreadRequest,
      ),
      throwsA(isA<ForumActionSecurityException>()),
    );
  });

  test('非隐藏 readonly 字段不会被降级为可编辑用户输入', () {
    final String readonly = _newThreadForm().replaceFirst(
      '<input type="text" name="subject" required />',
      '<input type="text" name="subject" readonly value="固定标题" />',
    );

    expect(
      () => parser.parse(
        readonly,
        _newThreadEntry,
        expectedUserId: 42,
        request: _newThreadRequest,
      ),
      throwsA(isA<ForumParseException>()),
    );
  });

  test('评分 GET 无标准 form 契约时在解析前 fail closed', () {
    final ForumActionRequest rate = ForumActionRequest(
      kind: ForumActionKind.rate,
      target: const ForumActionTarget(threadId: 101, postId: 202),
      entryUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=misc&action=rate&tid=101&pid=202&mobile=2',
      ),
      readbackUri: Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=misc&action=viewratings&tid=101&pid=202&mobile=2',
      ),
    );

    expect(
      () => parser.parse(
        _newThreadForm(),
        rate.entryUri,
        expectedUserId: 42,
        request: rate,
      ),
      throwsA(
        isA<ForumParseException>().having(
          (ForumParseException error) => error.message,
          'message',
          contains('尚未取得真实移动标准表单契约'),
        ),
      ),
    );
  });

  test('草稿拒绝 formhash 和验证码，只保留结构化用户输入', () {
    final ForumActionDraft draft = ForumActionDraft(
      userId: 42,
      kind: ForumActionKind.newThread,
      target: _newThreadRequest.target,
      values: <String, List<String>>{
        'subject': <String>['草稿标题'],
        'message': <String>['草稿正文'],
      },
      updatedAt: DateTime.utc(2026, 8, 13),
    );
    expect(draft.values['message'], <String>['草稿正文']);
    for (final String forbidden in <String>['formhash', 'seccodeverify']) {
      expect(
        () => ForumActionDraft(
          userId: 42,
          kind: ForumActionKind.newThread,
          target: _newThreadRequest.target,
          values: <String, List<String>>{
            forbidden: <String>['must-not-persist'],
          },
          updatedAt: DateTime.utc(2026, 8, 13),
        ),
        throwsArgumentError,
      );
    }
  });
}

final Uri _newThreadEntry = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=newthread&fid=30&mobile=2',
);
final Uri _newThreadAction = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=newthread&fid=30&topicsubmit=yes&mobile=2',
);
final Uri _threadReadback = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101&mobile=2',
);
final Uri _boardReadback = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=forumdisplay&fid=30&mobile=2',
);
final ForumActionRequest _newThreadRequest = ForumActionRequest(
  kind: ForumActionKind.newThread,
  target: const ForumActionTarget(boardId: 30),
  entryUri: _newThreadEntry,
  readbackUri: _boardReadback,
);
final ForumActionRequest _favoriteThreadRequest = ForumActionRequest(
  kind: ForumActionKind.favoriteThread,
  target: const ForumActionTarget(threadId: 101),
  entryUri: Uri.parse(
    'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&type=thread&id=101&mobile=2',
  ),
  readbackUri: Uri.parse(
    'https://bbs.yamibo.com/home.php?mod=space&do=favorite&type=thread&mobile=2',
  ),
);
final ForumActionRequest _removeFavoriteRequest = ForumActionRequest(
  kind: ForumActionKind.removeFavorite,
  target: const ForumActionTarget(favoriteId: 9),
  entryUri: Uri.parse(
    'https://bbs.yamibo.com/home.php?mod=spacecp&ac=favorite&op=delete&favid=9&type=thread&mobile=2',
  ),
  readbackUri: _favoriteThreadRequest.readbackUri,
);
final ForumActionRequest _shareThreadRequest = ForumActionRequest(
  kind: ForumActionKind.shareThread,
  target: const ForumActionTarget(threadId: 101),
  entryUri: Uri.parse(
    'https://bbs.yamibo.com/home.php?mod=spacecp&ac=share&type=thread&id=101&mobile=2',
  ),
  readbackUri: _threadReadback,
);

String _newThreadForm({
  int userId = 42,
  String? action,
  String extraField = '',
}) {
  return '''
    <html><body class="pg_post">
      <script>var discuz_uid = '$userId';</script>
      <form id="postform" method="post"
        action="${action ?? 'forum.php?mod=post&amp;action=newthread&amp;fid=30&amp;topicsubmit=yes&amp;mobile=2'}">
        <input type="hidden" name="formhash" value="memory-only-token" />
        <input type="hidden" name="fid" value="30" />
        <input type="hidden" name="custom_hidden" value="kept" />
        <input type="text" name="subject" required />
        $extraField
        <label for="message">正文</label>
        <textarea name="message" required maxlength="200">draft</textarea>
        <select name="typeid">
          <option value="0">请选择</option>
          <option value="7" selected>交流</option>
        </select>
        <label><input type="checkbox" name="tags[]" value="comic" checked />漫画</label>
        <label><input type="checkbox" name="tags[]" value="novel" />小说</label>
        <input type="future-control" name="future_widget" />
        <input type="file" name="Filedata" multiple accept=".jpg,.png,image/webp" />
        <button type="submit" name="topicsubmit" value="yes">发帖</button>
      </form>
    </body></html>
  ''';
}

String _favoriteThreadForm() {
  return '''
    <html><body><script>var discuz_uid = '42';</script>
      <form id="favoriteform_101" method="post"
        action="home.php?mod=spacecp&amp;ac=favorite&amp;type=thread&amp;id=101&amp;spaceuid=42&amp;mobile=2">
        <input type="hidden" name="formhash" value="favorite-token" />
        <input type="hidden" name="referer" value="forum.php?mod=viewthread&amp;tid=101&amp;mobile=2" />
        <input type="hidden" name="favoritesubmit" value="yes" />
        <textarea name="description"></textarea>
        <button type="submit" name="favoritesubmit_btn" value="yes">收藏</button>
      </form>
    </body></html>
  ''';
}

String _removeFavoriteForm() {
  return '''
    <html><body><script>var discuz_uid = '42';</script>
      <form id="favoriteform_9" method="post"
        action="home.php?mod=spacecp&amp;ac=favorite&amp;op=delete&amp;favid=9&amp;type=thread&amp;mobile=2">
        <input type="hidden" name="formhash" value="delete-token" />
        <input type="hidden" name="referer" value="home.php?mod=space&amp;do=favorite&amp;type=thread&amp;mobile=2" />
        <button type="submit" name="deletesubmit" value="yes">删除</button>
      </form>
    </body></html>
  ''';
}

String _shareThreadForm() {
  return '''
    <html><body><script>var discuz_uid = '42';</script>
      <form id="shareform_101" method="post"
        action="home.php?mod=spacecp&amp;ac=share&amp;type=thread&amp;id=101&amp;mobile=2">
        <input type="hidden" name="formhash" value="share-token" />
        <input type="hidden" name="referer" value="forum.php?mod=viewthread&amp;tid=101&amp;mobile=2" />
        <input type="hidden" name="sharesubmit" value="yes" />
        <textarea name="general"></textarea>
        <label><input type="checkbox" name="iscomment" value="1" />同时评论</label>
        <button type="submit" name="sharesubmit_btn" value="yes">分享</button>
      </form>
    </body></html>
  ''';
}
