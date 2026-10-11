import 'package:flutter/foundation.dart';

const appCategory = 'app';
const inputCategory = 'input';
const launcherCategory = 'launcher';

/// Something with actions and readable data: an app, a TV input, the
/// clock. Its actions and live data come from its category's entry in
/// `entity_registry.dart`.
@immutable
class Entity {
  const Entity({
    required this.id,
    required this.category,
    required this.label,
    String? name,
    this.data = const {},
  }) : name = name ?? label;

  /// e.g. `app:com.example`, `clock`.
  final String id;
  final String category;

  /// Display name; the user can change it.
  final String label;

  /// The device's own name for it; layout ids are derived from this.
  final String name;

  /// Static values read as `{{<id>.<key>}}`, e.g. an app's `package`.
  final Map<String, Object?> data;

  // Keys in [data] for an entity with a picture. The icon is a file path
  // or SVG markup.
  static const icon = 'icon', shape = 'shape';

  // Values of [shape]: full-frame artwork, or line art with no frame.
  // Anything else is a padded icon.
  static const banner = 'banner', lineArt = 'line';

  static String appId(String packageName) => 'app:$packageName';
  static String inputId(String tvInputId) => 'input:$tvInputId';

  /// Opens the launcher's settings.
  static const settings = Entity(
    id: 'launcher:settings',
    category: launcherCategory,
    label: 'Settings',
    data: {
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

  Entity withLabel(String label) =>
      Entity(id: id, category: category, label: label, name: name, data: data);

  /// A copy with [more] merged over [data].
  Entity withData(Map<String, Object?> more) => Entity(
    id: id,
    category: category,
    label: label,
    name: name,
    data: {...data, ...more},
  );

  @override
  bool operator ==(Object other) =>
      other is Entity &&
      other.id == id &&
      other.category == category &&
      other.label == label &&
      other.name == name &&
      mapEquals(other.data, data);

  @override
  int get hashCode => Object.hash(id, category, label, name);
}

extension EntitiesById on Iterable<Entity> {
  Entity? byId(String? id) => where((entity) => entity.id == id).firstOrNull;
}
