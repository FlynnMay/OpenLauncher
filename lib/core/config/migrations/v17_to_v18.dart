import 'package:openlauncher/core/config/migrations/save_json.dart';

/// The single entity that did each action when none was named.
const _owners = {
  'setup': 'system',
  'homeButton': 'system',
  'tvSettings': 'system',
  'newLayer': 'layers',
  'toLayer': 'layers',
  'closeLayer': 'layers',
  'close': 'layers',
  'set': 'variables',
  'remove': 'layout',
  'playPause': 'media',
  'next': 'media',
  'previous': 'media',
};

void _walk(Object? json) {
  if (json is List) {
    json.forEach(_walk);
  } else if (json is Json) {
    if (json['on'] case final Json on) {
      for (final acts in on.values) {
        if (acts is! List) continue;
        for (final act in acts) {
          if (act is! Json) continue;
          final entity = act['entity'];
          if (entity is String && entity.isNotEmpty) continue;
          // The rest were done to what the tile was handed.
          act['entity'] = _owners[act['do']] ?? '{{source.id}}';
        }
      }
    }
    json.values.forEach(_walk);
  }
}

/// Every saved action names the entity that does it.
void actionsTargeted(Json save, Device device) {
  _walk(save['layout']);
  _walk(save['prefabs']);
}
