import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/prefabs/instance_options.dart';

/// One primitive a prefab is made of: a kind of widget (`picture`, `text`,
/// ...) and its options, in which `{{source.label}}` and the like are what
/// the instance's source says.
@immutable
class PrefabPart {
  const PrefabPart(this.kind, [this.options = const {}]);

  final String kind;
  final Map<String, Object?> options;

  static PrefabPart? fromJson(Object? json) => switch (json) {
    {'kind': final String kind} => PrefabPart(kind, {
      for (final MapEntry(:key, :value) in (json as Map).entries)
        if (key is String && key != 'kind') key: value,
    }),
    _ => null,
  };

  Map<String, Object?> toJson() => {'kind': kind, ...options};
}

/// Where one part goes in a layout: in turn along it, taking a share of
/// the room ([flex]), keeping a shape ([aspect], width over height), or
/// only what it needs.
@immutable
class PrefabSlot {
  const PrefabSlot(
    this.part, {
    this.flex,
    this.aspect,
    this.keep = false,
    this.options = const {},
  });

  /// The id of the part.
  final String part;
  final double? flex, aspect;

  /// True to keep the part's room when it is hidden, so that hiding it
  /// does not change the size of the rest.
  final bool keep;

  /// What this layout sets differently about the part.
  final Map<String, Object?> options;

  static PrefabSlot? fromJson(Object? json) => switch (json) {
    {'part': final String part} => PrefabSlot(
      part,
      flex: switch (json['flex']) {
        final num flex when flex > 0 => flex.toDouble(),
        _ => null,
      },
      aspect: switch (json['aspect']) {
        final num aspect when aspect > 0 => aspect.toDouble(),
        _ => null,
      },
      keep: json['keep'] == true,
      options: switch (json['options']) {
        final Map<Object?, Object?> options => options.cast(),
        _ => const {},
      },
    ),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'part': part,
    'flex': ?flex,
    'aspect': ?aspect,
    if (keep) 'keep': true,
    if (options.isNotEmpty) 'options': options,
  };
}

/// One way a prefab's parts are arranged: side by side or one under the
/// other, in the order of its [slots].
@immutable
class PrefabLayout {
  const PrefabLayout({
    required this.label,
    required this.slots,
    this.row = false,
    this.gap = 0,
  });

  final String label;
  final bool row;
  final double gap;
  final List<PrefabSlot> slots;

  static PrefabLayout? fromJson(Object? json) => switch (json) {
    {'parts': final List<Object?> slots} => PrefabLayout(
      label: switch (json['label']) {
        final String label => label,
        _ => '',
      },
      row: json['direction'] == 'row',
      gap: switch (json['gap']) {
        final num gap when gap >= 0 => gap.toDouble(),
        _ => 0,
      },
      slots: [for (final slot in slots) ?PrefabSlot.fromJson(slot)],
    ),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'label': label,
    'direction': row ? 'row' : 'column',
    'gap': gap,
    'parts': [for (final slot in slots) slot.toJson()],
  };
}

/// Something ready made to put on the screen: primitives, how they are
/// arranged, and what it does, all written against a source that each
/// instance supplies. An entity is an instance of the prefab `app-card` whose
/// source is its app.
///
/// An instance keeps only what it sets differently; everything else it
/// reads from the prefab each time it is drawn, so a change to the prefab
/// reaches every instance that has not overridden that very value.
@immutable
class Prefab {
  const Prefab({
    required this.id,
    required this.name,
    this.on = const {},
    this.parts = const {},
    this.layouts = const {},
  });

  final String id, name;

  /// What an instance does, by what sets it off, unless it says otherwise.
  final Triggers on;

  /// The primitives, by the id an instance and a layout know each by.
  final Map<String, PrefabPart> parts;

  /// The ways they can be arranged, by name; the first is the usual one.
  final Map<String, PrefabLayout> layouts;

  Prefab copyWith({String? id, String? name, Map<String, PrefabPart>? parts}) =>
      Prefab(
        id: id ?? this.id,
        name: name ?? this.name,
        on: on,
        parts: parts ?? this.parts,
        layouts: layouts,
      );

  static Prefab? fromJson(Object? json) => switch (json) {
    {'id': final String id} when id.isNotEmpty && id == slugOf(id, '') =>
      Prefab(
        id: id,
        name: switch (json['name']) {
          final String name => name,
          _ => id,
        },
        on: triggersFromJson(json['on']),
        parts: {
          if (json['parts'] case final Map<Object?, Object?> parts)
            for (final MapEntry(:key, :value) in parts.entries)
              if (PrefabPart.fromJson(value) case final part?
                  when key is String)
                key: part,
        },
        layouts: {
          if (json['layouts'] case final Map<Object?, Object?> layouts)
            for (final MapEntry(:key, :value) in layouts.entries)
              if (PrefabLayout.fromJson(value) case final layout?
                  when key is String)
                key: layout,
        },
      ),
    _ => null,
  };

  /// Never throws; what cannot be read is left out, as is a second prefab
  /// with the id of an earlier one.
  static List<Prefab> listFromJson(Object? json) {
    final ids = <String>{};
    return [
      if (json is List)
        for (final entry in json)
          if (Prefab.fromJson(entry) case final prefab? when ids.add(prefab.id))
            prefab,
    ];
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (on.isNotEmpty) 'on': triggersToJson(on),
    'parts': {
      for (final MapEntry(:key, :value) in parts.entries) key: value.toJson(),
    },
    'layouts': {
      for (final MapEntry(:key, :value) in layouts.entries) key: value.toJson(),
    },
  };
}

const _name = PrefabPart('text', {
  'text': '{{source.label}}',
  'size': 12,
  'weight': 'medium',
  'overflow': 'ellipsis',
});

/// The two ways an entity is arranged, whatever its picture is.
Map<String, PrefabLayout> _cardLayouts({
  Map<String, Object?> small = const {},
}) => {
  'stacked': const PrefabLayout(
    label: 'Name under the picture',
    gap: 6,
    slots: [PrefabSlot('picture', flex: 1), PrefabSlot('name', keep: true)],
  ),
  'row': PrefabLayout(
    label: 'Name beside the picture',
    row: true,
    gap: 12,
    slots: [
      PrefabSlot('picture', aspect: 16 / 9, options: small),
      const PrefabSlot('name', flex: 1, options: {'align': 'left'}),
    ],
  ),
};

/// The prefabs the launcher comes with. The user's own, and their changed
/// copies of these, are in the config; one of those with the id of one of
/// these stands in for it until it is taken away again.
final List<Prefab> builtInPrefabs = [
  Prefab(
    id: cardPrefabId,
    name: 'App card',
    on: const {
      Trigger.press: [Act('open')],
      Trigger.hold: [Act('menu')],
    },
    parts: const {
      'picture': PrefabPart('picture', {
        'source': '{{source.icon}}',
        'fit': '{{source.fit}}',
        'pad': '{{source.pad}}',
        'alt': '{{source.label}}',
        'round': 0,
        'frame': true,
      }),
      'name': _name,
    },
    layouts: _cardLayouts(small: const {'pad': '{{source.padSmall}}'}),
  ),
  // What it does is open its folder, which is the item's to say.
  Prefab(
    id: folderPrefabId,
    name: 'Folder card',
    parts: const {
      // Drawn by the launcher: the folder's picture, or what is in it.
      'picture': PrefabPart('folder', {'frame': true}),
      'name': _name,
    },
    layouts: _cardLayouts(),
  ),
];
