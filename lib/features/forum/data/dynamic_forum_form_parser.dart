import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:x300/core/network/forum_exceptions.dart';
import 'package:x300/features/auth/data/auth_page_parser.dart';
import 'package:x300/features/forum/data/forum_action_contract.dart';
import 'package:x300/features/forum/data/forum_origin_policy.dart';
import 'package:x300/features/forum/domain/forum_action_models.dart';

class DynamicForumFormParser {
  const DynamicForumFormParser({
    this.contract = const ForumActionContract(),
    this.authParser = const AuthPageParser(),
  });

  final ForumActionContract contract;
  final AuthPageParser authParser;

  DynamicForumForm parse(
    String source,
    Uri pageUri, {
    required int expectedUserId,
    required ForumActionRequest request,
  }) {
    contract.validateEntry(request, pageUri);
    contract.validateAccountUri(pageUri, expectedUserId);
    final Document document = html_parser.parse(source);
    _validateIdentity(document, source, expectedUserId);
    final Element form = _findForm(document, request.kind);
    if (request.kind == ForumActionKind.editPost &&
        document.querySelectorAll('form#postform').length != 1) {
      throw const ForumParseException('论坛编辑页面缺少唯一 postform');
    }
    if ((form.attributes['method'] ?? 'get').toLowerCase() != 'post') {
      throw const ForumParseException('论坛操作表单不是 POST');
    }
    if (request.kind == ForumActionKind.editPost &&
        (form.attributes['enctype'] ?? '').toLowerCase() !=
            'multipart/form-data') {
      throw const ForumParseException('论坛编辑表单编码与移动契约不一致');
    }
    final String actionValue = form.attributes['action']?.trim() ?? '';
    if (actionValue.isEmpty) {
      throw const ForumParseException('论坛操作表单缺少提交地址');
    }
    final Uri actionUri;
    try {
      actionUri = pageUri.resolve(actionValue);
    } on FormatException {
      throw const ForumActionSecurityException('论坛表单提交地址无效');
    }

    final Map<String, List<String>> hiddenFields = <String, List<String>>{};
    for (final Element input in form.querySelectorAll(
      'input[type="hidden"][name]',
    )) {
      _addValue(
        hiddenFields,
        input.attributes['name']!.trim(),
        input.attributes['value'] ?? '',
      );
    }
    final List<String>? formHashes = hiddenFields['formhash'];
    if (formHashes == null ||
        formHashes.length != 1 ||
        formHashes.single.isEmpty) {
      throw const ForumParseException('论坛操作表单缺少唯一 formhash');
    }
    contract.validateAccountFields(hiddenFields, expectedUserId);
    contract.validateHiddenFields(request, hiddenFields);
    contract.validateFormAction(request, actionUri, hiddenFields);
    contract.validateAccountUri(actionUri, expectedUserId);

    final List<_FieldBuilder> builders = <_FieldBuilder>[];
    final Map<String, _FieldBuilder> groups = <String, _FieldBuilder>{};
    final Map<String, _FieldBuilder> fileGroups = <String, _FieldBuilder>{};
    final List<_SubmitControl> submitControls = <_SubmitControl>[];
    final List<ForumAttachmentField> attachmentFields =
        <ForumAttachmentField>[];

    for (final Element control in form.querySelectorAll(
      'input, textarea, select, button',
    )) {
      if (control.attributes.containsKey('disabled')) {
        continue;
      }
      final String name = control.attributes['name']?.trim() ?? '';
      if (name.isEmpty) {
        continue;
      }
      if (control.attributes.containsKey('readonly')) {
        throw ForumParseException('论坛表单包含不可编辑但会提交的字段：$name');
      }
      final String tag = control.localName ?? '';
      final String inputType = tag == 'input'
          ? (control.attributes['type'] ?? 'text').toLowerCase()
          : '';
      if (inputType == 'hidden') {
        continue;
      }
      if (_requiresHiddenSubmitMarker(request.kind, name)) {
        throw ForumParseException('论坛隐藏提交标记存在同名可提交控件：$name');
      }
      if (inputType == 'submit' ||
          (tag == 'button' &&
              (control.attributes['type'] ?? 'submit').toLowerCase() ==
                  'submit')) {
        submitControls.add(
          _SubmitControl(name, control.attributes['value'] ?? ''),
        );
        continue;
      }
      if (tag == 'button' ||
          const <String>{'button', 'reset', 'image'}.contains(inputType)) {
        continue;
      }

      final DynamicForumFieldType type = _fieldType(control, inputType);
      final bool grouped =
          type == DynamicForumFieldType.checkbox ||
          type == DynamicForumFieldType.radio;
      if (grouped) {
        final _FieldBuilder builder = groups.putIfAbsent(name, () {
          final _FieldBuilder value = _FieldBuilder(
            name: name,
            label: _labelFor(form, control, name),
            type: type,
            isRequired: _isRequired(control),
            multiple:
                type == DynamicForumFieldType.checkbox || name.endsWith('[]'),
          );
          builders.add(value);
          return value;
        });
        builder.isRequired = builder.isRequired || _isRequired(control);
        final String value = control.attributes['value'] ?? '1';
        final bool selected = control.attributes.containsKey('checked');
        builder.options.add(
          DynamicForumFieldOption(
            value: value,
            label: _labelFor(form, control, value),
            selected: selected,
          ),
        );
        if (selected) {
          builder.initialValues.add(value);
        }
        continue;
      }

      final _FieldBuilder builder = _FieldBuilder(
        name: name,
        label: _labelFor(form, control, name),
        type: type,
        isRequired:
            _isRequired(control) ||
            _isRequiredByContract(request.kind, name, type),
        multiple:
            control.attributes.containsKey('multiple') || name.endsWith('[]'),
        minimumLength: _positiveInt(control.attributes['minlength']),
        maximumLength: _positiveInt(control.attributes['maxlength']),
        minimumValue: num.tryParse(control.attributes['min'] ?? ''),
        maximumValue: num.tryParse(control.attributes['max'] ?? ''),
      );
      if (tag == 'textarea') {
        builder.initialValues.add(control.text);
      } else if (tag == 'select') {
        for (final Element option in control.querySelectorAll('option')) {
          final DynamicForumFieldOption parsed = DynamicForumFieldOption(
            value: option.attributes['value'] ?? option.text.trim(),
            label: _normalizeText(option.text),
            selected: option.attributes.containsKey('selected'),
          );
          builder.options.add(parsed);
          if (parsed.selected) {
            builder.initialValues.add(parsed.value);
          }
        }
        if (builder.initialValues.isEmpty &&
            builder.options.isNotEmpty &&
            !builder.multiple) {
          builder.initialValues.add(builder.options.first.value);
        }
      } else if (type != DynamicForumFieldType.file) {
        final String value = control.attributes['value'] ?? '';
        if (value.isNotEmpty) {
          builder.initialValues.add(value);
        }
      }
      if (type == DynamicForumFieldType.file) {
        final _FieldBuilder? existing = fileGroups[name];
        if (existing == null) {
          fileGroups[name] = builder;
          builders.add(builder);
        } else {
          existing.isRequired = existing.isRequired || builder.isRequired;
          existing.multiple = existing.multiple || builder.multiple;
        }
        attachmentFields.add(
          ForumAttachmentField(
            fieldName: name,
            multiple: builder.multiple,
            allowedExtensions: List<String>.unmodifiable(
              _extensions(control.attributes['accept']),
            ),
            maximumFileBytes: _positiveInt(
              control.attributes['data-max-size'] ??
                  control.attributes['maxsize'],
            ),
            maximumFiles: _positiveInt(
              control.attributes['data-max-files'] ??
                  control.attributes['maxfiles'],
            ),
          ),
        );
        continue;
      }
      builders.add(builder);
    }

    final Map<String, List<String>> submitFields = _selectSubmitFields(
      request.kind,
      hiddenFields,
      submitControls,
    );
    contract.validateSubmitFields(request, submitFields);
    final List<DynamicForumField> fields = builders
        .map((_FieldBuilder value) => value.build())
        .toList(growable: false);
    _validateEditContentFields(request.kind, fields);
    contract.validateUserFieldNames(
      fields.map((DynamicForumField field) => field.name),
    );
    final Set<String> declaredNames = <String>{};
    for (final DynamicForumField field in fields) {
      if (!declaredNames.add(field.name)) {
        throw ForumParseException('论坛表单重复声明字段：${field.name}');
      }
      if (hiddenFields.containsKey(field.name) ||
          submitFields.containsKey(field.name)) {
        throw ForumParseException('论坛表单字段角色冲突：${field.name}');
      }
    }
    final ForumCaptchaDescriptor? captcha = _parseCaptcha(
      form,
      fields,
      hiddenFields,
      pageUri,
    );

    return DynamicForumForm(
      sourceUri: pageUri,
      actionUri: actionUri,
      hiddenFields: _freezeMap(hiddenFields),
      submitFields: _freezeMap(submitFields),
      fields: List<DynamicForumField>.unmodifiable(fields),
      attachmentFields: List<ForumAttachmentField>.unmodifiable(
        attachmentFields,
      ),
      preparedAt: DateTime.now().toUtc(),
      captcha: captcha,
    );
  }

  void _validateIdentity(Document document, String source, int expectedUserId) {
    if (document.querySelector('form#loginform') != null ||
        expectedUserId <= 0 ||
        authParser.currentUserId(source) != expectedUserId) {
      throw const ForumSessionExpiredException();
    }
  }

  Element _findForm(Document document, ForumActionKind kind) {
    for (final String selector in _formSelectors(kind)) {
      final Element? form = document.querySelector(selector);
      if (form != null) {
        return form;
      }
    }
    final List<Element> candidates = document
        .querySelectorAll('form')
        .where(
          (Element form) =>
              form.id != 'loginform' &&
              (form.attributes['method'] ?? 'get').toLowerCase() == 'post' &&
              form.querySelector('input[name="formhash"]') != null,
        )
        .toList(growable: false);
    if (candidates.length == 1) {
      return candidates.single;
    }
    final String message = _normalizeText(
      document
              .querySelector(
                '#messagetext, .alert_error, .alert_info, .showmessage, .tip',
              )
              ?.text ??
          '',
    );
    throw ForumParseException(message.isEmpty ? '论坛页面没有唯一可识别的操作表单' : message);
  }

  List<String> _formSelectors(ForumActionKind kind) {
    return switch (kind) {
      ForumActionKind.newThread ||
      ForumActionKind.reply ||
      ForumActionKind.quoteReply ||
      ForumActionKind.editPost ||
      ForumActionKind.deletePost => const <String>['form#postform'],
      ForumActionKind.vote => const <String>['form#poll'],
      ForumActionKind.comment => const <String>[
        'form#commentform',
        'form[action*="action=comment"]',
      ],
      ForumActionKind.rate => const <String>[
        'form#rateform',
        'form[action*="action=rate"]',
      ],
      ForumActionKind.report => const <String>[
        'form#reportform',
        'form[action*="mod=report"]',
      ],
      ForumActionKind.favoriteThread ||
      ForumActionKind.favoriteBoard ||
      ForumActionKind.removeFavorite => const <String>[
        'form[id^="favoriteform"]',
        'form[action*="ac=favorite"]',
      ],
      ForumActionKind.shareThread => const <String>[
        'form[id^="shareform"]',
        'form[action*="ac=share"]',
      ],
    };
  }

  Map<String, List<String>> _selectSubmitFields(
    ForumActionKind kind,
    Map<String, List<String>> hidden,
    List<_SubmitControl> controls,
  ) {
    final Set<String> expected = _expectedSubmitNames(kind);
    final Map<String, List<String>> result = <String, List<String>>{};
    final String? hiddenMarker = switch (kind) {
      ForumActionKind.reply || ForumActionKind.quoteReply => 'replysubmit',
      ForumActionKind.editPost => 'editsubmit',
      _ => null,
    };
    if (hiddenMarker != null) {
      final List<String> markers = hidden[hiddenMarker] ?? const <String>[];
      if (markers.length != 1 ||
          markers.single != 'yes' ||
          controls.any((_SubmitControl control) =>
              expected.contains(control.name))) {
        throw ForumParseException(
          '论坛${kind == ForumActionKind.editPost ? '编辑' : '回复'}表单提交标记与移动契约不一致',
        );
      }
      result[hiddenMarker] = const <String>['yes'];
      return result;
    }
    for (final _SubmitControl control in controls) {
      if (expected.contains(control.name)) {
        _addValue(result, control.name, control.value);
        break;
      }
    }
    if (result.isEmpty) {
      final List<MapEntry<String, List<String>>> hiddenMarkers = hidden.entries
          .where((MapEntry<String, List<String>> entry) =>
              expected.contains(entry.key))
          .toList(growable: false);
      if (hiddenMarkers.length == 1) {
        result[hiddenMarkers.single.key] = List<String>.from(
          hiddenMarkers.single.value,
        );
      }
    }
    final bool declared = expected.any(
      (String name) => hidden.containsKey(name) || result.containsKey(name),
    );
    if (!declared) {
      throw const ForumParseException('论坛操作表单缺少对应的提交标记');
    }
    return result;
  }

  Set<String> _expectedSubmitNames(ForumActionKind kind) {
    return switch (kind) {
      ForumActionKind.newThread => const <String>{'topicsubmit'},
      ForumActionKind.reply ||
      ForumActionKind.quoteReply => const <String>{'replysubmit'},
      ForumActionKind.editPost ||
      ForumActionKind.deletePost => const <String>{'editsubmit'},
      ForumActionKind.vote => const <String>{'pollsubmit'},
      ForumActionKind.comment => const <String>{'commentsubmit'},
      ForumActionKind.rate => const <String>{'ratesubmit'},
      ForumActionKind.report => const <String>{'reportsubmit'},
      ForumActionKind.favoriteThread || ForumActionKind.favoriteBoard =>
        const <String>{'favoritesubmit', 'favoritesubmit_btn'},
      ForumActionKind.removeFavorite => const <String>{
        'deletesubmit',
        'deletesubmitbtn',
      },
      ForumActionKind.shareThread => const <String>{
        'sharesubmit',
        'sharesubmit_btn',
      },
    };
  }

  DynamicForumFieldType _fieldType(Element control, String inputType) {
    final String name = control.attributes['name']?.toLowerCase() ?? '';
    if (name.contains('seccodeverify') ||
        name.contains('captcha') ||
        name == 'secanswer') {
      return DynamicForumFieldType.verification;
    }
    if (control.localName == 'textarea') {
      return DynamicForumFieldType.multiline;
    }
    if (control.localName == 'select') {
      return DynamicForumFieldType.select;
    }
    return switch (inputType) {
      '' ||
      'text' ||
      'number' ||
      'email' ||
      'url' ||
      'tel' ||
      'password' ||
      'search' => DynamicForumFieldType.text,
      'checkbox' => DynamicForumFieldType.checkbox,
      'radio' => DynamicForumFieldType.radio,
      'file' => DynamicForumFieldType.file,
      _ => DynamicForumFieldType.unsupported,
    };
  }

  ForumCaptchaDescriptor? _parseCaptcha(
    Element form,
    List<DynamicForumField> fields,
    Map<String, List<String>> hidden,
    Uri pageUri,
  ) {
    final List<DynamicForumField> verifications = fields
        .where(
          (DynamicForumField field) =>
              field.type == DynamicForumFieldType.verification,
        )
        .toList(growable: false);
    final List<String> hashNames = hidden.keys
        .where(
          (String name) =>
              name.toLowerCase().contains('seccodehash') ||
              name.toLowerCase().contains('captchahash'),
        )
        .toList(growable: false);
    final List<Element> images = form.querySelectorAll(
      'img[src*="seccode"], img[src*="captcha"], [id^="seccode"] img',
    );
    if (verifications.isEmpty && hashNames.isEmpty && images.isEmpty) {
      return null;
    }
    if (verifications.length != 1 ||
        hashNames.length != 1 ||
        images.length != 1) {
      throw const ForumParseException('论坛验证码结构不完整');
    }
    final DynamicForumField verification = verifications.single;
    final String verificationName = verification.name.toLowerCase();
    if (!verificationName.contains('seccodeverify') &&
        !verificationName.contains('captcha')) {
      throw const ForumParseException('论坛验证字段尚未支持');
    }
    final List<String>? hashValues = hidden[hashNames.single];
    if (hashValues == null ||
        hashValues.length != 1 ||
        hashValues.single.isEmpty) {
      throw const ForumParseException('论坛验证码缺少唯一校验标记');
    }
    final String source = images.single.attributes['src']?.trim() ?? '';
    final Uri imageUri;
    try {
      imageUri = pageUri.resolve(source);
    } on FormatException {
      throw const ForumParseException('论坛验证码地址无效');
    }
    AuthPageParser.requireCaptchaUri(imageUri);
    return ForumCaptchaDescriptor(
      fieldName: verification.name,
      hashFieldName: hashNames.single,
      imageUri: imageUri,
    );
  }

  bool _isRequired(Element control) {
    return control.attributes.containsKey('required') ||
        control.attributes['aria-required'] == 'true' ||
        control.classes.contains('required');
  }

  bool _isRequiredByContract(
    ForumActionKind kind,
    String name,
    DynamicForumFieldType type,
  ) {
    return (kind == ForumActionKind.reply ||
            kind == ForumActionKind.quoteReply ||
            kind == ForumActionKind.editPost) &&
        type == DynamicForumFieldType.multiline &&
        name.toLowerCase() == 'message';
  }

  bool _requiresHiddenSubmitMarker(ForumActionKind kind, String name) {
    return switch (kind) {
      ForumActionKind.reply || ForumActionKind.quoteReply =>
        name == 'replysubmit',
      ForumActionKind.editPost => name == 'editsubmit',
      _ => false,
    };
  }

  void _validateEditContentFields(
    ForumActionKind kind,
    List<DynamicForumField> fields,
  ) {
    if (kind != ForumActionKind.editPost) {
      return;
    }
    final List<DynamicForumField> messages = fields
        .where((DynamicForumField field) => field.name == 'message')
        .toList(growable: false);
    if (messages.length != 1 ||
        messages.single.type != DynamicForumFieldType.multiline ||
        !messages.single.isRequired ||
        messages.single.multiple) {
      throw const ForumParseException('论坛编辑正文结构与移动契约不一致');
    }
    final List<DynamicForumField> subjects = fields
        .where((DynamicForumField field) => field.name == 'subject')
        .toList(growable: false);
    if (subjects.length != 1 ||
        subjects.single.type != DynamicForumFieldType.text ||
        subjects.single.isRequired ||
        subjects.single.multiple) {
      throw const ForumParseException('论坛编辑标题结构与移动契约不一致');
    }
  }

  String _labelFor(Element form, Element control, String fallback) {
    final String id = control.id;
    if (id.isNotEmpty) {
      final Element? explicit = form.querySelector('label[for="$id"]');
      final String label = _normalizeText(explicit?.text ?? '');
      if (label.isNotEmpty) {
        return label;
      }
    }
    final String wrapped = _normalizeText(control.parent?.text ?? '');
    return wrapped.isEmpty ? fallback : wrapped;
  }

  List<String> _extensions(String? accept) {
    if (accept == null || accept.trim().isEmpty) {
      return const <String>[];
    }
    return accept
        .split(',')
        .map((String value) => value.trim().toLowerCase())
        .where((String value) => value.startsWith('.') && value.length > 1)
        .toList(growable: false);
  }

  int? _positiveInt(String? value) {
    final int? parsed = int.tryParse(value ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  void _addValue(Map<String, List<String>> target, String name, String value) {
    if (name.isNotEmpty) {
      target.putIfAbsent(name, () => <String>[]).add(value);
    }
  }

  Map<String, List<String>> _freezeMap(Map<String, List<String>> source) {
    return Map<String, List<String>>.unmodifiable(<String, List<String>>{
      for (final MapEntry<String, List<String>> entry in source.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });
  }

  String _normalizeText(String source) {
    return source.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _SubmitControl {
  const _SubmitControl(this.name, this.value);

  final String name;
  final String value;
}

class _FieldBuilder {
  _FieldBuilder({
    required this.name,
    required this.label,
    required this.type,
    required this.isRequired,
    required this.multiple,
    this.minimumLength,
    this.maximumLength,
    this.minimumValue,
    this.maximumValue,
  });

  final String name;
  final String label;
  final DynamicForumFieldType type;
  bool isRequired;
  bool multiple;
  final int? minimumLength;
  final int? maximumLength;
  final num? minimumValue;
  final num? maximumValue;
  final List<String> initialValues = <String>[];
  final List<DynamicForumFieldOption> options = <DynamicForumFieldOption>[];

  DynamicForumField build() {
    return DynamicForumField(
      name: name,
      label: label,
      type: type,
      isRequired: isRequired,
      multiple: multiple,
      initialValues: List<String>.unmodifiable(initialValues),
      options: List<DynamicForumFieldOption>.unmodifiable(options),
      minimumLength: minimumLength,
      maximumLength: maximumLength,
      minimumValue: minimumValue,
      maximumValue: maximumValue,
    );
  }
}
