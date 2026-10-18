import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/overlays/overlays.dart';

/// The screen shown, if one was opened since starting, and those it was
/// opened from, oldest first.
@immutable
class ShownScreens {
  const ShownScreens([this.id, this.back = const []]);

  final String? id;
  final List<String> back;
}

final shownScreensProvider = NotifierProvider<ShownScreen, ShownScreens>(
  ShownScreen.new,
);

/// The screen drawn: the one opened, else the one [Startup] says.
final currentScreenProvider = Provider<Screen?>((ref) {
  final layout = ref.watch(layoutViewProvider).value;
  if (layout == null) return null;
  return _current(
    layout,
    ref.watch(shownScreensProvider).id,
    ref.watch(configProvider.select((c) => c.value?.lastScreen)),
  );
});

Screen _current(Layout layout, String? shown, String? last) {
  final id = shown ?? (layout.startup.remember ? last : null);
  return (id == null ? null : layout.screen(id)) ?? layout.start;
}

class ShownScreen extends Notifier<ShownScreens> {
  @override
  ShownScreens build() => const ShownScreens();

  /// Shows [id], keeping the screen before it for [back]. What is open over
  /// the screen closes.
  void open(String id) {
    final layout = ref.read(layoutViewProvider).value;
    final now = layout == null
        ? null
        : _current(
            layout,
            state.id,
            ref.read(configProvider).value?.lastScreen,
          ).id;
    if (now == id) return;
    _show(ShownScreens(id, [...state.back, ?now]));
  }

  /// Shows the screen before; false if there is none.
  bool back() {
    final layout = ref.read(layoutViewProvider).value;
    final back = [
      for (final id in state.back)
        if (layout?.screen(id) != null) id,
    ];
    if (back.isEmpty) return false;
    _show(ShownScreens(back.last, back.sublist(0, back.length - 1)));
    return true;
  }

  void _show(ShownScreens next) {
    ref.read(overlaysProvider.notifier).closeAll();
    state = next;
    final layout = ref.read(layoutViewProvider).value;
    if (layout != null && layout.startup.remember) {
      ref.read(configProvider.notifier).setLastScreen(next.id!);
    }
  }
}
