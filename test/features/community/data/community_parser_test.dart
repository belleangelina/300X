import 'package:flutter_test/flutter_test.dart';
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/community/data/community_parser.dart';
import 'package:x300/features/community/domain/community_models.dart';

void main() {
  const CommunityParser parser = CommunityParser();

  group('CommunityParser', () {
    test('解析通知分类、未读与精确楼层跳转', () {
      final CommunityNoticePage page = parser.parseNotices(
        _noticesHtml,
        _uri('home.php?mod=space&do=notice&mobile=2'),
        expectedViewerUserId: 42,
      );

      expect(page.readEffect, CommunityReadEffect.marksNoticeListRead);
      expect(page.items, hasLength(2));
      expect(page.items.first.category.key, 'rate');
      expect(page.items.first.unread, isTrue);
      expect(page.items.first.topicTarget?.threadId, 120);
      expect(page.items.first.topicTarget?.postId, 321);
      expect(page.items.first.profileTarget, isNull);
      expect(page.items.last.canOpen, isFalse);
      expect(page.cursor.nextPageUri?.queryParameters['page'], '2');
      expect(
        page.navigation.map((CommunitySectionLink value) => value.kind),
        <CommunitySectionKind>[
          CommunitySectionKind.messages,
          CommunitySectionKind.notices,
        ],
      );
    });

    test('解析私信会话列表与会话只读消息', () {
      final CommunityPmListPage list = parser.parsePmList(
        _pmListHtml,
        _uri('home.php?mod=space&do=pm&mobile=2'),
        expectedViewerUserId: 42,
      );
      expect(list.items.single.peerUserId, 77);
      expect(list.items.single.peerUsername, '用户A');
      expect(list.items.single.unread, isTrue);
      expect(
        list.composeUri,
        _uri('home.php?mod=spacecp&ac=pm&mobile=2'),
      );

      final CommunityPmThreadPage thread = parser.parsePmThread(
        _pmThreadHtml,
        _uri('home.php?mod=space&do=pm&subop=view&touid=77&mobile=2'),
        expectedViewerUserId: 42,
        expectedPeerUserId: 77,
      );
      expect(thread.readEffect, CommunityReadEffect.marksConversationRead);
      expect(thread.messages, hasLength(2));
      expect(thread.messages.first.sentByViewer, isFalse);
      expect(thread.messages.last.sentByViewer, isTrue);
      expect(thread.hasSendCapability, isTrue);
      final CommunityPmFormContract? contract = parser.parsePmFormContract(
        _pmThreadHtml,
        _uri('home.php?mod=space&do=pm&subop=view&touid=77&mobile=2'),
        expectedViewerUserId: 42,
        context: 'conversation',
      );
      expect(contract?.method, 'post');
      expect(contract?.actionPath, '/home.php');
      expect(contract?.actionQueryKeys, <String>[
        'ac',
        'daterange',
        'mobile',
        'mod',
        'op',
        'pmid',
        'pmsubmit',
      ]);
      expect(contract?.fieldNames, <String>['message', 'pmsubmit', 'touid']);
      expect(contract?.hasFormhash, isTrue);

      final CommunityPmFormContract? compose = parser.parsePmFormContract(
        _pmComposeHtml,
        _uri('home.php?mod=spacecp&ac=pm&mobile=2'),
        expectedViewerUserId: 42,
        context: 'compose',
      );
      expect(compose?.actionQueryKeys, <String>[
        'ac',
        'mobile',
        'mod',
        'op',
        'pmid',
        'touid',
      ]);
      expect(compose?.fieldNames, <String>[
        'message',
        'pmsubmit',
        'referer',
        'username',
      ]);
    });

    test('解析个人空间动态入口并保留未知禁用项', () {
      final CommunityProfile profile = parser.parseProfile(
        _profileHtml,
        _uri('home.php?mod=space&do=profile&mycenter=1&uid=42&mobile=2'),
        expectedViewerUserId: 42,
        expectedProfileUserId: 42,
      );

      expect(profile.username, '用户B');
      expect(
        profile.entries.map((CommunityProfileEntry value) => value.kind),
        containsAll(<CommunityProfileEntryKind>[
          CommunityProfileEntryKind.topics,
          CommunityProfileEntryKind.messages,
          CommunityProfileEntryKind.friends,
          CommunityProfileEntryKind.unknown,
        ]),
      );
      expect(profile.entries.last.supported, isFalse);
    });

    test('解析本人主题、回复及分页', () {
      final CommunityActivityPage topics = parser.parseActivity(
        _topicsHtml,
        _uri('home.php?mod=space&do=thread&view=me&uid=42&mobile=2'),
        expectedViewerUserId: 42,
        expectedProfileUserId: 42,
        expectedKind: CommunityActivityKind.topics,
      );
      expect(topics.items.single.target.threadId, 120);
      expect(topics.items.single.target.boardId, 16);
      expect(topics.tabs, hasLength(2));

      final CommunityActivityPage replies = parser.parseActivity(
        _repliesHtml,
        _uri('home.php?mod=space&do=thread&view=me&uid=42&type=reply&mobile=2'),
        expectedViewerUserId: 42,
        expectedProfileUserId: 42,
        expectedKind: CommunityActivityKind.replies,
      );
      expect(replies.items.single.target.threadId, 120);
      expect(replies.items.single.target.postId, 321);
      expect(replies.cursor.nextPageUri?.queryParameters['page'], '2');
    });

    test('解析好友、在线、访客和访问记录入口', () {
      final CommunityPeoplePage page = parser.parsePeople(
        _peopleHtml,
        _uri('home.php?mod=space&do=friend&type=member&view=online&mobile=2'),
        expectedViewerUserId: 42,
        expectedKind: CommunityPeopleKind.online,
      );

      expect(
        page.tabs.map((CommunityPeopleTab value) => value.kind),
        CommunityPeopleKind.values,
      );
      expect(page.people.single.profile.userId, 77);
      expect(page.people.single.conversationUri, isNotNull);
      expect(page.cursor.nextPageUri?.queryParameters['uid'], '42');

      for (final (CommunityPeopleKind kind, String path) in <(
        CommunityPeopleKind,
        String
      )>[
        (
          CommunityPeopleKind.friends,
          'home.php?mod=space&do=friend&mobile=2',
        ),
        (
          CommunityPeopleKind.visitors,
          'home.php?mod=space&do=friend&view=visitor&mobile=2',
        ),
        (
          CommunityPeopleKind.visited,
          'home.php?mod=space&do=friend&view=trace&mobile=2',
        ),
      ]) {
        expect(
          parser
              .parsePeople(
                _peopleHtml,
                _uri(path),
                expectedViewerUserId: 42,
                expectedKind: kind,
              )
              .kind,
          kind,
        );
      }
    });

    test('允许好友列表空态但不将模板漂移伪装成空态', () {
      final CommunityPeoplePage empty = parser.parsePeople(
        _peopleEmptyHtml,
        _uri('home.php?mod=space&do=friend&mobile=2'),
        expectedViewerUserId: 42,
        expectedKind: CommunityPeopleKind.friends,
      );
      expect(empty.people, isEmpty);

      expect(
        () => parser.parsePmList(
          _shell('<div class="empty">empty</div>'),
          _uri('home.php?mod=space&do=pm&mobile=2'),
          expectedViewerUserId: 42,
        ),
        throwsA(isA<ForumException>()),
      );
    });

    test('私信写入能力只有完整匹配当前标准表单时才开启', () {
      final Uri uri = _uri(
        'home.php?mod=space&do=pm&subop=view&touid=77&mobile=2',
      );
      final CommunityPmThreadPage extraField = parser.parsePmThread(
        _pmThreadHtml.replaceFirst(
          '</form>',
          '<input name="subject" value="x"></form>',
        ),
        uri,
        expectedViewerUserId: 42,
        expectedPeerUserId: 77,
      );
      final CommunityPmThreadPage wrongTarget = parser.parsePmThread(
        _pmThreadHtml.replaceFirst('value="77"', 'value="88"'),
        uri,
        expectedViewerUserId: 42,
        expectedPeerUserId: 77,
      );

      expect(extraField.hasSendCapability, isFalse);
      expect(wrongTarget.hasSendCapability, isFalse);
    });

    test('拒绝登录失效、错 uid、跨域、桌面和错分类页', () {
      expect(
        () => parser.parseNotices(
          '<body class="pg_logging"><form id="loginform"></form></body>',
          _uri('home.php?mod=space&do=notice&mobile=2'),
          expectedViewerUserId: 42,
        ),
        throwsA(isA<ForumSessionExpiredException>()),
      );
      expect(
        () => parser.parsePmList(
          _pmListHtml.replaceFirst("discuz_uid='42'", "discuz_uid='7'"),
          _uri('home.php?mod=space&do=pm&mobile=2'),
          expectedViewerUserId: 42,
        ),
        throwsA(isA<ForumSessionExpiredException>()),
      );
      expect(
        () => parser.parseNotices(
          _noticesHtml,
          Uri.parse(
            'https://evil.example/home.php?mod=space&do=notice&mobile=2',
          ),
          expectedViewerUserId: 42,
        ),
        throwsA(isA<ForumException>()),
      );
      expect(
        () => parser.parseNotices(
          _noticesHtml,
          _uri('home.php?mod=space&do=notice'),
          expectedViewerUserId: 42,
        ),
        throwsA(isA<ForumParseException>()),
      );
      expect(
        () => parser.parsePeople(
          _peopleHtml,
          _uri('home.php?mod=space&do=friend&view=visitor&mobile=2'),
          expectedViewerUserId: 42,
          expectedKind: CommunityPeopleKind.online,
        ),
        throwsA(isA<ForumParseException>()),
      );
    });
  });
}

Uri _uri(String path) => Uri.parse('https://bbs.yamibo.com/$path');

String _shell(String body) {
  return '''
<!doctype html>
<html><body id="home" class="pg_space">
<script>var discuz_uid='42';</script>
$body
</body></html>
''';
}

final String _noticesHtml = _shell('''
$_communityNavigation
<div id="notice_ul" class="imglist">
  <ul>
    <li class="cl unread" data-unread="1">
      <span class="mimg"><a href="home.php?mod=space&amp;uid=77&amp;mobile=2"><img src="uc_server/avatar.php?uid=77" /></a></span>
      <p class="mtit"><a id="a_note_11">[已脱敏]评分通知</a></p>
      <p class="mbody"><a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=120&amp;pid=321&amp;mobile=2">[已脱敏]查看楼层</a><span class="xg1">[时间]</span></p>
      <a href="home.php?mod=spacecp&amp;ac=common&amp;op=ignore&amp;type=rate&amp;authorid=77&amp;mobile=2">[已脱敏]</a>
    </li>
    <li class="cl">
      <p class="mtit"><a id="a_note_12">[已脱敏]系统通知</a></p>
      <p class="mbody">[已脱敏]无可用跳转</p>
      <a href="home.php?mod=spacecp&amp;ac=common&amp;op=ignore&amp;type=system&amp;authorid=77&amp;mobile=2">[已脱敏]</a>
    </li>
  </ul>
</div>
<div class="pg"><strong>1</strong><a class="nxt" href="home.php?mod=space&amp;do=notice&amp;page=2&amp;mobile=2">下一页</a></div>
''');

final String _pmListHtml = _shell('''
$_communityNavigation
<a class="newpm" href="home.php?mod=spacecp&amp;ac=pm&amp;mobile=2">发送私信</a>
<div id="pmlist" class="imglist"><ul>
  <li class="newpm">
    <span class="mimg"><a href="home.php?mod=space&amp;do=pm&amp;subop=view&amp;touid=77&amp;mobile=2"><img src="uc_server/avatar.php?uid=77" /></a></span>
    <a href="home.php?mod=space&amp;do=pm&amp;subop=view&amp;touid=77&amp;mobile=2">
      <p class="mtit">用户A<span class="mtime">[时间]</span></p>
      <p class="mtxt">[已脱敏]会话预览</p>
    </a>
  </li>
</ul></div>
''');

const String _communityNavigation = '''
<div class="dhnv">
  <a href="home.php?mod=space&amp;do=pm&amp;mobile=2">私信</a>
  <a href="home.php?mod=space&amp;do=notice&amp;mobile=2">通知</a>
</div>
''';

final String _pmThreadHtml = _shell('''
<div class="msgbox">
  <div class="friend_msg cl"><div class="avat"><img src="uc_server/avatar.php?uid=77" /></div><div class="dialog_green"><div class="dialog_c">[已脱敏]收到的消息</div><div class="date">[时间]</div></div></div>
  <div class="self_msg cl"><div class="avat"><img src="uc_server/avatar.php?uid=42" /></div><div class="dialog_white"><div class="dialog_c">[已脱敏]发出的消息</div><div class="date">[时间]</div></div></div>
  <form id="pmform" method="post" action="home.php?mod=spacecp&amp;ac=pm&amp;op=send&amp;pmid=1&amp;pmsubmit=yes&amp;daterange=2&amp;mobile=2">
    <input type="hidden" name="formhash" value="[redacted]" />
    <input type="hidden" name="touid" value="77" />
    <input type="text" name="message" /><button name="pmsubmit" value="yes">发送</button>
  </form>
</div>
''');

const String _pmComposeHtml = '''
<!doctype html>
<html><body id="home" class="pg_spacecp">
<script>var discuz_uid='42';</script>
<form method="post" action="home.php?mod=spacecp&amp;ac=pm&amp;op=send&amp;pmid=0&amp;touid=77&amp;mobile=2">
  <input type="hidden" name="formhash" value="[redacted]" />
  <input name="username" /><input name="message" />
  <input name="referer" /><input name="pmsubmit" />
</form>
</body></html>
''';

final String _profileHtml = _shell('''
<div class="userinfo">
  <div class="user_avatar"><div class="avatar_m"><img src="uc_server/avatar.php?uid=42" /></div><h2 class="name">用户B</h2></div>
  <div class="user_box">[已脱敏]账号摘要</div>
  <div class="myinfo_list_ico"><ul>
    <li><a href="home.php?mod=space&amp;do=thread&amp;view=me&amp;uid=42&amp;mobile=2">主题</a></li>
    <li><a href="home.php?mod=space&amp;do=pm&amp;mobile=2">私信</a></li>
    <li><a href="home.php?mod=space&amp;do=friend&amp;mobile=2">好友</a></li>
    <li><a href="plugin.php?id=redacted:entry&amp;mobile=2">扩展入口</a></li>
  </ul></div>
  <div class="myinfo_list"><ul><li>[已脱敏]资料</li></ul></div>
</div>
''');

String get _activityTabs => '''
<div class="dhnv">
  <a href="home.php?mod=space&amp;do=thread&amp;view=me&amp;uid=42&amp;mobile=2">主题</a>
  <a href="home.php?mod=space&amp;do=thread&amp;view=me&amp;uid=42&amp;type=reply&amp;mobile=2">回复</a>
</div>
''';

final String _topicsHtml = _shell('''
$_activityTabs
<div class="threadlist"><ul><li class="list">
  <div class="threadlist_top"><a class="mimg"><img src="uc_server/avatar.php?uid=42" /></a><div class="muser"><h3>用户B</h3><span class="mtime">[时间]</span></div></div>
  <a href="forum.php?mod=viewthread&amp;tid=120&amp;mobile=2"><div class="threadlist_tit">[已脱敏]主题</div><div class="threadlist_mes">[已脱敏]摘要</div></a>
  <div class="threadlist_foot"><ul><li><a href="forum.php?mod=forumdisplay&amp;fid=16&amp;mobile=2">版块</a></li><li>10</li><li>2</li></ul></div>
</li></ul></div>
''');

final String _repliesHtml = _shell('''
$_activityTabs
<div class="threadlist"><ul><li class="list">
  <a class="mt10" href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=120&amp;pid=321&amp;mobile=2"><div class="threadlist_tit">[已脱敏]回复主题</div></a>
  <a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=120&amp;pid=321&amp;mobile=2"><div class="quote">[已脱敏]回复摘要</div></a>
</li></ul></div>
<div class="pg"><strong>1</strong><a class="nxt" href="home.php?mod=space&amp;do=thread&amp;view=me&amp;uid=42&amp;type=reply&amp;order=dateline&amp;page=2&amp;mobile=2">下一页</a></div>
''');

String get _peopleTabs => '''
<div class="dhnv">
  <a href="home.php?mod=space&amp;do=friend&amp;mobile=2">好友</a>
  <a href="home.php?mod=space&amp;do=friend&amp;type=member&amp;view=online&amp;mobile=2">在线</a>
  <a href="home.php?mod=space&amp;do=friend&amp;view=visitor&amp;mobile=2">访客</a>
  <a href="home.php?mod=space&amp;do=friend&amp;view=trace&amp;mobile=2">访问记录</a>
</div>
''';

final String _peopleHtml = _shell('''
$_peopleTabs
<div id="friend_ul" class="imglist"><ul><li>
  <span class="mimg"><a href="home.php?mod=space&amp;uid=77&amp;mobile=2"><img src="uc_server/avatar.php?uid=77" /></a></span>
  <p class="mtit"><a href="home.php?mod=space&amp;uid=77&amp;mobile=2">用户A</a></p>
  <p class="mtxt">[已脱敏]用户摘要 <span class="mtime">[时间]</span><a href="home.php?mod=space&amp;do=pm&amp;subop=view&amp;touid=77&amp;mobile=2">私信</a></p>
</li></ul></div>
<div class="pg"><a class="nxt" href="home.php?mod=space&amp;do=friend&amp;type=member&amp;view=online&amp;uid=42&amp;page=2&amp;mobile=2">下一页</a></div>
''');

final String _peopleEmptyHtml = _shell(_peopleTabs);
