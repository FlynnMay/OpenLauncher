import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/option_fields.dart';

List<WidgetOption> _optionsOf(String kind) =>
    WidgetKind.named(kind)?.options ?? const [];

/// What one instance of a prefab sets for itself: the prefab it is of, the
/// layout, and for each part whether it shows and whatever it says
/// differently. Only what differs from the prefab is kept, value by value,
/// so everything else goes on following the prefab.
class InstanceSettings extends StatelessWidget {
  const InstanceSettings({
    super.key,
    required this.prefabs,
    required this.item,
    required this.onChanged,
    this.onPrefab,
  });

  final Map<String, Prefab> prefabs;
  final LayoutItem item;

  /// Called with the id of another prefab for the item to be an instance
  /// of, where the item itself is what says which.
  final void Function(String id)? onPrefab;

  /// Called with the item's options as they are to be.
  final void Function(Map<String, Object?> options) onChanged;

  void _set(String key, Object? value) => onChanged(
    {...item.options, key: value}..removeWhere((_, value) => value == null),
  );

  @override
  Widget build(BuildContext context) {
    final prefab = prefabs[prefabIdOf(item)];
    final instance = prefab == null ? null : instanceOf(prefab, item);
    final theme = Theme.of(context);
    final own = item.options[partsOption] != null;
    return Section('Prefab', [
      LabelledRow(
        'Made from',
        ChoiceBox<String>(
          value: prefab?.id,
          choices: {
            for (final prefab in prefabs.values) prefab.id: prefab.name,
          },
          // An instance names its prefab itself; a card that opens a
          // folder says so among its options, unless it is the usual one.
          onChanged: (id) => switch (onPrefab) {
            final onPrefab? => onPrefab(id),
            null => _set(prefabOption, id == folderPrefabId ? null : id),
          },
        ),
      ),
      if (prefab != null && instance != null) ...[
        LabelledRow(
          'Laid out',
          ChoiceBox<String>(
            value: instance.layoutName,
            choices: {
              for (final MapEntry(:key, :value) in prefab.layouts.entries)
                key: value.label.isEmpty ? key : value.label,
            },
            onChanged: (name) => _set(layoutOption, name),
          ),
        ),
        for (final part in instance.parts) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(part.id, style: theme.textTheme.labelLarge),
          ),
          TickBox(
            label: 'Shown',
            value: !part.hidden,
            onChanged: (shown) => onChanged(
              withOverrides(item.options, part.id, {
                hiddenOption: shown ? null : true,
              }),
            ),
          ),
          ...optionFields(
            options: _optionsOf(part.kind),
            values: part.options,
            onChanged: (next) {
              // What the part would be with nothing set for it here.
              final base = {
                ...?prefab.parts[part.id]?.options,
                ...part.slot.options,
              };
              onChanged(
                withOverrides(item.options, part.id, {
                  for (final option in _optionsOf(part.kind))
                    option.key: next[option.key] == base[option.key]
                        ? null
                        // Set back to the usual where the prefab says
                        // otherwise: that has to be said outright.
                        : next[option.key] ?? option.usual ?? '',
                }),
              );
            },
          ),
        ],
        if (own)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _set(partsOption, null),
              child: const Text('Back to what the prefab says'),
            ),
          ),
      ],
    ]);
  }
}

/// The prefabs there are, each with the parts it is made of to be set. A
/// change to one of the launcher's own makes a copy of it that stands in
/// for it, until it is taken back.
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
        for (final MapEntry(key: id, value: part) in prefab.parts.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(id, style: theme.textTheme.labelLarge),
          ),
          ...optionFields(
            options: _optionsOf(part.kind),
            values: part.options,
            onChanged: (next) => _put(
              prefab.copyWith(
                parts: {...prefab.parts, id: PrefabPart(part.kind, next)},
              ),
            ),
          ),
        ],
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
