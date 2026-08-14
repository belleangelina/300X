import 'package:x300/features/forum/domain/forum_models.dart';

class ForumAnnouncement {
  const ForumAnnouncement({
    required this.id,
    required this.title,
    required this.metadataLabel,
    required this.contentBlocks,
    required this.messageHtml,
    required this.sourceUri,
    this.isFromCache = false,
    this.cacheUpdatedAt,
  });

  final int id;
  final String title;
  final String metadataLabel;
  final List<ForumPostContentBlock> contentBlocks;
  final String messageHtml;
  final Uri sourceUri;
  final bool isFromCache;
  final DateTime? cacheUpdatedAt;

  bool get hasContent => contentBlocks.isNotEmpty || messageHtml.isNotEmpty;
}
