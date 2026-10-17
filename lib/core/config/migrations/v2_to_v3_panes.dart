import 'package:openlauncher/core/config/migrations/save_json.dart';

/// Nothing docks in the box of what opens it any more: such a node docks in
/// the middle. A folder's picture is any node's picture.
void inlineDocksCentred(Json save, Device device) {
  void walk(Json node) {
    if (node['modules'] case {
      'dock': {'position': 'inline'} && final Json dock,
    }) {
      dock['position'] = 'center';
    }
    if (node['modules'] case {'variables': final Json vars}) {
      for (final value in vars.values) {
        for (final held in value is List ? value : const []) {
          if (held is Json) walk(held);
        }
      }
    }
    objectsIn(node, 'children').forEach(walk);
  }

  for (final layer in objectsIn(layoutOf(save) ?? const {}, 'layers')) {
    if (layer['root'] case final Json root) walk(root);
  }
  for (final prefab in objectsIn(save, 'prefabs')) {
    if (prefab['root'] case final Json root) walk(root);
  }
  if (save['iconOverrides'] case final Json pictures) {
    save['iconOverrides'] = {
      for (final MapEntry(:key, :value) in pictures.entries)
        key.startsWith('folder:') ? 'node:${key.substring(7)}' : key: value,
    };
  }
}

const _visuals = {'text', 'picture', 'icon', 'meter', 'appWidget', 'preview'};

/// A node that held others on cells or by transform and drew nothing was
/// given a box by the launcher: padding 16, corners 14, what is in it
/// clipped, its name as a heading. That box is written out, and one on cells
/// with a name is an instance of the System pack's Section, which draws
/// the heading. A layer's root, never drawn with a box, stays as it is; so do
/// instances, and a prefab's root but for its box.
void panelsWrittenOut(Json save, Device device) {
  bool panel(Json node) {
    final modules = _json(node['modules']);
    final mode = _json(modules['layout'])['mode'];
    return node['prefab'] == null &&
        !modules.keys.any(_visuals.contains) &&
        mode != 'row' &&
        mode != 'column';
  }

  Json boxed(Json node) {
    final modules = node['modules'] = {..._json(node['modules'])};
    final style = {..._json(modules['style'])};
    final paints =
        style['background'] != null ||
        style['borderColor'] != null ||
        (style['shadow'] is num && style['shadow'] != 0);
    modules['style'] = {
      ...style,
      if (!style.containsKey('padding')) 'padding': 16,
      if (paints && !style.containsKey('radius')) 'radius': 14,
      if (!style.containsKey('clip')) 'clip': true,
    };
    return node;
  }

  Json headed(Json node) {
    final modules = _json(node['modules']);
    const laidOut = {'layout', 'scroll', 'prefabRules'};
    return {
      'id': node['id'],
      'name': node['name'],
      'prefab': 'system:section',
      'transform': ?node['transform'],
      'hidden': ?node['hidden'],
      'overrides': {
        // A name that reads variables is read where the heading is.
        if ((node['name']! as String).contains('{{'))
          'heading': {
            'modules': {
              'text': {'text': node['name']},
            },
          },
        'content': {
          'modules': {
            for (final module in laidOut) module: ?modules[module],
            // The Section scrolls down; one that did not says so.
            'scroll': {'down': false, ..._json(modules['scroll'])},
          },
        },
      },
      'modules': {
        for (final MapEntry(:key, :value) in modules.entries)
          if (!laidOut.contains(key)) key: value,
        'variables': {
          ..._json(modules['variables']),
          'content': objectsIn(node, 'children'),
        },
      },
    };
  }

  Json walk(Json node, {bool root = false}) {
    if (node['children'] is List<Object?>) {
      node['children'] = [
        for (final child in objectsIn(node, 'children')) walk(child),
      ];
    }
    final modules = _json(node['modules']);
    if (modules['variables'] case final Json vars) {
      for (final MapEntry(:key, :value) in vars.entries) {
        if (value is List<Object?>) {
          vars[key] = [
            for (final held in value)
              if (held is Json) walk(held) else held,
          ];
        }
      }
    }
    if (root || !panel(node)) return node;
    final mode = _json(modules['layout'])['mode'];
    final named = node['name'] is String && node['name'] != '';
    return named && mode != null ? headed(node) : boxed(node);
  }

  for (final layer in objectsIn(layoutOf(save) ?? const {}, 'layers')) {
    if (layer['root'] case final Json root) {
      layer['root'] = walk(root, root: true);
    }
  }
  for (final prefab in objectsIn(save, 'prefabs')) {
    if (prefab['root'] case final Json root) {
      prefab['root'] = panel(root)
          ? boxed(walk(root, root: true))
          : walk(root, root: true);
    }
  }
}

Json _json(Object? value) => value is Json ? value : <String, Object?>{};
