import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:x300/features/reader/data/reader_media_repository.dart';

class ForumImage extends ConsumerStatefulWidget
{
    const ForumImage({
        required this.uri,
        required this.referer,
        this.fit = BoxFit.contain,
        this.width,
        this.height,
        super.key,
    });

    final Uri uri;
    final String referer;
    final BoxFit fit;
    final double? width;
    final double? height;

    @override
    ConsumerState<ForumImage> createState()
    {
        return _ForumImageState();
    }
}

class _ForumImageState extends ConsumerState<ForumImage>
{
    ReaderMediaRepository? _repository;
    Future<Uri>? _future;

    @override
    void didUpdateWidget(covariant ForumImage oldWidget)
    {
        super.didUpdateWidget(oldWidget);
        if (oldWidget.uri != widget.uri || oldWidget.referer != widget.referer)
        {
            _repository = null;
            _future = null;
        }
    }

    @override
    Widget build(BuildContext context)
    {
        if (widget.uri.scheme == 'file')
        {
            return _image(widget.uri);
        }
        final ReaderMediaRepository repository = ref.watch(
            readerMediaRepositoryProvider,
        );
        final Uri? cached = repository.peek(widget.uri);
        if (cached != null)
        {
            return _image(cached, repository: repository);
        }
        if (!identical(_repository, repository) || _future == null)
        {
            _repository = repository;
            _future = repository.resolve(
                widget.uri,
                referer: widget.referer,
            );
        }
        return FutureBuilder<Uri>(
            future: _future,
            builder: (BuildContext context, AsyncSnapshot<Uri> snapshot)
            {
                if (snapshot.hasData)
                {
                    return _image(snapshot.data!, repository: repository);
                }
                if (snapshot.hasError)
                {
                    return InkWell(
                        onTap: () => unawaited(_retry(repository)),
                        child: _ImageError(
                            width: widget.width,
                            height: widget.height,
                        ),
                    );
                }
                return SizedBox(
                    width: widget.width,
                    height: widget.height ?? 120,
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                );
            },
        );
    }

    Widget _image(
        Uri uri, {
        ReaderMediaRepository? repository,
    })
    {
        return Image.file(
            File.fromUri(uri),
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stackTrace,
            ) => repository == null
                    ? _ImageError(width: widget.width, height: widget.height)
                    : InkWell(
                        onTap: () => unawaited(_retry(repository)),
                        child: _ImageError(
                            width: widget.width,
                            height: widget.height,
                        ),
                    ),
        );
    }

    Future<void> _retry(ReaderMediaRepository repository) async
    {
        await repository.evict(widget.uri);
        if (!mounted)
        {
            return;
        }
        setState(()
        {
            _repository = null;
            _future = null;
        });
    }
}

class _ImageError extends StatelessWidget
{
    const _ImageError({required this.width, required this.height});

    final double? width;
    final double? height;

    @override
    Widget build(BuildContext context)
    {
        return SizedBox(
            width: width,
            height: height ?? 120,
            child: const Center(
                child: Icon(Icons.broken_image_outlined, color: Colors.grey),
            ),
        );
    }
}
