import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher/server/custom_icons.dart';
import 'package:openlauncher/server/editor_files.dart';
import 'package:openlauncher/server/wallpaper_store.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

String _iconUrl(String id, String source) =>
    '/api/icon?id=${Uri.encodeQueryComponent(id)}'
    // The source changes whenever the image does, so it doubles as a cache
    // key.
    '&v=${source.hashCode.toRadixString(36)}';

/// What the config page shows and edits, as JSON: the wallpaper, every card
/// there is (placed or not), the layout, and what there is to choose from.
final configPageStateProvider = FutureProvider<Map<String, Object?>>((
  ref,
) async {
  final cards = await ref.watch(allCardsProvider.future);
  final config = await ref.watch(configProvider.future);
  final providers = await ref.watch(widgetProvidersProvider.future);
  // Not waited for: the page is worth showing before this is known.
  final playing = ref.watch(nowPlayingProvider).value;
  final wallpapers = [
    for (final path in config.wallpapers)
      if (Wallpaper.fromPath(path) case final wallpaper?)
        {
          'id': WallpaperStore.idOf(path),
          'kind': wallpaper.kind.name,
          // A file never changes under its name, so this caches for good.
          'url':
              '/api/wallpaper?id='
              '${Uri.encodeQueryComponent(WallpaperStore.idOf(path))}',
        },
  ];
  return {
    'wallpapers': wallpapers,
    // Minutes each one stays, or 0 to stay on the first.
    'wallpaperEvery': config.wallpaperEvery,
    'cards': [
      for (final card in cards)
        {
          'id': card.id,
          'kind': card.kind.name,
          'label': card.label,
          // Whether the user chose the name, rather than the device.
          'renamed': config.names.containsKey(card.id),
          // An uploaded picture, or another card's.
          'customIcon':
              config.iconOverrides.containsKey(card.id) ||
              config.iconSources.containsKey(card.id),
          // The card whose picture this one shows, if any.
          'iconFrom': config.iconSources[card.id],
          'wide': card.wideIcon,
          // Line art, drawn straight on the wallpaper with no card behind.
          'bare': card.iconPath == null && card.svg != null,
          'icon': switch (card.iconPath ?? card.svg) {
            null => null,
            final source => _iconUrl(card.id, source),
          },
        },
    ],
    // Exactly what the TV arranges: cards placed nowhere are already in
    // their section, and cards that are gone are left out.
    'layout': config.layout.withCards(cards.map((card) => card.id)).toJson(),
    // Pictures the user gave to cards that open a popup, by panel id.
    'panelIcons': {
      for (final panel in config.layout.panels)
        if (config.iconOverrides[PanelEntry.iconKey(panel.id)] case final path?)
          panel.id: _iconUrl(PanelEntry.iconKey(panel.id), path),
    },
    'widgets': [
      for (final kind in WidgetKind.values)
        // App widgets are only offered where there are some.
        if (kind != WidgetKind.android || providers.isNotEmpty)
          {
            'type': kind.name,
            'label': kind.label,
            'w': kind.defaultW,
            'h': kind.defaultH,
          },
    ],
    'widgetProviders': [
      for (final provider in providers)
        {'id': provider.id, 'label': provider.label, 'app': provider.appLabel},
    ],
    'actions': [
      for (final action in CardAction.values)
        {'id': action.name, 'label': action.label},
    ],
    'contextMenu': [for (final action in config.contextMenu) action.name],
    'toasts': config.toasts.toJson(),
    // Toasts and the now-playing widget stay empty without it.
    'notificationAccess': await ref.watch(notificationAccessProvider.future),
    // What the now-playing widget shows, or null.
    'nowPlaying': playing == null
        ? null
        : {
            'package': playing.packageName,
            'app': playing.appLabel,
            'title': playing.title,
            'artist': playing.artist,
            'playing': playing.playing,
            // A cover never changes under its name, so this caches for good.
            'art': switch (playing.artPath) {
              null => null,
              final path =>
                '/api/media/art?id=${Uri.encodeQueryComponent(p.basename(path))}',
            },
          },
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
      ('PUT', 'api/options') => _setOptions(await _body(request)),
      ('GET', 'api/geocode') => _geocode(request.url.queryParameters['q']),
      ('POST', 'api/remote') => _remote(id, await _body(request)),
      ('PUT', 'api/card') => _withCard(
        id,
        (id) async => _setCard(id, await _body(request)),
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

  /// Like [_withCard], but [id] may also name the card of a popup panel
  /// (`panel:<panel id>`), which can have a picture too.
  Future<Response> _withPicture(
    String? id,
    Future<Response> Function(String id) action,
  ) async {
    final layout = (await _ref.read(configProvider.future)).layout;
    final isPanel = layout.panels.any(
      (panel) =>
          panel.kind == PanelKind.popup && PanelEntry.iconKey(panel.id) == id,
    );
    return isPanel ? action(id!) : _withCard(id, action);
  }

  /// Replaces the whole layout with the one the page sends.
  Future<Response> _setLayout(Map<String, Object?> body) async {
    final layout = Layout.fromJson(body);
    await _ref.read(configProvider.notifier).setLayout(layout);
    // Pictures of popups that no longer exist have nothing to show on.
    final config = await _ref.read(configProvider.future);
    final kept = {
      for (final panel in config.layout.panels) PanelEntry.iconKey(panel.id),
    };
    for (final key in config.iconOverrides.keys.toList()) {
      if (key.startsWith(PanelEntry.iconKey('')) && !kept.contains(key)) {
        await _ref.read(customIconsProvider).clear(key);
      }
    }
    return _ok();
  }

  /// Sets a card's `name` and the card it takes its picture from
  /// (`iconFrom`); null undoes either, and whichever the body leaves out
  /// stays as it is.
  Future<Response> _setCard(String id, Map<String, Object?> body) async {
    final config = _ref.read(configProvider.notifier);
    final name = body['name'], from = body['iconFrom'];
    if (name is! String?) {
      throw const FormatException('"name" must be text or null');
    }
    if (name != null && name.trim().length > maxNameLength) {
      throw const FormatException('That name is too long');
    }
    if (body.containsKey('iconFrom')) {
      final cards = await _ref.read(allCardsProvider.future);
      if (from != null &&
          (from == id || !cards.any((card) => card.id == from))) {
        throw const FormatException('"iconFrom" must name another card');
      }
      // An uploaded picture is replaced by the borrowed one.
      await _ref.read(customIconsProvider).clear(id);
      if (from is String) await config.setIconSource(id, from);
    }
    if (body.containsKey('name')) await config.setName(id, name);
    return _ok();
  }

  /// Sets the quick actions (`contextMenu`) and how notifications pop up
  /// (`toasts`); whichever the body leaves out stays as it is.
  Future<Response> _setOptions(Map<String, Object?> body) async {
    final config = _ref.read(configProvider.notifier);
    if (body['contextMenu'] case final menu?) {
      final actions = [
        if (menu is List)
          for (final name in menu) ?CardAction.named(name),
      ];
      if (menu is! List || actions.length != menu.length) {
        throw const FormatException('"contextMenu" must list action ids');
      }
      await config.setContextMenu(actions.toSet().toList());
    }
    if (body['toasts'] case final toasts?) {
      if (toasts is! Map<String, Object?>) {
        throw const FormatException('"toasts" must be an object');
      }
      await config.setToasts(ToastOptions.fromJson(toasts));
    }
    return _ok();
  }

  /// Does on the TV what a press on the remote would (`do`): `open`, `info`,
  /// `uninstall` or `forceStop` the card [id], `media` (`command`), `setup`,
  /// `tvSettings`, or `homeButton`, which switches it if `enabled` is given
  /// and says how it stands.
  Future<Response> _remote(String? id, Map<String, Object?> body) async {
    final platform = _ref.read(launcherPlatformProvider);
    Response reply([Map<String, Object?> said = const {}]) =>
        Response.ok(jsonEncode(said), headers: _json);
    Future<Response> onCard(
      Future<Map<String, Object?>?> Function(LauncherCard card) action, {
      bool appOnly = true,
    }) => _withCard(id, (id) async {
      final cards = await _ref.read(allCardsProvider.future);
      final card = cards.firstWhere((card) => card.id == id);
      if (appOnly && card.kind != CardKind.app) {
        throw const FormatException('That card is not an app');
      }
      return reply(await action(card) ?? const {});
    });
    try {
      switch (body['do']) {
        case 'open':
          return await onCard(appOnly: false, (card) async {
            if (card.kind == CardKind.action) {
              throw const FormatException('That card opens nothing on the TV');
            }
            await _ref.read(cardActionsProvider).launch(card);
            return null;
          });
        case 'info':
          return await onCard((card) async {
            await platform.openAppInfo(card.target);
            return null;
          });
        case 'uninstall':
          return await onCard((card) async {
            await platform.uninstallApp(card.target);
            return null;
          });
        case 'forceStop':
          return await onCard(
            (card) async => {'done': await platform.forceStopApp(card.target)},
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
    final cards = await _ref.read(allCardsProvider.future);
    final config = await _ref.read(configProvider.future);
    // Null for the card of a popup, which only has a picture if given one.
    final card = cards.where((card) => card.id == id).firstOrNull;
    // The URL carries a version, so the image behind it never changes.
    const cache = {'cache-control': 'public, max-age=31536000, immutable'};
    final path = card == null ? config.iconOverrides[id] : card.iconPath;
    if (path == null) {
      return switch (card?.svg) {
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
