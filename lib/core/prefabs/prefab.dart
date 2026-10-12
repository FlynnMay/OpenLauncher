import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/components/component.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/style/style.dart';
import 'package:openlauncher/core/variables/variable.dart';

/// A named set of overrides on a prefab's components.
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

/// A saved component, reused through instances. An instance stores only what
/// it changes, so edits to the prefab reach every instance that has not
/// overridden that value.
@immutable
class Prefab {
  const Prefab({
    required this.id,
    required this.name,
    required this.root,
    this.variants = const {},
  });

  final String id, name;

  /// The component. Its size is what a new instance starts with.
  final Component root;

  /// By name; the first is the default.
  final Map<String, PrefabVariant> variants;

  Variables get vars => root.vars;
  Style get style => root.style;
  Triggers get on => root.on;

  /// Every non-pane descendant of the root.
  Iterable<Component> get parts =>
      root.all.skip(1).where((component) => !component.isPane);

  /// The variant instances use unless they name another.
  String? get defaultVariant => variants.keys.firstOrNull;

  /// [variant] if there is one of that name, else the default.
  String? variantNamed(String? variant) =>
      variants.containsKey(variant) ? variant : defaultVariant;

  /// Whether [variant] is the tree as built: the default, with no overrides
  /// of its own.
  bool isBase(String? variant) {
    final name = variantNamed(variant);
    return name == null ||
        name == defaultVariant && variants[name]!.overrides.isEmpty;
  }

  /// The root as [variant] has it, ids unchanged.
  Component rootAs(String? variant) => withOverrides(
    root,
    variants[variantNamed(variant)]?.overrides ?? const {},
  );

  /// The variant [instance] uses, falling back to the first.
  String? variantOf(Component instance) =>
      variants.containsKey(instance.variant)
      ? instance.variant
      : variants.keys.firstOrNull;

  Prefab copyWith({
    String? id,
    String? name,
    Component? root,
    Map<String, PrefabVariant>? variants,
  }) => Prefab(
    id: id ?? this.id,
    name: name ?? this.name,
    root: root ?? this.root,
    variants: variants ?? this.variants,
  );

  /// Replaces the descendant [id] with what [change] returns.
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

  /// Skips unreadable entries and duplicate ids. Never throws.
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

/// [root]'s tree with [overrides] applied; ids are kept.
Component withOverrides(Component root, Overrides overrides) =>
    overrides.isEmpty
    ? root
    : root
          .overridden(overrides[root.id])
          .copyWith(
            children: [
              for (final child in root.children)
                withOverrides(child, overrides),
            ],
          );

/// The concrete component for [instance]: the prefab's tree with the
/// variant's overrides, then the instance's. Variables, style and triggers
/// are merged; size and position are the instance's. A missing prefab falls
/// back to the first built-in.
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
  // Child ids are prefixed with the instance id to keep them unique.
  Component part(Component child) => child
      .overridden(set[child.id])
      .copyWith(
        id: '${instance.id}/${child.id}',
        children: [for (final inner in child.children) part(inner)],
      );
  // A prefab's root may itself be an instance.
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
  // Keeps its space when hidden so every card's picture is the same size.
  keep: true,
);

/// The two card variants. [small] is the picture's options in the row one.
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

/// A row or column pane.
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

/// Built-in prefabs, made only from what a user can make. A user prefab with
/// the same id replaces one.
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
      vars: const {'source': Variable(null, type: VarType.entity)},
      on: const {
        Trigger.press: [
          Act('open', {entityArg: sourceEntity}),
        ],
        // Opens the quick actions for this entity.
        Trigger.hold: [
          Act('set', {
            entityArg: 'variables',
            'of': 'quick-actions',
            'var': 'source',
            'value': '{{source.id}}',
          }),
          Act('set', {
            entityArg: 'variables',
            'of': 'quick-actions',
            'var': 'open',
            'value': true,
          }),
        ],
      },
      const [
        Component(
          id: 'picture',
          kind: 'picture',
          options: {
            'source': '{{source.icon}}',
            // Banners fill the frame, icons are padded, line art has no
            // frame.
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
  // Pressing it sets the folder's `open`.
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
          Act('set', {
            entityArg: 'variables',
            'var': 'open',
            'value': true,
            'of': '{{source.id}}',
          }),
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
        // The icon for the sky.
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
          exposed: false,
        ),
        // Description, plus high / low when known.
        'summary': Variable(
          null,
          when: '{{source.high}}',
          cases: [VarCase(VarTest.equals, '', '{{source.description}}')],
          otherwise:
              '{{source.description}}  ·  '
              '{{source.high | round}}° / {{source.low | round}}°',
          exposed: false,
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
          exposed: false,
        ),
        // Artist and app, or only the app.
        'summary': Variable(
          null,
          when: '{{source.artist}}',
          cases: [VarCase(VarTest.equals, '', '{{source.app}}')],
          otherwise: '{{source.artist}} · {{source.app}}',
          exposed: false,
        ),
      },
      on: const {
        Trigger.press: [
          Act('playPause', {entityArg: sourceEntity}),
        ],
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
