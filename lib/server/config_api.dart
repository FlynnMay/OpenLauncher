import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher/server/config_page_state.dart';
import 'package:openlauncher/server/custom_icons.dart';
import 'package:openlauncher/server/editor_files.dart';
import 'package:openlauncher/server/wallpaper_store.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

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
      ('POST', 'api/remote') => _remote(id, await _body(request)),
      ('PUT', 'api/entity') => _withEntity(
        id,
        (id) async => _setEntity(id, await _body(request)),
      ),
      ('GET', 'api/icon') => _withPicture(id, _icon),
      ('PUT', 'api/icon') => _withPicture(id, (id) => _uploadIcon(id, request)),
      ('DELETE', 'api/icon') => _withPicture(id, (id) async {
        await _ref.read(customIconsProvider).clear(id);
        return _ok();
      }),
      ('GET', 'api/media/art') => _cover(id),
      ('GET', 'api/wallpaper') => _wallpaper(request, id),
      // One more, after those there are.
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

  /// Runs [action] only if [id] names an entity that currently exists.
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

  /// Like [_withEntity], but [id] may also name the entity of a popup panel
  /// (`panel:<panel id>`), which can have a picture too.
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

  /// Replaces the whole layout with the one the page sends.
  Future<Response> _setLayout(Map<String, Object?> body) async {
    final layout = Layout.fromJson(body);
    await _ref.read(configProvider.notifier).setLayout(layout);
    // Pictures of popups that no longer exist have nothing to show on.
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

  /// Sets an entity's `name` and the entity it takes its picture from
  /// (`iconFrom`); null undoes either, and whichever the body leaves out
  /// stays as it is.
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
      // An uploaded picture is replaced by the borrowed one.
      await _ref.read(customIconsProvider).clear(id);
      if (from is String) await config.setIconSource(id, from);
    }
    if (body.containsKey('name')) await config.setName(id, name);
    return _ok();
  }

  /// Sets the parts of the config the body names, each as it is saved and
  /// as the state tells it under `config`; whatever is left out stays as it
  /// is. What cannot be read is put right rather than refused, as with a
  /// layout.
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

  /// What the user's value [id] is now, as the TV has it: the page cannot
  /// ask other sites itself, and so asks the TV, which asks only the
  /// addresses it was set up with.
  Future<Response> _sourceValue(String? id) async {
    final sources = (await _ref.read(configProvider.future)).sources;
    final source = sources.where((source) => source.id == id).firstOrNull;
    if (source == null) return _error(404, 'No such value');
    if (source.kind == SourceKind.text) {
      return Response.ok(jsonEncode({'value': source.text}), headers: _json);
    }
    // What the TV shows already is not asked for twice; what it does not
    // is held on to until it has answered.
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

  /// Does on the TV what a press on the remote would (`do`): `open`, `info`,
  /// `uninstall` or `forceStop` the entity [id], `media` (`command`), `setup`,
  /// `tvSettings`, or `homeButton`, which switches it if `enabled` is given
  /// and says how it stands.
  Future<Response> _remote(String? id, Map<String, Object?> body) async {
    final platform = _ref.read(launcherPlatformProvider);
    Response reply([Map<String, Object?> said = const {}]) =>
        Response.ok(jsonEncode(said), headers: _json);
    Future<Response> onEntity(
      Future<Map<String, Object?>?> Function(Entity entity) action, {
      bool appOnly = true,
    }) => _withEntity(id, (id) async {
      final entities = await _ref.read(entitiesProvider.future);
      final entity = entities.firstWhere((entity) => entity.id == id);
      if (appOnly && entity.kind != appKind) {
        throw const FormatException('That entity is not an app');
      }
      return reply(await action(entity) ?? const {});
    });
    try {
      switch (body['do']) {
        case 'open':
          return await onEntity(appOnly: false, (entity) async {
            if (entity.kind == launcherKind) {
              throw const FormatException('That opens nothing on the TV');
            }
            // As pressing something drawn from it would.
            await _ref
                .read(actionRunnerProvider)
                .run(const Act('open'), subject: entity);
            return null;
          });
        case 'info':
          return await onEntity((entity) async {
            await platform.openAppInfo(entity.target);
            return null;
          });
        case 'uninstall':
          return await onEntity((entity) async {
            await platform.uninstallApp(entity.target);
            return null;
          });
        case 'forceStop':
          return await onEntity(
            (entity) async => {
              'done': await platform.forceStopApp(entity.target),
            },
          );
        case 'media':
          final command = MediaCommand.values
              .where((command) => command.name == body['command'])
              .firstOrNull;
          if (command == null) {
            throw const FormatException('"command" must name a media command');
          }
          await platform.sendMediaCommand(command);
          return reply();
        case 'setup':
          final result = await platform.runAutomaticSetup();
          return reply({
            'outcome': result.outcome.name,
            'detail': result.detail,
          });
        case 'tvSettings':
          await platform.openHomeButtonSettings();
          return reply();
        case 'homeButton':
          if (body['enabled'] case final enabled?) {
            if (enabled is! bool) {
              throw const FormatException('"enabled" must be true or false');
            }
            await platform.setHomeButtonEnabled(enabled);
          }
          return reply({
            'enabled': await platform.isHomeButtonEnabled(),
            'canManage': await platform.canManageHomeButton(),
          });
        default:
          throw const FormatException('"do" must name something to do');
      }
    } on FormatException {
      rethrow;
    } on Exception catch (e) {
      return _error(502, 'The TV could not do that: $e');
    }
  }

  /// Finds places by name for the weather widget. Done here rather than by
  /// the page so the page never talks to anything but the TV.
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

  Future<Response> _icon(String id) async {
    final entities = await _ref.read(entitiesProvider.future);
    final config = await _ref.read(configProvider.future);
    // Null for the entity of a popup, which only has a picture if given one.
    final entity = entities.where((entity) => entity.id == id).firstOrNull;
    // The URL carries a version, so the image behind it never changes.
    const cache = {'cache-control': 'public, max-age=31536000, immutable'};
    final path = entity == null ? config.iconOverrides[id] : entity.iconPath;
    if (path == null) {
      return switch (entity?.svg) {
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

  /// Serves the cover of what is playing, if [id] still names it.
  Future<Response> _cover(String? id) async {
    final path = (await _ref.read(nowPlayingProvider.future))?.artPath;
    final file = path == null || p.basename(path) != id ? null : File(path);
    if (file == null || !await file.exists()) return _error(404, 'No cover');
    final bytes = await file.readAsBytes();
    return Response.ok(
      bytes,
      headers: {
        'cache-control': 'public, max-age=31536000, immutable',
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

  /// Sets the order of the wallpapers (`order`, their ids) and how many
  /// minutes each stays (`every`, 0 to stay on the first); whichever the
  /// body leaves out stays as it is.
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

  /// Serves the wallpaper [id], or the first if none is named. Byte ranges
  /// are honoured because browsers will not play a video without them.
  Future<Response> _wallpaper(Request request, String? id) async {
    final paths = (await _ref.read(configProvider.future)).wallpapers;
    final path = id == null
        ? paths.firstOrNull
        : paths.where((path) => WallpaperStore.idOf(path) == id).firstOrNull;
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
