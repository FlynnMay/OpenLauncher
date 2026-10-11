import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Fetches a JSON object from the internet. Replaced in tests.
final jsonFetcherProvider =
    Provider<Future<Map<String, Object?>> Function(Uri)>(
      (ref) => (uri) async {
        // The same on the TV and in a browser.
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          throw http.ClientException('Status ${response.statusCode}', uri);
        }
        final body = utf8.decode(response.bodyBytes);
        return (jsonDecode(body) as Map).cast<String, Object?>();
      },
    );

/// Which weather to show.
typedef WeatherQuery = ({double latitude, double longitude, bool fahrenheit});

enum Sky { clear, partlyCloudy, cloudy, fog, rain, snow, storm }

@immutable
class Weather {
  const Weather({
    required this.temperature,
    required this.code,
    this.high,
    this.low,
  });

  final double temperature;

  /// The WMO weather code.
  final int code;

  /// Today's highest and lowest temperature.
  final double? high, low;

  Sky get sky => switch (code) {
    0 || 1 => Sky.clear,
    2 => Sky.partlyCloudy,
    3 => Sky.cloudy,
    45 || 48 => Sky.fog,
    71 || 73 || 75 || 77 || 85 || 86 => Sky.snow,
    95 || 96 || 99 => Sky.storm,
    _ => Sky.rain,
  };

  String get description => switch (code) {
    0 => 'Clear',
    1 => 'Mostly clear',
    2 => 'Partly cloudy',
    3 => 'Cloudy',
    45 || 48 => 'Fog',
    51 || 53 || 55 || 56 || 57 => 'Drizzle',
    61 || 63 || 65 || 66 || 67 => 'Rain',
    71 || 73 || 75 || 77 => 'Snow',
    80 || 81 || 82 => 'Showers',
    85 || 86 => 'Snow showers',
    95 || 96 || 99 => 'Thunderstorm',
    _ => '',
  };

  factory Weather.fromJson(Map<String, Object?> json) {
    final current = json['current'];
    final daily = json['daily'];
    double? first(String key) => switch (daily is Map ? daily[key] : null) {
      [final num value, ...] => value.toDouble(),
      _ => null,
    };
    if (current case {
      'temperature_2m': final num temperature,
      'weather_code': final num code,
    }) {
      return Weather(
        temperature: temperature.toDouble(),
        code: code.toInt(),
        high: first('temperature_2m_max'),
        low: first('temperature_2m_min'),
      );
    }
    throw const FormatException('Unexpected weather reply');
  }
}

/// The weather at a place, from Open-Meteo (free, no account), refreshed
/// every half hour while something shows it.
final weatherProvider = FutureProvider.autoDispose
    .family<Weather, WeatherQuery>((ref, query) async {
      // Also retries after a failure, e.g. no network just after boot.
      final refresh = Timer(const Duration(minutes: 30), ref.invalidateSelf);
      ref.onDispose(refresh.cancel);
      final reply = await ref.watch(jsonFetcherProvider)(
        Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': '${query.latitude}',
          'longitude': '${query.longitude}',
          'current': 'temperature_2m,weather_code',
          'daily': 'temperature_2m_max,temperature_2m_min',
          'forecast_days': '1',
          'timezone': 'auto',
          if (query.fahrenheit) 'temperature_unit': 'fahrenheit',
        }),
      );
      return Weather.fromJson(reply);
    });

/// A place a weather component can be set to.
typedef Place = ({String name, double latitude, double longitude});

/// Looks up places called [name], best match first.
Future<List<Place>> findPlaces(
  Future<Map<String, Object?>> Function(Uri) fetch,
  String name,
) async {
  final reply = await fetch(
    Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': name,
      'count': '6',
      'format': 'json',
    }),
  );
  return [
    for (final result in (reply['results'] as List?) ?? const [])
      if (result case {
        'name': final String name,
        'latitude': final num latitude,
        'longitude': final num longitude,
      })
        (
          name: [
            name,
            if (result case {'admin1': final String region}) region,
            if (result case {'country': final String country}) country,
          ].join(', '),
          latitude: latitude.toDouble(),
          longitude: longitude.toDouble(),
        ),
  ];
}
