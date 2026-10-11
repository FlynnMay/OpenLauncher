import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/style/style.dart';
import 'package:openlauncher/core/variables/variable.dart';

/// One way a prefab can be, beside the way it was saved: a name for what
/// it sets differently about the prefab's components, by the id of each.
@immutable
class PrefabVariant {
  const PrefabVariant(this.label, [this.overrides = const {}]);

  final String label;
  final Overrides overrides;

  static PrefabVariant? fromJson(Object? json) => switch (json) {
    final Map<Object?, Object?> json => PrefabVariant(switch (json['label']) {
      final String label => label,
      _ => '',
    }, overridesFromJson(json['overrides'])),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'label': label,
    if (overrides.isNotEmpty) 'overrides': overrides,
  };
}

/// A component that was saved to be used again: [root], with everything
/// it is made of, written against variables that each instance may set
/// for itself. The launcher's cards are instances of `app-card`, whose
/// variable `source` each is handed an app as.
///
/// An instance keeps only what it sets differently; everything else it
/// reads from the prefab each time it is drawn, so a change to the prefab
/// reaches every instance that has not overridden that very value.
@immutable
class Prefab {
  const Prefab({
    required this.id,
    required this.name,
    required this.root,
    this.variants = const {},
  });

  final String id, name;

  /// The component itself. Its variables, look and triggers are what an
  /// instance has unless it sets its own; its size is what a new instance
  /// starts with.
  final Component root;

  /// The ways it can be, by name; the first is the usual one.
  final Map<String, PrefabVariant> variants;

  Variables get vars => root.vars;
  Style get style => root.style;
  Triggers get on => root.on;

  /// Everything it is made of other than the root, at any depth, that is
  /// not only there to arrange the rest.
  Iterable<Component> get parts =>
      root.all.skip(1).where((component) => !component.isPane);

  /// The name of the variant [instance] is: the one it names, where there
  /// is such a one, or else the first.
  String? variantOf(Component instance) =>
      variants.containsKey(instance.variant)
      ? instance.variant
      : variants.keys.firstOrNull;

  Prefab copyWith({String? id, String? name, Component? root}) => Prefab(
    id: id ?? this.id,
    name: name ?? this.name,
    root: root ?? this.root,
    variants: variants,
  );

  /// This prefab with the component [id] of it replaced by what [change]
  /// makes of it.
  Prefab withPart(String id, Component Function(Component part) change) {
    Component walk(Component component) => component.id == id
        ? change(component)
        : component.copyWith(
            children: [for (final child in component.children) walk(child)],
          );
    return copyWith(root: walk(root));
  }

  static Prefab? fromJson(Object? json) {
    if (json
        case {'id': final String id, 'root': final Map<Object?, Object?> root}
        when id.isNotEmpty && id == slugOf(id, '')) {
      try {
        return Prefab(
          id: id,
          name: switch (json['name']) {
            final String name => name,
            _ => id,
          },
          root: Component.fromJson(root),
          variants: {
            if (json['variants'] case final Map<Object?, Object?> variants)
              for (final MapEntry(:key, :value) in variants.entries)
                if (PrefabVariant.fromJson(value) case final variant?
                    when key is String)
                  key: variant,
          },
        );
      } on FormatException {
        return null;
      }
    }
    return null;
  }

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
    'root': root.toJson(),
    if (variants.isNotEmpty)
      'variants': {
        for (final MapEntry(:key, :value) in variants.entries)
          key: value.toJson(),
      },
  };
}

/// [instance] as it is drawn: its prefab's component with, value by
/// value, what the variant it is sets, and over that what the instance
/// sets itself. Its variables, look and triggers are the prefab's with
/// its own over them; its size and place are its own. Anything that is
/// not an instance is itself. One whose prefab is gone is drawn as the
/// launcher's first, a card.
Component resolved(
  Component instance,
  Map<String, Prefab> prefabs, [
  int depth = 0,
]) {
  if (!instance.isInstance) return instance;
  final prefab = prefabs[instance.prefab] ?? builtInPrefabs.first;
  final set = overridesOver(
    prefab.variants[prefab.variantOf(instance)]?.overrides ?? const {},
    instance.overrides,
  );
  // What is inside goes by the instance's id and its own, so that two
  // instances of one prefab have nothing of the same name.
  Component part(Component child) => child
      .overridden(set[child.id])
      .copyWith(
        id: '${instance.id}/${child.id}',
        children: [for (final inner in child.children) part(inner)],
      );
  // A prefab may itself be made from another.
  final base = depth < Component.maxDepth
      ? resolved(prefab.root, prefabs, depth + 1)
      : prefab.root;
  final root = base.overridden(set[prefab.root.id]);
  return Component(
    id: instance.id,
    kind: root.kind,
    options: {...root.options, ...instance.options},
    vars: {
      ...root.vars,
      for (final MapEntry(:key, :value) in instance.vars.entries)
        key: value.over(root.vars[key]),
    },
    style: {...root.style, ...instance.style},
    on: {...root.on, ...instance.on},
    w: instance.w,
    h: instance.h,
    x: instance.x,
    y: instance.y,
    flex: instance.flex,
    aspect: instance.aspect,
    keep: instance.keep,
    hidden: instance.hidden,
    children: [for (final child in root.children) part(child)],
  );
}

const _name = Component(
  id: 'name',
  kind: 'text',
  options: {'text': '{{source.label}}', 'overflow': 'ellipsis'},
  style: {'fontSize': 12, 'fontWeight': 'medium'},
  // Its room is kept while it is hidden, so every card's picture is the
  // same size.
  keep: true,
);

/// The two ways a card is arranged, whatever its picture is: as it was
/// saved, and in a row, where [small] is what the picture sets otherwise.
Map<String, PrefabVariant> _cardVariants({
  Map<String, Object?> small = const {},
}) => {
  'stacked': const PrefabVariant('Name under the picture'),
  'row': PrefabVariant('Name beside the picture', {
    'root': const {
      'options': {'mode': 'row', 'gap': 12},
    },
    'picture': {
      'transform': const {'flex': 0, 'aspect': 16 / 9},
      if (small.isNotEmpty) 'options': small,
    },
    'name': const {
      'transform': {'flex': 1, 'keep': false},
      'style': {'textAlign': 'left'},
    },
  }),
};

/// A pane that puts [children] in a line, as the launcher's own prefabs
/// are made.
Component _line(
  String id,
  PaneMode mode,
  List<Component> children, {
  Map<String, Object?> rules = const {},
  Variables vars = const {},
  Triggers on = const {},
  double w = 1,
  double? flex,
}) => Component(
  id: id,
  kind: paneKind,
  options: {'mode': mode.name, ...rules},
  vars: vars,
  on: on,
  w: w,
  flex: flex,
  children: children,
);

/// The prefabs the launcher comes with, each made only of what a user can
/// make. The user's own, and their changed copies of these, are in the
/// config; one of those with the id of one of these stands in for it
/// until it is taken away again.
final List<Prefab> builtInPrefabs = [
  Prefab(
    id: cardPrefabId,
    name: 'App card',
    variants: _cardVariants(
      small: const {'pad': "{{source.shape == 'icon' ? 4 : 0}}"},
    ),
    root: _line(
      'root',
      PaneMode.column,
      rules: const {'gap': 6},
      // What an instance is handed: an app, an input.
      vars: const {'source': Variable(null, type: VarType.entity)},
      on: const {
        Trigger.press: [Act('open')],
        // The quick actions are a pane like any folder: told what they
        // are about, and opened, by its variables.
        Trigger.hold: [
          Act('set', {
            'of': 'quick-actions',
            'var': 'source',
            'value': '{{source.id}}',
          }),
          Act('set', {'of': 'quick-actions', 'var': 'open', 'value': true}),
        ],
      },
      const [
        Component(
          id: 'picture',
          kind: 'picture',
          options: {
            'source': '{{source.icon}}',
            // How it sits in its frame is this card's to say, from the
            // sort of picture it was handed: artwork made for the whole
            // frame fills it, an icon sits in it, and line art has no
            // frame behind it at all.
            'fit': "{{source.shape == 'banner' ? 'cover' : 'contain'}}",
            'pad': "{{source.shape == 'icon' ? 14 : 0}}",
            'alt': '{{source.label}}',
            'frame': true,
            'bare': "{{source.shape == 'line'}}",
          },
          style: {'radius': 0},
          flex: 1,
        ),
        _name,
      ],
    ),
  ),
  // Handed a folder, which is a pane that says what it is called and how
  // much is in it. A press sets that folder's `open`, which is all that
  // opens one.
  Prefab(
    id: folderPrefabId,
    name: 'Folder card',
    variants: _cardVariants(),
    root: _line(
      'root',
      PaneMode.column,
      rules: const {'gap': 6},
      vars: const {'source': Variable(null, type: VarType.entity)},
      on: const {
        Trigger.press: [
          Act('set', {'var': 'open', 'value': true, 'of': '{{source.id}}'}),
        ],
      },
      const [
        Component(
          id: 'picture',
          kind: 'folder',
          options: {
            'folder': '{{source.id}}',
            'frame': true,
            'bare': '{{source.bare}}',
          },
          flex: 1,
        ),
        _name,
      ],
    ),
  ),
  // Each some text and pictures reading an entity the launcher has, to be
  // changed like any prefab.
  Prefab(
    id: 'clock',
    name: 'Clock',
    variants: const {'stacked': PrefabVariant('Date under the time')},
    root: _line(
      'root',
      PaneMode.column,
      w: 2,
      rules: const {'fit': true, 'align': 'center'},
      vars: const {'source': Variable('clock', type: VarType.entity)},
      const [
        Component(
          id: 'time',
          kind: 'text',
          options: {'text': '{{source.time}}'},
          style: {'fontSize': 44},
        ),
        Component(
          id: 'date',
          kind: 'text',
          options: {'text': '{{source.date}}'},
          style: {'fontSize': 14, 'color': '#ffffffb3'},
        ),
      ],
    ),
  ),
  Prefab(
    id: 'weather',
    name: 'Weather',
    variants: const {'row': PrefabVariant('Beside its picture')},
    root: _line(
      'root',
      PaneMode.row,
      w: 2,
      rules: const {'fit': true, 'gap': 14},
      vars: const {
        'source': Variable('weather', type: VarType.entity),
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
        // What it is like, and with them the day's highest and lowest.
        'summary': Variable(
          null,
          when: '{{source.high}}',
          cases: [VarCase(VarTest.equals, '', '{{source.description}}')],
          otherwise:
              '{{source.description}}  ·  '
              '{{source.high | round}}° / {{source.low | round}}°',
        ),
      },
      [
        const Component(
          id: 'icon',
          kind: 'icon',
          options: {'icon': '{{icon}}', 'size': 46},
        ),
        _line(
          'lines',
          PaneMode.column,
          rules: const {'fit': true, 'align': 'start'},
          const [
            Component(
              id: 'temperature',
              kind: 'text',
              options: {
                'text': '{{source | default:Choose a place in the editor}}',
              },
              style: {'fontSize': 38},
            ),
            Component(
              id: 'summary',
              kind: 'text',
              options: {'text': '{{summary}}'},
              style: {'fontSize': 14, 'color': '#ffffffb3'},
            ),
            Component(
              id: 'place',
              kind: 'text',
              options: {'text': '{{source.place}}'},
              style: {'fontSize': 14, 'color': '#ffffff8a'},
            ),
          ],
        ),
      ],
    ),
  ),
  Prefab(
    id: 'now-playing',
    name: 'Now playing',
    variants: const {'row': PrefabVariant('Beside its cover')},
    root: _line(
      'root',
      PaneMode.row,
      w: 2,
      rules: const {'gap': 12},
      vars: const {
        'source': Variable('media', type: VarType.entity),
        // What a press would do next.
        'stateIcon': Variable(
          null,
          when: '{{source.playing}}',
          cases: [VarCase(VarTest.equals, 'true', 'pause')],
          otherwise: 'play',
        ),
        // Who it is by and what is playing it, or only the second.
        'summary': Variable(
          null,
          when: '{{source.artist}}',
          cases: [VarCase(VarTest.equals, '', '{{source.app}}')],
          otherwise: '{{source.artist}} · {{source.app}}',
        ),
      },
      on: const {
        Trigger.press: [Act('playPause')],
      },
      [
        const Component(
          id: 'cover',
          kind: 'picture',
          options: {'source': '{{source.art}}'},
          aspect: 1,
        ),
        _line(
          'lines',
          PaneMode.column,
          flex: 1,
          rules: const {'align': 'start'},
          const [
            Component(
              id: 'title',
              kind: 'text',
              options: {
                'text': '{{source.title | default:Nothing is playing}}',
              },
              style: {'fontSize': 15, 'fontWeight': 'medium'},
            ),
            Component(
              id: 'summary',
              kind: 'text',
              options: {'text': '{{summary}}'},
              style: {'fontSize': 13, 'color': '#ffffffb3'},
            ),
          ],
        ),
        const Component(
          id: 'state',
          kind: 'icon',
          options: {'icon': '{{stateIcon}}', 'size': 24},
        ),
      ],
    ),
  ),
];
