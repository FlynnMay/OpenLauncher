import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/overlays/overlays.dart';
import 'package:openlauncher/core/screens/last_screen_store.dart';

export 'package:openlauncher/core/screens/last_screen_store.dart';

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
  final last = ref.watch(lastScreenProvider);
  if (layout == null || last.isLoading) return null;
  return _current(layout, ref.watch(shownScreensProvider).id, last.value);
});

/// The screen shown last, loaded before the first one is drawn.
final lastScreenProvider = AsyncNotifierProvider<LastScreen, String?>(
  LastScreen.new,
);

class LastScreen extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.read(lastScreenStoreProvider).load();

  Future<void> remember(String id) async {
    state = AsyncData(id);
    await ref.read(lastScreenStoreProvider).save(id);
  }
}

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
        : _current(layout, state.id, ref.read(lastScreenProvider).value).id;
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
      ref.read(lastScreenProvider.notifier).remember(next.id!);
    }
  }
}
