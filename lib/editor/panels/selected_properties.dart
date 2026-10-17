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
    final folders = ref.watch(selectedFoldersProvider);
    final allFolders =
        items.every((item) => item.isInstance) &&
        folders.length == items.length;
    void eachFolder(Node Function(Node pane) how) => change(
      (layout) =>
          folders.keys.fold(layout, (layout, id) => layout.withPane(id, how)),
    );

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
        if (single != null && allFolders)
          _FolderDetails(
            folder: folders.values.single,
            onRenamed: (title) =>
                eachFolder((pane) => pane.copyWith(name: title)),
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
          corner: allPanes ? LayoutModule.defaultCorner : 10,
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
        if (allFolders)
          Section('Folder', [
            // The pane's own id, apart from its card's.
            if (single != null)
              Align(
                alignment: Alignment.centerLeft,
                child: IdLabel(folders.keys.single),
              ),
            if (single != null)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => TvScreen.openPane(folders.keys.single),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Open'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      if (await sureToRemove(
                            context,
                            'Delete the folder?',
                            'Delete',
                          ) &&
                          context.mounted) {
                        ref.read(selectionProvider.notifier).clear();
                        change(
                          (layout) => removeItem(layout, folders.keys.single),
                        );
                      }
                    },
                    icon: const Icon(Icons.folder_delete_outlined),
                    label: const Text('Delete folder'),
                  ),
                ],
              ),
          ]),
        // The folder itself is a pane like any other.
        if (allFolders && single != null) ...[
          PaneSettings(
            title: 'Folder pane',
            prefabs: prefabs,
            named: false,
            panes: [folders.values.single],
            onChanged: eachFolder,
          ),
          Section(
            'Folder look',
            open: false,
            styleFields(
              keys: const [...boxStyle, ...textStyle],
              style: folders.values.single.style,
              corner: LayoutModule.defaultCorner,
              onChanged: (key, value) => eachFolder(
                (pane) => pane.styled(withStyle(pane.style, {key: value})),
              ),
            ),
          ),
        ],
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
class _FolderDetails extends ConsumerWidget {
  const _FolderDetails({required this.folder, required this.onRenamed});

  final Node folder;
  final void Function(String title) onRenamed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(tvApiProvider);
    final key = Layout.iconKey(folder.id);
    final picture = ref.watch(configProvider).value?.iconOverrides[key];
    return Section('Folder card', [
      CommitField(label: 'Name', value: folder.name, onChanged: onRenamed),
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
    ]);
  }
}
