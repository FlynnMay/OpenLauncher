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

const _systemEntities = {
  'clock',
  'weather',
  'location',
  'media',
  'device',
  'updates',
};

const _systemPrefabs = {
  'app-card',
  'folder-card',
  'clock',
  'weather',
  'now-playing',
};

/// A pack's ids are `<pack>:<name>`, the launcher's own `system:`. Apps are
/// `system:app/<package>`, inputs `system:input/<id>`.
String? _entity(Object? id) => switch (id) {
  final String id when id.startsWith('app:') => 'system:app/${id.substring(4)}',
  final String id when id.startsWith('input:') =>
    'system:input/${id.substring(6)}',
  'launcher:settings' => 'system:settings',
  final String id when _systemEntities.contains(id) => 'system:$id',
  _ => null,
};

String? _prefab(Object? id) =>
    _systemPrefabs.contains(id) ? 'system:$id' : null;

final _slot = RegExp(r'\{\{(.*?)\}\}');
final _unquoted = RegExp('(\'[^\']*\'|"[^"]*")|[^\'"]+');
final _root = RegExp(r'(^|[\s(!=<>?:])([A-Za-z][\w-]*)(?=[.\s|\[]|$)');

/// [text] with the launcher's own entities given in full where a template
/// starts a value's path with one.
String _template(String text) => text.replaceAllMapped(
  _slot,
  (slot) =>
      '{{${slot[1]!.replaceAllMapped(_unquoted, (part) {
        if (part[1] != null) return part[0]!;
        return part[0]!.replaceAllMapped(_root, (root) => _systemEntities.contains(root[2]) ? '${root[1]}system:${root[2]}' : root[0]!);
      })}}}',
);

/// Every pack's ids carry its own: what the launcher ships is `system:...`.
/// Saved ids are given in full wherever an entity or a prefab is named.
void packIds(Json save, Device device) {
  Map<String, Object?> keyed(Object? map, {bool values = false}) => {
    if (map is Json)
      for (final MapEntry(:key, :value) in map.entries)
        _entity(key) ?? key: values ? _entity(value) ?? value : value,
  };
  for (final key in ['names', 'iconOverrides']) {
    if (save[key] is Json) save[key] = keyed(save[key]);
  }
  if (save['iconSources'] is Json) {
    save['iconSources'] = keyed(save['iconSources'], values: true);
  }
  if (layoutOf(save) case final layout? when layout['removed'] is List) {
    layout['removed'] = [
      for (final id in layout['removed']! as List) _entity(id) ?? id,
    ];
  }
  for (final prefab in objectsIn(save, 'prefabs')) {
    prefab['id'] = _prefab(prefab['id']) ?? prefab['id'];
  }

  Object? walk(Object? json) {
    if (json is String) return json.contains('{{') ? _template(json) : json;
    if (json is List<Object?>) {
      for (var i = 0; i < json.length; i++) {
        json[i] = walk(json[i]);
      }
      return json;
    }
    if (json is! Json) return json;
    for (final key in [...json.keys]) {
      final value = json[key];
      json[key] = switch ((key, value)) {
        ('prefab', _) => _prefab(value) ?? value,
        // What the layout adds or removes is an entity.
        ('with', final Json told)
            when '${json['run']}'.startsWith('launcher://layout/') =>
          (walk(told)! as Json)
            ..['what'] = _entity(told['what']) ?? told['what'],
        ('entity', _) when json['do'] is String =>
          _entity(value) ?? walk(value),
        ('prefabRules', final Json rules) => {
          for (final MapEntry(:key, :value) in rules.entries)
            _prefab(key) ?? key: walk(value),
        },
        ('vars', final Json vars) => {
          for (final MapEntry(:key, :value) in vars.entries)
            key: switch (value) {
              {'type': 'entity', 'value': final String id} && final Json v =>
                (walk(v)! as Json)..['value'] = _entity(id) ?? walk(id),
              _ => walk(value),
            },
        },
        _ => walk(value),
      };
    }
    return json;
  }

  for (final key in ['layout', 'prefabs', 'entities']) {
    if (save[key] != null) save[key] = walk(save[key]);
  }
}

/// What the launcher made the quick actions menu with.
const _menuOptions = {
  'title': '{{source.label}}',
  'mode': 'flow',
  'columns': 1,
  'dock': 'center',
  'width': 432,
  'opening': 'instant',
  'rowHeight': 40,
  'spacing': 4,
};

/// The quick actions menu is the System pack's prefab: the saved pane is
/// replaced by an instance of it, keeping the pane's own style and the
/// options it changed. Its buttons are the prefab's.
void quickActionsAsPrefab(Json save, Device device) {
  void walk(Json pane) {
    objectsIn(pane, 'children').forEach(walk);
    if (pane['children'] case final List<Object?> list) {
      for (var i = 0; i < list.length; i++) {
        if (list[i]
            case {'id': 'quick-actions', 'kind': 'pane'} && final Json menu) {
          final options = {
            if (menu['options'] case final Json options)
              for (final MapEntry(:key, :value) in options.entries)
                if (_menuOptions[key] != value) key: value,
          };
          list[i] = {
            'id': 'quick-actions',
            'prefab': 'system:quick-actions',
            if (options.isNotEmpty) 'options': options,
            if (menu['style'] case final Json style when style.isNotEmpty)
              'style': style,
          };
        }
      }
    }
  }

  for (final layer in objectsIn(layoutOf(save) ?? const {}, 'layers')) {
    if (layer['root'] case final Json root) walk(root);
  }
}

/// A new folder or sidebar records the template it was copied from: the
/// saved ones were the launcher's, now the System pack's. One docked with a
/// strip is a sidebar; any other docked pane, a folder.
void templatesRecorded(Json save, Device device) {
  void walk(Json pane) {
    final children = objectsIn(pane, 'children');
    for (final child in children) {
      if (child
          case {
            'kind': 'pane',
            'options': {'dock': final String _} && final Json options,
          }
          when !child.containsKey('template')) {
        child['template'] = options.containsKey('closed')
            ? 'system:sidebar'
            : 'system:folder';
      }
      walk(child);
    }
  }

  for (final layer in objectsIn(layoutOf(save) ?? const {}, 'layers')) {
    if (layer['root'] case final Json root) walk(root);
  }
}

/// A docked pane says itself whether a press closes it: the launcher closed
/// one with no strip, unless it was opened in place.
void closeOnPressRecorded(Json save, Device device) {
  void walk(Json pane) {
    if (pane
        case {
          'kind': 'pane',
          'options': {'dock': final String dock} && final Json options,
        }
        when dock != 'inline' && !options.containsKey('closed')) {
      options.putIfAbsent('closeOnPress', () => true);
    }
    objectsIn(pane, 'children').forEach(walk);
  }

  for (final layer in objectsIn(layoutOf(save) ?? const {}, 'layers')) {
    if (layer['root'] case final Json root) walk(root);
  }
  for (final prefab in objectsIn(save, 'prefabs')) {
    if (prefab['root'] case final Json root) walk(root);
  }
}
