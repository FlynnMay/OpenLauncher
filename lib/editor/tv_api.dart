import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
import 'package:openlauncher/editor/file_pick.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// A component the TV can show, as the catalogue offers it.
typedef ComponentOffer = ({
  String type,
  String label,
  double w,
  double h,
  Map<String, Object?> options,
});

/// What the user has changed about an entity, beyond where it is.
typedef EntityDetails = ({bool renamed, bool customIcon, String? iconFrom});

/// What the TV says it has: the same things the launcher on the TV works
/// from, with every picture as the address the TV serves it at.
class TvState {
  const TvState({
    required this.entities,
    required this.config,
    required this.components,
    this.details = const {},
    this.wallpapers = const [],
    this.wallpaperEvery = 0,
    this.widgetProviders = const {},
    this.notificationAccess = true,
    this.homeButton = true,
    this.canManageHomeButton = false,
    this.nowPlaying,
  });

  /// Every entity, with the user's names and pictures already applied.
  final List<Entity> entities;

  /// The layout, the pictures of folders and the options.
  final LauncherConfig config;
  final List<ComponentOffer> components;

  /// By entity id.
  final Map<String, EntityDetails> details;

  /// Every wallpaper, by the name the TV knows it by, in order.
  final List<({String id, Wallpaper wallpaper})> wallpapers;

  /// How many minutes each wallpaper stays; 0 to stay on the first.
  final int wallpaperEvery;

  /// The app widgets there are to show, by id, with how each is called.
  final Map<String, String> widgetProviders;

  /// Whether the TV lets the launcher see notifications and what plays.
  final bool notificationAccess;

  /// Whether the TV remote's Home button opens the launcher.
  final bool homeButton;

  /// Whether the launcher may switch that itself.
  final bool canManageHomeButton;

  /// What is playing on the TV, if anything.
  final NowPlaying? nowPlaying;
}

final tvApiProvider = Provider<TvApi>((ref) => TvApi());

/// What the TV has, and again each time it changes.
final tvStateProvider = StreamProvider<TvState>(
  (ref) => ref.watch(tvApiProvider).states(),
);

/// The TV's config API, at the address this page came from.
class TvApi {
  final _client = http.Client();
  final _base = Uri.base;

  /// Line art by address: the address changes when the drawing does.
  final _drawings = <String, Future<String>>{};

  Uri _at(String path) => _base.resolve(path);

  /// Follows the TV's event stream, joining it again whenever it is lost.
  /// Fails only if the TV cannot be reached to begin with.
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
      } on Object {
        if (!reached) rethrow;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<TvState> _state(Map<Object?, Object?> json) async {
    final providers = json['widgetProviders'] as List;
    return TvState(
      entities: await Future.wait([
        for (final Map entity in json['entities'] as List) _entity(entity),
      ]),
      // Every plain setting comes as it is saved, whatever there are.
      config:
          LauncherConfig.fromJson({
            'v': saveVersion,
            ...(json['config'] as Map).cast<String, Object?>(),
            'layout': json['layout'],
          }).copyWith(
            iconOverrides: {
              for (final MapEntry(:key, :value)
                  in (json['panelIcons'] as Map).entries)
                Panel.iconKey(key as String): _at(value as String).toString(),
            },
          ),
      components: [
        for (final Map component in json['components'] as List)
          // An app widget is offered once for each one an app provides.
          for (final Map? provider
              in component['type'] == 'android' ? providers : [null])
            (
              type: component['type'] as String,
              label: provider == null
                  ? component['label'] as String
                  : '${provider['app']}: ${provider['label']}',
              w: (component['w'] as num).toDouble(),
              h: (component['h'] as num).toDouble(),
              options: {
                ...?ComponentKind.named(component['type'] as String)?.starter,
                'provider': ?provider?['id'],
              },
            ),
      ],
      details: {
        for (final Map entity in json['entities'] as List)
          entity['id'] as String: (
            renamed: entity['renamed'] == true,
            customIcon: entity['customIcon'] == true,
            iconFrom: entity['iconFrom'] as String?,
          ),
      },
      wallpapers: [
        for (final Map wallpaper in json['wallpapers'] as List)
          (
            id: wallpaper['id'] as String,
            wallpaper: Wallpaper(
              _at(wallpaper['url'] as String).toString(),
              WallpaperKind.values.byName(wallpaper['kind'] as String),
            ),
          ),
      ],
      wallpaperEvery: (json['wallpaperEvery'] as num).toInt(),
      widgetProviders: {
        for (final Map provider in providers)
          provider['id'] as String: '${provider['app']}: ${provider['label']}',
      },
      notificationAccess: json['notificationAccess'] != false,
      homeButton: switch (json['homeButton']) {
        {'enabled': false} => false,
        _ => true,
      },
      canManageHomeButton: switch (json['homeButton']) {
        {'canManage': true} => true,
        _ => false,
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
    );
  }

  Future<Entity> _entity(Map<Object?, Object?> json) async {
    final data = (json['data'] as Map).cast<String, Object?>();
    final icon = data[Entity.icon];
    return Entity(
      id: json['id'] as String,
      category: json['category'] as String,
      label: json['label'] as String,
      name: json['name'] as String?,
      data: {
        ...data,
        // On the TV its picture is a file, or the drawing itself; here it
        // is where the TV serves that file, or the drawing fetched.
        if (icon is String)
          Entity.icon: data[Entity.shape] == Entity.lineArt
              ? await _drawings.putIfAbsent(
                  icon,
                  () async => (await _client.get(_at(icon))).body,
                )
              : _at(icon).toString(),
      },
    );
  }

  /// What the TV said was wrong, from the body of its reply.
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
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request),
    );
    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode != 200) throw _refused(response.statusCode, text);
    return jsonDecode(text);
  }

  Future<void> _upload(String method, String path, PickedFile file) async {
    final reply = await file.send(method, _at(path));
    if (reply.status != 200) throw _refused(reply.status, reply.body);
  }

  static String _id(String id) => '?id=${Uri.encodeQueryComponent(id)}';

  Future<void> setLayout(Layout layout) =>
      _ask('PUT', '/api/layout', layout.toJson());

  /// Sets the plain settings [changed] names, each as it is saved.
  Future<void> setConfig(Map<String, Object?> changed) =>
      _ask('PUT', '/api/config', changed);

  /// What the user's value [id] is now, asked of the TV, which asks its
  /// source.
  Future<Object?> sourceValue(String id) async =>
      (await _ask('GET', '/api/source${_id(id)}') as Map)['value'];

  /// Gives the entity [id], or the entity of the popup `panel:<id>`, the
  /// picture [file].
  Future<void> setPicture(String id, PickedFile file) =>
      _upload('PUT', '/api/icon${_id(id)}', file);

  /// Returns an entity to its own picture, whether it had one given to it or
  /// borrowed another entity's.
  Future<void> clearPicture(String id) => _ask('DELETE', '/api/icon${_id(id)}');

  /// Has the entity [id] show the picture of the entity [from].
  Future<void> borrowPicture(String id, String from) =>
      _ask('PUT', '/api/entity${_id(id)}', {'iconFrom': from});

  /// Names the entity [id]; null gives it back the name the TV has for it.
  Future<void> rename(String id, String? name) =>
      _ask('PUT', '/api/entity${_id(id)}', {'name': name});

  Future<void> addWallpaper(PickedFile file) =>
      _upload('POST', '/api/wallpapers', file);

  Future<void> removeWallpaper(String id) =>
      _ask('DELETE', '/api/wallpaper${_id(id)}');

  /// Sets the order of the wallpapers, by id, and how many minutes each
  /// stays; whichever is left out stays as it is.
  Future<void> arrangeWallpapers({List<String>? order, int? every}) =>
      _ask('PUT', '/api/wallpapers', {'order': ?order, 'every': ?every});

  /// Has the TV do [act], and returns what it has to tell the user of it.
  Future<String?> act(Act act) async =>
      (await _ask('POST', '/api/act', act.toJson()) as Map)['message']
          as String?;

  /// Finds places by name, for the weather component.
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
