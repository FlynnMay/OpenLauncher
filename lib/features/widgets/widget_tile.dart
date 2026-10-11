import 'package:flutter/material.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/features/widgets/app_widget.dart';
import 'package:openlauncher/features/widgets/clock_widget.dart';
import 'package:openlauncher/features/widgets/media_widget.dart';
import 'package:openlauncher/features/widgets/primitive_widgets.dart';
import 'package:openlauncher/features/widgets/weather_widget.dart';

/// Draws the widget a layout item stands for. Widgets have no card behind
/// them: they sit straight on the wallpaper.
class WidgetTile extends StatelessWidget {
  const WidgetTile({super.key, required this.item, this.compact = false});

  final LayoutItem item;

  /// True in a closed rail, where a widget gets a small square.
  final bool compact;

  @override
  Widget build(BuildContext context) => switch (WidgetKind.named(item.ref)) {
    WidgetKind.clock => ClockWidget(options: item.options),
    WidgetKind.weather => WeatherWidget(options: item.options),
    WidgetKind.media => MediaWidget(compact: compact),
    WidgetKind.android => AppWidgetView(item: item),
    WidgetKind.text => TextWidget(options: item.options),
    WidgetKind.picture => PictureWidget(options: item.options),
    WidgetKind.meter => MeterWidget(options: item.options),
    WidgetKind.button => ButtonWidget(options: item.options),
    // Made by a newer version of the launcher.
    null => const SizedBox.shrink(),
  };
}
