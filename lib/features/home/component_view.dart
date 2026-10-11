import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/component_kind.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/components/component_tile.dart';
import 'package:openlauncher/features/components/primitives.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/features/home/styled_box.dart';
import 'package:openlauncher/features/home/tile_actions.dart';

/// Puts something around every component a pane of cells holds. The TV
/// has none; the web editor uses it to make them things that are picked
/// up and moved instead of opened.
class TileFrame extends InheritedWidget {
  const TileFrame({super.key, required this.wrap, required super.child});

  final Widget Function(Component component, Widget tile) wrap;

  @override
  bool updateShouldNotify(TileFrame oldWidget) => wrap != oldWidget.wrap;
}

/// The look of the tile the components below are part of, for the one of
/// them that shows its focus.
class TileLook extends InheritedWidget {
  const TileLook({super.key, required this.box, required super.child});

  final BoxStyle box;

  static TileLook? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TileLook>();

  @override
  bool updateShouldNotify(TileLook oldWidget) => box != oldWidget.box;
}

/// What shows that the tile it is part of has the focus: the frame behind
/// a picture, or the whole of a tile none of whose parts does.
class FocusFrame extends StatelessWidget {
  const FocusFrame({super.key, required this.child, this.bare = false});

  final Widget child;

  /// True for no frame behind what is in it, only a faint wash to show
  /// the focus: line art, which sits straight on the wallpaper.
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final look = TileLook.of(context);
    final box = look?.box ?? BoxStyle.none;
    final focused = TileFocus.of(context) ?? false;
    final fill = styleFill(box);
    final outline = box.border;
    final shape = styleShape(box, 10);
    return AnimatedContainer(
      duration: FocusTile.duration,
      clipBehavior: Clip.antiAlias,
      // The border is drawn over the artwork so the tile does not change
      // size when focused.
      foregroundDecoration: BoxDecoration(
        borderRadius: shape,
        border: Border.all(
          color: focused
              ? Colors.white
              : outline == null
              ? Colors.transparent
              : Color(outline),
          width: outline == null ? 2 : box.borderWidth,
        ),
      ),
      decoration: BoxDecoration(
        gradient: fill.gradient,
        color: fill.gradient != null
            ? null
            : fill.color ??
                  (!bare
                      ? Theme.of(context).colorScheme.surfaceContainerHigh
                      : focused
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.transparent),
        borderRadius: shape,
        boxShadow: styleShadow(box),
      ),
      child: child,
    );
  }
}

/// Draws one component, whatever it is, and gives it its behaviour, which
/// is whatever its triggers say. An instance of a prefab is drawn as its
/// prefab's component with what it sets differently; a pane draws what is
/// in it the same way. Anything given something to do on a press or a
/// hold can be landed on.
class ComponentView extends ConsumerWidget {
  const ComponentView({
    super.key,
    required this.component,
    this.focus,
    this.popup,
    this.inLine = false,
    this.shrink = false,
  });

  final Component component;

  /// Gives the starting focus to the first thing on screen that takes it.
  final FirstFocus? focus;

  /// The id of the folder it is in, where that hovers over the screen:
  /// one that closes when something in it is opened.
  final String? popup;

  /// True for one that is part of a line, which its place is the line's
  /// to give.
  final bool inLine;

  /// True for one to take only the room it needs, where it can.
  final bool shrink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = _tile(context, ref);
    if (inLine) return tile;
    final frame = context.dependOnInheritedWidgetOfExactType<TileFrame>();
    return frame == null ? tile : frame.wrap(component, tile);
  }

  Widget _tile(BuildContext context, WidgetRef ref) {
    final c = resolved(component, ref.watch(prefabsProvider));
    if (c.isPane && !c.mode.inLine) {
      return PaneBox(
        pane: c,
        tile: (inner) =>
            ComponentView(component: inner, focus: focus, popup: popup),
      );
    }
    // In an entity's menu, what is pressed is done to that entity.
    final menuOf = ActionSubject.of(context);
    // Its variables as they stand: what it was handed by whatever it is
    // inside, and its own on top.
    final scope = scopeOf(ref.watch, c.id, c.vars, TemplateScope.of(context));
    // Its look as it stands: whatever of it is written as a template read
    // now.
    final look = readStyle(ref.watch, c.style, scope.own);
    final box = BoxStyle.of(look);
    // What it was handed, where that is one of the entities there are.
    final handed = c.handed.firstOrNull;
    final entity = handed == null
        ? null
        : ref.watch(entitiesProvider.select((all) => all.value?.byId(handed)));
    final does = TileActions(
      context,
      ref,
      component: c.id,
      c.on,
      scope: scope.own,
      subject: entity ?? menuOf,
      popup: popup,
      closes: popup != null && (entity != null || menuOf != null),
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
    final acts = does.has(Trigger.press) || hold != null;

    if (!c.isPane) {
      Widget content = TemplateScope(
        // A component reads all its own variables, its private ones too.
        values: scope.own,
        child: ComponentTile(item: c, shrink: shrink),
      );
      if (c.options['frame'] == true) {
        // Whether it has a frame behind it is its own to say, as a value.
        final bare = switch (c.options['bare']) {
          final String template => readTemplate(ref.watch, template, scope.own),
          final other => other,
        };
        content = FocusFrame(
          bare: bare == true || bare == 'true',
          child: content,
        );
      }
      final styled = StyledBox(style: box, child: content);
      if (!acts && c.kind != ComponentKind.button.name) return styled;
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
    }

    // Handed a folder that is set to open in place, it shows what the
    // folder holds where it is, for as long as `open` is set.
    if (ref.watch(layoutViewProvider).value?.panel(handed ?? '')
        case final folder?
        when folder.kind == PanelKind.popup &&
            folder.rule('position') == 'inline' &&
            ref.watch(
              runtimeVarsProvider.select(
                (all) => all[folder.id]?[openVar] == true,
              ),
            )) {
      return _InPlace(panel: folder);
    }
    // What it is made of, in a line, reading what it hands down.
    final line = TemplateScope(
      values: scope.inner,
      child: TileLook(
        box: box,
        child: LinePane(pane: c, inner: inLine, focus: focus, popup: popup),
      ),
    );
    // Only what does something is landed on; the rest is looked at, and
    // has no frame of its own to carry the look the user gave it.
    if (!acts) {
      return StyleScope.under(
        context,
        look,
        StyledBox(style: box, child: line),
      );
    }
    // The part marked `frame` is what shows the focus, or the whole of it
    // where no part is.
    final framed = c.all.any((part) => part.options['frame'] == true);
    return StyleScope.under(
      context,
      look,
      styleOpacity(
        box,
        FocusTile(
          autofocus: focus?.take() ?? false,
          onSelect: does.has(Trigger.press) ? press : () {},
          onMenu: hold,
          onFocus: onFocus,
          focusedScale: c.mode == PaneMode.row ? 1.04 : 1.08,
          builder: (context, focused) => TileFocus(
            focused: focused,
            child: framed
                ? line
                : TileLook(
                    box: box,
                    child: FocusFrame(
                      bare: true,
                      child: Padding(
                        padding: EdgeInsets.all(box.padding ?? 8),
                        child: line,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// A pane that puts what is in it in a line, side by side or one under the
/// other: each takes the share of the room its transform says, keeps the
/// shape it says, or takes only what it needs.
class LinePane extends StatelessWidget {
  const LinePane({
    super.key,
    required this.pane,
    this.inner = false,
    this.focus,
    this.popup,
  });

  final Component pane;

  /// True for a line that is itself part of a line.
  final bool inner;
  final FirstFocus? focus;
  final String? popup;

  Widget? _place(Component child) {
    if (child.hidden && !child.keep) return null;
    // Where everything takes only the room it needs, nothing is shared out.
    final sized = !pane.fit && (child.flex != null || child.aspect != null);
    Widget placed = ComponentView(
      key: ValueKey(child.id),
      component: child,
      focus: focus,
      popup: popup,
      inLine: true,
      shrink: !sized,
    );
    // Its room is kept either way, so hiding it does not change the size
    // of the rest.
    if (child.keep) {
      placed = Visibility.maintain(visible: !child.hidden, child: placed);
    }
    if (pane.fit) return placed;
    if (child.aspect case final aspect?) {
      placed = AspectRatio(aspectRatio: aspect, child: placed);
    }
    return child.flex == null
        ? placed
        : Expanded(flex: child.flex!.round(), child: placed);
  }

  @override
  Widget build(BuildContext context) {
    final row = pane.mode == PaneMode.row;
    final flex = Flex(
      direction: row ? Axis.horizontal : Axis.vertical,
      mainAxisSize: pane.fit || inner ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: inner
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      crossAxisAlignment: switch (pane.align) {
        'start' => CrossAxisAlignment.start,
        'end' => CrossAxisAlignment.end,
        'center' => CrossAxisAlignment.center,
        'stretch' => CrossAxisAlignment.stretch,
        // Stretching asks for all the room, which a fitted one has none of.
        _ when row || pane.fit => CrossAxisAlignment.center,
        _ => CrossAxisAlignment.stretch,
      },
      spacing: pane.gap,
      children: [for (final child in pane.shown) ?_place(child)],
    );
    // Made as big as the box allows, once and at the top.
    return pane.fit && !inner ? FittedBox(child: flex) : flex;
  }
}

/// What a folder holds, shown where the folder is. Back closes it.
class _InPlace extends ConsumerWidget {
  const _InPlace({required this.panel});

  final Panel panel;

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
          ref.read(runtimeVarsProvider.notifier).set(panel.id, openVar, false);
        }
        return KeyEventResult.handled;
      },
      child: Material(
        color: const Color(0xFA1A1C23),
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(panel.root.box.padding ?? 12),
          child: PaneGrid(
            pane: panel.root,
            tile: (inner) => ComponentView(component: inner, focus: focus),
          ),
        ),
      ),
    );
  }
}
