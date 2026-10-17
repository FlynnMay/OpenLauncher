import 'dart:math';

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

/// What the parts of the System pack's prefabs drew, for overrides of them
/// saved outside the prefab.
const _systemParts = {
  'system:app-card': {'root': 'pane', 'picture': 'picture', 'name': 'text'},
  'system:clock': {'root': 'pane', 'time': 'text', 'date': 'text'},
  'system:folder-card': {'root': 'pane', 'picture': 'folder', 'name': 'text'},
  'system:folder': {'root': 'pane'},
  'system:now-playing': {
    'root': 'pane',
    'cover': 'picture',
    'lines': 'pane',
    'title': 'text',
    'summary': 'text',
    'state': 'icon',
  },
  'system:quick-actions': {
    'root': 'pane',
    'open': 'button',
    'info': 'button',
    'uninstall': 'button',
    'remove': 'button',
  },
  'system:sidebar': {'root': 'pane'},
  'system:weather': {
    'root': 'pane',
    'icon': 'icon',
    'lines': 'pane',
    'temperature': 'text',
    'summary': 'text',
    'place': 'text',
  },
};

const _scrollbarKeys = {
  'scrollbarSide',
  'scrollbarSize',
  'scrollbarLength',
  'scrollbarMargin',
  'scrollbarEndMargin',
  'scrollbarOpacity',
  'scrollbarThumb',
  'scrollbarThumbBorder',
  'scrollbarThumbBorderWidth',
  'scrollbarThumbRadius',
  'scrollbarInset',
  'scrollbarMinLength',
  'scrollbarTrack',
  'scrollbarTrackBorder',
  'scrollbarTrackBorderWidth',
  'scrollbarTrackRadius',
};

/// Where an option of a node of [kind] went: its module and key there. A
/// pane's title became the node's name (`null` module).
(String?, String)? _moved(String kind, String key) => switch ((kind, key)) {
  ('pane', 'title') => (null, 'name'),
  (
    'pane',
    'mode' ||
        'columns' ||
        'spacing' ||
        'rowHeight' ||
        'gap' ||
        'fit' ||
        'align' ||
        'itemW' ||
        'itemH',
  ) =>
    ('layout', key),
  ('pane', 'scrollX') => ('scroll', 'across'),
  ('pane', 'scrollY') => ('scroll', 'down'),
  ('pane', 'scrollbar') => ('scroll', 'bar'),
  ('pane', 'scrollbarShow') => ('scroll', 'show'),
  ('pane', 'dock') => ('dock', 'position'),
  (
    'pane',
    'width' || 'height' || 'closed' || 'closeOnPress' || 'opening' || 'reveal',
  ) =>
    ('dock', key),
  ('pane', 'prefabRules') => ('prefabRules', key),
  ('text', 'text' || 'overflow' || 'speed') => ('text', key),
  ('picture', 'source' || 'alt' || 'badge' || 'fit' || 'pad') => (
    'picture',
    key,
  ),
  ('meter', 'value' || 'min' || 'max' || 'shape') => ('meter', key),
  ('icon', 'icon' || 'size') => ('icon', key),
  ('folder', 'folder') => ('preview', 'node'),
  ('android', 'provider') => ('appWidget', key),
  ('button', 'label' || 'icon') => ('variables', key),
  _ => null,
};

/// Cell geometry of a pane, for placing what is on its cells in pixels.
class _Cells {
  _Cells(Json options, this.width)
    : columns = switch (options['columns']) {
        final num columns => columns.toInt().clamp(1, 24),
        _ => 5,
      },
      gapX = _number(options['spacing']) ?? 20,
      gapY = _number(options['spacing']) ?? 16,
      rowHeight = _number(options['rowHeight']);

  final int columns;
  final double gapX, gapY, width;
  final double? rowHeight;

  double get cellWidth => (width - (columns - 1) * gapX) / columns;
  double get cellHeight => rowHeight ?? cellWidth / 1.45;

  /// Width of [cells] columns, gaps included.
  double across(double cells) => cells * cellWidth + (cells - 1) * gapX;
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

Json _json(Object? value) => value is Json ? value : <String, Object?>{};

/// [value] to [places] decimals, whole ones as ints.
num _tidy(double value, [int places = 2]) {
  final scale = pow(10, places);
  final rounded = (value * scale).roundToDouble() / scale;
  return rounded == rounded.roundToDouble() ? rounded.toInt() : rounded;
}

/// A box drawn by a pane loses its padding to what is inside.
double _inside(double width, Json style, {double padding = 16}) =>
    width - 2 * (_number(style['padding']) ?? padding);

/// The cells [items] cover in a free pane: as given, or for one without a
/// position, in a row below the rest. One [docked] covers none.
List<(double, double, double, double)> _freeCells(
  List<Json> items,
  int columns,
  bool Function(Json item) docked,
) {
  double get(Json item, String key, double otherwise) =>
      _number(_json(item['transform'])[key]) ?? otherwise;
  double wide(Json item) => min(get(item, 'w', 1), columns * 1.0);
  bool placed(Json item) =>
      _json(item['transform']).containsKey('x') &&
      _json(item['transform']).containsKey('y');
  final below = items
      .where((item) => placed(item) && !docked(item))
      .fold(
        0.0,
        (rows, item) => max(rows, get(item, 'y', 0) + get(item, 'h', 1)),
      )
      .ceilToDouble();
  var x = 0.0, y = below, rowHeight = 0.0;
  return [
    for (final item in items)
      if (docked(item))
        (0, 0, 0, 0)
      else if (placed(item))
        (get(item, 'x', 0), get(item, 'y', 0), wide(item), get(item, 'h', 1))
      else
        () {
          if (x > 0 && x + wide(item) > columns) {
            x = 0;
            y += rowHeight;
            rowHeight = 0;
          }
          final cell = (x, y, wide(item), get(item, 'h', 1));
          x += wide(item);
          rowHeight = max(rowHeight, get(item, 'h', 1));
          return cell;
        }(),
  ];
}

/// A free pane's child at cells ([x], [y], [w], [h]) as a transform: anchored
/// across at fractions of the pane, so it keeps its share of any width; down
/// at pixels from the top.
Json _anchored(_Cells cells, (double, double, double, double) at) {
  final (x, y, w, h) = at;
  final c = cells.columns;
  final top = y * (cells.cellHeight + cells.gapY);
  final height = h * cells.cellHeight + (h - 1) * cells.gapY;
  return {
    'anchors': [_tidy(x / c, 4), 0, _tidy((x + w) / c, 4), 0],
    'offsets': [
      _tidy(x * cells.gapX / c),
      _tidy(top),
      _tidy((x + w) * cells.gapX / c - cells.gapX),
      _tidy(top + height),
    ],
  };
}

/// Kinds of the nodes in [tree], by id.
Map<String, String> _kindsIn(Json tree) => {
  '${tree['id']}': switch (tree['kind']) {
    final String kind => kind,
    _ => 'instance',
  },
  for (final child in objectsIn(tree, 'children')) ..._kindsIn(child),
};

/// One override entry in the new shape, for a node of [kind].
Json _override(Json set, String kind) {
  final modules = <String, Json>{};
  String? name;
  void put(String module, String key, Object? value) =>
      (modules[module] ??= {})[key] = value;
  for (final MapEntry(:key, :value) in _json(set['options']).entries) {
    switch (_moved(kind, key)) {
      case (null, _):
        name = value is String ? value : null;
      case ('prefabRules', _):
        modules['prefabRules'] = _rules(value, _systemParts);
      case (final String module, final String key):
        put(module, key, value);
      case null:
        break;
    }
  }
  for (final MapEntry(:key, :value) in _json(set['style']).entries) {
    put(
      kind == 'pane' && _scrollbarKeys.contains(key) ? 'scroll' : 'style',
      key,
      value,
    );
  }
  for (final MapEntry(:key, :value) in _json(set['transform']).entries) {
    put('sizing', key, value);
  }
  return {
    if (modules.isNotEmpty) 'modules': modules,
    if (set['hidden'] case final bool hidden) 'hidden': hidden,
    'name': ?name,
  };
}

/// A pane's prefab rules with their overrides in the new shape.
Json _rules(Object? rules, Map<String, Map<String, String>> prefabs) => {
  for (final MapEntry(key: id, value: rule) in _json(rules).entries)
    if (rule is Json)
      id: {
        ...rule,
        if (rule['overrides'] != null)
          'overrides': _overrides(rule['overrides'], prefabs[id] ?? {}),
      },
};

/// [overrides] in the new shape, for the nodes [kinds] says.
Json _overrides(Object? overrides, Map<String, String> kinds) => {
  for (final MapEntry(:key, :value) in _json(overrides).entries)
    if (value is Json) key: _override(value, kinds[key] ?? 'pane'),
};

/// The System pack's prefabs whose roots dock.
const _systemDocked = {
  'system:quick-actions',
  'system:folder',
  'system:sidebar',
};

/// Prefabs whose roots dock: the System pack's and the save's own.
Set<String> _dockedPrefabs(Json save) => {
  ..._systemDocked,
  for (final prefab in objectsIn(save, 'prefabs'))
    if (_json(_json(prefab['root'])['options'])['dock'] is String)
      '${prefab['id']}',
};

/// Node kinds of every prefab the save has, and the System pack's.
Map<String, Map<String, String>> _prefabKinds(Json save) => {
  ..._systemParts,
  for (final prefab in objectsIn(save, 'prefabs'))
    if (prefab['root'] case final Json root) '${prefab['id']}': _kindsIn(root),
};

/// [node] as a node with modules, in a parent laid out as [mode] (null for a
/// root) whose cells are [cells]. [width] is how wide it is drawn, as far as
/// can be told; [at] its cells in a free parent.
Json _node(
  Json node,
  Map<String, Map<String, String>> prefabs,
  Set<String> docks, {
  String? mode,
  double width = 960,
  (double, double, double, double)? at,
  _Cells? cells,
}) {
  final prefab = node['prefab'];
  final kind = prefab is String ? 'instance' : '${node['kind']}';
  final options = _json(node['options']);
  final style = _json(node['style']);
  final on = _json(node['on']);
  final transform = _json(node['transform']);
  final modules = <String, Json>{};
  String name = '';
  void put(String module, String key, Object? value) =>
      (modules[module] ??= {})[key] = value;

  // An instance's own options are its prefab root's, a pane's.
  final as = kind == 'instance' ? 'pane' : kind;
  for (final MapEntry(:key, :value) in options.entries) {
    switch (_moved(as, key)) {
      case (null, _):
        if (value is String) name = value;
      case ('prefabRules', _):
        modules['prefabRules'] = _rules(value, prefabs);
      case (final String module, final String key):
        put(module, key, value);
      case null:
        break;
    }
  }
  final layoutMode = switch (options['mode']) {
    final String mode => mode,
    _ => 'flow',
  };
  if (kind == 'pane') {
    if (layoutMode == 'free') {
      modules.remove('layout');
    } else {
      put('layout', 'mode', layoutMode);
    }
    // Cells scrolled down unless told not to; a column only when told to.
    final scroll = modules.remove('scroll') ?? {};
    final cellsMode = layoutMode == 'flow' || layoutMode == 'grid';
    final down = switch (layoutMode) {
      'flow' || 'grid' => scroll['down'] != false,
      'column' => scroll['down'] == true,
      _ => false,
    };
    final across =
        scroll['across'] == true && (cellsMode || layoutMode == 'row');
    if (down || across) {
      modules['scroll'] = {
        if (across) 'across': true,
        if (down) 'down': true,
        'bar': ?scroll['bar'],
        'show': ?scroll['show'],
        for (final MapEntry(:key, :value) in style.entries)
          if (_scrollbarKeys.contains(key)) key: value,
      };
    }
  }
  final ownStyle = {
    for (final MapEntry(:key, :value) in style.entries)
      if (kind != 'pane' || !_scrollbarKeys.contains(key)) key: value,
  };
  if (ownStyle.isNotEmpty) modules['style'] = ownStyle;
  if (node['vars'] case final Json vars when vars.isNotEmpty) {
    modules['variables'] = {...?modules['variables'], ...vars};
  }
  if (on.isNotEmpty) modules['triggers'] = on;
  // A free parent places it by a transform; any other by its cells.
  if (mode != 'free' && transform.isNotEmpty) modules['sizing'] = transform;

  // What can be pressed takes the focus; a pane on cells never did.
  bool acts(String trigger) =>
      on[trigger] is List && (on[trigger]! as List).isNotEmpty;
  final inLine = layoutMode == 'row' || layoutMode == 'column';
  // A button's prefab takes the focus itself.
  if ((acts('press') || acts('hold')) &&
      (kind != 'pane' || inLine) &&
      kind != 'button') {
    modules['focus'] = {};
  }
  // A part marked `frame` showed its tile's focus.
  if (modules.containsKey('focus')) {
    Json? framed(Json pane) {
      for (final child in objectsIn(pane, 'children')) {
        if (_json(child['options'])['frame'] == true) return child;
        if (child['kind'] == 'pane') {
          if (framed(child) case final found?) return found;
        }
      }
      return null;
    }

    if (framed(node) case final part?) {
      modules['focus'] = {
        'target': part['id'],
        'bare': _json(part['options'])['bare'] ?? false,
      };
    } else {
      // How a whole tile showed its focus: grown less, and a row or column
      // padded inside its frame.
      final focus = modules['focus']!;
      if (kind != 'pane') focus['scale'] = 103;
      if (layoutMode == 'row') focus['scale'] = 104;
      if (inLine && ownStyle['padding'] == null) {
        modules['style'] = {...ownStyle, 'padding': 8};
      }
    }
  }

  // How wide what is inside it is drawn, for children placed in pixels.
  final inner = kind == 'pane'
      ? _inside(width, style, padding: mode == null ? 0 : 16)
      : width;
  final children = objectsIn(node, 'children');
  final ownCells = _Cells(options, inner);
  final free = kind == 'pane' && layoutMode == 'free';
  bool docked(Json child) =>
      _json(child['options'])['dock'] is String ||
      docks.contains(child['prefab']);
  final freeAt = free ? _freeCells(children, ownCells.columns, docked) : null;
  Json child(int index, Json child) {
    final childOptions = _json(child['options']);
    final childTransform = _json(child['transform']);
    final apart = docked(child);
    final double childWidth;
    if (apart) {
      childWidth =
          _number(childOptions['width']) ??
          switch (childOptions['dock']) {
            'left' || 'right' => 260,
            'top' || 'bottom' => 960,
            _ => 595,
          };
    } else if (free) {
      childWidth = ownCells.across(freeAt![index].$3);
    } else if (inLine || kind != 'pane') {
      childWidth = inner;
    } else {
      childWidth = ownCells.across(
        min(_number(childTransform['w']) ?? 1, ownCells.columns * 1.0),
      );
    }
    return _node(
      child,
      prefabs,
      docks,
      mode: apart ? 'docked' : layoutMode,
      width: childWidth,
      at: free && !apart ? freeAt![index] : null,
      cells: ownCells,
    );
  }

  final next = <String, Object?>{
    'id': node['id'],
    if (name.isNotEmpty) 'name': name,
    if (kind == 'button') 'prefab': 'system:button' else 'prefab': ?prefab,
    'variant': ?node['variant'],
    if (at != null && cells != null) 'transform': _anchored(cells, at),
    if (node['hidden'] == true) 'hidden': true,
    'modules': modules,
    if (node['overrides'] != null)
      'overrides': _overrides(node['overrides'], prefabs['$prefab'] ?? {}),
    'template': ?node['template'],
    if (children.isNotEmpty)
      'children': [
        for (final (index, one) in children.indexed) child(index, one),
      ],
  };
  if (modules.isEmpty) next.remove('modules');
  return next;
}

/// Everything on screen is a node, and what it draws, how it lays out its
/// children and how it behaves are its modules: `kind` and `options` are
/// gone. A pane's title is its name; a button is an instance of the System
/// pack's Button; a free pane's children sit where transforms put them.
void nodesAndModules(Json save, Device device) {
  final prefabs = _prefabKinds(save);
  final docks = _dockedPrefabs(save);
  if (layoutOf(save) case final layout?) {
    for (final layer in objectsIn(layout, 'layers')) {
      if (layer['root'] case final Json root) {
        layer['root'] = _node(root, prefabs, docks);
      }
    }
  }
  for (final prefab in objectsIn(save, 'prefabs')) {
    final root = prefab['root'];
    if (root is! Json) continue;
    final kinds = _kindsIn(root);
    // Its size is its root's cells; how wide that is, a guess.
    prefab['root'] = _node(
      root,
      prefabs,
      docks,
      mode: 'flow',
      width: 960 * min(1, (_number(_json(root['transform'])['w']) ?? 1) / 12),
    );
    for (final variant in _json(prefab['variants']).values) {
      if (variant is Json && variant['overrides'] != null) {
        variant['overrides'] = _overrides(variant['overrides'], kinds);
      }
    }
  }
}
