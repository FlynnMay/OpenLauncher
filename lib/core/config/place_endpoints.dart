import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/weather.dart';
import 'package:openlauncher/core/config/config_controller.dart';
import 'package:openlauncher/core/endpoints/source_endpoint.dart';

/// To be deleted: weather and the saved place need nothing only the launcher
/// can do, so they move into the system pack as data.
final Map<String, SourceEndpoint> placeEndpoints = {
  'launcher://weather': (ref, watch) {
    final place = _place(ref);
    final weather = place == null
        ? null
        : ref
              .watch(
                weatherProvider((
                  latitude: place.latitude,
                  longitude: place.longitude,
                  fahrenheit: false,
                )),
              )
              .value;
    if (weather == null) return const {'text': null};
    return {
      'text': '${weather.temperature.round()}°',
      'temperature': weather.temperature,
      'high': weather.high,
      'low': weather.low,
      'description': weather.description,
      'sky': weather.sky.name,
      'place': place!.name,
    };
  },
  'launcher://location': (ref, watch) {
    final place = _place(ref);
    if (place == null) return const {'text': null};
    return {
      'text': place.name,
      'name': place.name,
      'latitude': place.latitude,
      'longitude': place.longitude,
    };
  },
};

Place? _place(Ref ref) =>
    ref.watch(configProvider.select((config) => config.value?.place));
