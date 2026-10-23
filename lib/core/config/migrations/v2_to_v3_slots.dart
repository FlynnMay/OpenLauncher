import 'package:openlauncher/core/config/migrations/save_json.dart';

/// The System pack's folder and sidebar as 0.2.0 ships them: the root's name
/// and modules, what each variant changes on the root, and the part, if not
/// the root, that holds the slot and lays out what is in it.
const Map<String, Json> _systemTemplates = {
  'system:sidebar': {
    'name': '',
    'modules': {
      'layout': {'mode': 'flow', 'columns': 8},
      'dock': {'position': 'top', 'closed': 0},
      'scroll': {'down': true},
      'triggers': {
        'focus': [
          {
            'run': 'launcher://variables/set',
            'with': {'var': 'open', 'value': true},
          },
        ],
        'blur': [
          {
            'run': 'launcher://variables/set',
            'with': {'var': 'open', 'value': false},
          },
        ],
        'reveal': [
          {'run': 'launcher://layers/new'},
          {'run': 'launcher://layers/raise'},
        ],
        'hide': [
          {'run': 'launcher://layers/close'},
        ],
      },
    },
    'variants': {
      'across': {},
      'side': {
        'layout': {'columns': 1, 'rowHeight': 36, 'itemW': 1, 'itemH': 1},
        'prefabRules': {
          'system:app-card': {'variant': 'row'},
          'system:folder-card': {'variant': 'row'},
        },
        'dock': {'position': 'left', 'closed': 96},
      },
    },
  },
  'system:folder': {
    'name': 'Folder',
    'part': 'content',
    'modules': {
      'layout': {'mode': 'flow', 'columns': 4},
      'dock': {
        'position': 'center',
        'opening': 'instant',
        'closeOnPress': true,
      },
      'scroll': {'down': true},
      'style': {'background': '#1a1c23fa', 'radius': 18, 'padding': 28},
      'triggers': {
        'reveal': [
          {
            'run': 'launcher://layers/new',
            'with': {'dim': 0.54, 'modal': true},
          },
          {'run': 'launcher://layers/raise'},
        ],
        'hide': [
          {'run': 'launcher://layers/close'},
        ],
      },
    },
    'variants': {},
  },
};

/// What lays out a slot's nodes, on the part that holds it.
const _slotModules = {'layout', 'scroll', 'prefabRules'};

bool _same(Object? a, Object? b) => switch ((a, b)) {
  (final Json a, final Json b) =>
    a.length == b.length &&
        a.entries.every((entry) => _same(entry.value, b[entry.key])),
  (final List<Object?> a, final List<Object?> b) =>
    a.length == b.length &&
        [for (var i = 0; i < a.length; i++) i].every((i) => _same(a[i], b[i])),
  _ => a == b,
};

/// [base]'s modules with [over]'s values set, key by key.
Json _merged(Json base, Json over) => {
  ...base,
  for (final MapEntry(key: module, :value) in over.entries)
    module: {...jsonObject(base[module]), ...jsonObject(value)},
};

/// What [modules] set differently from [base], key by key within each
/// module; what [base] sets and they leave out is null, which unsets it.
Json _differences(Json modules, Json base) => {
  for (final module in {...modules.keys, ...base.keys})
    if ({
          for (final key in {
            ...jsonObject(modules[module]).keys,
            ...jsonObject(base[module]).keys,
          })
            if (!_same(
              jsonObject(modules[module])[key],
              jsonObject(base[module])[key],
            ))
              key: jsonObject(modules[module])[key],
        }
        case final changed when changed.isNotEmpty)
      module: changed,
};

/// A folder or sidebar copied from a template is an instance of that prefab,
/// holding what was in it in the prefab's `content` slot, and keeping only
/// what differs from the variant nearest it. Where it docks is its own. A
/// user's template becomes a plain prefab with that slot.
void templatesLinked(Json save, Device device) {
  final own = <String, Json>{};
  for (final prefab in objectsIn(save, 'prefabs')) {
    if (prefab['id'] case final String id when prefab['template'] == true) {
      prefab.remove('template');
      final root = jsonObject(prefab['root']);
      final modules = root['modules'] = {...jsonObject(root['modules'])};
      modules['slot'] = {'variable': 'content'};
      modules['variables'] = {
        ...jsonObject(modules['variables']),
        'content': {'value': null, 'type': 'nodes'},
      };
      own[id] = {
        'name': root['name'] ?? '',
        'modules': {
          for (final MapEntry(:key, :value) in modules.entries)
            if (key != 'slot' && key != 'variables') key: value,
        },
        'variants': {
          for (final MapEntry(:key, :value) in jsonObject(
            prefab['variants'],
          ).entries)
            key: jsonObject(
              jsonObject(
                jsonObject(jsonObject(value)['overrides'])[root['id']],
              )['modules'],
            ),
        },
      };
    }
  }

  Json linked(Json copy, Json template, String prefab) {
    final modules = jsonObject(copy['modules']);
    final base = jsonObject(template['modules']);
    final variants = jsonObject(template['variants']);
    // The variant it differs least from; the first on a tie.
    String? nearest;
    var fewest = -1;
    for (final String? name in variants.isEmpty ? [null] : variants.keys) {
      final root = name == null
          ? base
          : _merged(base, jsonObject(variants[name]));
      final count = _differences(modules, root).values
          .map((set) => (set as Json).length)
          .fold(0, (sum, each) => sum + each);
      if (fewest < 0 || count < fewest) (nearest, fewest) = (name, count);
    }
    final root = nearest == null
        ? base
        : _merged(base, jsonObject(variants[nearest]));
    final all = _differences(modules, root);
    // How what is in it is laid out is the slot's part's.
    final part = template['part'];
    bool laysOut(String module) =>
        part is String && _slotModules.contains(module);
    final changed = {
      for (final MapEntry(:key, :value) in all.entries)
        if (!laysOut(key)) key: value,
    };
    final slotted = {
      for (final MapEntry(:key, :value) in all.entries)
        if (laysOut(key)) key: value,
    };
    final dock = jsonObject(modules['dock'])['position'];
    final name = copy['name'];
    return {
      'id': copy['id'],
      if (name is String && name.isNotEmpty && name != template['name'])
        'name': name,
      'prefab': prefab,
      if (nearest != null && nearest != variants.keys.first) 'variant': nearest,
      'transform': ?copy['transform'],
      'hidden': ?copy['hidden'],
      if (slotted.isNotEmpty)
        'overrides': {
          part: {'modules': slotted},
        },
      'modules': {
        ...changed,
        if (dock != null)
          'dock': {...jsonObject(changed['dock']), 'position': dock},
        'variables': {
          ...jsonObject(changed['variables']),
          'content': objectsIn(copy, 'children'),
        },
      },
    };
  }

  Json walk(Json pane) {
    if (pane['children'] is List<Object?>) {
      pane['children'] = [
        for (final child in objectsIn(pane, 'children')) walk(child),
      ];
    }
    return switch (pane) {
      {'template': final String prefab} => switch (_systemTemplates[prefab] ??
          own[prefab]) {
        final template? => linked(pane, template, prefab),
        null => pane..remove('template'),
      },
      _ => pane,
    };
  }

  for (final layer in objectsIn(layoutOf(save) ?? const {}, 'layers')) {
    if (layer['root'] case final Json root) walk(root);
  }
}
