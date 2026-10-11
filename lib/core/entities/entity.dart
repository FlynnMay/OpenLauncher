import 'package:flutter/foundation.dart';

// The names of the kinds of entity the launcher comes with; what each is
// and does is in `entity_kinds.dart`, and there may be any number more.
const appKind = 'app';
const inputKind = 'input';
const launcherKind = 'launcher';

/// Something that has actions a trigger can use and things to be read: an
/// app, one of the TV's inputs, the clock, the weather, the launcher
/// itself, and whatever other kinds there come to be. They are all the one
/// shape: what it is called, and under [data] whatever its kind says of
/// it. What can be done with it, and what it has that changes by itself,
/// are its kind's to say (`entity_kinds.dart`).
@immutable
class Entity {
  const Entity({
    required this.id,
    required this.kind,
    required this.label,
    String? name,
    this.data = const {},
  }) : name = name ?? label;

  /// Stable key used by config and the command API, e.g. `app:com.example`.
  final String id;

  /// The name of its `EntityKind`.
  final String kind;
  final String label;

  /// What the device calls it, whatever the user has named it since. The
  /// ids of what is made from it in the layout come from this, so that
  /// they say what the thing is.
  final String name;

  /// What there is to read of it that only changes when it does, by name:
  /// an app's `package`, its `icon` and the `shape` of that. Read as
  /// `{{<id>.<name>}}` like anything else an entity has.
  final Map<String, Object?> data;

  /// Under these names in [data], for an entity that has a picture: the
  /// picture (the path of an image, or SVG markup), and what sort it is.
  static const icon = 'icon', shape = 'shape';

  /// The sorts of picture: artwork made for the whole frame, an icon that
  /// sits in it, and line art, which has no frame behind it.
  static const banner = 'banner', lineArt = 'line';

  static String appId(String packageName) => 'app:$packageName';
  static String inputId(String tvInputId) => 'input:$tvInputId';

  /// The entity that opens the launcher's settings. It can be placed like
  /// any other; while it is nowhere, the home screen shows a button instead.
  static const settings = Entity(
    id: 'launcher:settings',
    kind: launcherKind,
    label: 'Settings',
    data: {
      // A cog, in the same line drawing as the inputs.
      icon:
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 90" '
          'fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" '
          'stroke-linejoin="round"><circle cx="80" cy="45" r="7"/>'
          '<circle cx="80" cy="45" r="17"/><path d="M80 20v8m0 34v8M55 45h8'
          'm34 0h8M62.3 27.3l5.7 5.7m24 24 5.7 5.7m0-35.4L92 33M68 57l-5.7 '
          '5.7"/></svg>',
      shape: lineArt,
    },
  );

  /// This entity under another name.
  Entity withLabel(String label) =>
      Entity(id: id, kind: kind, label: label, name: name, data: data);

  /// This entity with [more] to be read of it, over what there was.
  Entity withData(Map<String, Object?> more) => Entity(
    id: id,
    kind: kind,
    label: label,
    name: name,
    data: {...data, ...more},
  );

  @override
  bool operator ==(Object other) =>
      other is Entity &&
      other.id == id &&
      other.kind == kind &&
      other.label == label &&
      other.name == name &&
      mapEquals(other.data, data);

  @override
  int get hashCode => Object.hash(id, kind, label, name);
}

extension EntitiesById on Iterable<Entity> {
  /// The one called [id], if it is among them.
  Entity? byId(String? id) => where((entity) => entity.id == id).firstOrNull;
}
