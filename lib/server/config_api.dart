import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/media/media_dirs.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/sources/sources.dart';
import 'package:openlauncher/server/auth.dart';
import 'package:openlauncher/server/config_page_state.dart';
import 'package:openlauncher/server/editor_files.dart';
import 'package:openlauncher/server/media_store.dart';
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

  static const maxNameLength = 60;

  static const _media = 'api/media/';
  static const _packs = 'api/packs/';
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

  Future<Response> handle(Request request) async => _handler(request);

  late final Handler _handler = () {
    final auth = _ref.read(authProvider);
    final api = const Pipeline()
        .addMiddleware(auth.sessions)
        .addHandler(_serve);
    return const Pipeline()
        .addMiddleware(auth.hostCheck)
        .addHandler(
          (request) =>
              request.method == 'GET' && EditorFiles.owns(request.url.path)
              ? EditorFiles.serve(request)
              : api(request),
        );
  }();

  Future<Response> _serve(Request request) async {
    try {
      return await _route(request);
    } on FormatException catch (e) {
      return _error(400, e.message);
    } on MediaRefused catch (e) {
      return _error(e.status, e.message);
    } on PackRefused catch (e) {
      return _error(e.status, e.message);
    }
  }

  Future<Response> _route(Request request) async {
    final id = request.url.queryParameters['id'];
    final path = request.url.path;
    if (request.method == 'GET' && path.startsWith(_media)) {
      final file = await _ref
          .read(mediaStoreProvider)
          .pathOf(path.substring(_media.length));
      return _file(request, file, 'No such file');
    }
    if (request.method == 'GET' && path.startsWith(_packs)) {
      return _packFile(request, path.substring(_packs.length));
    }
    final media = _ref.read(mediaStoreProvider);
    final packs = _ref.read(packStoreProvider);
    return switch ((request.method, path)) {
      ('GET', 'api/state') => Response.ok(
        jsonEncode(await _ref.read(configPageStateProvider.future)),
        headers: _json,
      ),
      ('GET', 'api/events') => _events(),
      ('PUT', 'api/layout') => _setLayout(await _body(request)),
      // Back to the starting layout.
      ('DELETE', 'api/layout') => () async {
        await _ref.read(configProvider.notifier).revertLayout();
        return _ok();
      }(),
      ('PUT', 'api/config') => _setConfig(await _body(request)),
      ('GET', 'api/feed') => _feedValue(id),
      ('GET', 'api/geocode') => _geocode(request.url.queryParameters['q']),
      ('POST', 'api/act') => _act(await _body(request)),
      ('GET', 'api/icon') => _withEntity(id, (id) => _icon(request, id)),
      ('GET', 'api/playing/art') => _cover(request, id),
      ('GET', 'api/media') => Response.ok(
        jsonEncode({
          'files': [
            for (final file in await media.list())
              {'id': file.id, 'bytes': file.bytes, 'used': file.used},
          ],
        }),
        headers: _json,
      ),
      ('POST', 'api/media') => _upload(request),
      // Without an id, every file nothing points at.
      ('DELETE', 'api/media') => () async {
        if (id == null) {
          return Response.ok(
            jsonEncode({'deleted': await media.deleteUnused()}),
            headers: _json,
          );
        }
        await media.delete(id);
        return _ok();
      }(),
      ('POST', 'api/packs') => () async {
        final pack = await packs.install(request.read());
        return Response.ok(jsonEncode({'id': pack.id}), headers: _json);
      }(),
      ('DELETE', 'api/packs') => () async {
        if (id == null) throw const FormatException('"id" must name a pack');
        await packs.delete(id);
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

  Future<Response> _setLayout(Map<String, Object?> body) async {
    await _ref.read(configProvider.notifier).setLayout(Layout.fromJson(body));
    return _ok();
  }

  /// Sets the config keys in the body; files are named by id. Unreadable
  /// values fall back to defaults instead of failing.
  Future<Response> _setConfig(Map<String, Object?> body) async {
    final unknown = body.keys.where(
      (key) => !LauncherConfig.openKeys.contains(key),
    );
    if (unknown.isNotEmpty) {
      throw FormatException('Not a setting: ${unknown.join(', ')}');
    }
    if (body['names'] case final Map<Object?, Object?> names
        when names.values.any(
          (name) => name is String && name.trim().length > maxNameLength,
        )) {
      throw const FormatException('That name is too long');
    }
    await _ref
        .read(configProvider.notifier)
        .patch(await _ref.read(mediaStoreProvider).withPaths(body));
    return _ok();
  }

  /// What entity [id]'s `http` feed reads, fetched by the TV because the
  /// page cannot make cross-site requests.
  Future<Response> _feedValue(String? id) async {
    final entity = (await _ref.read(entitiesProvider.future)).byId(id);
    final at = entity?.feed?.at(entity.id);
    // Only the web's: the editor reads the rest itself.
    if (at == null || at.source.answeredHere) {
      return _error(404, 'No such feed');
    }
    // Reuse the value if the TV already shows it; otherwise wait for one.
    final provider = sourceValueProvider(at);
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

  /// Runs the action in the body and answers `{message}`; 400 if it names no
  /// entity that can do it. There is no screen, so screen-only actions do
  /// nothing.
  Future<Response> _act(Map<String, Object?> body) async {
    final act = Act.fromJson(body);
    if (act == null) {
      throw const FormatException(
        '"do" must name an action, or "run" an address',
      );
    }
    try {
      final message = await _ref.read(actionRunnerProvider).run(act);
      return Response.ok(jsonEncode({'message': message}), headers: _json);
    } on ImproperAct {
      rethrow;
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

  /// Serves a pack's file, given as `<pack id>/<path in the pack>`. Checked
  /// with the TV each time: a pack can be replaced by one of the same
  /// version.
  Future<Response> _packFile(Request request, String name) async {
    final at = name.indexOf('/');
    final path = at < 0
        ? null
        : await _ref
              .read(packStoreProvider)
              .pathOf(name.substring(0, at), name.substring(at + 1));
    if (path == null) return _error(404, 'No such file');
    final response = await createFileHandler(path, url: request.url.path)(
      request,
    );
    return response.change(headers: const {'cache-control': 'no-cache'});
  }

  static const _forGood = {
    'cache-control': 'public, max-age=31536000, immutable',
  };

  Future<Response> _icon(Request request, String id) async {
    final entity = (await _ref.read(entitiesProvider.future)).byId(id);
    final path = entity?.data[Entity.icon] as String?;
    // Line art may be SVG markup rather than a file.
    if (path != null &&
        path.startsWith('<') &&
        entity?.data[Entity.shape] == Entity.lineArt) {
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

  /// Keeps the file in the body for `as` (a `picture` or a `wallpaper`) and
  /// answers its `{id}`.
  Future<Response> _upload(Request request) async {
    final use = MediaUse.values.asNameMap()[request.url.queryParameters['as']];
    if (use == null) {
      throw const FormatException('"as" must be picture or wallpaper');
    }
    final id = await _ref.read(mediaStoreProvider).add(request.read(), use);
    return Response.ok(jsonEncode({'id': id}), headers: _json);
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
