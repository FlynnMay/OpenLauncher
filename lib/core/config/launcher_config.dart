import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/components/weather.dart';
import 'package:openlauncher/core/config/migrations/migrations.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/entities/user_entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefab.dart';

enum ToastPosition { topLeft, topRight, bottomLeft, bottomRight }

/// How other apps' notifications are shown.
@immutable
class ToastOptions {
  const ToastOptions({
    this.enabled = true,
    this.position = ToastPosition.topRight,
    this.seconds = 6,
  });

  final bool enabled;
  final ToastPosition position;

  final int seconds;

  /// The editor's form is generated from this.
  static const options = [
    ComponentOption(
      'enabled',
      'Pop up over the home screen',
      OptionKind.toggle,
      usual: true,
    ),
    ComponentOption(
      'position',
      'Corner',
      OptionKind.choice,
      usual: 'topRight',
      choices: {
        'topLeft': 'Top left',
        'topRight': 'Top right',
        'bottomLeft': 'Bottom left',
        'bottomRight': 'Bottom right',
      },
    ),
    ComponentOption(
      'seconds',
      'Seconds',
      OptionKind.number,
      usual: 6,
      min: 2,
      max: 30,
    ),
  ];

  factory ToastOptions.fromJson(Map<Object?, Object?> json) {
    final enabled = json['enabled'], seconds = json['seconds'];
    return ToastOptions(
      enabled: enabled is bool ? enabled : true,
      position:
          ToastPosition.values.asNameMap()[json['position']] ??
          ToastPosition.topRight,
      seconds: seconds is num ? seconds.toInt().clamp(2, 30) : 6,
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'position': position.name,
    'seconds': seconds,
  };
}

/// Everything the user can customise.
@immutable
class LauncherConfig {
  LauncherConfig({
    Layout? layout,
    this.iconOverrides = const {},
    this.iconSources = const {},
    this.names = const {},
    this.wallpapers = const [],
    this.wallpaperEvery = 0,
    this.toasts = const ToastOptions(),
    this.entities = const [],
    this.place,
    this.prefabs = const [],
  }) : layout = layout ?? Layout.initial();

  final Layout layout;

  /// Entity id -> image path. A folder's picture is under `Layout.iconKey`.
  final Map<String, String> iconOverrides;

  /// Entity id -> the entity whose picture it shows.
  final Map<String, String> iconSources;

  /// Entity id -> custom name.
  final Map<String, String> names;

  /// Image and video paths; the first is shown unless they rotate.
  final List<String> wallpapers;

  /// Minutes per wallpaper; 0 stays on the first.
  final int wallpaperEvery;

  /// One week.
  static const maxWallpaperEvery = 7 * 24 * 60;

  String? get wallpaper => wallpapers.firstOrNull;

  final ToastOptions toasts;

  /// The entities the user made; every other entity is generated.
  final List<Entity> entities;

  /// Where the TV is; used by `location` and `weather`.
  final Place? place;

  /// User prefabs; one with a built-in's id replaces it.
  final List<Prefab> prefabs;

  /// Config keys sent whole between the TV and the editor (`PUT
  /// /api/config`). A new plain-data setting is a field plus its name here.
  /// The layout and file paths are handled separately.
  static const openKeys = ['toasts', 'entities', 'place', 'prefabs'];

  /// The [openKeys] values as saved.
  Map<String, Object?> get open {
    final json = toJson();
    return {for (final key in openKeys) key: json[key]};
  }

  /// This config with the [openKeys] present in [json] replaced.
  LauncherConfig patched(Map<String, Object?> json) => LauncherConfig.fromJson({
    ...toJson(),
    for (final key in openKeys)
      if (json.containsKey(key)) key: json[key],
  });

  LauncherConfig copyWith({
    Layout? layout,
    Map<String, String>? iconOverrides,
    Map<String, String>? iconSources,
    Map<String, String>? names,
    List<String>? wallpapers,
    int? wallpaperEvery,
    ToastOptions? toasts,
    List<Entity>? entities,
    // A function so that null can be passed.
    Place? Function()? place,
    List<Prefab>? prefabs,
  }) => LauncherConfig(
    layout: layout ?? this.layout,
    iconOverrides: iconOverrides ?? this.iconOverrides,
    iconSources: iconSources ?? this.iconSources,
    names: names ?? this.names,
    wallpapers: wallpapers ?? this.wallpapers,
    wallpaperEvery: wallpaperEvery ?? this.wallpaperEvery,
    toasts: toasts ?? this.toasts,
    entities: entities ?? this.entities,
    place: place == null ? this.place : place(),
    prefabs: prefabs ?? this.prefabs,
  );

  /// Reads a saved config, migrating older versions first.
  factory LauncherConfig.fromJson(
    Map<String, dynamic> saved, {
    Device device = Device.unknown,
  }) => LauncherConfig._current(_upToDate(saved, device));

  static Json _upToDate(Json saved, Device device) {
    try {
      return migrate(saved, device: device);
    } on FormatException catch (e) {
      // A bad layout must not lose the rest of the config.
      debugPrint('Saved layout unreadable, starting a new one: $e');
      return {...saved, 'v': saveVersion}..remove('layout');
    }
  }

  factory LauncherConfig._current(Json json) => LauncherConfig(
    layout: _savedLayout(json),
    iconOverrides: {
      ...?(json['iconOverrides'] as Map?)?.cast<String, String>(),
    },
    iconSources: _strings(json['iconSources']),
    names: _strings(json['names']),
    wallpapers: switch (json['wallpapers']) {
      final List<Object?> paths => paths.whereType<String>().toList(),
      _ => const [],
    },
    wallpaperEvery: switch (json['wallpaperEvery']) {
      final num minutes => minutes.toInt().clamp(0, maxWallpaperEvery),
      _ => 0,
    },
    toasts: switch (json['toasts']) {
      final Map<Object?, Object?> toasts => ToastOptions.fromJson(toasts),
      _ => const ToastOptions(),
    },
    entities: userEntitiesFromJson(json['entities']),
    place: placeFromJson(json['place']),
    prefabs: Prefab.listFromJson(json['prefabs']),
  );

  static Place? placeFromJson(Object? json) => switch (json) {
    {
      'name': final String name,
      'latitude': final num latitude,
      'longitude': final num longitude,
    } =>
      (
        name: name,
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      ),
    _ => null,
  };

  static Map<String, Object?>? placeToJson(Place? place) => place == null
      ? null
      : {
          'name': place.name,
          'latitude': place.latitude,
          'longitude': place.longitude,
        };

  static Map<String, String> _strings(Object? json) => {
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String && value is String) key: value,
  };

  static Layout _savedLayout(Map<String, dynamic> json) {
    try {
      if (json['layout'] case final Map<Object?, Object?> layout) {
        return Layout.fromJson(layout).normalised();
      }
    } on FormatException catch (e) {
      // A bad layout must not lose the rest of the config.
      debugPrint('Saved layout unreadable, starting a new one: $e');
    }
    return Layout.initial();
  }

  Map<String, dynamic> toJson() => {
    'v': saveVersion,
    'layout': layout.toJson(),
    'iconOverrides': iconOverrides,
    'iconSources': iconSources,
    'names': names,
    'wallpapers': wallpapers,
    'wallpaperEvery': wallpaperEvery,
    'toasts': toasts.toJson(),
    'entities': [for (final entity in entities) entity.toJson()],
    'place': ?placeToJson(place),
    'prefabs': [for (final prefab in prefabs) prefab.toJson()],
  };
}
