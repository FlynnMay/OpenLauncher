import 'package:flutter/foundation.dart';

// The names of the kinds of entity the launcher comes with; what each is
// and does is in `entity_kinds.dart`, and there may be any number more.
const appKind = 'app';
const inputKind = 'input';
const launcherKind = 'launcher';

/// Something a prefab can be drawn from and do things to: an app, one of
/// the TV's inputs, a screen of the launcher's own, and whatever other
/// kinds there come to be. It says what it is called, what it looks like,
/// and, through its kind, what can be done with it.
@immutable
class Entity {
  const Entity({
    required this.id,
    required this.kind,
    required this.target,
    required this.label,
    String? sourceLabel,
    this.iconPath,
    this.wideIcon = false,
    this.svg,
  }) : sourceLabel = sourceLabel ?? label;

  /// Stable key used by config and the command API, e.g. `app:com.example`.
  final String id;

  /// The name of its `EntityKind`.
  final String kind;

  /// What its kind knows it by: an app's package name, a TV input's id.
  final String target;
  final String label;

  /// What the device calls it, whatever the user has named it since. The
  /// ids of entities that are not apps are made from this in the layout, so
  /// that they say what the thing is.
  final String sourceLabel;

  /// Absolute path of the image to show, or null to fall back to the label.
  final String? iconPath;

  /// True when [iconPath] is 16:9 artwork that should fill the entity.
  final bool wideIcon;

  /// Built-in line art, as SVG markup, shown when there is no [iconPath].
  /// Entities drawn this way have no background of their own.
  final String? svg;

  static String appId(String packageName) => 'app:$packageName';
  static String inputId(String tvInputId) => 'input:$tvInputId';

  /// The entity that opens the launcher's settings. It can be placed like
  /// any other; while it is nowhere, the home screen shows a button instead.
  static const settings = Entity(
    id: 'launcher:settings',
    kind: launcherKind,
    target: 'settings',
    label: 'Settings',
    // A cog, in the same line drawing as the input entities.
    svg:
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 90" '
        'fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" '
        'stroke-linejoin="round"><circle cx="80" cy="45" r="7"/>'
        '<circle cx="80" cy="45" r="17"/><path d="M80 20v8m0 34v8M55 45h8'
        'm34 0h8M62.3 27.3l5.7 5.7m24 24 5.7 5.7m0-35.4L92 33M68 57l-5.7 '
        '5.7"/></svg>',
  );

  /// This entity under another name.
  Entity withLabel(String label) => Entity(
    id: id,
    kind: kind,
    target: target,
    label: label,
    sourceLabel: sourceLabel,
    iconPath: iconPath,
    wideIcon: wideIcon,
    svg: svg,
  );

  /// This entity looking like [other].
  Entity withPictureOf(Entity other) => Entity(
    id: id,
    kind: kind,
    target: target,
    label: label,
    sourceLabel: sourceLabel,
    iconPath: other.iconPath,
    wideIcon: other.wideIcon,
    svg: other.svg,
  );

  @override
  bool operator ==(Object other) =>
      other is Entity &&
      other.id == id &&
      other.kind == kind &&
      other.target == target &&
      other.label == label &&
      other.sourceLabel == sourceLabel &&
      other.iconPath == iconPath &&
      other.wideIcon == wideIcon &&
      other.svg == svg;

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    target,
    label,
    sourceLabel,
    iconPath,
    wideIcon,
    svg,
  );
}
