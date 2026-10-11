import 'package:flutter/material.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/option_fields.dart';
import 'package:openlauncher/editor/style_settings.dart';
import 'package:openlauncher/editor/variables_settings.dart';

List<ComponentOption> _optionsOf(Component part) =>
    ComponentKind.named(part.kind)?.options ?? const [];

List<String> _styleOf(Component part) =>
    ComponentKind.named(part.kind)?.style ?? const [];

/// What one instance of a prefab sets for itself: the prefab it is of, the
/// variant, and for each component of the prefab whether it shows and
/// whatever it says differently. Only what differs from the prefab is
/// kept, value by value, so everything else goes on following the prefab.
class InstanceSettings extends StatelessWidget {
  const InstanceSettings({
    super.key,
    required this.prefabs,
    required this.item,
    required this.onChanged,
  });

  final Map<String, Prefab> prefabs;
  final Component item;

  /// Called with the instance as it is to be.
  final void Function(Component item) onChanged;

  void _override(String part, Map<String, Object?> values, [String? section]) =>
      onChanged(
        item.copyWith(
          overrides: withOverride(item.overrides, part, values, section),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final prefab = prefabs[item.prefab];
    final theme = Theme.of(context);
    // As it is drawn, and as it would be with nothing set for it here.
    final parts = {
      for (final part in resolved(item, prefabs).all.skip(1))
        if (!part.isPane) part.id.substring(item.id.length + 1): part,
    };
    final base = {
      for (final part in resolved(
        item.copyWith(overrides: const {}),
        prefabs,
      ).all.skip(1))
        part.id.substring(item.id.length + 1): part,
    };
    return Section('Prefab', [
      LabelledRow(
        'Made from',
        ChoiceBox<String>(
          value: prefab?.id,
          choices: {
            for (final prefab in prefabs.values) prefab.id: prefab.name,
          },
          onChanged: (id) => onChanged(item.copyWith(prefab: id)),
        ),
      ),
      if (prefab != null) ...[
        if (prefab.variants.isNotEmpty)
          LabelledRow(
            'Laid out',
            ChoiceBox<String>(
              value: prefab.variantOf(item),
              choices: {
                for (final MapEntry(:key, :value) in prefab.variants.entries)
                  key: value.label.isEmpty ? key : value.label,
              },
              onChanged: (name) => onChanged(item.withVariant(name)),
            ),
          ),
        for (final MapEntry(key: id, value: part) in parts.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(id, style: theme.textTheme.labelLarge),
          ),
          TickBox(
            label: 'Shown',
            value: !part.hidden,
            onChanged: (shown) => _override(id, {
              'hidden': shown == !base[id]!.hidden ? null : !shown,
            }),
          ),
          ...optionFields(
            options: _optionsOf(part),
            values: part.options,
            onChanged: (next) => _override(id, {
              for (final option in _optionsOf(part))
                option.key: next[option.key] == base[id]!.options[option.key]
                    ? null
                    // Set back to the usual where the prefab says
                    // otherwise: that has to be said outright.
                    : next[option.key] ?? option.usual ?? '',
            }, 'options'),
          ),
          // Its look, of which only what differs from the prefab's is kept.
          ...styleFields(
            keys: _styleOf(part),
            style: part.style,
            onChanged: (key, value) => _override(id, {
              key: base[id]!.style[key] == value ? null : value,
            }, 'style'),
          ),
        ],
        if (item.overrides.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => onChanged(item.copyWith(overrides: const {})),
              child: const Text('Back to what the prefab says'),
            ),
          ),
      ],
    ]);
  }
}

/// The prefabs there are, each with the components it is made of to be
/// set. A change to one of the launcher's own makes a copy of it that
/// stands in for it, until it is taken back.
class PrefabsSettings extends StatelessWidget {
  const PrefabsSettings({
    super.key,
    required this.prefabs,
    required this.own,
    required this.onChanged,
  });

  /// Every prefab, by id, and those of them that are the user's.
  final Map<String, Prefab> prefabs;
  final List<Prefab> own;
  final void Function(List<Prefab> own) onChanged;

  static bool _builtIn(String id) =>
      builtInPrefabs.any((prefab) => prefab.id == id);

  void _put(Prefab changed) => onChanged([
    for (final prefab in own)
      if (prefab.id != changed.id) prefab,
    changed,
  ]);

  void _drop(String id) => onChanged([
    for (final prefab in own)
      if (prefab.id != id) prefab,
  ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Section('Prefabs', open: false, [
      const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          'What the things on the screen are made from. A change here '
          'reaches every one that has not set that very thing for itself.',
        ),
      ),
      for (final prefab in prefabs.values) ...[
        const Divider(height: 24),
        Text(prefab.name, style: theme.textTheme.titleSmall),
        for (final part in prefab.parts) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(part.id, style: theme.textTheme.labelLarge),
          ),
          ...optionFields(
            options: _optionsOf(part),
            values: part.options,
            onChanged: (next) => _put(
              prefab.withPart(part.id, (part) => part.copyWith(options: next)),
            ),
          ),
          ...styleFields(
            keys: _styleOf(part),
            style: part.style,
            onChanged: (key, value) => _put(
              prefab.withPart(
                part.id,
                (part) =>
                    part.copyWith(style: withStyle(part.style, {key: value})),
              ),
            ),
          ),
        ],
        // The look every instance starts with.
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Its look', style: theme.textTheme.labelLarge),
        ),
        ...styleFields(
          keys: const [...boxStyle, ...textStyle],
          style: prefab.style,
          onChanged: (key, value) => _put(
            prefab.copyWith(
              root: prefab.root.copyWith(
                style: withStyle(prefab.style, {key: value}),
              ),
            ),
          ),
        ),
        // What its components read by name, and what an instance may set.
        VariablesSettings(
          variables: prefab.vars,
          onChanged: (vars) =>
              _put(prefab.copyWith(root: prefab.root.copyWith(vars: vars))),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () async {
                final name = await askName(
                  context,
                  '${prefab.name} copy',
                  title: 'Name of the prefab',
                );
                if (name == null || name.isEmpty) return;
                _put(
                  prefab.copyWith(
                    id: freeId(slugOf(name, 'prefab'), prefabs.keys.toSet()),
                    name: name,
                  ),
                );
              },
              child: const Text('Make a copy'),
            ),
            if (own.any((one) => one.id == prefab.id))
              TextButton(
                onPressed: () => _drop(prefab.id),
                child: Text(
                  _builtIn(prefab.id)
                      ? "Back to the launcher's own"
                      : 'Delete it',
                ),
              ),
          ],
        ),
      ],
    ]);
  }
}
