import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/community/domain/community_models.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';

class CommunityCacheCodec {
  const CommunityCacheCodec({this.originPolicy = const ForumOriginPolicy()});

  final ForumOriginPolicy originPolicy;

  Map<String, dynamic> encodeNotices(CommunityNoticePage value) {
    return <String, dynamic>{
      'items': <Map<String, dynamic>>[
        for (final CommunityNotice item in value.items)
          <String, dynamic>{
            'id': item.id,
            'categoryKey': item.category.key,
            'categoryLabel': item.category.label,
            'title': item.title,
            'message': item.message,
            'timeLabel': item.timeLabel,
            'unread': item.unread,
            'avatarUri': item.avatarUri == null
                ? null
                : _encodeAllowedUri(item.avatarUri!),
            'topic': _encodeTopic(item.topicTarget),
            'profile': _encodeProfileTarget(item.profileTarget),
          },
      ],
      'categories': <Map<String, dynamic>>[
        for (final CommunityNoticeCategory item in value.categories)
          <String, dynamic>{'key': item.key, 'label': item.label},
      ],
      'navigation': _encodeNavigation(value.navigation),
      'cursor': _encodeCursor(value.cursor),
    };
  }

  CommunityNoticePage decodeNotices(Map<String, dynamic> value) {
    final List<CommunityNoticeCategory> categories = _maps(value['categories'])
        .map(
          (Map<String, dynamic> item) => CommunityNoticeCategory(
            key: _string(item['key']),
            label: _string(item['label']),
          ),
        )
        .toList(growable: false);
    return CommunityNoticePage(
      items: _maps(value['items'])
          .map((Map<String, dynamic> item) {
            final String categoryKey = _string(item['categoryKey']);
            final CommunityNoticeCategory category =
                categories
                    .where(
                      (CommunityNoticeCategory value) =>
                          value.key == categoryKey,
                    )
                    .firstOrNull ??
                CommunityNoticeCategory(
                  key: categoryKey,
                  label: _string(item['categoryLabel']),
                );
            return CommunityNotice(
              id: _integer(item['id']),
              category: category,
              title: _string(item['title']),
              message: _string(item['message']),
              timeLabel: _string(item['timeLabel']),
              unread: item['unread'] == true,
              avatarUri: _optionalAllowedUri(item['avatarUri']),
              topicTarget: _decodeTopic(item['topic']),
              profileTarget: _decodeProfileTarget(item['profile']),
            );
          })
          .toList(growable: false),
      categories: categories,
      navigation: _decodeNavigation(value['navigation']),
      cursor: _decodeCursor(value['cursor']),
    );
  }

  Map<String, dynamic> encodePmList(CommunityPmListPage value) {
    return <String, dynamic>{
      'items': <Map<String, dynamic>>[
        for (final CommunityPmConversation item in value.items)
          <String, dynamic>{
            'peerUserId': item.peerUserId,
            'peerUsername': item.peerUsername,
            'avatarUri': item.avatarUri == null
                ? null
                : _encodeAllowedUri(item.avatarUri!),
            'timeLabel': item.timeLabel,
            'uri': _encodeMobileUri(item.uri),
            'unread': item.unread,
          },
      ],
      'navigation': _encodeNavigation(value.navigation),
      'cursor': _encodeCursor(value.cursor),
    };
  }

  CommunityPmListPage decodePmList(Map<String, dynamic> value) {
    return CommunityPmListPage(
      items: _maps(value['items'])
          .map(
            (Map<String, dynamic> item) => CommunityPmConversation(
              peerUserId: _integer(item['peerUserId']),
              peerUsername: _string(item['peerUsername']),
              avatarUri: _optionalAllowedUri(item['avatarUri']),
              preview: '',
              timeLabel: _string(item['timeLabel']),
              uri: _mobileUri(item['uri']),
              unread: item['unread'] == true,
            ),
          )
          .toList(growable: false),
      navigation: _decodeNavigation(value['navigation']),
      cursor: _decodeCursor(value['cursor']),
    );
  }

  Map<String, dynamic> encodeProfile(CommunityProfile value) {
    return <String, dynamic>{
      'userId': value.userId,
      'username': value.username,
      'avatarUri': value.avatarUri == null
          ? null
          : _encodeAllowedUri(value.avatarUri!),
      'sourceUri': _encodeMobileUri(value.sourceUri),
      'entries': <Map<String, dynamic>>[
        for (final CommunityProfileEntry item in value.entries)
          <String, dynamic>{
            'label': item.label,
            'uri': _encodeMobileUri(item.uri),
            'kind': item.kind.name,
          },
      ],
      'details': value.details,
    };
  }

  CommunityProfile decodeProfile(Map<String, dynamic> value) {
    return CommunityProfile(
      userId: _integer(value['userId']),
      username: _string(value['username']),
      avatarUri: _optionalAllowedUri(value['avatarUri']),
      sourceUri: _mobileUri(value['sourceUri']),
      entries: _maps(value['entries'])
          .map(
            (Map<String, dynamic> item) => CommunityProfileEntry(
              label: _string(item['label']),
              uri: _mobileUri(item['uri']),
              kind: _enumByName(CommunityProfileEntryKind.values, item['kind']),
            ),
          )
          .toList(growable: false),
      details: _strings(value['details']),
    );
  }

  Map<String, dynamic> encodeActivity(CommunityActivityPage value) {
    return <String, dynamic>{
      'kind': value.kind.name,
      'profileUserId': value.profileUserId,
      'items': <Map<String, dynamic>>[
        for (final CommunityActivityItem item in value.items)
          <String, dynamic>{
            'title': item.title,
            'timeLabel': item.timeLabel,
            'author': item.author,
            'avatarUri': item.avatarUri == null
                ? null
                : _encodeAllowedUri(item.avatarUri!),
            'views': item.views,
            'replies': item.replies,
            'target': _encodeTopic(item.target),
          },
      ],
      'tabs': <Map<String, dynamic>>[
        for (final CommunityProfileEntry item in value.tabs)
          <String, dynamic>{
            'label': item.label,
            'uri': _encodeMobileUri(item.uri),
            'kind': item.kind.name,
          },
      ],
      'cursor': _encodeCursor(value.cursor),
    };
  }

  CommunityActivityPage decodeActivity(Map<String, dynamic> value) {
    return CommunityActivityPage(
      kind: _enumByName(CommunityActivityKind.values, value['kind']),
      profileUserId: _integer(value['profileUserId']),
      items: _maps(value['items'])
          .map(
            (Map<String, dynamic> item) => CommunityActivityItem(
              title: _string(item['title']),
              summary: '',
              timeLabel: _string(item['timeLabel']),
              author: _string(item['author']),
              avatarUri: _optionalAllowedUri(item['avatarUri']),
              views: _integer(item['views']),
              replies: _integer(item['replies']),
              target:
                  _decodeTopic(item['target']) ??
                  (throw const ForumParseException('社区缓存缺少主题目标')),
            ),
          )
          .toList(growable: false),
      cursor: _decodeCursor(value['cursor']),
      tabs: _maps(value['tabs'])
          .map(
            (Map<String, dynamic> item) => CommunityProfileEntry(
              label: _string(item['label']),
              uri: _mobileUri(item['uri']),
              kind: _enumByName(CommunityProfileEntryKind.values, item['kind']),
            ),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> encodePeople(CommunityPeoplePage value) {
    return <String, dynamic>{
      'kind': value.kind.name,
      'people': <Map<String, dynamic>>[
        for (final CommunityPerson item in value.people)
          <String, dynamic>{
            'profile': _encodeProfileTarget(item.profile),
            'description': item.description,
            'timeLabel': item.timeLabel,
            'conversationUri': item.conversationUri == null
                ? null
                : _encodeMobileUri(item.conversationUri!),
          },
      ],
      'tabs': <Map<String, dynamic>>[
        for (final CommunityPeopleTab item in value.tabs)
          <String, dynamic>{
            'kind': item.kind.name,
            'label': item.label,
            'uri': _encodeMobileUri(item.uri),
            'selected': item.selected,
          },
      ],
      'cursor': _encodeCursor(value.cursor),
    };
  }

  CommunityPeoplePage decodePeople(Map<String, dynamic> value) {
    return CommunityPeoplePage(
      kind: _enumByName(CommunityPeopleKind.values, value['kind']),
      people: _maps(value['people'])
          .map(
            (Map<String, dynamic> item) => CommunityPerson(
              profile:
                  _decodeProfileTarget(item['profile']) ??
                  (throw const ForumParseException('社区缓存缺少用户目标')),
              description: _string(item['description']),
              timeLabel: _string(item['timeLabel']),
              conversationUri: _optionalMobileUri(item['conversationUri']),
            ),
          )
          .toList(growable: false),
      tabs: _maps(value['tabs'])
          .map(
            (Map<String, dynamic> item) => CommunityPeopleTab(
              kind: _enumByName(CommunityPeopleKind.values, item['kind']),
              label: _string(item['label']),
              uri: _mobileUri(item['uri']),
              selected: item['selected'] == true,
            ),
          )
          .toList(growable: false),
      cursor: _decodeCursor(value['cursor']),
    );
  }

  Map<String, dynamic> _encodeCursor(CommunityPageCursor value) {
    return <String, dynamic>{
      'sourceUri': _encodeMobileUri(value.sourceUri),
      'currentPage': value.currentPage,
      'totalPages': value.totalPages,
      'previousPageUri': value.previousPageUri == null
          ? null
          : _encodeMobileUri(value.previousPageUri!),
      'nextPageUri': value.nextPageUri == null
          ? null
          : _encodeMobileUri(value.nextPageUri!),
    };
  }

  List<Map<String, dynamic>> _encodeNavigation(
    List<CommunitySectionLink> value,
  ) {
    return <Map<String, dynamic>>[
      for (final CommunitySectionLink item in value)
        <String, dynamic>{
          'kind': item.kind.name,
          'label': item.label,
          'uri': _encodeMobileUri(item.uri),
          'selected': item.selected,
        },
    ];
  }

  List<CommunitySectionLink> _decodeNavigation(Object? value) {
    if (value == null) {
      return const <CommunitySectionLink>[];
    }
    return _maps(value)
        .map(
          (Map<String, dynamic> item) => CommunitySectionLink(
            kind: _enumByName(CommunitySectionKind.values, item['kind']),
            label: _string(item['label']),
            uri: _mobileUri(item['uri']),
            selected: item['selected'] == true,
          ),
        )
        .toList(growable: false);
  }

  CommunityPageCursor _decodeCursor(Object? value) {
    final Map<String, dynamic> map = _map(value);
    return CommunityPageCursor(
      sourceUri: _mobileUri(map['sourceUri']),
      currentPage: _integer(map['currentPage']),
      totalPages: _integer(map['totalPages']),
      previousPageUri: _optionalMobileUri(map['previousPageUri']),
      nextPageUri: _optionalMobileUri(map['nextPageUri']),
    );
  }

  Map<String, dynamic>? _encodeTopic(CommunityTopicTarget? value) {
    if (value == null) {
      return null;
    }
    return <String, dynamic>{
      'threadId': value.threadId,
      'postId': value.postId,
      'boardId': value.boardId,
      'title': value.title,
      'uri': _encodeMobileUri(value.uri),
    };
  }

  CommunityTopicTarget? _decodeTopic(Object? value) {
    if (value == null) {
      return null;
    }
    final Map<String, dynamic> map = _map(value);
    return CommunityTopicTarget(
      threadId: _integer(map['threadId']),
      postId: _optionalInteger(map['postId']),
      boardId: _integer(map['boardId']),
      title: _string(map['title']),
      uri: _mobileUri(map['uri']),
    );
  }

  Map<String, dynamic>? _encodeProfileTarget(CommunityProfileTarget? value) {
    if (value == null) {
      return null;
    }
    return <String, dynamic>{
      'userId': value.userId,
      'username': value.username,
      'uri': _encodeMobileUri(value.uri),
      'avatarUri': value.avatarUri == null
          ? null
          : _encodeAllowedUri(value.avatarUri!),
    };
  }

  CommunityProfileTarget? _decodeProfileTarget(Object? value) {
    if (value == null) {
      return null;
    }
    final Map<String, dynamic> map = _map(value);
    return CommunityProfileTarget(
      userId: _integer(map['userId']),
      username: _string(map['username']),
      uri: _mobileUri(map['uri']),
      avatarUri: _optionalAllowedUri(map['avatarUri']),
    );
  }

  Uri _mobileUri(Object? value) {
    final Uri uri = Uri.parse(_string(value));
    originPolicy.requireMobilePage(uri);
    return uri;
  }

  String _encodeMobileUri(Uri value) {
    originPolicy.requireMobilePage(value);
    return _withoutSensitiveParts(value).toString();
  }

  String _encodeAllowedUri(Uri value) {
    originPolicy.ensureAllowed(value);
    if (value.scheme != 'https') {
      throw const ForumParseException('社区缓存图片地址无效');
    }
    return _withoutSensitiveParts(value).toString();
  }

  Uri _withoutSensitiveParts(Uri value) {
    final Map<String, List<String>> query = <String, List<String>>{
      for (final MapEntry<String, List<String>> entry
          in value.queryParametersAll.entries)
        if (!_sensitiveQueryKeys.contains(entry.key.toLowerCase()))
          entry.key: entry.value,
    };
    return value.replace(queryParameters: query, fragment: '');
  }

  static const Set<String> _sensitiveQueryKeys = <String>{
    'formhash',
    'auth',
    'authkey',
    'token',
    'access_token',
    'refresh_token',
    'password',
    'passwd',
    'cookie',
    'credential',
    'session',
    'sessionid',
    'sid',
    'signature',
    'secret',
    'ticket',
  };

  Uri? _optionalMobileUri(Object? value) {
    final String raw = _string(value);
    return raw.isEmpty ? null : _mobileUri(raw);
  }

  Uri? _optionalAllowedUri(Object? value) {
    final String raw = _string(value);
    if (raw.isEmpty) {
      return null;
    }
    final Uri uri = Uri.parse(raw);
    originPolicy.ensureAllowed(uri);
    if (uri.scheme != 'https') {
      throw const ForumParseException('社区缓存图片地址无效');
    }
    return uri;
  }

  T _enumByName<T extends Enum>(List<T> values, Object? value) {
    final String name = _string(value);
    return values.where((T item) => item.name == name).firstOrNull ??
        (throw const ForumParseException('社区缓存枚举值无效'));
  }

  List<Map<String, dynamic>> _maps(Object? value) {
    if (value is! List) {
      throw const ForumParseException('社区缓存列表无效');
    }
    return value.map(_map).toList(growable: false);
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const ForumParseException('社区缓存对象无效');
    }
    return value.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
  }

  List<String> _strings(Object? value) {
    if (value is! List) {
      throw const ForumParseException('社区缓存文本列表无效');
    }
    return value.map(_string).toList(growable: false);
  }

  String _string(Object? value) => value?.toString() ?? '';

  int _integer(Object? value) {
    return value is int ? value : int.tryParse(_string(value)) ?? 0;
  }

  int? _optionalInteger(Object? value) {
    final int result = _integer(value);
    return result > 0 ? result : null;
  }
}
