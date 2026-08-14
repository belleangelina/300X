import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';
import 'package:x300/features/community/domain/community_models.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/library/data/forum_parse_utils.dart';

class CommunityParser {
  const CommunityParser({
    this.originPolicy = const ForumOriginPolicy(),
    this.authParser = const AuthPageParser(),
  });

  final ForumOriginPolicy originPolicy;
  final AuthPageParser authParser;

  CommunityNoticePage parseNotices(
    String html,
    Uri pageUri, {
    required int expectedViewerUserId,
  }) {
    final dom.Document document = _shell(html, pageUri, expectedViewerUserId);
    _requireSpaceRoute(pageUri, doValue: 'notice');
    final dom.Element? container = document.querySelector('#notice_ul');
    if (container == null) {
      throw const ForumParseException('通知页缺少通知列表');
    }
    final List<CommunityNotice> items = <CommunityNotice>[];
    final Map<String, CommunityNoticeCategory> categories =
        <String, CommunityNoticeCategory>{};
    int fallbackId = 0;
    for (final dom.Element row in container.querySelectorAll('li')) {
      final String title = _text(row.querySelector('.mtit'));
      final String message = _text(row.querySelector('.mbody'));
      if (title.isEmpty && message.isEmpty) {
        continue;
      }
      final String categoryKey = _noticeCategory(row, pageUri);
      final CommunityNoticeCategory category = categories.putIfAbsent(
        categoryKey,
        () => CommunityNoticeCategory(
          key: categoryKey,
          label: _noticeCategoryLabel(categoryKey),
        ),
      );
      final dom.Element? time = row.querySelector(
        '.mbody .xg1, .mbody .mtime, .mtime, time',
      );
      final CommunityTopicTarget? topic = _topicTargetIn(row, pageUri);
      final CommunityProfileTarget? profile = _profileTargetIn(row, pageUri);
      final int parsedId =
          int.tryParse(
            RegExp(r'(\d+)')
                    .firstMatch(row.querySelector('[id^="a_note_"]')?.id ?? '')
                    ?.group(1) ??
                '',
          ) ??
          0;
      items.add(
        CommunityNotice(
          id: parsedId > 0 ? parsedId : --fallbackId,
          category: category,
          title: title,
          message: message,
          timeLabel: _text(time),
          unread: _isUnread(row),
          avatarUri: _imageUri(row, pageUri),
          topicTarget: topic,
          profileTarget: topic == null ? profile : null,
        ),
      );
    }
    return CommunityNoticePage(
      items: List<CommunityNotice>.unmodifiable(items),
      categories: List<CommunityNoticeCategory>.unmodifiable(categories.values),
      cursor: _cursor(
        document,
        pageUri,
        (Uri value) => _isSpaceRoute(value, doValue: 'notice'),
      ),
      navigation: _sectionLinks(document, pageUri),
    );
  }

  CommunityPmListPage parsePmList(
    String html,
    Uri pageUri, {
    required int expectedViewerUserId,
  }) {
    final dom.Document document = _shell(html, pageUri, expectedViewerUserId);
    _requireSpaceRoute(pageUri, doValue: 'pm');
    if (_single(pageUri, 'subop') != null) {
      throw const ForumParseException('私信列表地址无效');
    }
    final dom.Element? container = document.querySelector('#pmlist');
    if (container == null) {
      throw const ForumParseException('私信页缺少会话列表');
    }
    final List<CommunityPmConversation> items = <CommunityPmConversation>[];
    for (final dom.Element row in container.querySelectorAll('li')) {
      Uri? conversationUri;
      for (final dom.Element anchor in row.querySelectorAll('a[href]')) {
        final Uri? candidate = _resolveMobile(
          pageUri,
          anchor.attributes['href'],
        );
        if (candidate != null && _isPmThreadRoute(candidate)) {
          conversationUri = candidate;
          break;
        }
      }
      final int peerUserId = _positive(
        conversationUri == null ? null : _single(conversationUri, 'touid'),
      );
      if (conversationUri == null || peerUserId <= 0) {
        continue;
      }
      final dom.Element? titleElement = row.querySelector('.mtit');
      final dom.Element? timeElement = row.querySelector(
        '.mtit .mtime, .mtime, time',
      );
      final String time = _text(timeElement);
      String username = _text(titleElement);
      if (time.isNotEmpty && username.endsWith(time)) {
        username = username.substring(0, username.length - time.length).trim();
      }
      if (username.isEmpty) {
        throw const ForumParseException('私信会话缺少对方名称');
      }
      items.add(
        CommunityPmConversation(
          peerUserId: peerUserId,
          peerUsername: username,
          preview: _text(row.querySelector('.mtxt')),
          timeLabel: time,
          uri: conversationUri,
          avatarUri: _imageUri(row, pageUri),
          unread: _isUnread(row),
        ),
      );
    }
    if (container.querySelectorAll('li').isNotEmpty && items.isEmpty) {
      throw const ForumParseException('私信会话列表结构无法识别');
    }
    return CommunityPmListPage(
      items: List<CommunityPmConversation>.unmodifiable(items),
      cursor: _cursor(document, pageUri, (Uri value) => _isPmListRoute(value)),
      navigation: _sectionLinks(document, pageUri),
      composeUri: _pmComposeUri(document, pageUri),
    );
  }

  CommunityPmThreadPage parsePmThread(
    String html,
    Uri pageUri, {
    required int expectedViewerUserId,
    required int expectedPeerUserId,
  }) {
    final dom.Document document = _shell(html, pageUri, expectedViewerUserId);
    if (!_isPmThreadRoute(pageUri) ||
        _positive(_single(pageUri, 'touid')) != expectedPeerUserId) {
      throw const ForumParseException('私信会话地址与对方账号不一致');
    }
    final dom.Element? box = document.querySelector('.msgbox');
    if (box == null) {
      throw const ForumParseException('私信会话页缺少消息区域');
    }
    final List<CommunityPmMessage> messages = <CommunityPmMessage>[];
    for (final dom.Element row in box.querySelectorAll(
      '.friend_msg, .self_msg',
    )) {
      final String message = _text(row.querySelector('.dialog_c'));
      if (message.isEmpty) {
        continue;
      }
      messages.add(
        CommunityPmMessage(
          message: message,
          timeLabel: _text(row.querySelector('.date, time')),
          sentByViewer: row.classes.contains('self_msg'),
          avatarUri: _imageUri(row, pageUri),
        ),
      );
    }
    if (box.querySelectorAll('.friend_msg, .self_msg').isNotEmpty &&
        messages.isEmpty) {
      throw const ForumParseException('私信消息结构无法识别');
    }
    return CommunityPmThreadPage(
      peerUserId: expectedPeerUserId,
      messages: List<CommunityPmMessage>.unmodifiable(messages),
      cursor: _cursor(
        document,
        pageUri,
        (Uri value) =>
            _isPmThreadRoute(value) &&
            _positive(_single(value, 'touid')) == expectedPeerUserId,
      ),
      hasSendCapability: _hasPmSendCapability(
        document,
        pageUri,
        expectedPeerUserId,
      ),
    );
  }

  CommunityPmFormContract? parsePmFormContract(
    String html,
    Uri pageUri, {
    required int expectedViewerUserId,
    required String context,
  }) {
    final dom.Document document = _authenticatedDocument(
      html,
      pageUri,
      expectedViewerUserId,
    );
    final bool validContext = switch (context) {
      'compose' =>
        pageUri.path == '/home.php' &&
            _single(pageUri, 'mod') == 'spacecp' &&
            _single(pageUri, 'ac') == 'pm' &&
            document.body?.id == 'home' &&
            document.body?.classes.contains('pg_spacecp') == true,
      'conversation' =>
        _isPmThreadRoute(pageUri) &&
            document.body?.id == 'home' &&
            document.body?.classes.contains('pg_space') == true,
      _ => false,
    };
    if (!validContext) {
      throw const ForumParseException('私信表单上下文无效');
    }
    dom.Element? form;
    for (final dom.Element candidate in document.querySelectorAll('form')) {
      if (candidate.querySelector('[name="message"]') != null &&
          candidate.querySelector('[name="formhash"]') != null) {
        form = candidate;
        break;
      }
    }
    if (form == null) {
      return null;
    }
    final String method = (form.attributes['method'] ?? 'get').toLowerCase();
    final Uri? action = originPolicy.resolveMobile(
      pageUri,
      form.attributes['action'],
    );
    if (method != 'post' ||
        action == null ||
        action.path != '/home.php' ||
        _single(action, 'mod') != 'spacecp' ||
        _single(action, 'ac') != 'pm' ||
        _single(action, 'op') != 'send') {
      return null;
    }
    final List<String> actionQueryKeys =
        action.queryParameters.keys
            .where((String value) => value.toLowerCase() != 'formhash')
            .toList(growable: false)
          ..sort();
    final List<String> fieldNames =
        form
            .querySelectorAll('[name]')
            .map((dom.Element value) => value.attributes['name'] ?? '')
            .where(
              (String value) =>
                  value.isNotEmpty && value.toLowerCase() != 'formhash',
            )
            .toSet()
            .toList(growable: false)
          ..sort();
    return CommunityPmFormContract(
      context: context,
      method: method,
      actionPath: action.path,
      actionQueryKeys: List<String>.unmodifiable(actionQueryKeys),
      fieldNames: List<String>.unmodifiable(fieldNames),
      hasFormhash: form.querySelector('[name="formhash"]') != null,
    );
  }

  CommunityProfile parseProfile(
    String html,
    Uri pageUri, {
    required int expectedViewerUserId,
    required int expectedProfileUserId,
  }) {
    final dom.Document document = _shell(html, pageUri, expectedViewerUserId);
    if (!_isProfileRoute(pageUri) ||
        _positive(_single(pageUri, 'uid')) != expectedProfileUserId) {
      throw const ForumParseException('个人空间地址与目标账号不一致');
    }
    final dom.Element? container = document.querySelector('.userinfo');
    if (container == null) {
      throw const ForumParseException('个人空间结构无法识别');
    }
    final String username = _text(container.querySelector('h2.name'));
    if (username.isEmpty) {
      throw const ForumParseException('个人空间缺少用户名');
    }
    final List<CommunityProfileEntry> entries = <CommunityProfileEntry>[];
    for (final dom.Element anchor in container.querySelectorAll(
      '.myinfo_list_ico a[href]',
    )) {
      final Uri? uri = originPolicy.resolveAllowed(
        pageUri,
        anchor.attributes['href'],
      );
      if (uri == null || uri.queryParameters['mobile'] != '2') {
        continue;
      }
      final CommunityProfileEntryKind kind = _profileEntryKind(
        uri,
        expectedProfileUserId,
      );
      final String label = _text(anchor).isEmpty
          ? _profileEntryLabel(kind)
          : _text(anchor);
      entries.add(CommunityProfileEntry(label: label, uri: uri, kind: kind));
    }
    if (entries.isEmpty && expectedProfileUserId == expectedViewerUserId) {
      throw const ForumParseException('个人空间缺少功能入口');
    }
    final List<String> details = <String>[
      for (final dom.Element value in container.querySelectorAll(
        '.user_box, .myinfo_list li',
      ))
        if (_text(value).isNotEmpty) _text(value),
    ];
    return CommunityProfile(
      userId: expectedProfileUserId,
      username: username,
      avatarUri: _imageUri(
        container.querySelector('.avatar_m') ?? container,
        pageUri,
      ),
      sourceUri: pageUri,
      entries: List<CommunityProfileEntry>.unmodifiable(entries),
      details: List<String>.unmodifiable(details),
    );
  }

  CommunityActivityPage parseActivity(
    String html,
    Uri pageUri, {
    required int expectedViewerUserId,
    required int expectedProfileUserId,
    required CommunityActivityKind expectedKind,
  }) {
    final dom.Document document = _shell(html, pageUri, expectedViewerUserId);
    if (!_isActivityRoute(pageUri, expectedProfileUserId, expectedKind)) {
      throw const ForumParseException('主题或回复列表地址与目标不一致');
    }
    final dom.Element? container = document.querySelector('.threadlist');
    if (container == null) {
      throw const ForumParseException('主题或回复列表结构无法识别');
    }
    final List<CommunityActivityItem> items = <CommunityActivityItem>[];
    for (final dom.Element row in container.querySelectorAll('li.list')) {
      final CommunityTopicTarget? target = _topicTargetIn(row, pageUri);
      if (target == null) {
        continue;
      }
      final String title = _text(row.querySelector('.threadlist_tit'));
      if (title.isEmpty) {
        continue;
      }
      final List<int> counts = <int>[
        for (final dom.Element value in row.querySelectorAll(
          '.threadlist_foot li',
        ))
          if (_firstInteger(_text(value)) != null) _firstInteger(_text(value))!,
      ];
      items.add(
        CommunityActivityItem(
          title: title,
          summary: _text(row.querySelector('.threadlist_mes, .quote')),
          timeLabel: _text(row.querySelector('.mtime, time')),
          author: _text(row.querySelector('.muser h3, .muser .mmc')),
          avatarUri: _imageUri(row, pageUri),
          views: counts.isEmpty ? 0 : counts.first,
          replies: counts.length < 2 ? 0 : counts.last,
          target: target,
        ),
      );
    }
    if (container.querySelectorAll('li.list').isNotEmpty && items.isEmpty) {
      throw const ForumParseException('主题或回复列表行结构无法识别');
    }
    return CommunityActivityPage(
      kind: expectedKind,
      profileUserId: expectedProfileUserId,
      items: List<CommunityActivityItem>.unmodifiable(items),
      cursor: _cursor(
        document,
        pageUri,
        (Uri value) =>
            _isActivityRoute(value, expectedProfileUserId, expectedKind),
      ),
      tabs: _activityTabs(document, pageUri, expectedProfileUserId),
    );
  }

  CommunityPeoplePage parsePeople(
    String html,
    Uri pageUri, {
    required int expectedViewerUserId,
    required CommunityPeopleKind expectedKind,
  }) {
    final dom.Document document = _shell(html, pageUri, expectedViewerUserId);
    if (!_isPeopleRoute(pageUri, expectedKind, expectedViewerUserId)) {
      throw const ForumParseException('好友或访客列表地址与类型不一致');
    }
    if (document.querySelector('.dhnv') == null) {
      throw const ForumParseException('好友或访客页缺少分类入口');
    }
    final dom.Element? container = document.querySelector('#friend_ul');
    final List<CommunityPerson> people = <CommunityPerson>[];
    for (final dom.Element row
        in container?.querySelectorAll('li') ?? const <dom.Element>[]) {
      final CommunityProfileTarget? profile = _profileTargetIn(row, pageUri);
      if (profile == null) {
        continue;
      }
      Uri? conversationUri;
      for (final dom.Element anchor in row.querySelectorAll('a[href]')) {
        final Uri? candidate = _resolveMobile(
          pageUri,
          anchor.attributes['href'],
        );
        if (candidate != null &&
            _isPmThreadRoute(candidate) &&
            _positive(_single(candidate, 'touid')) == profile.userId) {
          conversationUri = candidate;
          break;
        }
      }
      final dom.Element? description = row.querySelector('.mtxt');
      final dom.Element? time = description?.querySelector(
        '.mtime, .xg1, time',
      );
      people.add(
        CommunityPerson(
          profile: CommunityProfileTarget(
            userId: profile.userId,
            username: profile.username,
            uri: profile.uri,
            avatarUri: _imageUri(row, pageUri) ?? profile.avatarUri,
          ),
          description: _text(description),
          timeLabel: _text(time),
          conversationUri: conversationUri,
        ),
      );
    }
    if (container != null &&
        container.querySelectorAll('li').isNotEmpty &&
        people.isEmpty) {
      throw const ForumParseException('好友或访客列表行结构无法识别');
    }
    return CommunityPeoplePage(
      kind: expectedKind,
      people: List<CommunityPerson>.unmodifiable(people),
      tabs: _peopleTabs(document, pageUri, expectedViewerUserId),
      cursor: _cursor(
        document,
        pageUri,
        (Uri value) =>
            _isPeopleRoute(value, expectedKind, expectedViewerUserId),
      ),
    );
  }

  dom.Document _shell(String html, Uri pageUri, int expectedViewerUserId) {
    final dom.Document document = _authenticatedDocument(
      html,
      pageUri,
      expectedViewerUserId,
    );
    if (document.body?.id != 'home' ||
        document.body?.classes.contains('pg_space') != true) {
      throw const ForumParseException('论坛未返回移动社区页');
    }
    return document;
  }

  dom.Document _authenticatedDocument(
    String html,
    Uri pageUri,
    int expectedViewerUserId,
  ) {
    originPolicy.requireMobilePage(pageUri);
    final dom.Document document = html_parser.parse(html);
    if (document.querySelector('form#loginform') != null ||
        document.body?.classes.contains('pg_logging') == true) {
      throw const ForumSessionExpiredException();
    }
    if (authParser.currentUserId(html) != expectedViewerUserId ||
        expectedViewerUserId <= 0) {
      throw const ForumSessionExpiredException();
    }
    return document;
  }

  void _requireSpaceRoute(Uri uri, {required String doValue}) {
    if (!_isSpaceRoute(uri, doValue: doValue)) {
      throw const ForumParseException('移动社区页地址无效');
    }
  }

  bool _isSpaceRoute(Uri uri, {required String doValue}) {
    return _baseSpaceRoute(uri) && _single(uri, 'do') == doValue;
  }

  bool _baseSpaceRoute(Uri uri) {
    return originPolicy.isAllowed(uri) &&
        uri.path == '/home.php' &&
        uri.fragment.isEmpty &&
        _single(uri, 'mod') == 'space' &&
        _single(uri, 'mobile') == '2';
  }

  bool _isPmListRoute(Uri uri) {
    return _isSpaceRoute(uri, doValue: 'pm') && _single(uri, 'subop') == null;
  }

  bool _isPmThreadRoute(Uri uri) {
    return _isSpaceRoute(uri, doValue: 'pm') &&
        _single(uri, 'subop') == 'view' &&
        _positive(_single(uri, 'touid')) > 0;
  }

  bool _isProfileRoute(Uri uri) {
    if (!_baseSpaceRoute(uri) || _positive(_single(uri, 'uid')) <= 0) {
      return false;
    }
    final String? value = _single(uri, 'do');
    return value == null || value == 'profile';
  }

  bool _isActivityRoute(
    Uri uri,
    int profileUserId,
    CommunityActivityKind kind,
  ) {
    if (!_isSpaceRoute(uri, doValue: 'thread') ||
        _positive(_single(uri, 'uid')) != profileUserId ||
        _single(uri, 'view') != 'me') {
      return false;
    }
    final String? type = _single(uri, 'type');
    return kind == CommunityActivityKind.replies
        ? type == 'reply'
        : type == null || type.isEmpty;
  }

  bool _isPeopleRoute(Uri uri, CommunityPeopleKind kind, int viewerUserId) {
    if (!_isSpaceRoute(uri, doValue: 'friend')) {
      return false;
    }
    final int uid = _positive(_single(uri, 'uid'));
    if (uid > 0 && uid != viewerUserId) {
      return false;
    }
    return switch (kind) {
      CommunityPeopleKind.friends =>
        _single(uri, 'view') == null && _single(uri, 'type') == null,
      CommunityPeopleKind.online =>
        _single(uri, 'view') == 'online' && _single(uri, 'type') == 'member',
      CommunityPeopleKind.visitors => _single(uri, 'view') == 'visitor',
      CommunityPeopleKind.visited => _single(uri, 'view') == 'trace',
    };
  }

  CommunityTopicTarget? _topicTargetIn(dom.Element root, Uri pageUri) {
    for (final dom.Element anchor in root.querySelectorAll('a[href]')) {
      final Uri? uri = _resolveMobile(pageUri, anchor.attributes['href']);
      if (uri == null || uri.path != '/forum.php') {
        continue;
      }
      final String? mod = _single(uri, 'mod');
      final int threadId = mod == 'redirect'
          ? _positive(_single(uri, 'ptid'))
          : _positive(_single(uri, 'tid'));
      final int postId = _positive(_single(uri, 'pid'));
      final bool valid =
          (mod == 'viewthread' && threadId > 0) ||
          (mod == 'redirect' &&
              _single(uri, 'goto') == 'findpost' &&
              threadId > 0 &&
              postId > 0);
      if (!valid) {
        continue;
      }
      int boardId = 0;
      for (final dom.Element boardAnchor in root.querySelectorAll(
        'a[href*="mod=forumdisplay"][href*="fid="]',
      )) {
        final Uri? boardUri = _resolveMobile(
          pageUri,
          boardAnchor.attributes['href'],
        );
        if (boardUri?.path == '/forum.php' &&
            _single(boardUri!, 'mod') == 'forumdisplay') {
          boardId = _positive(_single(boardUri, 'fid'));
          break;
        }
      }
      return CommunityTopicTarget(
        threadId: threadId,
        postId: postId > 0 ? postId : null,
        boardId: boardId,
        title: _text(root.querySelector('.threadlist_tit, .mtit')),
        uri: uri,
      );
    }
    return null;
  }

  CommunityProfileTarget? _profileTargetIn(dom.Element root, Uri pageUri) {
    for (final dom.Element anchor in root.querySelectorAll(
      'a[href*="mod=space"][href*="uid="]',
    )) {
      final Uri? uri = _resolveMobile(pageUri, anchor.attributes['href']);
      final int userId = uri == null ? 0 : _positive(_single(uri, 'uid'));
      if (uri == null || !_isProfileRoute(uri) || userId <= 0) {
        continue;
      }
      String username = _text(anchor);
      if (username.isEmpty) {
        username = _text(root.querySelector('.mtit'));
      }
      return CommunityProfileTarget(
        userId: userId,
        username: username,
        uri: uri,
        avatarUri: _imageUri(root, pageUri),
      );
    }
    return null;
  }

  CommunityProfileEntryKind _profileEntryKind(Uri uri, int profileUserId) {
    if (_isActivityRoute(uri, profileUserId, CommunityActivityKind.replies)) {
      return CommunityProfileEntryKind.replies;
    }
    if (_isActivityRoute(uri, profileUserId, CommunityActivityKind.topics)) {
      return CommunityProfileEntryKind.topics;
    }
    if (_isPmListRoute(uri)) {
      return CommunityProfileEntryKind.messages;
    }
    if (_isPeopleRoute(uri, CommunityPeopleKind.friends, profileUserId)) {
      return CommunityProfileEntryKind.friends;
    }
    if (_isSpaceRoute(uri, doValue: 'favorite')) {
      return CommunityProfileEntryKind.favorites;
    }
    return CommunityProfileEntryKind.unknown;
  }

  String _profileEntryLabel(CommunityProfileEntryKind kind) {
    return switch (kind) {
      CommunityProfileEntryKind.topics => '主题',
      CommunityProfileEntryKind.replies => '回复',
      CommunityProfileEntryKind.messages => '私信',
      CommunityProfileEntryKind.friends => '好友',
      CommunityProfileEntryKind.favorites => '收藏',
      CommunityProfileEntryKind.unknown => '暂不支持的入口',
    };
  }

  List<CommunityProfileEntry> _activityTabs(
    dom.Document document,
    Uri pageUri,
    int profileUserId,
  ) {
    final List<CommunityProfileEntry> result = <CommunityProfileEntry>[];
    final Set<CommunityProfileEntryKind> seen = <CommunityProfileEntryKind>{};
    for (final dom.Element anchor in document.querySelectorAll(
      '.dhnv a[href]',
    )) {
      final Uri? uri = _resolveMobile(pageUri, anchor.attributes['href']);
      if (uri == null) {
        continue;
      }
      final CommunityProfileEntryKind kind = _profileEntryKind(
        uri,
        profileUserId,
      );
      if ((kind != CommunityProfileEntryKind.topics &&
              kind != CommunityProfileEntryKind.replies) ||
          !seen.add(kind)) {
        continue;
      }
      result.add(
        CommunityProfileEntry(
          label: _text(anchor).isEmpty
              ? _profileEntryLabel(kind)
              : _text(anchor),
          uri: uri,
          kind: kind,
        ),
      );
    }
    if (result.length < 2) {
      throw const ForumParseException('主题与回复页缺少动态分类入口');
    }
    return List<CommunityProfileEntry>.unmodifiable(result);
  }

  List<CommunityPeopleTab> _peopleTabs(
    dom.Document document,
    Uri pageUri,
    int viewerUserId,
  ) {
    final List<CommunityPeopleTab> result = <CommunityPeopleTab>[];
    final Set<CommunityPeopleKind> seen = <CommunityPeopleKind>{};
    for (final dom.Element anchor in document.querySelectorAll(
      '.dhnv a[href]',
    )) {
      final Uri? uri = _resolveMobile(pageUri, anchor.attributes['href']);
      if (uri == null) {
        continue;
      }
      CommunityPeopleKind? kind;
      for (final CommunityPeopleKind candidate in CommunityPeopleKind.values) {
        if (_isPeopleRoute(uri, candidate, viewerUserId)) {
          kind = candidate;
          break;
        }
      }
      if (kind == null || !seen.add(kind)) {
        continue;
      }
      result.add(
        CommunityPeopleTab(
          kind: kind,
          label: _text(anchor).isEmpty ? _peopleLabel(kind) : _text(anchor),
          uri: uri,
          selected:
              anchor.classes.contains('mon') || _sameSemanticUri(uri, pageUri),
        ),
      );
    }
    if (result.length < 4) {
      throw const ForumParseException('好友与访客页缺少完整分类入口');
    }
    return List<CommunityPeopleTab>.unmodifiable(result);
  }

  List<CommunitySectionLink> _sectionLinks(dom.Document document, Uri pageUri) {
    final List<CommunitySectionLink> result = <CommunitySectionLink>[];
    final Set<CommunitySectionKind> seen = <CommunitySectionKind>{};
    for (final dom.Element anchor in document.querySelectorAll(
      '.dhnv a[href], .foot a[href]',
    )) {
      final Uri? uri = _resolveMobile(pageUri, anchor.attributes['href']);
      if (uri == null) {
        continue;
      }
      final CommunitySectionKind? kind = switch (_single(uri, 'do')) {
        'notice' when _isSpaceRoute(uri, doValue: 'notice') =>
          CommunitySectionKind.notices,
        'pm' when _isPmListRoute(uri) => CommunitySectionKind.messages,
        'profile' when _isProfileRoute(uri) => CommunitySectionKind.profile,
        _ => null,
      };
      if (kind == null || !seen.add(kind)) {
        continue;
      }
      result.add(
        CommunitySectionLink(
          kind: kind,
          label: _text(anchor).isEmpty ? _sectionLabel(kind) : _text(anchor),
          uri: uri,
          selected: _sameSemanticUri(uri, pageUri),
        ),
      );
    }
    return List<CommunitySectionLink>.unmodifiable(result);
  }

  String _sectionLabel(CommunitySectionKind kind) {
    return switch (kind) {
      CommunitySectionKind.notices => '通知',
      CommunitySectionKind.messages => '私信',
      CommunitySectionKind.profile => '个人资料',
    };
  }

  String _peopleLabel(CommunityPeopleKind kind) {
    return switch (kind) {
      CommunityPeopleKind.friends => '好友',
      CommunityPeopleKind.online => '在线会员',
      CommunityPeopleKind.visitors => '访客',
      CommunityPeopleKind.visited => '访问过的人',
    };
  }

  String _noticeCategory(dom.Element row, Uri pageUri) {
    for (final dom.Element anchor in row.querySelectorAll('a[href]')) {
      final Uri? uri = originPolicy.resolveAllowed(
        pageUri,
        anchor.attributes['href'],
      );
      final String type = uri?.queryParameters['type'] ?? '';
      if (type.isNotEmpty) {
        return type;
      }
    }
    return _topicTargetIn(row, pageUri) == null ? 'system' : 'post';
  }

  String _noticeCategoryLabel(String key) {
    return switch (key) {
      'system' => '系统',
      'post' || 'mypost' => '帖子',
      'rate' => '评分',
      'friend' => '互动',
      _ => '其他',
    };
  }

  bool _hasPmSendCapability(
    dom.Document document,
    Uri pageUri,
    int peerUserId,
  ) {
    final List<dom.Element> forms = document.querySelectorAll('form#pmform');
    if (forms.length != 1) {
      return false;
    }
    final dom.Element form = forms.single;
    if (
        (form.attributes['method'] ?? 'get').toLowerCase() != 'post') {
      return false;
    }
    final Uri? action = originPolicy.resolveMobile(
      pageUri,
      form.attributes['action'],
    );
    if (action == null ||
        action.path != '/home.php' ||
        _single(action, 'mod') != 'spacecp' ||
        _single(action, 'ac') != 'pm' ||
        _single(action, 'op') != 'send' ||
        _single(action, 'pmsubmit') != 'yes' ||
        _positive(_single(action, 'pmid')) <= 0) {
      return false;
    }
    const Set<String> actionKeys = <String>{
      'mod',
      'ac',
      'op',
      'pmid',
      'pmsubmit',
      'daterange',
      'mobile',
    };
    final Set<String> actualActionKeys = action.queryParametersAll.keys.toSet();
    if (actualActionKeys.length != actionKeys.length ||
        !actualActionKeys.containsAll(actionKeys) ||
        actionKeys.any(
          (String name) =>
              (action.queryParametersAll[name] ?? const <String>[]).length != 1,
        )) {
      return false;
    }
    final Set<String> names = form
        .querySelectorAll('[name]')
        .map((dom.Element value) => value.attributes['name'] ?? '')
        .where((String value) => value.isNotEmpty)
        .toSet();
    if (!names.containsAll(const <String>{
          'formhash',
          'touid',
          'message',
          'pmsubmit',
        }) ||
        names.difference(const <String>{
          'formhash',
          'touid',
          'message',
          'pmsubmit',
        }).isNotEmpty ||
        form.querySelectorAll('[name="formhash"]').length != 1 ||
        form.querySelectorAll('[name="touid"]').length != 1 ||
        form.querySelectorAll('[name="message"]').length != 1 ||
        form.querySelectorAll('[name="pmsubmit"]').length != 1 ||
        form.querySelector('[name="pmsubmit"]')?.attributes['value']
                ?.trim()
                .isEmpty !=
            false) {
      return false;
    }
    const Map<String, String> expectedTypes = <String, String>{
      'formhash': 'hidden',
      'message': 'text',
      'pmsubmit': 'button',
      'touid': 'hidden',
    };
    for (final dom.Element control in form.querySelectorAll('[name]')) {
      final String name = control.attributes['name'] ?? '';
      final String type = control.localName == 'textarea'
          ? 'textarea'
          : control.localName == 'button'
          ? 'button'
          : (control.attributes['type'] ?? 'text').toLowerCase();
      if (expectedTypes[name] != type) {
        return false;
      }
    }
    final String formhash =
        form.querySelector('[name="formhash"]')?.attributes['value'] ?? '';
    final int target = _positive(
      form.querySelector('[name="touid"]')?.attributes['value'],
    );
    return formhash.isNotEmpty &&
        target == peerUserId &&
        form.querySelector('[name="message"]') != null;
  }

  Uri? _pmComposeUri(dom.Document document, Uri pageUri) {
    Uri? result;
    for (final dom.Element anchor in document.querySelectorAll('a[href]')) {
      final Uri? uri = _resolveMobile(pageUri, anchor.attributes['href']);
      if (uri == null ||
          uri.path != '/home.php' ||
          _single(uri, 'mod') != 'spacecp' ||
          _single(uri, 'ac') != 'pm' ||
          _single(uri, 'mobile') != '2' ||
          uri.queryParameters.keys.toSet().difference(const <String>{
            'mod',
            'ac',
            'mobile',
          }).isNotEmpty) {
        continue;
      }
      if (result != null && result != uri) {
        return null;
      }
      result = uri;
    }
    return result;
  }

  CommunityPageCursor _cursor(
    dom.Document document,
    Uri pageUri,
    bool Function(Uri value) accepts,
  ) {
    final dom.Element? page = document.querySelector('.pg, #dumppage');
    int currentPage = _positive(_single(pageUri, 'page'));
    if (currentPage <= 0) {
      currentPage = _positive(
        page?.querySelector('input[name="custompage"]')?.attributes['value'],
      );
    }
    currentPage = currentPage <= 0 ? 1 : currentPage;
    int totalPages = currentPage;
    final String title =
        page?.querySelector('label span')?.attributes['title'] ?? '';
    totalPages = _firstInteger(title) ?? totalPages;
    for (final dom.Element anchor
        in page?.querySelectorAll('a[href]') ?? const <dom.Element>[]) {
      final Uri? uri = _resolveMobile(pageUri, anchor.attributes['href']);
      if (uri != null && accepts(uri)) {
        final int value = _positive(_single(uri, 'page'));
        if (value > totalPages) {
          totalPages = value;
        }
      }
    }
    return CommunityPageCursor(
      sourceUri: pageUri,
      currentPage: currentPage,
      totalPages: totalPages,
      previousPageUri: _pageUri(
        page?.querySelector('a.prev[href]'),
        pageUri,
        accepts,
      ),
      nextPageUri: _pageUri(
        page?.querySelector('a.nxt[href]'),
        pageUri,
        accepts,
      ),
    );
  }

  Uri? _pageUri(
    dom.Element? anchor,
    Uri pageUri,
    bool Function(Uri value) accepts,
  ) {
    final Uri? uri = _resolveMobile(pageUri, anchor?.attributes['href']);
    return uri != null && accepts(uri) ? uri : null;
  }

  Uri? _resolveMobile(Uri pageUri, String? value) {
    final Uri? uri = originPolicy.resolveMobile(pageUri, value);
    return uri?.fragment.isEmpty == true ? uri : null;
  }

  Uri? _imageUri(dom.Element root, Uri pageUri) {
    final String? source = root.querySelector('img[src]')?.attributes['src'];
    if (source == null) {
      return null;
    }
    final Uri? uri = originPolicy.resolveAllowed(pageUri, source);
    return uri?.scheme == 'https' ? uri : null;
  }

  bool _isUnread(dom.Element element) {
    bool hasMarker(dom.Element value) {
      return value.classes.any(
            (String item) => const <String>{
              'new',
              'unread',
              'newpm',
              'newnotice',
            }.contains(item.toLowerCase()),
          ) ||
          value.attributes['data-unread'] == '1';
    }

    return hasMarker(element) || element.querySelectorAll('*').any(hasMarker);
  }

  bool _sameSemanticUri(Uri first, Uri second) {
    return first.path == second.path &&
        first.queryParameters['mod'] == second.queryParameters['mod'] &&
        first.queryParameters['do'] == second.queryParameters['do'] &&
        first.queryParameters['view'] == second.queryParameters['view'] &&
        first.queryParameters['type'] == second.queryParameters['type'];
  }

  String? _single(Uri uri, String name) {
    final List<String> values =
        uri.queryParametersAll[name] ?? const <String>[];
    return values.length == 1 ? values.single : null;
  }

  int _positive(String? value) {
    final int result = int.tryParse(value ?? '') ?? 0;
    return result > 0 ? result : 0;
  }

  int? _firstInteger(String value) {
    return int.tryParse(RegExp(r'\d+').firstMatch(value)?.group(0) ?? '');
  }

  String _text(dom.Element? element) {
    return normalizeForumText(element?.text ?? '');
  }
}
