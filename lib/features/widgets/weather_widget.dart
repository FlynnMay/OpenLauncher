import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/widgets/widgets.dart';

/// Current conditions at a place chosen on the config page.
///
/// Options: `latitude`, `longitude`, `place` (its name), `fahrenheit`.
class WeatherWidget extends ConsumerWidget {
  const WeatherWidget({super.key, required this.options});

  final Map<String, Object?> options;

  static IconData _icon(Sky sky) => switch (sky) {
    Sky.clear => Icons.wb_sunny_outlined,
    Sky.partlyCloudy => Icons.wb_cloudy_outlined,
    Sky.cloudy => Icons.cloud_outlined,
    Sky.fog => Icons.foggy,
    Sky.rain => Icons.water_drop_outlined,
    Sky.snow => Icons.ac_unit,
    Sky.storm => Icons.thunderstorm_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const quiet = TextStyle(color: Colors.white70, fontSize: 14);
    final latitude = options['latitude'], longitude = options['longitude'];
    if (latitude is! num || longitude is! num) {
      return const FittedBox(
        child: Text(
          'Choose a place for the weather\non the web page',
          style: quiet,
        ),
      );
    }
    final weather = ref.watch(
      weatherProvider((
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        fahrenheit: options['fahrenheit'] == true,
      )),
    );
    final place = options['place'];
    return FittedBox(
      child: switch (weather) {
        AsyncData(:final value) => Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 14,
          children: [
            Icon(_icon(value.sky), color: Colors.white, size: 46),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${value.temperature.round()}°',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.w300,
                    height: 1.1,
                  ),
                ),
                Text(
                  [
                    value.description,
                    if ((value.high, value.low) case (final high?, final low?))
                      '${high.round()}° / ${low.round()}°',
                  ].where((part) => part.isNotEmpty).join('  ·  '),
                  style: quiet,
                ),
                if (place is String && place.isNotEmpty)
                  Text(place, style: quiet.copyWith(color: Colors.white54)),
              ],
            ),
          ],
        ),
        AsyncError() => const Text('Weather unavailable', style: quiet),
        _ => const Text('Loading weather…', style: quiet),
      },
    );
  }
}
