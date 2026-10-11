import 'package:flutter/material.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/components/app_widget.dart';
import 'package:openlauncher/features/components/primitives.dart';

/// Draws a primitive component.
class ComponentTile extends StatelessWidget {
  const ComponentTile({super.key, required this.item, this.shrink = false});

  final Component item;

  /// Take its natural size instead of filling, where the kind supports it.
  final bool shrink;

  /// The widget for [kind] with [options].
  static Widget of(
    String kind,
    Map<String, Object?> options, {
    bool shrink = false,
  }) => switch (ComponentRegistry.named(kind)) {
    ComponentRegistry.text => TextComponent(options: options, shrink: shrink),
    ComponentRegistry.picture => PictureComponent(options: options),
    ComponentRegistry.meter => MeterComponent(options: options),
    ComponentRegistry.button => ButtonComponent(options: options),
    ComponentRegistry.icon => IconComponent(options: options),
    ComponentRegistry.folder => FolderPicture(options: options),
    // App widgets need their component's id; unknown kinds draw nothing.
    ComponentRegistry.android || null => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) => switch (ComponentRegistry.named(
    item.kind,
  )) {
    ComponentRegistry.android => AppWidgetView(item: item),
    _ => of(item.kind, {...item.options, 'style': item.style}, shrink: shrink),
  };
}
