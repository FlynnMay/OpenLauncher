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
  }) => switch (ComponentKind.named(kind)) {
    ComponentKind.text => TextComponent(options: options, shrink: shrink),
    ComponentKind.picture => PictureComponent(options: options),
    ComponentKind.meter => MeterComponent(options: options),
    ComponentKind.button => ButtonComponent(options: options),
    ComponentKind.icon => IconComponent(options: options),
    ComponentKind.folder => FolderPicture(options: options),
    // App widgets need their component's id; unknown kinds draw nothing.
    ComponentKind.android || null => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) => switch (ComponentKind.named(
    item.kind,
  )) {
    ComponentKind.android => AppWidgetView(item: item),
    _ => of(item.kind, {...item.options, 'style': item.style}, shrink: shrink),
  };
}
