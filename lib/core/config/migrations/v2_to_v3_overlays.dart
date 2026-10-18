import 'package:openlauncher/core/config/migrations/save_json.dart';

const _new = 'launcher://layers/new',
    _raise = 'launcher://layers/raise',
    _close = 'launcher://layers/close';

/// A layer's backdrop as an Overlay's values; dim as a percentage.
Json _backdrop(Json from) => {
  if (from['dim'] case final num dim when dim != 0)
    'dim': (dim.clamp(0, 1) * 100).round(),
  if (from['blur'] case final num blur when blur != 0) 'blur': blur,
  if (from['modal'] == true) 'modal': true,
};

Json _with(Json act) => switch (act['with']) {
  final Json args => args,
  _ => <String, Object?>{},
};

bool _runs(Object? act, String address, {bool self = false}) =>
    act is Json && act['run'] == address && (!self || _with(act)['of'] == null);

/// [acts] calling the overlay addresses: a new layer then a raise opens the
/// raised node with the layer's backdrop, a raise alone opens it, a close
/// closes it, and a new layer alone is dropped. Adding to and removing from
/// a layer names the screen.
List<Object?> _rewritten(List<Object?> acts) {
  final out = <Object?>[];
  Json? made;
  for (final act in acts) {
    if (act is! Json) {
      out.add(act);
      continue;
    }
    switch (act['run']) {
      case _new:
        made = _with(act);
      case _raise:
        out.add({
          'run': 'launcher://overlay/open',
          'with': {
            'of': ?_with(act)['of'],
            ...?(made == null ? null : _backdrop(made)),
          },
        });
        made = null;
      case _close:
        out.add({
          'run': 'launcher://overlay/close',
          'with': {'of': ?_with(act)['of']},
        });
      case 'launcher://layout/add' || 'launcher://layout/remove'
          when _with(act).containsKey('layer'):
        final args = {..._with(act)};
        args['screen'] = args.remove('layer');
        out.add({...act, 'with': args});
      default:
        out.add(act);
    }
  }
  return [
    for (final act in out)
      if (act case {'with': final Json args} when args.isEmpty)
        {...act}..remove('with')
      else
        act,
  ];
}

/// A node that put itself on a new layer as it showed is an Overlay with
/// that layer's backdrop; its hide chain no longer closes the layer.
void _overlayIn(Json modules) {
  final triggers = modules['triggers'];
  if (triggers is! Json) return;
  final reveal = triggers['reveal'];
  if (reveal is! List<Object?>) return;
  final at = reveal.indexWhere((act) => _runs(act, _new));
  if (at < 0 ||
      at + 1 >= reveal.length ||
      !_runs(reveal[at + 1], _raise, self: true)) {
    return;
  }
  modules['overlay'] = {
    ...?(modules['overlay'] is Json ? modules['overlay']! as Json : null),
    ..._backdrop(_with(reveal[at]! as Json)),
  };
  triggers['reveal'] = [...reveal]..removeRange(at, at + 2);
  if (triggers['hide'] case final List<Object?> hide) {
    triggers['hide'] = [
      for (final act in hide)
        if (!_runs(act, _close, self: true)) act,
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

/// Walks [json], making Overlays and rewriting every act, in a list or on
/// its own; one left with nothing to do goes.
Object? _walk(Object? json) {
  switch (json) {
    case final Json map:
      if (map['modules'] case final Json modules) _overlayIn(modules);
      for (final MapEntry(:key, :value) in [...map.entries]) {
        if (_isAct(value)) {
          switch (_rewritten([value])) {
            case [final act]:
              map[key] = _walk(act);
            case _:
              map.remove(key);
          }
        } else {
          map[key] = _walk(value);
        }
      }
      return map;
    case final List<Object?> list:
      final acts = list.any(_isAct);
      return [for (final one in acts ? _rewritten(list) : list) _walk(one)];
    default:
      return json;
  }
}

/// Layers are gone: the layout holds screens, home first. A saved layer
/// above home is a node on home with an Overlay of its backdrop, opened by
/// `launcher://overlay/open`. What made, raised or closed layers makes an
/// Overlay or calls the overlay addresses.
void overlaysForLayers(Json save, Device device) {
  if (layoutOf(save) case final layout?) {
    final layers = objectsIn(layout, 'layers');
    layout.remove('layers');
    final home = layers.where((layer) => layer['id'] == 'home').firstOrNull;
    final above = [
      for (final layer in layers)
        if (layer != home && layer['root'] is Json)
          {
            ...layer['root']! as Json,
            if ((layer['root']! as Json)['name'] == null) 'name': layer['id'],
            'modules': {
              ...?((layer['root']! as Json)['modules'] as Json?),
              'overlay': _backdrop(layer),
            },
          },
    ];
    layout['screens'] = [
      if (home != null)
        {
          'id': 'home',
          if (home['root'] case final Json root)
            'root': {
              ...root,
              'children': [...objectsIn(root, 'children'), ...above],
            },
        },
    ];
  }
  for (final key in const ['layout', 'prefabs', 'entities']) {
    if (save[key] != null) save[key] = _walk(save[key]);
  }
}
