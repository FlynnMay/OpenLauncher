import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/panels/entity_picker.dart';
import 'package:openlauncher/editor/settings/settings.dart';
import 'package:openlauncher/editor/stage/stage.dart';
import 'package:openlauncher/editor/tv/tv.dart';
import 'package:openlauncher/features/home/entity_art.dart';
import 'package:openlauncher/features/home/picture.dart';

/// Settings of the selection. With several selected, only shared settings
/// show and changes apply to all.
class SelectedProperties extends ConsumerWidget {
  const SelectedProperties({super.key, required this.found});

  final List<Found> found;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = {for (final one in found) one.item.id};
    final items = [for (final one in found) one.item];
    final single = items.length == 1 ? items.single : null;
    final entities = ref.watch(entitiesProvider).value ?? const <Entity>[];
    void change(Layout Function(Layout layout) how) =>
        changeLayout(context, ref, how);
    void each(Node Function(Node item) how) =>
        change((layout) => changeItems(layout, ids, (item, _) => how(item)));

    // In an open prefab: the prefab, the variant shown when its edits are
    // overrides, and whether the selection is the prefab's root.
    final prefab = ref.watch(editedPrefabProvider);
    final shown = ref.watch(prefabModeProvider)?.variant;
    final variant = prefab == null || prefab.isBase(shown)
        ? null
        : prefab.variants[prefab.variantNamed(shown)];
    final isRoot = prefab != null && single?.id == prefab.root.id;
    final prefabs = ref.watch(prefabsProvider);
    final declared =
        prefabs[single?.prefab]?.root.vars ?? const <String, Variable>{};
    final fielded = single != null && single.isInstance
        ? InstanceVariables.shown(declared, single.vars)
        : const <String>{};

    final allPanes = items.every((item) => item.isPane);
    final handed = ref.watch(selectedHandedProvider);

    final transform = {
      'w': [for (final item in items) item.w],
      'h': [for (final item in items) item.h],
      'x': [for (final item in items) item.x],
      'y': [for (final item in items) item.y],
      'flex': [for (final item in items) item.flex],
      'aspect': [for (final item in items) item.aspect],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (single != null && variant != null)
          Section('Variant overrides', [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'What "${variant.label}" changes here. Other edits made '
                'now are added to it.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            OverrideList(
              set: variant.overrides[single.id] ?? const {},
              onReverted: (module, key) =>
                  revertOverride(ref, single.id, module, key),
            ),
          ]),
        // Name and picture apply to auto-placed entities (apps, inputs) only.
        if (single != null &&
            single.isInstance &&
            (entities.byId(single.handed.firstOrNull)?.placed ?? false))
          _EntityDetails(entityId: single.handed.firstOrNull ?? ''),
        if (single != null && handed.length == 1)
          _HandedNode(
            node: handed.values.single,
            onChanged: (how) =>
                change((layout) => layout.withPane(handed.keys.single, how)),
          ),
        if (single != null && !single.isInstance && !single.isPane)
          ComponentSettings(
            item: single,
            onChanged: (values) => each(
              (item) => item.visual == null
                  ? item
                  : item.withModule(item.visual!.name, values),
            ),
          ),
        if (single != null && single.isInstance) ...[
          if (found.single.parent.prefabRules.containsKey(single.prefab))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Its pane has a rule for this prefab, which overrides '
                'what is set here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          InstanceSettings(
            prefabs: prefabs,
            item: single,
            onChanged: (next) => each((_) => next),
            onOpen: () => openPrefab(ref, single.prefab!, from: single),
            onUnpack: () => changeLayout(
              context,
              ref,
              (layout) => withUnpacked(layout, single.id, prefabs),
            ),
          ),
          InstanceVariables(
            declared: declared,
            own: single.vars,
            onChanged: (vars) => each((item) => item.withVars(vars)),
          ),
          // Where it docks is its own; shown as its prefab and it say.
          if (resolved(single, prefabs) case final drawn when drawn.isDocked)
            Section('Dock', dockFields(drawn, each)),
        ],
        if (single != null && !single.isPane)
          VariablesSettings(
            // An instance's own, besides those it has fields for.
            variables: {
              for (final MapEntry(key: name, :value) in single.vars.entries)
                if (!fielded.contains(name)) name: value,
            },
            note: single.isInstance
                ? 'Its own, besides the prefab\'s. One named as a prefab '
                      'variable overrides it.'
                : null,
            exposable: isRoot,
            onChanged: (vars) => each(
              (item) => item.withVars({
                for (final MapEntry(key: name, :value) in item.vars.entries)
                  if (fielded.contains(name)) name: value,
                ...vars,
              }),
            ),
          ),
        // A row or column with actions is a tile.
        if (single != null &&
            (!single.isPane || single.mode.inLine && !single.isDocked))
          TriggerSettings(
            set: single.on,
            defaults: {...?prefabs[single.prefab]?.on},
            // Its own variables over what the panes around it hand down.
            scope: {
              for (final pane in [?found.single.dock, found.single.parent])
                for (final MapEntry(:key, :value) in pane.vars.entries)
                  if (value.access != VarAccess.private) key: value,
              ...variablesOf(single, prefabs),
            },
            onChanged: (on) => each((item) => withPressable(item, on)),
          ),
        // A prefab's part is hidden, not removed, where a variant lacks it.
        if (single != null && prefab != null && !isRoot)
          Section('Visibility', [
            TickBox(
              label: 'Visible',
              value: !single.hidden,
              onChanged: (visible) =>
                  each((item) => item.copyWith(hidden: !visible)),
            ),
            if (found.single.parent.mode.inLine)
              TickBox(
                label: 'Keep space when hidden',
                value: single.keep,
                onChanged: (keep) => each(
                  (item) => item.withValue(sizingModule.name, 'keep', keep),
                ),
              ),
          ]),
        // A docked pane has no cells, nor what has no layout around it.
        if (!items.any((item) => item.isDocked) &&
            found.every((one) => one.parent.mode != PaneMode.free))
          Section(
            'Sizing',
            ruleFields(
              options: SizingModule.fieldsIn([
                for (final one in found) one.parent,
              ], found.map((one) => one.parent.reach).reduce(min)),
              json: {
                for (final MapEntry(:key, :value) in transform.entries)
                  key: ?shared<double?>(value),
              },
              mixed: {
                for (final MapEntry(:key, :value) in transform.entries)
                  if (value.toSet().length > 1) key,
              },
              onChanged: (key, value) => change(
                (layout) => transformItems(
                  layout,
                  ids,
                  key,
                  (value as num?)?.toDouble(),
                ),
              ),
            ),
          ),
        // Only style keys common to all.
        StyleSettings(
          keys: items
              .map((item) => item.styleKeys.toSet())
              .reduce((all, own) => all.intersection(own)),
          style: items.first.style,
          onChanged: (key, value) =>
              each((item) => item.styled(withStyle(item.style, {key: value}))),
        ),
        if (allPanes)
          PaneSettings(
            title: 'Pane',
            prefabs: prefabs,
            panes: items,
            onChanged: each,
            dockable: prefab == null,
            exposable: isRoot,
            children: [
              // Not in a docked pane or a prefab.
              if (single != null &&
                  prefab == null &&
                  found.single.dock == null &&
                  !single.isDocked)
                TickBox(
                  label: 'New apps go here',
                  value: ref.watch(inboxProvider) == single.id,
                  onChanged: (here) {
                    if (here) {
                      change((layout) => withInbox(layout, single.id));
                    }
                  },
                ),
            ],
          ),
        if (!isRoot)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => removeSelected(context, ref),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
                // A pane or primitive on the screen can be saved for reuse.
                if (single != null &&
                    prefab == null &&
                    !single.isInstance &&
                    !single.all.any((part) => part.isDocked))
                  OutlinedButton.icon(
                    onPressed: () => createPrefab(context, ref, found.single),
                    icon: const Icon(prefabIcon),
                    label: const Text('Create prefab'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// An entity's name and picture.
class _EntityDetails extends ConsumerStatefulWidget {
  const _EntityDetails({required this.entityId});

  final String entityId;

  @override
  ConsumerState<_EntityDetails> createState() => _EntityDetailsState();
}

class _EntityDetailsState extends ConsumerState<_EntityDetails>
    with Busy<_EntityDetails> {
  @override
  Widget build(BuildContext context) {
    final api = ref.watch(tvApiProvider);
    final entities = ref.watch(entitiesProvider).value ?? const <Entity>[];
    final entity = entities.byId(widget.entityId);
    if (entity == null) return const SizedBox.shrink();
    final config = ref.watch(configProvider).value;
    final from = config?.iconSources[entity.id];
    final borrowed = entities.byId(from);
    final custom =
        from != null || (config?.iconOverrides.containsKey(entity.id) ?? false);
    Future<void> change(
      Future<void> Function(ConfigController controller) how,
    ) => whileBusy(() => changeConfig(context, ref, how));
    return Section('Source', [
      CommitField(
        label: 'Name',
        value: entity.label,
        // Empty restores the device's name.
        onChanged: (name) => change((c) => c.setName(entity.id, name)),
      ),
      if (config?.names.containsKey(entity.id) ?? false)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: busy
                ? null
                : () => change((c) => c.setName(entity.id, null)),
            child: const Text('Reset name'),
          ),
        ),
      PictureSettings(
        picture: EntityArt(entity: entity, padding: 10),
        clearLabel: 'Reset picture',
        onPicked: (file) async {
          final url = await api.upload(file);
          await change((c) => c.setIconOverride(entity.id, url));
        },
        onCleared: custom
            ? () => change((c) => c.setIconOverride(entity.id, null))
            : null,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final from = await pickEntity(
                    context,
                    title: 'Use picture from',
                    entities: [
                      for (final other in entities)
                        // Only entities that have pictures.
                        if (other.id != entity.id && other.placed) other,
                    ],
                  );
                  if (from != null) {
                    await change((c) => c.setIconSource(entity.id, from.id));
                  }
                },
          icon: const Icon(Icons.collections_outlined),
          label: Text(
            borrowed == null
                ? 'Use picture from…'
                : 'Picture from ${borrowed.label}',
          ),
        ),
      ),
    ]);
  }
}

/// A folder's name and picture.
/// The node an instance is handed, as a card shows it: its name and picture,
/// and ways to open it, select it or delete it.
class _HandedNode extends ConsumerWidget {
  const _HandedNode({required this.node, required this.onChanged});

  final Node node;
  final void Function(Node Function(Node node) how) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(tvApiProvider);
    final key = Layout.pictureKey(node.id);
    final picture = ref.watch(configProvider).value?.iconOverrides[key];
    return Section('Handed node', [
      Align(alignment: Alignment.centerLeft, child: IdLabel(node.id)),
      CommitField(
        label: 'Name',
        value: node.name,
        onChanged: (name) => onChanged((node) => node.copyWith(name: name)),
      ),
      PictureSettings(
        picture: picture == null
            ? null
            : Image(image: pictureAt(picture), fit: BoxFit.cover),
        empty: 'Preview of contents',
        clearLabel: 'Reset picture',
        onPicked: (file) async {
          final url = await api.upload(file);
          if (!context.mounted) return;
          await changeConfig(context, ref, (c) => c.setIconOverride(key, url));
        },
        onCleared: picture == null
            ? null
            : () => changeConfig(
                context,
                ref,
                (c) => c.setIconOverride(key, null),
              ),
      ),
      Wrap(
        spacing: 8,
        children: [
          if (node.isDocked)
            OutlinedButton.icon(
              onPressed: () => TvScreen.openPane(node.id),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open'),
            ),
          TextButton(
            onPressed: () => ref
                .read(selectionProvider.notifier)
                .tap(node.id, adding: false),
            child: const Text('Select'),
          ),
          TextButton.icon(
            onPressed: () async {
              if (await sureToRemove(
                    context,
                    'Delete ${node.name.isEmpty ? 'it' : node.name}?',
                    'Delete',
                  ) &&
                  context.mounted) {
                ref.read(selectionProvider.notifier).clear();
                await changeLayout(
                  context,
                  ref,
                  (layout) => removeItem(layout, node.id),
                );
              }
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        ],
      ),
    ]);
  }
}
