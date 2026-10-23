import 'package:openlauncher/core/config/migrations/save_json.dart';

const _newLayer = 'launcher://layers/new';
const _raiseLayer = 'launcher://layers/raise';
const _closeLayer = 'launcher://layers/close';

/// A layer's backdrop as an Overlay's values; dim as a percentage.
Json _backdrop(Json layer) => {
  if (layer['dim'] case final num dim when dim != 0)
    'dim': (dim.clamp(0, 1) * 100).round(),
  if (layer['blur'] case final num blur when blur != 0) 'blur': blur,
  if (layer['modal'] == true) 'modal': true,
};

Json _argumentsOf(Json act) => jsonObject(act['with']);

/// Whether [act] calls [address], on the node it is on if [onItself].
bool _calls(Object? act, String address, {bool onItself = false}) =>
    act is Json &&
    act['run'] == address &&
    (!onItself || _argumentsOf(act)['of'] == null);

/// [acts] calling the overlay addresses: a new layer then a raise opens the
/// raised node with the layer's backdrop, a raise alone opens it, a close
/// closes it, and a new layer alone is dropped. Adding to and removing from
/// a layer names the screen.
List<Object?> _rewritten(List<Object?> acts) {
  final rewritten = <Object?>[];
  Json? newLayer;
  for (final act in acts) {
    if (act is! Json) {
      rewritten.add(act);
    } else if (act['run'] == _newLayer) {
      newLayer = _argumentsOf(act);
    } else {
      rewritten.add(_rewrittenAct(act, newLayer));
      if (act['run'] == _raiseLayer) newLayer = null;
    }
  }
  return rewritten.map(_withoutEmptyArguments).toList();
}

/// [act], with [newLayer] the arguments of a new layer just before it.
Json _rewrittenAct(Json act, Json? newLayer) => switch (act['run']) {
  _raiseLayer => {
    'run': 'launcher://overlay/open',
    'with': {
      'of': ?_argumentsOf(act)['of'],
      if (newLayer != null) ..._backdrop(newLayer),
    },
  },
  _closeLayer => {
    'run': 'launcher://overlay/close',
    'with': {'of': ?_argumentsOf(act)['of']},
  },
  'launcher://layout/add' || 'launcher://layout/remove'
      when _argumentsOf(act).containsKey('layer') =>
    {...act, 'with': _layerAsScreen(_argumentsOf(act))},
  _ => act,
};

Json _layerAsScreen(Json arguments) {
  final renamed = {...arguments};
  renamed['screen'] = renamed.remove('layer');
  return renamed;
}

Object? _withoutEmptyArguments(Object? act) => switch (act) {
  {'with': final Json arguments} && final Json call when arguments.isEmpty =>
    without(call, {'with'}),
  _ => act,
};

/// A node that put itself on a new layer as it showed is an Overlay with
/// that layer's backdrop; its hide chain no longer closes the layer.
void _overlayIn(Json modules) {
  final triggers = modules['triggers'];
  if (triggers is! Json) return;
  final reveal = triggers['reveal'];
  if (reveal is! List<Object?>) return;
  final newLayerAt = reveal.indexWhere((act) => _calls(act, _newLayer));
  if (newLayerAt < 0 ||
      newLayerAt + 1 >= reveal.length ||
      !_calls(reveal[newLayerAt + 1], _raiseLayer, onItself: true)) {
    return;
  }
  modules['overlay'] = {
    ...jsonObject(modules['overlay']),
    ..._backdrop(_argumentsOf(reveal[newLayerAt]! as Json)),
  };
  triggers['reveal'] = [...reveal]..removeRange(newLayerAt, newLayerAt + 2);
  if (triggers['hide'] case final List<Object?> hide) {
    triggers['hide'] = [
      for (final act in hide)
        if (!_calls(act, _closeLayer, onItself: true)) act,
    ];
  }
  for (final key in const ['reveal', 'hide']) {
    if (triggers[key] case final List<Object?> left when left.isEmpty) {
      triggers.remove(key);
    }
  }
  if (triggers.isEmpty) modules.remove('triggers');
}

bool _isAct(Object? json) => json is Json && json['run'] is String;

/// [json] with Overlays made and every act rewritten, in a list or on its
/// own; one left with nothing to do goes.
Object? _rewrittenIn(Object? json) => switch (json) {
  final Json object => _objectRewritten(object),
  final List<Object?> list => [
    for (final item in list.any(_isAct) ? _rewritten(list) : list)
      _rewrittenIn(item),
  ],
  _ => json,
};

Json _objectRewritten(Json object) {
  if (object['modules'] case final Json modules) _overlayIn(modules);
  for (final MapEntry(:key, :value) in [...object.entries]) {
    if (!_isAct(value)) {
      object[key] = _rewrittenIn(value);
      continue;
    }
    switch (_rewritten([value])) {
      case [final act]:
        object[key] = _rewrittenIn(act);
      case _:
        object.remove(key);
    }
  }
  return object;
}

/// Layers are gone: the layout holds screens, home first. A saved layer
/// above home is a node on home with an Overlay of its backdrop, opened by
/// `launcher://overlay/open`. What made, raised or closed layers makes an
/// Overlay or calls the overlay addresses.
void overlaysForLayers(Json save, Device device) {
  if (layoutOf(save) case final layout?) _layersAsScreens(layout);
  for (final key in const ['layout', 'prefabs', 'entities']) {
    if (save[key] != null) save[key] = _rewrittenIn(save[key]);
  }
}

void _layersAsScreens(Json layout) {
  final layers = objectsIn(layout, 'layers');
  layout.remove('layers');
  final home = layers.where((layer) => layer['id'] == 'home').firstOrNull;
  final overlays = [
    for (final layer in layers)
      if (layer != home)
        if (layer['root'] case final Json root) _overlayNode(layer, root),
  ];
  layout['screens'] = [if (home != null) _homeScreen(home, overlays)];
}

/// [layer]'s [root] as a node with an Overlay of its backdrop.
Json _overlayNode(Json layer, Json root) => {
  ...root,
  if (root['name'] == null) 'name': layer['id'],
  'modules': {...jsonObject(root['modules']), 'overlay': _backdrop(layer)},
};

Json _homeScreen(Json home, List<Json> overlays) => {
  'id': 'home',
  if (home['root'] case final Json root)
    'root': {
      ...root,
      'children': [...objectsIn(root, 'children'), ...overlays],
    },
};
