import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/commands/commands.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/slice/slice.dart';

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
    final nodes = await _ref.read(nodesProvider.future);
    final entity = nodes.byId(what);
    final layout = await _layoutAsEdited();
    final target = layout.screen(screen);
    if (entity == null || target == null) return null;
    final container = to ?? _defaultContainer(layout, target);
    if (!_holds(target, container)) {
      return 'There is no layout "$container" there.';
    }
    final item = instanceFor(
      entity.id,
      entity.category,
      entity.deviceName,
      layout,
      _ref.read(prefabsProvider),
    );
    if (item == null) return '${entity.name} has no card to show it.';
    await _run([
      SliceEdit(LayoutAddress(container), [Insert(Where.into, NodeClip(item))]),
    ]);
    return '${entity.name} was added.';
  }

  /// Takes every instance of [what] (an entity id) off [screen], or off every
  /// screen if it is null.
  Future<String?> remove({required String what, String? screen}) async {
    final nodes = await _ref.read(nodesProvider.future);
    final layout = await _layoutAsEdited();
    final screens = [
      for (final one in layout.screens)
        if (screen == null || one.id == screen) one,
    ];
    await _run([
      for (final one in screens)
        for (final node in one.root.all)
          if (!node.isContainer && node.handed.contains(what))
            SliceEdit(LayoutAddress(node.id), const [RemoveNode()]),
      SliceEdit(const ConfigAddress(), [
        SetRemoved({...layout.removed, what}),
      ]),
    ]);
    final label = nodes.byId(what)?.name ?? what;
    return '$label was removed. Add it again from the web page.';
  }

  /// What commands are run on: the saved layout with the entities not placed
  /// yet in the inbox.
  Future<Layout> _layoutAsEdited() async => layoutWith(
    (await _ref.read(configProvider.future)).layout,
    await _ref.read(nodesProvider.future),
    _ref.read(prefabsProvider),
  );

  /// Done as the launcher's own command, so it is logged and shown to editors.
  Future<void> _run(List<SliceEdit> edits) =>
      _ref.read(commandsProvider).run(EditSlice(edits));

  String _defaultContainer(Layout layout, Screen screen) =>
      _holds(screen, layout.inbox) ? layout.inbox : screen.root.id;

  bool _holds(Screen screen, String? id) =>
      screen.root.containers.any((container) => container.id == id);
}

final layoutServiceProvider = Provider<LayoutService>(LayoutService.new);
