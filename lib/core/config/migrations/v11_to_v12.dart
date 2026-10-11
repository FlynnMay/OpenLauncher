import 'package:openlauncher/core/config/migrations/save_json.dart';

// The parts of the launcher's own prefabs that were small pictures when
// this was written: their `size` is not one of letters.
const _icons = {
  'weather': {'icon'},
  'now-playing': {'state'},
};

Json _styleOf(Json thing) {
  final style = <String, Object?>{
    if (thing['style'] case final Map<Object?, Object?> there) ...there.cast(),
  };
  thing['style'] = style;
  return style;
}

void _tidy(Json thing) {
  if (thing['style'] case final Map<Object?, Object?> style
      when style.isEmpty) {
    thing.remove('style');
  }
}

/// The look of a box was its `colors`, their `stops` and `angle`, and a
/// `border`; a pane kept its `corners` and `padding` beside that.
void _box(Json thing) {
  final was = switch (thing.remove('style')) {
    final Map<Object?, Object?> style => style,
    _ => const <Object?, Object?>{},
  };
  final style = _styleOf(thing);
  switch (was['colors']) {
    case [final String only]:
      style['background'] = only;
    case final List<Object?> colors when colors.length > 1:
      style['background'] = {
        'colors': colors,
        'stops': ?was['stops'],
        'angle': ?was['angle'],
      };
  }
  if (was['border'] case final String border) style['borderColor'] = border;
  switch (thing.remove('corners')) {
    case final List<Object?> corners when corners.length == 4:
      style['radius'] = corners.toSet().length == 1 ? corners.first : corners;
  }
  if (thing.remove('padding') case final num padding) {
    style['padding'] = padding;
  }
  _tidy(thing);
}

/// What a widget, or a part of a prefab, said of its look among its other
/// [options] goes under the names every look has, in a `style` of its
/// own. [letters] is false for a small picture, whose `size` is not one
/// of letters and stays where it is.
void _look(Json options, {bool letters = true}) {
  final style = _styleOf(options);
  void move(String from, String to) {
    if (options.remove(from) case final value?) style[to] = value;
  }

  move('colour', 'color');
  move('align', 'textAlign');
  move('round', 'radius');
  // Before letters had a weight they were bold or not.
  if (options.remove('bold') == true) style['fontWeight'] = 'bold';
  move('weight', 'fontWeight');
  if (letters) move('size', 'fontSize');
  _tidy(options);
}

/// What is set for each of a prefab's parts by name, [icons] being those
/// that are small pictures.
void _parts(Object? parts, Set<String> icons) {
  if (parts is! Json) return;
  for (final MapEntry(:key, :value) in parts.entries) {
    if (value is Json) _look(value, letters: !icons.contains(key));
  }
}

void _slots(Json layout, Set<String> icons) {
  for (final slot in objectsIn(layout, 'parts')) {
    if (slot['group'] case final Json group) _slots(group, icons);
    if (slot['options'] case final Json options) {
      _look(options, letters: !icons.contains(slot['part']));
      if (options.isEmpty) slot.remove('options');
    }
  }
}

/// Everything on the screen has one look, a `style` of named properties
/// (`background`, `borderColor`, `radius`, `padding`, `color`, `fontSize`,
/// ...), where there were a box's colours, a pane's corners and padding,
/// and each kind of widget's own options.
void stylesAsOne(Json save, Device device) {
  final icons = {..._icons};
  for (final prefab in objectsIn(save, 'prefabs')) {
    final own = <String>{};
    if (prefab['parts'] case final Json parts) {
      for (final MapEntry(:key, :value) in parts.entries) {
        if (value is! Json) continue;
        if (value['kind'] == 'icon') own.add(key);
        _look(value, letters: value['kind'] != 'icon');
      }
    }
    if (prefab['id'] case final String id) icons[id] = own;
    if (prefab['layouts'] case final Json layouts) {
      for (final layout in layouts.values) {
        if (layout is Json) _slots(layout, own);
      }
    }
  }
  final layout = layoutOf(save);
  if (layout == null) return;
  for (final pane in panesOf(layout)) {
    _box(pane);
    if (pane['rules'] case final Json rules) {
      for (final MapEntry(:key, :value) in rules.entries) {
        if (value is Json) _parts(value['parts'], icons[key] ?? const {});
      }
    }
    for (final item in itemsOf(pane)) {
      _box(item);
      final options = item['options'];
      if (options is! Json) continue;
      if (item['kind'] == 'widget') {
        _look(options, letters: item['ref'] != 'icon');
        if (options.remove('style') case final Json look) {
          _styleOf(item).addAll(look);
        }
        if (options.isEmpty) item.remove('options');
      } else if (item['kind'] == 'prefab') {
        _parts(options['parts'], icons[item['ref']] ?? const {});
      }
    }
  }
}
