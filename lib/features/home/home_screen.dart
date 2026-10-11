import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layers/layers.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/entry_tile.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/pane_grid.dart';
import 'package:openlauncher/features/home/popup_host.dart';
import 'package:openlauncher/features/home/popup_panel.dart';
import 'package:openlauncher/features/home/sidebar.dart';
import 'package:openlauncher/features/home_button/home_button.dart';
import 'package:openlauncher/features/settings/settings_screen.dart';
import 'package:openlauncher/features/wallpaper/wallpaper_background.dart';

/// Where the focus is on the home screen itself, kept while a layer above
/// has it, so that it can be given back.
final _homeFocusProvider = Provider((ref) {
  final node = FocusScopeNode(debugLabel: 'home');
  ref.onDispose(node.dispose);
  return node;
});

/// What each sidebar is known by across the layers it moves between.
final _sidebarKeysProvider = Provider((ref) => <String, GlobalKey>{});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // TV overscan-safe margins (5% of a 960x540dp screen).
  static const _padding = EdgeInsets.symmetric(horizontal: 48, vertical: 27);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(layoutViewProvider);
    final layers = ref.watch(layersProvider);
    final keys = ref.watch(_sidebarKeysProvider);
    // Hides everything on [layer], which is what takes it away.
    void shut(ScreenLayer layer) {
      for (final id in layer.holds) {
        ref.read(runtimeVarsProvider.notifier).set(id, openVar, false);
      }
    }

    // With the last layer that kept the focus gone, it goes back to where
    // it was on the home screen.
    final home = ref.watch(_homeFocusProvider);
    ref.listen(layersProvider, (before, now) {
      bool keeps(List<ScreenLayer>? layers) =>
          layers?.any((layer) => layer.modal) ?? false;
      if (keeps(before) && !keeps(now)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (home.context != null) home.requestFocus();
        });
      }
    });
    // The same sidebar wherever it is drawn, so that moving between layers
    // keeps how far open it is and where the focus is in it.
    Widget sidebar(PanelView view) => KeyedSubtree(
      key: keys.putIfAbsent(view.panel.id, GlobalKey.new),
      child: Sidebar(
        view: view,
        onOpen: (open) => ref
            .read(runtimeVarsProvider.notifier)
            .set(view.panel.id, openVar, open),
      ),
    );
    return PopScope(
      // This is the home screen: Back has nowhere to go, but for taking
      // away the top layer that keeps the focus, a folder's.
      canPop: false,
      onPopInvokedWithResult: (_, _) {
        if (layers.where((layer) => layer.modal).lastOrNull case final top?) {
          shut(top);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // Folders show over all of it while their `open` is set.
        body: PopupHost(
          child: TileTraversal(
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
                    // What one layer does to all below it, and what is on
                    // it.
                    List<Widget> shown(ScreenLayer layer) => [
                      if (layer.blur > 0 || layer.dim > 0)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ClipRect(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: layer.blur,
                                  sigmaY: layer.blur,
                                ),
                                child: ColoredBox(
                                  color: Colors.black.withValues(
                                    alpha: layer.dim,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Where it keeps the focus, a press beside what is on
                      // it takes it away, as Back does.
                      if (layer.modal)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => shut(layer),
                          ),
                        ),
                      for (final bar in layout.bars)
                        if (layer.holds.contains(bar.panel.id)) sidebar(bar),
                      for (final id in layer.holds)
                        if (layout.panels[id]?.panel.kind == PanelKind.popup)
                          Positioned.fill(
                            key: ValueKey('folder $id'),
                            child: PanelPopup(
                              panelId: id,
                              subject: subjectOf(ref, id),
                            ),
                          ),
                    ];
                    return [
                      // The home screen and the layers that share the focus
                      // with it, so that it can pass between them: an open
                      // sidebar is on a layer, and still a step away.
                      Positioned.fill(
                        child: FocusScope(
                          node: home,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (layout.home.isEmpty)
                                const Center(child: Text('Nothing here yet'))
                              else
                                // The global pane: the whole screen, edge to
                                // edge. It is the user's to arrange, margins
                                // included.
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
                              // Over the home screen, each from its own edge:
                              // those that are on no layer of their own.
                              for (final bar in layout.bars)
                                if (layerOf(layers, bar.panel.id) == null)
                                  sidebar(bar),
                              Positioned(
                                top: _padding.top,
                                right: _padding.right,
                                child: _Header(
                                  settingsPlaced: _hasSettings(layout),
                                ),
                              ),
                              for (final layer in layers)
                                if (!layer.modal) ...shown(layer),
                            ],
                          ),
                        ),
                      ),
                      // Those that keep the focus to themselves, over all of
                      // that, lowest first.
                      for (final layer in layers)
                        if (layer.modal) ...shown(layer),
                    ];
                  },
                ),
              ],
            ),
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
