import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities_provider.dart';
import 'package:openlauncher/core/overlays/overlays.dart';
import 'package:openlauncher/core/updates/updates.dart';
import 'package:openlauncher/core/values/date_format.dart';
import 'package:openlauncher/core/values/value_providers.dart';

/// Answers a source at an address the launcher itself answers: plain values
/// and rows, pictures as file paths. [watch] reads it again when what it
/// reads changes; the live ones always do.
typedef SourceEndpoint = FutureOr<Object?> Function(Ref ref, bool watch);

/// What `os://<area>` (the TV) and `launcher://<area>` (the launcher) answer
/// as sources. A new one is one entry here; none is ever asked over the
/// network.
final Map<String, SourceEndpoint> sourceEndpoints = {
  'os://apps': (ref, watch) async => [
    for (final app in await _read(ref, installedAppsProvider.future, watch))
      {
        'package': app.packageName,
        'label': app.label,
        'icon': app.iconPath,
        'banner': app.isBanner,
      },
  ],
  'os://inputs': (ref, watch) async => [
    for (final input in await _read(ref, tvInputsProvider.future, watch))
      {'id': input.id, 'label': input.label, 'kind': input.kind.name},
  ],
  'launcher://clock': (ref, watch) {
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
  'os://media': (ref, watch) {
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
  'launcher://updates': (ref, watch) {
    final update = ref.watch(updateStateProvider);
    return {
      'text': update.current,
      'current': update.current,
      'latest': update.latest,
      'available': update.available,
      'status': update.status.name,
      'progress': update.progress,
      'notes': update.notes,
      'error': update.error,
    };
  },
  // What is open over the screen.
  'launcher://overlays': (ref, watch) => {
    'count': ref.watch(overlaysProvider).length,
  },
};

T _read<T>(Ref ref, ProviderListenable<T> provider, bool watch) =>
    watch ? ref.watch(provider) : ref.read(provider);

Place? _place(Ref ref) =>
    ref.watch(configProvider.select((config) => config.value?.place));
