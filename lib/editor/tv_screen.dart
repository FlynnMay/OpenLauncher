import 'package:flutter/material.dart';
import 'package:openlauncher/features/home/home_screen.dart';
import 'package:openlauncher/features/home/popup_panel.dart';

/// The launcher itself, running in a box the size of the TV's screen: the
/// same home screen, popups, menus and settings, each kept inside the box.
class TvScreen extends StatelessWidget {
  const TvScreen({super.key});

  /// The TV's screen, in the units everything on it is measured in.
  static const size = Size(960, 540);

  /// The launcher's own navigator, for opening something on its screen
  /// from outside it.
  static final navigator = GlobalKey<NavigatorState>();

  /// Closes whatever the launcher has open over its home screen.
  static void closePopups() =>
      navigator.currentState?.popUntil((route) => route.isFirst);

  /// Shows the popup [panelId] on the launcher's screen.
  static void openPopup(String panelId) {
    if (navigator.currentState?.overlay?.context case final context?) {
      showPanelPopup(context, panelId);
    }
  }

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
