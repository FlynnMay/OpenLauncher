import 'package:openlauncher/core/config/migrations/save_json.dart';

// What a template wrote for each of the values the launcher had of its
// own, and what it writes now that each is an entity read by its id.
final _whole = {
  RegExp(r'\{\{\s*time\s*(?=[|}])'): '{{clock.time ',
  RegExp(r'\{\{\s*date\s*(?=[|}])'): '{{clock.date ',
};
final _part = RegExp(r'\{\{\s*(time|date|nowPlaying)\s*(?=\.)');

String _rewritten(String text) {
  var next = text;
  // A time or a date written to a pattern is the clock written to it.
  next = next.replaceAllMapped(
    RegExp(r'\{\{\s*(?:time|date)\s*(\|\s*format\s*:)'),
    (match) => '{{clock ${match[1]}',
  );
  for (final MapEntry(key: was, value: now) in _whole.entries) {
    next = next.replaceAll(was, now);
  }
  next = next.replaceAllMapped(
    _part,
    (match) => match[1] == 'nowPlaying' ? '{{media' : '{{clock',
  );
  return next
      .replaceAll(RegExp(r'\{\{\s*nowPlaying\s*(?=[|}])'), '{{media ')
      .replaceAll(' }}', '}}');
}

/// Every text in [json], however deep, as a template now writes it.
Object? _templates(Object? json) => switch (json) {
  final String text when text.contains('{{') => _rewritten(text),
  final Map<Object?, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries) '$key': _templates(value),
  },
  final List<Object?> list => [for (final value in list) _templates(value)],
  _ => json,
};

/// What plays was told what to do by the launcher, with which command
/// beside; now the media player is an entity that presents each command
/// as an action of its own.
void _mediaActs(Object? on) {
  if (on is! Json) return;
  for (final acts in on.values) {
    if (acts is! List<Object?>) continue;
    for (final act in acts) {
      if (act is Json && act['do'] == 'media') {
        act['do'] = switch (act.remove('command')) {
          final String command => command,
          _ => 'playPause',
        };
        act['entity'] = 'media';
      }
    }
  }
}

/// The values the launcher had of its own are entities: `{{time}}` is
/// `{{clock.time}}`, `{{date.weekday}}` is `{{clock.weekday}}`, and what
/// was `nowPlaying` is `media`, the media player, whose commands are its
/// own actions.
void valuesAsEntities(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout != null) {
    for (final pane in panesOf(layout)) {
      for (final item in itemsOf(pane)) {
        _mediaActs(item['on']);
        if (item['options'] case final Json options) {
          item['options'] = _templates(options);
        }
      }
    }
  }
  for (final prefab in objectsIn(save, 'prefabs')) {
    _mediaActs(prefab['on']);
    for (final key in ['parts', 'layouts']) {
      if (prefab[key] != null) prefab[key] = _templates(prefab[key]);
    }
  }
}
