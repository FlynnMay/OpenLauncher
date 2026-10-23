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
    _actionsByAddress(jsonObject(entity['actions']));
  }
}

void _actionsByAddress(Json actions) {
  for (final action in actions.values) {
    if (action case {'run': final String run} as Json
        when _addresses.containsKey(run)) {
      action['run'] = _addresses[run];
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

const _layerAddresses = {
  'newLayer': 'launcher://layers/new',
  'toLayer': 'launcher://layers/raise',
  'closeLayer': 'launcher://layers/close',
  'close': 'launcher://popups/close',
};

const _layoutAddresses = {
  'add': 'launcher://layout/add',
  'remove': 'launcher://layout/remove',
};

/// A feed is a source: `{from: http, url, every}` is written in place as
/// `{url, every}`, the launcher's own by address. The machinery entities
/// are gone: acts that asked `variables`, `layers` or a layer call the
/// address instead, and `system` is `device`.
void feedsAsSources(Json save, Device device) {
  for (final entity in objectsIn(save, 'entities')) {
    _feedAsSource(entity);
  }
  final layerIds = {
    for (final layer in objectsIn(layoutOf(save) ?? const {}, 'layers'))
      layer['id'],
  };
  _MachineryActs(layerIds).replaceIn(save);
}

void _feedAsSource(Json entity) {
  final source = switch (entity['feed']) {
    {'from': 'http'} && final Json feed => without(feed, {'from'}),
    {'from': final String from} when _feeds.containsKey(from) => _feeds[from],
    final other => other,
  };
  if (source == null) {
    entity.remove('feed');
  } else {
    entity['feed'] = source;
  }
}

/// Rewrites acts that asked a machinery entity to call its address.
class _MachineryActs {
  _MachineryActs(this.layerIds);

  final Set<Object?> layerIds;

  void replaceIn(Object? json) {
    if (json is Json) {
      json.values.forEach(replaceIn);
    } else if (json is List<Object?>) {
      _replaceInList(json);
    }
  }

  void _replaceInList(List<Object?> list) {
    for (var index = 0; index < list.length; index++) {
      final item = list[index];
      if (item case final Json act when act['do'] is String) {
        if (_addressCall(act) case final call?) {
          list[index] = call;
          continue;
        }
        if (act['entity'] == 'system') act['entity'] = 'device';
      }
      replaceIn(item);
    }
  }

  Json? _addressCall(Json act) {
    final name = act['do'];
    final entity = act['entity'];
    final address = switch (entity) {
      'variables' when name == 'set' => 'launcher://variables/set',
      'layers' => _layerAddresses[name],
      _ when layerIds.contains(entity) => _layoutAddresses[name],
      _ => null,
    };
    if (address == null) return null;
    final arguments = {
      if (_layoutAddresses.containsValue(address)) 'layer': entity,
      ...without(act, {'do', 'entity'}),
    };
    return {'run': address, if (arguments.isNotEmpty) 'with': arguments};
  }
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
String? _entityId(Object? id) => switch (id) {
  final String id when id.startsWith('app:') => 'system:app/${id.substring(4)}',
  final String id when id.startsWith('input:') =>
    'system:input/${id.substring(6)}',
  'launcher:settings' => 'system:settings',
  final String id when _systemEntities.contains(id) => 'system:$id',
  _ => null,
};

String? _prefabId(Object? id) =>
    _systemPrefabs.contains(id) ? 'system:$id' : null;

final _templateSlot = RegExp(r'\{\{(.*?)\}\}');
final _quotedOrCode = RegExp('(\'[^\']*\'|"[^"]*")|[^\'"]+');
final _pathRoot = RegExp(r'(^|[\s(!=<>?:])([A-Za-z][\w-]*)(?=[.\s|\[]|$)');

/// [text] with the launcher's own entities given in full where a template
/// starts a value's path with one.
String _template(String text) => text.replaceAllMapped(
  _templateSlot,
  (slot) => '{{${_slotWithSystemIds(slot[1]!)}}}',
);

/// Quoted text is left alone.
String _slotWithSystemIds(String expression) => expression.replaceAllMapped(
  _quotedOrCode,
  (part) => part[1] != null ? part[0]! : _pathsWithSystemIds(part[0]!),
);

String _pathsWithSystemIds(String code) => code.replaceAllMapped(
  _pathRoot,
  (root) => _systemEntities.contains(root[2])
      ? '${root[1]}system:${root[2]}'
      : root[0]!,
);

/// Every pack's ids carry its own: what the launcher ships is `system:...`.
/// Saved ids are given in full wherever an entity or a prefab is named.
void packIds(Json save, Device device) {
  for (final key in ['names', 'iconOverrides']) {
    if (save[key] case final Json byEntity) {
      save[key] = _entityKeyed(byEntity);
    }
  }
  if (save['iconSources'] case final Json sources) {
    save['iconSources'] = _entityKeyed(sources, valuesToo: true);
  }
  if (layoutOf(save) case final layout? when layout['removed'] is List) {
    layout['removed'] = [
      for (final id in layout['removed']! as List) _entityId(id) ?? id,
    ];
  }
  for (final prefab in objectsIn(save, 'prefabs')) {
    prefab['id'] = _prefabId(prefab['id']) ?? prefab['id'];
  }
  for (final key in ['layout', 'prefabs', 'entities']) {
    if (save[key] != null) save[key] = _withFullIds(save[key]);
  }
}

Json _entityKeyed(Json byEntity, {bool valuesToo = false}) => {
  for (final MapEntry(:key, :value) in byEntity.entries)
    _entityId(key) ?? key: valuesToo ? _entityId(value) ?? value : value,
};

/// [json] with every entity and prefab it names given in full.
Object? _withFullIds(Object? json) => switch (json) {
  final String text => text.contains('{{') ? _template(text) : text,
  final List<Object?> list => _listWithFullIds(list),
  final Json object => _objectWithFullIds(object),
  final other => other,
};

List<Object?> _listWithFullIds(List<Object?> list) {
  for (var index = 0; index < list.length; index++) {
    list[index] = _withFullIds(list[index]);
  }
  return list;
}

Json _objectWithFullIds(Json object) {
  for (final key in [...object.keys]) {
    object[key] = _valueWithFullIds(object, key, object[key]);
  }
  return object;
}

/// [value] at [key] in [object], with its ids given in full.
Object? _valueWithFullIds(Json object, String key, Object? value) =>
    switch ((key, value)) {
      ('prefab', _) => _prefabId(value) ?? value,
      // What the layout adds or removes is an entity.
      ('with', final Json arguments)
          when '${object['run']}'.startsWith('launcher://layout/') =>
        (_withFullIds(arguments)! as Json)
          ..['what'] = _entityId(arguments['what']) ?? arguments['what'],
      ('entity', _) when object['do'] is String =>
        _entityId(value) ?? _withFullIds(value),
      ('prefabRules', final Json rules) => _prefabRulesWithFullIds(rules),
      ('vars', final Json variables) => _variablesWithFullIds(variables),
      _ => _withFullIds(value),
    };

Json _prefabRulesWithFullIds(Json rules) => {
  for (final MapEntry(:key, :value) in rules.entries)
    _prefabId(key) ?? key: _withFullIds(value),
};

Json _variablesWithFullIds(Json variables) => {
  for (final MapEntry(:key, :value) in variables.entries)
    key: switch (value) {
      {'type': 'entity', 'value': final String id} && final Json variable =>
        (_withFullIds(variable)! as Json)
          ..['value'] = _entityId(id) ?? _withFullIds(id),
      _ => _withFullIds(value),
    },
};

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
void quickActionsAsPrefab(Json save, Device device) =>
    layerRoots(save).forEach(_quickActionsAsPrefabIn);

void _quickActionsAsPrefabIn(Json pane) {
  objectsIn(pane, 'children').forEach(_quickActionsAsPrefabIn);
  if (pane['children'] case final List<Object?> children) {
    for (var index = 0; index < children.length; index++) {
      if (children[index]
          case {'id': 'quick-actions', 'kind': 'pane'} && final Json menu) {
        children[index] = _quickActionsInstance(menu);
      }
    }
  }
}

Json _quickActionsInstance(Json menu) {
  final changedOptions = {
    for (final MapEntry(:key, :value) in jsonObject(menu['options']).entries)
      if (_menuOptions[key] != value) key: value,
  };
  return {
    'id': 'quick-actions',
    'prefab': 'system:quick-actions',
    if (changedOptions.isNotEmpty) 'options': changedOptions,
    if (menu['style'] case final Json style when style.isNotEmpty)
      'style': style,
  };
}

/// A new folder or sidebar records the template it was copied from: the
/// saved ones were the launcher's, now the System pack's. One docked with a
/// strip is a sidebar; any other docked pane, a folder.
void templatesRecorded(Json save, Device device) =>
    layerRoots(save).forEach(_templatesRecordedIn);

void _templatesRecordedIn(Json pane) {
  for (final child in objectsIn(pane, 'children')) {
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
    _templatesRecordedIn(child);
  }
}

/// A docked pane says itself whether a press closes it: the launcher closed
/// one with no strip, unless it was opened in place.
void closeOnPressRecorded(Json save, Device device) {
  layerRoots(save).forEach(_closeOnPressRecordedIn);
  for (final prefab in objectsIn(save, 'prefabs')) {
    if (prefab['root'] case final Json root) _closeOnPressRecordedIn(root);
  }
}

void _closeOnPressRecordedIn(Json pane) {
  if (pane
      case {
        'kind': 'pane',
        'options': {'dock': final String dock} && final Json options,
      }
      when dock != 'inline' && !options.containsKey('closed')) {
    options.putIfAbsent('closeOnPress', () => true);
  }
  objectsIn(pane, 'children').forEach(_closeOnPressRecordedIn);
}

/// Node kinds of each part, by node id.
typedef _PartKinds = Map<String, String>;

/// What the parts of the System pack's prefabs drew, for overrides of them
/// saved outside the prefab.
const Map<String, _PartKinds> _systemParts = {
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
(String?, String)? _movedOption(String kind, String key) => switch ((
  kind,
  key,
)) {
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

/// Module values gathered for one node, and the name its title gave it.
class _Modules {
  final values = <String, Json>{};
  String? name;

  void put(String module, String key, Object? value) =>
      (values[module] ??= {})[key] = value;

  /// [options] of a node of [kind] moved to their modules; prefab rules
  /// rewritten for the parts [prefabs] lists.
  void moveOptions(Json options, String kind, Map<String, _PartKinds> prefabs) {
    for (final MapEntry(:key, :value) in options.entries) {
      switch (_movedOption(kind, key)) {
        case (null, _):
          if (value is String) name = value;
        case ('prefabRules', _):
          values['prefabRules'] = _prefabRules(value, prefabs);
        case (final String module, final String key):
          put(module, key, value);
        case null:
          break;
      }
    }
  }
}

/// Cells a node covers on its parent's grid.
typedef _CellRect = ({double x, double y, double width, double height});

const _CellRect _noCells = (x: 0, y: 0, width: 0, height: 0);

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
  final double gapX;
  final double gapY;
  final double width;
  final double? rowHeight;

  double get cellWidth => (width - (columns - 1) * gapX) / columns;
  double get cellHeight => rowHeight ?? cellWidth / 1.45;

  /// Width of [cells] columns, gaps included.
  double across(double cells) => cells * cellWidth + (cells - 1) * gapX;
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

/// [value] to [places] decimals, whole ones as ints.
num _rounded(double value, [int places = 2]) {
  final scale = pow(10, places);
  final rounded = (value * scale).roundToDouble() / scale;
  return rounded == rounded.roundToDouble() ? rounded.toInt() : rounded;
}

/// A box drawn by a pane loses its padding to what is inside.
double _widthInside(double width, Json style, {double padding = 16}) =>
    width - 2 * (_number(style['padding']) ?? padding);

double _transformValue(Json item, String key, double fallback) =>
    _number(jsonObject(item['transform'])[key]) ?? fallback;

bool _hasPosition(Json item) {
  final transform = jsonObject(item['transform']);
  return transform.containsKey('x') && transform.containsKey('y');
}

/// The cells [items] cover in a free pane: as given, or for one without a
/// position, in a row below the rest. One [isDocked] covers none.
List<_CellRect> _freeCells(
  List<Json> items,
  int columns,
  bool Function(Json item) isDocked,
) {
  double widthOf(Json item) =>
      min(_transformValue(item, 'w', 1), columns * 1.0);
  double heightOf(Json item) => _transformValue(item, 'h', 1);
  final rowsUsed = items
      .where((item) => _hasPosition(item) && !isDocked(item))
      .fold(
        0.0,
        (rows, item) =>
            max(rows, _transformValue(item, 'y', 0) + heightOf(item)),
      )
      .ceilToDouble();
  final unplaced = _RowFiller(columns, rowsUsed);
  return [
    for (final item in items)
      if (isDocked(item))
        _noCells
      else if (_hasPosition(item))
        (
          x: _transformValue(item, 'x', 0),
          y: _transformValue(item, 'y', 0),
          width: widthOf(item),
          height: heightOf(item),
        )
      else
        unplaced.next(widthOf(item), heightOf(item)),
  ];
}

/// Puts items without a position in rows, from row [y] down.
class _RowFiller {
  _RowFiller(this.columns, this.y);

  final int columns;
  double y;
  double x = 0;
  double rowHeight = 0;

  _CellRect next(double width, double height) {
    if (x > 0 && x + width > columns) {
      x = 0;
      y += rowHeight;
      rowHeight = 0;
    }
    final cells = (x: x, y: y, width: width, height: height);
    x += width;
    rowHeight = max(rowHeight, height);
    return cells;
  }
}

/// A free pane's child on [at] as a transform: anchored across at fractions
/// of the pane, so it keeps its share of any width; down at pixels from the
/// top.
Json _anchored(_Cells cells, _CellRect at) {
  final columns = cells.columns;
  final top = at.y * (cells.cellHeight + cells.gapY);
  final height = at.height * cells.cellHeight + (at.height - 1) * cells.gapY;
  final right = at.x + at.width;
  return {
    'anchors': [
      _rounded(at.x / columns, 4),
      0,
      _rounded(right / columns, 4),
      0,
    ],
    'offsets': [
      _rounded(at.x * cells.gapX / columns),
      _rounded(top),
      _rounded(right * cells.gapX / columns - cells.gapX),
      _rounded(top + height),
    ],
  };
}

/// Kinds of the nodes in [tree], by id.
_PartKinds _kindsIn(Json tree) => {
  '${tree['id']}': switch (tree['kind']) {
    final String kind => kind,
    _ => 'instance',
  },
  for (final child in objectsIn(tree, 'children')) ..._kindsIn(child),
};

/// One override entry in the new shape, for a node of [kind].
Json _override(Json saved, String kind) {
  final modules = _Modules()
    ..moveOptions(jsonObject(saved['options']), kind, _systemParts);
  for (final MapEntry(:key, :value) in jsonObject(saved['style']).entries) {
    final scrollbar = kind == 'pane' && _scrollbarKeys.contains(key);
    modules.put(scrollbar ? 'scroll' : 'style', key, value);
  }
  for (final MapEntry(:key, :value) in jsonObject(saved['transform']).entries) {
    modules.put('sizing', key, value);
  }
  return {
    if (modules.values.isNotEmpty) 'modules': modules.values,
    if (saved['hidden'] case final bool hidden) 'hidden': hidden,
    'name': ?modules.name,
  };
}

/// A pane's prefab rules with their overrides in the new shape.
Json _prefabRules(Object? rules, Map<String, _PartKinds> prefabs) => {
  for (final MapEntry(key: id, value: rule) in jsonObject(rules).entries)
    if (rule is Json)
      id: {
        ...rule,
        if (rule['overrides'] != null)
          'overrides': _overrides(rule['overrides'], prefabs[id] ?? {}),
      },
};

/// [overrides] in the new shape, for the nodes [kinds] says.
Json _overrides(Object? overrides, _PartKinds kinds) => {
  for (final MapEntry(:key, :value) in jsonObject(overrides).entries)
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
    if (jsonObject(jsonObject(prefab['root'])['options'])['dock'] is String)
      '${prefab['id']}',
};

/// Node kinds of every prefab the save has, and the System pack's.
Map<String, _PartKinds> _prefabKinds(Json save) => {
  ..._systemParts,
  for (final prefab in objectsIn(save, 'prefabs'))
    if (prefab['root'] case final Json root) '${prefab['id']}': _kindsIn(root),
};

/// A node as version 2 saved it.
class _OldNode {
  _OldNode(this.json)
    : options = jsonObject(json['options']),
      style = jsonObject(json['style']),
      triggers = jsonObject(json['on']),
      transform = jsonObject(json['transform']);

  final Json json;
  final Json options;
  final Json style;
  final Json triggers;
  final Json transform;

  Object? get prefab => json['prefab'];
  String get kind => prefab is String ? 'instance' : '${json['kind']}';
  bool get isPane => kind == 'pane';

  /// An instance's own options are its prefab root's, a pane's.
  String get optionsKind => kind == 'instance' ? 'pane' : kind;

  String get layoutMode => switch (options['mode']) {
    final String mode => mode,
    _ => 'flow',
  };

  bool get isFree => isPane && layoutMode == 'free';
  bool get inLine => layoutMode == 'row' || layoutMode == 'column';

  /// Its style, less the scroll bar keys a pane gives its Scroll.
  Json get ownStyle => {
    for (final MapEntry(:key, :value) in style.entries)
      if (!isPane || !_scrollbarKeys.contains(key)) key: value,
  };

  Json get scrollbarStyle => {
    for (final MapEntry(:key, :value) in style.entries)
      if (_scrollbarKeys.contains(key)) key: value,
  };

  /// What can be pressed takes the focus; a pane on cells never did, and a
  /// button's prefab takes it itself.
  bool get takesFocus =>
      (_runsActs('press') || _runsActs('hold')) &&
      (!isPane || inLine) &&
      kind != 'button';

  bool _runsActs(String trigger) => switch (triggers[trigger]) {
    final List<Object?> acts => acts.isNotEmpty,
    _ => false,
  };
}

/// A pane's Layout and Scroll from its mode: cells scrolled down unless told
/// not to, a column only when told to.
void _paneLayoutAndScroll(_OldNode pane, _Modules modules) {
  final mode = pane.layoutMode;
  if (mode == 'free') {
    modules.values.remove('layout');
  } else {
    modules.put('layout', 'mode', mode);
  }
  final scroll = modules.values.remove('scroll') ?? {};
  final onCells = mode == 'flow' || mode == 'grid';
  final down = switch (mode) {
    'flow' || 'grid' => scroll['down'] != false,
    'column' => scroll['down'] == true,
    _ => false,
  };
  final across = scroll['across'] == true && (onCells || mode == 'row');
  if (!down && !across) return;
  modules.values['scroll'] = {
    if (across) 'across': true,
    if (down) 'down': true,
    'bar': ?scroll['bar'],
    'show': ?scroll['show'],
    ...pane.scrollbarStyle,
  };
}

/// The part marked `frame`, which showed its tile's focus.
Json? _framedPart(Json pane) {
  for (final child in objectsIn(pane, 'children')) {
    if (jsonObject(child['options'])['frame'] == true) return child;
    if (child['kind'] != 'pane') continue;
    if (_framedPart(child) case final found?) return found;
  }
  return null;
}

/// The Focus of a node that takes it: on its framed part, or how a whole
/// tile showed it, grown less and a row or column padded inside its frame.
void _focus(_OldNode node, _Modules modules, Json ownStyle) {
  if (_framedPart(node.json) case final part?) {
    modules.values['focus'] = {
      'target': part['id'],
      'bare': jsonObject(part['options'])['bare'] ?? false,
    };
    return;
  }
  final focus = <String, Object?>{};
  if (!node.isPane) focus['scale'] = 103;
  if (node.layoutMode == 'row') focus['scale'] = 104;
  modules.values['focus'] = focus;
  if (node.inLine && ownStyle['padding'] == null) {
    modules.values['style'] = {...ownStyle, 'padding': 8};
  }
}

/// Turns version 2 nodes into nodes with modules.
class _NodeConverter {
  _NodeConverter(this.prefabs, this.dockedPrefabs);

  final Map<String, _PartKinds> prefabs;
  final Set<String> dockedPrefabs;

  /// [json] in a parent laid out as [parentMode] (null for a root) whose
  /// cells are [parentCells]. [width] is how wide it is drawn, as far as can
  /// be told; [at] its cells in a free parent.
  Json convert(
    Json json, {
    String? parentMode,
    double width = 960,
    _CellRect? at,
    _Cells? parentCells,
  }) {
    final node = _OldNode(json);
    final modules = _Modules()
      ..moveOptions(node.options, node.optionsKind, prefabs);
    if (node.isPane) _paneLayoutAndScroll(node, modules);
    final ownStyle = node.ownStyle;
    if (ownStyle.isNotEmpty) modules.values['style'] = ownStyle;
    if (json['vars'] case final Json variables when variables.isNotEmpty) {
      modules.values['variables'] = {
        ...?modules.values['variables'],
        ...variables,
      };
    }
    if (node.triggers.isNotEmpty) modules.values['triggers'] = node.triggers;
    // A free parent places it by a transform; any other by its cells.
    if (parentMode != 'free' && node.transform.isNotEmpty) {
      modules.values['sizing'] = node.transform;
    }
    if (node.takesFocus) _focus(node, modules, ownStyle);
    final children = objectsIn(json, 'children');
    return {
      'id': json['id'],
      if (modules.name case final name? when name.isNotEmpty) 'name': name,
      if (node.kind == 'button')
        'prefab': 'system:button'
      else
        'prefab': ?node.prefab,
      'variant': ?json['variant'],
      if (at != null && parentCells != null)
        'transform': _anchored(parentCells, at),
      if (json['hidden'] == true) 'hidden': true,
      if (modules.values.isNotEmpty) 'modules': modules.values,
      if (json['overrides'] != null)
        'overrides': _overrides(
          json['overrides'],
          prefabs['${node.prefab}'] ?? {},
        ),
      'template': ?json['template'],
      if (children.isNotEmpty)
        'children': _ChildPlacement(
          this,
          node,
          children,
          width: width,
          isRoot: parentMode == null,
        ).converted(),
    };
  }

  /// [prefab]'s root and its variants' overrides.
  void convertPrefab(Json prefab, Json root) {
    final kinds = _kindsIn(root);
    // Its size is its root's cells; how wide that is, a guess.
    final columnsWide = _number(jsonObject(root['transform'])['w']) ?? 1;
    prefab['root'] = convert(
      root,
      parentMode: 'flow',
      width: 960 * min(1, columnsWide / 12),
    );
    for (final variant in jsonObject(prefab['variants']).values) {
      if (variant is Json && variant['overrides'] != null) {
        variant['overrides'] = _overrides(variant['overrides'], kinds);
      }
    }
  }

  bool isDocked(Json node) =>
      jsonObject(node['options'])['dock'] is String ||
      dockedPrefabs.contains(node['prefab']);
}

/// Where and how wide the children of [parent] are drawn.
class _ChildPlacement {
  _ChildPlacement(
    this.converter,
    this.parent,
    this.children, {
    required double width,
    required bool isRoot,
  }) : innerWidth = parent.isPane
           ? _widthInside(width, parent.style, padding: isRoot ? 0 : 16)
           : width {
    cells = _Cells(parent.options, innerWidth);
    freeCells = parent.isFree
        ? _freeCells(children, cells.columns, converter.isDocked)
        : const [];
  }

  final _NodeConverter converter;
  final _OldNode parent;
  final List<Json> children;

  /// How wide what is inside it is drawn, for children placed in pixels.
  final double innerWidth;
  late final _Cells cells;
  late final List<_CellRect> freeCells;

  List<Json> converted() => [
    for (final (index, child) in children.indexed) _converted(index, child),
  ];

  Json _converted(int index, Json child) {
    final docked = converter.isDocked(child);
    return converter.convert(
      child,
      parentMode: docked ? 'docked' : parent.layoutMode,
      width: _widthOf(index, child, docked: docked),
      at: parent.isFree && !docked ? freeCells[index] : null,
      parentCells: cells,
    );
  }

  double _widthOf(int index, Json child, {required bool docked}) {
    if (docked) return _dockedWidth(jsonObject(child['options']));
    if (parent.isFree) return cells.across(freeCells[index].width);
    if (parent.inLine || !parent.isPane) return innerWidth;
    final columnsWide = _number(jsonObject(child['transform'])['w']) ?? 1;
    return cells.across(min(columnsWide, cells.columns * 1.0));
  }

  static double _dockedWidth(Json options) =>
      _number(options['width']) ??
      switch (options['dock']) {
        'left' || 'right' => 260,
        'top' || 'bottom' => 960,
        _ => 595,
      };
}

/// Everything on screen is a node, and what it draws, how it lays out its
/// children and how it behaves are its modules: `kind` and `options` are
/// gone. A pane's title is its name; a button is an instance of the System
/// pack's Button; a free pane's children sit where transforms put them.
void nodesAndModules(Json save, Device device) {
  final converter = _NodeConverter(_prefabKinds(save), _dockedPrefabs(save));
  for (final layer in objectsIn(layoutOf(save) ?? const {}, 'layers')) {
    if (layer['root'] case final Json root) {
      layer['root'] = converter.convert(root);
    }
  }
  for (final prefab in objectsIn(save, 'prefabs')) {
    if (prefab['root'] case final Json root) {
      converter.convertPrefab(prefab, root);
    }
  }
}
