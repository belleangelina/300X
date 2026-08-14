import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';
import 'package:x300/features/community/domain/community_pm_action_models.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';

class CommunityPmActionParser {
  const CommunityPmActionParser({
    this.originPolicy = const ForumOriginPolicy(),
    this.authParser = const AuthPageParser(),
  });

  final ForumOriginPolicy originPolicy;
  final AuthPageParser authParser;

  CommunityPmSendForm parse(
    String html,
    Uri pageUri, {
    required int expectedViewerUserId,
    required CommunityPmSendRequest request,
  }) {
    validateEntryUri(request, pageUri);
    originPolicy.requireMobilePage(pageUri);
    final dom.Document document = html_parser.parse(html);
    if (document.querySelector('form#loginform') != null ||
        document.body?.classes.contains('pg_logging') == true ||
        expectedViewerUserId <= 0 ||
        authParser.currentUserId(html) != expectedViewerUserId) {
      throw const ForumSessionExpiredException();
    }
    final bool validBody = switch (request.context) {
      CommunityPmSendContext.compose =>
        document.body?.id == 'home' &&
            document.body?.classes.contains('pg_spacecp') == true,
      CommunityPmSendContext.conversation =>
        document.body?.id == 'home' &&
            document.body?.classes.contains('pg_space') == true,
    };
    if (!validBody) {
      throw const ForumParseException('论坛未返回对应的移动私信表单页');
    }

    final List<dom.Element> candidates = request.context ==
            CommunityPmSendContext.conversation
        ? document.querySelectorAll('form#pmform')
        : document
            .querySelectorAll('form')
            .where(
              (dom.Element value) =>
                  value.querySelector('[name="message"]') != null &&
                  value.querySelector('[name="formhash"]') != null,
            )
            .toList(growable: false);
    if (candidates.length != 1) {
      throw const ForumParseException('移动私信页缺少唯一标准发送表单');
    }
    final dom.Element form = candidates.single;
    if ((form.attributes['method'] ?? 'get').toLowerCase() != 'post') {
      throw const ForumParseException('私信表单不是标准 POST 表单');
    }
    final Uri? actionUri = originPolicy.resolveMobile(
      pageUri,
      form.attributes['action'],
    );
    if (actionUri == null || actionUri.fragment.isNotEmpty) {
      throw const ForumParseException('私信表单提交地址无效');
    }
    final (int peerUserId, int privateMessageId) = _validateActionUri(
      request,
      actionUri,
    );

    final Set<String> expectedFields = switch (request.context) {
      CommunityPmSendContext.compose => const <String>{
        'formhash',
        'message',
        'pmsubmit',
        'referer',
        'username',
      },
      CommunityPmSendContext.conversation => const <String>{
        'formhash',
        'message',
        'pmsubmit',
        'touid',
      },
    };
    final List<dom.Element> controls = form.querySelectorAll('[name]');
    final Set<String> names = controls
        .map((dom.Element value) => value.attributes['name'] ?? '')
        .where((String value) => value.isNotEmpty)
        .toSet();
    if (names.length != controls.length ||
        names.length != expectedFields.length ||
        !names.containsAll(expectedFields)) {
      throw const ForumParseException('私信表单字段与已验证白名单不一致');
    }
    final Map<String, String> expectedTypes = switch (request.context) {
      CommunityPmSendContext.compose => const <String, String>{
        'formhash': 'hidden',
        'message': 'textarea',
        'pmsubmit': 'hidden',
        'referer': 'hidden',
        'username': 'text',
      },
      CommunityPmSendContext.conversation => const <String, String>{
        'formhash': 'hidden',
        'message': 'text',
        'pmsubmit': 'button',
        'touid': 'hidden',
      },
    };
    for (final dom.Element control in controls) {
      final String name = control.attributes['name'] ?? '';
      final String type = control.localName == 'textarea'
          ? 'textarea'
          : control.localName == 'button'
          ? 'button'
          : (control.attributes['type'] ?? 'text').toLowerCase();
      if (expectedTypes[name] != type) {
        throw const ForumParseException('私信表单包含未验证的控件类型');
      }
    }

    String valueOf(String name) {
      final dom.Element control = controls.singleWhere(
        (dom.Element value) => value.attributes['name'] == name,
      );
      return control.localName == 'textarea'
          ? control.text
          : control.attributes['value'] ?? '';
    }

    final String formHash = valueOf('formhash');
    final String pmSubmit = valueOf('pmsubmit');
    if (formHash.trim().isEmpty || pmSubmit.trim().isEmpty) {
      throw const ForumParseException('私信表单缺少一次性提交字段');
    }
    if (request.context == CommunityPmSendContext.compose) {
      final String referer = valueOf('referer').trim();
      if (referer.isNotEmpty) {
        final Uri? refererUri = originPolicy.resolveAllowed(pageUri, referer);
        if (refererUri == null || refererUri.fragment.isNotEmpty) {
          throw const ForumParseException('私信表单 referer 不安全');
        }
      }
    }
    if (request.context == CommunityPmSendContext.conversation) {
      final int hiddenPeer = int.tryParse(valueOf('touid')) ?? 0;
      if (hiddenPeer <= 0 || hiddenPeer != request.expectedPeerUserId) {
        throw const ForumParseException('私信表单 touid 与会话目标不一致');
      }
    }

    final Map<String, String> fixedFields = <String, String>{
      for (final String name in expectedFields)
        if (name != 'formhash' && name != 'message' && name != 'username')
          name: valueOf(name),
    };
    return CommunityPmSendForm(
      context: request.context,
      sourceUri: pageUri,
      actionUri: actionUri,
      viewerUserId: expectedViewerUserId,
      peerUserId: peerUserId,
      privateMessageId: privateMessageId,
      formHash: formHash,
      fixedFields: fixedFields,
      acceptsUsername: request.context == CommunityPmSendContext.compose,
      initialUsername: request.context == CommunityPmSendContext.compose
          ? valueOf('username')
          : request.expectedPeerUsername,
    );
  }

  void validateEntryUri(CommunityPmSendRequest request, Uri uri) {
    originPolicy.requireMobilePage(uri);
    if (uri.fragment.isNotEmpty) {
      throw const ForumParseException('私信表单入口地址无效');
    }
    final bool matched = switch (request.context) {
      CommunityPmSendContext.compose =>
        uri.path == '/home.php' &&
            _single(uri, 'mod') == 'spacecp' &&
            _single(uri, 'ac') == 'pm' &&
            _single(uri, 'mobile') == '2' &&
            _exactQueryKeys(uri, const <String>{'mod', 'ac', 'mobile'}) &&
            request.expectedPeerUserId == 0,
      CommunityPmSendContext.conversation =>
        uri.path == '/home.php' &&
            _single(uri, 'mod') == 'space' &&
            _single(uri, 'do') == 'pm' &&
            _single(uri, 'subop') == 'view' &&
            _single(uri, 'mobile') == '2' &&
            _positive(_single(uri, 'touid')) == request.expectedPeerUserId &&
            request.expectedPeerUserId > 0 &&
            _queryKeysWithin(
              uri,
              const <String>{
                'mod',
                'do',
                'subop',
                'touid',
                'page',
                'mobile',
              },
            ),
    };
    if (!matched ||
        (uri.queryParameters.containsKey('page') &&
            _positive(_single(uri, 'page')) <= 0)) {
      throw const ForumParseException('私信表单入口与目标不一致');
    }
  }

  (int, int) _validateActionUri(
    CommunityPmSendRequest request,
    Uri uri,
  ) {
    originPolicy.requireMobilePage(uri);
    if (uri.path != '/home.php' ||
        _single(uri, 'mod') != 'spacecp' ||
        _single(uri, 'ac') != 'pm' ||
        _single(uri, 'op') != 'send' ||
        _single(uri, 'mobile') != '2') {
      throw const ForumParseException('私信表单动作不在已验证范围内');
    }
    switch (request.context) {
      case CommunityPmSendContext.compose:
        if (!_exactQueryKeys(uri, const <String>{
              'mod',
              'ac',
              'op',
              'pmid',
              'touid',
              'mobile',
            })) {
          throw const ForumParseException('新私信动作参数不在白名单内');
        }
        final int? pmid = int.tryParse(_single(uri, 'pmid') ?? '');
        final int? touid = int.tryParse(_single(uri, 'touid') ?? '');
        if (pmid == null ||
            pmid < 0 ||
            touid == null ||
            touid != request.expectedPeerUserId) {
          throw const ForumParseException('新私信动作目标无效');
        }
        return (touid, pmid);
      case CommunityPmSendContext.conversation:
        if (!_exactQueryKeys(uri, const <String>{
              'mod',
              'ac',
              'op',
              'pmid',
              'pmsubmit',
              'daterange',
              'mobile',
            }) ||
            _single(uri, 'pmsubmit') != 'yes') {
          throw const ForumParseException('回复私信动作参数不在白名单内');
        }
        final int pmid = _positive(_single(uri, 'pmid'));
        if (pmid <= 0) {
          throw const ForumParseException('回复私信缺少有效 pmid');
        }
        return (request.expectedPeerUserId, pmid);
    }
  }

  bool _exactQueryKeys(Uri uri, Set<String> expected) {
    final Set<String> keys = uri.queryParametersAll.keys.toSet();
    return keys.length == expected.length &&
        keys.containsAll(expected) &&
        expected.every(
          (String name) =>
              (uri.queryParametersAll[name] ?? const <String>[]).length == 1,
        );
  }

  bool _queryKeysWithin(Uri uri, Set<String> allowed) {
    final Set<String> keys = uri.queryParametersAll.keys.toSet();
    return keys.containsAll(const <String>{
          'mod',
          'do',
          'subop',
          'touid',
          'mobile',
        }) &&
        keys.difference(allowed).isEmpty &&
        keys.every(
          (String name) =>
              (uri.queryParametersAll[name] ?? const <String>[]).length == 1,
        );
  }

  String? _single(Uri uri, String name) {
    final List<String> values = uri.queryParametersAll[name] ?? const <String>[];
    return values.length == 1 ? values.single : null;
  }

  int _positive(String? value) {
    final int result = int.tryParse(value ?? '') ?? 0;
    return result > 0 ? result : 0;
  }
}
