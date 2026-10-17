import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/settings/dock_settings.dart';
import 'package:openlauncher/editor/settings/style_settings.dart';
import 'package:openlauncher/editor/settings/trigger_settings.dart';
import 'package:openlauncher/editor/settings/variables_settings.dart';

/// Settings of one or more containers, including the screen's root pane.
class LayoutSettings extends StatelessWidget {
  const LayoutSettings({
    super.key,
    required this.title,
    required this.containers,
    required this.onChanged,
    this.named = true,
    this.children = const [],
    this.prefabs = const {},
    this.dockable = true,
    this.exposable = false,
  });

  final String title;
  final List<Node> containers;

  /// Called with a function to apply to each pane.
  final void Function(Node Function(Node pane) change) onChanged;

  /// Whether the title is editable.
  final bool named;

  /// Prefabs for the rules section; empty hides it.
  final Map<String, Prefab> prefabs;

  /// Whether it can be docked; a layer's root cannot.
  final bool dockable;

  /// It is a prefab's root, whose variables instances can show.
  final bool exposable;

  /// The chains a docked pane runs.
  static const _chains = [
    Trigger.focus,
    Trigger.blur,
    Trigger.reveal,
    Trigger.hide,
  ];

  /// Extra widgets after the settings.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _arrangement,
      if (containers.every((pane) => pane.scrollbar != null))
        Section(
          'Scroll bar',
          styleFields(
            keys: scrollbarStyle,
            style: containers.first.scroll,
            onChanged: (key, value) => onChanged(
              (pane) => pane.withValue(scrollModule.name, key, value),
            ),
          ),
        ),
      _entities,
      if (prefabs.isNotEmpty)
        Consumer(
          builder: (context, ref, _) =>
              _rules(ref.watch(shippedPrefabsProvider).keys.toSet()),
        ),
      // One pane at a time.
      if (dockable && containers.length == 1)
        Section(
          'Dock',
          open: containers.single.isDocked,
          dockFields(containers.single, onChanged),
        ),
      if (containers.length == 1 && containers.single.isDocked)
        TriggerSettings(
          scope: containers.single.vars,
          triggers: _chains,
          set: containers.single.on,
          onChanged: (on) => onChanged((pane) => pane.triggered(on)),
        ),
      if (containers.length == 1)
        VariablesSettings(
          variables: containers.single.vars,
          exposable: exposable,
          onChanged: (vars) => onChanged((pane) => pane.withVars(vars)),
        ),
    ],
  );

  /// With several containers the first one's values show and a change applies to
  /// all.
  Widget get _arrangement => Section(title, [
    if (named && containers.length == 1)
      ...ruleFields(
        options: const [Field('name', 'Name', FieldKind.text)],
        json: {'name': containers.single.name},
        onChanged: (_, name) =>
            onChanged((pane) => pane.copyWith(name: '${name ?? ''}')),
      ),
    for (final module in [layoutModule, scrollModule])
      ...ruleFields(
        options: [
          for (final field in module.fields)
            if (!scrollbarStyle.contains(field.key)) field,
        ],
        json: containers.first.values(module.name) ?? const {},
        onChanged: (key, value) =>
            onChanged((pane) => withRule(pane, module.name, key, value)),
      ),
    ...children,
  ]);

  /// Sets [key] of the pane's rule for [prefab]; null removes it, and an
  /// empty rule is dropped.
  static Node _ruled(Node pane, String prefab, String key, Object? value) {
    final rule = {...?pane.prefabRules[prefab], key: value}
      ..removeWhere((_, value) => value == null);
    final rules = {
      for (final MapEntry(:key, :value) in pane.prefabRules.entries)
        if (key != prefab) key: value,
      if (rule.isNotEmpty) prefab: rule,
    };
    return pane.withPrefabRules(rules);
  }

  /// Rules for instances directly in the pane. Prefabs packs ship are
  /// always listed; a user prefab's rule appears once added.
  Widget _rules(Set<String> shipped) {
    bool ruled(Prefab prefab) =>
        containers.any((pane) => pane.prefabRules.containsKey(prefab.id));
    final shown = [
      for (final prefab in prefabs.values)
        if (shipped.contains(prefab.id) || ruled(prefab)) prefab,
    ];
    final addable = [
      for (final prefab in prefabs.values)
        if (!shown.contains(prefab) && prefab.variants.isNotEmpty) prefab,
    ];
    return Section('Prefab rules', open: false, [
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          'Applies to every prefab instance in this layout and overrides '
          'the instance\'s own setting.',
        ),
      ),
      for (final prefab in shown)
        ..._rule(prefab, shipped: shipped.contains(prefab.id)),
      if (addable.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<Prefab>(
            tooltip: 'Add a prefab rule',
            // A rule starts with the prefab's first variant.
            onSelected: (prefab) => onChanged(
              (pane) => _ruled(
                pane,
                prefab.id,
                'variant',
                prefab.variants.keys.first,
              ),
            ),
            itemBuilder: (context) => [
              for (final prefab in addable)
                PopupMenuItem(value: prefab, child: Text(prefab.name)),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [Icon(Icons.add, size: 18), Text('Add rule')],
              ),
            ),
          ),
        ),
    ]);
  }

  /// A prefab's rule: its variant and each part's visibility.
  List<Widget> _rule(Prefab prefab, {required bool shipped}) => [
    LabelledRow(
      prefab.name,
      ChoiceBox<String>(
        value: shared(
          containers.map(
            (pane) => switch (pane.prefabRules[prefab.id]?['variant']) {
              final String variant when prefab.variants.containsKey(variant) =>
                variant,
              _ => _each,
            },
          ),
        ),
        choices: {
          // A pack's may leave the variant to each instance.
          if (shipped ||
              containers.any(
                (pane) => pane.prefabRules[prefab.id]?['variant'] == null,
              ))
            _each: 'Per instance',
          for (final MapEntry(:key, :value) in prefab.variants.entries)
            key: value.label.isEmpty ? key : value.label,
        },
        onChanged: (variant) => onChanged(
          (pane) => _ruled(
            pane,
            prefab.id,
            'variant',
            variant == _each ? null : variant,
          ),
        ),
      ),
    ),
    for (final part in prefab.parts)
      LabelledRow(
        '  ${part.id}',
        ChoiceBox<String>(
          value: shared(
            containers.map(
              (pane) => switch (overridesFromJson(
                pane.prefabRules[prefab.id]?['overrides'],
              )[part.id]?['hidden']) {
                true => 'hidden',
                false => 'shown',
                _ => _each,
              },
            ),
          ),
          choices: const {
            _each: 'Per instance',
            'shown': 'Shown',
            'hidden': 'Hidden',
          },
          onChanged: (shown) => onChanged((pane) {
            final overrides = withOverride(
              overridesFromJson(pane.prefabRules[prefab.id]?['overrides']),
              part.id,
              {
                'hidden': switch (shown) {
                  'shown' => false,
                  'hidden' => true,
                  _ => null,
                },
              },
            );
            return _ruled(
              pane,
              prefab.id,
              'overrides',
              overrides.isEmpty ? null : overrides,
            );
          }),
        ),
      ),
    if (!shipped)
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => onChanged((pane) {
            final rules = {
              for (final MapEntry(:key, :value) in pane.prefabRules.entries)
                if (key != prefab.id) key: value,
            };
            return pane.withPrefabRules(rules);
          }),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text('Remove rule for ${prefab.name}'),
        ),
      ),
  ];

  Widget get _entities => Section('Item size', open: false, [
    TickBox(
      label: 'Same size for all',
      value: shared(containers.map((pane) => pane.itemW != null)),
      onChanged: (same) => onChanged(
        (pane) => pane
            .withValue(
              layoutModule.name,
              'itemW',
              same ? pane.itemW ?? 1 : null,
            )
            .withValue(
              layoutModule.name,
              'itemH',
              same ? pane.itemH ?? 1 : null,
            ),
      ),
    ),
    if (containers.every((pane) => pane.itemW != null)) ...[
      NumberField(
        label: 'Width (cells)',
        value: shared(containers.map((pane) => pane.itemW!)),
        mixed: containers.map((pane) => pane.itemW).toSet().length > 1,
        min: 1,
        max: containers
            .map((pane) => pane.reach)
            .reduce((a, b) => a < b ? a : b),
        onChanged: (w) =>
            onChanged((pane) => pane.withValue(layoutModule.name, 'itemW', w)),
      ),
      NumberField(
        label: 'Height (cells)',
        value: shared(containers.map((pane) => pane.itemH ?? 1)),
        mixed: containers.map((pane) => pane.itemH ?? 1).toSet().length > 1,
        min: 1,
        max: SizingModule.maxRows,
        onChanged: (h) =>
            onChanged((pane) => pane.withValue(layoutModule.name, 'itemH', h)),
      ),
    ],
  ]);

  /// The "not decided by the pane" choice.
  static const _each = 'each';
}
