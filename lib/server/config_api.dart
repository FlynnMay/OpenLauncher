import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf.dart';

import '../core/cards/cards_provider.dart';
import '../core/config/config_controller.dart';
import '../core/wallpaper/wallpaper.dart';
import 'custom_icons.dart';
import 'wallpaper_store.dart';

/// The HTML of the config page.
final configPageProvider = FutureProvider<String>(
  (ref) => rootBundle.loadString('assets/web/index.html'),
);

/// What the config page shows: the wallpaper and every card, in order, as
/// JSON.
final configPageStateProvider = FutureProvider<Map<String, Object?>>((
  ref,
) async {
  final cards = await ref.watch(allCardsProvider.future);
  final config = await ref.watch(configProvider.future);
  return {
    'wallpaper': switch (Wallpaper.fromPath(config.wallpaper)) {
      null => null,
      final wallpaper => {
        'kind': wallpaper.kind.name,
        'url': '/api/wallpaper?v=${wallpaper.path.hashCode.toRadixString(36)}',
      },
    },
    'cards': [
      for (final card in cards)
        {
          'id': card.id,
          'kind': card.kind.name,
          'label': card.label,
          'hidden': config.hidden.contains(card.id),
          'customIcon': config.iconOverrides.containsKey(card.id),
          'wide': card.wideIcon,
          // The path changes whenever the image does, so it doubles as a
          // cache key.
          'icon': switch (card.iconPath ?? card.svg) {
            null => null,
            final source =>
              '/api/icon?id=${Uri.encodeQueryComponent(card.id)}'
                  '&v=${source.hashCode.toRadixString(36)}',
          },
        },
    ],
  };
});

final configApiProvider = Provider<ConfigApi>((ref) {
  final api = ConfigApi(ref);
  ref.listen(configPageStateProvider, (_, next) {
    if (next case AsyncData(:final value)) api._publish(value);
  }, fireImmediately: true);
  ref.onDispose(api._dispose);
  return api;
});

/// The HTTP API behind the config page. A second client of the core, next to
/// the TV UI: it reads the same providers and changes config through the same
/// controller.
class ConfigApi {
  ConfigApi(this._ref);

  static const maxIconBytes = 8 * 1024 * 1024;
  static const _json = {'content-type': 'application/json; charset=utf-8'};

  final Ref _ref;
  final _states = StreamController<String>.broadcast();
  String? _latestState;

  void _publish(Map<String, Object?> state) {
    final encoded = jsonEncode(state);
    if (encoded == _latestState) return;
    _latestState = encoded;
    _states.add(encoded);
  }

  void _dispose() => _states.close();

  Future<Response> handle(Request request) async {
    try {
      return await _route(request);
    } on FormatException catch (e) {
      return _error(400, e.message);
    }
  }

  Future<Response> _route(Request request) async {
    final id = request.url.queryParameters['id'];
    return switch ((request.method, request.url.path)) {
      ('GET', '') => Response.ok(
        await _ref.read(configPageProvider.future),
        headers: {'content-type': 'text/html; charset=utf-8'},
      ),
      ('GET', 'api/state') => Response.ok(
        jsonEncode(await _ref.read(configPageStateProvider.future)),
        headers: _json,
      ),
      ('GET', 'api/events') => _events(),
      ('PUT', 'api/order') => _setOrder(await _body(request)),
      ('PUT', 'api/hidden') => _withCard(
        id,
        (id) async => _setHidden(id, await _body(request)),
      ),
      ('GET', 'api/icon') => _withCard(id, _icon),
      ('PUT', 'api/icon') => _withCard(id, (id) => _uploadIcon(id, request)),
      ('DELETE', 'api/icon') => _withCard(id, (id) async {
        await _ref.read(customIconsProvider).clear(id);
        return _ok();
      }),
      ('GET', 'api/wallpaper') => _wallpaper(request),
      ('PUT', 'api/wallpaper') => _uploadWallpaper(request),
      ('DELETE', 'api/wallpaper') => () async {
        await _ref.read(wallpaperStoreProvider).clear();
        return _ok();
      }(),
      _ => _error(404, 'Not found'),
    };
  }

  Response _ok() => Response.ok('{}', headers: _json);

  Response _error(int status, String message) =>
      Response(status, body: jsonEncode({'error': message}), headers: _json);

  Future<Map<String, Object?>> _body(Request request) async {
    final decoded = jsonDecode(await request.readAsString());
    if (decoded is Map<String, Object?>) return decoded;
    throw const FormatException('Expected a JSON object');
  }

  /// Runs [action] only if [id] names a card that currently exists.
  Future<Response> _withCard(
    String? id,
    Future<Response> Function(String id) action,
  ) async {
    final cards = await _ref.read(allCardsProvider.future);
    if (id == null || !cards.any((card) => card.id == id)) {
      return _error(404, 'Unknown card');
    }
    return action(id);
  }

  Future<Response> _setOrder(Map<String, Object?> body) async {
    final order = body['order'];
    if (order is! List || order.any((id) => id is! String)) {
      throw const FormatException('"order" must be a list of card ids');
    }
    await _ref.read(configProvider.notifier).setOrder(order.cast<String>());
    return _ok();
  }

  Future<Response> _setHidden(String id, Map<String, Object?> body) async {
    final hidden = body['hidden'];
    if (hidden is! bool) {
      throw const FormatException('"hidden" must be true or false');
    }
    await _ref.read(configProvider.notifier).setHidden(id, hidden);
    return _ok();
  }

  Future<Response> _icon(String id) async {
    final cards = await _ref.read(allCardsProvider.future);
    final card = cards.firstWhere((card) => card.id == id);
    // The URL carries a version, so the image behind it never changes.
    const cache = {'cache-control': 'public, max-age=31536000, immutable'};
    final path = card.iconPath;
    if (path == null) {
      return switch (card.svg) {
        null => _error(404, 'No icon'),
        final svg => Response.ok(
          svg,
          headers: {...cache, 'content-type': 'image/svg+xml'},
        ),
      };
    }
    final file = File(path);
    if (!await file.exists()) return _error(404, 'No icon');
    final bytes = await file.readAsBytes();
    return Response.ok(
      bytes,
      headers: {
        ...cache,
        'content-type': imageContentType(sniffImageExtension(bytes) ?? ''),
      },
    );
  }

  Future<Response> _uploadIcon(String id, Request request) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request.read()) {
      bytes.add(chunk);
      if (bytes.length > maxIconBytes) return _error(413, 'Image too large');
    }
    final saved = await _ref
        .read(customIconsProvider)
        .set(id, bytes.takeBytes());
    return saved ? _ok() : _error(415, 'Not a PNG, JPEG, GIF or WebP image');
  }

  Future<Response> _uploadWallpaper(Request request) async =>
      switch (await _ref.read(wallpaperStoreProvider).save(request.read())) {
        WallpaperUpload.saved => _ok(),
        WallpaperUpload.tooLarge => _error(413, 'File too large (300 MB max)'),
        WallpaperUpload.unsupported => _error(
          415,
          'Not a supported image (PNG, JPEG, GIF, WebP) or video (MP4, '
          'WebM, MKV)',
        ),
      };

  /// Serves the wallpaper for the page's preview. Byte ranges are honoured
  /// because browsers will not play a video without them.
  Future<Response> _wallpaper(Request request) async {
    final path = (await _ref.read(configProvider.future)).wallpaper;
    final file = path == null ? null : File(path);
    if (file == null || !await file.exists()) {
      return _error(404, 'No wallpaper');
    }
    final length = await file.length();
    final headers = {
      'content-type': wallpaperContentType(file.path),
      'accept-ranges': 'bytes',
      // The URL carries a version, so the file behind it never changes.
      'cache-control': 'public, max-age=31536000, immutable',
    };
    final range = RegExp(r'^bytes=(\d*)-(\d*)$')
        .firstMatch(request.headers['range'] ?? '');
    if (range == null) {
      return Response.ok(
        file.openRead(),
        headers: {...headers, 'content-length': '$length'},
      );
    }
    final first = int.tryParse(range[1]!);
    final last = int.tryParse(range[2]!);
    // "bytes=-N" asks for the final N bytes.
    final start =
        first ?? (last == null ? 0 : (length - last).clamp(0, length));
    final end = first == null || last == null || last >= length
        ? length - 1
        : last;
    if (start > end) {
      return Response(416, headers: {'content-range': 'bytes */$length'});
    }
    return Response(
      206,
      body: file.openRead(start, end + 1),
      headers: {
        ...headers,
        'content-range': 'bytes $start-$end/$length',
        'content-length': '${end - start + 1}',
      },
    );
  }

  /// Server-sent events: the current state, then every later state.
  Response _events() {
    late final StreamController<List<int>> out;
    StreamSubscription<String>? states;
    Timer? keepAlive;
    void send(String text) => out.add(utf8.encode(text));
    out = StreamController(
      onListen: () {
        if (_latestState case final state?) send('data: $state\n\n');
        states = _states.stream.listen((state) => send('data: $state\n\n'));
        // Comment lines keep idle connections from being dropped.
        keepAlive = Timer.periodic(
          const Duration(seconds: 20),
          (_) => send(': keep-alive\n\n'),
        );
      },
      onCancel: () {
        keepAlive?.cancel();
        return states?.cancel();
      },
    );
    return Response.ok(
      out.stream,
      headers: {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
      },
      context: {'shelf.io.buffer_output': false},
    );
  }
}
