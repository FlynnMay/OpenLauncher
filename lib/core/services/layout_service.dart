import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';

/// What is on a screen.
class LayoutService {
  LayoutService(this._ref);

  final Ref _ref;

  /// Puts [what] (an entity id) in container [to] on [screen], else in the
  /// inbox. Returns a message for the user, or null if there was nothing to do.
  Future<String?> add({
    required String screen,
    required String what,
    String? to,
  }) async {
    final entities = await _ref.read(entitiesProvider.future);
    final entity = entities.byId(what);
    final layout = (await _ref.read(configProvider.future)).layout;
    final target = layout.screen(screen);
    if (entity == null || target == null) return null;
    final container = to ?? _defaultContainer(layout, target);
    if (!_holds(target, container)) {
      return 'There is no layout "$container" there.';
    }
    final item = instanceFor(entity, layout, _ref.read(prefabsProvider));
    if (item == null) return '${entity.label} has no card to show it.';
    await _ref.read(configProvider.notifier).addItem(item, container);
    return '${entity.label} was added.';
  }

  /// Takes every instance of [what] (an entity id) off [screen], or off every
  /// screen if it is null.
  Future<String?> remove({required String what, String? screen}) async {
    final entities = await _ref.read(entitiesProvider.future);
    await _ref.read(configProvider.notifier).removeEntity(what, screen: screen);
    final label = entities.byId(what)?.label ?? what;
    return '$label was removed. Add it again from the web page.';
  }

  String _defaultContainer(Layout layout, Screen screen) =>
      _holds(screen, layout.inbox) ? layout.inbox : screen.root.id;

  bool _holds(Screen screen, String? id) =>
      screen.root.containers.any((container) => container.id == id);
}

final layoutServiceProvider = Provider<LayoutService>(LayoutService.new);
