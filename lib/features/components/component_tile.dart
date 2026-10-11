import 'package:flutter/material.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/components/app_widget.dart';
import 'package:openlauncher/features/components/primitives.dart';

/// Draws the component a layout item stands for. Components have no entity behind
/// them: they sit straight on the wallpaper.
class ComponentTile extends StatelessWidget {
  const ComponentTile({super.key, required this.item, this.shrink = false});

  final Component item;

  /// True to take only the room it needs, where its kind can.
  final bool shrink;

  /// The component of the kind called [kind], set up by [options]. [shrink]
  /// has one that can take only the room it needs do so.
  static Widget of(
    String kind,
    Map<String, Object?> options, {
    bool shrink = false,
  }) => switch (ComponentKind.named(kind)) {
    ComponentKind.text => TextComponent(options: options, shrink: shrink),
    ComponentKind.picture => PictureComponent(options: options),
    ComponentKind.meter => MeterComponent(options: options),
    ComponentKind.button => ButtonComponent(options: options),
    ComponentKind.icon => IconComponent(options: options),
    ComponentKind.folder => FolderPicture(options: options),
    // Needs the item it is, which the device knows it by; and what was
    // made by a newer version of the launcher.
    ComponentKind.android || null => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) => switch (ComponentKind.named(
    item.kind,
  )) {
    ComponentKind.android => AppWidgetView(item: item),
    // Its look is its item's.
    _ => of(item.kind, {...item.options, 'style': item.style}, shrink: shrink),
  };
}
