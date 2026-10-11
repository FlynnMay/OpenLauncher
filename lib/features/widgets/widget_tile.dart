import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/instance_options.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/features/widgets/app_widget.dart';
import 'package:openlauncher/features/widgets/primitive_widgets.dart';

/// Draws the widget a layout item stands for. Widgets have no entity behind
/// them: they sit straight on the wallpaper.
class WidgetTile extends StatelessWidget {
  const WidgetTile({super.key, required this.item});

  final LayoutItem item;

  /// The widget of the kind called [kind], set up by [options]. [shrink]
  /// has one that can take only the room it needs do so.
  static Widget of(
    String kind,
    Map<String, Object?> options, {
    bool shrink = false,
  }) => switch (WidgetKind.named(kind)) {
    WidgetKind.text => TextWidget(options: options, shrink: shrink),
    WidgetKind.picture => PictureWidget(options: options),
    WidgetKind.meter => MeterWidget(options: options),
    WidgetKind.button => ButtonWidget(options: options),
    WidgetKind.icon => IconWidget(options: options),
    WidgetKind.folder => FolderPicture(options: options),
    // Needs the item it is, which the device knows it by; and what was
    // made by a newer version of the launcher.
    WidgetKind.android || null => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) => switch (WidgetKind.named(item.ref)) {
    WidgetKind.android => AppWidgetView(item: item),
    // Its look is its item's.
    _ => of(item.ref, {...item.options, styleOption: item.style}),
  };
}
