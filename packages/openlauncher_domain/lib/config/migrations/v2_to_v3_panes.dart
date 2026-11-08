import 'package:openlauncher_domain/config/migrations/save_json.dart';

void inlineDocksCentred(Json save, Device device) {
  layerRoots(save).forEach(_inlineDocksCentredIn);
  prefabRoots(save).forEach(_inlineDocksCentredIn);
  if (save['iconOverrides'] case final Json pictures) {
    save['iconOverrides'] = {
      for (final MapEntry(:key, :value) in pictures.entries)
        key.startsWith('folder:') ? 'node:${key.substring(7)}' : key: value,
    };
  }
}

void _inlineDocksCentredIn(Json node) {
  if (node['modules'] case {
    'dock': {'position': 'inline'} && final Json dock,
  }) {
    dock['position'] = 'center';
  }
  _heldNodes(node).forEach(_inlineDocksCentredIn);
  objectsIn(node, 'children').forEach(_inlineDocksCentredIn);
}

Iterable<Json> _heldNodes(Json node) => switch (node['modules']) {
  {'variables': final Json variables} =>
    variables.values.whereType<List<Object?>>().expand(
      (held) => held.whereType<Json>(),
    ),
  _ => const [],
};

const _visuals = {'text', 'picture', 'icon', 'meter', 'appWidget', 'preview'};

void panelsWrittenOut(Json save, Device device) {
  for (final layer in objectsIn(layoutOf(save) ?? const {}, 'layers')) {
    if (layer['root'] case final Json root) {
      layer['root'] = _panelsWrittenOutIn(root, isRoot: true);
    }
  }
  for (final prefab in objectsIn(save, 'prefabs')) {
    if (prefab['root'] case final Json root) {
      final isPanel = _isPanel(root);
      final written = _panelsWrittenOutIn(root, isRoot: true);
      prefab['root'] = isPanel ? _boxed(written) : written;
    }
  }
}

Object? _layoutMode(Json node) =>
    jsonObject(jsonObject(node['modules'])['layout'])['mode'];

bool _isPanel(Json node) {
  final modules = jsonObject(node['modules']);
  final mode = _layoutMode(node);
  return node['prefab'] == null &&
      !modules.keys.any(_visuals.contains) &&
      mode != 'row' &&
      mode != 'column';
}

Json _panelsWrittenOutIn(Json node, {bool isRoot = false}) {
  if (node['children'] is List<Object?>) {
    node['children'] = [
      for (final child in objectsIn(node, 'children'))
        _panelsWrittenOutIn(child),
    ];
  }
  if (jsonObject(node['modules'])['variables'] case final Json variables) {
    _heldPanelsWrittenOut(variables);
  }
  if (isRoot || !_isPanel(node)) return node;
  final named = node['name'] is String && node['name'] != '';
  return named && _layoutMode(node) != null ? _asSection(node) : _boxed(node);
}

void _heldPanelsWrittenOut(Json variables) {
  for (final key in [...variables.keys]) {
    if (variables[key] case final List<Object?> held) {
      variables[key] = _listPanelsWrittenOut(held);
    }
  }
}

List<Object?> _listPanelsWrittenOut(List<Object?> held) => [
  for (final item in held)
    if (item is Json) _panelsWrittenOutIn(item) else item,
];

Json _boxed(Json node) {
  final modules = node['modules'] = {...jsonObject(node['modules'])};
  final style = {...jsonObject(modules['style'])};
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

Json _asSection(Json node) {
  final modules = jsonObject(node['modules']);
  return {
    'id': node['id'],
    'name': node['name'],
    'prefab': 'system:section',
    'transform': ?node['transform'],
    'hidden': ?node['hidden'],
    'overrides': {
      if (_readsVariables(node['name']! as String))
        'heading': {
          'modules': {
            'text': {'text': node['name']},
          },
        },
      'content': {
        'modules': {
          for (final module in slotLayoutModules) module: ?modules[module],
          // The Section scrolls down by default; this one did not.
          'scroll': {'down': false, ...jsonObject(modules['scroll'])},
        },
      },
    },
    'modules': {
      ...without(modules, slotLayoutModules),
      'variables': {
        ...jsonObject(modules['variables']),
        'content': objectsIn(node, 'children'),
      },
    },
  };
}

bool _readsVariables(String text) => text.contains('{{');
