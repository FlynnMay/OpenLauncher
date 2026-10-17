import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/modules/drawers.dart';

/// The entity [container]'s entity-typed variables hold, [runtime] values
/// first.
Entity? _subject(
  Node container,
  Map<String, Object?>? runtime,
  Iterable<Entity> entities,
) => container
    .handedWith(runtime ?? const {})
    .map(entities.byId)
    .nonNulls
    .firstOrNull;

/// The entity the menu [id] was opened for.
Entity? subjectOf(WidgetRef ref, String id) {
  final container = ref.watch(
    layoutViewProvider.select((layout) => layout.value?.container(id)),
  );
  if (container == null) return null;
  return _subject(
    container,
    ref.watch(runtimeVarsProvider.select((all) => all[id])),
    ref.watch(entitiesProvider).value ?? const [],
  );
}

/// Watches each docked container's `open` variable and runs its reveal or hide
/// chain when it changes.
class DockHost extends ConsumerStatefulWidget {
  const DockHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DockHost> createState() => _DockHostState();
}

class _DockHostState extends ConsumerState<DockHost> {
  /// Last seen `open` per container.
  final _was = <String, bool>{};

  void _sync(Map<String, Map<String, Object?>> all) {
    final containers = ref.read(layoutViewProvider).value?.docked;
    if (containers == null || !mounted) return;
    final vars = ref.read(runtimeVarsProvider.notifier);
    for (final container in containers) {
      final id = container.id;
      final open = all[id]?[openVar] == true;
      if (open == (_was[id] ?? false)) continue;
      // A menu with no applicable actions is not shown.
      if (open) {
        final entities = ref.read(entitiesProvider).value ?? const <Entity>[];
        if (_subject(container, all[id], entities) != null &&
            offeredFor(container, ref.read, entities).isEmpty) {
          Future.microtask(() => vars.set(id, openVar, false));
          continue;
        }
      }
      _was[id] = open;
      runChain(
        context,
        ref,
        container.on[open ? Trigger.reveal : Trigger.hide] ?? const [],
        id,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(runtimeVarsProvider, (_, next) => _sync(next));
    return widget.child;
  }
}
