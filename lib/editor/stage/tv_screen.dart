import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/home_screen.dart';

/// The launcher running in a box the size of the TV's screen.
class TvScreen extends StatelessWidget {
  const TvScreen({super.key});

  /// In the TV's logical pixels.
  static const size = Size(960, 540);

  /// For opening things on the launcher's screen from outside.
  static final navigator = GlobalKey<NavigatorState>();

  static ProviderContainer? get _launcher =>
      switch (navigator.currentState?.overlay?.context) {
        null => null,
        final context => ProviderScope.containerOf(context),
      };

  /// Opens docked pane [id] by setting its `open` variable.
  static void openDocked(String id) =>
      _launcher?.read(runtimeVarsProvider.notifier).set(id, openVar, true);

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
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
          child: Navigator(
            key: navigator,
            onGenerateRoute: (_) =>
                MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
          ),
        ),
      ),
    ),
  );
}
