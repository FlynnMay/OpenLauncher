import 'package:flutter/foundation.dart';

/// Everything the user can customise. Persisted as JSON by a `ConfigStore`.
@immutable
class LauncherConfig {
  const LauncherConfig({
    this.order = const [],
    this.hidden = const {},
    this.iconOverrides = const {},
    this.wallpaper,
  });

  /// Card ids in display order. Cards not listed follow, sorted by label.
  final List<String> order;

  /// Card ids that are not shown.
  final Set<String> hidden;

  /// Card id -> absolute path of a user-chosen image.
  final Map<String, String> iconOverrides;

  /// Absolute path of the image or video shown behind the home screen, or
  /// null for a plain background.
  final String? wallpaper;

  static const _keep = Object();

  LauncherConfig copyWith({
    List<String>? order,
    Set<String>? hidden,
    Map<String, String>? iconOverrides,
    // Nullable, so "not given" needs its own marker.
    Object? wallpaper = _keep,
  }) => LauncherConfig(
    order: order ?? this.order,
    hidden: hidden ?? this.hidden,
    iconOverrides: iconOverrides ?? this.iconOverrides,
    wallpaper: identical(wallpaper, _keep)
        ? this.wallpaper
        : wallpaper as String?,
  );

  factory LauncherConfig.fromJson(Map<String, dynamic> json) => LauncherConfig(
    order: [...?(json['order'] as List?)?.cast<String>()],
    hidden: {...?(json['hidden'] as List?)?.cast<String>()},
    iconOverrides: {
      ...?(json['iconOverrides'] as Map?)?.cast<String, String>(),
    },
    wallpaper: json['wallpaper'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'order': order,
    'hidden': hidden.toList(),
    'iconOverrides': iconOverrides,
    'wallpaper': ?wallpaper,
  };
}
