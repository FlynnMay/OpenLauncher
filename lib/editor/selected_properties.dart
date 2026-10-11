import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/actions.dart';
import 'package:openlauncher/editor/component_settings.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/entity_picker.dart';
import 'package:openlauncher/editor/layout_edit.dart';
import 'package:openlauncher/editor/option_fields.dart';
import 'package:openlauncher/editor/pane_settings.dart';
import 'package:openlauncher/editor/picture_settings.dart';
import 'package:openlauncher/editor/prefab_settings.dart';
import 'package:openlauncher/editor/selection.dart';
import 'package:openlauncher/editor/style_settings.dart';
import 'package:openlauncher/editor/trigger_settings.dart';
import 'package:openlauncher/editor/tv_api.dart';
import 'package:openlauncher/editor/tv_screen.dart';
import 'package:openlauncher/editor/variables_settings.dart';
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
    void each(Component Function(Component item) how) =>
        change((layout) => changeItems(layout, ids, (item, _) => how(item)));

    final allPanes = items.every((item) => item.isPane);
    final folders = ref.watch(selectedPanelsProvider);
    final allFolders =
        items.every((item) => item.isInstance) &&
        folders.length == items.length;
    void eachFolder(Panel Function(Panel panel) how) => change(
      (layout) => folders.keys.fold(
        layout,
        (layout, id) => changePanel(layout, id, how),
      ),
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
        // Name and picture apply to auto-placed entities (apps, inputs) only.
        if (single != null &&
            single.isInstance &&
            (entityRegistry(
                  entities.byId(single.handed.firstOrNull)?.category ?? '',
                )?.placed ??
                false))
          _EntityDetails(entityId: single.handed.firstOrNull ?? ''),
        if (single != null && allFolders)
          _FolderDetails(
            panel: folders.values.single,
            onRenamed: (title) =>
                eachFolder((panel) => withPanelRule(panel, 'title', title)),
          ),
        if (single != null && !single.isInstance && !single.isPane)
          ComponentSettings(
            item: single,
            onChanged: (options) =>
                each((item) => item.copyWith(options: options)),
          ),
        if (single != null && single.isInstance) ...[
          if (found.single.parent.prefabRules.containsKey(single.prefab))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'The pane this is in has a rule for its prefab, which '
                'counts over what is set here until the rule is gone.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          InstanceSettings(
            prefabs: ref.watch(prefabsProvider),
            item: single,
            onChanged: (next) => each((_) => next),
          ),
        ],
        if (single != null && !single.isPane)
          VariablesSettings(
            variables: single.vars,
            note: single.isInstance
                ? 'Its own, set over those its prefab has, which are '
                      'under Prefabs.'
                : null,
            onChanged: (vars) => each((item) => item.copyWith(vars: vars)),
          ),
        if (single != null && !single.isPane)
          TriggerSettings(
            set: single.on,
            // The prefab's triggers are the defaults.
            usual: {...?ref.watch(prefabsProvider)[single.prefab]?.on},
            entities: {
              for (final entity
                  in ref.watch(entitiesProvider).value ?? const <Entity>[])
                entity.id: entity.label,
            },
            onChanged: (on) => each((item) => item.copyWith(on: on)),
          ),
        Section(
          'Transform',
          ruleFields(
            options: transformOptions([for (final one in found) one.parent]),
            json: {
              for (final MapEntry(:key, :value) in transform.entries)
                key: ?shared<double?>(value),
            },
            mixed: {
              for (final MapEntry(:key, :value) in transform.entries)
                if (value.toSet().length > 1) key,
            },
            onChanged: (key, value) => change(
              (layout) =>
                  transformItems(layout, ids, key, (value as num?)?.toDouble()),
            ),
          ),
        ),
        // Only style keys common to all.
        StyleSettings(
          keys: items
              .map((item) => item.styleKeys.toSet())
              .reduce((all, own) => all.intersection(own)),
          style: items.first.style,
          corner: allPanes ? Component.defaultCorner : 10,
          onChanged: (key, value) => each(
            (item) => item.copyWith(style: withStyle(item.style, {key: value})),
          ),
        ),
        if (allPanes)
          PaneSettings(
            title: 'Pane',
            prefabs: ref.watch(prefabsProvider),
            panes: items,
            onChanged: each,
            children: [
              if (single != null && found.single.panel.kind == PanelKind.home)
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
            ...ruleFields(
              options: panelRules(folders.values.first.kind),
              json: folders.values.first.rules,
              onChanged: (key, value) =>
                  eachFolder((panel) => withPanelRule(panel, key, value)),
            ),
            if (single != null)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => TvScreen.openPopup(folders.keys.single),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Open it'),
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
                          (layout) => removePanel(layout, folders.keys.single),
                        );
                      }
                    },
                    icon: const Icon(Icons.folder_delete_outlined),
                    label: const Text('Delete the folder'),
                  ),
                ],
              ),
          ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: FilledButton.tonalIcon(
            onPressed: () => removeSelected(context, ref),
            icon: const Icon(Icons.delete_outline),
            label: Text(
              single != null ? 'Take it off the TV' : 'Take them off the TV',
            ),
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
    final details = ref.watch(tvStateProvider).value?.details[entity.id];
    final borrowed = entities.byId(details?.iconFrom);
    return Section('Source', [
      CommitField(
        label: 'Name',
        value: entity.label,
        // Empty restores the device's name.
        onChanged: (name) =>
            whileBusy(() => api.rename(entity.id, name.isEmpty ? null : name)),
      ),
      if (details?.renamed ?? false)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: busy
                ? null
                : () => whileBusy(() => api.rename(entity.id, null)),
            child: const Text("Use the TV's name for it"),
          ),
        ),
      PictureSettings(
        picture: EntityArt(entity: entity, padding: 10),
        clearLabel: 'Back to its own picture',
        onPicked: (file) => api.setPicture(entity.id, file),
        onCleared: details?.customIcon ?? false
            ? () => api.clearPicture(entity.id)
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
                    title: "Use another one's picture",
                    entities: [
                      for (final other in entities)
                        // Only entities that have pictures.
                        if (other.id != entity.id &&
                            (entityRegistry(other.category)?.placed ?? false))
                          other,
                    ],
                  );
                  if (from != null) {
                    await whileBusy(
                      () => api.borrowPicture(entity.id, from.id),
                    );
                  }
                },
          icon: const Icon(Icons.collections_outlined),
          label: Text(
            borrowed == null
                ? "Use another one's picture"
                : 'Showing the picture of ${borrowed.label}',
          ),
        ),
      ),
    ]);
  }
}

/// A folder's name and picture.
class _FolderDetails extends ConsumerWidget {
  const _FolderDetails({required this.panel, required this.onRenamed});

  final Panel panel;
  final void Function(String title) onRenamed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(tvApiProvider);
    final key = Panel.iconKey(panel.id);
    final picture = ref.watch(configProvider).value?.iconOverrides[key];
    return Section('Folder card', [
      CommitField(label: 'Name', value: panel.title, onChanged: onRenamed),
      PictureSettings(
        picture: picture == null
            ? null
            : Image(image: pictureAt(picture), fit: BoxFit.cover),
        empty: 'Shows what is inside',
        clearLabel: 'Back to showing what is inside',
        onPicked: (file) => api.setPicture(key, file),
        onCleared: picture == null ? null : () => api.clearPicture(key),
      ),
    ]);
  }
}
