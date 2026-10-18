import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/components/weather.dart';
import 'package:openlauncher/core/config/app_version.dart';
import 'package:openlauncher/core/config/migrations/migrations.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/entities/user_entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/prefabs/prefab.dart';
import 'package:openlauncher/core/updates/update.dart';

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
    Field(
      'enabled',
      'Show notifications',
      FieldKind.toggle,
      defaultValue: true,
    ),
    Field(
      'position',
      'Position',
      FieldKind.choice,
      defaultValue: 'topRight',
      choices: {
        'topLeft': 'Top left',
        'topRight': 'Top right',
        'bottomLeft': 'Bottom left',
        'bottomRight': 'Bottom right',
      },
    ),
    Field(
      'seconds',
      'Duration (s)',
      FieldKind.number,
      defaultValue: 6,
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
    bool? ownLayout,
    this.iconOverrides = const {},
    this.iconSources = const {},
    this.names = const {},
    this.wallpapers = const [],
    this.wallpaperEvery = 0,
    this.toasts = const ToastOptions(),
    this.entities = const [],
    this.place,
    this.prefabs = const [],
    this.updates = const UpdateOptions(),
    this.lastScreen,
  }) : layout = layout ?? Layout.blank(),
       ownLayout = ownLayout ?? layout != null;

  final Layout layout;

  /// Whether [layout] is the user's. If not it is a pack's starting layout,
  /// read from the pack and not saved.
  final bool ownLayout;

  /// Entity id -> image path. A node's picture is under `Layout.pictureKey`.
  /// In the editor the paths are the TV's URLs.
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

  static const maxWallpapers = 12;

  String? get wallpaper => wallpapers.firstOrNull;

  final ToastOptions toasts;

  /// The entities the user made; every other entity is generated.
  final List<Entity> entities;

  /// Where the TV is; used by `location` and `weather`.
  final Place? place;

  /// User prefabs; one with a built-in's id replaces it.
  final List<Prefab> prefabs;

  /// What is done about a newer release of the launcher.
  final UpdateOptions updates;

  /// The screen shown last, kept for a startup that remembers it.
  final String? lastScreen;

  /// Config keys sent whole between the TV and the editor (`PUT
  /// /api/config`). A new plain-data setting is a field plus its name here.
  /// The layout is sent separately; [fileKeys] travel as file ids.
  static const openKeys = [
    'toasts',
    'updates',
    'entities',
    'place',
    'prefabs',
    'names',
    'iconSources',
    'wallpaperEvery',
    ...fileKeys,
  ];

  /// The [openKeys] that point at uploaded files.
  static const fileKeys = ['iconOverrides', 'wallpapers'];

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

  /// Giving a [layout] makes it the user's unless [ownLayout] says not.
  LauncherConfig copyWith({
    Layout? layout,
    bool? ownLayout,
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
    UpdateOptions? updates,
    String? Function()? lastScreen,
  }) => LauncherConfig(
    layout: layout ?? this.layout,
    ownLayout: ownLayout ?? (layout != null || this.ownLayout),
    iconOverrides: iconOverrides ?? this.iconOverrides,
    iconSources: iconSources ?? this.iconSources,
    names: names ?? this.names,
    wallpapers: wallpapers ?? this.wallpapers,
    wallpaperEvery: wallpaperEvery ?? this.wallpaperEvery,
    toasts: toasts ?? this.toasts,
    entities: entities ?? this.entities,
    place: place == null ? this.place : place(),
    prefabs: prefabs ?? this.prefabs,
    updates: updates ?? this.updates,
    lastScreen: lastScreen == null ? this.lastScreen : lastScreen(),
  );

  /// Reads a saved config, migrating older versions first. Throws
  /// [FormatException] for one from a newer release.
  factory LauncherConfig.fromJson(
    Map<String, dynamic> saved, {
    Device device = Device.unknown,
  }) => LauncherConfig._current(_upToDate(saved, device));

  static Json _upToDate(Json saved, Device device) {
    try {
      return migrate(saved, device: device);
    } on FormatException catch (e) {
      if (isNewer(saved)) rethrow;
      // A bad layout must not lose the rest of the config.
      debugPrint('Saved layout unreadable, starting a new one: $e');
      return {...saved, 'v': saveVersion}..remove('layout');
    }
  }

  factory LauncherConfig._current(Json json) => LauncherConfig(
    layout: _savedLayout(json),
    iconOverrides: _strings(json['iconOverrides']),
    iconSources: _strings(json['iconSources']),
    names: _strings(json['names']),
    wallpapers: switch (json['wallpapers']) {
      final List<Object?> paths =>
        paths.whereType<String>().take(maxWallpapers).toList(),
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
    updates: switch (json['updates']) {
      final Map<Object?, Object?> updates => UpdateOptions.fromJson(updates),
      _ => const UpdateOptions(),
    },
    lastScreen: switch (json['lastScreen']) {
      final String id => id,
      _ => null,
    },
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

  static Layout? _savedLayout(Map<String, dynamic> json) {
    try {
      if (json['layout'] case final Map<Object?, Object?> layout) {
        return Layout.fromJson(layout).normalised();
      }
    } on FormatException catch (e) {
      // A bad layout must not lose the rest of the config.
      debugPrint('Saved layout unreadable, starting a new one: $e');
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'v': saveVersion,
    'app': appVersion,
    if (ownLayout) 'layout': layout.toJson(),
    'iconOverrides': iconOverrides,
    'iconSources': iconSources,
    'names': names,
    'wallpapers': wallpapers,
    'wallpaperEvery': wallpaperEvery,
    'toasts': toasts.toJson(),
    'entities': [for (final entity in entities) entity.toJson()],
    'place': ?placeToJson(place),
    'prefabs': [for (final prefab in prefabs) prefab.toJson()],
    'updates': updates.toJson(),
    'lastScreen': ?lastScreen,
  };
}
