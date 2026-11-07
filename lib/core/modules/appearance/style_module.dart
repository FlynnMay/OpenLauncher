import 'package:openlauncher/core/modules/module.dart';
import 'package:openlauncher/core/modules/module_registry.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/nodes/node.dart';
import 'package:openlauncher/core/style/box_style.dart';
import 'package:openlauncher/core/style/style.dart';

/// Its look: background, border, corners, padding, opacity, shadow, and the
/// text properties its children inherit.
class StyleModule extends ModuleType {
  const StyleModule() : super('style', 'Style');

  @override
  List<Field> get fields => [
    for (final prop in styleProps)
      if (!scrollbarStyle.contains(prop.key)) prop,
  ];
}

const styleModule = StyleModule();

extension NodeStyle on Node {
  Style get style => values(styleModule.name) ?? const {};

  BoxStyle get box => BoxStyle.of(style);

  /// With [style] as its style.
  Node styled(Style style) =>
      withModule(styleModule.name, style.isEmpty ? null : style);

  /// The style properties that apply to it. What draws nothing passes text
  /// properties down.
  List<String> get styleKeys => [
    ...boxStyle,
    ...visual?.styleKeys ?? textStyle,
  ];
}
