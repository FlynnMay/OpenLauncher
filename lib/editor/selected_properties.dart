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

Style _styleOf(LayoutItem item) => item.pane?.style ?? item.style;

/// A pane's look is its own; anything else's is the item's.
LayoutItem _withStyle(LayoutItem item, Style style) => switch (item.pane) {
  null => item.copyWith(style: style),
  final pane => item.withPane(pane.copyWith(style: style)),
};

/// The settings of what is picked out on the screen. With several things
/// picked out, only what every one of them has is offered, and a change is
/// made to them all; what belongs to one thing alone, such as an entity's name
/// and picture, is offered for one thing alone.
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
    void each(LayoutItem Function(LayoutItem item) how) =>
        change((layout) => changeItems(layout, ids, (item, _) => how(item)));

    // What every one of the selected things is decides what is offered.
    final allPanes = items.every((item) => item.kind == ItemKind.pane);
    final folders = ref.watch(selectedPanelsProvider);
    final allFolders =
        items.every((item) => item.kind == ItemKind.prefab) &&
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
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // What it is called and its picture are an app's or an input's to
        // have changed; the clock has neither.
        if (single != null &&
            single.kind == ItemKind.prefab &&
            (entityKind(
                  entities
                          .where((entity) => entity.id == single.source)
                          .firstOrNull
                          ?.kind ??
                      '',
                )?.placed ??
                false))
          _EntityDetails(entityId: single.source ?? ''),
        if (single != null && allFolders)
          _FolderDetails(
            panel: folders.values.single,
            onRenamed: (title) =>
                eachFolder((panel) => withPanelRule(panel, 'title', title)),
          ),
        if (single != null && single.kind == ItemKind.component)
          ComponentSettings(
            item: single,
            onChanged: (options) =>
                each((item) => item.copyWith(options: options)),
          ),
        if (single != null && single.kind == ItemKind.prefab) ...[
          if (found.single.parent.rules.containsKey(prefabIdOf(single)))
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
            onChanged: (options) =>
                each((item) => item.copyWith(options: options)),
            onPrefab: single.kind == ItemKind.prefab
                ? (id) => each((item) => item.copyWith(ref: id))
                : null,
          ),
        ],
        if (single != null && single.kind != ItemKind.pane)
          VariablesSettings(
            variables: single.vars,
            note: single.kind == ItemKind.prefab
                ? 'Its own, set over those its prefab has, which are '
                      'under Prefabs.'
                : null,
            onChanged: (vars) => each((item) => item.copyWith(vars: vars)),
          ),
        if (single != null && single.kind != ItemKind.pane)
          TriggerSettings(
            set: single.on,
            // An entity's are its prefab's.
            usual: {
              if (single.kind == ItemKind.prefab)
                ...?ref.watch(prefabsProvider)[single.ref]?.on,
            },
            entities: {
              for (final entity
                  in ref.watch(entitiesProvider).value ?? const <Entity>[])
                entity.id: entity.label,
            },
            onChanged: (on) => each((item) => item.copyWith(on: on)),
          ),
        // What the panes they are in make of how big each is and where.
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
        // Only what every one of them takes.
        StyleSettings(
          keys: items
              .map((item) => item.styleKeys.toSet())
              .reduce((all, own) => all.intersection(own)),
          style: _styleOf(items.first),
          corner: allPanes ? Pane.defaultCorner : 10,
          onChanged: (key, value) => each(
            (item) => _withStyle(item, withStyle(_styleOf(item), {key: value})),
          ),
        ),
        if (allPanes)
          PaneSettings(
            title: 'Pane',
            prefabs: ref.watch(prefabsProvider),
            panes: [for (final item in items) item.pane!],
            onChanged: (how) => each((item) => item.withPane(how(item.pane!))),
            children: [
              if (single != null && found.single.panel.kind == PanelKind.home)
                TickBox(
                  label: 'New apps go here',
                  value: ref.watch(inboxProvider) == single.pane!.id,
                  onChanged: (here) {
                    if (here) {
                      change((layout) => withInbox(layout, single.pane!.id));
                    }
                  },
                ),
            ],
          ),
        if (allFolders)
          Section('Folder', [
            // Its rules as a pane that is shown and hidden.
            ...ruleFields(
              options: panelRules(folders.values.first),
              json: folders.values.first.toJson(),
              onChanged: (key, value) =>
                  eachFolder((panel) => withPanelRule(panel, key, value)),
            ),
            if (single != null)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => TvScreen.openPopup(single.source!),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Open it'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      if (await _sure(context) && context.mounted) {
                        ref.read(selectionProvider.notifier).clear();
                        change((layout) => removePanel(layout, single.source!));
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

  static Future<bool> _sure(BuildContext context) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete the folder?'),
          content: const Text(
            'What is in it comes off the TV with it. The apps can be added '
            'again anywhere.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}

/// What an entity is called and what it looks like, wherever it is placed.
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
    final entity = entities
        .where((entity) => entity.id == widget.entityId)
        .firstOrNull;
    if (entity == null) return const SizedBox.shrink();
    final details = ref.watch(tvStateProvider).value?.details[entity.id];
    final borrowed = switch (details?.iconFrom) {
      null => null,
      final from => entities.where((other) => other.id == from).firstOrNull,
    };
    return Section('Source', [
      CommitField(
        label: 'Name',
        value: entity.label,
        // Emptied, it goes back to the name the TV has for it.
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
                        // Those with a picture to lend: what is put on
                        // the screen as one.
                        if (other.id != entity.id &&
                            (entityKind(other.kind)?.placed ?? false))
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

/// What a folder is called and the picture on the entity that opens it.
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
