import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/core/widgets/widget_kind.dart';
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
  const EntryTile({super.key, required this.entry, this.focus, this.popup});

  final Entry entry;

  /// Gives the starting focus to the first entity on screen.
  final FirstFocus? focus;

  /// The id of the folder it is in, where that hovers over the screen:
  /// one that closes when something in it is opened.
  final String? popup;

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
        tile: (inner) => EntryTile(entry: inner, focus: focus, popup: popup),
      );
    }
    // In an entity's menu, what is pressed is done to that entity.
    final menuOf = ActionSubject.of(context);
    // An instance of a prefab: the prefab says what it is made of and
    // what it does, the instance only where it differs. One whose prefab
    // is gone is drawn as the launcher's first, a card.
    final instance = switch (entry.item) {
      final item when item.kind == ItemKind.prefab =>
        switch (ref.watch(
              prefabsProvider.select((prefabs) => prefabs[item.ref]),
            )) {
              null => null,
              final prefab => instanceOf(prefab, item),
            } ??
            instanceOf(builtInPrefabs.first, item),
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
    // Its look as it stands: its prefab's, its own over that, and whatever
    // of either is written as a template read now.
    final look = readStyle(ref.watch, {
      ...?instance?.prefab.style,
      ...entry.item.style,
    }, scope.own);
    final box = BoxStyle.of(look);
    final does = TileActions(
      context,
      ref,
      component: entry.item.id,
      instance?.triggers(entry.item) ?? entry.item.on,
      scope: scope.own,
      subject: entry is EntityEntry ? entry.entity : menuOf,
      popup: popup,
      closes: popup != null && (entry is EntityEntry || menuOf != null),
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
      case EntityEntry() || PrefabEntry():
        // Drawn from a folder that is set to open in place, it shows what
        // the folder holds where it is, for as long as `open` is set.
        final layout = ref.watch(layoutViewProvider).value;
        if (layout?.panels[entry.item.source] case final folder?
            when folder.panel.kind == PanelKind.popup &&
                folder.panel.position == PopupPosition.inline &&
                ref.watch(
                  runtimeVarsProvider.select(
                    (all) => all[folder.panel.id]?[openVar] == true,
                  ),
                )) {
          return _InPlace(view: folder);
        }
        final acts = does.has(Trigger.press) || hold != null;
        final tile = PrefabTile(
          instance: instance!,
          scope: scope.inner,
          // Only what does something is landed on; the rest is looked at.
          autofocus: acts && (focus?.take() ?? false),
          boxStyle: box,
          onSelect: does.has(Trigger.press) ? press : null,
          onMenu: hold,
          onFocus: onFocus,
        );
        // Its parts take after it. What is only looked at has no frame of
        // its own to carry the look the user gave it.
        return StyleScope.under(
          context,
          look,
          acts ? styleOpacity(box, tile) : StyledBox(style: box, child: tile),
        );
      case WidgetEntry(:final item):
        final styled = StyledBox(
          style: box,
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
          return styled;
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
            child: styled,
          ),
        );
      case PaneEntry():
        throw StateError('Drawn above');
    }
  }
}

/// What a folder holds, shown where the folder is. Back closes it.
class _InPlace extends ConsumerWidget {
  const _InPlace({required this.view});

  final PanelView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = FirstFocus();
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        final key = event.logicalKey;
        if (key != LogicalKeyboardKey.goBack &&
            key != LogicalKeyboardKey.escape &&
            key != LogicalKeyboardKey.browserBack) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent) {
          ref
              .read(runtimeVarsProvider.notifier)
              .set(view.panel.id, openVar, false);
        }
        return KeyEventResult.handled;
      },
      child: Material(
        color: const Color(0xFA1A1C23),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(view.root.pane.box.padding ?? 12),
          child: PaneGrid(
            view: view.root,
            tile: (entry) => EntryTile(entry: entry, focus: focus),
          ),
        ),
      ),
    );
  }
}
