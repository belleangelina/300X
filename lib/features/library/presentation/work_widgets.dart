import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/features/library/data/cover_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';

final workCoverProvider = FutureProvider.autoDispose.family<Uri?, CoverRequest>(
    (Ref ref, CoverRequest request)
    {
        final CoverRepository repository = ref.watch(coverRepositoryProvider);
        final CoverLoadCoordinator coordinator = ref.watch(
            coverLoadCoordinatorProvider,
        );
        coordinator.retain(request);
        ref.onDispose(() => coordinator.release(request));
        if (!request.finalized && request.entryTid == null)
        {
            return repository.resolve(request.work);
        }
        return repository.resolve(
            request.work,
            finalize: request.finalized,
            entryTid: request.entryTid,
        );
    },
);

class WorkTextCover extends StatelessWidget
{
    const WorkTextCover({
        required this.title,
        this.kind,
        this.width,
        this.height,
        this.borderRadius = 4,
        super.key,
    });

    final String title;
    final LibraryKind? kind;
    final double? width;
    final double? height;
    final double borderRadius;

    @override
    Widget build(BuildContext context)
    {
        final bool dark = Theme.of(context).brightness == Brightness.dark;
        final Color foreground = dark
                ? const Color(0xffd5d9de)
                : const Color(0xff49515a);
        return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints)
            {
                final double effectiveWidth = width ?? constraints.maxWidth;
                final bool compact = effectiveWidth < 100;
                return Container(
                    width: width,
                    height: height,
                    padding: EdgeInsets.all(compact ? 8 : 12),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(borderRadius),
                        color: dark
                                ? const Color(0xff30343b)
                                : const Color(0xffeef1f4),
                        border: Border.all(
                            color: dark
                                    ? const Color(0xff444a52)
                                    : const Color(0xffd9dee3),
                        ),
                    ),
                    child: Column(
                        children: <Widget>[
                            Align(
                                alignment: Alignment.topLeft,
                                child: Icon(
                                    kind == LibraryKind.comic
                                        ? Icons.auto_stories_outlined
                                        : Icons.menu_book_outlined,
                                    color: foreground.withValues(alpha: 0.5),
                                    size: compact ? 18 : 22,
                                ),
                            ),
                            const Spacer(),
                            Text(
                                title,
                                maxLines: compact ? 2 : 3,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: foreground,
                                    fontSize: compact ? 12 : 14,
                                    fontWeight: FontWeight.w500,
                                    height: 1.3,
                                ),
                            ),
                            const Spacer(),
                        ],
                    ),
                );
            },
        );
    }
}

class WorkCover extends ConsumerStatefulWidget
{
    const WorkCover({
        required this.work,
        this.width,
        this.height,
        this.borderRadius = 4,
        this.finalized = false,
        this.entryTid,
        super.key,
    });

    final Work work;
    final double? width;
    final double? height;
    final double borderRadius;
    final bool finalized;
    final int? entryTid;

    @override
    ConsumerState<WorkCover> createState()
    {
        return _WorkCoverState();
    }
}

class _WorkCoverState extends ConsumerState<WorkCover>
{
    late final CoverLoadCoordinator _loadCoordinator;
    Uri? _visibleUri;
    Uri? _reportedBrokenUri;
    bool _waitingForDisplayResume = false;

    CoverRequest get _request => CoverRequest(
        work: widget.work,
        finalized: widget.finalized,
        entryTid: widget.entryTid,
    );

    @override
    void initState()
    {
        super.initState();
        _loadCoordinator = ref.read(coverLoadCoordinatorProvider);
        _loadCoordinator.addListener(_handleLoadCoordinatorChanged);
        _visibleUri = ref.read(coverRepositoryProvider).peek(_request);
    }

    @override
    void dispose()
    {
        _loadCoordinator.removeListener(_handleLoadCoordinatorChanged);
        super.dispose();
    }

    @override
    void didUpdateWidget(covariant WorkCover oldWidget)
    {
        super.didUpdateWidget(oldWidget);
        final CoverRequest oldRequest = CoverRequest(
            work: oldWidget.work,
            finalized: oldWidget.finalized,
            entryTid: oldWidget.entryTid,
        );
        final CoverRequest request = _request;
        if (oldRequest.cacheKey == request.cacheKey)
        {
            return;
        }
        final bool sameVisualWork = oldRequest.work.kind == request.work.kind &&
                (oldRequest.sourceTid == request.sourceTid ||
                        oldRequest.work.id == request.work.id);
        final Uri? cached = ref.read(coverRepositoryProvider).peek(request);
        _visibleUri = cached ?? (sameVisualWork ? _visibleUri : null);
        _reportedBrokenUri = null;
    }

    @override
    Widget build(BuildContext context)
    {
        final CoverRequest request = _request;
        final AsyncValue<Uri?>? cover = TickerMode.valuesOf(context).enabled
                ? ref.watch(workCoverProvider(request))
                : null;
        final Uri? resolved = switch (cover)
        {
            AsyncData<Uri?>(value: final Uri? value) => value,
            _ => null,
        };
        final Uri? uri = resolved ??
                _visibleUri ??
                ref.read(coverRepositoryProvider).peek(request);
        if (resolved != null && resolved != _visibleUri)
        {
            WidgetsBinding.instance.addPostFrameCallback((_)
            {
                if (mounted && _visibleUri != resolved)
                {
                    setState(()
                    {
                        _visibleUri = resolved;
                        _reportedBrokenUri = null;
                    });
                }
            });
        }
        return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints)
            {
                final Widget fallback = WorkTextCover(
                    title: widget.work.title,
                    kind: widget.work.kind,
                    width: widget.width,
                    height: widget.height,
                    borderRadius: widget.borderRadius,
                );
                final int? cacheHeight = _cacheExtent(
                    widget.height,
                    constraints.hasBoundedHeight ? constraints.maxHeight : null,
                    MediaQuery.devicePixelRatioOf(context),
                );
                final int? cacheWidth = cacheHeight == null
                        ? _cacheExtent(
                                widget.width,
                                constraints.hasBoundedWidth
                                        ? constraints.maxWidth
                                        : null,
                                MediaQuery.devicePixelRatioOf(context),
                            )
                        : null;
                final ImageProvider<Object>? imageProvider = uri == null
                        ? null
                        : ResizeImage.resizeIfNeeded(
                                cacheWidth,
                                cacheHeight,
                                FileImage(File.fromUri(uri)),
                            );
                final bool showImage = imageProvider != null &&
                        _canDisplay(context, imageProvider);
                if (imageProvider == null)
                {
                    _waitingForDisplayResume = false;
                }
                final Widget child = !showImage
                        ? KeyedSubtree(
                                key: ValueKey<String>(
                                    'text:${widget.work.kind.name}:${widget.work.title}',
                                ),
                                child: fallback,
                            )
                        : Image(
                                image: imageProvider,
                                key: ValueKey<String>(uri.toString()),
                                width: widget.width,
                                height: widget.height,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                                errorBuilder: (
                                    BuildContext context,
                                    Object error,
                                    StackTrace? stackTrace,
                                )
                                {
                                    _reportBroken(request, uri!);
                                    return fallback;
                                },
                            );
                return SizedBox(
                    width: widget.width,
                    height: widget.height,
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(widget.borderRadius),
                        child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            layoutBuilder: (
                                Widget? currentChild,
                                List<Widget> previousChildren,
                            )
                            {
                                return Stack(
                                    fit: StackFit.expand,
                                    children: <Widget>[
                                        ...previousChildren,
                                        ?currentChild,
                                    ],
                                );
                            },
                            child: child,
                        ),
                    ),
                );
            },
        );
    }

    bool _canDisplay(
        BuildContext context,
        ImageProvider<Object> imageProvider,
    )
    {
        if (!_loadCoordinator.paused)
        {
            _waitingForDisplayResume = false;
            return true;
        }
        Object? cacheKey;
        imageProvider
            .obtainKey(createLocalImageConfiguration(context))
            .then<void>((Object value)
            {
                cacheKey = value;
            });
        final ImageCacheStatus? status = cacheKey == null
                ? null
                : PaintingBinding.instance.imageCache.statusForKey(cacheKey!);
        final bool cached = status?.tracked ?? false;
        _waitingForDisplayResume = !cached;
        return cached;
    }

    void _handleLoadCoordinatorChanged()
    {
        if (!mounted ||
                !_waitingForDisplayResume ||
                _loadCoordinator.paused)
        {
            return;
        }
        _waitingForDisplayResume = false;
        setState(() {});
    }

    int? _cacheExtent(
        double? explicitExtent,
        double? constrainedExtent,
        double devicePixelRatio,
    )
    {
        final double? logicalExtent = explicitExtent ?? constrainedExtent;
        if (logicalExtent == null || !logicalExtent.isFinite || logicalExtent <= 0)
        {
            return null;
        }
        return (logicalExtent * devicePixelRatio).ceil();
    }

    void _reportBroken(CoverRequest request, Uri uri)
    {
        if (_reportedBrokenUri == uri)
        {
            return;
        }
        _reportedBrokenUri = uri;
        WidgetsBinding.instance.addPostFrameCallback((_)
        {
            if (!mounted)
            {
                return;
            }
            ref.read(coverRepositoryProvider).reportBroken(request, uri).whenComplete(()
            {
                if (mounted)
                {
                    ref.invalidate(workCoverProvider(request));
                }
            });
        });
    }
}

class WorkListTile extends StatelessWidget
{
    const WorkListTile({
        required this.work,
        required this.onTap,
        this.rank,
        this.trailing,
        super.key,
    });

    final Work work;
    final VoidCallback? onTap;
    final int? rank;
    final Widget? trailing;

    @override
    Widget build(BuildContext context)
    {
        final SourceThread source = work.primarySourceThread;
        return InkWell(
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                        Stack(
                            clipBehavior: Clip.none,
                            children: <Widget>[
                                WorkCover(work: work, width: 80, height: 110),
                                if (rank != null)
                                    Positioned(
                                        left: -5,
                                        top: -5,
                                        child: CircleAvatar(
                                            radius: 13,
                                            backgroundColor: rank! <= 3
                                                    ? Colors.orange
                                                    : Colors.blueGrey,
                                            child: Text(
                                                '$rank',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                ),
                                            ),
                                        ),
                                    ),
                            ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: SizedBox(
                                height: 110,
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                        Text(
                                            work.title,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(height: 1.2),
                                        ),
                                        const Spacer(),
                                        _MetadataLine(
                                            icon: Icons.sell_outlined,
                                            text: <String>[
                                                if (work.typeName.isNotEmpty) work.typeName,
                                                work.chapters.length > 1
                                                        ? '${work.chapters.length} 个章节'
                                                        : work.chapters.first.title,
                                            ].join(' · '),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                            '${source.timeLabel}  '
                                            '${source.views} 浏览 · ${source.replies} 回复',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 12,
                                            ),
                                        ),
                                    ],
                                ),
                            ),
                        ),
                        const SizedBox(width: 4),
                        trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                ),
            ),
        );
    }
}

class WorkGridCard extends StatelessWidget
{
    const WorkGridCard({required this.work, required this.onTap, super.key});

    final Work work;
    final VoidCallback onTap;

    @override
    Widget build(BuildContext context)
    {
        return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                    Expanded(
                        child: SizedBox.expand(child: WorkCover(work: work)),
                    ),
                    const SizedBox(height: 7),
                    Text(
                        work.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.2),
                    ),
                    Text(
                        <String>[
                            if (work.typeName.isNotEmpty) work.typeName,
                            work.chapters.length > 1
                                    ? '${work.chapters.length}章'
                                    : work.chapters.first.title,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                            height: 1.2,
                        ),
                    ),
                ],
            ),
        );
    }
}

class _MetadataLine extends StatelessWidget
{
    const _MetadataLine({required this.icon, required this.text});

    final IconData icon;
    final String text;

    @override
    Widget build(BuildContext context)
    {
        return Row(
            children: <Widget>[
                Icon(icon, size: 16, color: Colors.grey),
                const SizedBox(width: 5),
                Expanded(
                    child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                ),
            ],
        );
    }
}
