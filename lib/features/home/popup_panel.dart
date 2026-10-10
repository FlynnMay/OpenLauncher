import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/entry_tile.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';

/// Opens the popup panel [panelId] over the current screen. Back closes it.
Future<void> showPanelPopup(BuildContext context, String panelId) =>
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 150),
      transitionBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (_, _, _) => _PanelPopup(panelId: panelId),
    );

class _PanelPopup extends ConsumerWidget {
  const _PanelPopup({required this.panelId});

  final String panelId;

  /// The share of the screen's width and height a popup may take.
  static (double, double) _extent(Panel panel) {
    final step = panel.size.index;
    return switch (panel.position) {
      PopupPosition.center => (const [0.45, 0.62, 0.86][step], 0.8),
      PopupPosition.bottom => (1, const [0.34, 0.5, 0.72][step]),
      PopupPosition.left ||
      PopupPosition.right => (const [0.26, 0.36, 0.5][step], 1),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched, so edits made on the web page show while the popup is open.
    final view = ref.watch(layoutViewProvider).value?.panels[panelId];
    if (view == null) return const SizedBox.shrink();
    final panel = view.panel;
    final screen = MediaQuery.sizeOf(context);
    final (width, height) = _extent(panel);
    final centred = panel.position == PopupPosition.center;
    final focus = FirstFocus();
    return TileTraversal(
      child: Align(
        alignment: switch (panel.position) {
          PopupPosition.center => Alignment.center,
          PopupPosition.bottom => Alignment.bottomCenter,
          PopupPosition.left => Alignment.centerLeft,
          PopupPosition.right => Alignment.centerRight,
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
                  if (panel.title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        panel.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  if (view.isEmpty)
                    const Text(
                      'Nothing here yet. Add cards from the web page.',
                      style: TextStyle(color: Colors.white60),
                    ),
                  // The popup's global pane fills it, inside its margins.
                  Padding(
                    padding: EdgeInsets.all(view.root.pane.padding ?? 0),
                    child: PaneGrid(
                      view: view.root,
                      tile: (entry) =>
                          EntryTile(entry: entry, focus: focus, inPopup: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
