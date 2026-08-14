import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show FlutterView, Offset, PointerDeviceKind, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Debug-only UI handle for Linux 实机: tap/find/enter by Flutter [Key].
///
/// Starts only when [kDebugMode] is true. The HTTP server binds 127.0.0.1.
/// Release builds must not call [install].
class DebugUiAutomation
{
    DebugUiAutomation._();

    static const int preferredPort = 17830;
    static const String portFilePath = '/tmp/x300-debug-ui.json';
    static const String vmExtensionName = 'ext.x300.debug.ui';

    static HttpServer? _server;
    static bool _installed = false;
    static int _pointer = 910000;
    static int? _boundPort;

    static int? get boundPort => _boundPort;

    static Future<void> install({int port = preferredPort}) async
    {
        if (!kDebugMode || _installed)
        {
            return;
        }
        _installed = true;
        _registerVmExtension();
        await _startHttp(port);
    }

    static Future<void> uninstall() async
    {
        await _server?.close(force: true);
        _server = null;
        _boundPort = null;
        _installed = false;
        try
        {
            final File file = File(portFilePath);
            if (file.existsSync())
            {
                await file.delete();
            }
        }
        on FileSystemException
        {
            // Port file is only a convenience for local scripts.
        }
    }

    static Map<String, Object?> health()
    {
        return <String, Object?>{
            'ok': true,
            'debug': kDebugMode,
            'port': _boundPort,
            'pid': pid,
        };
    }

    static List<Map<String, Object?>> listKeys()
    {
        return _collect()
            .map(_hitJson)
            .toList(growable: false);
    }

    static Map<String, Object?> find(String key)
    {
        if (key.isEmpty)
        {
            return _fail('missing_key');
        }
        final _Hit? hit = _locate(key);
        if (hit == null)
        {
            return _fail('not_found', key: key);
        }
        return <String, Object?>{
            'ok': true,
            ..._hitJson(hit),
        };
    }

    static Future<Map<String, Object?>> tap(String key) async
    {
        if (key.isEmpty)
        {
            return _fail('missing_key');
        }
        _Hit? hit = _locate(key);
        if (hit == null)
        {
            return _fail('not_found', key: key);
        }
        if (!hit.onstage)
        {
            return _fail('offstage', key: key, hit: hit);
        }
        if (!hit.enabled)
        {
            return _fail('disabled', key: key, hit: hit);
        }
        if (!hit.hittable && Scrollable.maybeOf(hit.element) != null)
        {
            await _reveal(hit);
            hit = _locate(key);
            if (hit == null)
            {
                return _fail('not_found', key: key);
            }
        }
        if (!hit.onstage || !hit.enabled)
        {
            return _fail(
                hit.onstage ? 'disabled' : 'offstage',
                key: key,
                hit: hit,
            );
        }
        if (!hit.hittable)
        {
            return _fail('not_hittable', key: key, hit: hit);
        }
        _sendTap(hit.rect.center);
        return <String, Object?>{
            'ok': true,
            'command': 'tap',
            ..._hitJson(hit),
        };
    }

    static Future<Map<String, Object?>> enterText(
        String key,
        String text,
    ) async
    {
        if (key.isEmpty)
        {
            return _fail('missing_key');
        }
        final Map<String, Object?> focused = await tap(key);
        if (focused['ok'] != true)
        {
            return focused;
        }
        final _Hit? hit = _locate(key);
        if (hit == null)
        {
            return _fail('not_found', key: key);
        }
        final EditableTextState? state = _editableState(hit.element);
        if (state == null)
        {
            return _fail('not_editable', key: key, hit: hit);
        }
        state.userUpdateTextEditingValue(
            TextEditingValue(
                text: text,
                selection: TextSelection.collapsed(offset: text.length),
            ),
            SelectionChangedCause.keyboard,
        );
        return <String, Object?>{
            'ok': true,
            'command': 'enter',
            'length': text.length,
            ..._hitJson(hit),
        };
    }

    static Map<String, Object?> back()
    {
        final BuildContext? context = _visibleContext();
        if (context == null)
        {
            return _fail('no_context');
        }
        final NavigatorState? navigator = Navigator.maybeOf(context);
        if (navigator == null || !navigator.canPop())
        {
            return _fail('cannot_pop');
        }
        navigator.pop();
        return <String, Object?>{
            'ok': true,
            'command': 'back',
        };
    }

    static Future<Map<String, Object?>> waitFor(
        String key, {
        Duration timeout = const Duration(seconds: 8),
    }) async
    {
        if (key.isEmpty)
        {
            return _fail('missing_key');
        }
        final DateTime deadline = DateTime.now().add(timeout);
        while (true)
        {
            final _Hit? hit = _locate(key);
            if (hit != null && hit.onstage)
            {
                return <String, Object?>{
                    'ok': true,
                    'command': 'wait',
                    ..._hitJson(hit),
                };
            }
            if (!DateTime.now().isBefore(deadline))
            {
                return _fail(
                    'timeout',
                    key: key,
                    extra: <String, Object?>{
                        'timeoutMs': timeout.inMilliseconds,
                    },
                );
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
        }
    }

    static Future<Map<String, Object?>> dispatch(
        String command,
        Map<String, String> params,
    ) async
    {
        switch (command)
        {
            case 'health':
                return health();
            case 'keys':
                return <String, Object?>{
                    'ok': true,
                    'keys': listKeys(),
                };
            case 'find':
                return find(params['key'] ?? '');
            case 'tap':
                return tap(params['key'] ?? '');
            case 'enter':
                return enterText(params['key'] ?? '', params['text'] ?? '');
            case 'back':
                return back();
            case 'wait':
                return waitFor(
                    params['key'] ?? '',
                    timeout: Duration(
                        milliseconds:
                            int.tryParse(params['timeoutMs'] ?? '') ?? 8000,
                    ),
                );
            default:
                return _fail('unknown_command', extra: <String, Object?>{
                    'command': command,
                });
        }
    }

    static void _registerVmExtension()
    {
        developer.registerExtension(vmExtensionName, (
            String method,
            Map<String, String> params,
        ) async
        {
            final Map<String, Object?> result = await dispatch(
                params['cmd'] ?? params['command'] ?? '',
                params,
            );
            return developer.ServiceExtensionResponse.result(
                jsonEncode(result),
            );
        });
    }

    static Future<void> _startHttp(int requestedPort) async
    {
        HttpServer? server;
        Object? lastError;
        final List<int> ports = requestedPort == 0
            ? <int>[0]
            : <int>[
                  for (int port = requestedPort; port < requestedPort + 10; port++)
                      port,
              ];
        for (final int port in ports)
        {
            try
            {
                server = await HttpServer.bind(
                    InternetAddress.loopbackIPv4,
                    port,
                );
                break;
            }
            catch (error)
            {
                lastError = error;
            }
        }
        if (server == null)
        {
            debugPrint('x300 debug ui: bind failed: $lastError');
            return;
        }
        _server = server;
        _boundPort = server.port;
        await _writePortFile();
        debugPrint(
            'x300 debug ui: http://127.0.0.1:$_boundPort  ($portFilePath)',
        );
        server.listen(_handleHttp);
    }

    static Future<void> _writePortFile() async
    {
        try
        {
            await File(portFilePath).writeAsString(
                jsonEncode(<String, Object?>{
                    'port': _boundPort,
                    'pid': pid,
                }),
            );
        }
        on FileSystemException catch (error)
        {
            debugPrint('x300 debug ui: port file failed: $error');
        }
    }

    static Future<void> _handleHttp(HttpRequest request) async
    {
        final String command = _httpCommand(request);
        final Map<String, String> params = <String, String>{
            ...request.uri.queryParameters,
        };
        if (request.method == 'POST')
        {
            final String body = await utf8.decodeStream(request);
            if (body.isNotEmpty)
            {
                params.addAll(_decodeBody(body, request.headers.contentType));
            }
        }
        Map<String, Object?> result;
        try
        {
            result = await dispatch(command, params);
        }
        catch (error)
        {
            result = _fail('exception', extra: <String, Object?>{
                'message': error.toString(),
            });
        }
        request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(result));
        await request.response.close();
    }

    static String _httpCommand(HttpRequest request)
    {
        final List<String> parts = request.uri.path
            .split('/')
            .where((String part) => part.isNotEmpty)
            .toList(growable: false);
        if (parts.isEmpty)
        {
            return 'health';
        }
        return parts.first;
    }

    static Map<String, String> _decodeBody(String body, ContentType? type)
    {
        if (type?.mimeType == 'application/json')
        {
            final Object? decoded = jsonDecode(body);
            if (decoded is Map<String, dynamic>)
            {
                return decoded.map(
                    (String key, dynamic value) => MapEntry<String, String>(
                        key,
                        value?.toString() ?? '',
                    ),
                );
            }
            return <String, String>{};
        }
        return Uri.splitQueryString(body);
    }

    static List<_Hit> _collect()
    {
        final Element? root = WidgetsBinding.instance.rootElement;
        if (root == null)
        {
            return <_Hit>[];
        }
        final Size viewSize = _viewSize();
        final List<_Hit> hits = <_Hit>[];
        void visit(Element element)
        {
            final String? name = _keyName(element.widget.key);
            if (name != null)
            {
                final RenderObject? renderObject = element.renderObject;
                if (renderObject is RenderBox &&
                    renderObject.hasSize &&
                    renderObject.attached)
                {
                    final Offset topLeft = renderObject.localToGlobal(
                        Offset.zero,
                    );
                    final Rect rect = topLeft & renderObject.size;
                    if (!rect.isEmpty)
                    {
                        final bool onstage = _isOnstage(element);
                        hits.add(
                            _Hit(
                                key: name,
                                element: element,
                                renderObject: renderObject,
                                rect: rect,
                                onstage: onstage,
                                enabled: _isEnabled(element),
                                inViewport: _intersectsViewport(rect, viewSize),
                                hittable: onstage &&
                                    _isHittable(element, renderObject, rect),
                            ),
                        );
                    }
                }
            }
            element.visitChildren(visit);
        }

        visit(root);
        return hits;
    }

    static _Hit? _locate(String key)
    {
        final List<_Hit> matches = _collect()
            .where((_Hit hit) => hit.key == key)
            .toList(growable: false);
        if (matches.isEmpty)
        {
            return null;
        }
        for (final _Hit hit in matches.reversed)
        {
            if (hit.onstage && hit.hittable)
            {
                return hit;
            }
        }
        for (final _Hit hit in matches.reversed)
        {
            if (hit.onstage)
            {
                return hit;
            }
        }
        return matches.last;
    }

    static Future<void> _reveal(_Hit hit) async
    {
        try
        {
            await Scrollable.ensureVisible(
                hit.element,
                alignment: 0.45,
                duration: Duration.zero,
            );
        }
        on FlutterError
        {
            return;
        }
    }

    static void _sendTap(Offset position)
    {
        final int viewId = _viewId();
        final int pointer = _pointer++;
        GestureBinding.instance.handlePointerEvent(
            PointerDownEvent(
                pointer: pointer,
                position: position,
                kind: PointerDeviceKind.touch,
                viewId: viewId,
            ),
        );
        GestureBinding.instance.handlePointerEvent(
            PointerUpEvent(
                pointer: pointer,
                position: position,
                kind: PointerDeviceKind.touch,
                viewId: viewId,
            ),
        );
    }

    static bool _isHittable(
        Element element,
        RenderBox renderObject,
        Rect rect,
    )
    {
        final int viewId = _viewId();
        final HitTestResult result = HitTestResult();
        WidgetsBinding.instance.hitTestInView(result, rect.center, viewId);
        for (final HitTestEntry entry in result.path)
        {
            final HitTestTarget target = entry.target;
            if (target is! RenderObject)
            {
                continue;
            }
            RenderObject? current = target;
            while (current != null)
            {
                if (identical(current, renderObject))
                {
                    return true;
                }
                current = current.parent;
            }
        }
        return false;
    }

    static bool _isOnstage(Element element)
    {
        bool onstage = true;
        element.visitAncestorElements((Element ancestor)
        {
            final Widget widget = ancestor.widget;
            if (widget is Offstage && widget.offstage)
            {
                onstage = false;
                return false;
            }
            if (widget is TickerMode && !widget.enabled)
            {
                onstage = false;
                return false;
            }
            if (widget is Visibility && !widget.visible)
            {
                onstage = false;
                return false;
            }
            return true;
        });
        return onstage;
    }

    static bool _isEnabled(Element element)
    {
        bool enabled = true;
        element.visitAncestorElements((Element ancestor)
        {
            final Widget widget = ancestor.widget;
            if (widget is IgnorePointer && widget.ignoring)
            {
                enabled = false;
                return false;
            }
            final bool? buttonEnabled = _buttonEnabled(widget);
            if (buttonEnabled != null)
            {
                enabled = buttonEnabled;
                return false;
            }
            if (widget is ListTile)
            {
                enabled = widget.enabled &&
                    (widget.onTap != null || widget.onLongPress != null);
                return false;
            }
            if (widget is PopupMenuItem<dynamic>)
            {
                enabled = widget.enabled;
                return false;
            }
            if (widget is ChoiceChip)
            {
                enabled = widget.onSelected != null;
                return false;
            }
            return true;
        });
        final bool? selfEnabled = _buttonEnabled(element.widget);
        if (selfEnabled != null)
        {
            return selfEnabled;
        }
        return enabled;
    }

    static bool? _buttonEnabled(Widget widget)
    {
        if (widget is IconButton)
        {
            return widget.onPressed != null;
        }
        if (widget is FloatingActionButton)
        {
            return widget.onPressed != null;
        }
        if (widget is ButtonStyleButton)
        {
            return widget.enabled;
        }
        if (widget is InkWell)
        {
            return widget.onTap != null || widget.onLongPress != null;
        }
        if (widget is GestureDetector)
        {
            return widget.onTap != null || widget.onLongPress != null;
        }
        return null;
    }

    static EditableTextState? _editableState(Element start)
    {
        EditableTextState? found;
        void visit(Element element)
        {
            if (found != null)
            {
                return;
            }
            if (element is StatefulElement && element.state is EditableTextState)
            {
                found = element.state as EditableTextState;
                return;
            }
            element.visitChildren(visit);
        }

        visit(start);
        if (found != null)
        {
            return found;
        }
        start.visitAncestorElements((Element ancestor)
        {
            if (ancestor is StatefulElement &&
                ancestor.state is EditableTextState)
            {
                found = ancestor.state as EditableTextState;
                return false;
            }
            return true;
        });
        return found;
    }

    static BuildContext? _visibleContext()
    {
        for (final _Hit hit in _collect().reversed)
        {
            if (hit.onstage)
            {
                return hit.element;
            }
        }
        return WidgetsBinding.instance.rootElement;
    }

    static String? _keyName(Key? key)
    {
        if (key is ValueKey<String>)
        {
            return key.value;
        }
        if (key is ValueKey<int>)
        {
            return '${key.value}';
        }
        if (key is ValueKey)
        {
            final Object? value = key.value;
            if (value is String)
            {
                return value;
            }
            if (value is int)
            {
                return '$value';
            }
        }
        return null;
    }

    static Map<String, Object?> _hitJson(_Hit hit)
    {
        return <String, Object?>{
            'key': hit.key,
            'x': hit.rect.left,
            'y': hit.rect.top,
            'w': hit.rect.width,
            'h': hit.rect.height,
            'onstage': hit.onstage,
            'enabled': hit.enabled,
            'inViewport': hit.inViewport,
            'hittable': hit.hittable,
        };
    }

    static Map<String, Object?> _fail(
        String error, {
        String? key,
        _Hit? hit,
        Map<String, Object?> extra = const <String, Object?>{},
    })
    {
        return <String, Object?>{
            'ok': false,
            'error': error,
            if (key != null) 'key': key,
            if (hit != null) ..._hitJson(hit),
            ...extra,
        };
    }

    static int _viewId()
    {
        final Iterable<FlutterView> views =
            WidgetsBinding.instance.platformDispatcher.views;
        if (views.isEmpty)
        {
            return 0;
        }
        return views.first.viewId;
    }

    static Size _viewSize()
    {
        final Iterable<FlutterView> views =
            WidgetsBinding.instance.platformDispatcher.views;
        if (views.isEmpty)
        {
            return Size.zero;
        }
        return views.first.physicalSize / views.first.devicePixelRatio;
    }

    static bool _intersectsViewport(Rect rect, Size viewSize)
    {
        if (viewSize.isEmpty)
        {
            return !rect.isEmpty;
        }
        return rect.overlaps(Offset.zero & viewSize);
    }
}

class _Hit
{
    const _Hit({
        required this.key,
        required this.element,
        required this.renderObject,
        required this.rect,
        required this.onstage,
        required this.enabled,
        required this.inViewport,
        required this.hittable,
    });

    final String key;
    final Element element;
    final RenderBox renderObject;
    final Rect rect;
    final bool onstage;
    final bool enabled;
    final bool inViewport;
    final bool hittable;
}
