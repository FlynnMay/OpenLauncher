import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/home_screen.dart';

/// The launcher itself, running in a box the size of the TV's screen: the
/// same home screen, popups, menus and settings, each kept inside the box.
class TvScreen extends StatelessWidget {
  const TvScreen({super.key});

  /// The TV's screen, in the units everything on it is measured in.
  static const size = Size(960, 540);

  /// The launcher's own navigator, for opening something on its screen
  /// from outside it.
  static final navigator = GlobalKey<NavigatorState>();

  static ProviderContainer? get _launcher =>
      switch (navigator.currentState?.overlay?.context) {
        null => null,
        final context => ProviderScope.containerOf(context),
      };

  /// Closes whatever folders the launcher has open over its home screen.
  static void closePopups() {
    final launcher = _launcher;
    if (launcher == null) return;
    final vars = launcher.read(runtimeVarsProvider.notifier);
    for (final MapEntry(key: id, value: set)
        in launcher.read(runtimeVarsProvider).entries) {
      if (set[openVar] == true && Panel.kindOf(id) == PanelKind.popup) {
        vars.set(id, openVar, false);
      }
    }
  }

  /// Shows the folder [panelId] on the launcher's screen, as a press on
  /// what opens it would: by its variable.
  static void openPopup(String panelId) =>
      _launcher?.read(runtimeVarsProvider.notifier).set(panelId, openVar, true);

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
        // Its own, so that what the launcher opens and says stays on its
        // screen instead of covering the page.
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
