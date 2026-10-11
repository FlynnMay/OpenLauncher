import 'package:openlauncher/core/config/migrations/save_json.dart';

Json _map(Json json, String key) {
  final map = <String, Object?>{
    if (json[key] case final Map<Object?, Object?> there) ...there.cast(),
  };
  json[key] = map;
  return map;
}

/// The clock, the weather and what plays were widgets of kinds of their
/// own; each is now an instance of a prefab, drawn from the entity that
/// has what it shows. What a widget was set to becomes what the instance
/// sets differently from its prefab, as far as that can be said: the hours
/// of a clock, whether its date shows, Fahrenheit.
///
/// A weather widget had a place of its own. The weather there is now is
/// that of the one place the launcher is told, which is the first such
/// widget's unless a place was told already.
void widgetsAsPrefabs(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout == null) return;
  for (final pane in panesOf(layout)) {
    for (final item in itemsOf(pane)) {
      if (item['kind'] != 'widget') continue;
      final was = switch (item.remove('options')) {
        final Json options => options,
        _ => <String, Object?>{},
      };
      final Json set = {};
      switch (item['ref']) {
        case 'clock':
          item['ref'] = item['source'] = 'clock';
          final hour24 = was['hour24'] != false;
          final seconds = was['seconds'] == true;
          if (!hour24 || seconds) {
            final pattern = [
              hour24 ? 'HH:mm' : 'h:mm',
              if (seconds) ':ss',
              if (!hour24) ' a',
            ].join();
            _map(_map(set, 'parts'), 'time')['text'] =
                '{{source | format:$pattern}}';
          }
          if (was['date'] == false) {
            _map(_map(set, 'parts'), 'date')['hidden'] = true;
          }
        case 'weather':
          item['ref'] = item['source'] = 'weather';
          if (save['place'] == null) {
            if (was case {
              'latitude': final num latitude,
              'longitude': final num longitude,
            }) {
              save['place'] = {
                'name': switch (was['place']) {
                  final String name => name,
                  _ => '',
                },
                'latitude': latitude,
                'longitude': longitude,
              };
            }
          }
          if (was['fahrenheit'] == true) {
            _map(_map(set, 'parts'), 'temperature')['text'] =
                '{{source.temperature | times:1.8 | plus:32 | round}}°';
          }
        case 'media':
          item['ref'] = 'now-playing';
          item['source'] = 'media';
        default:
          // Any other widget is what it was.
          if (was.isNotEmpty) item['options'] = was;
          continue;
      }
      item['kind'] = 'prefab';
      if (set.isNotEmpty) item['options'] = set;
    }
  }
}
