import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/values/data_source.dart';
import 'package:openlauncher/core/values/date_format.dart';
import 'package:openlauncher/core/values/template.dart';
import 'package:openlauncher/core/widgets/widgets.dart';

/// What time it is. Replaced in tests.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The time, told again as each second or each minute begins.
final _tickProvider = Provider.autoDispose.family<DateTime, bool>((
  ref,
  seconds,
) {
  final now = ref.watch(nowProvider)();
  final left = seconds
      ? 1000 - now.millisecond
      : 60000 - now.second * 1000 - now.millisecond;
  final next = Timer(Duration(milliseconds: left), ref.invalidateSelf);
  ref.onDispose(next.cancel);
  return now;
});

/// Asks a source's web address for its value: what it answers as JSON, or
/// as plain text where it is not JSON. In a browser the TV is asked to ask.
final sourceFetcherProvider = Provider<Future<Object?> Function(DataSource)>(
  (ref) => (source) async {
    final address = source.address;
    if (address == null) {
      throw const FormatException('Not a web address');
    }
    final response = await http
        .get(address, headers: const {'accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw http.ClientException('Status ${response.statusCode}', address);
    }
    if (response.bodyBytes.length > maxSourceBytes) {
      throw http.ClientException('Too much to take in', address);
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    try {
      return jsonDecode(body);
    } on FormatException {
      return body.trim();
    }
  },
);

/// The most a source may answer with.
const maxSourceBytes = 512 * 1024;

/// What a source of the user's last answered, asked again every so often
/// for as long as something shows it.
final sourceValueProvider = FutureProvider.autoDispose
    .family<Object?, DataSource>(
      (ref, source) async {
        // Also asks again after a failure.
        final again = Timer(
          Duration(seconds: source.every),
          ref.invalidateSelf,
        );
        ref.onDispose(again.cancel);
        return ref.watch(sourceFetcherProvider)(source);
      },
      // Once each time it is due, and no more.
      retry: (_, _) => null,
    );

/// What the root [root] of a template is now: one of the launcher's own
/// values, or a source of the user's by its id. Null while there is none.
final valueProvider = Provider.autoDispose.family<Object?, String>((ref, root) {
  T? config<T>(T Function(LauncherConfig config) of) => ref.watch(
    configProvider.select(
      (config) => switch (config.value) {
        null => null,
        final config => of(config),
      },
    ),
  );
  switch (root) {
    case 'time':
      final now = ref.watch(_tickProvider(true));
      return {
        'text': formatDateTime(now, 'HH:mm'),
        'hour': now.hour,
        'minute': now.minute,
        'second': now.second,
        'hour12': now.hour % 12 == 0 ? 12 : now.hour % 12,
        'ampm': now.hour < 12 ? 'am' : 'pm',
        'epoch': now.millisecondsSinceEpoch,
      };
    case 'date':
      final now = ref.watch(_tickProvider(false));
      return {
        'text': formatDateTime(now, 'EEEE d MMMM'),
        'weekday': dayNames[now.weekday - 1],
        'day': now.day,
        'month': now.month,
        'monthName': monthNames[now.month - 1],
        'year': now.year,
        'epoch': now.millisecondsSinceEpoch,
      };
    case 'nowPlaying':
      final playing = ref.watch(nowPlayingProvider).value;
      if (playing == null) return null;
      return {
        'text': playing.title ?? playing.appLabel,
        'title': playing.title,
        'artist': playing.artist,
        'app': playing.appLabel,
        'playing': playing.playing,
        'art': playing.artPath,
      };
    case 'location':
      final place = config((config) => config.place);
      if (place == null) return null;
      return {
        'text': place.name,
        'name': place.name,
        'latitude': place.latitude,
        'longitude': place.longitude,
      };
    case 'weather':
      final place = config((config) => config.place);
      if (place == null) return null;
      final weather = ref
          .watch(
            weatherProvider((
              latitude: place.latitude,
              longitude: place.longitude,
              fahrenheit: false,
            )),
          )
          .value;
      if (weather == null) return null;
      return {
        'text': '${weather.temperature.round()}°',
        'temperature': weather.temperature,
        'high': weather.high,
        'low': weather.low,
        'description': weather.description,
      };
  }
  final source = config(
    (config) => config.sources.where((source) => source.id == root).firstOrNull,
  );
  return switch (source) {
    null => null,
    DataSource(kind: SourceKind.text, :final text) => text,
    _ => ref.watch(sourceValueProvider(source)).value,
  };
});

/// How the template [source] reads now. Whatever watches it is told only
/// when that changes, however often the values under it do.
final templateProvider = Provider.autoDispose.family<String, String>((
  ref,
  source,
) {
  final template = Template.parse(source);
  final values = {
    for (final root in template.roots) root: ref.watch(valueProvider(root)),
  };
  return template.render((root) => values[root]);
});
