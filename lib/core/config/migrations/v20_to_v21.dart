import 'package:openlauncher/core/config/migrations/save_json.dart';

/// The launcher's old icon names, as the Material pack calls them.
const _names = {
  'play': 'play_arrow',
  'pause': 'pause_circle',
  'next': 'skip_next',
  'previous': 'skip_previous',
  'info': 'info',
  'stop': 'cancel',
  'delete': 'delete',
  'add': 'add_circle',
  'remove': 'do_not_disturb_on',
  'menu': 'more_horiz',
  'folder': 'folder',
  'settings': 'settings',
  'close': 'close',
  'home': 'home',
  'apps': 'apps',
  'tv': 'tv',
  'star': 'star',
  'power': 'power_settings_new',
  'light': 'lightbulb',
  'music': 'music_note',
  'sun': 'sunny',
  'partly': 'partly_cloudy_day',
  'cloud': 'cloud',
  'fog': 'foggy',
  'rain': 'rainy',
  'snow': 'weather_snowy',
  'storm': 'thunderstorm',
};

Object? _named(Object? was) => switch (_names[was]) {
  final name? => 'material:$name',
  null => was,
};

void _walk(Object? json) {
  if (json is List) {
    json.forEach(_walk);
  } else if (json is Json) {
    if (json.containsKey('icon')) json['icon'] = _named(json['icon']);
    if (json['vars'] case final Json vars) {
      for (final MapEntry(key: name, value: variable) in vars.entries) {
        // Only a variable named for an icon is taken to hold one.
        if (!name.toLowerCase().contains('icon')) continue;
        if (variable is! Json) {
          vars[name] = _named(variable);
          continue;
        }
        for (final key in const ['value', 'else']) {
          if (variable.containsKey(key)) variable[key] = _named(variable[key]);
        }
        for (final one in objectsIn(variable, 'cases')) {
          one['then'] = _named(one['then']);
        }
      }
    }
    for (final MapEntry(:key, :value) in json.entries) {
      // An entity's `data.icon` is its picture, not an icon's name.
      if (key != 'data') _walk(value);
    }
  }
}

/// Icons are named by their set, `material:home`: buttons, icon components,
/// actions, and variables that choose an icon.
void iconsNamedBySet(Json save, Device device) {
  for (final key in const ['layout', 'prefabs', 'entities']) {
    _walk(save[key]);
  }
}
