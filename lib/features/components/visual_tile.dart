import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/components/app_widget.dart';
import 'package:openlauncher/features/components/primitives.dart';

/// Draws what a node's visual module shows.
class VisualTile extends StatelessWidget {
  const VisualTile({super.key, required this.item, this.shrink = false});

  final Node item;

  /// Take its natural size instead of filling, where the module supports it.
  final bool shrink;

  @override
  Widget build(BuildContext context) {
    final visual = item.visual;
    if (visual == null) return const SizedBox.shrink();
    final values = {...?item.values(visual.name), 'style': item.style};
    return switch (visual) {
      textModule => TextComponent(options: values, shrink: shrink),
      pictureModule => PictureComponent(options: values),
      meterModule => MeterComponent(options: values),
      iconModule => IconComponent(options: values),
      previewModule => FolderPicture(options: values),
      appWidgetModule => AppWidgetView(item: item),
      _ => const SizedBox.shrink(),
    };
  }
}
