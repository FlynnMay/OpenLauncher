import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config_store.dart';
import 'package:openlauncher/core/config/launcher_config.dart';
import 'package:openlauncher/core/layout/layout.dart';

final configProvider = AsyncNotifierProvider<ConfigController, LauncherConfig>(
  ConfigController.new,
);

/// The only place config is mutated. The TV UI and the web server
/// both go through these methods, so every change is persisted and every
/// listener is notified the same way.
class ConfigController extends AsyncNotifier<LauncherConfig> {
  @override
  Future<LauncherConfig> build() => ref.watch(configStoreProvider).load();

  Future<void> _update(LauncherConfig Function(LauncherConfig) change) async {
    final next = change(await future);
    state = AsyncData(next);
    await ref.read(configStoreProvider).save(next);
  }

  /// Replaces where everything is. [layout] is made valid first.
  Future<void> setLayout(Layout layout) =>
      _update((c) => c.copyWith(layout: layout.normalised()));

  /// Sets which quick actions a held-down card offers, in order.
  Future<void> setContextMenu(List<CardAction> actions) =>
      _update((c) => c.copyWith(contextMenu: List.unmodifiable(actions)));

  Future<void> setToasts(ToastOptions toasts) =>
      _update((c) => c.copyWith(toasts: toasts));

  /// Takes a card off every panel. It stays off until it is placed again.
  Future<void> removeCard(String id) =>
      _update((c) => c.copyWith(layout: c.layout.without({id}).normalised()));

  /// Sets the image or video behind the home screen; null removes it.
  Future<void> setWallpaper(String? path) =>
      _update((c) => c.copyWith(wallpaper: path));

  /// Sets a custom image for a card; pass null to return to the automatic one.
  Future<void> setIconOverride(String id, String? path) => _update(
    (c) => c.copyWith(
      iconOverrides: path == null
          ? ({...c.iconOverrides}..remove(id))
          : {...c.iconOverrides, id: path},
    ),
  );
}
