import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/core/widgets/widget_kind.dart';
import 'package:openlauncher/features/home/entity_art.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/features/home/prefab_tile.dart';
import 'package:openlauncher/features/home/styled_box.dart';
import 'package:openlauncher/features/home/tile_actions.dart';
import 'package:openlauncher/features/widgets/primitive_widgets.dart';
import 'package:openlauncher/features/widgets/widget_tile.dart';

/// Puts something around every tile drawn under it. The TV has none; the
/// web editor uses it to make tiles things that are picked up and moved
/// instead of opened.
class TileFrame extends InheritedWidget {
  const TileFrame({super.key, required this.wrap, required super.child});

  final Widget Function(Entry entry, Widget tile) wrap;

  @override
  bool updateShouldNotify(TileFrame oldWidget) => wrap != oldWidget.wrap;
}

/// Draws one layout entry and gives it its behaviour, which is whatever its
/// triggers say (`triggersOf`): an entity is only a button that came with a
/// press and a hold already set. A pane draws what is in it the same way.
class EntryTile extends ConsumerWidget {
  const EntryTile({
    super.key,
    required this.entry,
    this.focus,
    this.inPopup = false,
  });

  final Entry entry;

  /// Gives the starting focus to the first entity on screen.
  final FirstFocus? focus;

  /// True inside a popup, which closes when one of its entities is opened.
  final bool inPopup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = _tile(context, ref);
    final frame = context.dependOnInheritedWidgetOfExactType<TileFrame>();
    return frame == null ? tile : frame.wrap(entry, tile);
  }

  Widget _tile(BuildContext context, WidgetRef ref) {
    final entry = this.entry;
    if (entry case PaneEntry(:final view)) {
      return PaneBox(
        view: view,
        tile: (inner) =>
            EntryTile(entry: inner, focus: focus, inPopup: inPopup),
      );
    }
    // In an entity's menu, what is pressed is done to that entity.
    final menuOf = ActionSubject.of(context);
    // An entity, and an entity that opens a folder, is an instance of a prefab,
    // which says what it is made of and what it does; the instance says
    // only where it differs. One whose prefab is gone is drawn as the
    // launcher's own for its kind.
    final instance = switch (entry) {
      EntityEntry(:final item) || PanelEntry(:final item) => () {
        final own = ref.watch(
          prefabsProvider.select((prefabs) => prefabs[prefabIdOf(item)]),
        );
        final usual = builtInPrefabs.firstWhere(
          (prefab) =>
              prefab.id ==
              (item.kind == ItemKind.panel ? folderPrefabId : cardPrefabId),
        );
        return (own == null ? null : instanceOf(own, item)) ??
            instanceOf(usual, item);
      }(),
      _ => null,
    };
    // Its variables as they stand: what it was handed by whatever it is
    // inside, and its own (and its prefab's) on top.
    final scope = scopeOf(
      ref.watch,
      entry.item.id,
      variablesOf(entry.item, ref.watch(prefabsProvider)),
      TemplateScope.of(context),
    );
    final does = TileActions(
      context,
      ref,
      component: entry.item.id,
      instance?.triggers(entry.item) ?? triggersOf(entry.item),
      subject: entry is EntityEntry ? entry.entity : menuOf,
      inPopup: inPopup,
      closes: inPopup && (entry is EntityEntry || menuOf != null),
    );
    void press() => does.fire(Trigger.press);
    final hold = does.has(Trigger.hold)
        ? (bool held) {
            does.fire(Trigger.hold, held: held);
          }
        : null;
    final onFocus = does.has(Trigger.focus) || does.has(Trigger.blur)
        ? (bool focused) {
            does.fire(focused ? Trigger.focus : Trigger.blur);
          }
        : null;
    switch (entry) {
      case EntityEntry(:final entity):
        final acts = does.has(Trigger.press) || hold != null;
        final tile = PrefabTile(
          instance: instance!,
          scope: scope.inner,
          bare: EntityArt.isBare(entity),
          // Only what does something is landed on; the rest is looked at.
          autofocus: acts && (focus?.take() ?? false),
          boxStyle: entry.item.style,
          onSelect: does.has(Trigger.press) ? press : null,
          onMenu: hold,
          onFocus: onFocus,
        );
        // What is only looked at has no frame of its own to carry the
        // look the user gave it.
        return acts
            ? tile
            : StyledBox(
                style: entry.item.style,
                radius: 10,
                padding: const EdgeInsets.all(8),
                child: tile,
              );
      case PanelEntry(:final panel):
        return PrefabTile(
          instance: instance!,
          // What it opens is what it is drawn from, unless it says.
          scope: {'source': folderValues(panel), ...scope.inner},
          custom: {'folder': FolderArt(entry: entry)},
          bare: FolderArt.isBare(entry),
          autofocus: focus?.take() ?? false,
          boxStyle: entry.item.style,
          onSelect: press,
          onMenu: hold,
          onFocus: onFocus,
        );
      case WidgetEntry(:final item):
        final box = StyledBox(
          style: item.style,
          radius: 10,
          padding: const EdgeInsets.all(8),
          // A widget reads all its own variables, its private ones too.
          child: TemplateScope(
            values: scope.own,
            child: WidgetTile(item: item),
          ),
        );
        // Anything given something to do can be landed on and pressed.
        if (!does.has(Trigger.press) &&
            hold == null &&
            item.ref != WidgetKind.button.name) {
          return box;
        }
        return FocusTile(
          autofocus: focus?.take() ?? false,
          focusedScale: 1.03,
          onSelect: press,
          onMenu: hold,
          onFocus: onFocus,
          builder: (context, focused) => AnimatedContainer(
            duration: FocusTile.duration,
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: focused ? Colors.white : Colors.transparent,
                width: 2,
              ),
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: focused ? 0.12 : 0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: box,
          ),
        );
      case PaneEntry():
        throw StateError('Drawn above');
    }
  }
}
