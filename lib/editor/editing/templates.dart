import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher/editor/editing/prefab_edit.dart';

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
Node madeFrom(
  Prefab template,
  String id,
  Set<String> used, {
  String? variant,
}) => unpacked(Node(id: id, prefab: template.id, variant: variant), {
  template.id: template,
}, used).copyWith(template: template.id);

/// A new pane of id [id] made from [template]: docked at [dock] as the
/// variant made for it, else where the template's root docks. Its children
/// get ids not in [used].
Node paneFrom(
  Prefab template,
  String id, {
  String? dock,
  Set<String> used = const {},
}) {
  final made = madeFrom(template, id, {
    ...used,
  }, variant: dock == null ? null : variantFor(template, dock));
  return dock == null
      ? made
      : made.withValue(dockModule.name, 'position', dock);
}

/// The docked panes in [layout] copied from [template].
Iterable<Node> madeBy(Prefab template, Layout layout) =>
    layout.docked.where((pane) => pane.template == template.id);

/// [layout] with [template]'s look and chains on every pane copied from it:
/// its style, its chains and how it opens. What is in them, their titles and
/// where they dock stay.
Layout withTemplateApplied(Layout layout, Prefab template) {
  var next = layout;
  for (final pane in madeBy(template, layout).toList()) {
    final made = paneFrom(template, pane.id, dock: pane.dock);
    next = next.withPane(
      pane.id,
      (pane) => pane
          .styled(made.style)
          .withModule(dockModule.name, {
            ...?made.values(dockModule.name),
            'position': pane.dock,
          })
          .triggered({...pane.on, ...made.on}),
    );
  }
  return next;
}
