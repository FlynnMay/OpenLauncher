import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/editing/prefab_edit.dart';

/// Whether [template] makes sidebars: its root docks at a screen edge.
/// Anything else it makes is a folder.
bool makesSidebars(Prefab template) => template.root.edge != null;

/// What [template] makes, in words.
String madeName(Prefab template) =>
    makesSidebars(template) ? 'sidebar' : 'folder';

/// The first template in [prefabs] that makes what docks at [dock]: at an
/// edge a sidebar, anywhere else a folder.
Prefab? templateFor(String dock, Map<String, Prefab> prefabs) {
  final atEdge = BarEdge.values.asNameMap().containsKey(dock);
  return prefabs.values
      .where((prefab) => prefab.template && makesSidebars(prefab) == atEdge)
      .firstOrNull;
}

/// True for the left and right edges, false for the top and bottom.
bool? _upright(String? dock) => switch (dock) {
  'left' || 'right' => true,
  'top' || 'bottom' => false,
  _ => null,
};

/// [template]'s variant whose root docks at [dock], else one on the same
/// side of the screen's axis, else the default.
String? variantFor(Prefab template, String dock) {
  int fit(String? variant) {
    final at = template.rootAs(variant).dock;
    if (at == dock) return 2;
    return _upright(at) != null && _upright(at) == _upright(dock) ? 1 : 0;
  }

  var best = template.defaultVariant;
  for (final variant in template.variants.keys) {
    if (fit(variant) > fit(best)) best = variant;
  }
  return best;
}

/// [template]'s root as [variant], a plain pane of id [id] that records
/// the template. Its children get ids not in [used].
Component madeFrom(
  Prefab template,
  String id,
  Set<String> used, {
  String? variant,
}) => unpacked(Component(id: id, prefab: template.id, variant: variant), {
  template.id: template,
}, used).copyWith(template: template.id);

/// A new sidebar on [edge], made from [template]; a bare docked pane
/// without one.
Component sidebarFrom(
  Prefab? template,
  String id,
  String edge, [
  Set<String> used = const {},
]) =>
    (template == null
            ? Component.pane(id: id)
            : madeFrom(template, id, {
                ...used,
              }, variant: variantFor(template, edge)))
        .withOption('dock', edge);

/// A new folder titled [title], made from [template]; a bare pane in the
/// middle without one.
Component folderFrom(
  Prefab? template,
  String id, {
  String title = '',
  Set<String> used = const {},
}) =>
    (template == null
            ? Component.pane(id: id).withOption('dock', 'center')
            : madeFrom(template, id, {...used}))
        .withOption('title', title.isEmpty ? null : title);

/// [pane] given what only a docked pane has from [made], and the chains
/// [made] has that [pane] does not.
Component dockedLike(Component pane, Component made) => pane.copyWith(
  options: {
    ...pane.options,
    for (final key in dockKeys)
      if (made.options.containsKey(key)) key: made.options[key],
  },
  on: {...made.on, ...pane.on},
);

/// The docked panes in [layout] copied from [template].
Iterable<Component> madeBy(Prefab template, Layout layout) =>
    layout.docked.where((pane) => pane.template == template.id);

/// [layout] with [template]'s look and chains on every pane copied from it:
/// its style, its chains and how it docks. What is in them, their titles and
/// where they dock stay.
Layout withTemplateApplied(Layout layout, Prefab template) {
  var next = layout;
  for (final pane in madeBy(template, layout).toList()) {
    final made = makesSidebars(template)
        ? sidebarFrom(template, pane.id, pane.dock!)
        : folderFrom(template, pane.id);
    // One opened in place needs no layer.
    final inPlace = pane.dock == Component.inline;
    next = next.withPane(
      pane.id,
      (pane) => pane.copyWith(
        style: made.style,
        options: {
          ...pane.options,
          for (final key in dockKeys)
            if (key != 'dock') key: made.options[key],
        }..removeWhere((_, value) => value == null),
        on: {
          ...pane.on,
          for (final MapEntry(:key, :value) in made.on.entries)
            if (!inPlace || (key != Trigger.reveal && key != Trigger.hide))
              key: value,
        },
      ),
    );
  }
  return next;
}
