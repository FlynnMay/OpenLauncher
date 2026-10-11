import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/entry_tile.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/features/home/sidebar.dart';
import 'package:openlauncher/features/home_button/home_button.dart';
import 'package:openlauncher/features/settings/settings_screen.dart';
import 'package:openlauncher/features/wallpaper/wallpaper_background.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // TV overscan-safe margins (5% of a 960x540dp screen).
  static const _padding = EdgeInsets.symmetric(horizontal: 48, vertical: 27);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(layoutViewProvider);
    return PopScope(
      // This is the home screen: Back has nowhere to go.
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: TileTraversal(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const WallpaperBackground(),
              ...layout.when(
                skipLoadingOnReload: true,
                loading: () => const [
                  Center(child: CircularProgressIndicator()),
                ],
                error: (error, _) => [
                  Center(
                    child: Padding(
                      padding: _padding,
                      child: Text('Could not load apps: $error'),
                    ),
                  ),
                ],
                data: (layout) {
                  final focus = FirstFocus();
                  return [
                    if (layout.home.isEmpty)
                      const Center(child: Text('Nothing here yet'))
                    else
                      // The global pane: the whole screen, edge to edge. It
                      // is the user's to arrange, margins included.
                      SingleChildScrollView(
                        padding: EdgeInsets.all(
                          layout.home.root.pane.padding ?? 0,
                        ),
                        child: PaneGrid(
                          view: layout.home.root,
                          tile: (entry) =>
                              EntryTile(entry: entry, focus: focus),
                        ),
                      ),
                    // Over the home screen, each from its own edge.
                    for (final bar in layout.bars) Sidebar(view: bar),
                    Positioned(
                      top: _padding.top,
                      right: _padding.right,
                      child: _Header(settingsPlaced: _hasSettings(layout)),
                    ),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether the Settings entity is somewhere the user can get to.
  static bool _hasSettings(LayoutView layout) => layout.panels.values.any(
    (view) => view.panel.items.any(
      (item) =>
          item.kind == ItemKind.prefab && item.source == Entity.settings.id,
    ),
  );
}

/// Buttons over the top right corner that are only there when needed.
class _Header extends ConsumerWidget {
  const _Header({required this.settingsPlaced});

  final bool settingsPlaced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        // Offered until Home opens this launcher.
        if (ref.watch(homeButtonEnabledProvider).value == false)
          _HeaderButton(
            icon: Icons.home_outlined,
            label: 'Set as Home',
            onPressed: () => SettingsScreen.show(context),
          ),
        // The way in to Settings is an entity like any other; this stands in
        // for it while it has been removed, so there is always a way in.
        if (!settingsPlaced)
          _HeaderButton(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onPressed: () => SettingsScreen.show(context),
          ),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(foregroundColor: Colors.white70),
    );
  }
}
