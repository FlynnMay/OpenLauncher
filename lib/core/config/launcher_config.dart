import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/components/weather.dart';
import 'package:openlauncher/core/config/migrations/migrations.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefab.dart';
import 'package:openlauncher/core/values/built_in_values.dart';
import 'package:openlauncher/core/values/data_source.dart';

enum ToastPosition { topLeft, topRight, bottomLeft, bottomRight }

/// How notifications from other apps pop up over the home screen.
@immutable
class ToastOptions {
  const ToastOptions({
    this.enabled = true,
    this.position = ToastPosition.topRight,
    this.seconds = 6,
  });

  final bool enabled;
  final ToastPosition position;

  /// How long each one stays up.
  final int seconds;

  /// What there is to set about them: the editor's form is made from
  /// this.
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

/// Everything the user can customise. Persisted as JSON by a `ConfigStore`.
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
    this.sources = const [],
    this.place,
    this.prefabs = const [],
  }) : layout = layout ?? Layout.initial();

  /// Where every entity, folder and component is.
  final Layout layout;

  /// Entity id -> absolute path of a user-chosen image. Entities that open a
  /// popup are keyed `panel:<panel id>`.
  final Map<String, String> iconOverrides;

  /// Entity id -> id of the entity whose picture it shows instead of its own.
  final Map<String, String> iconSources;

  /// Entity id -> the name the user gave it.
  final Map<String, String> names;

  /// Absolute paths of the images and videos shown behind the home screen;
  /// none for a plain background. The first is the one shown, unless they
  /// take turns.
  final List<String> wallpapers;

  /// How many minutes each wallpaper stays before the next takes its turn;
  /// 0 to stay on the first.
  final int wallpaperEvery;

  /// The longest [wallpaperEvery] may be: a week.
  static const maxWallpaperEvery = 7 * 24 * 60;

  /// The first wallpaper, which is the only one unless they take turns.
  String? get wallpaper => wallpapers.firstOrNull;

  final ToastOptions toasts;

  /// The values the user defined, which text on the screen can be made of
  /// beside the launcher's own.
  final List<DataSource> sources;

  /// Where the TV is, as the user said: the `location` value, and where
  /// the `weather` value is the weather of.
  final Place? place;

  /// The prefabs the user made, and their changed copies of the launcher's
  /// own, which stand in for those by having the same id.
  final List<Prefab> prefabs;

  /// The parts of the config that are carried whole between the TV and
  /// whatever edits it: told in the state, set through `PUT /api/config`,
  /// sent back by the editor when they change. **A new setting that is
  /// plain data is a field here and its name in this list, and nothing
  /// anywhere else.** What is not here needs more than carrying: the layout
  /// (repaired, and its pictures tidied), and whatever holds the paths of
  /// files on the TV, which no page may choose.
  static const openKeys = ['toasts', 'sources', 'place', 'prefabs'];

  /// The [openKeys] parts as they are saved; one that is not set is null.
  Map<String, Object?> get open {
    final json = toJson();
    return {for (final key in openKeys) key: json[key]};
  }

  /// This config with the [openKeys] parts that [json] has set to what it
  /// says. Like anything read from a save, what cannot be read falls back
  /// to how it is when nothing was chosen.
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
    List<DataSource>? sources,
    // A function, so that it can be taken away: null leaves it as it is.
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
    sources: sources ?? this.sources,
    place: place == null ? this.place : place(),
    prefabs: prefabs ?? this.prefabs,
  );

  /// Reads a saved config of any version: an older one is brought up to
  /// date first, by the steps in `migrations`, which do better for knowing
  /// the [device]. Only what is written now is read here.
  factory LauncherConfig.fromJson(
    Map<String, dynamic> saved, {
    Device device = Device.unknown,
  }) => LauncherConfig._current(_upToDate(saved, device));

  static Json _upToDate(Json saved, Device device) {
    try {
      return migrate(saved, device: device);
    } on FormatException catch (e) {
      // A broken layout must not take the wallpaper and pictures with it.
      debugPrint('Saved layout unreadable, starting a new one: $e');
      // The rest is read as it stands.
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
    sources: DataSource.listFromJson(json['sources'], taken: builtInRoots),
    place: placeFromJson(json['place']),
    prefabs: Prefab.listFromJson(json['prefabs']),
  );

  /// A place as it is saved, or null for anything else.
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
      // A broken layout must not take the wallpaper and pictures with it.
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
    'sources': [for (final source in sources) source.toJson()],
    'place': ?placeToJson(place),
    'prefabs': [for (final prefab in prefabs) prefab.toJson()],
  };
}
