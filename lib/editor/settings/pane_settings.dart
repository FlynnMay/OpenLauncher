import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/settings/dock_settings.dart';
import 'package:openlauncher/editor/settings/style_settings.dart';
import 'package:openlauncher/editor/settings/trigger_settings.dart';
import 'package:openlauncher/editor/settings/variables_settings.dart';

/// Settings of one or more panes, including the screen's root pane.
class PaneSettings extends StatelessWidget {
  const PaneSettings({
    super.key,
    required this.title,
    required this.panes,
    required this.onChanged,
    this.named = true,
    this.children = const [],
    this.prefabs = const {},
    this.dockable = true,
    this.exposable = false,
  });

  final String title;
  final List<Component> panes;

  /// Called with a function to apply to each pane.
  final void Function(Component Function(Component pane) change) onChanged;

  /// Whether the title is editable.
  final bool named;

  /// Prefabs for the rules section; empty hides it.
  final Map<String, Prefab> prefabs;

  /// Whether it can be docked; a layer's root cannot.
  final bool dockable;

  /// It is a prefab's root, whose variables instances can show.
  final bool exposable;

  /// The chains a docked pane runs: when it is shown and hidden, and for one
  /// with a closed strip, when the focus comes and goes.
  static List<Trigger> _chains(Component pane) => [
    if (!pane.hovers) ...[Trigger.focus, Trigger.blur],
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
      if (panes.every((pane) => pane.scrollbar != null))
        Section(
          'Scroll bar',
          styleFields(
            keys: scrollbarStyle,
            style: panes.first.style,
            onChanged: (key, value) => onChanged(
              (pane) =>
                  pane.copyWith(style: withStyle(pane.style, {key: value})),
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
      if (dockable && panes.length == 1)
        Section(
          'Dock',
          open: panes.single.isDocked,
          dockFields(panes.single, onChanged),
        ),
      if (panes.length == 1 && panes.single.isDocked)
        TriggerSettings(
          scope: panes.single.vars,
          triggers: _chains(panes.single),
          set: panes.single.on,
          onChanged: (on) => onChanged((pane) => pane.copyWith(on: on)),
        ),
      if (panes.length == 1)
        VariablesSettings(
          variables: panes.single.vars,
          exposable: exposable,
          onChanged: (vars) => onChanged((pane) => pane.copyWith(vars: vars)),
        ),
    ],
  );

  /// With several panes the first one's values show and a change applies to
  /// all.
  Widget get _arrangement => Section(title, [
    ...ruleFields(
      options: [
        for (final rule in paneRules)
          if (rule.key != 'title' || named && panes.length == 1) rule,
      ],
      json: panes.first.options,
      onChanged: (key, value) =>
          onChanged((pane) => withRule(pane, key, value)),
    ),
    ...children,
  ]);

  /// Sets [key] of the pane's rule for [prefab]; null removes it, and an
  /// empty rule is dropped.
  static Component _ruled(
    Component pane,
    String prefab,
    String key,
    Object? value,
  ) {
    final rule = {...?pane.prefabRules[prefab], key: value}
      ..removeWhere((_, value) => value == null);
    final rules = {
      for (final MapEntry(:key, :value) in pane.prefabRules.entries)
        if (key != prefab) key: value,
      if (rule.isNotEmpty) prefab: rule,
    };
    return pane.withOption('prefabRules', rules.isEmpty ? null : rules);
  }

  /// Rules for instances directly in the pane. Prefabs packs ship are
  /// always listed; a user prefab's rule appears once added.
  Widget _rules(Set<String> shipped) {
    bool ruled(Prefab prefab) =>
        panes.any((pane) => pane.prefabRules.containsKey(prefab.id));
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
          'Applies to every prefab instance in this pane and overrides '
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
          panes.map(
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
              panes.any(
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
            panes.map(
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
            return pane.withOption('prefabRules', rules.isEmpty ? null : rules);
          }),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text('Remove rule for ${prefab.name}'),
        ),
      ),
  ];

  Widget get _entities => Section('Item size', open: false, [
    TickBox(
      label: 'Same size for all',
      value: shared(panes.map((pane) => pane.itemW != null)),
      onChanged: (same) => onChanged(
        (pane) => pane
            .withOption('itemW', same ? pane.itemW ?? 1 : null)
            .withOption('itemH', same ? pane.itemH ?? 1 : null),
      ),
    ),
    if (panes.every((pane) => pane.itemW != null)) ...[
      NumberField(
        label: 'Width (cells)',
        value: shared(panes.map((pane) => pane.itemW!)),
        mixed: panes.map((pane) => pane.itemW).toSet().length > 1,
        min: 1,
        max: panes.map((pane) => pane.reach).reduce((a, b) => a < b ? a : b),
        onChanged: (w) => onChanged((pane) => pane.withOption('itemW', w)),
      ),
      NumberField(
        label: 'Height (cells)',
        value: shared(panes.map((pane) => pane.itemH ?? 1)),
        mixed: panes.map((pane) => pane.itemH ?? 1).toSet().length > 1,
        min: 1,
        max: Component.maxRows,
        onChanged: (h) => onChanged((pane) => pane.withOption('itemH', h)),
      ),
    ],
  ]);

  /// The "not decided by the pane" choice.
  static const _each = 'each';
}
