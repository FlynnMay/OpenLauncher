import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/editing/editor_mode.dart';
import 'package:openlauncher/features/home/home_screen.dart';

/// The launcher running in a box the size of the TV's screen.
class TvScreen extends ConsumerWidget {
  const TvScreen({super.key});

  /// In the TV's logical pixels.
  static const size = Size(960, 540);

  /// For opening things on the launcher's screen from outside.
  static final navigator = GlobalKey<NavigatorState>();

  /// A browser's own shortcuts scroll with the arrow keys; the TV's move the
  /// focus.
  static const _arrows = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(
      TraversalDirection.left,
    ),
    SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(
      TraversalDirection.right,
    ),
    SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(
      TraversalDirection.up,
    ),
    SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(
      TraversalDirection.down,
    ),
  };

  static ProviderContainer? get _launcher =>
      switch (navigator.currentState?.overlay?.context) {
        null => null,
        final context => ProviderScope.containerOf(context),
      };

  /// Opens docked container [id] by setting its `open` variable.
  static void openDocked(String id) =>
      _launcher?.read(runtimeVarsProvider.notifier).set(id, openVar, true);

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox.fromSize(
    size: size,
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: size,
        padding: EdgeInsets.zero,
        viewInsets: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
      ),
      child: ClipRect(
        // Its own messenger, so snackbars stay inside the box.
        child: ScaffoldMessenger(
          child: Shortcuts(
            // Only testing is a remote in the hand; editing leaves the keys.
            shortcuts: ref.watch(editorModeProvider) == EditorMode.test
                ? _arrows
                : const {},
            child: Navigator(
              key: navigator,
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
            ),
          ),
        ),
      ),
    ),
  );
}
