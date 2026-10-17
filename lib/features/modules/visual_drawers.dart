import 'package:flutter/widgets.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/modules/app_widget_drawer.dart';
import 'package:openlauncher/features/modules/icon_drawer.dart';
import 'package:openlauncher/features/modules/meter_drawer.dart';
import 'package:openlauncher/features/modules/picture_drawer.dart';
import 'package:openlauncher/features/modules/preview_drawer.dart';
import 'package:openlauncher/features/modules/text_drawer.dart';

/// What a visual module draws for [node]. [values] are its module's, with
/// the node's style under `style`; [shrink] asks for its natural size where
/// it has one.
typedef VisualDrawer = Widget Function(
  Node node,
  Map<String, Object?> values,
  bool shrink,
);

/// Each visual module's drawer, by module name. A new visual module goes
/// here.
final visualDrawers = <String, VisualDrawer>{
  textModule.name: (_, values, shrink) =>
      TextVisual(values: values, shrink: shrink),
  pictureModule.name: (_, values, _) => PictureVisual(values: values),
  iconModule.name: (_, values, _) => IconVisual(values: values),
  meterModule.name: (_, values, _) => MeterVisual(values: values),
  previewModule.name: (_, values, _) => PreviewVisual(values: values),
  appWidgetModule.name: (node, _, _) => AppWidgetVisual(node: node),
};

/// What [node]'s visual module draws, if it has one.
Widget? drawVisual(Node node, {bool shrink = false}) {
  final visual = node.visual;
  if (visual == null) return null;
  final values = {...?node.values(visual.name), 'style': node.style};
  return visualDrawers[visual.name]?.call(node, values, shrink);
}
