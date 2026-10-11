import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/entities/entity_action.dart';
import 'package:openlauncher/core/entities/http_feed.dart';
import 'package:openlauncher/core/layers/layers.dart';
import 'package:openlauncher/core/values/date_format.dart';
import 'package:openlauncher/core/values/value_providers.dart';

/// Reads an entity's live values, re-run when what it watches changes. A map
/// is laid over the entity's data, with `text` as the whole-value form;
/// anything else is the value itself.
typedef FeedRead = Object? Function(Ref ref, Entity entity, Feed feed);

/// Where live values can come from, by the name a [Feed] says. A new one is
/// one entry here.
final Map<String, FeedRead> feeds = {
  'clock': (ref, entity, feed) {
    final now = ref.watch(tickProvider(true));
    final time = formatDateTime(now, 'HH:mm');
    return {
      'text': time,
      'time': time,
      'date': formatDateTime(now, 'EEEE d MMMM'),
      'hour': now.hour,
      'minute': now.minute,
      'second': now.second,
      'hour12': now.hour % 12 == 0 ? 12 : now.hour % 12,
      'ampm': now.hour < 12 ? 'am' : 'pm',
      'weekday': dayNames[now.weekday - 1],
      'day': now.day,
      'month': now.month,
      'monthName': monthNames[now.month - 1],
      'year': now.year,
      'epoch': now.millisecondsSinceEpoch,
    };
  },
  'weather': (ref, entity, feed) {
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
  'location': (ref, entity, feed) {
    final place = _place(ref);
    if (place == null) return const {'text': null};
    return {
      'text': place.name,
      'name': place.name,
      'latitude': place.latitude,
      'longitude': place.longitude,
    };
  },
  'media': (ref, entity, feed) {
    final playing = ref.watch(nowPlayingProvider).value;
    if (playing == null) {
      return const {'text': null, 'playing': false};
    }
    return {
      'text': playing.title ?? playing.appLabel,
      'title': playing.title,
      'artist': playing.artist,
      'app': playing.appLabel,
      'playing': playing.playing,
      'art': playing.artPath,
    };
  },
  // The saved layers and those made since.
  'layers': (ref, entity, feed) => {
    'count':
        ref.watch(layersProvider).length +
        ref.watch(
          configProvider.select(
            (config) => config.value?.layout.layers.length ?? 1,
          ),
        ),
  },
  // A web address, asked again every so many seconds; its answer is the
  // value.
  httpFeed: (ref, entity, feed) => switch (HttpFeed.of(entity)) {
    null => null,
    final asked => ref.watch(feedValueProvider(asked)).value,
  },
};

Place? _place(Ref ref) =>
    ref.watch(configProvider.select((config) => config.value?.place));
