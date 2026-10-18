import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/modules/module_edit_context.dart';

/// The rules of its Prefab rules module.
List<Widget> prefabRulesEditor(ModuleEdit edit) => [
  PrefabRulesSettings(
    containers: edit.nodes,
    prefabs: edit.prefabs,
    onChanged: edit.onChanged,
  ),
];

/// Rules for instances directly in [containers]. Prefabs packs ship are
/// always listed; a user prefab's rule appears once added. With several
/// containers, a change applies to all.
class PrefabRulesSettings extends ConsumerWidget {
  const PrefabRulesSettings({
    super.key,
    required this.containers,
    required this.prefabs,
    required this.onChanged,
  });

  final List<Node> containers;
  final Map<String, Prefab> prefabs;

  /// Called with a function to apply to each container.
  final void Function(Node Function(Node container) change) onChanged;

  /// Sets [key] of the container's rule for [prefab]; null removes it, and an
  /// empty rule is dropped.
  static Node _ruled(Node container, String prefab, String key, Object? value) {
    final rule = {...?container.prefabRules[prefab], key: value}
      ..removeWhere((_, value) => value == null);
    final rules = {
      for (final MapEntry(:key, :value) in container.prefabRules.entries)
        if (key != prefab) key: value,
      if (rule.isNotEmpty) prefab: rule,
    };
    return container.withModule(prefabRulesModule.name, rules);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shipped = ref.watch(shippedPrefabsProvider).keys.toSet();
    bool ruled(Prefab prefab) => containers.any(
      (container) => container.prefabRules.containsKey(prefab.id),
    );
    final shown = [
      for (final prefab in prefabs.values)
        if (shipped.contains(prefab.id) || ruled(prefab)) prefab,
    ];
    final addable = [
      for (final prefab in prefabs.values)
        if (!shown.contains(prefab) && prefab.variants.isNotEmpty) prefab,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                (container) => _ruled(
                  container,
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
      ],
    );
  }

  /// A prefab's rule: its variant and each part's visibility.
  List<Widget> _rule(Prefab prefab, {required bool shipped}) => [
    LabelledRow(
      prefab.name,
      ChoiceBox<String>(
        value: shared(
          containers.map(
            (container) =>
                switch (container.prefabRules[prefab.id]?['variant']) {
                  final String variant
                      when prefab.variants.containsKey(variant) =>
                    variant,
                  _ => _each,
                },
          ),
        ),
        choices: {
          // A pack's may leave the variant to each instance.
          if (shipped ||
              containers.any(
                (container) =>
                    container.prefabRules[prefab.id]?['variant'] == null,
              ))
            _each: 'Per instance',
          for (final MapEntry(:key, :value) in prefab.variants.entries)
            key: value.label.isEmpty ? key : value.label,
        },
        onChanged: (variant) => onChanged(
          (container) => _ruled(
            container,
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
              (container) => switch (modulesFromJson(
                overridesFromJson(
                  container.prefabRules[prefab.id]?['overrides'],
                )[part.id]?['modules'],
              )[visibilityModule.name]?['visible']) {
                false => 'hidden',
                true => 'shown',
                _ => _each,
              },
            ),
          ),
          choices: const {
            _each: 'Per instance',
            'shown': 'Shown',
            'hidden': 'Hidden',
          },
          onChanged: (shown) => onChanged((container) {
            final overrides = withOverride(
              overridesFromJson(container.prefabRules[prefab.id]?['overrides']),
              part.id,
              {
                'visible': switch (shown) {
                  'shown' => true,
                  'hidden' => false,
                  _ => null,
                },
              },
              visibilityModule.name,
            );
            return _ruled(
              container,
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
          onPressed: () => onChanged((container) {
            final rules = {
              for (final MapEntry(:key, :value)
                  in container.prefabRules.entries)
                if (key != prefab.id) key: value,
            };
            return container.withModule(prefabRulesModule.name, rules);
          }),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: Text('Remove rule for ${prefab.name}'),
        ),
      ),
  ];

  /// The "not decided by the container" choice.
  static const _each = 'each';
}
