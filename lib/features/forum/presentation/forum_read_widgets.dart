import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
import 'package:x300/features/forum/application/forum_attachment_download_controller.dart';
import 'package:x300/features/forum/domain/forum_models.dart';
import 'package:x300/shared/presentation/forum_image.dart';

class ForumCacheBanner extends StatelessWidget {
  const ForumCacheBanner({this.updatedAt, super.key});

  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    final String time = updatedAt == null
        ? ''
        : ' · ${DateFormat('MM-dd HH:mm').format(updatedAt!)}';
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            const Icon(Icons.cloud_off_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '论坛不可用，当前显示只读缓存$time',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ForumPostContent extends StatelessWidget {
  const ForumPostContent({
    required this.post,
    this.onOpenLink,
    this.onOpenAttachment,
    this.onCancelAttachment,
    this.attachmentState,
    this.onOpenAuthor,
    super.key,
  });

  final ForumPost post;
  final ValueChanged<ForumPostLinkInline>? onOpenLink;
  final ValueChanged<ForumAttachment>? onOpenAttachment;
  final ValueChanged<ForumAttachment>? onCancelAttachment;
  final ForumAttachmentDownloadState? Function(ForumAttachment attachment)?
  attachmentState;
  final void Function(Uri uri, int userId)? onOpenAuthor;

  @override
  Widget build(BuildContext context) {
    final bool hasStructuredContent = post.contentBlocks.isNotEmpty;
    final String message = hasStructuredContent
        ? ''
        : forumPlainText(post.messageHtml);
    final Set<Uri> inlineImages = <Uri>{
      for (final ForumPostContentBlock block in post.contentBlocks)
        for (final ForumPostImageInline image
            in block.inlines.whereType<ForumPostImageInline>())
          image.uri,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (hasStructuredContent)
          for (
            int index = 0;
            index < post.contentBlocks.length;
            index++
          ) ...<Widget>[
            if (index > 0) const SizedBox(height: 10),
            _ForumPostBlockView(
              key: ValueKey<String>('forum-post-${post.id}-block-$index'),
              block: post.contentBlocks[index],
              referer: post.uri.toString(),
              onOpenLink: onOpenLink,
            ),
          ],
        if (message.isNotEmpty)
          SelectableText(
            key: ValueKey<String>('forum-post-${post.id}-legacy-text'),
            message,
            style: const TextStyle(fontSize: 15, height: 1.65),
          ),
        for (final ForumAttachment attachment in post.attachments.where(
          (ForumAttachment value) =>
              !value.isImage || !inlineImages.contains(value.uri),
        )) ...<Widget>[
          const SizedBox(height: 12),
          _ForumAttachmentView(
            attachment: attachment,
            referer: post.uri.toString(),
            state: attachmentState?.call(attachment),
            onCancel: onCancelAttachment == null
                ? null
                : () => onCancelAttachment!(attachment),
            onOpen: onOpenAttachment != null
                ? () => onOpenAttachment!(attachment)
                : onOpenLink == null
                ? null
                : () => onOpenLink!(
                    ForumPostLinkInline(
                      label: attachment.name.isEmpty ? '附件' : attachment.name,
                      uri: attachment.uri,
                      kind: ForumPostLinkKind.download,
                    ),
                  ),
          ),
        ],
        if (post.comments.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          ForumPostComments(
            comments: post.comments,
            referer: post.uri.toString(),
            onOpenLink: onOpenLink,
            onOpenAuthor: onOpenAuthor,
          ),
        ],
        if (post.ratingSummary != null) ...<Widget>[
          const SizedBox(height: 12),
          ForumPostRatings(
            summary: post.ratingSummary!,
            onOpenAuthor: onOpenAuthor,
          ),
        ],
      ],
    );
  }
}

class ForumPostComments extends StatelessWidget {
  const ForumPostComments({
    required this.comments,
    required this.referer,
    this.onOpenLink,
    this.onOpenAuthor,
    super.key,
  });

  final List<ForumPostComment> comments;
  final String referer;
  final ValueChanged<ForumPostLinkInline>? onOpenLink;
  final void Function(Uri uri, int userId)? onOpenAuthor;

  @override
  Widget build(BuildContext context) {
    return _ForumInteractionPanel(
      title: '点评 ${comments.length}',
      icon: Icons.chat_bubble_outline,
      children: <Widget>[
        for (int index = 0; index < comments.length; index++) ...<Widget>[
          if (index > 0) const Divider(height: 17),
          _ForumCommentView(
            comment: comments[index],
            referer: referer,
            onOpenLink: onOpenLink,
            onOpenAuthor: onOpenAuthor,
          ),
        ],
      ],
    );
  }
}

class ForumPostRatings extends StatelessWidget {
  const ForumPostRatings({
    required this.summary,
    this.onViewAll,
    this.onOpenAuthor,
    super.key,
  });

  final ForumPostRatingSummary summary;
  final VoidCallback? onViewAll;
  final void Function(Uri uri, int userId)? onOpenAuthor;

  @override
  Widget build(BuildContext context) {
    return _ForumInteractionPanel(
      title: '评分 · ${summary.participantCount} 人',
      icon: Icons.favorite_border,
      trailing: summary.hasMore && onViewAll != null
          ? TextButton(onPressed: onViewAll, child: const Text('查看全部'))
          : null,
      children: <Widget>[
        Text(
          summary.totals.map(_ratingText).join(' · '),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        for (int index = 0; index < summary.entries.length; index++) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_canOpenAuthor(
                summary.entries[index].authorUri,
                summary.entries[index].authorId,
                onOpenAuthor,
              ))
                _ForumAuthorButton(
                  key: ValueKey<String>(
                    'forum-rating-author-${summary.entries[index].authorId}-$index',
                  ),
                  author: summary.entries[index].author,
                  onPressed: () => onOpenAuthor!(
                    summary.entries[index].authorUri!,
                    summary.entries[index].authorId!,
                  ),
                ),
              Expanded(
                child: Text(
                  summary.entries[index].author,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                summary.entries[index].scores.map(_ratingText).join(' · '),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (summary.entries[index].reason.isNotEmpty ||
              summary.entries[index].timeLabel.isNotEmpty)
            Text(
              <String>[
                summary.entries[index].reason,
                summary.entries[index].timeLabel,
              ].where((String value) => value.isNotEmpty).join(' · '),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
        ],
      ],
    );
  }

  String _ratingText(ForumPostRatingScore score) {
    final String value = score.value > 0 ? '+${score.value}' : '${score.value}';
    return '${score.credit} $value';
  }
}

class _ForumInteractionPanel extends StatelessWidget {
  const _ForumInteractionPanel({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ForumCommentView extends StatelessWidget {
  const _ForumCommentView({
    required this.comment,
    required this.referer,
    required this.onOpenLink,
    this.onOpenAuthor,
  });

  final ForumPostComment comment;
  final String referer;
  final ValueChanged<ForumPostLinkInline>? onOpenLink;
  final void Function(Uri uri, int userId)? onOpenAuthor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          radius: 11,
          child: comment.avatarUri == null
              ? Text(
                  comment.author.isEmpty
                      ? '?'
                      : comment.author.characters.first,
                  style: const TextStyle(fontSize: 9),
                )
              : ClipOval(
                  child: ForumImage(
                    uri: comment.avatarUri!,
                    referer: referer,
                    width: 22,
                    height: 22,
                    fit: BoxFit.cover,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (_canOpenAuthor(
                    comment.authorUri,
                    comment.authorId,
                    onOpenAuthor,
                  ))
                    _ForumAuthorButton(
                      key: ValueKey<String>(
                        'forum-comment-author-${comment.id}',
                      ),
                      author: comment.author,
                      onPressed: () => onOpenAuthor!(
                        comment.authorUri!,
                        comment.authorId!,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      <String>[
                        comment.author.isEmpty ? '游客' : comment.author,
                        comment.timeLabel,
                      ].where((String value) => value.isNotEmpty).join(' · '),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              for (
                int index = 0;
                index < comment.contentBlocks.length;
                index++
              ) ...<Widget>[
                if (index > 0) const SizedBox(height: 6),
                _ForumPostBlockView(
                  block: comment.contentBlocks[index],
                  referer: referer,
                  onOpenLink: onOpenLink,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ForumPostBlockView extends StatelessWidget {
  const _ForumPostBlockView({
    required this.block,
    required this.referer,
    required this.onOpenLink,
    super.key,
  });

  final ForumPostContentBlock block;
  final String referer;
  final ValueChanged<ForumPostLinkInline>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final bool quote = block is ForumPostQuoteBlock;
    final bool code = block is ForumPostCodeBlock;
    final Widget content = _ForumPostInlineContent(
      inlines: block.inlines,
      referer: referer,
      onOpenLink: onOpenLink,
      baseStyle: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontFamily: code ? 'monospace' : null,
        fontSize: code ? 13 : 15,
        height: code ? 1.55 : 1.65,
      ),
    );
    if (!quote && !code) {
      return content;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: code
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Theme.of(context).colorScheme.surfaceContainerLow,
        border: quote
            ? Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 3,
                ),
              )
            : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(padding: const EdgeInsets.all(10), child: content),
    );
  }
}

class _ForumPostInlineContent extends StatelessWidget {
  const _ForumPostInlineContent({
    required this.inlines,
    required this.referer,
    required this.onOpenLink,
    required this.baseStyle,
  });

  final List<ForumPostInline> inlines;
  final String referer;
  final ValueChanged<ForumPostLinkInline>? onOpenLink;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    final List<ForumPostInline> textRun = <ForumPostInline>[];

    void flushTextRun() {
      if (textRun.isEmpty) {
        return;
      }
      children.add(
        SelectableText.rich(
          TextSpan(
            style: baseStyle,
            children: textRun
                .map((ForumPostInline value) => _inlineSpan(context, value))
                .toList(growable: false),
          ),
        ),
      );
      textRun.clear();
    }

    for (final ForumPostInline inline in inlines) {
      if (inline is ForumPostImageInline && !inline.isEmoticon) {
        flushTextRun();
        if (children.isNotEmpty) {
          children.add(const SizedBox(height: 8));
        }
        children.add(
          Semantics(
            image: true,
            label: inline.alt.isEmpty ? '帖子图片' : inline.alt,
            child: ClipRRect(
              key: ValueKey<String>('forum-inline-image-${inline.uri}'),
              borderRadius: BorderRadius.circular(6),
              child: ForumImage(uri: inline.uri, referer: referer),
            ),
          ),
        );
        continue;
      }
      textRun.add(inline);
    }
    flushTextRun();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  InlineSpan _inlineSpan(BuildContext context, ForumPostInline inline) {
    return switch (inline) {
      ForumPostTextInline() => TextSpan(
        text: inline.text,
        style: _styledText(
          baseStyle,
          bold: inline.bold,
          italic: inline.italic,
          code: inline.code,
        ),
      ),
      ForumPostLineBreakInline() => const TextSpan(text: '\n'),
      ForumPostImageInline() => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Semantics(
          image: true,
          label: inline.alt.isEmpty ? '表情' : inline.alt,
          child: SizedBox(
            key: ValueKey<String>('forum-inline-emoticon-${inline.uri}'),
            width: 24,
            height: 24,
            child: ForumImage(
              uri: inline.uri,
              referer: referer,
              width: 24,
              height: 24,
            ),
          ),
        ),
      ),
      ForumPostLinkInline() => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: InkWell(
          key: ValueKey<String>(
            'forum-post-link-${inline.kind.name}-${inline.uri}',
          ),
          onTap: onOpenLink == null ? null : () => onOpenLink!(inline),
          child: Text(
            inline.label,
            style: _styledText(
              baseStyle.copyWith(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              bold: inline.bold,
              italic: inline.italic,
              code: inline.code,
            ),
          ),
        ),
      ),
    };
  }

  TextStyle _styledText(
    TextStyle base, {
    required bool bold,
    required bool italic,
    required bool code,
  }) {
    return base.copyWith(
      fontFamily: code ? 'monospace' : base.fontFamily,
      fontStyle: italic ? FontStyle.italic : base.fontStyle,
      fontWeight: bold ? FontWeight.bold : base.fontWeight,
    );
  }
}

class _ForumAttachmentView extends StatelessWidget {
  const _ForumAttachmentView({
    required this.attachment,
    required this.referer,
    required this.onOpen,
    required this.onCancel,
    required this.state,
  });

  final ForumAttachment attachment;
  final String referer;
  final VoidCallback? onOpen;
  final VoidCallback? onCancel;
  final ForumAttachmentDownloadState? state;

  @override
  Widget build(BuildContext context) {
    if (attachment.isImage) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (attachment.name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                attachment.name,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ForumImage(uri: attachment.uri, referer: referer),
          ),
          if (attachment.description.isNotEmpty ||
              attachment.sizeLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                <String>[
                  attachment.description,
                  attachment.sizeLabel,
                ].where((String value) => value.isNotEmpty).join(' · '),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
        ],
      );
    }
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        key: ValueKey<String>('forum-attachment-${attachment.uri}'),
        borderRadius: BorderRadius.circular(6),
        onTap: state?.phase == ForumAttachmentDownloadPhase.downloading
            ? null
            : onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              const Icon(Icons.attach_file, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(attachment.name.isEmpty ? '附件' : attachment.name),
                    if (attachment.description.isNotEmpty ||
                        attachment.sizeLabel.isNotEmpty)
                      Text(
                        <String>[
                          attachment.description,
                          attachment.sizeLabel,
                        ].where((String value) => value.isNotEmpty).join(' · '),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    if (state != null && state!.message.isNotEmpty)
                      Text(
                        state!.message,
                        style: TextStyle(
                          color:
                              state!.phase ==
                                  ForumAttachmentDownloadPhase.failed
                              ? Theme.of(context).colorScheme.error
                              : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (state?.phase == ForumAttachmentDownloadPhase.downloading)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          key: ValueKey<String>(
                            'forum-attachment-progress-${attachment.uri}',
                          ),
                          strokeWidth: 2,
                          value: state!.progress,
                        ),
                      ),
                      if (onCancel != null)
                        IconButton(
                          key: ValueKey<String>(
                            'forum-attachment-cancel-${attachment.uri}',
                          ),
                          padding: EdgeInsets.zero,
                          iconSize: 14,
                          tooltip: '取消下载',
                          onPressed: onCancel,
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                )
              else
                Icon(
                  state?.downloaded == null
                      ? Icons.download_outlined
                      : Icons.open_in_new,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _canOpenAuthor(
  Uri? uri,
  int? userId,
  void Function(Uri uri, int userId)? onOpenAuthor,
) {
  return onOpenAuthor != null && uri != null && (userId ?? 0) > 0;
}

class _ForumAuthorButton extends StatelessWidget {
  const _ForumAuthorButton({
    required this.author,
    required this.onPressed,
    super.key,
  });

  final String author;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: author.isEmpty ? '查看作者资料' : '查看 $author',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      iconSize: 18,
      onPressed: onPressed,
      icon: const Icon(Icons.account_circle_outlined),
    );
  }
}

String forumPlainText(String source) {
  if (source.trim().isEmpty) {
    return '';
  }
  final dom.DocumentFragment fragment = html_parser.parseFragment(source);
  final StringBuffer buffer = StringBuffer();

  void newline() {
    if (buffer.isNotEmpty && !buffer.toString().endsWith('\n')) {
      buffer.write('\n');
    }
  }

  void visit(dom.Node node) {
    if (node is dom.Text) {
      buffer.write(node.data);
      return;
    }
    if (node is! dom.Element) {
      for (final dom.Node child in node.nodes) {
        visit(child);
      }
      return;
    }
    final String tag = node.localName ?? '';
    if (const <String>{
      'script',
      'style',
      'noscript',
      'form',
      'button',
      'input',
      'select',
      'textarea',
      'iframe',
      'object',
      'embed',
    }.contains(tag)) {
      return;
    }
    if (tag == 'br') {
      newline();
      return;
    }
    final bool block = const <String>{
      'address',
      'blockquote',
      'div',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'li',
      'p',
      'pre',
      'table',
      'tr',
    }.contains(tag);
    if (block) {
      newline();
    }
    if (tag == 'li') {
      buffer.write('• ');
    }
    for (final dom.Node child in node.nodes) {
      visit(child);
    }
    if (block) {
      newline();
    }
  }

  for (final dom.Node node in fragment.nodes) {
    visit(node);
  }
  return buffer
      .toString()
      .replaceAll('\u00a0', ' ')
      .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
