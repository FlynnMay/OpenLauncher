import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/server/config_page_state.dart';
import 'package:openlauncher/server/custom_icons.dart';
import 'package:openlauncher/server/editor_files.dart';
import 'package:openlauncher/server/wallpaper_store.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

final configApiProvider = Provider<ConfigApi>((ref) {
  final api = ConfigApi(ref);
  ref.listen(configPageStateProvider, (_, next) {
    if (next case AsyncData(:final value)) api._publish(value);
  }, fireImmediately: true);
  ref.onDispose(api._dispose);
  return api;
});

/// The HTTP API for the web editor. It uses the same providers and controller
/// as the TV UI.
class ConfigApi {
  ConfigApi(this._ref);

  static const maxIconBytes = 8 * 1024 * 1024;
  static const maxNameLength = 60;
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
    final path = request.url.path;
    if (request.method == 'GET' && EditorFiles.owns(path)) {
      return EditorFiles.serve(request);
    }
    return switch ((request.method, path)) {
      ('GET', 'api/state') => Response.ok(
        jsonEncode(await _ref.read(configPageStateProvider.future)),
        headers: _json,
      ),
      ('GET', 'api/events') => _events(),
      ('PUT', 'api/layout') => _setLayout(await _body(request)),
      ('PUT', 'api/config') => _setConfig(await _body(request)),
      ('GET', 'api/source') => _sourceValue(id),
      ('GET', 'api/geocode') => _geocode(request.url.queryParameters['q']),
      ('POST', 'api/act') => _act(await _body(request)),
      ('PUT', 'api/entity') => _withEntity(
        id,
        (id) async => _setEntity(id, await _body(request)),
      ),
      ('GET', 'api/icon') => _withPicture(id, (id) => _icon(request, id)),
      ('PUT', 'api/icon') => _withPicture(id, (id) => _uploadIcon(id, request)),
      ('DELETE', 'api/icon') => _withPicture(id, (id) async {
        await _ref.read(customIconsProvider).clear(id);
        return _ok();
      }),
      ('GET', 'api/media/art') => _cover(request, id),
      ('GET', 'api/wallpaper') => _wallpaper(request, id),
      ('POST', 'api/wallpapers') => _uploadWallpaper(request),
      ('PUT', 'api/wallpapers') => _arrangeWallpapers(await _body(request)),
      ('DELETE', 'api/wallpaper') => () async {
        final store = _ref.read(wallpaperStoreProvider);
        if (id == null) {
          await store.clear();
        } else if (!await store.remove(id)) {
          return _error(404, 'No such wallpaper');
        }
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

  /// Runs [action] if [id] is an existing entity.
  Future<Response> _withEntity(
    String? id,
    Future<Response> Function(String id) action,
  ) async {
    final entities = await _ref.read(entitiesProvider.future);
    if (id == null || !entities.any((entity) => entity.id == id)) {
      return _error(404, 'Unknown entity');
    }
    return action(id);
  }

  /// Like [_withEntity], but also accepts a folder's `panel:<id>`.
  Future<Response> _withPicture(
    String? id,
    Future<Response> Function(String id) action,
  ) async {
    final layout = (await _ref.read(configProvider.future)).layout;
    final isPanel = layout.panels.any(
      (panel) => panel.kind == PanelKind.popup && Panel.iconKey(panel.id) == id,
    );
    return isPanel ? action(id!) : _withEntity(id, action);
  }

  Future<Response> _setLayout(Map<String, Object?> body) async {
    final layout = Layout.fromJson(body);
    await _ref.read(configProvider.notifier).setLayout(layout);
    // Drop pictures of folders that no longer exist.
    final config = await _ref.read(configProvider.future);
    final kept = {
      for (final panel in config.layout.panels) Panel.iconKey(panel.id),
    };
    for (final key in config.iconOverrides.keys.toList()) {
      if (key.startsWith(Panel.iconKey('')) && !kept.contains(key)) {
        await _ref.read(customIconsProvider).clear(key);
      }
    }
    return _ok();
  }

  /// Sets `name` and `iconFrom`; null resets one, a missing key leaves it.
  Future<Response> _setEntity(String id, Map<String, Object?> body) async {
    final config = _ref.read(configProvider.notifier);
    final name = body['name'], from = body['iconFrom'];
    if (name is! String?) {
      throw const FormatException('"name" must be text or null');
    }
    if (name != null && name.trim().length > maxNameLength) {
      throw const FormatException('That name is too long');
    }
    if (body.containsKey('iconFrom')) {
      final entities = await _ref.read(entitiesProvider.future);
      if (from != null &&
          (from == id || !entities.any((entity) => entity.id == from))) {
        throw const FormatException('"iconFrom" must name another entity');
      }
      // A borrowed picture replaces an uploaded one.
      await _ref.read(customIconsProvider).clear(id);
      if (from is String) await config.setIconSource(id, from);
    }
    if (body.containsKey('name')) await config.setName(id, name);
    return _ok();
  }

  /// Sets the config keys in the body. Unreadable values fall back to
  /// defaults instead of failing.
  Future<Response> _setConfig(Map<String, Object?> body) async {
    final unknown = body.keys.where(
      (key) => !LauncherConfig.openKeys.contains(key),
    );
    if (unknown.isNotEmpty) {
      throw FormatException('Not a setting: ${unknown.join(', ')}');
    }
    await _ref.read(configProvider.notifier).patch(body);
    return _ok();
  }

  /// The current value of user source [id], fetched by the TV because the
  /// page cannot make cross-site requests.
  Future<Response> _sourceValue(String? id) async {
    final sources = (await _ref.read(configProvider.future)).sources;
    final source = sources.where((source) => source.id == id).firstOrNull;
    if (source == null) return _error(404, 'No such value');
    if (source.kind == SourceKind.text) {
      return Response.ok(jsonEncode({'value': source.text}), headers: _json);
    }
    // Reuse the value if the TV already shows it; otherwise wait for one.
    final provider = sourceValueProvider(source);
    final held = _ref.listen(provider, (_, _) {});
    try {
      final value = await _ref.read(provider.future);
      return Response.ok(jsonEncode({'value': value}), headers: _json);
    } on Exception catch (e) {
      return _error(502, 'The TV could not get that: $e');
    } finally {
      held.close();
    }
  }

  /// Runs the action in the body and answers `{message}`. There is no screen,
  /// so screen-only actions do nothing.
  Future<Response> _act(Map<String, Object?> body) async {
    final act = Act.fromJson(body);
    if (act == null) throw const FormatException('"do" must name an action');
    Entity? entity;
    if (body.containsKey(entityArg)) {
      final entities = await _ref.read(entitiesProvider.future);
      entity = entities.byId(act.arg(entityArg));
      if (entity == null) return _error(404, 'Unknown entity');
    }
    if (actionFor(act.name, entity) == null) {
      throw FormatException(
        entity == null
            ? 'There is no "${act.name}" to do'
            : 'That entity has no "${act.name}"',
      );
    }
    try {
      final message = await _ref.read(actionRunnerProvider).run(act);
      return Response.ok(jsonEncode({'message': message}), headers: _json);
    } on Exception catch (e) {
      return _error(502, 'The TV could not do that: $e');
    }
  }

  /// Geocoding for the weather, proxied so the page only talks to the TV.
  Future<Response> _geocode(String? query) async {
    if (query == null || query.trim().isEmpty) {
      throw const FormatException('"q" must name a place');
    }
    try {
      final places = await findPlaces(
        _ref.read(jsonFetcherProvider),
        query.trim(),
      );
      return Response.ok(
        jsonEncode({
          'places': [
            for (final place in places)
              {
                'name': place.name,
                'latitude': place.latitude,
                'longitude': place.longitude,
              },
          ],
        }),
        headers: _json,
      );
    } on Exception catch (e) {
      return _error(502, 'The TV could not look that up: $e');
    }
  }

  /// Serves a versioned, immutable file with byte ranges (browsers need them
  /// for video).
  Future<Response> _file(Request request, String? path, String none) async {
    if (path == null || !await File(path).exists()) return _error(404, none);
    final response = await createFileHandler(path, url: request.url.path)(
      request,
    );
    return response.change(headers: _forGood);
  }

  static const _forGood = {
    'cache-control': 'public, max-age=31536000, immutable',
  };

  Future<Response> _icon(Request request, String id) async {
    final entities = await _ref.read(entitiesProvider.future);
    final config = await _ref.read(configProvider.future);
    // Null for a folder's picture.
    final entity = entities.byId(id);
    final path = switch (entity) {
      null => config.iconOverrides[id],
      _ => entity.data[Entity.icon] as String?,
    };
    // Line art is SVG markup, not a file.
    if (path != null && entity?.data[Entity.shape] == Entity.lineArt) {
      return Response.ok(
        path,
        headers: {..._forGood, 'content-type': 'image/svg+xml'},
      );
    }
    return _file(request, path, 'No icon');
  }

  /// Serves the cover of what is playing, if [id] still names it.
  Future<Response> _cover(Request request, String? id) async {
    final path = (await _ref.read(nowPlayingProvider.future))?.artPath;
    return _file(
      request,
      path == null || p.basename(path) != id ? null : path,
      'No cover',
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

  /// Sets wallpaper `order` and `every`; a missing key is left alone.
  Future<Response> _arrangeWallpapers(Map<String, Object?> body) async {
    if (body['order'] case final order?) {
      if (order is! List || order.any((id) => id is! String)) {
        throw const FormatException('"order" must list wallpaper ids');
      }
      await _ref.read(wallpaperStoreProvider).arrange(order.cast());
    }
    if (body['every'] case final every?) {
      if (every is! num || every < 0) {
        throw const FormatException('"every" must be a number of minutes');
      }
      await _ref.read(configProvider.notifier).setWallpaperEvery(every.toInt());
    }
    return _ok();
  }

  Future<Response> _uploadWallpaper(Request request) async =>
      switch (await _ref.read(wallpaperStoreProvider).add(request.read())) {
        WallpaperUpload.saved => _ok(),
        WallpaperUpload.tooLarge => _error(413, 'File too large (300 MB max)'),
        WallpaperUpload.tooMany => _error(
          409,
          'There are ${WallpaperStore.maxCount} wallpapers already; '
          'remove one first',
        ),
        WallpaperUpload.unsupported => _error(
          415,
          'Not a supported image (PNG, JPEG, GIF, WebP) or video (MP4, '
          'WebM, MKV)',
        ),
      };

  /// Serves the wallpaper [id], or the first if none is named.
  Future<Response> _wallpaper(Request request, String? id) async {
    final paths = (await _ref.read(configProvider.future)).wallpapers;
    return _file(
      request,
      id == null
          ? paths.firstOrNull
          : paths.where((path) => WallpaperStore.idOf(path) == id).firstOrNull,
      'No wallpaper',
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
