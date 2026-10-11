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

/// Watches each panel's `open` variable and runs its reveal or hide chain
/// when it changes.
class PopupHost extends ConsumerStatefulWidget {
  const PopupHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PopupHost> createState() => _PopupHostState();
}

class _PopupHostState extends ConsumerState<PopupHost> {
  /// Last seen `open` per panel.
  final _was = <String, bool>{};

  Future<void> _fire(Panel panel, bool open) async {
    final acts =
        panelTriggersOf(panel)[open ? Trigger.reveal : Trigger.hide] ??
        const <Act>[];
    final actions = ref.read(actionRunnerProvider);
    for (final act in acts) {
      if (!mounted) return;
      await actions.run(act, component: panel.id);
    }
  }

  void _sync(Map<String, Map<String, Object?>> all) {
    final panels = ref.read(layoutViewProvider).value?.panels;
    if (panels == null || !mounted) return;
    final vars = ref.read(runtimeVarsProvider.notifier);
    for (final panel in panels) {
      final id = panel.id;
      final open = all[id]?[openVar] == true;
      if (open == (_was[id] ?? false)) continue;
      // A menu with no applicable actions is not shown.
      if (open) {
        final subject = switch (all[id]?[Component.sourceVar]) {
          final String source => ref.read(entitiesProvider).value?.byId(source),
          _ => null,
        };
        if (subject != null &&
            offeredFor(
              panel.root,
              subject,
              ref.read(actionRunnerProvider),
            ).isEmpty) {
          Future.microtask(() => vars.set(id, openVar, false));
          continue;
        }
      }
      _was[id] = open;
      _fire(panel, open);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(runtimeVarsProvider, (_, next) => _sync(next));
    return widget.child;
  }
}
