import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/overlays/overlays.dart';
import 'package:openlauncher/features/home/dock_host.dart';
import 'package:openlauncher/features/home/docked_node.dart';
import 'package:openlauncher/features/home/focus_navigation.dart';
import 'package:openlauncher/features/modules/drawers.dart';
import 'package:openlauncher/features/modules/lifted.dart';
import 'package:openlauncher/features/settings/settings_screen.dart';
import 'package:openlauncher/features/wallpaper/wallpaper_background.dart';

/// The home screen's focus scope, kept so focus can return from a modal
/// overlay.
final _homeFocusProvider = Provider((ref) {
  final node = FocusScopeNode(debugLabel: 'home');
  ref.onDispose(node.dispose);
  return node;
});

/// One key per docked container so its state survives going over the screen
/// and back.
final _dockKeysProvider = Provider((ref) => <String, GlobalKey>{});

/// Draws the home screen, then what is open over it, in the order it opened.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // TV overscan-safe margins (5% of a 960x540dp screen).
  static const _padding = EdgeInsets.symmetric(horizontal: 48, vertical: 27);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(layoutViewProvider);
    final entities = ref.watch(entitiesProvider).value ?? const <Entity>[];
    final overlays = ref.watch(overlaysProvider);
    final keys = ref.watch(_dockKeysProvider);
    final held = context.dependOnInheritedWidgetOfExactType<DockHold>()?.ids;
    void shut(OpenOverlay overlay) =>
        ref.read(overlaysProvider.notifier).close(overlay.id);

    // A modal overlay closing gives the focus back to what opened it, else to
    // the home screen.
    final home = ref.watch(_homeFocusProvider);
    ref.listen(overlaysProvider, (before, now) {
      for (final gone in before ?? const <OpenOverlay>[]) {
        if (!gone.modal || now.any((open) => open.id == gone.id)) continue;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final opener = gone.opener;
          if (opener != null &&
              opener.context != null &&
              opener.canRequestFocus) {
            opener.requestFocus();
          } else if (home.context != null && !now.any((open) => open.modal)) {
            home.requestFocus();
          }
        });
      }
    });
    Widget docked(Node container) => KeyedSubtree(
      key: keys.putIfAbsent(container.id, GlobalKey.new),
      child: DockedNode(container: container),
    );
    return PopScope(
      // Back only closes the top modal overlay.
      canPop: false,
      onPopInvokedWithResult: (_, _) {
        if (overlays.where((open) => open.modal).lastOrNull case final top?) {
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
                    final root = layout.home.root;
                    final over = {for (final open in overlays) open.id};
                    final empty = root.children.every(
                      (child) =>
                          child.offCells || child.isContainer && child.isEmpty,
                    );
                    // The screen: its root filling it, what is docked and not
                    // over it, and an Overlay the editor holds open.
                    final screen = [
                      if (!empty)
                        // Margins are the user's.
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
                      else
                        const Center(child: Text('Nothing here yet')),
                      for (final node in root.all)
                        if (!over.contains(node.id))
                          if (node.isDocked)
                            docked(node)
                          else if (node.isOverlay &&
                              (held?.contains(node.id) ?? false))
                            _Placed(node: node),
                      Positioned(
                        top: _padding.top,
                        right: _padding.right,
                        child: _Header(
                          settingsPlaced: _hasSettings(layout, entities),
                        ),
                      ),
                    ];

                    // An overlay: its backdrop, then its node, docked, placed
                    // by its transform, or lifted from its spot.
                    List<Widget> shown(OpenOverlay overlay) {
                      final node = layout.find(overlay.id);
                      if (node == null) return const [];
                      return [
                        if (overlay.blur > 0 || overlay.dim > 0)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ClipRect(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: overlay.blur,
                                    sigmaY: overlay.blur,
                                  ),
                                  child: ColoredBox(
                                    color: Colors.black.withValues(
                                      alpha: overlay.dim,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        // Tapping outside a modal overlay closes it.
                        if (overlay.modal)
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => shut(overlay),
                            ),
                          ),
                        if (node.isDocked)
                          docked(node)
                        else if (node.isOverlay)
                          _Placed(node: node)
                        else
                          Lifted(
                            id: node.id,
                            child: NodeView(component: node, lifted: true),
                          ),
                      ];
                    }

                    return [
                      // The screen and overlays that are not modal share one
                      // focus scope, so the D-pad moves between them.
                      Positioned.fill(
                        child: FocusScope(
                          node: home,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ...screen,
                              for (final overlay in overlays)
                                if (!overlay.modal) ...shown(overlay),
                            ],
                          ),
                        ),
                      ),
                      // Modal overlays on top, lowest first, each with the
                      // focus to itself.
                      for (final overlay in overlays)
                        if (overlay.modal)
                          Positioned.fill(
                            key: ValueKey('overlay ${overlay.id}'),
                            child: _Held(
                              child: Stack(
                                fit: StackFit.expand,
                                children: shown(overlay),
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

/// An Overlay that does not dock, where its transform puts it on the screen.
class _Placed extends StatefulWidget {
  const _Placed({required this.node});

  final Node node;

  @override
  State<_Placed> createState() => _PlacedState();
}

class _PlacedState extends State<_Placed> {
  /// The first tile in it takes the focus as it opens.
  final _first = FirstFocus();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, screen) => Stack(
      children: [
        Positioned.fromRect(
          rect: widget.node.transform.rectIn(screen.biggest),
          child: NodeView(component: widget.node, screen: true, focus: _first),
        ),
      ],
    ),
  );
}

/// Traps the focus and takes it on appearing.
class _Held extends StatefulWidget {
  const _Held({required this.child});

  final Widget child;

  @override
  State<_Held> createState() => _HeldState();
}

class _HeldState extends State<_Held> {
  final _scope = FocusScopeNode(debugLabel: 'modal overlay');

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
