import 'package:openlauncher/core/config/migrations/save_json.dart';

Json _json(Object? json) => switch (json) {
  final Map<Object?, Object?> map => map.cast(),
  _ => {},
};

/// Old per-part overrides, with options split from style and `hidden`.
Json _overrides(Object? parts) => {
  for (final MapEntry(key: id, value: set) in _json(parts).entries)
    if (set is Map)
      id: {
        'hidden': ?set['hidden'],
        if (set['style'] is Map) 'style': set['style'],
        if (_json(set)
              ..removeWhere((key, _) => key == 'hidden' || key == 'style')
            case final options when options.isNotEmpty)
          'options': options,
      },
};

/// Size and position as a transform.
Json _transform(Json from, [List<String> keys = const ['w', 'h', 'x', 'y']]) =>
    {
      for (final key in keys)
        if (from[key] case final num value
            when !(value == 1 && key.length == 1 && 'wh'.contains(key)))
          key: value,
    };

void _put(Json into, String key, Object? value) {
  if (value == null || value is Map && value.isEmpty || value == '') return;
  into[key] = value;
}

/// A pane as a component: settings become options, items children.
Json _pane(Json pane, Json transform) {
  final rules = <String, Object?>{
    for (final MapEntry(key: prefab, value: rule) in _json(
      pane['prefabRules'],
    ).entries)
      if (rule is Map)
        prefab: {
          'variant': ?rule['layout'],
          if (_overrides(rule['parts']) case final overrides
              when overrides.isNotEmpty)
            'overrides': overrides,
        },
  };
  final component = <String, Object?>{'id': pane['id'], 'kind': 'pane'};
  _put(component, 'transform', transform);
  _put(component, 'options', {
    if (pane['title'] case final String title when title.isNotEmpty)
      'title': title,
    'mode': pane['mode'] ?? 'flow',
    'columns': pane['columns'] ?? 5,
    ..._json(pane['rules']),
    if (rules.isNotEmpty) 'prefabRules': rules,
  });
  for (final key in const ['vars', 'style', 'on']) {
    _put(component, key, pane[key]);
  }
  component['children'] = [for (final item in itemsOf(pane)) _item(item)];
  return component;
}

/// A layout item as a component.
Json _item(Json item) {
  final transform = _transform(item);
  if (item['pane'] case final Json pane) return _pane(pane, transform);
  final options = _json(item['options']);
  final component = <String, Object?>{'id': item['id']};
  if (item['kind'] == 'prefab') {
    component['prefab'] = item['ref'];
    _put(component, 'variant', options.remove('layout'));
    _put(component, 'overrides', _overrides(options.remove('parts')));
  } else {
    component['kind'] = item['ref'];
  }
  _put(component, 'transform', transform);
  _put(component, 'options', options);
  for (final key in const ['vars', 'style', 'on']) {
    _put(component, key, item[key]);
  }
  return component;
}

/// Panes and items become components; a panel's pane becomes its `root`.
void everythingAComponent(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout == null) return;
  for (final panel in panelsOf(layout)) {
    if (panel.remove('pane') case final Json pane) {
      panel['root'] = _pane(pane, const {});
    }
  }
}

/// One slot of an old prefab layout: a part or a group.
Json? _slot(Json slot, Json parts, int index) {
  final transform = <String, Object?>{
    ..._transform(slot, const ['flex', 'aspect']),
    if (slot['keep'] == true) 'keep': true,
  };
  if (slot['group'] case final Json group) {
    return {
      'id': 'group-${index + 1}',
      'kind': 'pane',
      if (transform.isNotEmpty) 'transform': transform,
      'options': _line(group),
      'children': _slots(group, parts),
    };
  }
  final part = _json(parts[slot['part']]);
  if (part['kind'] is! String) return null;
  final own = _json(slot['options']);
  final options = {...part, ...own}
    ..removeWhere((key, _) => key == 'kind' || key == 'style');
  final style = {..._json(part['style']), ..._json(own['style'])};
  return {
    'id': slot['part'],
    'kind': part['kind'],
    if (transform.isNotEmpty) 'transform': transform,
    if (options.isNotEmpty) 'options': options,
    if (style.isNotEmpty) 'style': style,
  };
}

List<Json> _slots(Json layout, Json parts) => [
  for (final (index, slot) in objectsIn(layout, 'parts').indexed)
    ?_slot(slot, parts, index),
];

/// An old prefab layout's arrangement as pane options.
Json _line(Json layout) => {
  'mode': layout['direction'] == 'row' ? 'row' : 'column',
  if (layout['gap'] case final num gap when gap > 0) 'gap': gap,
  if (layout['fit'] == true) 'fit': true,
  'align': ?layout['align'],
};

/// Every part an old layout placed, including those in groups.
Iterable<Json> _placed(Json layout) => objectsIn(layout, 'parts').expand(
  (slot) => switch (slot['group']) {
    final Json group => _placed(group),
    _ => [slot],
  },
);

/// Old prefabs (parts + layouts) become a root component from the first
/// layout, with each other layout as a variant. Later layouts keep the first
/// one's grouping.
void prefabsAsComponents(Json save, Device device) {
  final prefabs = objectsIn(save, 'prefabs');
  for (final prefab in prefabs) {
    final parts = _json(prefab.remove('parts'));
    final layouts = _json(prefab.remove('layouts'));
    final first = _json(layouts.values.firstOrNull);
    final transform = _transform(prefab, const ['w', 'h']);
    prefab['root'] = {
      'id': 'root',
      'kind': 'pane',
      if (transform.isNotEmpty) 'transform': transform,
      'options': _line(first),
      for (final key in const ['vars', 'style', 'on']) key: ?prefab.remove(key),
      'children': _slots(first, parts),
    };
    prefab
      ..remove('w')
      ..remove('h');
    prefab['variants'] = {
      for (final MapEntry(key: name, value: layout) in layouts.entries)
        name: {
          'label': _json(layout)['label'] ?? '',
          if (!identical(layout, layouts.values.first))
            'overrides': {
              'root': {
                'options': {'gap': 0, 'fit': false, ..._line(_json(layout))},
              },
              for (final slot in _placed(_json(layout)))
                if (slot['part'] case final String id)
                  id: {
                    'transform': {
                      'flex': slot['flex'] ?? 0,
                      'aspect': slot['aspect'] ?? 0,
                      'keep': slot['keep'] == true,
                    },
                    if (_json(slot['options']) case final options
                        when options.isNotEmpty) ...{
                      if (options['style'] is Map) 'style': options['style'],
                      if (options..remove('style') case final rest
                          when rest.isNotEmpty)
                        'options': rest,
                    },
                  },
            },
        },
    };
  }
}
