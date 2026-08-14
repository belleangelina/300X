enum CommunityPmSendContext { compose, conversation }

class CommunityPmSendRequest {
  const CommunityPmSendRequest({
    required this.context,
    required this.entryUri,
    this.expectedPeerUserId = 0,
    this.expectedPeerUsername = '',
  });

  final CommunityPmSendContext context;
  final Uri entryUri;
  final int expectedPeerUserId;
  final String expectedPeerUsername;
}

class CommunityPmSendForm {
  CommunityPmSendForm({
    required this.context,
    required this.sourceUri,
    required this.actionUri,
    required this.viewerUserId,
    required this.peerUserId,
    required this.privateMessageId,
    required this.formHash,
    required Map<String, String> fixedFields,
    required this.acceptsUsername,
    this.initialUsername = '',
  }) : fixedFields = Map<String, String>.unmodifiable(fixedFields);

  final CommunityPmSendContext context;
  final Uri sourceUri;
  final Uri actionUri;
  final int viewerUserId;
  final int peerUserId;
  final int privateMessageId;
  final String formHash;
  final Map<String, String> fixedFields;
  final bool acceptsUsername;
  final String initialUsername;
}

class CommunityPmPreparedSend {
  const CommunityPmPreparedSend({
    required this.token,
    required this.userId,
    required this.request,
    required this.form,
  });

  final String token;
  final int userId;
  final CommunityPmSendRequest request;
  final CommunityPmSendForm form;
}

enum CommunityPmSubmissionStatus { explicitFailure, resultUnknown }

class CommunityPmSubmissionResult {
  const CommunityPmSubmissionResult({
    required this.status,
    required this.message,
    required this.submissionAttempted,
    this.canRetryPrepared = false,
    this.requiresSessionRefresh = false,
  });

  final CommunityPmSubmissionStatus status;
  final String message;
  final bool submissionAttempted;
  final bool canRetryPrepared;
  final bool requiresSessionRefresh;
}

class CommunityPmDraft {
  const CommunityPmDraft({
    required this.userId,
    required this.context,
    required this.peerUserId,
    required this.username,
    required this.message,
    required this.updatedAt,
  });

  final int userId;
  final CommunityPmSendContext context;
  final int peerUserId;
  final String username;
  final String message;
  final DateTime updatedAt;
}
