import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/modules/modules.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// One layer of the screen, drawn over the ones before it. The home screen is
/// the bottom one. Its content is [root]; a layer made while running starts
/// empty and [holds] what was moved to it.
@immutable
class Layer {
  const Layer({
    required this.id,
    required this.root,
    this.blur = 0,
    this.dim = 0,
    this.modal = false,
    this.holds = const {},
  });

  /// A layer with an empty root container.
  Layer.empty(this.id, {this.blur = 0, this.dim = 0, this.modal = false})
    : root = _emptyRoot(id),
      holds = const {};

  final String id;

  final Node root;

  /// Blur of what is below; 0 for none.
  final double blur;

  /// Dimming of what is below, 0 to 1.
  final double dim;

  /// Takes the focus; Back closes what is on it.
  final bool modal;

  /// Ids of the docked containers moved to it. Not saved.
  final Set<String> holds;

  static String rootId(String layerId) => '$layerId/root';

  static Node _emptyRoot(String id) => Node.layout(
    id: rootId(id),
    mode: LayoutMode.grid,
    columns: LayoutModule.globalColumns,
  );

  Layer withRoot(Node root) => Layer(
    id: id,
    root: root,
    blur: blur,
    dim: dim,
    modal: modal,
    holds: holds,
  );

  Layer holding(Set<String> holds) => Layer(
    id: id,
    root: root,
    blur: blur,
    dim: dim,
    modal: modal,
    holds: holds,
  );

  factory Layer.fromJson(Map<Object?, Object?> json) {
    final id = jsonRequired<String>(json, 'id');
    return Layer(
      id: id,
      root: switch (jsonOptional<Map<Object?, Object?>>(json, 'root')) {
        final container? => Node.fromJson(container),
        null => _emptyRoot(id),
      },
      blur: (jsonOptional<num>(json, 'blur') ?? 0).clamp(0, 40).toDouble(),
      dim: (jsonOptional<num>(json, 'dim') ?? 0).clamp(0, 1).toDouble(),
      modal: json['modal'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    if (blur != 0) 'blur': tidy(blur),
    if (dim != 0) 'dim': tidy(dim),
    if (modal) 'modal': true,
    'root': root.toJson(),
  };
}
