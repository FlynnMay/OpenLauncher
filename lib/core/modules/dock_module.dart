import 'package:openlauncher/core/layout/layout_enums.dart';
import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/nodes/node.dart';

const _edges = {
  'left': 'Left edge',
  'right': 'Right edge',
  'top': 'Top edge',
  'bottom': 'Bottom edge',
};

bool _atEdge(Map<String, Object?> values) =>
    _edges.containsKey(values['position']);
bool _docked(Map<String, Object?> values) =>
    DockModule.positions.contains(values['position']);

/// Takes it off its parent's cells and docks it at an edge or in the middle,
/// shown while its `open` variable is set.
class DockModule extends ModuleType {
  const DockModule()
    : super(
        'dock',
        'Dock',
        fields: const [
          Field(
            'position',
            'Position',
            FieldKind.choice,
            unset: 'None',
            choices: {..._edges, 'center': 'Centre'},
          ),
          // 0 leaves it at its edge with nothing showing; unset, it is not
          // there.
          Field(
            'closed',
            'Collapsed size',
            FieldKind.number,
            max: 400,
            step: 8,
            unset: 'Hidden',
            when: _atEdge,
          ),
          Field(
            'closeOnPress',
            'Close after a press',
            FieldKind.toggle,
            defaultValue: false,
            when: _docked,
          ),
          Field(
            'opening',
            'Animation',
            FieldKind.choice,
            defaultValue: 'expand',
            choices: {
              'expand': 'Expand',
              'slide': 'Slide',
              'fade': 'Fade',
              'instant': 'None',
            },
            when: _docked,
          ),
          Field(
            'reveal',
            'Content animation',
            FieldKind.choice,
            defaultValue: 'always',
            choices: {
              'always': 'None',
              'fade': 'Fade',
              'late': 'Fade after opening',
              'slide': 'Slide',
            },
            when: _docked,
          ),
        ],
      );

  /// A docked size that fills the screen.
  static const fill = double.infinity;

  /// Largest docked size, in TV pixels.
  static const maxExtent = 960.0;

  /// The edges, or the middle.
  static const positions = ['left', 'right', 'top', 'bottom', 'center'];
}

const dockModule = DockModule();

extension NodeDock on Node {
  ModuleValues get _dock => values(dockModule.name) ?? const {};

  /// One of [DockModule.positions], or null for a node on its parent's cells.
  String? get dock => switch (_dock['position']) {
    final String at when DockModule.positions.contains(at) => at,
    _ => null,
  };

  bool get isDocked => dock != null;

  /// The screen edge it is docked to, if any.
  BarEdge? get edge => BarEdge.values.asNameMap()[dock];

  /// True for the left and right edges.
  bool get opensAcross => edge == BarEdge.left || edge == BarEdge.right;

  double? _extent(String key) => switch (_dock[key]) {
    'fill' => DockModule.fill,
    final num size => size.toDouble(),
    _ => null,
  };

  /// Open size in TV pixels, [DockModule.fill] for all of the screen; null
  /// for the dock's default.
  double? get dockWidth => _extent('width');
  double? get dockHeight => _extent('height');

  /// How much shows while closed; 0 leaves it at its edge with nothing
  /// showing. Null hides it: see [hiddenWhenClosed].
  double? get closed => _extent('closed');

  /// Whether it is not there while closed, and so cannot take the focus then.
  bool get hiddenWhenClosed => isDocked && closed == null;

  /// Whether a press on something in it closes it.
  bool get closeOnPress => isDocked && _dock['closeOnPress'] == true;

  /// Defaults per dock: side bars are full height, top and bottom bars full
  /// width, one in the middle as tall as what is in it (null).
  double get openWidth =>
      dockWidth ??
      switch (edge) {
        BarEdge.left || BarEdge.right => 260,
        BarEdge.top || BarEdge.bottom => DockModule.fill,
        null => 595,
      };
  double? get openHeight =>
      dockHeight ??
      switch (edge) {
        BarEdge.left || BarEdge.right => DockModule.fill,
        BarEdge.top || BarEdge.bottom => 120,
        null => null,
      };
}
