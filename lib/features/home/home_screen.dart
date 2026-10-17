import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layers/layers.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/dock_host.dart';
import 'package:openlauncher/features/home/docked_node.dart';
import 'package:openlauncher/features/home/focus_navigation.dart';
import 'package:openlauncher/features/modules/drawers.dart';
import 'package:openlauncher/features/settings/settings_screen.dart';
import 'package:openlauncher/features/wallpaper/wallpaper_background.dart';

/// The home screen's focus scope, kept so focus can return from a modal
/// layer.
final _homeFocusProvider = Provider((ref) {
  final node = FocusScopeNode(debugLabel: 'home');
  ref.onDispose(node.dispose);
  return node;
});

/// One key per docked container so its state survives moving between layers.
final _dockKeysProvider = Provider((ref) => <String, GlobalKey>{});

/// Draws the layers: the saved ones, the home screen first, then those made
/// since.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // TV overscan-safe margins (5% of a 960x540dp screen).
  static const _padding = EdgeInsets.symmetric(horizontal: 48, vertical: 27);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(layoutViewProvider);
    final entities = ref.watch(entitiesProvider).value ?? const <Entity>[];
    final above = ref.watch(layersProvider);
    final keys = ref.watch(_dockKeysProvider);
    // Hides everything on [layer], which closes it.
    void shut(Layer layer) {
      for (final id in layer.holds) {
        ref.read(runtimeVarsProvider.notifier).set(id, openVar, false);
      }
    }

    // When the last modal layer closes, focus returns to the home screen.
    final home = ref.watch(_homeFocusProvider);
    ref.listen(layersProvider, (before, now) {
      bool keeps(List<Layer>? layers) =>
          layers?.any((layer) => layer.modal) ?? false;
      if (keeps(before) && !keeps(now)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (home.context != null) home.requestFocus();
        });
      }
    });
    Widget docked(Node container) => KeyedSubtree(
      key: keys.putIfAbsent(container.id, GlobalKey.new),
      child: DockedNode(container: container),
    );
    return PopScope(
      // Back only closes the top modal layer.
      canPop: false,
      onPopInvokedWithResult: (_, _) {
        if (above.where((layer) => layer.modal).lastOrNull case final top?) {
          shut(top);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: DockHost(
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
                    // A layer's backdrop, its own container, and the docked
                    // containers on it: its own that have not been moved, and
                    // those moved to it.
                    List<Widget> shown(Layer layer) {
                      final root = layer.root;
                      final first = layer.id == Layout.homeId;
                      final empty = root.children.every(
                        (child) =>
                            child.isDocked ||
                            child.isContainer && child.isEmpty,
                      );
                      return [
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
                        // Tapping outside a modal layer closes it.
                        if (layer.modal)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => shut(layer),
                            ),
                          ),
                        if (!empty)
                          // The root container fills the screen; margins are
                          // the user's.
                          _scrolling(
                            root,
                            Padding(
                              padding: EdgeInsets.all(root.box.padding ?? 0),
                              child: ChildrenLayout(
                                container: root,
                                tile: (entry) =>
                                    NodeView(component: entry, focus: focus),
                              ),
                            ),
                          )
                        else if (first)
                          const Center(child: Text('Nothing here yet')),
                        for (final container in root.all)
                          if (container.isDocked &&
                              layerOf(above, container.id) == null)
                            docked(container),
                        for (final id in layer.holds)
                          if (layout.container(id) case final container?
                              when container.isDocked)
                            docked(container),
                        if (first)
                          Positioned(
                            top: _padding.top,
                            right: _padding.right,
                            child: _Header(
                              settingsPlaced: _hasSettings(layout, entities),
                            ),
                          ),
                      ];
                    }

                    final layers = [...layout.layers, ...above];
                    return [
                      // Layers that are not modal share one focus scope, so
                      // the D-pad moves between them.
                      Positioned.fill(
                        child: FocusScope(
                          node: home,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              for (final layer in layers)
                                if (!layer.modal) ...shown(layer),
                            ],
                          ),
                        ),
                      ),
                      // Modal layers on top, lowest first, each with the
                      // focus to itself.
                      for (final layer in layers)
                        if (layer.modal)
                          Positioned.fill(
                            key: ValueKey('layer ${layer.id}'),
                            child: _Held(
                              child: Stack(
                                fit: StackFit.expand,
                                children: shown(layer),
                              ),
                            ),
                          ),
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

  static Widget _scrolling(Node root, Widget child) => ScrollBars.over(
    root,
    root.scroll,
    root.scrollsDown ? ScreenScrollView(child: child) : child,
  );

  /// Whether something placed opens the settings.
  static bool _hasSettings(Layout layout, List<Entity> entities) {
    final opening = {
      for (final entity in entities)
        if (entity.actions.values.any((action) => action.run == _settings))
          entity.id,
    };
    return layout.items.any((item) => item.handed.any(opening.contains));
  }

  static const _settings = 'launcher://settings/open';
}

/// Traps the focus and takes it on appearing.
class _Held extends StatefulWidget {
  const _Held({required this.child});

  final Widget child;

  @override
  State<_Held> createState() => _HeldState();
}

class _HeldState extends State<_Held> {
  final _scope = FocusScopeNode(debugLabel: 'modal layer');

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

/// Buttons shown only when needed.
class _Header extends ConsumerWidget {
  const _Header({required this.settingsPlaced});

  final bool settingsPlaced;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        // Until Home opens this launcher.
        if (ref.watch(accessProvider(Access.homeButton)).value == false)
          _HeaderButton(
            icon: Icons.home_outlined,
            label: 'Set as Home',
            onPressed: () => SettingsScreen.show(context),
          ),
        // A fallback way into Settings while its card is not placed.
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
