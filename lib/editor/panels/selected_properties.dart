import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/modules/modules.dart';
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
    final handed = ref.watch(selectedHandedProvider);

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
            onChanged: (how) => change(
              (layout) => layout.withContainer(handed.keys.single, how),
            ),
          ),
        Section('Node', [
          if (single != null)
            CommitField(
              label: 'Name',
              value: single.name,
              onChanged: (name) => each((item) => item.copyWith(name: name)),
            ),
          TickBox(
            label: 'Visible',
            value: !(shared(items.map((item) => item.hidden)) ?? false),
            onChanged: (visible) =>
                each((item) => item.copyWith(hidden: !visible)),
          ),
          if (single != null)
            TemplateField(
              label: 'Visible when',
              value: single.visible ?? '',
              onChanged: (visible) => each((item) => item.withVisible(visible)),
            ),
        ]),
        if (single != null)
          TransformSettings(
            node: single,
            parentSize: () =>
                Stage.sizeOf(found.single.parent.id) ?? const Size(960, 540),
            placedBy: switch (found.single.parent) {
              _ when resolved(single, prefabs).isDocked => 'its Dock',
              _ when isRoot => 'each instance',
              final parent when parent.has(layoutModule.name) =>
                "its parent's Layout",
              _ => null,
            },
            onChanged: (transform) =>
                each((item) => item.copyWith(transform: transform)),
          ),
        if (single != null && single.isInstance) ...[
          if (found.single.parent.prefabRules.containsKey(single.prefab))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Its parent has a rule for this prefab, which overrides '
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
        ],
        ModuleSections(
          nodes: items,
          parents: [for (final one in found) one.parent],
          onChanged: each,
          onLayout: change,
          inPrefab: prefab != null,
          exposable: isRoot,
          inDock: found.any((one) => one.dock != null),
          // What the nodes around it hand down.
          scope: {
            if (single != null)
              for (final container in [?found.single.dock, found.single.parent])
                for (final MapEntry(:key, :value) in container.vars.entries)
                  if (value.access != VarAccess.private) key: value,
          },
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
                // A container or primitive on the screen can be saved for
                // reuse.
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
          if (node.offCells)
            OutlinedButton.icon(
              onPressed: () => TvScreen.openDocked(node.id),
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
