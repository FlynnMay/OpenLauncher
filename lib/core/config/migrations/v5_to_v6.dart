import 'package:openlauncher/core/config/migrations/save_json.dart';

/// What an action was told as `card`, the thing to do it to, it is told as
/// `entity`.
void _renameArg(Object? on) {
  if (on is! Json) return;
  for (final acts in on.values) {
    if (acts is! List<Object?>) continue;
    for (final act in acts) {
      if (act is Json && act.containsKey('card')) {
        act['entity'] = act.remove('card');
      }
    }
  }
}

/// A card is no longer a kind of item: it is an instance of a prefab,
/// drawn from an entity. What was `kind: card, ref: <the app>` says so:
/// `kind: prefab`, `ref` the prefab (`app-card`, unless it named another
/// among its options) and `source` the entity. An item that said no kind
/// was a card.
void cardsAsInstances(Json save, Device device) {
  final layout = layoutOf(save);
  if (layout == null) return;
  for (final pane in panesOf(layout)) {
    for (final item in itemsOf(pane)) {
      _renameArg(item['on']);
      final kind = item['kind'];
      if (kind != null && kind != 'card') continue;
      final options = item['options'];
      var prefab = 'app-card';
      if (options is Json) {
        if (options.remove('prefab') case final String named) prefab = named;
        if (options.isEmpty) item.remove('options');
      }
      item['kind'] = 'prefab';
      item['source'] = item['ref'];
      item['ref'] = prefab;
    }
  }
}

/// The same for what the user's prefabs do.
void prefabActsOnEntities(Json save, Device device) {
  for (final prefab in objectsIn(save, 'prefabs')) {
    _renameArg(prefab['on']);
  }
}
