import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/component_registry.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layers/layers.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/components/component_tile.dart';
import 'package:openlauncher/features/components/primitives.dart';
import 'package:openlauncher/features/home/dock_host.dart';
import 'package:openlauncher/features/home/docked_pane.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/features/home/styled_box.dart';
import 'package:openlauncher/features/home/tile_actions.dart';

/// Wraps every component in a cell pane. Unused on the TV; the editor uses it
/// to make them draggable.
class TileFrame extends InheritedWidget {
  const TileFrame({super.key, required this.wrap, required super.child});

  final Widget Function(Component component, Widget tile) wrap;

  @override
  bool updateShouldNotify(TileFrame oldWidget) => wrap != oldWidget.wrap;
}

/// The box style of the tile the widgets below belong to, for its focus
/// frame.
class TileLook extends InheritedWidget {
  const TileLook({super.key, required this.box, required super.child});

  final BoxStyle box;

  static TileLook? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TileLook>();

  @override
  bool updateShouldNotify(TileLook oldWidget) => box != oldWidget.box;
}

/// Shows the tile's focus: the frame behind a picture, or around a whole
/// tile.
class FocusFrame extends StatelessWidget {
  const FocusFrame({super.key, required this.child, this.bare = false});

  final Widget child;

  /// No background, only a faint wash when focused (for line art).
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
      // The border is drawn over the content so focus does not resize the
      // tile.
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

/// Draws any component and wires up its triggers. An instance is resolved
/// against its prefab first. Anything with a press or hold action is
/// focusable.
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

  /// Gives the initial focus to the first focusable component.
  final FirstFocus? focus;

  /// The hovering folder it is in, which closes when something in it is
  /// opened.
  final String? popup;

  /// It is a child of a row or column pane.
  final bool inLine;

  /// Take its natural size where it can.
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
    final scope = scopeOf(ref.watch, c.id, c.vars, TemplateScope.of(context));
    final look = readStyle(ref.watch, c.style, scope.own);
    final box = BoxStyle.of(look);
    // The entity it was handed, if any.
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
      popup: popup,
      // An entity's tile, or a button of an entity's menu.
      closes:
          popup != null && (entity != null || subjectOf(ref, popup!) != null),
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
        // A component reads its own private variables too.
        values: scope.own,
        child: ComponentTile(item: c, shrink: shrink),
      );
      if (c.options['frame'] == true) {
        // `bare` may be a template.
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
      if (!acts && c.kind != ComponentRegistry.button.name) return styled;
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

    // A folder docked in place is drawn here while `open` is set, unless
    // its own chain moved it to a layer.
    if (ref.watch(layoutViewProvider).value?.pane(handed ?? '')
        case final folder?
        when folder.dock == Component.inline &&
            layerOf(ref.watch(layersProvider), folder.id) == null &&
            ref.watch(
              runtimeVarsProvider.select(
                (all) => all[folder.id]?[openVar] == true,
              ),
            )) {
      return DockedPane(pane: folder, inPlace: true);
    }
    final line = TemplateScope(
      values: scope.inner,
      child: TileLook(
        box: box,
        child: LinePane(pane: c, inner: inLine, focus: focus, popup: popup),
      ),
    );
    // Without actions it is not focusable.
    if (!acts) {
      return StyleScope.under(
        context,
        look,
        StyledBox(style: box, child: line),
      );
    }
    // A child with `frame` shows the focus; otherwise the whole tile does.
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

/// Draws a row or column pane: children sized by flex, aspect or their
/// natural size.
class LinePane extends StatelessWidget {
  const LinePane({
    super.key,
    required this.pane,
    this.inner = false,
    this.focus,
    this.popup,
  });

  final Component pane;

  /// Nested in another row or column.
  final bool inner;
  final FirstFocus? focus;
  final String? popup;

  Widget? _place(Component child) {
    if (child.isDocked || child.hidden && !child.keep) return null;
    // Nothing is shared out when the pane is fitted.
    final sized = !pane.fit && (child.flex != null || child.aspect != null);
    Widget placed = ComponentView(
      key: ValueKey(child.id),
      component: child,
      focus: focus,
      popup: popup,
      inLine: true,
      shrink: !sized,
    );
    // Keeps its space while hidden.
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
        // A fitted row cannot stretch.
        _ when row || pane.fit => CrossAxisAlignment.center,
        _ => CrossAxisAlignment.stretch,
      },
      spacing: pane.gap,
      children: [for (final child in pane.shown) ?_place(child)],
    );
    // Scaled to the box once, at the top level.
    return pane.fit && !inner ? FittedBox(child: flex) : flex;
  }
}
