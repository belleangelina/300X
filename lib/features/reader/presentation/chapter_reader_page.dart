import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:x300/features/downloads/data/download_repository.dart';
import 'package:x300/features/downloads/domain/download_models.dart';
import 'package:x300/features/history/application/reading_anchor.dart';
import 'package:x300/features/history/data/reading_history_repository.dart';
import 'package:x300/features/history/domain/reading_history_models.dart';
import 'package:x300/features/library/data/chapter_content_selector.dart';
import 'package:x300/features/library/data/forum_library_repository.dart';
import 'package:x300/features/library/domain/library_models.dart';
import 'package:x300/features/library/domain/thread_models.dart';
import 'package:x300/features/reader/data/reader_media_repository.dart';
import 'package:x300/features/reader/presentation/novel_paginator.dart';
import 'package:x300/features/settings/application/app_settings_controller.dart';
import 'package:x300/features/settings/domain/app_settings.dart';
import 'package:x300/shared/presentation/app_error_view.dart';
import 'package:x300/shared/presentation/app_loading_view.dart';
import 'package:x300/shared/presentation/forum_image.dart';

class ChapterReaderPage extends ConsumerStatefulWidget
{
    const ChapterReaderPage({
        required this.work,
        required this.chapter,
        this.chapters,
        this.restoreProgress = true,
        super.key,
    });

    final Work work;
    final Chapter chapter;
    final List<Chapter>? chapters;
    final bool restoreProgress;

    @override
    ConsumerState<ChapterReaderPage> createState()
    {
        return _ChapterReaderPageState();
    }
}

class _ChapterReaderPageState extends ConsumerState<ChapterReaderPage>
{
    static const ChapterContentSelector _contentSelector =
        ChapterContentSelector();
    static const NovelPaginator _novelPaginator = NovelPaginator();
    static const MethodChannel _androidSystemUiChannel = MethodChannel(
        'com.yamibox300/system_ui',
    );
    static const Duration _comicSwipeDecisionWindow = Duration(
        milliseconds: 100,
    );

    late Future<_LoadedChapter> _contentFuture;
    late Future<void> _progressFuture;
    late final ReadingHistoryRepository _historyRepository;
    late final ScrollController _scrollController;
    late final FocusNode _focusNode;
    late Chapter _chapter;
    PageController? _pageController;
    Future<List<NovelPageLayout>>? _novelPagesFuture;
    Timer? _saveTimer;
    Timer? _comicPrefetchTimer;
    ReaderDirection _flow = ReaderDirection.vertical;
    NovelReaderPalette _novelTheme = NovelReaderPalette.light;
    double _fontSize = 18;
    double _lineHeight = 1.8;
    int _pageIndex = 0;
    int _activeMaxPosition = -1;
    int _activePageCount = 1;
    List<double> _activePageAnchors = const <double>[0];
    String? _pageLayoutKey;
    String? _novelPaginationKey;
    int _novelPaginationGeneration = 0;
    double _currentProgress = 0;
    bool _scrollRestored = false;
    bool _initialHistoryWritten = false;
    bool _fullScreen = false;
    bool _controlsVisible = false;
    bool _showStatus = true;
    bool _reverseControls = false;
    bool _pageAnimation = true;
    bool _progressDragging = false;
    int _comicPreloadPages = 3;
    int _comicPrefetchGeneration = 0;
    String? _comicPrefetchKey;
    List<Uri> _activeComicImages = const <Uri>[];
    Uri? _activeComicReferer;
    final Set<int> _zoomedComicPages = <int>{};
    final Set<int> _activeReaderPointers = <int>{};
    int? _sideTapPointer;
    Offset? _sideTapOrigin;
    int? _sideTapOffset;
    double _sideTapSlop = kTouchSlop;
    bool _sideTapCancelled = false;
    Timer? _comicSwipeDecisionTimer;
    int? _comicSwipePointer;
    int? _comicSwipeStartPage;
    Offset? _comicSwipeOrigin;
    Offset? _comicSwipeOriginLocalPosition;
    Offset? _comicSwipeLastPosition;
    Offset? _comicSwipeLastLocalPosition;
    Offset? _comicSwipeDispatchedPosition;
    Duration? _comicSwipeLastTimeStamp;
    PointerDeviceKind? _comicSwipeKind;
    VelocityTracker? _comicSwipeVelocityTracker;
    Drag? _comicPageDrag;
    bool _comicSwipeReady = false;
    bool _comicSwipeBlocked = false;

    @override
    void initState()
    {
        super.initState();
        _chapter = widget.chapter;
        final AppSettings settings = ref.read(
            appSettingsControllerProvider,
        );
        final bool comic = widget.work.kind == LibraryKind.comic;
        _flow = comic
            ? settings.comicDirection
            : settings.novelDirection;
        _novelTheme = settings.novelPalette;
        _fontSize = settings.novelFontSize;
        _lineHeight = settings.novelLineHeight;
        _fullScreen = comic && settings.comicFullScreen;
        _controlsVisible = false;
        if (_fullScreen)
        {
            unawaited(_setImmersiveMode(true));
        }
        _showStatus = comic
            ? settings.comicShowStatus
            : settings.novelShowStatus;
        _reverseControls = comic
            ? settings.comicReverseControls
            : settings.novelReverseControls;
        _pageAnimation = comic
            ? settings.comicPageAnimation
            : settings.novelPageAnimation;
        _comicPreloadPages = settings.comicPreloadPages;
        _historyRepository = ref.read(readingHistoryRepositoryProvider);
        _scrollController = ScrollController()..addListener(_handleVerticalScroll);
        _focusNode = FocusNode(debugLabel: 'chapter-reader');
        _contentFuture = _load();
        _progressFuture = widget.restoreProgress
                ? _restoreProgress()
                : Future<void>.value();
    }

    @override
    void dispose()
    {
        _novelPaginationGeneration++;
        if (_fullScreen)
        {
            unawaited(_setImmersiveMode(false));
        }
        _saveTimer?.cancel();
        _comicPrefetchTimer?.cancel();
        _cancelComicSwipe(resetPage: false);
        _comicPrefetchGeneration++;
        unawaited(_saveProgress());
        _scrollController
            ..removeListener(_handleVerticalScroll)
            ..dispose();
        _pageController?.dispose();
        _focusNode.dispose();
        super.dispose();
    }

    Future<void> _setImmersiveMode(bool enabled) async
    {
        if (Platform.isAndroid)
        {
            await _androidSystemUiChannel.invokeMethod<void>(
                'setImmersive',
                enabled,
            );
            if (!enabled)
            {
                await SystemChrome.setEnabledSystemUIMode(
                    SystemUiMode.edgeToEdge,
                );
            }
        }
        else if (Platform.isIOS)
        {
            await SystemChrome.setEnabledSystemUIMode(
                enabled
                    ? SystemUiMode.immersiveSticky
                    : SystemUiMode.edgeToEdge,
            );
        }
    }

    @override
    Widget build(BuildContext context)
    {
        final bool comic = widget.work.kind == LibraryKind.comic;
        return KeyboardListener(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _handleKeyEvent,
            child: Scaffold(
                backgroundColor: comic ? Colors.black : _readerBackground,
                body: Stack(
                    children: <Widget>[
                        Positioned.fill(
                            child: LayoutBuilder(
                                builder: (
                                    BuildContext context,
                                    BoxConstraints constraints,
                                ) => GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onTapUp: (TapUpDetails details)
                                    {
                                        final double left =
                                                constraints.maxWidth * 0.3;
                                        final double right =
                                                constraints.maxWidth * 0.7;
                                        if (details.localPosition.dx > left &&
                                                details.localPosition.dx < right)
                                        {
                                            _toggleControls();
                                        }
                                    },
                                    child: _buildContent(comic),
                                ),
                            ),
                        ),
                        Positioned.fill(child: _buildTapZones()),
                        _buildTopControls(comic),
                        _buildBottomControls(comic),
                    ],
                ),
            ),
        );
    }

    Widget _buildContent(bool comic)
    {
        return FutureBuilder<_LoadedChapter>(
            future: _contentFuture,
            builder: (
                BuildContext context,
                AsyncSnapshot<_LoadedChapter> snapshot,
            )
            {
                if (snapshot.connectionState != ConnectionState.done)
                {
                    return const AppLoadingView(message: '正在加载章节');
                }
                if (snapshot.hasError)
                {
                    return AppErrorView(
                        message: snapshot.error.toString(),
                        onRetry: _retry,
                    );
                }
                final _LoadedChapter content = snapshot.data!;
                if (content.blocks.isEmpty)
                {
                    return AppErrorView(
                        message: '没有找到这一章节的正文，可能受论坛权限限制',
                        onRetry: () => _confirmOpenOriginal(_chapter.sourceUri),
                    );
                }
                return FutureBuilder<void>(
                    future: _progressFuture,
                    builder: (
                        BuildContext context,
                        AsyncSnapshot<void> progressSnapshot,
                    )
                    {
                        if (progressSnapshot.connectionState !=
                            ConnectionState.done)
                        {
                            return const AppLoadingView(
                                message: '正在恢复阅读位置',
                            );
                        }
                        return comic
                            ? _buildComic(content.blocks, content.referer)
                            : _buildNovel(content.blocks, content.referer);
                    },
                );
            },
        );
    }

    Widget _buildTapZones()
    {
        final bool leftIsNext = _reverseControls;
        final bool comicZoomed = widget.work.kind == LibraryKind.comic &&
                _zoomedComicPages.contains(_pageIndex);
        return IgnorePointer(
            ignoring: comicZoomed,
            child: LayoutBuilder(
                builder: (
                    BuildContext context,
                    BoxConstraints constraints,
                ) => Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (PointerDownEvent event) =>
                        _handleReaderPointerDown(
                            event,
                            width: constraints.maxWidth,
                        ),
                    onPointerMove: _handleReaderPointerMove,
                    onPointerUp: _handleReaderPointerUp,
                    onPointerCancel: _handleReaderPointerCancel,
                    child: Row(
                        children: <Widget>[
                            Expanded(
                                flex: 3,
                                child: Semantics(
                                    label: leftIsNext
                                            ? '下一页区域'
                                            : '上一页区域',
                                    button: true,
                                    onTap: () => _turnPage(
                                        leftIsNext ? 1 : -1,
                                    ),
                                    child: const Listener(
                                        key: Key('reader-left-page-area'),
                                        behavior: HitTestBehavior.translucent,
                                        child: SizedBox.expand(),
                                    ),
                                ),
                            ),
                            const Spacer(flex: 4),
                            Expanded(
                                flex: 3,
                                child: Semantics(
                                    label: leftIsNext
                                            ? '上一页区域'
                                            : '下一页区域',
                                    button: true,
                                    onTap: () => _turnPage(
                                        leftIsNext ? -1 : 1,
                                    ),
                                    child: const Listener(
                                        key: Key('reader-right-page-area'),
                                        behavior: HitTestBehavior.translucent,
                                        child: SizedBox.expand(),
                                    ),
                                ),
                            ),
                        ],
                    ),
                ),
            ),
        );
    }

    void _handleReaderPointerDown(
        PointerDownEvent event, {
        required double width,
    })
    {
        _activeReaderPointers.add(event.pointer);
        if (_activeReaderPointers.length != 1)
        {
            _sideTapCancelled = true;
            _blockComicSwipe();
            return;
        }
        _beginComicSwipe(event);
        final int? offset = event.localPosition.dx <= width * 0.3
                ? (_reverseControls ? 1 : -1)
                : event.localPosition.dx >= width * 0.7
                ? (_reverseControls ? -1 : 1)
                : null;
        if (offset == null || event.buttons != kPrimaryButton)
        {
            return;
        }
        _sideTapPointer = event.pointer;
        _sideTapOrigin = event.localPosition;
        _sideTapOffset = offset;
        _sideTapSlop = event.kind == PointerDeviceKind.mouse ||
                event.kind == PointerDeviceKind.trackpad
            ? kPrecisePointerHitSlop
            : kTouchSlop;
        _sideTapCancelled = false;
    }

    void _handleReaderPointerMove(PointerMoveEvent event)
    {
        final Offset? origin = _sideTapOrigin;
        if (event.pointer == _sideTapPointer && origin != null &&
                (event.localPosition - origin).distance > _sideTapSlop)
        {
            _sideTapCancelled = true;
        }
        _updateComicSwipe(event);
    }

    void _handleReaderPointerUp(PointerUpEvent event)
    {
        final bool candidate = event.pointer == _sideTapPointer;
        final int? offset = _sideTapOffset;
        final bool shouldTurn = candidate &&
                !_sideTapCancelled &&
                _activeReaderPointers.length == 1 &&
                offset != null;
        _endComicSwipe(event);
        _activeReaderPointers.remove(event.pointer);
        if (candidate || _activeReaderPointers.isEmpty)
        {
            _resetSideTap();
        }
        if (_activeReaderPointers.isEmpty)
        {
            _comicSwipeBlocked = false;
        }
        if (shouldTurn)
        {
            _turnPage(offset);
        }
    }

    void _handleReaderPointerCancel(PointerCancelEvent event)
    {
        _cancelComicSwipePointer(event.pointer);
        _activeReaderPointers.remove(event.pointer);
        if (event.pointer == _sideTapPointer || _activeReaderPointers.isEmpty)
        {
            _resetSideTap();
        }
        if (_activeReaderPointers.isEmpty)
        {
            _comicSwipeBlocked = false;
        }
    }

    void _resetSideTap()
    {
        _sideTapPointer = null;
        _sideTapOrigin = null;
        _sideTapOffset = null;
        _sideTapCancelled = false;
    }

    void _beginComicSwipe(PointerDownEvent event)
    {
        final PageController? controller = _pageController;
        if (_comicSwipeBlocked ||
                widget.work.kind != LibraryKind.comic ||
                _flow == ReaderDirection.vertical ||
                _zoomedComicPages.contains(_pageIndex) ||
                event.buttons != kPrimaryButton ||
                controller == null ||
                !controller.hasClients)
        {
            return;
        }
        _cancelComicSwipe(resetPage: false);
        _comicSwipePointer = event.pointer;
        _comicSwipeStartPage = _pageIndex;
        _comicSwipeOrigin = event.position;
        _comicSwipeOriginLocalPosition = event.localPosition;
        _comicSwipeLastPosition = event.position;
        _comicSwipeLastLocalPosition = event.localPosition;
        _comicSwipeDispatchedPosition = event.position;
        _comicSwipeLastTimeStamp = event.timeStamp;
        _comicSwipeKind = event.kind;
        _comicSwipeVelocityTracker = VelocityTracker.withKind(event.kind)
            ..addPosition(event.timeStamp, event.position);
        if (event.kind == PointerDeviceKind.touch)
        {
            _comicSwipeDecisionTimer = Timer(
                _comicSwipeDecisionWindow,
                ()
                {
                    _comicSwipeReady = true;
                    _tryStartComicSwipe();
                },
            );
        }
        else
        {
            _comicSwipeReady = true;
        }
    }

    void _updateComicSwipe(PointerMoveEvent event)
    {
        final Offset? origin = _comicSwipeOrigin;
        if (event.pointer != _comicSwipePointer ||
                origin == null ||
                _comicSwipeBlocked)
        {
            return;
        }
        _comicSwipeVelocityTracker?.addPosition(
            event.timeStamp,
            event.position,
        );
        _comicSwipeLastPosition = event.position;
        _comicSwipeLastLocalPosition = event.localPosition;
        _comicSwipeLastTimeStamp = event.timeStamp;
        final Offset movement = event.position - origin;
        final double slop = event.kind == PointerDeviceKind.mouse
            ? kPrecisePointerHitSlop
            : kTouchSlop;
        if (_comicPageDrag == null &&
                movement.dy.abs() > slop &&
                movement.dy.abs() > movement.dx.abs())
        {
            _cancelComicSwipe(resetPage: false);
            return;
        }
        final bool started = _comicPageDrag == null &&
                _tryStartComicSwipe();
        if (!started && _comicPageDrag != null)
        {
            _dispatchComicSwipeUpdate();
        }
    }

    bool _tryStartComicSwipe()
    {
        final Offset? origin = _comicSwipeOrigin;
        final Offset? localOrigin = _comicSwipeOriginLocalPosition;
        final Offset? position = _comicSwipeLastPosition;
        final PageController? controller = _pageController;
        if (!_comicSwipeReady ||
                _comicSwipeBlocked ||
                _comicPageDrag != null ||
                origin == null ||
                localOrigin == null ||
                position == null ||
                controller == null ||
                !controller.hasClients)
        {
            return false;
        }
        final Offset movement = position - origin;
        final double slop = _comicSwipeKind == PointerDeviceKind.mouse
            ? kPrecisePointerHitSlop
            : kTouchSlop;
        if (movement.dx.abs() <= slop ||
                movement.dx.abs() <= movement.dy.abs())
        {
            return false;
        }
        late final Drag drag;
        drag = controller.position.drag(
            DragStartDetails(
                globalPosition: origin,
                localPosition: localOrigin,
                sourceTimeStamp: _comicSwipeLastTimeStamp,
                kind: _comicSwipeKind,
            ),
            ()
            {
                if (identical(_comicPageDrag, drag))
                {
                    _comicPageDrag = null;
                }
            },
        );
        _comicPageDrag = drag;
        _dispatchComicSwipeUpdate();
        return true;
    }

    void _dispatchComicSwipeUpdate()
    {
        final Drag? drag = _comicPageDrag;
        final Offset? position = _comicSwipeLastPosition;
        final Offset? localPosition = _comicSwipeLastLocalPosition;
        final Offset? previous = _comicSwipeDispatchedPosition;
        if (drag == null ||
                position == null ||
                localPosition == null ||
                previous == null)
        {
            return;
        }
        final double delta = position.dx - previous.dx;
        _comicSwipeDispatchedPosition = position;
        if (delta == 0)
        {
            return;
        }
        drag.update(
            DragUpdateDetails(
                globalPosition: position,
                localPosition: localPosition,
                sourceTimeStamp: _comicSwipeLastTimeStamp,
                delta: Offset(delta, 0),
                primaryDelta: delta,
                kind: _comicSwipeKind,
            ),
        );
    }

    void _endComicSwipe(PointerUpEvent event)
    {
        if (event.pointer != _comicSwipePointer)
        {
            return;
        }
        _comicSwipeVelocityTracker?.addPosition(
            event.timeStamp,
            event.position,
        );
        _comicSwipeLastPosition = event.position;
        _comicSwipeLastLocalPosition = event.localPosition;
        _comicSwipeLastTimeStamp = event.timeStamp;
        if (!_comicSwipeBlocked && _comicPageDrag == null)
        {
            _comicSwipeReady = true;
            _tryStartComicSwipe();
        }
        final Drag? drag = _comicPageDrag;
        final Velocity velocity = _comicSwipeVelocityTracker?.getVelocity() ??
                Velocity.zero;
        _clearComicSwipe();
        if (drag != null && !_comicSwipeBlocked)
        {
            final double horizontal = velocity.pixelsPerSecond.dx;
            drag.end(
                DragEndDetails(
                    globalPosition: event.position,
                    localPosition: event.localPosition,
                    velocity: Velocity(
                        pixelsPerSecond: Offset(horizontal, 0),
                    ),
                    primaryVelocity: horizontal,
                ),
            );
        }
        else
        {
            drag?.cancel();
        }
    }

    void _blockComicSwipe()
    {
        _comicSwipeBlocked = true;
        _cancelComicSwipe(resetPage: true);
    }

    void _cancelComicSwipePointer(int pointer)
    {
        if (pointer == _comicSwipePointer)
        {
            _cancelComicSwipe(resetPage: false);
        }
    }

    void _cancelComicSwipe({required bool resetPage})
    {
        final Drag? drag = _comicPageDrag;
        final int? startPage = _comicSwipeStartPage;
        _clearComicSwipe();
        drag?.cancel();
        final PageController? controller = _pageController;
        if (resetPage &&
                startPage != null &&
                controller != null &&
                controller.hasClients)
        {
            controller.jumpToPage(startPage);
        }
    }

    void _clearComicSwipe()
    {
        _comicSwipeDecisionTimer?.cancel();
        _comicSwipeDecisionTimer = null;
        _comicSwipePointer = null;
        _comicSwipeStartPage = null;
        _comicSwipeOrigin = null;
        _comicSwipeOriginLocalPosition = null;
        _comicSwipeLastPosition = null;
        _comicSwipeLastLocalPosition = null;
        _comicSwipeDispatchedPosition = null;
        _comicSwipeLastTimeStamp = null;
        _comicSwipeKind = null;
        _comicSwipeVelocityTracker = null;
        _comicPageDrag = null;
        _comicSwipeReady = false;
    }

    Widget _buildTopControls(bool comic)
    {
        final Color foreground = comic ? Colors.white : _readerForeground;
        return Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedSlide(
                    offset: _controlsVisible
                        ? Offset.zero
                        : const Offset(0, -1),
                    duration: const Duration(milliseconds: 120),
                    child: Material(
                        key: const Key('reader-top-controls'),
                        color: _readerControlsBackground(comic),
                        child: SafeArea(
                            bottom: false,
                            child: SizedBox(
                                height: 56,
                                child: IconTheme(
                                    data: IconThemeData(color: foreground),
                                    child: Row(
                                        children: <Widget>[
                                            IconButton(
                                                tooltip: '返回',
                                                onPressed: () => Navigator.of(
                                                    context,
                                                ).maybePop(),
                                                icon: const Icon(Icons.arrow_back),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                                child: Text(
                                                    _chapter.title,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                        color: foreground,
                                                        fontSize: 16,
                                                    ),
                                                ),
                                            ),
                                            IconButton(
                                                key: const Key(
                                                    'reader-refresh-button',
                                                ),
                                                tooltip: '刷新',
                                                onPressed: _refresh,
                                                icon: const Icon(Icons.refresh),
                                            ),
                                            const SizedBox(width: 4),
                                        ],
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        );
    }

    Widget _buildBottomControls(bool comic)
    {
        final Color foreground = comic ? Colors.white : _readerForeground;
        return Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedSlide(
                    offset: _controlsVisible
                        ? Offset.zero
                        : const Offset(0, 1),
                    duration: const Duration(milliseconds: 120),
                    child: Material(
                        key: const Key('reader-bottom-controls'),
                        color: _readerControlsBackground(comic),
                        child: SafeArea(
                            top: false,
                            child: Center(
                                child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                        maxWidth: 500,
                                    ),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                            SizedBox(
                                                height: 46,
                                                child: Row(
                                                    children: <Widget>[
                                                        IconButton(
                                                            key: const Key(
                                                                'reader-previous-chapter',
                                                            ),
                                                            tooltip: '上一章',
                                                            color: foreground,
                                                            disabledColor:
                                                                    foreground.withValues(
                                                                alpha: 0.35,
                                                            ),
                                                            visualDensity:
                                                                VisualDensity.compact,
                                                            onPressed:
                                                                _hasPreviousChapter
                                                                    ? () =>
                                                                        _changeChapter(
                                                                            -1,
                                                                        )
                                                                    : null,
                                                            icon: const Icon(
                                                                Icons.skip_previous,
                                                            ),
                                                        ),
                                                        Expanded(
                                                            child: Slider(
                                                                key: const Key(
                                                                    'reader-progress-slider',
                                                                ),
                                                                value:
                                                                    _currentProgress.clamp(
                                                                        0.0,
                                                                        1.0,
                                                                    ),
                                                                onChanged:
                                                                    _jumpToProgress,
                                                                onChangeStart:
                                                                    _beginProgressDrag,
                                                                onChangeEnd:
                                                                    _endProgressDrag,
                                                            ),
                                                        ),
                                                        if (comic ||
                                                                _flow != ReaderDirection.vertical)
                                                            SizedBox(
                                                                key: const Key(
                                                                    'reader-control-page-count',
                                                                ),
                                                                width: 52,
                                                                child: Text(
                                                                    '${(_flow == ReaderDirection.vertical ? _pageForProgress(_currentProgress) + 1 : _pageIndex + 1).clamp(1, _activePageCount)}/$_activePageCount',
                                                                    textAlign: TextAlign.center,
                                                                    style: TextStyle(
                                                                        color: foreground,
                                                                        fontSize: 12,
                                                                    ),
                                                                ),
                                                            ),
                                                        IconButton(
                                                            key: const Key(
                                                                'reader-next-chapter',
                                                            ),
                                                            tooltip: '下一章',
                                                            color: foreground,
                                                            disabledColor:
                                                                    foreground.withValues(
                                                                alpha: 0.35,
                                                            ),
                                                            visualDensity:
                                                                VisualDensity.compact,
                                                            onPressed: _hasNextChapter
                                                                ? () => _changeChapter(
                                                                    1,
                                                                )
                                                                : null,
                                                            icon: const Icon(
                                                                Icons.skip_next,
                                                            ),
                                                        ),
                                                    ],
                                                ),
                                            ),
                                            TextButtonTheme(
                                                data: TextButtonThemeData(
                                                    style: TextButton.styleFrom(
                                                        foregroundColor: foreground,
                                                    ),
                                                ),
                                                child: IconTheme(
                                                    data: IconThemeData(
                                                        color: foreground,
                                                    ),
                                                    child: Row(
                                                        children: <Widget>[
                                                            Expanded(
                                                                child: TextButton.icon(
                                                                    key: const Key(
                                                                        'reader-original-button',
                                                                    ),
                                                                    onPressed:
                                                                        _confirmOpenOriginal,
                                                                    icon: const Icon(
                                                                        Icons.open_in_browser,
                                                                    ),
                                                                    label: const Text(
                                                                        '原帖',
                                                                    ),
                                                                ),
                                                            ),
                                                            Expanded(
                                                                child: TextButton.icon(
                                                                    key: const Key(
                                                                        'reader-directory-button',
                                                                    ),
                                                                    onPressed:
                                                                        _showChapterDirectory,
                                                                    icon: const Icon(
                                                                        Icons.list,
                                                                    ),
                                                                    label: const Text(
                                                                        '目录',
                                                                    ),
                                                                ),
                                                            ),
                                                            Expanded(
                                                                child: TextButton.icon(
                                                                    key: const Key(
                                                                        'reader-settings-button',
                                                                    ),
                                                                    onPressed: () =>
                                                                        _showReaderSettings(
                                                                            comic,
                                                                        ),
                                                                    icon: const Icon(
                                                                        Icons.tune,
                                                                    ),
                                                                    label: const Text(
                                                                        '设置',
                                                                    ),
                                                                ),
                                                            ),
                                                        ],
                                                    ),
                                                ),
                                            ),
                                        ],
                                    ),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        );
    }

    List<Chapter> get _chapters
    {
        final List<Chapter> values = widget.chapters ?? widget.work.chapters;
        return values.isEmpty ? <Chapter>[_chapter] : values;
    }

    int get _chapterIndex
    {
        final int index = _chapters.indexWhere(
            (Chapter value) => value.id == _chapter.id,
        );
        return index < 0 ? 0 : index;
    }

    bool get _hasPreviousChapter => _chapterIndex > 0;

    bool get _hasNextChapter => _chapterIndex + 1 < _chapters.length;

    Future<_LoadedChapter> _load({bool forceReload = false}) async
    {
        final OfflineChapterContent? offline = await ref
                .read(downloadRepositoryProvider)
                .loadOfflineContent(widget.work.id, _chapter.id);
        if (offline != null)
        {
            return _LoadedChapter(blocks: offline.blocks, referer: offline.referer);
        }
        final ForumLibraryRepository repository = ref.read(
            forumLibraryRepositoryProvider,
        );
        final ForumThreadPage page = forceReload
                ? await repository.loadChapterPage(
                    _chapter,
                    widget.work.primaryBoard,
                    forceReload: true,
                )
                : await repository.loadChapterPage(
                    _chapter,
                    widget.work.primaryBoard,
                );
        return _LoadedChapter(
            blocks: _contentSelector.select(page, _chapter),
            referer: page.uri,
        );
    }

    Future<void> _restoreProgress() async
    {
        try
        {
            final ReadingHistoryEntry? entry = await _historyRepository.get(
                widget.work.id,
            );
            if (entry?.chapterId == _chapter.id)
            {
                _currentProgress = entry!.progress.clamp(0.0, 1.0);
            }
        }
        on Object
        {
            _currentProgress = 0;
        }
    }

    Widget _buildComic(List<PostContentBlock> blocks, Uri referer)
    {
        final List<Uri> images = blocks
                .whereType<PostImageBlock>()
                .map((PostImageBlock block) => block.uri)
                .toList(growable: false);
        _activeComicImages = images;
        _activeComicReferer = referer;
        if (images.isEmpty)
        {
            return _PermissionFallback(
                text: blocks
                        .whereType<PostTextBlock>()
                        .map((PostTextBlock block) => block.text)
                        .join('\n\n'),
                onOpenOriginal: () => _confirmOpenOriginal(_chapter.sourceUri),
            );
        }
        if (_flow == ReaderDirection.vertical)
        {
            _configureContent(
                maxPosition: images.length - 1,
                pageCount: images.length,
                restoreVertical: true,
            );
            return Stack(
                children: <Widget>[
                    ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.zero,
                        itemCount: images.length,
                        itemBuilder: (BuildContext context, int index) => ForumImage(
                            uri: images[index],
                            referer: referer.toString(),
                            width: double.infinity,
                            fit: BoxFit.fitWidth,
                        ),
                    ),
                    if (_showStatus)
                        Positioned(
                            right: 12,
                            bottom: 12,
                            child: _ProgressBadge(
                                progress: _currentProgress,
                                background: Colors.transparent,
                            ),
                        ),
                ],
            );
        }
        _configureContent(
            maxPosition: images.length - 1,
            pageCount: images.length,
        );
        final PageController controller = _pageControllerFor(images.length);
        if (!_progressDragging)
        {
            _scheduleComicPrefetch(images, referer, _pageIndex);
        }
        return Stack(
            children: <Widget>[
                PageView.builder(
                    controller: controller,
                    physics: const NeverScrollableScrollPhysics(
                        parent: PageScrollPhysics(),
                    ),
                    reverse: _flow == ReaderDirection.rightToLeft,
                    itemCount: images.length,
                    onPageChanged: (int value)
                    {
                        setState(()
                        {
                            _pageIndex = value;
                            _currentProgress = ReadingAnchor.progressForPage(
                                value,
                                images.length,
                            );
                        });
                        _scheduleSave();
                        if (!_progressDragging)
                        {
                            _scheduleComicPrefetch(images, referer, value);
                        }
                    },
                    itemBuilder: (BuildContext context, int index) =>
                        _ZoomableComicPage(
                            key: ValueKey<String>(
                                '${_chapter.id}:${images[index]}',
                            ),
                            pageKey: Key('reader-comic-page-$index'),
                            centerChild: true,
                            onZoomChanged: (bool zoomed) =>
                                _handleComicZoomChanged(index, zoomed),
                            child: ForumImage(
                                uri: images[index],
                                referer: referer.toString(),
                            ),
                        ),
                ),
                if (_showStatus)
                    Positioned(
                        right: 12,
                        bottom: 12,
                        child: _PageBadge(
                            current: _pageIndex + 1,
                            total: images.length,
                            background: Colors.transparent,
                        ),
                    ),
            ],
        );
    }

    Widget _buildNovel(List<PostContentBlock> blocks, Uri referer)
    {
        if (_flow == ReaderDirection.vertical)
        {
            _configureContent(
                maxPosition: _novelCharacterCount(blocks),
                pageCount: 1,
                restoreVertical: true,
            );
            return Stack(
                children: <Widget>[
                    ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 48),
                        itemCount: blocks.length,
                        itemBuilder: (BuildContext context, int index) =>
                            _buildNovelBlock(blocks[index], referer),
                    ),
                    if (_showStatus)
                        Positioned(
                            right: 12,
                            bottom: 12,
                            child: _ProgressBadge(
                                progress: _currentProgress,
                                foreground: _readerForeground,
                                background: Colors.transparent,
                            ),
                        ),
                ],
            );
        }

        return LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints)
            {
                final TextDirection textDirection = Directionality.of(context);
                final TextStyle baseStyle =
                    Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
                final TextScaler textScaler = MediaQuery.textScalerOf(context);
                final String layoutKey = <Object>[
                    _chapter.id,
                    identityHashCode(blocks),
                    constraints.maxWidth.toStringAsFixed(1),
                    constraints.maxHeight.toStringAsFixed(1),
                    _fontSize.toStringAsFixed(1),
                    _lineHeight.toStringAsFixed(2),
                    textDirection,
                    baseStyle.hashCode,
                    textScaler.scale(10).toStringAsFixed(3),
                ].join('|');
                final Future<List<NovelPageLayout>> pagesFuture =
                    _novelPagesFor(
                        layoutKey: layoutKey,
                        blocks: blocks,
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        textDirection: textDirection,
                        baseStyle: baseStyle,
                        textScaler: textScaler,
                    );
                return FutureBuilder<List<NovelPageLayout>>(
                    future: pagesFuture,
                    builder: (
                        BuildContext context,
                        AsyncSnapshot<List<NovelPageLayout>> snapshot,
                    )
                    {
                        if (snapshot.connectionState != ConnectionState.done)
                        {
                            return const AppLoadingView(message: '正在排版本章');
                        }
                        if (snapshot.hasError)
                        {
                            return AppErrorView(
                                message: '章节排版失败：${snapshot.error}',
                                onRetry: _retryNovelPagination,
                            );
                        }
                        final List<NovelPageLayout> pages = snapshot.data!;
                        return _buildNovelPages(
                            pages: pages,
                            blocks: blocks,
                            referer: referer,
                            constraints: constraints,
                            layoutKey: layoutKey,
                        );
                    },
                );
            },
        );
    }

    Future<List<NovelPageLayout>> _novelPagesFor({
        required String layoutKey,
        required List<PostContentBlock> blocks,
        required double width,
        required double height,
        required TextDirection textDirection,
        required TextStyle baseStyle,
        required TextScaler textScaler,
    })
    {
        final Future<List<NovelPageLayout>>? existing = _novelPagesFuture;
        if (_novelPaginationKey == layoutKey && existing != null)
        {
            return existing;
        }
        final int generation = ++_novelPaginationGeneration;
        _novelPaginationKey = layoutKey;
        return _novelPagesFuture = _novelPaginator.paginateIncrementally(
            blocks: blocks,
            width: width,
            height: height,
            fontSize: _fontSize,
            lineHeight: _lineHeight,
            textDirection: textDirection,
            baseStyle: baseStyle,
            textScaler: textScaler,
            isCancelled: () =>
                !mounted || generation != _novelPaginationGeneration,
        );
    }

    Widget _buildNovelPages({
        required List<NovelPageLayout> pages,
        required List<PostContentBlock> blocks,
        required Uri referer,
        required BoxConstraints constraints,
        required String layoutKey,
    })
    {
        final int characters = _novelCharacterCount(blocks);
        final List<double> anchors = pages
            .asMap()
            .entries
            .map(
                (MapEntry<int, NovelPageLayout> entry) => characters <= 0
                    ? ReadingAnchor.progressForPage(entry.key, pages.length)
                    : (entry.value.startCharacter / characters).clamp(0.0, 1.0),
            )
            .toList(growable: false);
        _configureContent(
            maxPosition: characters,
            pageCount: pages.length,
            pageAnchors: anchors,
        );
        return Stack(
            children: <Widget>[
                PageView.builder(
                    controller: _pageControllerFor(
                        pages.length,
                        layoutKey: layoutKey,
                    ),
                    reverse: _flow == ReaderDirection.rightToLeft,
                    itemCount: pages.length,
                    onPageChanged: (int value)
                    {
                        setState(()
                        {
                            _pageIndex = value;
                            _currentProgress = anchors[value];
                        });
                        _scheduleSave();
                    },
                    itemBuilder: (BuildContext context, int index) => Padding(
                        padding: NovelPaginator.contentPadding,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: pages[index].blocks
                                .asMap()
                                .entries
                                .map(
                                    (MapEntry<int, PostContentBlock> entry) =>
                                        KeyedSubtree(
                                            key: Key(
                                                'reader-novel-page-block-'
                                                '${entry.key}',
                                            ),
                                            child: _buildNovelBlock(
                                                entry.value,
                                                referer,
                                                imageMaxHeight:
                                                    constraints.maxHeight * 0.65,
                                            ),
                                        ),
                                )
                                .toList(growable: false),
                        ),
                    ),
                ),
                if (_showStatus)
                    Positioned(
                        right: 12,
                        bottom: 12,
                        child: _PageBadge(
                            current: _pageIndex + 1,
                            total: pages.length,
                            foreground: _readerForeground,
                            background: Colors.transparent,
                        ),
                    ),
            ],
        );
    }

    void _invalidateNovelPagination()
    {
        _novelPaginationGeneration++;
        _novelPaginationKey = null;
        _novelPagesFuture = null;
    }

    void _retryNovelPagination()
    {
        setState(_invalidateNovelPagination);
    }

    Widget _buildNovelBlock(
        PostContentBlock block,
        Uri referer, {
        double? imageMaxHeight,
    })
    {
        return switch (block)
        {
            PostTextBlock() => Padding(
                padding: EdgeInsets.only(bottom: block.heading ? 18 : 14),
                child: Text(
                    block.text,
                    style: (Theme.of(context).textTheme.bodyMedium ??
                            const TextStyle()).copyWith(
                        color: _readerForeground,
                        fontSize: block.heading ? _fontSize + 3 : _fontSize,
                        height: _lineHeight,
                        fontWeight: block.heading ? FontWeight.bold : FontWeight.normal,
                        decoration: TextDecoration.none,
                        decorationColor: Colors.transparent,
                    ),
                ),
            ),
            PostImageBlock() => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ForumImage(
                    uri: block.uri,
                    referer: referer.toString(),
                    width: double.infinity,
                    height: imageMaxHeight,
                    fit: BoxFit.contain,
                ),
            ),
        };
    }

    int _novelCharacterCount(List<PostContentBlock> blocks)
    {
        return blocks.whereType<PostTextBlock>().fold<int>(
            0,
            (int total, PostTextBlock block) => total + block.text.length,
        );
    }

    PageController _pageControllerFor(
        int pageCount, {
        String? layoutKey,
    })
    {
        final PageController? existing = _pageController;
        if (existing != null &&
            (layoutKey == null || layoutKey == _pageLayoutKey))
        {
            return existing;
        }
        if (existing != null)
        {
            WidgetsBinding.instance.addPostFrameCallback(
                (Duration timeStamp) => existing.dispose(),
            );
        }
        _pageLayoutKey = layoutKey;
        _pageIndex = _pageForProgress(_currentProgress);
        return _pageController = PageController(initialPage: _pageIndex);
    }

    int _pageForProgress(double progress)
    {
        if (_activePageAnchors.length != _activePageCount)
        {
            return ReadingAnchor.pageForProgress(
                progress,
                _activePageCount,
            );
        }
        int result = 0;
        for (int index = 0; index < _activePageAnchors.length; index++)
        {
            if (_activePageAnchors[index] <= progress)
            {
                result = index;
            }
            else
            {
                break;
            }
        }
        return result.clamp(0, _activePageCount - 1);
    }

    void _configureContent({
        required int maxPosition,
        required int pageCount,
        List<double>? pageAnchors,
        bool restoreVertical = false,
    })
    {
        final int previousPageCount = _activePageCount;
        _activeMaxPosition = maxPosition < 0 ? 0 : maxPosition;
        _activePageCount = pageCount < 1 ? 1 : pageCount;
        _activePageAnchors = pageAnchors ?? List<double>.generate(
            _activePageCount,
            (int index) => ReadingAnchor.progressForPage(
                index,
                _activePageCount,
            ),
            growable: false,
        );
        if (previousPageCount != _activePageCount && _controlsVisible)
        {
            WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp)
            {
                if (mounted)
                {
                    setState(()
                    {
                    });
                }
            });
        }
        if (!_initialHistoryWritten)
        {
            _initialHistoryWritten = true;
            WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp)
            {
                if (mounted)
                {
                    unawaited(_saveProgress());
                }
            });
        }
        if (restoreVertical && !_scrollRestored)
        {
            WidgetsBinding.instance.addPostFrameCallback(
                (Duration timeStamp) => _restoreVerticalScroll(),
            );
        }
    }

    void _restoreVerticalScroll()
    {
        if (!mounted || !_scrollController.hasClients || _scrollRestored)
        {
            return;
        }
        _scrollRestored = true;
        final double target =
                _scrollController.position.maxScrollExtent * _currentProgress;
        _scrollController.jumpTo(
            target.clamp(
                _scrollController.position.minScrollExtent,
                _scrollController.position.maxScrollExtent,
            ),
        );
    }

    void _handleVerticalScroll()
    {
        if (!_scrollController.hasClients)
        {
            return;
        }
        final double maximum = _scrollController.position.maxScrollExtent;
        final double progress = maximum <= 0
                ? 0
                : (_scrollController.offset / maximum).clamp(0.0, 1.0);
        final bool needsRebuild =
            (progress - _currentProgress).abs() >= 0.01;
        _currentProgress = progress;
        if (needsRebuild && mounted && (_showStatus || _controlsVisible))
        {
            setState(()
            {
            });
        }
        _scheduleSave();
    }

    void _scheduleSave()
    {
        _saveTimer?.cancel();
        _saveTimer = Timer(
            const Duration(milliseconds: 500),
            () => unawaited(_saveProgress()),
        );
    }

    Future<void> _saveProgress() async
    {
        if (_activeMaxPosition < 0)
        {
            return;
        }
        await _historyRepository.save(
            work: widget.work,
            chapter: _chapter,
            position: ReadingAnchor.positionForProgress(
                _currentProgress,
                _activeMaxPosition,
            ),
            progress: _currentProgress,
        );
    }

    Color get _readerBackground
    {
        return switch (_novelTheme)
        {
            NovelReaderPalette.light => const Color(0xfffafafa),
            NovelReaderPalette.sepia => const Color(0xfff4ecd8),
            NovelReaderPalette.dark => const Color(0xff171717),
        };
    }

    Color get _readerForeground
    {
        return _novelTheme == NovelReaderPalette.dark
                ? const Color(0xffdddddd)
                : const Color(0xff333333);
    }

    Color _readerControlsBackground(bool comic)
    {
        if (comic)
        {
            return const Color(0xff242424);
        }
        return switch (_novelTheme)
        {
            NovelReaderPalette.light => const Color(0xffe9e9e9),
            NovelReaderPalette.sepia => const Color(0xffe2d6b9),
            NovelReaderPalette.dark => const Color(0xff2b2b2b),
        };
    }

    Future<void> _showReaderSettings(bool comic) async
    {
        await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (BuildContext context) => StatefulBuilder(
                builder: (BuildContext context, StateSetter setSheetState)
                {
                    void update(
                        VoidCallback callback, {
                        bool repaginateNovel = false,
                    })
                    {
                        setState(()
                        {
                            callback();
                            if (repaginateNovel)
                            {
                                _invalidateNovelPagination();
                            }
                        });
                        _persistReaderSettings();
                        setSheetState(()
                        {
                        });
                    }

                    return SafeArea(
                        child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxHeight:
                                        MediaQuery.sizeOf(context).height * 0.8,
                            ),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                    ListTile(
                                        title: Text(
                                            comic ? '漫画阅读设置' : '小说阅读设置',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                        ),
                                        trailing: IconButton(
                                            tooltip: '关闭',
                                            onPressed: () => Navigator.of(
                                                context,
                                            ).pop(),
                                            icon: const Icon(Icons.close),
                                        ),
                                    ),
                                    const Divider(height: 1),
                                    Flexible(
                                        child: ListView(
                                            shrinkWrap: true,
                                            padding: const EdgeInsets.only(
                                                bottom: 20,
                                            ),
                                            children: <Widget>[
                                                ListTile(
                                                    title: const Text('阅读方向'),
                                                    trailing: SegmentedButton<
                                                        ReaderDirection
                                                    >(
                                                        segments: const <
                                                            ButtonSegment<
                                                                ReaderDirection
                                                            >
                                                        >[
                                                            ButtonSegment<
                                                                ReaderDirection
                                                            >(
                                                                value:
                                                                    ReaderDirection.leftToRight,
                                                                icon: Icon(
                                                                    Icons.arrow_forward,
                                                                ),
                                                            ),
                                                            ButtonSegment<
                                                                ReaderDirection
                                                            >(
                                                                value:
                                                                    ReaderDirection.rightToLeft,
                                                                icon: Icon(
                                                                    Icons.arrow_back,
                                                                ),
                                                            ),
                                                            ButtonSegment<
                                                                ReaderDirection
                                                            >(
                                                                value:
                                                                    ReaderDirection.vertical,
                                                                icon: Icon(
                                                                    Icons.arrow_downward,
                                                                ),
                                                            ),
                                                        ],
                                                        selected:
                                                            <ReaderDirection>{
                                                                _flow,
                                                            },
                                                        showSelectedIcon: false,
                                                        onSelectionChanged: (
                                                            Set<ReaderDirection>
                                                                values,
                                                        )
                                                        {
                                                            _selectDirection(
                                                                values.first,
                                                            );
                                                            setSheetState(
                                                                ()
                                                                {
                                                                },
                                                            );
                                                        },
                                                    ),
                                                ),
                                                SwitchListTile(
                                                    value: _reverseControls,
                                                    onChanged: (bool value) =>
                                                        update(()
                                                        {
                                                            _reverseControls =
                                                                value;
                                                        }),
                                                    title: const Text('操作反转'),
                                                    subtitle: const Text(
                                                        '点击左侧下一页，右侧上一页',
                                                    ),
                                                ),
                                                if (comic)
                                                    SwitchListTile(
                                                        value: _fullScreen,
                                                        onChanged: (bool value)
                                                        {
                                                            update(()
                                                            {
                                                                _fullScreen = value;
                                                            });
                                                            unawaited(
                                                                _setImmersiveMode(
                                                                    value,
                                                                ),
                                                            );
                                                        },
                                                        title: const Text(
                                                            '全屏阅读',
                                                        ),
                                                    ),
                                                SwitchListTile(
                                                    value: _showStatus,
                                                    onChanged: (bool value) =>
                                                        update(()
                                                        {
                                                            _showStatus = value;
                                                        }),
                                                    title: const Text(
                                                        '显示状态信息',
                                                    ),
                                                ),
                                                SwitchListTile(
                                                    value: _pageAnimation,
                                                    onChanged: (bool value) =>
                                                        update(()
                                                        {
                                                            _pageAnimation = value;
                                                        }),
                                                    title: const Text('翻页动画'),
                                                ),
                                                if (comic)
                                                    ListTile(
                                                        title: const Text(
                                                            '预加载',
                                                        ),
                                                        trailing:
                                                            SegmentedButton<int>(
                                                                segments: const <
                                                                    ButtonSegment<
                                                                        int
                                                                    >
                                                                >[
                                                                    ButtonSegment<int>(
                                                                        value: 1,
                                                                        label: Text('1页'),
                                                                    ),
                                                                    ButtonSegment<int>(
                                                                        value: 3,
                                                                        label: Text('3页'),
                                                                    ),
                                                                    ButtonSegment<int>(
                                                                        value: 5,
                                                                        label: Text('5页'),
                                                                    ),
                                                                ],
                                                                selected: <int>{
                                                                    _comicPreloadPages,
                                                                },
                                                                showSelectedIcon: false,
                                                                onSelectionChanged: (
                                                                    Set<int> values,
                                                                )
                                                                {
                                                                    _cancelComicPrefetch(
                                                                        clearKey: true,
                                                                    );
                                                                    update(()
                                                                    {
                                                                        _comicPreloadPages =
                                                                            values.first;
                                                                    });
                                                                },
                                                            ),
                                                    ),
                                                if (!comic) ...<Widget>[
                                                    ListTile(
                                                        title: const Text('字体大小'),
                                                        subtitle: Slider(
                                                            value: _fontSize,
                                                            min: 13,
                                                            max: 30,
                                                            divisions: 17,
                                                            label: _fontSize
                                                                .round()
                                                                .toString(),
                                                            onChanged: (
                                                                double value,
                                                            ) => update(
                                                                ()
                                                                {
                                                                    _fontSize = value;
                                                                },
                                                                repaginateNovel:
                                                                    true,
                                                            ),
                                                        ),
                                                        trailing: Text(
                                                            '${_fontSize.round()}',
                                                        ),
                                                    ),
                                                    ListTile(
                                                        title: const Text('行距'),
                                                        subtitle: Slider(
                                                            value: _lineHeight,
                                                            min: 1.3,
                                                            max: 2.3,
                                                            divisions: 10,
                                                            label: _lineHeight
                                                                .toStringAsFixed(
                                                                    1,
                                                                ),
                                                            onChanged: (
                                                                double value,
                                                            ) => update(
                                                                ()
                                                                {
                                                                    _lineHeight = value;
                                                                },
                                                                repaginateNovel:
                                                                    true,
                                                            ),
                                                        ),
                                                        trailing: Text(
                                                            _lineHeight
                                                                .toStringAsFixed(
                                                                    1,
                                                                ),
                                                        ),
                                                    ),
                                                    ListTile(
                                                        title: const Text('阅读主题'),
                                                        trailing: SegmentedButton<
                                                            NovelReaderPalette
                                                        >(
                                                            segments:
                                                                NovelReaderPalette
                                                                    .values
                                                                    .map(
                                                                        (
                                                                            NovelReaderPalette
                                                                                value,
                                                                        ) => ButtonSegment<
                                                                            NovelReaderPalette
                                                                        >(
                                                                            value:
                                                                                value,
                                                                            label:
                                                                                Text(
                                                                                    value.label,
                                                                                ),
                                                                        ),
                                                                    )
                                                                    .toList(
                                                                        growable:
                                                                            false,
                                                                    ),
                                                            selected: <
                                                                NovelReaderPalette
                                                            >{
                                                                _novelTheme,
                                                            },
                                                            showSelectedIcon:
                                                                false,
                                                            onSelectionChanged: (
                                                                Set<
                                                                    NovelReaderPalette
                                                                > values,
                                                            ) => update(()
                                                            {
                                                                _novelTheme =
                                                                    values.first;
                                                            }),
                                                        ),
                                                    ),
                                                ],
                                            ],
                                        ),
                                    ),
                                ],
                            ),
                        ),
                    );
                },
            ),
        );
    }

    void _persistReaderSettings()
    {
        final AppSettings settings = ref.read(
            appSettingsControllerProvider,
        );
        ref.read(appSettingsControllerProvider.notifier).update(
            widget.work.kind == LibraryKind.comic
                ? settings.copyWith(
                    comicDirection: _flow,
                    comicReverseControls: _reverseControls,
                    comicFullScreen: _fullScreen,
                    comicShowStatus: _showStatus,
                    comicPageAnimation: _pageAnimation,
                    comicPreloadPages: _comicPreloadPages,
                )
                : settings.copyWith(
                    novelDirection: _flow,
                    novelReverseControls: _reverseControls,
                    novelShowStatus: _showStatus,
                    novelPageAnimation: _pageAnimation,
                    novelFontSize: _fontSize,
                    novelLineHeight: _lineHeight,
                    novelPalette: _novelTheme,
                ),
        );
    }

    void _saveDirection(ReaderDirection value)
    {
        final AppSettings settings = ref.read(
            appSettingsControllerProvider,
        );
        ref.read(appSettingsControllerProvider.notifier).update(
            widget.work.kind == LibraryKind.comic
                ? settings.copyWith(comicDirection: value)
                : settings.copyWith(novelDirection: value),
        );
    }

    void _selectDirection(ReaderDirection value)
    {
        if (value == _flow)
        {
            return;
        }
        _cancelComicPrefetch(clearKey: true);
        _cancelComicSwipe(resetPage: false);
        _zoomedComicPages.clear();
        final PageController? previous = _pageController;
        _invalidateNovelPagination();
        setState(()
        {
            _flow = value;
            _pageIndex = 0;
            _pageController = null;
            _pageLayoutKey = null;
            _scrollRestored = false;
        });
        _saveDirection(value);
        WidgetsBinding.instance.addPostFrameCallback(
            (Duration timeStamp) => previous?.dispose(),
        );
    }

    void _toggleControls()
    {
        setState(()
        {
            _controlsVisible = !_controlsVisible;
        });
    }

    void _handleKeyEvent(KeyEvent event)
    {
        if (event is! KeyUpEvent)
        {
            return;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.pageUp)
        {
            _turnPage(_reverseControls ? 1 : -1);
        }
        else if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
            event.logicalKey == LogicalKeyboardKey.pageDown)
        {
            _turnPage(_reverseControls ? -1 : 1);
        }
    }

    void _turnPage(int offset)
    {
        if (_flow == ReaderDirection.vertical)
        {
            if (!_scrollController.hasClients)
            {
                return;
            }
            final ScrollPosition position = _scrollController.position;
            if (offset < 0 && position.pixels <= position.minScrollExtent + 1)
            {
                if (_hasPreviousChapter)
                {
                    unawaited(_changeChapter(-1));
                }
                return;
            }
            if (offset > 0 && position.pixels >= position.maxScrollExtent - 1)
            {
                if (_hasNextChapter)
                {
                    unawaited(_changeChapter(1));
                }
                return;
            }
            final double target = (
                position.pixels +
                position.viewportDimension * 0.9 * offset
            ).clamp(position.minScrollExtent, position.maxScrollExtent);
            if (_pageAnimation)
            {
                unawaited(
                    _scrollController.animateTo(
                        target,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.linear,
                    ),
                );
            }
            else
            {
                _scrollController.jumpTo(target);
            }
            return;
        }

        final PageController? controller = _pageController;
        if (controller == null || !controller.hasClients)
        {
            return;
        }
        final int target = _pageIndex + offset;
        if (target < 0)
        {
            if (_hasPreviousChapter)
            {
                unawaited(_changeChapter(-1));
            }
            return;
        }
        if (target >= _activePageCount)
        {
            if (_hasNextChapter)
            {
                unawaited(_changeChapter(1));
            }
            return;
        }
        if (_pageAnimation)
        {
            unawaited(
                controller.animateToPage(
                    target,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.linear,
                ),
            );
        }
        else
        {
            controller.jumpToPage(target);
        }
    }

    void _jumpToProgress(double value)
    {
        final double progress = value.clamp(0.0, 1.0);
        setState(()
        {
            _currentProgress = progress;
        });
        if (_flow == ReaderDirection.vertical)
        {
            if (_scrollController.hasClients)
            {
                final ScrollPosition position = _scrollController.position;
                _scrollController.jumpTo(
                    position.maxScrollExtent * progress,
                );
            }
        }
        else
        {
            final int page = _pageForProgress(progress);
            _pageIndex = page;
            _pageController?.jumpToPage(page);
        }
        _scheduleSave();
    }

    void _beginProgressDrag(double value)
    {
        if (widget.work.kind != LibraryKind.comic ||
                _flow == ReaderDirection.vertical)
        {
            return;
        }
        _progressDragging = true;
        _cancelComicPrefetch(clearKey: true);
    }

    void _endProgressDrag(double value)
    {
        if (widget.work.kind != LibraryKind.comic ||
                _flow == ReaderDirection.vertical)
        {
            return;
        }
        _progressDragging = false;
        final Uri? referer = _activeComicReferer;
        if (referer != null)
        {
            _scheduleComicPrefetch(
                _activeComicImages,
                referer,
                _pageIndex,
                delayed: true,
            );
        }
    }

    void _scheduleComicPrefetch(
        List<Uri> images,
        Uri referer,
        int pageIndex, {
        bool delayed = false,
    })
    {
        if (images.isEmpty || _flow == ReaderDirection.vertical)
        {
            _cancelComicPrefetch(clearKey: true);
            return;
        }
        final int current = pageIndex.clamp(0, images.length - 1);
        final String key = '${_chapter.id}|$current|$_comicPreloadPages|$referer';
        if (_comicPrefetchKey == key)
        {
            return;
        }
        _comicPrefetchKey = key;
        _comicPrefetchTimer?.cancel();
        final int generation = ++_comicPrefetchGeneration;
        void start()
        {
            if (mounted && generation == _comicPrefetchGeneration)
            {
                unawaited(
                    _prefetchComicWindow(
                        images,
                        referer,
                        current,
                        generation,
                    ),
                );
            }
        }
        if (delayed)
        {
            _comicPrefetchTimer = Timer(
                const Duration(milliseconds: 180),
                start,
            );
        } else
        {
            WidgetsBinding.instance.addPostFrameCallback(
                (Duration timeStamp) => start(),
            );
        }
    }

    Future<void> _prefetchComicWindow(
        List<Uri> images,
        Uri referer,
        int current,
        int generation,
    ) async
    {
        final List<int> indices = <int>[];
        if (current + 1 < images.length)
        {
            indices.add(current + 1);
        }
        if (current > 0)
        {
            indices.add(current - 1);
        }
        for (int offset = 2; offset <= _comicPreloadPages; offset++)
        {
            if (current + offset < images.length)
            {
                indices.add(current + offset);
            }
        }
        ReaderMediaRepository? repository;
        for (final int index in indices)
        {
            if (!mounted || generation != _comicPrefetchGeneration)
            {
                return;
            }
            final Uri source = images[index];
            try
            {
                final Uri cached;
                if (source.scheme == 'file')
                {
                    cached = source;
                } else
                {
                    repository ??= ref.read(readerMediaRepositoryProvider);
                    cached = await repository!.resolve(
                        source,
                        referer: referer.toString(),
                    );
                }
                if ((index - current).abs() == 1 && mounted &&
                        generation == _comicPrefetchGeneration)
                {
                    unawaited(
                        precacheImage(
                            FileImage(File.fromUri(cached)),
                            context,
                            onError: (Object error, StackTrace? stackTrace)
                            {
                            },
                        ),
                    );
                }
            }
            on Object
            {
                continue;
            }
        }
    }

    void _cancelComicPrefetch({required bool clearKey})
    {
        _comicPrefetchTimer?.cancel();
        _comicPrefetchTimer = null;
        _comicPrefetchGeneration++;
        if (clearKey)
        {
            _comicPrefetchKey = null;
        }
    }

    void _handleComicZoomChanged(int index, bool zoomed)
    {
        final bool changed = zoomed
            ? _zoomedComicPages.add(index)
            : _zoomedComicPages.remove(index);
        if (changed && mounted && index == _pageIndex)
        {
            setState(()
            {
            });
        }
    }

    Future<void> _changeChapter(int offset) async
    {
        final int targetIndex = _chapterIndex + offset;
        if (targetIndex < 0 || targetIndex >= _chapters.length)
        {
            return;
        }
        await _saveProgress();
        _cancelComicPrefetch(clearKey: true);
        _cancelComicSwipe(resetPage: false);
        _zoomedComicPages.clear();
        final PageController? previousController = _pageController;
        _invalidateNovelPagination();
        setState(()
        {
            _chapter = _chapters[targetIndex];
            _pageController = null;
            _pageIndex = 0;
            _activeMaxPosition = -1;
            _activePageCount = 1;
            _activePageAnchors = const <double>[0];
            _pageLayoutKey = null;
            _currentProgress = 0;
            _scrollRestored = false;
            _initialHistoryWritten = false;
            _contentFuture = _load();
            _progressFuture = _restoreProgress();
        });
        WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp)
        {
            previousController?.dispose();
            if (_scrollController.hasClients)
            {
                _scrollController.jumpTo(0);
            }
        });
    }

    Future<void> _showChapterDirectory() async
    {
        final Chapter? selected = await showModalBottomSheet<Chapter>(
            context: context,
            builder: (BuildContext context) => SafeArea(
                child: ListView.builder(
                    itemCount: _chapters.length,
                    itemBuilder: (BuildContext context, int index)
                    {
                        final Chapter value = _chapters[index];
                        final bool selected = value.id == _chapter.id;
                        return ListTile(
                            title: Text(value.title),
                            trailing: selected
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () => Navigator.of(context).pop(value),
                        );
                    },
                ),
            ),
        );
        if (selected == null || selected.id == _chapter.id || !mounted)
        {
            return;
        }
        final int targetIndex = _chapters.indexWhere(
            (Chapter value) => value.id == selected.id,
        );
        await _changeChapter(targetIndex - _chapterIndex);
    }

    void _retry()
    {
        _reload();
    }

    void _refresh()
    {
        _reload(forceReload: true);
    }

    void _reload({bool forceReload = false})
    {
        _cancelComicPrefetch(clearKey: true);
        _invalidateNovelPagination();
        setState(()
        {
            _contentFuture = _load(forceReload: forceReload);
        });
    }

    Future<void> _confirmOpenOriginal([Uri? target]) async
    {
        final bool confirmed = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) => AlertDialog(
                    title: const Text('打开原帖'),
                    content: const Text('即将在系统浏览器中打开当前章节原帖，是否继续？'),
                    actions: <Widget>[
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('取消'),
                        ),
                        FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('打开'),
                        ),
                    ],
                ),
            ) ??
            false;
        if (confirmed && mounted)
        {
            await _openOriginal(target ?? _chapter.sourceUri);
        }
    }

    Future<void> _openOriginal(Uri uri) async
    {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
}

class _ComicDoubleTapGestureRecognizer extends DoubleTapGestureRecognizer
{
    bool Function(PointerDownEvent event) isAllowed = (_) => true;

    @override
    bool isPointerAllowed(PointerDownEvent event)
    {
        return isAllowed(event) && super.isPointerAllowed(event);
    }
}

class _ZoomableComicPage extends StatefulWidget
{
    const _ZoomableComicPage({
        required this.pageKey,
        required this.child,
        required this.onZoomChanged,
        this.centerChild = false,
        super.key,
    });

    final Key pageKey;
    final Widget child;
    final ValueChanged<bool> onZoomChanged;
    final bool centerChild;

    @override
    State<_ZoomableComicPage> createState()
    {
        return _ZoomableComicPageState();
    }
}

class _ZoomableComicPageState extends State<_ZoomableComicPage>
    with SingleTickerProviderStateMixin
{
    static const double _doubleTapScale = 2;
    final TransformationController _controller = TransformationController();
    late final AnimationController _zoomAnimationController;
    Animation<Matrix4>? _zoomAnimation;
    Offset _doubleTapPosition = Offset.zero;
    bool _zoomed = false;

    @override
    void initState()
    {
        super.initState();
        _zoomAnimationController = AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 180),
        )..addListener(()
        {
            final Animation<Matrix4>? animation = _zoomAnimation;
            if (animation != null)
            {
                _controller.value = animation.value;
            }
        });
    }

    @override
    void dispose()
    {
        _zoomAnimationController.dispose();
        _controller.dispose();
        super.dispose();
    }

    @override
    Widget build(BuildContext context)
    {
        return LayoutBuilder(
            builder: (
                BuildContext context,
                BoxConstraints constraints,
            ) => RawGestureDetector(
                key: widget.pageKey,
                behavior: HitTestBehavior.opaque,
                gestures: <Type, GestureRecognizerFactory>{
                    _ComicDoubleTapGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                            _ComicDoubleTapGestureRecognizer
                        >(
                            _ComicDoubleTapGestureRecognizer.new,
                            (_ComicDoubleTapGestureRecognizer recognizer)
                            {
                                recognizer
                                    ..isAllowed = (PointerDownEvent event)
                                    {
                                        if (_zoomed)
                                        {
                                            return true;
                                        }
                                        final double left =
                                                constraints.maxWidth * 0.3;
                                        final double right =
                                                constraints.maxWidth * 0.7;
                                        return event.localPosition.dx > left &&
                                                event.localPosition.dx < right;
                                    }
                                    ..onDoubleTapDown = (TapDownDetails details)
                                    {
                                        _doubleTapPosition =
                                                details.localPosition;
                                    }
                                    ..onDoubleTap = _toggleZoom;
                            },
                        ),
                },
                child: InteractiveViewer(
                    transformationController: _controller,
                    minScale: 1,
                    maxScale: 4,
                    panEnabled: _zoomed,
                    onInteractionStart: (ScaleStartDetails details)
                    {
                        _zoomAnimationController.stop();
                    },
                    onInteractionUpdate: (ScaleUpdateDetails details)
                    {
                        _reportZoom(
                            _controller.value.getMaxScaleOnAxis() > 1.01,
                        );
                    },
                    onInteractionEnd: (ScaleEndDetails details)
                    {
                        _reportZoom(
                            _controller.value.getMaxScaleOnAxis() > 1.01,
                        );
                    },
                    child: widget.centerChild
                            ? Center(child: widget.child)
                            : widget.child,
                ),
            ),
        );
    }

    void _toggleZoom()
    {
        final bool zoomIn = !_zoomed;
        final Matrix4 target = zoomIn
                ? (Matrix4.identity()
                    ..translateByDouble(
                        -_doubleTapPosition.dx * (_doubleTapScale - 1),
                        -_doubleTapPosition.dy * (_doubleTapScale - 1),
                        0,
                        1,
                    )
                    ..scaleByDouble(
                        _doubleTapScale,
                        _doubleTapScale,
                        _doubleTapScale,
                        1,
                    ))
                : Matrix4.identity();
        _zoomAnimation = Matrix4Tween(
            begin: _controller.value.clone(),
            end: target,
        ).animate(
            CurvedAnimation(
                parent: _zoomAnimationController,
                curve: Curves.easeOutCubic,
            ),
        );
        _reportZoom(zoomIn);
        _zoomAnimationController.forward(from: 0);
    }

    void _reportZoom(bool value)
    {
        if (_zoomed == value)
        {
            return;
        }
        setState(()
        {
            _zoomed = value;
        });
        widget.onZoomChanged(value);
    }
}

class _LoadedChapter
{
    const _LoadedChapter({required this.blocks, required this.referer});

    final List<PostContentBlock> blocks;
    final Uri referer;
}

class _PageBadge extends StatelessWidget
{
    const _PageBadge({
        required this.current,
        required this.total,
        this.foreground = Colors.white,
        this.background = Colors.black54,
    });

    final int current;
    final int total;
    final Color foreground;
    final Color background;

    @override
    Widget build(BuildContext context)
    {
        return DecoratedBox(
            key: const Key('reader-page-badge'),
            decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(
                    '$current / $total',
                    style: TextStyle(color: foreground, fontSize: 12),
                ),
            ),
        );
    }
}

class _ProgressBadge extends StatelessWidget
{
    const _ProgressBadge({
        required this.progress,
        this.foreground = Colors.white,
        this.background = Colors.black54,
    });

    final double progress;
    final Color foreground;
    final Color background;

    @override
    Widget build(BuildContext context)
    {
        return DecoratedBox(
            key: const Key('reader-progress-badge'),
            decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Text(
                    '${(progress.clamp(0.0, 1.0) * 100).round()}%',
                    style: TextStyle(color: foreground, fontSize: 12),
                ),
            ),
        );
    }
}

class _PermissionFallback extends StatelessWidget
{
    const _PermissionFallback({required this.text, required this.onOpenOriginal});

    final String text;
    final VoidCallback onOpenOriginal;

    @override
    Widget build(BuildContext context)
    {
        return Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                        Text(
                            text.isEmpty ? '正文中没有可读取的漫画图片' : text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                            onPressed: onOpenOriginal,
                            icon: const Icon(Icons.open_in_browser),
                            label: const Text('在浏览器打开原帖'),
                        ),
                    ],
                ),
            ),
        );
    }
}
