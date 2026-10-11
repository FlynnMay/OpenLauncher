import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/home/tile_actions.dart';

/// The entity the folder [id] is about, where its `source` variable says
/// one: what makes it that entity's menu.
Entity? subjectOf(WidgetRef ref, String id) => switch (ref.watch(
  runtimeVarsProvider.select((all) => all[id]?[LayoutItem.sourceVar]),
)) {
  final String source => ref.watch(entitiesProvider).value?.byId(source),
  _ => null,
};

/// Follows the `open` variable of everything that is shown and hidden: a
/// sidebar, a folder. As one changes, what that pane does on being
/// revealed or hidden is done, one action after another. That is all that
/// shows a folder: revealed, it makes a layer and moves to it, unless it
/// is set to do otherwise.
class PopupHost extends ConsumerStatefulWidget {
  const PopupHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PopupHost> createState() => _PopupHostState();
}

class _PopupHostState extends ConsumerState<PopupHost> {
  /// Whether each panel was open when last looked at, by id.
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
    for (final view in panels.values) {
      final id = view.panel.id;
      final open = all[id]?[openVar] == true;
      if (open == (_was[id] ?? false)) continue;
      // A menu with nothing in it for what it is about is not shown at all.
      if (open) {
        final subject = switch (all[id]?[LayoutItem.sourceVar]) {
          final String source => ref.read(entitiesProvider).value?.byId(source),
          _ => null,
        };
        if (subject != null &&
            offeredFor(
              view.root,
              subject,
              ref.read(actionRunnerProvider),
            ).isEmpty) {
          Future.microtask(() => vars.set(id, openVar, false));
          continue;
        }
      }
      _was[id] = open;
      _fire(view.panel, open);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(runtimeVarsProvider, (_, next) => _sync(next));
    return widget.child;
  }
}
