import 'dart:math';

import 'package:openlauncher_domain/config/migrations/save_json.dart';

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

String _template(String text) => text.replaceAllMapped(
  _templateSlot,
  (slot) => '{{${_slotWithSystemIds(slot[1]!)}}}',
);

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

Object? _valueWithFullIds(Json object, String key, Object? value) =>
    switch ((key, value)) {
      ('prefab', _) => _prefabId(value) ?? value,
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

void closeOnPressRecorded(Json save, Device device) {
  layerRoots(save).forEach(_closeOnPressRecordedIn);
  prefabRoots(save).forEach(_closeOnPressRecordedIn);
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

typedef _PartKinds = Map<String, String>;

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

/// A `null` module is the node itself.
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

class _Modules {
  final values = <String, Json>{};
  String? name;

  void put(String module, String key, Object? value) =>
      (values[module] ??= {})[key] = value;

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

typedef _CellRect = ({double x, double y, double width, double height});

const _CellRect _noCells = (x: 0, y: 0, width: 0, height: 0);

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

  double across(double cells) => cells * cellWidth + (cells - 1) * gapX;
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

num _rounded(double value, [int places = 2]) {
  final scale = pow(10, places);
  final rounded = (value * scale).roundToDouble() / scale;
  return rounded == rounded.roundToDouble() ? rounded.toInt() : rounded;
}

double _widthInside(double width, Json style, {double padding = 16}) =>
    width - 2 * (_number(style['padding']) ?? padding);

double _transformValue(Json item, String key, double fallback) =>
    _number(jsonObject(item['transform'])[key]) ?? fallback;

bool _hasPosition(Json item) {
  final transform = jsonObject(item['transform']);
  return transform.containsKey('x') && transform.containsKey('y');
}

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

/// Anchored across, so it keeps its share of any width; pixels down.
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

_PartKinds _kindsIn(Json tree) => {
  '${tree['id']}': switch (tree['kind']) {
    final String kind => kind,
    _ => 'instance',
  },
  for (final child in objectsIn(tree, 'children')) ..._kindsIn(child),
};

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

Json _prefabRules(Object? rules, Map<String, _PartKinds> prefabs) => {
  for (final MapEntry(key: id, value: rule) in jsonObject(rules).entries)
    if (rule is Json)
      id: {
        ...rule,
        if (rule['overrides'] != null)
          'overrides': _overrides(rule['overrides'], prefabs[id] ?? {}),
      },
};

Json _overrides(Object? overrides, _PartKinds kinds) => {
  for (final MapEntry(:key, :value) in jsonObject(overrides).entries)
    if (value is Json) key: _override(value, kinds[key] ?? 'pane'),
};

const _systemDocked = {
  'system:quick-actions',
  'system:folder',
  'system:sidebar',
};

Set<String> _dockedPrefabs(Json save) => {
  ..._systemDocked,
  for (final prefab in objectsIn(save, 'prefabs'))
    if (jsonObject(jsonObject(prefab['root'])['options'])['dock'] is String)
      '${prefab['id']}',
};

Map<String, _PartKinds> _prefabKinds(Json save) => {
  ..._systemParts,
  for (final prefab in objectsIn(save, 'prefabs'))
    if (prefab['root'] case final Json root) '${prefab['id']}': _kindsIn(root),
};

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

  /// An instance's options are its prefab root's, a pane's.
  String get optionsKind => kind == 'instance' ? 'pane' : kind;

  String get layoutMode => switch (options['mode']) {
    final String mode => mode,
    _ => 'flow',
  };

  bool get isFree => isPane && layoutMode == 'free';
  bool get inLine => layoutMode == 'row' || layoutMode == 'column';

  Json get ownStyle => {
    for (final MapEntry(:key, :value) in style.entries)
      if (!isPane || !_scrollbarKeys.contains(key)) key: value,
  };

  Json get scrollbarStyle => {
    for (final MapEntry(:key, :value) in style.entries)
      if (_scrollbarKeys.contains(key)) key: value,
  };

  /// A pane on cells never took the focus; a button's prefab takes its own.
  bool get takesFocus =>
      (_runsActs('press') || _runsActs('hold')) &&
      (!isPane || inLine) &&
      kind != 'button';

  bool _runsActs(String trigger) => switch (triggers[trigger]) {
    final List<Object?> acts => acts.isNotEmpty,
    _ => false,
  };
}

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

Json? _framedPart(Json pane) {
  for (final child in objectsIn(pane, 'children')) {
    if (jsonObject(child['options'])['frame'] == true) return child;
    if (child['kind'] != 'pane') continue;
    if (_framedPart(child) case final found?) return found;
  }
  return null;
}

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

class _NodeConverter {
  _NodeConverter(this.prefabs, this.dockedPrefabs);

  final Map<String, _PartKinds> prefabs;
  final Set<String> dockedPrefabs;

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
    final placedOnCells = parentMode != 'free';
    if (placedOnCells && node.transform.isNotEmpty) {
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

  void convertPrefab(Json prefab, Json root) {
    final kinds = _kindsIn(root);
    final columnsWide = _number(jsonObject(root['transform'])['w']) ?? 1;
    final double guessedWidth = 960 * min(1, columnsWide / 12);
    prefab['root'] = convert(root, parentMode: 'flow', width: guessedWidth);
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
