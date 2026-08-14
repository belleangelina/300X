enum ForumActionKind {
  newThread,
  reply,
  quoteReply,
  editPost,
  deletePost,
  vote,
  comment,
  rate,
  report,
  favoriteThread,
  favoriteBoard,
  removeFavorite,
  shareThread,
}

class ForumActionTarget {
  const ForumActionTarget({
    this.boardId,
    this.threadId,
    this.postId,
    this.favoriteId,
  });

  final int? boardId;
  final int? threadId;
  final int? postId;
  final int? favoriteId;
}

class ForumActionRequest {
  const ForumActionRequest({
    required this.kind,
    required this.target,
    required this.entryUri,
    required this.readbackUri,
  });

  final ForumActionKind kind;
  final ForumActionTarget target;
  final Uri entryUri;
  final Uri readbackUri;
}

enum DynamicForumFieldType {
  text,
  multiline,
  select,
  checkbox,
  radio,
  verification,
  file,
  unsupported,
}

class DynamicForumFieldOption {
  const DynamicForumFieldOption({
    required this.value,
    required this.label,
    this.selected = false,
  });

  final String value;
  final String label;
  final bool selected;
}

class DynamicForumField {
  const DynamicForumField({
    required this.name,
    required this.label,
    required this.type,
    required this.isRequired,
    required this.multiple,
    required this.initialValues,
    required this.options,
    this.minimumLength,
    this.maximumLength,
    this.minimumValue,
    this.maximumValue,
  });

  final String name;
  final String label;
  final DynamicForumFieldType type;
  final bool isRequired;
  final bool multiple;
  final List<String> initialValues;
  final List<DynamicForumFieldOption> options;
  final int? minimumLength;
  final int? maximumLength;
  final num? minimumValue;
  final num? maximumValue;
}

class ForumCaptchaDescriptor {
  const ForumCaptchaDescriptor({
    required this.fieldName,
    required this.hashFieldName,
    required this.imageUri,
  });

  final String fieldName;
  final String hashFieldName;
  final Uri imageUri;
}

class ForumAttachmentField {
  const ForumAttachmentField({
    required this.fieldName,
    required this.multiple,
    required this.allowedExtensions,
    this.maximumFileBytes,
    this.maximumFiles,
  });

  final String fieldName;
  final bool multiple;
  final List<String> allowedExtensions;
  final int? maximumFileBytes;
  final int? maximumFiles;
}

class ForumAttachmentSelection {
  const ForumAttachmentSelection({
    required this.fieldName,
    required this.fileName,
    required this.localPath,
    required this.length,
    this.mimeType,
  });

  final String fieldName;
  final String fileName;
  final String localPath;
  final int length;
  final String? mimeType;
}

abstract interface class ForumAttachmentUploader {
  Future<Map<String, List<String>>> upload({
    required int userId,
    required ForumPreparedAction prepared,
    required List<ForumAttachmentSelection> attachments,
  });
}

class DynamicForumForm {
  const DynamicForumForm({
    required this.sourceUri,
    required this.actionUri,
    required this.hiddenFields,
    required this.submitFields,
    required this.fields,
    required this.attachmentFields,
    required this.preparedAt,
    this.captcha,
  });

  final Uri sourceUri;
  final Uri actionUri;
  final Map<String, List<String>> hiddenFields;
  final Map<String, List<String>> submitFields;
  final List<DynamicForumField> fields;
  final List<ForumAttachmentField> attachmentFields;
  final DateTime preparedAt;
  final ForumCaptchaDescriptor? captcha;

  String get formHash => hiddenFields['formhash']?.firstOrNull ?? '';

  bool get declaresAttachments => attachmentFields.isNotEmpty;

  bool get attachmentUploadVerified => false;

  DynamicForumField? fieldByName(String name) {
    for (final DynamicForumField field in fields) {
      if (field.name == name) {
        return field;
      }
    }
    return null;
  }
}

enum ForumReadbackKind {
  boardThreads,
  thread,
  post,
  poll,
  comments,
  ratings,
  report,
  threadFavorites,
  boardFavorites,
  shares,
}

class ForumReadbackDescriptor {
  const ForumReadbackDescriptor({
    required this.kind,
    required this.uri,
    required this.target,
    required this.description,
  });

  final ForumReadbackKind kind;
  final Uri uri;
  final ForumActionTarget target;
  final String description;
}

class ForumReadbackReceipt {
  const ForumReadbackReceipt({
    required this.userId,
    required this.descriptor,
    required this.sourceUri,
    required this.contentDigest,
    required this.receivedAt,
  });

  final int userId;
  final ForumReadbackDescriptor descriptor;
  final Uri sourceUri;
  final String contentDigest;
  final DateTime receivedAt;
}

class ForumPreparedAction {
  const ForumPreparedAction({
    required this.token,
    required this.userId,
    required this.request,
    required this.form,
    required this.readback,
    this.draftContext = '',
  });

  final String token;
  final int userId;
  final ForumActionRequest request;
  final DynamicForumForm form;
  final ForumReadbackDescriptor readback;
  final String draftContext;
}

enum ForumSubmissionTombstoneStatus { pending, attempted }

class ForumUnresolvedSubmission {
  const ForumUnresolvedSubmission({
    required this.attemptId,
    required this.userId,
    required this.request,
    required this.readback,
    required this.status,
    required this.recordedAt,
    this.draftContext = '',
  });

  final String attemptId;
  final int userId;
  final ForumActionRequest request;
  final ForumReadbackDescriptor readback;
  final ForumSubmissionTombstoneStatus status;
  final DateTime recordedAt;
  final String draftContext;
}

class ForumSubmissionTombstoneSnapshot {
  const ForumSubmissionTombstoneSnapshot({
    required this.attemptId,
    required this.userId,
    required this.kind,
    required this.target,
    required this.status,
    required this.recordedAt,
    required this.draftContext,
  });

  final String attemptId;
  final int userId;
  final ForumActionKind kind;
  final ForumActionTarget target;
  final ForumSubmissionTombstoneStatus status;
  final DateTime recordedAt;
  final String draftContext;
}

enum ForumSubmissionStatus {
  success,
  explicitFailure,
  permissionDenied,
  tokenExpired,
  resultUnknown,
}

class ForumSubmissionResult {
  const ForumSubmissionResult({
    required this.status,
    required this.userId,
    required this.message,
    required this.readback,
    this.serverCode = '',
    this.responseUri,
    this.threadId,
    this.postId,
    this.submissionAttempted = false,
    this.canRetryPrepared = false,
    this.requiresSessionRefresh = false,
  });

  final ForumSubmissionStatus status;
  final int userId;
  final String message;
  final String serverCode;
  final Uri? responseUri;
  final int? threadId;
  final int? postId;
  final ForumReadbackDescriptor readback;
  final bool submissionAttempted;
  final bool canRetryPrepared;
  final bool requiresSessionRefresh;

  bool get requiresReadback =>
      status == ForumSubmissionStatus.success ||
      status == ForumSubmissionStatus.resultUnknown;

  bool get permitsCacheMutation => false;
}

class ForumActionDraft {
  ForumActionDraft({
    required this.userId,
    required this.kind,
    required this.target,
    required Map<String, List<String>> values,
    required this.updatedAt,
  }) : values = _validateValues(values);

  final int userId;
  final ForumActionKind kind;
  final ForumActionTarget target;
  final Map<String, List<String>> values;
  final DateTime updatedAt;

  static Map<String, List<String>> _validateValues(
    Map<String, List<String>> source,
  ) {
    for (final String name in source.keys) {
      final String normalized = name.toLowerCase();
      if (normalized == 'formhash' ||
          normalized.contains('seccode') ||
          normalized.contains('captcha')) {
        throw ArgumentError.value(name, 'values', '草稿不能保存临时验证字段');
      }
    }
    return Map<String, List<String>>.unmodifiable(<String, List<String>>{
      for (final MapEntry<String, List<String>> entry in source.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });
  }
}
