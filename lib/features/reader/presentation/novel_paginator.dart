import 'package:flutter/material.dart';
import 'package:x300/features/library/domain/thread_models.dart';

class NovelPageLayout
{
    const NovelPageLayout({
        required this.blocks,
        required this.startCharacter,
        required this.endCharacter,
    });

    final List<PostContentBlock> blocks;
    final int startCharacter;
    final int endCharacter;
}

class NovelPaginator
{
    const NovelPaginator();

    static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(
        26,
        44,
        26,
        20,
    );

    List<NovelPageLayout> paginate({
        required List<PostContentBlock> blocks,
        required double width,
        required double height,
        required double fontSize,
        required double lineHeight,
        required TextDirection textDirection,
        TextStyle baseStyle = const TextStyle(),
        TextScaler textScaler = TextScaler.noScaling,
    })
    {
        final _NovelPaginationBuilder builder = _NovelPaginationBuilder(
            paginator: this,
            blocks: blocks,
            width: width,
            height: height,
            fontSize: fontSize,
            lineHeight: lineHeight,
            textDirection: textDirection,
            baseStyle: baseStyle,
            textScaler: textScaler,
        );
        while (!builder.isComplete)
        {
            builder.advance();
        }
        return builder.finish();
    }

    Future<List<NovelPageLayout>> paginateIncrementally({
        required List<PostContentBlock> blocks,
        required double width,
        required double height,
        required double fontSize,
        required double lineHeight,
        required TextDirection textDirection,
        TextStyle baseStyle = const TextStyle(),
        TextScaler textScaler = TextScaler.noScaling,
        Duration timeSlice = const Duration(milliseconds: 8),
        bool Function()? isCancelled,
    }) async
    {
        await Future<void>.delayed(Duration.zero);
        if (isCancelled?.call() ?? false)
        {
            return const <NovelPageLayout>[];
        }
        final _NovelPaginationBuilder builder = _NovelPaginationBuilder(
            paginator: this,
            blocks: blocks,
            width: width,
            height: height,
            fontSize: fontSize,
            lineHeight: lineHeight,
            textDirection: textDirection,
            baseStyle: baseStyle,
            textScaler: textScaler,
        );
        final Stopwatch slice = Stopwatch()..start();
        while (!builder.isComplete)
        {
            builder.advance();
            if (isCancelled?.call() ?? false)
            {
                return const <NovelPageLayout>[];
            }
            if (timeSlice == Duration.zero || slice.elapsed >= timeSlice)
            {
                await Future<void>.delayed(Duration.zero);
                if (isCancelled?.call() ?? false)
                {
                    return const <NovelPageLayout>[];
                }
                slice
                    ..reset()
                    ..start();
            }
        }
        return builder.finish();
    }

    _TextFit _fittingText(
        String text, {
        required TextStyle style,
        required double width,
        required double height,
        required TextDirection textDirection,
        required TextScaler textScaler,
    })
    {
        final double fullHeight = _measure(
            text,
            style: style,
            width: width,
            textDirection: textDirection,
            textScaler: textScaler,
        );
        if (fullHeight <= height)
        {
            return _TextFit(length: text.length, height: fullHeight);
        }
        int low = 0;
        int high = text.length;
        int bestLength = 0;
        double bestHeight = 0;
        while (low < high)
        {
            final int middle = (low + high + 1) ~/ 2;
            final int boundary = _safeBoundary(text, middle);
            final double measured = _measure(
                text.substring(0, boundary),
                style: style,
                width: width,
                textDirection: textDirection,
                textScaler: textScaler,
            );
            if (measured <= height)
            {
                if (boundary >= bestLength)
                {
                    bestLength = boundary;
                    bestHeight = measured;
                }
                low = middle;
            }
            else
            {
                high = middle - 1;
            }
        }
        if (low <= 0)
        {
            return const _TextFit(length: 0, height: 0);
        }
        final int length = _safeBoundary(text, low);
        if (length == bestLength)
        {
            return _TextFit(length: length, height: bestHeight);
        }
        return _TextFit(
            length: length,
            height: _measure(
                text.substring(0, length),
                style: style,
                width: width,
                textDirection: textDirection,
                textScaler: textScaler,
            ),
        );
    }

    double _measure(
        String text, {
        required TextStyle style,
        required double width,
        required TextDirection textDirection,
        required TextScaler textScaler,
    })
    {
        final TextPainter painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: textDirection,
            textScaler: textScaler,
        )..layout(maxWidth: width);
        return painter.height;
    }

    int _safeBoundary(String text, int proposed)
    {
        int result = proposed.clamp(1, text.length);
        if (result < text.length && _isLowSurrogate(text.codeUnitAt(result)))
        {
            if (result == 1 && _isHighSurrogate(text.codeUnitAt(0)))
            {
                result++;
            }
            else
            {
                result--;
            }
        }
        return result < 1 ? 1 : result;
    }

    bool _isHighSurrogate(int codeUnit)
    {
        return codeUnit >= 0xd800 && codeUnit <= 0xdbff;
    }

    bool _isLowSurrogate(int codeUnit)
    {
        return codeUnit >= 0xdc00 && codeUnit <= 0xdfff;
    }
}

class _NovelPaginationBuilder
{
    _NovelPaginationBuilder({
        required this.paginator,
        required this.blocks,
        required double width,
        required double height,
        required this.fontSize,
        required this.lineHeight,
        required this.textDirection,
        required this.baseStyle,
        required this.textScaler,
    }) : availableWidth = (
            width - NovelPaginator.contentPadding.horizontal
         ).clamp(1, double.infinity),
         availableHeight = (
            height - NovelPaginator.contentPadding.vertical
         ).clamp(1, double.infinity);

    final NovelPaginator paginator;
    final List<PostContentBlock> blocks;
    final double availableWidth;
    final double availableHeight;
    final double fontSize;
    final double lineHeight;
    final TextDirection textDirection;
    final TextStyle baseStyle;
    final TextScaler textScaler;
    final List<NovelPageLayout> _result = <NovelPageLayout>[];
    List<PostContentBlock> _page = <PostContentBlock>[];
    int _blockIndex = 0;
    PostTextBlock? _pendingTextBlock;
    String _remainingText = '';
    bool _firstTextSegment = true;
    double _usedHeight = 0;
    int _character = 0;
    int _pageStart = 0;

    bool get isComplete =>
        _blockIndex >= blocks.length && _pendingTextBlock == null;

    void advance()
    {
        if (isComplete)
        {
            return;
        }
        if (_pendingTextBlock == null)
        {
            final PostContentBlock block = blocks[_blockIndex++];
            if (block is PostImageBlock)
            {
                _addImage(block);
                return;
            }
            _pendingTextBlock = block as PostTextBlock;
            _remainingText = block.text;
            _firstTextSegment = true;
            if (_remainingText.isEmpty)
            {
                _pendingTextBlock = null;
                return;
            }
        }
        _addTextSegment();
    }

    List<NovelPageLayout> finish()
    {
        _commitPage();
        if (_result.isNotEmpty)
        {
            return _result;
        }
        return <NovelPageLayout>[
            NovelPageLayout(
                blocks: List<PostContentBlock>.unmodifiable(blocks),
                startCharacter: 0,
                endCharacter: _character,
            ),
        ];
    }

    void _addImage(PostImageBlock block)
    {
        final double imageHeight = availableHeight * 0.65 + 16;
        if (_page.isNotEmpty &&
            _usedHeight + imageHeight > availableHeight)
        {
            _commitPage();
        }
        _page.add(block);
        _usedHeight += imageHeight.clamp(1, availableHeight);
        if (_usedHeight >= availableHeight * 0.92)
        {
            _commitPage();
        }
    }

    void _addTextSegment()
    {
        final PostTextBlock textBlock = _pendingTextBlock!;
        final bool heading = textBlock.heading && _firstTextSegment;
        final TextStyle style = baseStyle.copyWith(
            fontSize: heading ? fontSize + 3 : fontSize,
            height: lineHeight,
            fontWeight: heading ? FontWeight.bold : FontWeight.normal,
        );
        final double bottomSpacing = heading ? 18 : 14;
        final double textHeight = availableHeight - _usedHeight - bottomSpacing;
        if (textHeight <= 0 && _page.isNotEmpty)
        {
            _commitPage();
            return;
        }
        final _TextFit fit = paginator._fittingText(
            _remainingText,
            style: style,
            width: availableWidth,
            height: textHeight <= 0 ? availableHeight : textHeight,
            textDirection: textDirection,
            textScaler: textScaler,
        );
        int length = fit.length;
        double segmentHeight = fit.height;
        if (length <= 0)
        {
            if (_page.isNotEmpty)
            {
                _commitPage();
                return;
            }
            length = paginator._safeBoundary(_remainingText, 1);
            segmentHeight = paginator._measure(
                _remainingText.substring(0, length),
                style: style,
                width: availableWidth,
                textDirection: textDirection,
                textScaler: textScaler,
            );
        }
        final String segment = _remainingText.substring(0, length);
        _page.add(PostTextBlock(text: segment, heading: heading));
        _usedHeight += segmentHeight + bottomSpacing;
        _character += segment.length;
        _remainingText = _remainingText.substring(length);
        _firstTextSegment = false;
        if (_remainingText.isEmpty)
        {
            _pendingTextBlock = null;
        }
        else
        {
            _commitPage();
        }
    }

    void _commitPage()
    {
        if (_page.isEmpty)
        {
            return;
        }
        _result.add(
            NovelPageLayout(
                blocks: List<PostContentBlock>.unmodifiable(_page),
                startCharacter: _pageStart,
                endCharacter: _character,
            ),
        );
        _page = <PostContentBlock>[];
        _usedHeight = 0;
        _pageStart = _character;
    }
}

class _TextFit
{
    const _TextFit({required this.length, required this.height});

    final int length;
    final double height;
}
