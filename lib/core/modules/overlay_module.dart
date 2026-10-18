import 'package:openlauncher/core/modules/dock_module.dart';
import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/nodes/node.dart';

/// Takes it off its parent's cells and draws it over the screen while its
/// `open` variable is set, placed by its Dock or its transform. Closed, it
/// shows only its Dock's strip, if any.
class OverlayModule extends ModuleType {
  const OverlayModule()
    : super(
        'overlay',
        'Overlay',
        use: ModuleUse.onScreen,
        fields: const [
          // A percentage, as opacity is.
          Field(
            'dim',
            'Dim behind',
            FieldKind.number,
            defaultValue: 0,
            step: 5,
          ),
          Field(
            'blur',
            'Blur behind',
            FieldKind.number,
            defaultValue: 0,
            max: OverlayModule.maxBlur,
          ),
          // Back closes it, and the focus cannot leave it.
          Field('modal', 'Modal', FieldKind.toggle, defaultValue: false),
        ],
      );

  static const maxBlur = 40;
}

const overlayModule = OverlayModule();

extension NodeOverlay on Node {
  ModuleValues get _overlay => values(overlayModule.name) ?? const {};

  bool get isOverlay => has(overlayModule.name);

  /// Drawn over the screen rather than on its parent's cells.
  bool get offCells => isDocked || isOverlay;

  /// 0 to 1.
  double get overlayDim => switch (_overlay['dim']) {
    final num dim => dim.clamp(0, 100) / 100,
    _ => 0,
  };

  double get overlayBlur => switch (_overlay['blur']) {
    final num blur => blur.clamp(0, OverlayModule.maxBlur).toDouble(),
    _ => 0,
  };

  bool get overlayModal => _overlay['modal'] == true;
}
