import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/updates/updates.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/tv/auth.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// A node with one visual module, as the catalogue offers it.
typedef VisualOffer = ({
  String module,
  String label,
  double w,
  double h,
  Map<String, Object?> values,
});

/// A file uploaded to the TV; [used] if the TV's config points at it.
typedef MediaFile = ({String id, String url, int bytes, bool used});

/// The TV's state, with every picture as a URL.
class TvState {
  const TvState({
    required this.entities,
    required this.config,
    required this.visuals,
    this.packs = const [],
    this.widgetProviders = const {},
    this.access = const {},
    this.nowPlaying,
    this.update = const UpdateState(),
  });

  /// With the user's names and pictures applied.
  final List<Entity> entities;

  final LauncherConfig config;
  final List<VisualOffer> visuals;

  /// The packs installed on the TV.
  final List<Pack> packs;

  /// App widget ids with their labels.
  final Map<String, String> widgetProviders;

  /// What the TV's settings allow the launcher; allowed unless it says not.
  final Map<Access, bool> access;

  final NowPlaying? nowPlaying;

  /// Where the TV stands against the latest release.
  final UpdateState update;
}

final tvApiProvider = Provider<TvApi>(
  (ref) => TvApi(
    onRefused: () => ref.read(pairingNeededProvider.notifier).refused(),
  ),
);

/// The TV's state, updated on every change.
final tvStateProvider = StreamProvider<TvState>(
  (ref) => ref.watch(tvApiProvider).states(),
  // Retrying cannot fix a refused session; pairing can.
  retry: (count, error) => error is NeedsPairing
      ? null
      : ProviderContainer.defaultRetry(count, error),
);

/// The TV's HTTP API, at this page's origin.
class TvApi {
  TvApi({http.Client? client, void Function()? onRefused})
    : _client = SessionClient(client ?? http.Client(), onRefused: onRefused);

  final SessionClient _client;

  final _base = Uri.base;

  /// Line art by URL; the URL changes with the drawing.
  final _drawings = <String, Future<String>>{};

  Uri _at(String path) => _base.resolve(path);

  /// Where the editor reaches uploaded file [id].
  String mediaUrl(String id) => _at('/api/media/$id').toString();

  /// The id of the uploaded file at [url].
  static String mediaIdOf(String url) => Uri.parse(url).pathSegments.last;

  /// Follows the TV's event stream, reconnecting when it drops. Fails only if
  /// the first connection does.
  Stream<TvState> states() async* {
    var reached = false;
    while (true) {
      try {
        final response = await _client.send(
          http.Request('GET', _at('/api/events')),
        );
        if (response.statusCode != 200) {
          throw Exception('The TV answered ${response.statusCode}');
        }
        final lines = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in lines) {
          if (!line.startsWith('data: ')) continue;
          yield await _state(jsonDecode(line.substring(6)) as Map);
          reached = true;
        }
      } on NeedsPairing {
        rethrow;
      } on Object {
        if (!reached) rethrow;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<TvState> _state(Map<Object?, Object?> json) async {
    final providers = json['widgetProviders'] as List;
    final config = LauncherConfig.fromJson({
      'v': saveVersion,
      ...(json['config'] as Map).cast<String, Object?>(),
      'layout': json['layout'],
    }).copyWith(ownLayout: json['ownLayout'] != false);
    return TvState(
      entities: await Future.wait([
        for (final Map entity in json['entities'] as List) _entity(entity),
      ]),
      // Files arrive as ids.
      config: config.copyWith(
        iconOverrides: {
          for (final MapEntry(:key, value: id) in config.iconOverrides.entries)
            key: mediaUrl(id),
        },
        wallpapers: [for (final id in config.wallpapers) mediaUrl(id)],
      ),
      visuals: [
        for (final Map visual in json['visuals'] as List)
          // One offer per app widget.
          for (final Map? provider
              in visual['module'] == appWidgetModule.name ? providers : [null])
            (
              module: visual['module'] as String,
              label: provider == null
                  ? visual['label'] as String
                  : '${provider['app']}: ${provider['label']}',
              w: (visual['w'] as num).toDouble(),
              h: (visual['h'] as num).toDouble(),
              values: {
                ...?moduleNamed(visual['module'] as String)?.starter,
                'provider': ?provider?['id'],
              },
            ),
      ],
      packs: [
        if (json['packs'] case final List<Object?> packs)
          for (final pack in packs) ?Pack.fromJson(pack),
      ],
      widgetProviders: {
        for (final Map provider in providers)
          provider['id'] as String: '${provider['app']}: ${provider['label']}',
      },
      access: {
        if (json['access'] case final Map<Object?, Object?> allowed)
          for (final access in Access.values)
            if (allowed[access.name] case final bool held) access: held,
      },
      nowPlaying: switch (json['nowPlaying']) {
        final Map playing => NowPlaying(
          packageName: playing['package'] as String,
          appLabel: playing['app'] as String,
          title: playing['title'] as String?,
          artist: playing['artist'] as String?,
          artPath: switch (playing['art']) {
            final String art => _at(art).toString(),
            _ => null,
          },
          playing: playing['playing'] == true,
        ),
        _ => null,
      },
      update: UpdateState.fromJson(json['update']),
    );
  }

  Future<Entity> _entity(Map<Object?, Object?> json) async {
    final entity = Entity.fromJson(json)!;
    final icon = entity.data[Entity.icon];
    if (icon is! String) return entity;
    // The icon arrives as a URL; line art is fetched as markup.
    return entity.withData({
      Entity.icon: entity.data[Entity.shape] == Entity.lineArt
          ? await _drawings.putIfAbsent(
              icon,
              () async => (await _client.get(_at(icon))).body,
            )
          : _at(icon).toString(),
    });
  }

  /// The error from the TV's reply body.
  static Exception _refused(int status, String body) {
    try {
      if (jsonDecode(body) case {'error': final String error}) {
        return Exception(error);
      }
    } on FormatException {
      // Not one of the TV's own replies.
    }
    return Exception('The TV answered $status');
  }

  Future<Object?> _ask(String method, String path, [Object? body]) async {
    final request = http.Request(method, _at(path));
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) throw _refused(response.statusCode, text);
    return jsonDecode(text);
  }

  /// The TV answers with a session cookie.
  Future<void> pair(String code, String label) =>
      _ask('POST', '/api/pair', {'code': code, 'label': label});

  Future<List<Map<String, Object?>>> devices() async {
    final reply = await _ask('GET', '/api/devices') as Map;
    return [
      for (final device in reply['devices'] as List)
        (device as Map).cast<String, Object?>(),
    ];
  }

  Future<void> revoke(String id) => _ask('DELETE', '/api/devices${_id(id)}');

  static String _id(String id) => '?id=${Uri.encodeQueryComponent(id)}';

  Future<void> setLayout(Layout layout) =>
      _ask('PUT', '/api/layout', layout.toJson());

  Future<void> revertLayout() => _ask('DELETE', '/api/layout');

  /// Sends the changed config keys, files as ids.
  Future<void> setConfig(Map<String, Object?> changed) => _ask(
    'PUT',
    '/api/config',
    {
      ...changed,
      if (changed['iconOverrides'] case final Map<Object?, Object?> pictures)
        'iconOverrides': {
          for (final MapEntry(:key, :value) in pictures.entries)
            key: mediaIdOf(value as String),
        },
      if (changed['wallpapers'] case final List<Object?> wallpapers)
        'wallpapers': [for (final url in wallpapers) mediaIdOf(url as String)],
    },
  );

  /// Uploads [file] and returns its URL; nothing points at it until the
  /// config does.
  Future<String> upload(PickedFile file, {bool wallpaper = false}) async {
    final reply = await _sendFile(
      file,
      '/api/media?as=${wallpaper ? 'wallpaper' : 'picture'}',
    );
    return mediaUrl(reply['id'] as String);
  }

  /// Every uploaded file, newest first.
  Future<List<MediaFile>> media() async => [
    for (final Map file in (await _ask('GET', '/api/media') as Map)['files'])
      (
        id: file['id'] as String,
        url: mediaUrl(file['id'] as String),
        bytes: (file['bytes'] as num).toInt(),
        used: file['used'] == true,
      ),
  ];

  /// Deletes an unused file.
  Future<void> deleteMedia(String id) => _ask('DELETE', '/api/media${_id(id)}');

  /// Deletes every unused file; returns how many.
  Future<int> deleteUnusedMedia() async =>
      ((await _ask('DELETE', '/api/media') as Map)['deleted'] as num).toInt();

  /// A file of [pack] on the TV; null if it has none at [path].
  Future<Uint8List?> packFile(Pack pack, String path) async {
    final reply = await _client.get(_at('/api/packs/${pack.id}/$path'));
    return reply.statusCode == 200 ? reply.bodyBytes : null;
  }

  /// Installs the pack in [file] (a `.zip`) and returns its id.
  Future<String> installPack(PickedFile file) async {
    final reply = await _sendFile(file, '/api/packs');
    return reply['id'] as String;
  }

  /// Streamed by the browser from disk, so not through [_client].
  Future<Map<Object?, Object?>> _sendFile(PickedFile file, String path) async {
    final reply = await file.send(
      'POST',
      _at(path),
      headers: SessionClient.headers,
    );
    _client.check(reply.status);
    if (reply.status != 200) throw _refused(reply.status, reply.body);
    return jsonDecode(reply.body) as Map;
  }

  /// Removes a pack nothing uses.
  Future<void> removePack(String id) => _ask('DELETE', '/api/packs${_id(id)}');

  /// What entity [id]'s `http` feed reads, fetched by the TV.
  Future<Object?> feedValue(String id) async =>
      (await _ask('GET', '/api/feed${_id(id)}') as Map)['value'];

  /// Runs [act] on the TV; returns its message.
  Future<String?> act(Act act) async =>
      (await _ask('POST', '/api/act', act.toJson()) as Map)['message']
          as String?;

  Future<List<Place>> findPlaces(String name) async {
    final reply = await _ask(
      'GET',
      '/api/geocode?q=${Uri.encodeQueryComponent(name)}',
    ) as Map;
    return [
      for (final Map place in reply['places'] as List)
        (
          name: place['name'] as String,
          latitude: (place['latitude'] as num).toDouble(),
          longitude: (place['longitude'] as num).toDouble(),
        ),
    ];
  }
}
