import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/editing/editing.dart';
import 'package:openlauncher/editor/modules/module_edit_context.dart';
import 'package:openlauncher/editor/modules/module_editors.dart';

/// A section per module the selected nodes all have, in registry order, then
/// a way to add one. Sizing shows whenever their parents lay them out.
class ModuleSections extends ConsumerWidget {
  const ModuleSections({
    super.key,
    required this.nodes,
    required this.parents,
    required this.onChanged,
    this.onLayout,
    this.inPrefab = false,
    this.exposable = false,
    this.inDock = false,
    this.scope = const {},
  });

  /// As saved.
  final List<Node> nodes;

  /// Their parents; none for a screen's root.
  final List<Node> parents;

  final void Function(Node Function(Node node) how) onChanged;
  final void Function(Layout Function(Layout layout) how)? onLayout;
  final bool inPrefab, exposable, inDock;
  final Variables scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefabs = ref.watch(prefabsProvider);
    final drawn = [for (final node in nodes) resolved(node, prefabs)];
    final laidOut =
        parents.isNotEmpty &&
        parents.every((parent) => parent.has(layoutModule.name)) &&
        !drawn.any((node) => node.offCells);
    ModuleEdit edit(ModuleType type) => ModuleEdit(
      type: type,
      nodes: nodes,
      parents: parents,
      onChanged: onChanged,
      onLayout: onLayout,
      prefabs: prefabs,
      inPrefab: inPrefab,
      exposable: exposable,
      inDock: inDock,
      scope: scope,
    );
    final shown = [
      for (final type in moduleTypes)
        if (drawn.every((node) => node.added(type.name)) ||
            type.inLayout && laidOut)
          type,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in shown) ModuleSection(edit(type)),
        _AddModule(
          offered: [
            for (final type in moduleTypes)
              if (_offered(type, drawn)) type,
          ],
          onAdded: (type) => onChanged((node) => withAdded(node, type)),
        ),
      ],
    );
  }

  /// Whether Add module offers [type] for nodes drawn as [drawn].
  bool _offered(ModuleType type, List<Node> drawn) =>
      !type.inLayout &&
      switch (type.use) {
        ModuleUse.anywhere => true,
        ModuleUse.inPrefab => inPrefab,
        ModuleUse.onScreen => !inPrefab,
      } &&
      !drawn.any((node) => node.added(type.name)) &&
      // One visual each.
      !(type.visual &&
          drawn.any(
            (node) => visualModules.any((visual) => node.added(visual.name)),
          ));
}

/// One module's section: a switch, a menu to remove it, and its fields.
class ModuleSection extends StatelessWidget {
  const ModuleSection(this.edit, {super.key});

  final ModuleEdit edit;

  @override
  Widget build(BuildContext context) {
    final type = edit.type;
    final theme = Theme.of(context);
    final on = shared(edit.on);
    // An instance cannot take away what its prefab gives, only switch it
    // off.
    final added = edit.drawn.every((node) => node.added(type.name));
    final removable =
        edit.nodes.every((node) => node.added(type.name)) &&
        edit.nodes.every(
          (node) =>
              !node.isInstance ||
              type.instanceOwned ||
              !resolved(
                node.withModule(type.name, null),
                edit.prefabs,
              ).added(type.name),
        );
    final needed = {for (final node in edit.nodes) ...needing(node, type)};
    final body = editModule(edit);
    return Section(
      type.label,
      leading: added
          ? Checkbox(
              value: on,
              tristate: on == null,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (_) => edit.onChanged(
                (node) => withSwitch(node, type, on != true, edit.prefabs),
              ),
            )
          : null,
      trailing: added
          ? PopupMenuButton<VoidCallback>(
              tooltip: 'Module menu',
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (does) => does(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: removable && needed.isEmpty,
                  value: () =>
                      edit.onChanged((node) => withRemoved(node, type)),
                  child: Text(switch ((removable, needed)) {
                    (false, _) => 'Remove (its prefab gives it)',
                    (_, final needed) when needed.isNotEmpty =>
                      'Remove (${needed.join(', ')} needs it)',
                    _ => 'Remove module',
                  }),
                ),
                if (edit.own.isNotEmpty)
                  PopupMenuItem(
                    value: () => edit.onChanged((node) {
                      var next = node;
                      for (final key in edit.own) {
                        next = withInherited(next, type, key, edit.prefabs);
                      }
                      return next;
                    }),
                    child: const Text('Revert to prefab'),
                  ),
              ],
            )
          : null,
      [
        if (on == false) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Switched off: kept, but it does nothing.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          IgnorePointer(
            child: Opacity(
              opacity: 0.5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: body,
              ),
            ),
          ),
        ] else
          ...body,
      ],
    );
  }
}

/// A search over the modules the nodes can take.
class _AddModule extends StatelessWidget {
  const _AddModule({required this.offered, required this.onAdded});

  final List<ModuleType> offered;
  final void Function(ModuleType type) onAdded;

  @override
  Widget build(BuildContext context) {
    if (offered.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SearchBox(
        // Empty again once one is added.
        key: ValueKey(offered.map((type) => type.name).join(' ')),
        value: null,
        hint: 'Add module',
        groups: {
          'Draws': {
            for (final type in offered)
              if (type.visual) type.name: type.label,
          },
          'Behaviour': {
            for (final type in offered)
              if (!type.visual) type.name: type.label,
          },
        }..removeWhere((_, choices) => choices.isEmpty),
        onChanged: (name) => onAdded(moduleNamed(name)!),
      ),
    );
  }
}
