import 'package:openlauncher/core/config/migrations/save_json.dart';

/// A folder or sidebar template: its root's name and modules, what each
/// variant changes on the root, and the part, if not the root, that holds
/// the slot and lays out what is in it.
class _Template {
  const _Template({
    required this.name,
    required this.modules,
    this.variants = const {},
    this.part,
  });

  final String name;
  final Json modules;
  final Map<String, Json> variants;
  final String? part;

  /// The root's modules in [variant], or with none.
  Json rootModules(String? variant) =>
      variant == null ? modules : _merged(modules, variants[variant]!);

  /// The variant [copied] differs least from, the first on a tie.
  String? nearestVariant(Json copied) {
    if (variants.isEmpty) return null;
    final counts = {
      for (final variant in variants.keys)
        variant: _differenceCount(copied, rootModules(variant)),
    };
    return counts.keys.reduce(
      (nearest, variant) =>
          counts[variant]! < counts[nearest]! ? variant : nearest,
    );
  }
}

/// The System pack's folder and sidebar as 0.2.0 ships them.
const _systemTemplates = {
  'system:sidebar': _Template(
    name: '',
    modules: {
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
    variants: {
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
  ),
  'system:folder': _Template(
    name: 'Folder',
    part: 'content',
    modules: {
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
  ),
};

/// [base]'s modules with [over]'s values set, key by key.
Json _merged(Json base, Json over) => {
  ...base,
  for (final MapEntry(key: module, :value) in over.entries)
    module: {...jsonObject(base[module]), ...jsonObject(value)},
};

/// What [modules] set differently from [base], key by key within each
/// module; what [base] sets and they leave out is null, which unsets it.
Map<String, Json> _differences(Json modules, Json base) => {
  for (final module in {...modules.keys, ...base.keys})
    if (_valueDifferences(jsonObject(modules[module]), jsonObject(base[module]))
        case final changed when changed.isNotEmpty)
      module: changed,
};

Json _valueDifferences(Json values, Json base) => {
  for (final key in {...values.keys, ...base.keys})
    if (!jsonEquals(values[key], base[key])) key: values[key],
};

int _differenceCount(Json modules, Json base) => _differences(
  modules,
  base,
).values.fold(0, (count, changed) => count + changed.length);

/// A folder or sidebar copied from a template is an instance of that prefab,
/// holding what was in it in the prefab's `content` slot, and keeping only
/// what differs from the variant nearest it. Where it docks is its own. A
/// user's template becomes a plain prefab with that slot.
void templatesLinked(Json save, Device device) {
  final userTemplates = <String, _Template>{};
  for (final prefab in objectsIn(save, 'prefabs')) {
    if (prefab['id'] case final String id when prefab['template'] == true) {
      userTemplates[id] = _asSlotPrefab(prefab);
    }
  }
  final linker = _TemplateLinker(userTemplates);
  for (final root in layerRoots(save)) {
    linker.link(root);
  }
}

/// [prefab] made a plain prefab with a `content` slot on its root; returns
/// the template it was.
_Template _asSlotPrefab(Json prefab) {
  prefab.remove('template');
  final root = switch (prefab['root']) {
    final Json root => root,
    _ => <String, Object?>{},
  };
  final modules = root['modules'] = {...jsonObject(root['modules'])};
  modules['slot'] = {'variable': 'content'};
  modules['variables'] = {
    ...jsonObject(modules['variables']),
    'content': {'value': null, 'type': 'nodes'},
  };
  return _Template(
    name: switch (root['name']) {
      final String name => name,
      _ => '',
    },
    modules: without(modules, {'slot', 'variables'}),
    variants: {
      for (final MapEntry(:key, :value) in jsonObject(
        prefab['variants'],
      ).entries)
        key: _overriddenModules(jsonObject(value), root['id']),
    },
  );
}

/// The modules [variant] overrides on node [id].
Json _overriddenModules(Json variant, Object? id) {
  final overrides = jsonObject(variant['overrides']);
  return jsonObject(jsonObject(overrides[id])['modules']);
}

/// Turns copies of templates into instances of their prefabs.
class _TemplateLinker {
  _TemplateLinker(this.userTemplates);

  final Map<String, _Template> userTemplates;

  /// [pane], or the instance it is if it was copied from a template.
  Json link(Json pane) {
    if (pane['children'] is List<Object?>) {
      pane['children'] = [
        for (final child in objectsIn(pane, 'children')) link(child),
      ];
    }
    if (pane['template'] case final String prefab) {
      final template = _systemTemplates[prefab] ?? userTemplates[prefab];
      if (template != null) return _instance(pane, template, prefab);
      pane.remove('template');
    }
    return pane;
  }

  /// [copy] as an instance of [prefab]. How what is in it is laid out is
  /// the slot's part's.
  Json _instance(Json copy, _Template template, String prefab) {
    final modules = jsonObject(copy['modules']);
    final variant = template.nearestVariant(modules);
    final differences = _differences(modules, template.rootModules(variant));
    final part = template.part;
    bool laysOut(String module) => part != null && slotModules.contains(module);
    final changed = {
      for (final MapEntry(:key, :value) in differences.entries)
        if (!laysOut(key)) key: value,
    };
    final slotted = {
      for (final MapEntry(:key, :value) in differences.entries)
        if (laysOut(key)) key: value,
    };
    final dock = jsonObject(modules['dock'])['position'];
    final name = copy['name'];
    return {
      'id': copy['id'],
      if (name is String && name.isNotEmpty && name != template.name)
        'name': name,
      'prefab': prefab,
      if (variant != null && variant != template.variants.keys.first)
        'variant': variant,
      'transform': ?copy['transform'],
      'hidden': ?copy['hidden'],
      if (part != null && slotted.isNotEmpty)
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
}
