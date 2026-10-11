import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/card_tile.dart';
import 'package:openlauncher/core/widgets/widget_kind.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/features/home/styled_box.dart';
import 'package:openlauncher/features/home/tile_actions.dart';
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
/// triggers say (`triggersOf`): a card is only a button that came with a
/// press and a hold already set. A pane draws what is in it the same way.
class EntryTile extends ConsumerWidget {
  const EntryTile({
    super.key,
    required this.entry,
    this.focus,
    this.inPopup = false,
  });

  final Entry entry;

  /// Gives the starting focus to the first card on screen.
  final FirstFocus? focus;

  /// True inside a popup, which closes when one of its cards is opened.
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
    // In a card's menu, what is pressed is done to that card.
    final menuOf = ActionSubject.of(context);
    final does = TileActions(
      context,
      ref,
      triggersOf(entry.item),
      subject: entry is CardEntry ? entry.card : menuOf,
      inPopup: inPopup,
      closes: inPopup && (entry is CardEntry || menuOf != null),
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
      case CardEntry(:final card):
        return ArtTile(
          label: card.label,
          art: CardArt(
            card: card,
            padding: entry.item.look == TileLook.card ? 14 : 4,
          ),
          bare: CardArt.isBare(card),
          autofocus: focus?.take() ?? false,
          style: entry.item.look,
          showLabel: !entry.item.hideName,
          boxStyle: entry.item.style,
          onSelect: press,
          onMenu: hold,
          onFocus: onFocus,
        );
      case PanelEntry():
        return ArtTile(
          label: entry.label,
          art: FolderArt(entry: entry),
          bare: FolderArt.isBare(entry),
          autofocus: focus?.take() ?? false,
          style: entry.item.look,
          showLabel: !entry.item.hideName,
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
          child: WidgetTile(item: item),
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
