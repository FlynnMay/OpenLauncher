import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/entities/entity_action.dart';

const appCategory = 'app';
const inputCategory = 'input';
const launcherCategory = 'launcher';

/// Something with actions and readable values: an app, a TV input, the
/// clock. It defines its own actions, and JSON is its one shape: saved (the
/// user's own), generated on the TV, or sent to the editor.
@immutable
class Entity {
  const Entity({
    required this.id,
    required this.category,
    required this.label,
    String? name,
    this.data = const {},
    this.feed,
    this.actions = const {},
    this.prefab,
    this.placed = false,
  }) : name = name ?? label;

  /// e.g. `app:com.example`, `clock`.
  final String id;

  /// What it is grouped and sorted with, e.g. `app`.
  final String category;

  /// Display name; the user can change it.
  final String label;

  /// The device's own name for it; layout ids are derived from this.
  final String name;

  /// Static values read as `{{<id>.<key>}}`, e.g. an app's `package`.
  final Map<String, Object?> data;

  /// Its live values, laid over [data].
  final Feed? feed;

  /// What it can be told to do, by the name an `Act` uses.
  final Map<String, EntityAction> actions;

  /// The prefab the editor offers it as, if any.
  final String? prefab;

  /// Whether it goes to the inbox while it is nowhere on the screen (apps,
  /// inputs).
  final bool placed;

  // Keys in [data] for an entity with a picture. The icon is a file path
  // or SVG markup.
  static const icon = 'icon', shape = 'shape';

  // Values of [shape]: full-frame artwork, or line art with no frame.
  // Anything else is a padded icon.
  static const banner = 'banner', lineArt = 'line';

  static String appId(String packageName) => 'app:$packageName';
  static String inputId(String tvInputId) => 'input:$tvInputId';

  /// What an action's `{{self...}}` reads: [data] and what names it.
  Map<String, Object?> get self => {
    'id': id,
    'label': label,
    'name': name,
    'category': category,
    ...data,
  };

  Entity copyWith({
    String? label,
    Map<String, Object?>? data,
    Feed? feed,
    Map<String, EntityAction>? actions,
  }) => Entity(
    id: id,
    category: category,
    label: label ?? this.label,
    name: name,
    data: data ?? this.data,
    feed: feed ?? this.feed,
    actions: actions ?? this.actions,
    prefab: prefab,
    placed: placed,
  );

  Entity withLabel(String label) => copyWith(label: label);

  /// A copy with [more] merged over [data].
  Entity withData(Map<String, Object?> more) =>
      copyWith(data: {...data, ...more});

  /// Null unless [json] has an id.
  static Entity? fromJson(Object? json) {
    if (json case {'id': final String id} when id.isNotEmpty) {
      final label = switch (json['label']) {
        final String label when label.isNotEmpty => label,
        _ => id,
      };
      return Entity(
        id: id,
        category: switch (json['category']) {
          final String category when category.isNotEmpty => category,
          _ => userCategory,
        },
        label: label,
        name: switch (json['name']) {
          final String name when name.isNotEmpty => name,
          _ => label,
        },
        data: switch (json['data']) {
          final Map<Object?, Object?> data => {
            for (final MapEntry(:key, :value) in data.entries)
              if (key is String) key: value,
          },
          _ => const {},
        },
        feed: Feed.fromJson(json['feed']),
        actions: switch (json['actions']) {
          final Map<Object?, Object?> actions => {
            for (final MapEntry(:key, :value) in actions.entries)
              if (key is String && key.isNotEmpty)
                key: ?EntityAction.fromJson(value),
          },
          _ => const {},
        },
        prefab: switch (json['prefab']) {
          final String prefab when prefab.isNotEmpty => prefab,
          _ => null,
        },
        placed: json['placed'] == true,
      );
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'category': category,
    'label': label,
    if (name != label) 'name': name,
    if (data.isNotEmpty) 'data': data,
    'feed': ?feed?.toJson(),
    if (actions.isNotEmpty)
      'actions': {
        for (final MapEntry(key: name, value: action) in actions.entries)
          name: action.toJson(),
      },
    'prefab': ?prefab,
    if (placed) 'placed': true,
  };

  @override
  bool operator ==(Object other) =>
      other is Entity &&
      other.id == id &&
      other.category == category &&
      other.label == label &&
      other.name == name &&
      other.feed == feed &&
      other.prefab == prefab &&
      other.placed == placed &&
      mapEquals(other.data, data) &&
      mapEquals(other.actions, actions);

  @override
  int get hashCode => Object.hash(id, category, label, name);
}

/// The category of an entity the user made, unless it says another.
const userCategory = 'value';

extension EntitiesById on Iterable<Entity> {
  Entity? byId(String? id) => where((entity) => entity.id == id).firstOrNull;
}
