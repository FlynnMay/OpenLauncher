import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/nodes/node.dart';

bool _inLine(Map<String, Object?> values) =>
    values['mode'] == 'row' || values['mode'] == 'column';
bool _onCells(Map<String, Object?> values) => !_inLine(values);

/// Arranges a node's children: on cells (flow or grid) or in a line (row or
/// column). A node without one places its children by their transforms.
class LayoutModule extends ModuleType {
  const LayoutModule()
    : super(
        'layout',
        'Layout',
        fields: const [
          Field(
            'mode',
            'Layout',
            FieldKind.choice,
            defaultValue: 'flow',
            choices: {
              'flow': 'Flow',
              'grid': 'Grid',
              'row': 'Row',
              'column': 'Column',
            },
          ),
          Field(
            'columns',
            'Columns',
            FieldKind.number,
            defaultValue: defaultColumns,
            min: 1,
            max: maxColumns,
            when: _onCells,
          ),
          Field(
            'rowHeight',
            'Row height',
            FieldKind.number,
            min: 16,
            max: 400,
            step: 4,
            unset: 'Auto',
            when: _onCells,
          ),
          Field(
            'spacing',
            'Spacing',
            FieldKind.number,
            max: 80,
            step: 2,
            unset: 'Default',
            when: _onCells,
          ),
          Field(
            'gap',
            'Gap',
            FieldKind.number,
            max: 80,
            step: 2,
            defaultValue: 0,
            when: _inLine,
          ),
          Field('fit', 'Stretch to fit', FieldKind.toggle, when: _inLine),
          Field(
            'align',
            'Align',
            FieldKind.choice,
            unset: 'Default',
            choices: {
              'start': 'Start',
              'center': 'Centre',
              'end': 'End',
              'stretch': 'Stretch',
            },
            when: _inLine,
          ),
          // Forced on every instance directly in it.
          Field(
            'itemW',
            'Item width (cells)',
            FieldKind.number,
            min: 1,
            max: maxColumns,
            unset: 'Each its own',
            when: _onCells,
          ),
          Field(
            'itemH',
            'Item height (cells)',
            FieldKind.number,
            min: 1,
            max: 60,
            unset: 'Each its own',
            when: _onCells,
          ),
        ],
      );

  static const defaultColumns = 5;

  static const minRowHeight = 16.0, maxRowHeight = 400.0;

  /// Default row height of a sidebar.
  static const barRowHeight = 36.0;

  /// Cell gaps when spacing is unset.
  static const defaultSpacingX = 20.0, defaultSpacingY = 16.0;
  static const maxSpacing = 80.0;

  /// Columns of a new layer's root.
  static const globalColumns = 12;
  static const maxColumns = 24;

  /// Columns of a layout that scrolls across.
  static const maxReach = 999;
}

const layoutModule = LayoutModule();

extension NodeLayout on Node {
  ModuleValues get _layout => values(layoutModule.name) ?? const {};

  double? _measure(String key) => switch (_layout[key]) {
    final num measure => measure.toDouble(),
    _ => null,
  };

  /// How it arranges its children; [LayoutMode.free] without a layout.
  LayoutMode get mode => !has(layoutModule.name)
      ? LayoutMode.free
      : LayoutMode.values.asNameMap()[_layout['mode']] ?? LayoutMode.flow;

  int get columns => switch (_layout['columns']) {
    final num columns => columns.toInt(),
    _ => LayoutModule.defaultColumns,
  };

  /// Cell gap in TV pixels, both axes; null for the default.
  double? get spacing => _measure('spacing');
  double get spacingX => spacing ?? LayoutModule.defaultSpacingX;
  double get spacingY => spacing ?? LayoutModule.defaultSpacingY;

  /// Row height in TV pixels; null derives it from the cell width.
  double? get rowHeight => _measure('rowHeight');

  /// Size forced on every instance directly in it; null leaves it to each.
  double? get itemW => _measure('itemW');
  double? get itemH => _measure('itemH');

  /// Gap between children in a row or column.
  double get gap => _measure('gap') ?? 0;

  /// Children take their natural size, then the whole row or column is
  /// scaled to fit its box.
  bool get fit => _layout['fit'] == true;

  /// Cross axis alignment in a row or column: `start`, `center`, `end` or
  /// `stretch`.
  String? get align => switch (_layout['align']) {
    final String align => align,
    _ => null,
  };
}
