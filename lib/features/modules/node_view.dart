import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/modules/focus_drawer.dart';
import 'package:openlauncher/features/modules/layout_drawer.dart';
import 'package:openlauncher/features/modules/line_layout.dart';
import 'package:openlauncher/features/modules/scroll_drawer.dart';
import 'package:openlauncher/features/modules/style_drawer.dart';
import 'package:openlauncher/features/modules/triggers_drawer.dart';
import 'package:openlauncher/features/modules/variables_drawer.dart';
import 'package:openlauncher/features/modules/visual_drawers.dart';

/// Wraps every node drawn. Unused on the TV; the editor uses it to make
/// them selectable and draggable.
class TileFrame extends InheritedWidget {
  const TileFrame({
    super.key,
    required this.wrap,
    this.still = false,
    required super.child,
  });

  final Widget Function(Node node, Widget tile) wrap;

  /// Tiles do nothing when pressed.
  final bool still;

  @override
  bool updateShouldNotify(TileFrame oldWidget) =>
      wrap != oldWidget.wrap || still != oldWidget.still;
}

/// Draws any node by composing its modules, in this order: the instance
/// resolved against its prefab, its Variables in scope, what its visual
/// module draws with its children over it (placed by its Layout, or by their
/// transforms without one), its Style's padding, its Scroll, its Style's
/// box, and its Focus wired to its Triggers. Dock is drawn by the layers. An
/// instance's parts read its id and name as `instance`.
class NodeView extends ConsumerWidget {
  const NodeView({
    super.key,
    required this.component,
    this.focus,
    this.popup,
    this.inLine = false,
    this.shrink = false,
    this.screen = false,
    this.tall = false,
    this.placeholder,
    this.wrap,
  });

  final Node component;

  /// Gives the initial focus to the first focusable node.
  final FirstFocus? focus;

  /// The docked pane it is in, if a press closes it.
  final String? popup;

  /// It is a child of a row or column.
  final bool inLine;

  /// Take its natural size where it can.
  final bool shrink;

  /// It is a whole screen of tiles, a docked pane: it is not framed by the
  /// editor, and it centres the focused tile as it scrolls.
  final bool screen;

  /// As tall as what is in it, where it has the room to be.
  final bool tall;

  /// Shown while there is nothing in it.
  final String? placeholder;

  /// Wraps what each of its children draws.
  final Widget Function(Node child, Widget drawn)? wrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frame = screen
        ? null
        : context.dependOnInheritedWidgetOfExactType<TileFrame>();
    final drawn = _drawn(context, ref, still: frame?.still ?? false);
    return frame == null ? drawn : frame.wrap(component, drawn);
  }

  Widget _child(Node child, {bool inLine = false, bool shrink = false}) {
    final drawn = NodeView(
      component: child,
      focus: focus,
      popup: popup,
      inLine: inLine,
      shrink: shrink,
    );
    return wrap?.call(child, drawn) ?? drawn;
  }

  Widget _drawn(BuildContext context, WidgetRef ref, {required bool still}) {
    final node = resolved(component, ref.watch(prefabsProvider));
    // An instance's parts can read it as `instance`.
    final scope = scopeOf(ref.watch, node.id, node.vars, {
      ...TemplateScope.of(context),
      if (component.isInstance) 'instance': {'id': node.id, 'name': node.name},
    });
    final look = readStyle(ref.watch, node.style, scope.own);
    final box = BoxStyle.of(look);

    // What its visual draws, reading its own private variables too.
    final visual = switch (drawVisual(node, shrink: shrink)) {
      final drawn? => TemplateScope(values: scope.own, child: drawn),
      null => null,
    };
    // Its children, reading what it shares with them.
    final children = visual != null && node.children.isEmpty
        ? null
        : TemplateScope(
            values: scope.inner,
            child: node.mode.inLine
                ? LineLayout(
                    pane: node,
                    inner: inLine,
                    hug: tall,
                    tile: (child, {required shrink}) =>
                        _child(child, inLine: true, shrink: shrink),
                  )
                : ChildrenLayout(pane: node, tile: _child),
          );
    Widget content = switch ((visual, children)) {
      (final visual?, final children?) => Stack(
        fit: StackFit.expand,
        children: [visual, children],
      ),
      _ => visual ?? children!,
    };

    if (placeholder != null && node.isEmpty) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(placeholder!, style: const TextStyle(color: Colors.white60)),
          content,
        ],
      );
    }
    // A target part paints the box of a node whose focus it shows.
    final targeted = node.focusable && node.focusTarget != null;
    final padding = targeted ? 0.0 : paddingOf(box);
    if (padding > 0) {
      content = Padding(padding: EdgeInsets.all(padding), child: content);
    }
    content = scrolled(
      node,
      readStyle(ref.watch, node.scroll, scope.own),
      content,
      screen: screen,
    );

    // The part a focusable node above names shows that node's focus.
    if (FocusTarget.of(context) case final target?
        when target.ids.contains(node.id)) {
      content = FocusFrame(box: target.box, bare: target.bare, child: content);
    }
    if (node.focusable) {
      final bare = switch (node.focusBare) {
        final String template => readTemplate(ref.watch, template, scope.own),
        final other => other,
      };
      content = FocusView(
        node: node,
        box: box,
        bare: bare == true || bare == 'true',
        autofocus: focus?.take() ?? false,
        still: still,
        calls: TileActions(
          context,
          ref,
          node.on,
          component: node.id,
          scope: scope.own,
          popup: popup,
        ).remote,
        child: content,
      );
    } else {
      content = NodeBox(box: box, child: content);
    }
    return StyleScope.under(context, look, styleOpacity(box, content));
  }
}
