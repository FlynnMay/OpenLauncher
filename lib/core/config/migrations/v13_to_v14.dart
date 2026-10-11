import 'package:openlauncher/core/config/migrations/save_json.dart';

/// Takes what [from] has under each of [keys] and keeps it together as its
/// `rules`, but for what is only the [usual].
void _gather(
  Json from,
  List<String> keys, [
  Map<String, Object?> usual = const {},
]) {
  final rules = <String, Object?>{
    if (from['rules'] case final Map<Object?, Object?> there) ...there.cast(),
    for (final key in keys)
      if (from.remove(key) case final value? when value != usual[key])
        key: value,
  };
  if (rules.isNotEmpty) from['rules'] = rules;
}

/// What a panel is set to as a pane that is shown and hidden, and a pane's
/// own measures, stood each by itself beside the title; they are kept
/// together now, as its `rules`. What a pane says of each prefab had that
/// name, and is its `prefabRules`.
void settingsAsRules(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout == null) return;
  for (final pane in panesOf(layout)) {
    final prefabs = pane.remove('rules');
    if (prefabs is Map && prefabs.isNotEmpty) pane['prefabRules'] = prefabs;
    _gather(pane, const ['spacing', 'rowHeight', 'itemW', 'itemH']);
  }
  for (final panel in panelsOf(layout)) {
    _gather(
      panel,
      const [
        'position',
        'size',
        'width',
        'height',
        'closed',
        'opening',
        'reveal',
      ],
      const {
        'position': 'center',
        'size': 'medium',
        'opening': 'expand',
        'reveal': 'always',
      },
    );
  }
}
