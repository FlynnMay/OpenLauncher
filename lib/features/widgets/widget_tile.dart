import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/features/widgets/app_widget.dart';
import 'package:openlauncher/features/widgets/clock_widget.dart';
import 'package:openlauncher/features/widgets/media_widget.dart';
import 'package:openlauncher/features/widgets/primitive_widgets.dart';
import 'package:openlauncher/features/widgets/weather_widget.dart';

/// Draws the widget a layout item stands for. Widgets have no entity behind
/// them: they sit straight on the wallpaper.
class WidgetTile extends StatelessWidget {
  const WidgetTile({super.key, required this.item, this.compact = false});

  final LayoutItem item;

  /// True in a closed rail, where a widget gets a small square.
  final bool compact;

  /// The widget of the kind called [kind], set up by [options]. [shrink]
  /// has one that can take only the room it needs do so.
  static Widget of(
    String kind,
    Map<String, Object?> options, {
    bool shrink = false,
  }) => switch (WidgetKind.named(kind)) {
    WidgetKind.clock => ClockWidget(options: options),
    WidgetKind.weather => WeatherWidget(options: options),
    WidgetKind.media => const MediaWidget(),
    WidgetKind.text => TextWidget(options: options, shrink: shrink),
    WidgetKind.picture => PictureWidget(options: options),
    WidgetKind.meter => MeterWidget(options: options),
    WidgetKind.button => ButtonWidget(options: options),
    // Needs the item it is, which the device knows it by; and what was
    // made by a newer version of the launcher.
    WidgetKind.android || null => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) => switch (WidgetKind.named(item.ref)) {
    WidgetKind.android => AppWidgetView(item: item),
    WidgetKind.media => MediaWidget(compact: compact),
    _ => of(item.ref, item.options),
  };
}
