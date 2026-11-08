import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/components/weather.dart';
import 'package:openlauncher/core/entities/user_entities.dart';
import 'package:openlauncher_domain/config/app_version.dart';
import 'package:openlauncher_domain/config/migrations/migrations.dart';
import 'package:openlauncher_domain/entities/entity.dart';
import 'package:openlauncher_domain/layout/layout.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';
import 'package:openlauncher_domain/updates/update.dart';

enum ToastPosition { topLeft, topRight, bottomLeft, bottomRight }

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
    final enabled = json['enabled'];
    final seconds = json['seconds'];
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
  }) : layout = layout ?? Layout.blank(),
       ownLayout = ownLayout ?? layout != null;

  final Layout layout;

  /// False while [layout] is a pack's starting layout, which is not saved.
  final bool ownLayout;

  /// Picture path by entity id, or by [Layout.pictureKey] for a node.
  final Map<String, String> iconOverrides;

  /// The entity whose picture to show, by entity id.
  final Map<String, String> iconSources;

  /// Custom name by entity id.
  final Map<String, String> names;

  final List<String> wallpapers;

  /// Minutes per wallpaper; 0 stays on the first.
  final int wallpaperEvery;

  static const maxWallpaperEvery = Duration.minutesPerDay * 7;
  static const maxWallpapers = 12;

  String? get wallpaper => wallpapers.firstOrNull;

  final ToastOptions toasts;
  final List<Entity> entities;
  final Place? place;
  final List<Prefab> prefabs;
  final UpdateOptions updates;

  /// Sent whole by `PUT /api/config`; [fileKeys] travel as file ids.
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

  static const fileKeys = ['iconOverrides', 'wallpapers'];

  static const maxNameLength = 60;

  /// Why [settings] cannot be kept, or null.
  static String? settingsValidationError(Map<String, Object?> settings) {
    final unknown = settings.keys.where((key) => !openKeys.contains(key));
    if (unknown.isNotEmpty) return 'Not a setting: ${unknown.join(', ')}';
    if (settings['names'] case final Map<Object?, Object?> names
        when names.values.any(
          (name) => name is String && name.trim().length > maxNameLength,
        )) {
      return 'That name is too long';
    }
    return null;
  }

  Map<String, Object?> get open {
    final json = toJson();
    return {for (final key in openKeys) key: json[key]};
  }

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
    Place? Function()? place,
    List<Prefab>? prefabs,
    UpdateOptions? updates,
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
  );

  /// Throws [FormatException] for a save from a newer release.
  factory LauncherConfig.fromJson(
    Json saved, {
    Device device = Device.unknown,
  }) => LauncherConfig._current(_upToDate(saved, device));

  static Json _upToDate(Json saved, Device device) {
    try {
      return migrate(saved, device: device);
    } on FormatException catch (error) {
      if (isNewer(saved)) rethrow;
      _reportUnreadableLayout(error);
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

  static Layout? _savedLayout(Json json) {
    try {
      if (json['layout'] case final Map<Object?, Object?> layout) {
        return Layout.fromJson(layout).normalised();
      }
    } on FormatException catch (error) {
      _reportUnreadableLayout(error);
    }
    return null;
  }

  static void _reportUnreadableLayout(Object error) =>
      debugPrint('Saved layout unreadable, starting a new one: $error');

  Json toJson() => {
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
  };
}
