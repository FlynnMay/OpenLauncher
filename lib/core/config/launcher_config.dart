import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/layout/layout.dart';

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
    this.wallpaper,
    this.contextMenu = CardAction.values,
    this.toasts = const ToastOptions(),
  }) : layout = layout ?? Layout.initial();

  /// Where every card, folder and widget is.
  final Layout layout;

  /// Card id -> absolute path of a user-chosen image. Cards that open a
  /// popup are keyed `panel:<panel id>`.
  final Map<String, String> iconOverrides;

  /// Absolute path of the image or video shown behind the home screen, or
  /// null for a plain background.
  final String? wallpaper;

  /// The quick actions offered when a card is held down, in order.
  final List<CardAction> contextMenu;

  final ToastOptions toasts;

  static const _keep = Object();

  LauncherConfig copyWith({
    Layout? layout,
    Map<String, String>? iconOverrides,
    // Nullable, so "not given" needs its own marker.
    Object? wallpaper = _keep,
    List<CardAction>? contextMenu,
    ToastOptions? toasts,
  }) => LauncherConfig(
    layout: layout ?? this.layout,
    iconOverrides: iconOverrides ?? this.iconOverrides,
    wallpaper: identical(wallpaper, _keep)
        ? this.wallpaper
        : wallpaper as String?,
    contextMenu: contextMenu ?? this.contextMenu,
    toasts: toasts ?? this.toasts,
  );

  factory LauncherConfig.fromJson(Map<String, dynamic> json) => LauncherConfig(
    layout: _layout(json),
    iconOverrides: {
      ...?(json['iconOverrides'] as Map?)?.cast<String, String>(),
    },
    wallpaper: json['wallpaper'] as String?,
    contextMenu: switch (json['contextMenu']) {
      final List<Object?> names => [
        for (final name in names) ?CardAction.named(name),
      ],
      _ => CardAction.values,
    },
    toasts: switch (json['toasts']) {
      final Map<Object?, Object?> toasts => ToastOptions.fromJson(toasts),
      _ => const ToastOptions(),
    },
  );

  static Layout _savedLayout(Map<String, dynamic> json) {
    try {
      if (json['layout'] case final Map<Object?, Object?> layout) {
        return Layout.fromJson(layout).normalised();
      }
    } on FormatException catch (e) {
      // A broken layout must not take the wallpaper and pictures with it.
      debugPrint('Saved layout unreadable, starting a new one: $e');
    }
    // Configs from before layouts existed only had a card order.
    return Layout.initial([...?(json['order'] as List?)?.cast<String>()]);
  }

  /// The layout in [json]. Cards that older configs listed as hidden were
  /// still placed, just not shown; they become removed cards.
  static Layout _layout(Map<String, dynamic> json) {
    final hidden = {...?(json['hidden'] as List?)?.whereType<String>()};
    final layout = _savedLayout(json);
    return hidden.isEmpty ? layout : layout.without(hidden).normalised();
  }

  Map<String, dynamic> toJson() => {
    'layout': layout.toJson(),
    'iconOverrides': iconOverrides,
    'wallpaper': ?wallpaper,
    'contextMenu': [for (final action in contextMenu) action.name],
    'toasts': toasts.toJson(),
  };
}
