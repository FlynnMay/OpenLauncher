import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/controls/dialogs.dart';
import 'package:openlauncher/editor/editing/layout_edit.dart';
import 'package:openlauncher/editor/editing/prefab_edit.dart';
import 'package:openlauncher/editor/editing/prefab_mode.dart';
import 'package:openlauncher/editor/editing/selection.dart';

/// Marks a prefab or an instance of one wherever it is shown.
const prefabIcon = Icons.view_in_ar_outlined;

/// The name of the pack whose id [id] starts with: `system:home` is
/// System's.
final packNameProvider = Provider.family<String, String>((ref, id) {
  final pack = id.substring(0, max(0, id.indexOf(':')));
  return ref
          .watch(packsProvider)
          .value
          ?.where((one) => one.id == pack)
          .firstOrNull
          ?.name ??
      pack;
});

/// The name of the pack that ships prefab [id], if one does; the user's of
/// that id is it, edited.
final shippedByProvider = Provider.family<String?, String>(
  (ref, id) => ref.watch(shippedPrefabsProvider).containsKey(id)
      ? ref.watch(packNameProvider(id))
      : null,
);

const _shared =
    'Variants share the prefab\'s structure, variables and actions. Switch '
    'to the default variant to change them.';

Future<void> _put(WidgetRef ref, Prefab prefab) => ref
    .read(configProvider.notifier)
    .change((c) => c.copyWith(prefabs: withPrefab(c.prefabs, prefab)));

void _say(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

/// The entity-typed variables of [prefab]'s root that have no value, which
/// a preview fills in.
Iterable<String> previewed(Prefab prefab) => [
  for (final MapEntry(key: name, value: variable) in prefab.root.vars.entries)
    if (variable.type == VarType.entity &&
        !variable.isConditional &&
        (variable.value == null || variable.value == ''))
      name,
];

final _handedDown = RegExp(r'^\{\{(\w+)\.id\}\}$');

/// Lets go of the open prefab's selection and previews.
void _leave(WidgetRef ref) {
  ref.read(selectionProvider.notifier).clear();
  if (ref.read(editedPrefabProvider) case final prefab?) {
    ref.read(runtimeVarsProvider.notifier).clear(prefab.root.id);
  }
}

/// Draws the prefab now open with its previews.
void _enter(WidgetRef ref) {
  final prefab = ref.read(editedPrefabProvider);
  final mode = ref.read(prefabModeProvider);
  if (prefab == null || mode == null) return;
  final runtime = ref.read(runtimeVarsProvider.notifier);
  for (final MapEntry(key: name, value: id) in mode.previews.entries) {
    runtime.set(prefab.root.id, name, id);
  }
}

/// Opens [prefabId] for editing in place of the layout, with something to
/// draw for each variable that has no value: what the instance [from] holds,
/// else the first thing that uses the prefab. Opened from an instance inside
/// the open prefab, it is added to the trail.
void openPrefab(WidgetRef ref, String prefabId, {Node? from}) {
  final prefab = ref.read(prefabsProvider)[prefabId];
  if (prefab == null) return;
  final trail = ref.read(prefabTrailProvider);
  final nested = from != null && trail.isNotEmpty;
  // One already on the trail is gone back to.
  final at = trail.indexWhere((mode) => mode.id == prefabId);
  if (nested && at >= 0) return backPrefab(ref, at + 1);
  final entities = ref.read(entitiesProvider).value ?? const <Entity>[];
  final placed = ref.read(configProvider).value?.layout.all ?? const [];
  final prefabs = ref.read(prefabsProvider);
  // A card that opens instances of a prefab is shown with one of them.
  final opensOthers = prefabs.values.any((opened) => opened.card == prefabId);
  final sample =
      entities.where((entity) => entity.prefab == prefabId).firstOrNull?.id ??
      (opensOthers
          ? placed
                .where(
                  (node) =>
                      node.isInstance && prefabs[node.prefab]?.card == prefabId,
                )
                .firstOrNull
                ?.id
          : entities.where((entity) => entity.placed).firstOrNull?.id);
  // What [from] was handed, read through the prefab around it.
  String? held(String name) => switch (from?.vars[name]?.value) {
    final String value when !value.contains('{{') && value.isNotEmpty => value,
    final String value => switch (_handedDown.firstMatch(value)?.group(1)) {
      null => null,
      final outer =>
        trail.lastOrNull?.previews[outer] ??
            switch (ref.read(editedPrefabProvider)?.root.vars[outer]?.value) {
              final String id when id.isNotEmpty => id,
              _ => null,
            },
    },
    _ => null,
  };
  final previews = {
    for (final name in previewed(prefab)) name: ?(held(name) ?? sample),
  };
  _leave(ref);
  ref
      .read(prefabTrailProvider.notifier)
      .open(prefabId, previews: previews, via: from?.id, nested: nested);
  _enter(ref);
}

/// Goes back along the trail until [keep] prefabs are open, the instance the
/// next was opened from selected; with 0, to the layout.
void backPrefab(WidgetRef ref, int keep) {
  final trail = ref.read(prefabTrailProvider);
  if (keep < 0 || keep >= trail.length) return;
  final via = trail[keep].via;
  _leave(ref);
  ref.read(prefabTrailProvider.notifier).backTo(keep);
  _enter(ref);
  if (via != null) ref.read(selectionProvider.notifier).tap(via, adding: false);
}

/// Back to editing the layout.
void closePrefab(WidgetRef ref) => backPrefab(ref, 0);

/// What a variable of the open prefab with no value is drawn with.
void previewWith(WidgetRef ref, String name, String id) {
  final prefab = ref.read(editedPrefabProvider);
  if (prefab == null) return;
  ref.read(prefabTrailProvider.notifier).preview(name, id);
  ref.read(runtimeVarsProvider.notifier).set(prefab.root.id, name, id);
}

/// Saves the open [prefab] as [edited] has it. Returns why it could not be
/// kept, or null.
Future<String?> saveEdited(WidgetRef ref, Prefab prefab, Layout edited) async {
  final root = prefabRootIn(edited, prefab.root.id);
  if (root == null) return 'A prefab keeps its root.';
  final next = withEdited(prefab, ref.read(prefabModeProvider)?.variant, root);
  if (next == null) return _shared;
  final left = {for (final part in next.root.all) part.id};
  final gone = {
    for (final part in prefab.root.all)
      if (!left.contains(part.id)) part.id: null,
  };
  await ref.read(configProvider.notifier).change((c) {
    final own = withPrefab(c.prefabs, next);
    if (gone.isEmpty) return c.copyWith(prefabs: own);
    // What named a removed child goes with it.
    final fixed = withPartIds(c.layout, own, next.id, gone);
    return c.copyWith(layout: fixed.layout, prefabs: fixed.prefabs);
  });
  return null;
}

/// Asks for a name, makes an empty prefab and opens it.
Future<void> newPrefab(BuildContext context, WidgetRef ref) async {
  final name = await askName(context, 'Prefab', title: 'Prefab name');
  if (name == null || name.isEmpty) return;
  final id = freeId(slugOf(name, 'prefab'), {
    ...ref.read(prefabsProvider).keys,
  });
  await _put(
    ref,
    Prefab(
      id: id,
      name: name,
      root: Node.layout(id: 'root', mode: LayoutMode.column),
    ),
  );
  openPrefab(ref, id);
}

Future<void> duplicatePrefab(
  BuildContext context,
  WidgetRef ref,
  Prefab prefab,
) async {
  final name = await askName(
    context,
    '${prefab.name} copy',
    title: 'Prefab name',
  );
  if (name == null || name.isEmpty) return;
  await _put(
    ref,
    prefab.copyWith(
      id: freeId(slugOf(name, 'prefab'), {...ref.read(prefabsProvider).keys}),
      name: name,
    ),
  );
}

Future<void> renamePrefab(
  BuildContext context,
  WidgetRef ref,
  Prefab prefab,
) async {
  final name = await askName(
    context,
    prefab.name,
    title: 'Prefab name',
    does: 'Rename',
  );
  if (name == null || name.isEmpty) return;
  await _put(ref, prefab.copyWith(name: name));
}

/// Deletes [prefab] once confirmed, unpacking its instances where they
/// stand; an edited one a pack ships goes back to the pack's.
Future<void> deletePrefab(
  BuildContext context,
  WidgetRef ref,
  Prefab prefab,
) async {
  final config = ref.read(configProvider).value;
  if (config == null) return;
  final controller = ref.read(configProvider.notifier);
  if (ref.read(shippedByProvider(prefab.id)) case final pack?) {
    if (!await confirm(
      context,
      'Revert "${prefab.name}" to $pack?',
      'Your changes to it are lost. Its instances follow $pack\'s again.',
      'Revert',
    )) {
      return;
    }
    ref.read(selectionProvider.notifier).clear();
    await controller.change(
      (c) => c.copyWith(
        prefabs: [
          for (final one in c.prefabs)
            if (one.id != prefab.id) one,
        ],
      ),
    );
    return;
  }
  final prefabs = ref.read(prefabsProvider);
  final after = withoutPrefab(
    config.layout,
    config.prefabs,
    prefabs,
    prefab.id,
  );
  String count(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';
  if (!context.mounted ||
      !await confirm(
        context,
        'Delete "${prefab.name}"?',
        after.instances == 0
            ? 'Nothing uses it.'
            : '${count(after.instances, 'instance')} will be unpacked into '
                  'plain components, keeping the values they had.'
                  '${after.blank == 0 ? '' : ' ${after.blank} could not be '
                            'filled in and will have a blank variable.'}',
        'Delete',
      )) {
    return;
  }
  // Back to what it was opened from, where its instance is unpacked.
  if (ref.read(prefabModeProvider)?.id == prefab.id) {
    backPrefab(ref, ref.read(prefabTrailProvider).length - 1);
  }
  await controller.change((c) {
    final after = withoutPrefab(c.layout, c.prefabs, prefabs, prefab.id);
    return c.copyWith(
      layout: after.layout.normalised(),
      prefabs: after.prefabs,
    );
  });
}

/// Makes a prefab of the component [found], which an instance replaces.
Future<void> createPrefab(
  BuildContext context,
  WidgetRef ref,
  Found found,
) async {
  final name = await askName(context, 'Prefab', title: 'Prefab name');
  if (name == null || name.isEmpty) return;
  final made = asPrefab(
    found.item,
    freeId(slugOf(name, 'prefab'), {...ref.read(prefabsProvider).keys}),
    name,
    // Placed by its transform: its size on the TV's screen.
    size: found.parent.mode == LayoutMode.free
        ? found.item.transform.rectIn(const Size(960, 540)).size
        : null,
  );
  await ref.read(configProvider.notifier).change((c) {
    final layout = changeItems(c.layout, {
      found.item.id,
    }, (_, _) => made.instance);
    return c.copyWith(
      prefabs: [...c.prefabs, made.prefab],
      // What it holds is no longer on the screen in its own right, and is not
      // put back.
      layout: layout
          .copyWith(
            removed: {
              ...layout.removed,
              for (final part in found.item.all)
                if (part.isInstance)
                  for (final id in part.handed)
                    if (layout.container(id) == null) id,
            },
          )
          .normalised(),
    );
  });
}

/// Renames child [part] of the open prefab, and what names it.
Future<void> renamePart(BuildContext context, WidgetRef ref, Node part) async {
  final prefab = ref.read(editedPrefabProvider);
  if (prefab == null) return;
  if (!prefab.isBase(ref.read(prefabModeProvider)?.variant)) {
    return _say(context, _shared);
  }
  final name = await askName(context, part.id, title: 'ID', does: 'Rename');
  final to = slugOf(name ?? '', '');
  if (to.isEmpty || to == part.id || !context.mounted) return;
  if (prefab.root.all.any((other) => other.id == to)) {
    return _say(context, 'Another part of the prefab is called "$to".');
  }
  await ref.read(configProvider.notifier).change((c) {
    final fixed = withPartRenamed(
      c.layout,
      withPrefab(c.prefabs, prefab),
      prefab,
      part.id,
      to,
    );
    return c.copyWith(layout: fixed.layout, prefabs: fixed.prefabs);
  });
  final selection = ref.read(selectionProvider.notifier);
  if (ref.read(selectionProvider).contains(part.id)) {
    selection.tap(to, adding: false);
  }
}

/// Adds a variant to the open prefab and shows it.
Future<void> addVariant(BuildContext context, WidgetRef ref) async {
  final prefab = ref.read(editedPrefabProvider);
  if (prefab == null) return;
  final name = await askName(context, 'Variant', title: 'Variant name');
  if (name == null || name.isEmpty) return;
  final key = freeId(slugOf(name, 'variant'), {...prefab.variants.keys});
  await _put(
    ref,
    prefab.copyWith(
      variants: {
        // The tree as built is the first.
        if (prefab.variants.isEmpty) 'default': const PrefabVariant('Default'),
        ...prefab.variants,
        key: PrefabVariant(name),
      },
    ),
  );
  ref.read(prefabTrailProvider.notifier).show(key);
}

Future<void> renameVariant(
  BuildContext context,
  WidgetRef ref,
  String key,
) async {
  final prefab = ref.read(editedPrefabProvider);
  final variant = prefab?.variants[key];
  if (prefab == null || variant == null) return;
  final name = await askName(
    context,
    variant.label.isEmpty ? key : variant.label,
    title: 'Variant name',
    does: 'Rename',
  );
  if (name == null || name.isEmpty) return;
  await _put(
    ref,
    prefab.copyWith(
      variants: {
        ...prefab.variants,
        key: PrefabVariant(name, variant.overrides),
      },
    ),
  );
}

/// Makes variant [key] the tree itself; the others are kept as they look,
/// as overrides on it.
Future<void> makeDefaultVariant(WidgetRef ref, String key) async {
  final prefab = ref.read(editedPrefabProvider);
  if (prefab == null || !prefab.variants.containsKey(key)) return;
  final root = prefab.rootAs(key);
  await _put(
    ref,
    prefab.copyWith(
      root: root,
      variants: {
        key: PrefabVariant(prefab.variants[key]!.label),
        for (final MapEntry(key: other, value: variant)
            in prefab.variants.entries)
          if (other != key)
            other: PrefabVariant(
              variant.label,
              overridesBetween(root, prefab.rootAs(other)) ?? const {},
            ),
      },
    ),
  );
}

Future<void> deleteVariant(WidgetRef ref, String key) async {
  final prefab = ref.read(editedPrefabProvider);
  if (prefab == null || key == prefab.defaultVariant) return;
  ref.read(prefabTrailProvider.notifier).show(null);
  await _put(ref, prefab.copyWith(variants: {...prefab.variants}..remove(key)));
}

/// Hands one value of child [part] back to the tree in the shown variant;
/// with no [key], all of them.
Future<void> revertOverride(
  WidgetRef ref,
  String part, [
  String? section,
  String? key,
]) async {
  final prefab = ref.read(editedPrefabProvider);
  final name = prefab?.variantNamed(ref.read(prefabModeProvider)?.variant);
  final variant = prefab?.variants[name];
  if (prefab == null || variant == null) return;
  await _put(
    ref,
    prefab.copyWith(
      variants: {
        ...prefab.variants,
        name!: PrefabVariant(
          variant.label,
          key == null
              ? ({...variant.overrides}..remove(part))
              : withOverride(variant.overrides, part, {key: null}, section),
        ),
      },
    ),
  );
}
