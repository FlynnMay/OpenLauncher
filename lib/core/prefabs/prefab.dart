import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/prefabs/instance_options.dart';
import 'package:openlauncher/core/style/style.dart';
import 'package:openlauncher/core/variables/variable.dart';

/// One primitive a prefab is made of: a kind of component (`picture`, `text`,
/// ...) and its options, in which `{{source.label}}` and the like are what
/// the instance's source says. Its look is among them, as `style`.
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
    this.group,
  });

  /// Several parts arranged among themselves, taking this place together.
  const PrefabSlot.group(PrefabLayout this.group, {this.flex, this.aspect})
    : part = '',
      keep = false,
      options = const {};

  /// The id of the part; empty for a [group].
  final String part;

  /// The parts that take this place together, arranged as it says.
  final PrefabLayout? group;
  final double? flex, aspect;

  /// True to keep the part's room when it is hidden, so that hiding it
  /// does not change the size of the rest.
  final bool keep;

  /// What this layout sets differently about the part.
  final Map<String, Object?> options;

  static PrefabSlot? fromJson(Object? json) => switch (json) {
    {'group': final Map<Object?, Object?> group} =>
      switch (PrefabLayout.fromJson(group)) {
        null => null,
        final layout => PrefabSlot.group(
          layout,
          flex: _positive(json['flex']),
          aspect: _positive(json['aspect']),
        ),
      },
    {'part': final String part} => PrefabSlot(
      part,
      flex: _positive(json['flex']),
      aspect: _positive(json['aspect']),
      keep: json['keep'] == true,
      options: switch (json['options']) {
        final Map<Object?, Object?> options => options.cast(),
        _ => const {},
      },
    ),
    _ => null,
  };

  static double? _positive(Object? json) => switch (json) {
    final num number when number > 0 => number.toDouble(),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    if (group case final group?) 'group': group.toJson() else 'part': part,
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
    this.fit = false,
    this.align,
  });

  final String label;
  final bool row;
  final double gap;

  /// True for parts that each take the room they need and are then made,
  /// together, as big as the box allows: a clock, whatever its box.
  final bool fit;

  /// Where the parts sit across the way they run: `start`, `center`,
  /// `end` or `stretch`. Unsaid, in the middle of a row and filling the
  /// width of a column.
  final String? align;
  final List<PrefabSlot> slots;

  static PrefabLayout? fromJson(Object? json) => switch (json) {
    {'parts': final List<Object?> slots} => PrefabLayout(
      label: switch (json['label']) {
        final String label => label,
        _ => '',
      },
      row: json['direction'] == 'row',
      fit: json['fit'] == true,
      align: switch (json['align']) {
        final String align => align,
        _ => null,
      },
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
    if (fit) 'fit': true,
    'align': ?align,
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
    this.vars = const {},
    this.style = const {},
    this.w = 1,
    this.h = 1,
  });

  final String id, name;

  /// The look an instance has unless it sets its own, property by
  /// property; its parts take after it as anything inside a thing does.
  final Style style;

  /// The variables an instance has unless it sets them otherwise, which
  /// its parts read by name. This is how a prefab is handed what it is to
  /// show: the launcher's own each have a `source`, the entity an
  /// instance is drawn from.
  final Variables vars;

  /// The size, in cells, a new instance starts with.
  final double w, h;

  /// What an instance does, by what sets it off, unless it says otherwise.
  final Triggers on;

  /// The primitives, by the id an instance and a layout know each by.
  final Map<String, PrefabPart> parts;

  /// The ways they can be arranged, by name; the first is the usual one.
  final Map<String, PrefabLayout> layouts;

  Prefab copyWith({
    String? id,
    String? name,
    Map<String, PrefabPart>? parts,
    Variables? vars,
    Style? style,
  }) => Prefab(
    id: id ?? this.id,
    name: name ?? this.name,
    on: on,
    parts: parts ?? this.parts,
    layouts: layouts,
    vars: vars ?? this.vars,
    style: style ?? this.style,
    w: w,
    h: h,
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
        vars: variablesFromJson(json['vars']),
        style: styleFromJson(json['style']),
        w: PrefabSlot._positive(json['w']) ?? 1,
        h: PrefabSlot._positive(json['h']) ?? 1,
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
    if (vars.isNotEmpty) 'vars': variablesToJson(vars),
    if (style.isNotEmpty) 'style': style,
    if (w != 1) 'w': w,
    if (h != 1) 'h': h,
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
  'overflow': 'ellipsis',
  'style': {'fontSize': 12, 'fontWeight': 'medium'},
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
      const PrefabSlot(
        'name',
        flex: 1,
        options: {
          'style': {'textAlign': 'left'},
        },
      ),
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
    // What an instance is drawn from: an app, an input.
    vars: const {'source': Variable(null)},
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
        'frame': true,
        'style': {'radius': 0},
      }),
      'name': _name,
    },
    layouts: _cardLayouts(small: const {'pad': '{{source.padSmall}}'}),
  ),
  // Drawn from a folder, which is a pane that says what it is called and
  // how much is in it. A press sets that folder's `open`, which is all
  // that opens one.
  Prefab(
    id: folderPrefabId,
    name: 'Folder card',
    vars: const {'source': Variable(null)},
    on: const {
      Trigger.press: [
        Act('set', {'var': 'open', 'value': true, 'of': '{{source.id}}'}),
      ],
    },
    parts: const {
      'picture': PrefabPart('folder', {
        'folder': '{{source.id}}',
        'frame': true,
      }),
      'name': _name,
    },
    layouts: _cardLayouts(),
  ),
  // What used to be components of their own: each some text and pictures
  // reading an entity the launcher has, to be changed like any prefab.
  Prefab(
    id: 'clock',
    name: 'Clock',
    w: 2,
    vars: const {'source': Variable('clock')},
    parts: const {
      'time': PrefabPart('text', {
        'text': '{{source.time}}',
        'style': {'fontSize': 44},
      }),
      'date': PrefabPart('text', {
        'text': '{{source.date}}',
        'style': {'fontSize': 14, 'color': '#ffffffb3'},
      }),
    },
    layouts: const {
      'stacked': PrefabLayout(
        label: 'Date under the time',
        fit: true,
        align: 'center',
        slots: [PrefabSlot('time'), PrefabSlot('date')],
      ),
    },
  ),
  Prefab(
    id: 'weather',
    name: 'Weather',
    w: 2,
    vars: const {
      'source': Variable('weather'),
      // Which of the launcher's small pictures stands for the sky: told
      // by what the weather says of it, as any variable may be told.
      'icon': Variable(
        null,
        when: '{{source.sky}}',
        cases: [
          VarCase(VarTest.equals, 'clear', 'sun'),
          VarCase(VarTest.equals, 'partlyCloudy', 'partly'),
          VarCase(VarTest.equals, 'cloudy', 'cloud'),
          VarCase(VarTest.equals, 'fog', 'fog'),
          VarCase(VarTest.equals, 'snow', 'snow'),
          VarCase(VarTest.equals, 'storm', 'storm'),
        ],
        otherwise: 'rain',
      ),
    },
    parts: const {
      'icon': PrefabPart('icon', {'icon': '{{icon}}', 'size': 46}),
      'temperature': PrefabPart('text', {
        'text': '{{source | default:Choose a place in the editor}}',
        'style': {'fontSize': 38},
      }),
      'summary': PrefabPart('text', {
        'text': '{{source.summary}}',
        'style': {'fontSize': 14, 'color': '#ffffffb3'},
      }),
      'place': PrefabPart('text', {
        'text': '{{source.place}}',
        'style': {'fontSize': 14, 'color': '#ffffff8a'},
      }),
    },
    layouts: const {
      'row': PrefabLayout(
        label: 'Beside its picture',
        row: true,
        fit: true,
        gap: 14,
        slots: [
          PrefabSlot('icon'),
          PrefabSlot.group(
            PrefabLayout(
              label: '',
              fit: true,
              align: 'start',
              slots: [
                PrefabSlot('temperature'),
                PrefabSlot('summary'),
                PrefabSlot('place'),
              ],
            ),
          ),
        ],
      ),
    },
  ),
  Prefab(
    id: 'now-playing',
    name: 'Now playing',
    w: 2,
    vars: const {
      'source': Variable('media'),
      // What a press would do next.
      'stateIcon': Variable(
        null,
        when: '{{source.playing}}',
        cases: [VarCase(VarTest.equals, 'true', 'pause')],
        otherwise: 'play',
      ),
      // Said the short way: one of two things by a comparison.
      'summary': Variable(
        "{{source.artist == '' ? source.app : source.byline}}",
      ),
    },
    on: const {
      Trigger.press: [Act('playPause')],
    },
    parts: const {
      'cover': PrefabPart('picture', {'source': '{{source.art}}'}),
      'title': PrefabPart('text', {
        'text': '{{source.title | default:Nothing is playing}}',
        'style': {'fontSize': 15, 'fontWeight': 'medium'},
      }),
      'summary': PrefabPart('text', {
        'text': '{{summary}}',
        'style': {'fontSize': 13, 'color': '#ffffffb3'},
      }),
      'state': PrefabPart('icon', {'icon': '{{stateIcon}}', 'size': 24}),
    },
    layouts: const {
      'row': PrefabLayout(
        label: 'Beside its cover',
        row: true,
        gap: 12,
        slots: [
          PrefabSlot('cover', aspect: 1),
          PrefabSlot.group(
            PrefabLayout(
              label: '',
              align: 'start',
              slots: [PrefabSlot('title'), PrefabSlot('summary')],
            ),
            flex: 1,
          ),
          PrefabSlot('state'),
        ],
      ),
    },
  ),
];
