import 'dart:math';

import 'package:openlauncher/core/config/migrations/save_json.dart';

const _edges = {'left', 'right', 'top', 'bottom'};
const _layers = {'entity': 'layers'};

Json _set(bool open) => {
  'do': 'set',
  'entity': 'variables',
  'var': 'open',
  'value': open,
};

/// What a sidebar did of itself: open while focused, on its own layer.
Json _barChains() => {
  'focus': [_set(true)],
  'blur': [_set(false)],
  'reveal': [
    {'do': 'newLayer', ..._layers},
    {'do': 'toLayer', ..._layers},
  ],
  'hide': [
    {'do': 'closeLayer', ..._layers},
  ],
};

/// What a hovering folder did of itself.
Json _folderChains() => {
  'reveal': [
    {'do': 'newLayer', ..._layers, 'dim': 0.54, 'modal': true},
    {'do': 'toLayer', ..._layers},
  ],
  'hide': [
    {'do': 'closeLayer', ..._layers},
  ],
};

Json _map(Object? json) => json is Json ? json : <String, Object?>{};

/// [panel] as a docked pane: its root pane under the panel's id, with the
/// panel's title and rules as options and its chains written out. Null for an
/// untouched empty sidebar.
Json? _docked(Json panel) {
  final id = panel['id'];
  if (id is! String) return null;
  final pane = _map(panel['root']);
  final rules = _map(panel['rules']);
  final options = {..._map(pane['options'])};
  final style = {..._map(pane['style'])};
  final children = pane['children'] is List ? pane['children'] : <Object?>[];
  if (panel['title'] case final String title when title.isNotEmpty) {
    options['title'] = title;
  }
  options['mode'] ??= 'flow';
  final Json chains;
  if (_edges.contains(id)) {
    if ((children as List).isEmpty && rules.isEmpty) return null;
    final side = id == 'left' || id == 'right';
    options['columns'] ??= side ? 1 : 8;
    options['dock'] = id;
    // The closed size was the edge's own when unset.
    options['closed'] = rules['closed'] ?? (side ? 96 : 0);
    for (final key in const ['width', 'height', 'opening', 'reveal']) {
      if (rules[key] != null) options[key] = rules[key];
    }
    chains = _barChains();
  } else {
    final position = switch (rules['position']) {
      'bottom' => 'bottom',
      'left' => 'left',
      'right' => 'right',
      'inline' => 'inline',
      _ => 'center',
    };
    final step = switch (rules['size']) {
      'small' => 0,
      'large' => 2,
      _ => 1,
    };
    options['columns'] ??= 4;
    options['dock'] = position;
    options['opening'] = 'instant';
    // Sizes were fractions of a 960x540 screen.
    switch (position) {
      case 'bottom':
        options['height'] = const [184, 270, 389][step];
      case 'left' || 'right':
        options['width'] = const [250, 346, 480][step];
      case 'center' when step != 1:
        options['width'] = const [432, 595, 826][step];
    }
    // The look every folder was drawn with.
    style['background'] ??= '#1a1c23fa';
    style['radius'] ??= switch (position) {
      'center' => 18,
      'inline' => 14,
      _ => 0,
    };
    final padding = style['padding'];
    style['padding'] = position == 'inline'
        ? padding ?? 12
        : min<num>(80, (padding is num ? padding : 0) + 28);
    chains = position == 'inline' ? {} : _folderChains();
    // The menu was titled after what it was opened for.
    if (id == 'quick-actions') options['title'] ??= '{{source.label}}';
  }
  final on = {...chains, ..._map(pane['on'])};
  return {
    ...pane,
    'id': id,
    'kind': 'pane',
    'options': options,
    if (style.isNotEmpty) 'style': style,
    if (on.isNotEmpty) 'on': on,
    'children': children,
  }..remove('transform');
}

/// Gives every component under [pane] an id not in [taken].
void _claim(Json pane, Set<String> taken) {
  for (final child in objectsIn(pane, 'children')) {
    if (child['id'] case final String id) {
      var free = id;
      for (var n = 2; !taken.add(free); n++) {
        free = '$id-$n';
      }
      child['id'] = free;
    }
    _claim(child, taken);
  }
}

/// The layout as layers: the home screen is the bottom one, and every
/// sidebar and folder a docked pane in it.
void panelsToLayers(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout == null) return;
  final panels = panelsOf(layout);
  final home = panels.where((panel) => panel['id'] == 'home').firstOrNull;
  final root = switch (home?['root']) {
    final Json root => root,
    _ => <String, Object?>{
      'id': 'home/root',
      'kind': 'pane',
      'options': {'mode': 'grid', 'columns': 12},
    },
  };
  final docked = [
    for (final panel in panels)
      if (panel != home) ?_docked(panel),
  ];
  // A folder and something on the screen could share an id; the folder
  // keeps it, since its cards name it.
  final taken = {'${root['id']}', for (final pane in docked) '${pane['id']}'};
  _claim(root, taken);
  for (final pane in docked) {
    _claim(pane, taken);
  }
  root['children'] = [...objectsIn(root, 'children'), ...docked];
  layout
    ..remove('panels')
    ..['layers'] = [
      {'id': 'home', 'root': root},
    ];
}

void _walk(Object? json) {
  if (json is List) {
    json.forEach(_walk);
  } else if (json is Json) {
    if (json['on'] case final Json on) {
      for (final acts in on.values) {
        if (acts is! List) continue;
        for (final act in acts) {
          if (act case {'entity': 'layout'}) (act as Json)['entity'] = 'home';
        }
      }
    }
    json.values.forEach(_walk);
  }
}

/// What was the one layout entity is the home layer's.
void layoutOfALayer(Json save, Device device) {
  _walk(save['layout']);
  _walk(save['prefabs']);
}

/// A folder's picture is kept under `folder:<id>`.
void folderPictures(Json save, Device device) {
  if (save['iconOverrides'] case final Json icons) {
    save['iconOverrides'] = {
      for (final MapEntry(:key, :value) in icons.entries)
        key.startsWith('panel:') ? 'folder:${key.substring(6)}' : key: value,
    };
  }
}
