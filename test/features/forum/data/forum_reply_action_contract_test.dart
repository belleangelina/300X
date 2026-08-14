import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/forum/data/dynamic_forum_form_parser.dart';
import 'package:x300/features/forum/data/forum_action_contract.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

void main() {
  const DynamicForumFormParser parser = DynamicForumFormParser();
  const ForumActionContract contract = ForumActionContract();

  test('真实移动普通回复与引用回复表单按楼层目标解析', () {
    expect(
      ForumActionContract.verifiedKinds,
      containsAll(<ForumActionKind>[
        ForumActionKind.reply,
        ForumActionKind.quoteReply,
      ]),
    );

    for (final (ForumActionRequest request, String source) in <
        (ForumActionRequest, String)
      >[
      (_replyRequest, _replyForm()),
      (_quoteRequest, _quoteForm()),
    ]) {
      final DynamicForumForm form = parser.parse(
        source,
        request.entryUri,
        expectedUserId: 42,
        request: request,
      );

      expect(form.hiddenFields['reppid'], <String>['202']);
      expect(form.hiddenFields['reppost'], <String>['202']);
      expect(form.submitFields['replysubmit'], <String>['yes']);
      expect(form.fieldByName('message')?.isRequired, isTrue);
      expect(
        form.fields.where((DynamicForumField field) => field.name == 'Filedata'),
        hasLength(1),
      );
      expect(form.attachmentFields, hasLength(2));
      expect(form.attachmentUploadVerified, isFalse);
    }
  });

  test('回复入口必须精确绑定版块、主题、页码和当前响应楼层', () {
    for (final ForumActionRequest request in <ForumActionRequest>[
      _withEntry(_replyRequest, _replyEntry.replace(queryParameters: <String, String>{
        'mod': 'post', 'action': 'reply', 'fid': '30', 'tid': '101',
        'page': '2', 'mobile': '2',
      })),
      _withEntry(_replyRequest, _replyEntry.replace(queryParameters: <String, String>{
        ..._replyEntry.queryParameters, 'reppost': '999',
      })),
      _withEntry(_replyRequest, _replyEntry.replace(queryParameters: <String, String>{
        ..._replyEntry.queryParameters, 'page': '0',
      })),
      _withEntry(_replyRequest, Uri.parse('$_replyEntry&extra=page%3D2')),
      _withEntry(_quoteRequest, _quoteEntry.replace(queryParameters: <String, String>{
        ..._quoteEntry.queryParameters, 'repquote': '999',
      })),
      _withEntry(_quoteRequest, _quoteEntry.replace(queryParameters: <String, String>{
        ..._quoteEntry.queryParameters, 'extra': 'page=3',
      })),
      _withEntry(_quoteRequest, _quoteEntry.replace(queryParameters: <String, String>{
        'mod': 'post', 'action': 'reply', 'fid': '30', 'tid': '101',
        'page': '2', 'repquote': '202', 'mobile': '2',
      })),
      _withEntry(_quoteRequest, Uri.parse('$_quoteEntry&reppost=202')),
    ]) {
      expect(
        () => parser.parse(
          _replyForm(),
          request.entryUri,
          expectedUserId: 42,
          request: request,
        ),
        throwsA(isA<ForumException>()),
        reason: request.entryUri.toString(),
      );
    }
  });

  test('回复 POST 地址和隐藏楼层目标漂移时 fail closed', () {
    for (final (ForumActionRequest request, String source) in <
        (ForumActionRequest, String)
      >[
      (_replyRequest, _replyForm().replaceFirst('name="reppid" value="202"', 'name="reppid" value="999"')),
      (_replyRequest, _replyForm().replaceFirst('<input type="hidden" name="reppost" value="202" />', '')),
      (_replyRequest, _replyForm().replaceFirst('name="reppost" value="202"', 'name="repquote" value="202"')),
      (_replyRequest, _replyForm().replaceFirst('<button id="postsubmit">回复</button>', '<button id="postsubmit" name="replysubmit" value="evil">回复</button>')),
      (_replyRequest, _replyForm().replaceFirst('name="replysubmit" value="yes"', 'name="replysubmit" value="evil"')),
      (_replyRequest, _replyForm(action: 'forum.php?mod=post&amp;action=reply&amp;fid=30&amp;tid=101&amp;replysubmit=yes&amp;extra=page%3D2&amp;mobile=2')),
      (_quoteRequest, _quoteForm(action: 'forum.php?mod=post&amp;action=reply&amp;fid=30&amp;tid=101&amp;replysubmit=yes&amp;extra=&amp;mobile=2')),
      (_quoteRequest, _quoteForm(action: 'forum.php?mod=post&amp;action=reply&amp;fid=30&amp;tid=101&amp;replysubmit=yes&amp;extra=page%3D3&amp;mobile=2')),
      (_quoteRequest, _quoteForm(action: 'forum.php?mod=post&amp;action=reply&amp;fid=30&amp;tid=101&amp;replysubmit=yes&amp;extra=page%3D2&amp;pid=202&amp;mobile=2')),
    ]) {
      expect(
        () => parser.parse(
          source,
          request.entryUri,
          expectedUserId: 42,
          request: request,
        ),
        throwsA(isA<ForumException>()),
        reason: request.kind.name,
      );
    }
  });

  test('GET 最终回复页不能改变原入口页码或传输楼层', () {
    for (final (ForumActionRequest request, Uri finalUri) in <
        (ForumActionRequest, Uri)
      >[
      (
        _replyRequest,
        _replyEntry.replace(queryParameters: <String, String>{
          ..._replyEntry.queryParameters,
          'reppost': '999',
        }),
      ),
      (
        _replyRequest,
        _replyEntry.replace(queryParameters: <String, String>{
          ..._replyEntry.queryParameters,
          'page': '3',
        }),
      ),
      (
        _quoteRequest,
        _quoteEntry.replace(queryParameters: <String, String>{
          ..._quoteEntry.queryParameters,
          'page': '3',
          'extra': 'page=3',
        }),
      ),
    ]) {
      expect(
        () => contract.validateEntry(request, finalUri),
        throwsA(isA<ForumException>()),
      );
    }
  });

  test('回复逻辑目标不能夹带会分裂封存键的无关标识', () {
    for (final ForumActionRequest request in <ForumActionRequest>[
      ForumActionRequest(
        kind: ForumActionKind.reply,
        target: const ForumActionTarget(
          boardId: 30,
          threadId: 101,
          postId: 202,
        ),
        entryUri: _replyEntry,
        readbackUri: _readback,
      ),
      ForumActionRequest(
        kind: ForumActionKind.reply,
        target: const ForumActionTarget(
          boardId: 30,
          threadId: 101,
          favoriteId: 9,
        ),
        entryUri: _replyEntry,
        readbackUri: _readback,
      ),
      ForumActionRequest(
        kind: ForumActionKind.quoteReply,
        target: const ForumActionTarget(
          boardId: 30,
          threadId: 101,
          postId: 202,
          favoriteId: 9,
        ),
        entryUri: _quoteEntry,
        readbackUri: _readback,
      ),
    ]) {
      expect(
        () => contract.validateEntry(request, request.entryUri),
        throwsA(isA<ForumException>()),
      );
    }
  });
}

ForumActionRequest _withEntry(ForumActionRequest source, Uri entryUri) {
  return ForumActionRequest(
    kind: source.kind,
    target: source.target,
    entryUri: entryUri,
    readbackUri: source.readbackUri,
  );
}

final Uri _replyEntry = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=30&tid=101&page=2&reppost=202&mobile=2',
);
final Uri _quoteEntry = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=post&action=reply&fid=30&tid=101&page=2&repquote=202&extra=page%3D2&mobile=2',
);
final Uri _readback = Uri.parse(
  'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=101&mobile=2',
);
final ForumActionRequest _replyRequest = ForumActionRequest(
  kind: ForumActionKind.reply,
  target: const ForumActionTarget(boardId: 30, threadId: 101),
  entryUri: _replyEntry,
  readbackUri: _readback,
);
final ForumActionRequest _quoteRequest = ForumActionRequest(
  kind: ForumActionKind.quoteReply,
  target: const ForumActionTarget(boardId: 30, threadId: 101, postId: 202),
  entryUri: _quoteEntry,
  readbackUri: _readback,
);

String _replyForm({String? action}) {
  return _form(
    action: action ??
        'forum.php?mod=post&amp;action=reply&amp;fid=30&amp;tid=101&amp;replysubmit=yes&amp;extra=&amp;mobile=2',
  );
}

String _quoteForm({String? action}) {
  return _form(
    action: action ??
        'forum.php?mod=post&amp;action=reply&amp;fid=30&amp;tid=101&amp;replysubmit=yes&amp;extra=page%3D2&amp;mobile=2',
  );
}

String _form({required String action}) {
  return '''
    <html><body id="forum" class="pg_post">
      <script>var discuz_uid = '42';</script>
      <form id="postform" method="post" action="$action">
        <input type="hidden" name="formhash" value="memory-only" />
        <input type="hidden" name="posttime" value="1" />
        <input type="hidden" name="noticeauthor" value="" />
        <input type="hidden" name="reppid" value="202" />
        <input type="hidden" name="reppost" value="202" />
        <textarea id="needmessage" name="message"></textarea>
        <input id="filedata" type="file" name="Filedata" multiple accept="image/*" />
        <input id="attfiledata" type="file" name="Filedata" multiple />
        <input type="checkbox" name="usesig" value="1" checked />
        <input type="hidden" name="replysubmit" value="yes" />
        <button id="postsubmit">回复</button>
      </form>
    </body></html>
  ''';
}
