import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';

/// True for the left and right edges, false for the top and bottom.
bool? _upright(String? dock) => switch (dock) {
  'left' || 'right' => true,
  'top' || 'bottom' => false,
  _ => null,
};

/// [prefab]'s variant whose root docks at [dock], else one on the same side
/// of the screen's axis, else the default.
String? variantFor(Prefab prefab, String dock) {
  int fit(String? variant) {
    final at = prefab.rootAs(variant).dock;
    if (at == dock) return 2;
    return _upright(at) != null && _upright(at) == _upright(dock) ? 1 : 0;
  }

  var best = prefab.defaultVariant;
  for (final variant in prefab.variants.keys) {
    if (fit(variant) > fit(best)) best = variant;
  }
  return best;
}

/// A new instance of [prefab], id [id], that docks: at [dock] as the variant
/// made for it, else where the prefab's root docks. Where it docks is its
/// own, so it says so.
Node dockedInstance(Prefab prefab, String id, {String? dock}) {
  final variant = dock == null ? null : variantFor(prefab, dock);
  return prefab
      .blank(id)
      .withVariant(variant)
      .withValue(
        dockModule.name,
        'position',
        dock ?? prefab.rootAs(variant).dock,
      );
}
