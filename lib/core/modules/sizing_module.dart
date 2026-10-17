import 'dart:math';

import 'package:openlauncher/core/layout/json_read.dart';
import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/modules/layout_module.dart';
import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/nodes/node.dart';

double? _positive(double? value) => value != null && value > 0 ? value : null;

/// How a child sizes inside its parent's Layout: cells it spans and where
/// (on cells), or its share and shape (in a row or column).
class SizingModule extends ModuleType {
  const SizingModule()
    : super('sizing', 'Sizing', instanceOwned: true, inLayout: true);

  /// What an override says to take a value away; once applied it is gone.
  static bool _none(String key, Object? value) => switch (key) {
    'flex' || 'aspect' => value is num && value <= 0,
    'w' || 'h' => value == 1,
    'keep' => value == false,
    _ => false,
  };

  @override
  ModuleValues merge(ModuleValues under, ModuleValues over) => {
    for (final MapEntry(:key, :value) in mergeValues(under, over).entries)
      if (!_none(key, value)) key: value,
  };

  /// Tallest a node can be, in cells.
  static const maxRows = 60;

  /// The fields for nodes whose parents are [parents]; only what applies in
  /// all of them.
  static List<Field> fieldsIn(Iterable<Node> parents, int reach) {
    if (parents.every((container) => container.mode.inLine)) {
      return const [
        Field('flex', 'Flex', FieldKind.number, max: 12, unset: 'Auto'),
        Field(
          'aspect',
          'Aspect ratio',
          FieldKind.number,
          max: 10,
          unset: 'Auto',
        ),
      ];
    }
    return [
      Field('w', 'Width (cells)', FieldKind.number, min: 1, max: reach),
      const Field(
        'h',
        'Height (cells)',
        FieldKind.number,
        min: 1,
        max: maxRows,
      ),
      if (parents.every((container) => container.mode != LayoutMode.flow)) ...[
        Field(
          'x',
          'Column',
          FieldKind.number,
          max: max(0, reach - 1),
          unset: 'Auto',
        ),
        const Field('y', 'Row', FieldKind.number, max: 999, unset: 'Auto'),
      ],
    ];
  }
}

const sizingModule = SizingModule();

extension NodeSizing on Node {
  ModuleValues get _sizing => values(sizingModule.name) ?? const {};

  double? _number(String key) => switch (_sizing[key]) {
    final num value => value.toDouble(),
    _ => null,
  };

  /// Cells it spans in a parent laid out on cells.
  double get w => _number('w') ?? 1;
  double get h => _number('h') ?? 1;

  /// The cell it starts at, in a grid; unused in a flow.
  double? get x => _number('x');
  double? get y => _number('y');

  /// In a row or column: share of the free space ([flex]) or width over
  /// height ([aspect]). With neither it takes its natural size. 0 means
  /// none, so a variant can unset its prefab's.
  double? get flex => _positive(_number('flex'));
  double? get aspect => _positive(_number('aspect'));

  /// Keeps its space in a row or column while hidden.
  bool get keep => _sizing['keep'] == true;

  /// With its cells set; omitted [x] and [y] are cleared, and so is a value
  /// of 1 for [w] or [h].
  Node sized(double w, double h, {double? x, double? y}) => withModule(
    sizingModule.name,
    {
      for (final MapEntry(:key, :value) in _sizing.entries)
        if (!const {'w', 'h', 'x', 'y'}.contains(key)) key: value,
      if (w != 1) 'w': tidy(w),
      if (h != 1) 'h': tidy(h),
      if (x != null) 'x': tidy(x),
      if (y != null) 'y': tidy(y),
    }.emptyAsNull,
  );
}

extension on Map<String, Object?> {
  Map<String, Object?>? get emptyAsNull => isEmpty ? null : this;
}
