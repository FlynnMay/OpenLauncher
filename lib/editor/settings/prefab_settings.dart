import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/settings/style_settings.dart';

List<ComponentOption> _optionsOf(Component part) =>
    ComponentRegistry.named(part.kind)?.options ?? const [];

List<String> _styleOf(Component part) =>
    ComponentRegistry.named(part.kind)?.style ?? const [];

/// An instance's own settings: which prefab it is of, its variant, and
/// per-part visibility, options and style. Only differences from the prefab
/// are stored.
class InstanceSettings extends StatelessWidget {
  const InstanceSettings({
    super.key,
    required this.prefabs,
    required this.item,
    required this.onChanged,
    this.onOpen,
    this.onUnpack,
  });

  final Map<String, Prefab> prefabs;
  final Component item;

  final void Function(Component item) onChanged;

  /// Opens its prefab for editing.
  final VoidCallback? onOpen;

  /// Replaces it with a plain copy.
  final VoidCallback? onUnpack;

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
    // As drawn, and as it would be without its own overrides.
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
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          spacing: 8,
          children: [
            Icon(prefabIcon, size: 18, color: theme.colorScheme.primary),
            Expanded(
              child: Text(
                prefab?.name ?? 'Missing prefab "${item.prefab}"',
                style: theme.textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          if (prefab != null && onOpen != null)
            OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Open'),
            ),
          if (onUnpack != null)
            TextButton(onPressed: onUnpack, child: const Text('Unpack')),
        ],
      ),
      if (prefab != null) ...[
        if (prefab.variants.isNotEmpty)
          LabelledRow(
            'Variant',
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
            label: 'Visible',
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
                    // Resetting to the default where the prefab differs must
                    // be stored explicitly.
                    : next[option.key] ?? option.defaultValue ?? '',
            }, 'options'),
          ),
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
              child: const Text('Reset to prefab'),
            ),
          ),
      ],
    ]);
  }
}

/// One child's overrides, each with a revert.
class OverrideList extends StatelessWidget {
  const OverrideList({
    super.key,
    required this.set,
    required this.onReverted,
    this.options = const [],
  });

  /// One entry of an [Overrides]: `options`, `style`, `transform`, `hidden`.
  final Map<String, Object?> set;

  /// The child's options, for their labels.
  final List<ComponentOption> options;

  /// Called with the section and key to revert; with neither for all.
  final void Function(String? section, String? key) onReverted;

  static const _transform = {
    'w': 'Width',
    'h': 'Height',
    'x': 'X',
    'y': 'Y',
    'flex': 'Flex',
    'aspect': 'Aspect ratio',
    'keep': 'Keep space when hidden',
  };

  String _label(String section, String key) => switch (section) {
    'style' => stylePropsOf([key]).firstOrNull?.label ?? key,
    'transform' => _transform[key] ?? key,
    _ => options.where((option) => option.key == key).firstOrNull?.label ?? key,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, String? section, String? key) => Row(
      children: [
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          tooltip: 'Revert',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.undo, size: 18),
          onPressed: () => onReverted(section, key),
        ),
      ],
    );
    final rows = [
      for (final section in const ['options', 'style', 'transform'])
        if (set[section] case final Map<Object?, Object?> values)
          for (final key in values.keys.whereType<String>())
            row(_label(section, key), section, key),
      if (set.containsKey('hidden')) row('Visible', null, 'hidden'),
    ];
    if (rows.isEmpty) {
      return Text('None', style: theme.textTheme.bodySmall);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...rows,
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => onReverted(null, null),
            child: const Text('Revert all'),
          ),
        ),
      ],
    );
  }
}

/// How many instances [prefab] has, in words.
String _used(WidgetRef ref, Prefab prefab) {
  final config = ref.watch(configProvider).value;
  final count = config == null
      ? 0
      : instancesOf(prefab.id, config.layout, config.prefabs);
  return count == 1 ? '1 instance' : '$count instances';
}

bool _edited(WidgetRef ref, Prefab prefab) =>
    ref
        .watch(configProvider)
        .value
        ?.prefabs
        .any((own) => own.id == prefab.id) ??
    false;

/// Every prefab: opened for editing, duplicated, deleted. One a pack ships that
/// was edited can be reset.
class PrefabList extends ConsumerWidget {
  const PrefabList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefabs = ref.watch(prefabsProvider);
    return Section('Prefabs', open: false, [
      for (final prefab in prefabs.values)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(prefab.name),
          subtitle: Text(
            [
              _used(ref, prefab),
              if (shippedBy(ref, prefab.id) case final pack?)
                _edited(ref, prefab) ? '$pack, modified' : pack,
            ].join(' · '),
          ),
          onTap: () => openPrefab(ref, prefab.id),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Open ${prefab.name}',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => openPrefab(ref, prefab.id),
              ),
              _PrefabMenu(prefab),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => newPrefab(context, ref),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New prefab'),
        ),
      ),
    ]);
  }
}

/// Duplicate, rename, and delete or reset.
class _PrefabMenu extends ConsumerWidget {
  const _PrefabMenu(this.prefab);

  final Prefab prefab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = shippedBy(ref, prefab.id);
    return PopupMenuButton<void Function()>(
      tooltip: 'More',
      iconSize: 18,
      onSelected: (does) => does(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: () => duplicatePrefab(context, ref, prefab),
          child: const Text('Duplicate'),
        ),
        PopupMenuItem(
          value: () => renamePrefab(context, ref, prefab),
          child: const Text('Rename'),
        ),
        if (pack == null || _edited(ref, prefab))
          PopupMenuItem(
            value: () => deletePrefab(context, ref, prefab),
            child: Text(pack == null ? 'Delete' : 'Revert to $pack'),
          ),
      ],
    );
  }
}

/// The open prefab itself: its name and what can be done with it.
class PrefabDetails extends ConsumerWidget {
  const PrefabDetails({super.key, required this.prefab});

  final Prefab prefab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pack = shippedBy(ref, prefab.id);
    return Section('Prefab', [
      CommitField(
        label: 'Name',
        value: prefab.name,
        onChanged: (name) {
          if (name.isEmpty) return;
          ref
              .read(configProvider.notifier)
              .change(
                (c) => c.copyWith(
                  prefabs: withPrefab(c.prefabs, prefab.copyWith(name: name)),
                ),
              );
        },
      ),
      Text(_used(ref, prefab), style: Theme.of(context).textTheme.bodySmall),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: () => duplicatePrefab(context, ref, prefab),
            child: const Text('Duplicate'),
          ),
          if (pack == null || _edited(ref, prefab))
            TextButton(
              onPressed: () => deletePrefab(context, ref, prefab),
              child: Text(pack == null ? 'Delete' : 'Revert to $pack'),
            ),
        ],
      ),
    ]);
  }
}
