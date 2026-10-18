import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';

/// What is on a screen, named by `screen`.
class LayoutOperationsManager implements OperationsManager {
  LayoutOperationsManager(this._ref);

  final Ref _ref;

  @override
  late final List<Operation> operations = [
    Operation(
      name: 'launcher://layout/add',
      label: 'Add an entity to a screen',
      // `what` is an entity id; `to` a container on the screen, else the inbox.
      args: const {'screen': [], 'what': [], 'to': []},
      run: (run) async {
        final entities = await _ref.read(entitiesProvider.future);
        final entity = entities.byId(run.arg('what'));
        final layout = (await _ref.read(configProvider.future)).layout;
        final screen = layout.screen(run.arg('screen') ?? '');
        if (entity == null || screen == null) return null;
        bool holds(String? id) => screen.root.containers.any((p) => p.id == id);
        final to =
            run.arg('to') ??
            (holds(layout.inbox) ? layout.inbox : screen.root.id);
        if (!holds(to)) return 'There is no layout "$to" there.';
        final item = instanceFor(entity, layout, _ref.read(prefabsProvider));
        if (item == null) return '${entity.label} has no card to show it.';
        await _ref.read(configProvider.notifier).addItem(item, to);
        return '${entity.label} was added.';
      },
    ),
    Operation(
      name: 'launcher://layout/remove',
      label: 'Remove an entity from a screen',
      // `what` is an entity id; every instance handed it is removed.
      args: const {'screen': [], 'what': []},
      run: (run) async {
        final id = run.arg('what');
        if (id == null) return null;
        final entities = await _ref.read(entitiesProvider.future);
        await _ref
            .read(configProvider.notifier)
            .removeEntity(id, screen: run.arg('screen'));
        final label = entities.byId(id)?.label ?? id;
        return '$label was removed. Add it again from the web page.';
      },
    ),
  ];
}
