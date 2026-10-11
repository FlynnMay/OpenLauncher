import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/tile_actions.dart';

/// The entity the menu [id] was opened for, from its `source` variable.
Entity? subjectOf(WidgetRef ref, String id) => switch (ref.watch(
  runtimeVarsProvider.select((all) => all[id]?[Component.sourceVar]),
)) {
  final String source => ref.watch(entitiesProvider).value?.byId(source),
  _ => null,
};

/// Watches each docked pane's `open` variable and runs its reveal or hide
/// chain when it changes.
class DockHost extends ConsumerStatefulWidget {
  const DockHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DockHost> createState() => _DockHostState();
}

class _DockHostState extends ConsumerState<DockHost> {
  /// Last seen `open` per pane.
  final _was = <String, bool>{};

  void _sync(Map<String, Map<String, Object?>> all) {
    final panes = ref.read(layoutViewProvider).value?.docked;
    if (panes == null || !mounted) return;
    final vars = ref.read(runtimeVarsProvider.notifier);
    for (final pane in panes) {
      final id = pane.id;
      final open = all[id]?[openVar] == true;
      if (open == (_was[id] ?? false)) continue;
      // A menu with no applicable actions is not shown.
      if (open) {
        final entities = ref.read(entitiesProvider).value ?? const <Entity>[];
        final source = all[id]?[Component.sourceVar];
        if (source is String &&
            entities.byId(source) != null &&
            offeredFor(pane, ref.read, entities).isEmpty) {
          Future.microtask(() => vars.set(id, openVar, false));
          continue;
        }
      }
      _was[id] = open;
      runChain(
        context,
        ref,
        pane.on[open ? Trigger.reveal : Trigger.hide] ?? const [],
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
