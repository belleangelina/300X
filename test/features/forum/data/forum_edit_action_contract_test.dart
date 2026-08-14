import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/dynamic_forum_form_parser.dart';
import 'package:x300/features/forum/data/forum_action_contract.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

void main() {
  const DynamicForumFormParser parser = DynamicForumFormParser();
  const ForumActionContract contract = ForumActionContract();

  test('真实移动编辑表单绑定入口、隐藏目标与动态字段', () {
    expect(
      ForumActionContract.verifiedKinds,
      contains(ForumActionKind.editPost),
    );
    expect(
      ForumActionContract.verifiedKinds,
      isNot(contains(ForumActionKind.deletePost)),
    );

    final DynamicForumForm form = parser.parse(
      _editForm(),
      _entry,
      expectedUserId: 42,
      request: _request,
    );

    expect(form.actionUri, _action);
    expect(form.hiddenFields['fid'], <String>['30']);
    expect(form.hiddenFields['tid'], <String>['101']);
    expect(form.hiddenFields['pid'], <String>['202']);
    expect(form.hiddenFields['page'], <String>['2']);
    expect(form.submitFields, <String, List<String>>{
      'editsubmit': <String>['yes'],
    });
    expect(form.fieldByName('message')?.isRequired, isTrue);
    expect(form.fieldByName('subject')?.isRequired, isFalse);
    expect(form.fieldByName('subject')?.initialValues, <String>['原主题']);
    expect(form.fieldByName('message')?.initialValues, <String>['原正文']);
    expect(
      form.fields.where((DynamicForumField field) => field.name == 'Filedata'),
      hasLength(1),
    );
    expect(form.attachmentFields, hasLength(2));
    expect(form.attachmentUploadVerified, isFalse);
  });

  test('编辑入口与 GET final 必须精确绑定 fid tid pid page', () {
    for (final Uri uri in <Uri>[
      _replaceEntry(<String, String>{'page': '3'}),
      _replaceEntry(<String, String>{'fid': '31'}),
      _replaceEntry(<String, String>{'tid': '102'}),
      _replaceEntry(<String, String>{'pid': '203'}),
      Uri.parse(
        'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=30&tid=101&pid=202&mobile=2',
      ),
      Uri.parse('$_entry&extra=page%3D2'),
      Uri.parse('$_entry&page=2'),
    ]) {
      expect(
        () => contract.validateEntry(_request, uri),
        throwsA(isA<ForumException>()),
        reason: uri.toString(),
      );
    }

    expect(
      () => contract.validateEntry(
        ForumActionRequest(
          kind: ForumActionKind.editPost,
          target: const ForumActionTarget(
            boardId: 30,
            threadId: 101,
            postId: 202,
            favoriteId: 9,
          ),
          entryUri: _entry,
          readbackUri: _readback,
        ),
        _entry,
      ),
      throwsA(isA<ForumException>()),
    );
  });

  test('编辑 POST action 只接受已确认键和值且目标仅来自 hidden', () {
    for (final String action in <String>[
      'forum.php?mod=post&amp;action=edit&amp;editsubmit=yes&amp;mobile=2',
      'forum.php?mod=post&amp;action=edit&amp;editsubmit=no&amp;extra=&amp;mobile=2',
      'forum.php?mod=post&amp;action=edit&amp;editsubmit=yes&amp;extra=page%3D2&amp;mobile=2',
      'forum.php?mod=post&amp;action=edit&amp;editsubmit=yes&amp;extra=&amp;fid=30&amp;mobile=2',
      'forum.php?mod=post&amp;action=edit&amp;editsubmit=yes&amp;extra=&amp;mobile=no',
    ]) {
      expect(
        () => parser.parse(
          _editForm(action: action),
          _entry,
          expectedUserId: 42,
          request: _request,
        ),
        throwsA(isA<ForumException>()),
        reason: action,
      );
    }
  });

  test('编辑 hidden fid tid pid page 必须唯一且与入口完全一致', () {
    for (final String source in <String>[
      _editForm().replaceFirst(
        '<input type="hidden" name="fid" value="30" />',
        '',
      ),
      _editForm().replaceFirst('name="fid" value="30"', 'name="fid" value="31"'),
      _editForm().replaceFirst('name="tid" value="101"', 'name="tid" value="102"'),
      _editForm().replaceFirst('name="pid" value="202"', 'name="pid" value="203"'),
      _editForm().replaceFirst('name="page" value="2"', 'name="page" value="3"'),
      _editForm().replaceFirst(
        '<input type="hidden" name="page" value="2" />',
        '<input type="hidden" name="page" value="2" />\n'
            '<input type="hidden" name="page" value="2" />',
      ),
    ]) {
      expect(
        () => parser.parse(
          source,
          _entry,
          expectedUserId: 42,
          request: _request,
        ),
        throwsA(isA<ForumException>()),
      );
    }
  });

  test('editsubmit 必须是唯一 hidden yes 且拒绝任何同名控件', () {
    for (final String source in <String>[
      _editForm().replaceFirst(
        '<input type="hidden" name="editsubmit" value="yes" />',
        '',
      ),
      _editForm().replaceFirst(
        'name="editsubmit" value="yes"',
        'name="editsubmit" value="no"',
      ),
      _editForm().replaceFirst(
        '<input type="hidden" name="editsubmit" value="yes" />',
        '<input type="hidden" name="editsubmit" value="yes" />\n'
            '<input type="hidden" name="editsubmit" value="yes" />',
      ),
      _editForm().replaceFirst(
        '<button id="postsubmit">保存</button>',
        '<button id="postsubmit" name="editsubmit" value="yes">保存</button>',
      ),
      _editForm().replaceFirst(
        '<button id="postsubmit">保存</button>',
        '<input type="text" name="editsubmit" value="yes" />',
      ),
    ]) {
      expect(
        () => parser.parse(
          source,
          _entry,
          expectedUserId: 42,
          request: _request,
        ),
        throwsA(isA<ForumException>()),
      );
    }
  });

  test('编辑要求唯一 multipart postform、可空标题与必填正文结构', () {
    for (final String source in <String>[
      _editForm().replaceFirst('enctype="multipart/form-data"', ''),
      _editForm().replaceFirst('method="post"', 'method="get"'),
      _editForm().replaceFirst(
        '</body>',
        '<form id="postform" method="post"></form></body>',
      ),
      _editForm().replaceFirst(
        '<input type="text" name="subject" value="原主题" />',
        '',
      ),
      _editForm().replaceFirst(
        'type="text" name="subject"',
        'type="text" required name="subject"',
      ),
      _editForm().replaceFirst(
        '<textarea name="message">原正文</textarea>',
        '<input type="text" name="message" value="原正文" />',
      ),
      _editForm().replaceFirst(
        '<textarea name="message">原正文</textarea>',
        '',
      ),
    ]) {
      expect(
        () => parser.parse(
          source,
          _entry,
          expectedUserId: 42,
          request: _request,
        ),
        throwsA(isA<ForumException>()),
      );
    }
  });

  test('删除仍未注册为可执行标准表单操作', () {
    final ForumActionRequest deleteRequest = ForumActionRequest(
      kind: ForumActionKind.deletePost,
      target: _request.target,
      entryUri: _entry,
      readbackUri: _readback,
    );

    expect(
      () => contract.validateEntry(deleteRequest, deleteRequest.entryUri),
      throwsA(isA<ForumParseException>()),
    );
  });
}

Uri _replaceEntry(Map<String, String> replacement) {
  return _entry.replace(
    queryParameters: <String, String>{
      ..._entry.queryParameters,
      ...replacement,
    },
  );
}

final Uri _entry = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=edit&fid=30&tid=101&pid=202&page=2&mobile=2',
);
final Uri _action = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=edit&editsubmit=yes&extra=&mobile=2',
);
final Uri _readback = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=redirect&goto=findpost&pid=202&ptid=101&mobile=2',
);
final ForumActionRequest _request = ForumActionRequest(
  kind: ForumActionKind.editPost,
  target: const ForumActionTarget(boardId: 30, threadId: 101, postId: 202),
  entryUri: _entry,
  readbackUri: _readback,
);

String _editForm({String? action}) {
  return '''
    <html><body id="forum" class="pg_post">
      <script>var discuz_uid = '42';</script>
      <form id="postform" method="post" enctype="multipart/form-data"
        action="${action ?? 'forum.php?mod=post&amp;action=edit&amp;editsubmit=yes&amp;extra=&amp;mobile=2'}">
        <input type="hidden" name="formhash" value="memory-only" />
        <input type="hidden" name="posttime" value="1" />
        <input type="hidden" name="fid" value="30" />
        <input type="hidden" name="tid" value="101" />
        <input type="hidden" name="pid" value="202" />
        <input type="hidden" name="page" value="2" />
        <input type="text" name="subject" value="原主题" />
        <textarea name="message">原正文</textarea>
        <input id="filedata" type="file" name="Filedata" multiple />
        <input id="attfiledata" type="file" name="Filedata" multiple />
        <input type="checkbox" name="usesig" value="1" checked />
        <input type="hidden" name="editsubmit" value="yes" />
        <button id="postsubmit">保存</button>
      </form>
    </body></html>
  ''';
}
