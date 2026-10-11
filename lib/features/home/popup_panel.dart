import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/component_view.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/features/home/tile_actions.dart';

/// A hovering folder. With a [subject] it is that entity's menu: titled after
/// it, with inapplicable buttons left out.
class PanelPopup extends ConsumerWidget {
  const PanelPopup({super.key, required this.panelId, this.subject});

  final String panelId;
  final Entity? subject;

  /// Fraction of the screen a popup may take.
  static (double, double) _extent(Panel panel) {
    final step = switch (panel.rule('size')) {
      'small' => 0,
      'large' => 2,
      _ => 1,
    };
    return switch (panel.rule('position')) {
      'bottom' => (1, const [0.34, 0.5, 0.72][step]),
      'left' || 'right' => (const [0.26, 0.36, 0.5][step], 1),
      // Centred (also the fallback for `inline`).
      _ => (const [0.45, 0.62, 0.86][step], 0.8),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched, so edits made on the web page show while the popup is open.
    final panel = ref.watch(layoutViewProvider).value?.panel(panelId);
    if (panel == null) return const SizedBox.shrink();
    final subject = this.subject;
    final root = subject == null
        ? panel.root
        : panel.root.copyWith(
            children: offeredFor(
              panel.root,
              subject,
              ref.watch(actionRunnerProvider),
            ),
          );
    final title = switch (panel.title) {
      '' =>
        subject?.label ?? (panel.id == Layout.menuId ? 'Quick actions' : ''),
      final title => title,
    };
    final screen = MediaQuery.sizeOf(context);
    final (width, height) = _extent(panel);
    final position = panel.rule('position');
    final centred = !const {'bottom', 'left', 'right'}.contains(position);
    final focus = FirstFocus();
    final popup = TileTraversal(
      child: Align(
        alignment: switch (position) {
          'bottom' => Alignment.bottomCenter,
          'left' => Alignment.centerLeft,
          'right' => Alignment.centerRight,
          _ => Alignment.center,
        },
        child: Material(
          color: const Color(0xFA1A1C23),
          borderRadius: centred ? BorderRadius.circular(18) : null,
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: screen.width * width,
              maxWidth: screen.width * width,
              // Only a centred popup shrinks to fit what is in it.
              minHeight: centred ? 0 : screen.height * height,
              maxHeight: screen.height * height,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  if (root.isEmpty)
                    const Text(
                      'Nothing here yet. Add things from the web page.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  Padding(
                    padding: EdgeInsets.all(panel.root.box.padding ?? 0),
                    child: PaneGrid(
                      pane: root,
                      owner: panelId,
                      tile: (entry) => ComponentView(
                        component: entry,
                        focus: focus,
                        popup: panelId,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final held = _Held(child: popup);
    return subject == null ? held : ActionSubject(entity: subject, child: held);
  }
}

/// Traps the focus and takes it on appearing.
class _Held extends StatefulWidget {
  const _Held({required this.child});

  final Widget child;

  @override
  State<_Held> createState() => _HeldState();
}

class _HeldState extends State<_Held> {
  final _scope = FocusScopeNode(debugLabel: 'folder');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_scope.hasFocus) _scope.requestFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FocusScope(node: _scope, autofocus: true, child: widget.child);
}
