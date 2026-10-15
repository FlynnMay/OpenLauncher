import 'package:openlauncher/core/config/migrations/save_json.dart';

const _addresses = {
  'launchApp': 'os://apps/launch',
  'openAppInfo': 'os://apps/info',
  'uninstallApp': 'os://apps/uninstall',
  'switchInput': 'os://inputs/switch',
  'mediaCommand': 'os://media/command',
  'openTvSettings': 'os://settings/open',
  'changeAccess': 'os://access/change',
  'openSettings': 'launcher://settings/open',
  'checkForUpdate': 'launcher://updates/check',
  'installUpdate': 'launcher://updates/install',
  'newLayer': 'launcher://layers/new',
  'toLayer': 'launcher://layers/raise',
  'closeLayer': 'launcher://layers/close',
  'closePopup': 'launcher://popups/close',
  'setVariable': 'launcher://variables/set',
  'addItem': 'launcher://layout/add',
  'removeItem': 'launcher://layout/remove',
};

/// Operations are named by address: the user's own actions run
/// `os://apps/launch` where they ran `launchApp`.
void operationsByAddress(Json save, Device device) {
  for (final entity in objectsIn(save, 'entities')) {
    if (entity['actions'] case final Json actions) {
      for (final action in actions.values) {
        if (action case {'run': final String run} as Json
            when _addresses.containsKey(run)) {
          action['run'] = _addresses[run];
        }
      }
    }
  }
}

const _feeds = {
  'clock': 'launcher://clock',
  'weather': 'launcher://weather',
  'location': 'launcher://location',
  'media': 'os://media',
  'updates': 'launcher://updates',
  'layers': 'launcher://layers',
};

const _layers = {
  'newLayer': 'launcher://layers/new',
  'toLayer': 'launcher://layers/raise',
  'closeLayer': 'launcher://layers/close',
  'close': 'launcher://popups/close',
};

const _layout = {
  'add': 'launcher://layout/add',
  'remove': 'launcher://layout/remove',
};

/// A feed is a source: `{from: http, url, every}` is written in place as
/// `{url, every}`, the launcher's own by address. The machinery entities
/// are gone: acts that asked `variables`, `layers` or a layer call the
/// address instead, and `system` is `device`.
void feedsAsSources(Json save, Device device) {
  for (final entity in objectsIn(save, 'entities')) {
    entity['feed'] = switch (entity['feed']) {
      {'from': 'http'} && final Json feed => {
        for (final MapEntry(:key, :value) in feed.entries)
          if (key != 'from') key: value,
      },
      {'from': final String from} when _feeds.containsKey(from) => _feeds[from],
      final other => other,
    };
    if (entity['feed'] == null) entity.remove('feed');
  }
  final layers = {
    for (final layer in objectsIn(layoutOf(save) ?? const {}, 'layers'))
      layer['id'],
  };

  Json? called(Json act) {
    final name = act['do'], entity = act['entity'];
    final address = switch (entity) {
      'variables' when name == 'set' => 'launcher://variables/set',
      'layers' => _layers[name],
      _ when layers.contains(entity) => _layout[name],
      _ => null,
    };
    if (address == null) return null;
    final told = {
      if (_layout.containsValue(address)) 'layer': entity,
      for (final MapEntry(:key, :value) in act.entries)
        if (key != 'do' && key != 'entity') key: value,
    };
    return {'run': address, if (told.isNotEmpty) 'with': told};
  }

  void walk(Object? json) {
    if (json is List<Object?>) {
      for (var i = 0; i < json.length; i++) {
        if (json[i] case final Json act when act['do'] is String) {
          if (called(act) case final next?) {
            json[i] = next;
            continue;
          }
          if (act['entity'] == 'system') act['entity'] = 'device';
        }
        walk(json[i]);
      }
    } else if (json is Json) {
      json.values.forEach(walk);
    }
  }

  walk(save);
}
