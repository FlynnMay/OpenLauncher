import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/entities/entity_action.dart';
import 'package:openlauncher/core/entities/http_feed.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/nodes/field.dart';
import 'package:openlauncher/core/operations/operation.dart';

/// The most entities a user can make.
const maxUserEntities = 24;

/// Ids an entity the user makes may not take: what an action's templates
/// read itself as.
const reservedIds = {'self'};

/// The user's own entities from a save. Skips what cannot be read, duplicate
/// ids, ids that are not plain slugs and [reservedIds].
List<Entity> userEntitiesFromJson(Object? json) {
  final used = {...reservedIds};
  return [
    if (json is List)
      for (final one in json.take(maxUserEntities))
        if (Entity.fromJson(one) case final entity?
            when entity.id == slugOf(entity.id, '') && used.add(entity.id))
          entity,
  ];
}

// Form values of `kind`.
const _text = 'text', _web = 'http';

String _kind(Map<String, Object?> one) => '${one['kind'] ?? _web}';

// A bound argument's key in an action's form row.
const _with = 'with:';

/// The editor's form for the user's entities, over [userEntityToForm]. An
/// action is offered [operations] to run.
Field userEntityOptions(Iterable<Operation> operations) => Field(
  'entities',
  'Add entity',
  FieldKind.list,
  heading: 'name',
  asks: 'Entity name',
  blank: const {'name': 'Value'},
  max: maxUserEntities,
  fields: (one) => [
    const Field('name', 'Name', FieldKind.text),
    Field(
      'kind',
      'Source',
      FieldKind.choice,
      defaultValue: _web,
      choices: {
        _web: 'URL (JSON)',
        _text: 'Static text',
        // A feed written by hand is kept.
        if (!const {_web, _text}.contains(_kind(one))) _kind(one): _kind(one),
      },
    ),
    Field('text', 'Text', FieldKind.text, when: (one) => _kind(one) == _text),
    Field('url', 'URL', FieldKind.text, when: (one) => _kind(one) == _web),
    // Polled by the TV while something shows it.
    Field(
      'every',
      'Refresh interval (s)',
      FieldKind.number,
      defaultValue: 60,
      min: HttpFeed.minEvery,
      max: 3600,
      step: 10,
      when: (one) => _kind(one) == _web,
    ),
    Field(
      'actions',
      'Add action',
      FieldKind.list,
      heading: 'name',
      asks: 'Action name',
      blank: {'name': 'do', 'run': operations.firstOrNull?.name},
      fields: (action) => _actionFields(action, operations),
    ),
  ],
);

List<Field> _actionFields(
  Map<String, Object?> action,
  Iterable<Operation> operations,
) => [
  Field(
    'run',
    'Operation',
    FieldKind.choice,
    choices: {
      // Keeps one this build does not know.
      if (action['run'] case final String run) run: run,
      for (final operation in operations) operation.name: operation.label,
    },
  ),
  const Field('label', 'Label', FieldKind.text),
  const Field('icon', 'Icon', FieldKind.icon),
  // What is left empty, the act may say.
  ...argFields(
    _argsOf(operations, action['run']),
    keyPrefix: _with,
    free: FieldKind.template,
    unset: 'Set by the action',
  ),
];

Map<String, List<String>> _argsOf(
  Iterable<Operation> operations,
  Object? name,
) =>
    operations.where((operation) => operation.name == name).firstOrNull?.args ??
    const {};

/// [entity] as a row of the form.
Map<String, Object?> userEntityToForm(Entity entity) => {
  'id': entity.id,
  'name': entity.label,
  'kind': switch (entity.feed) {
    null => _text,
    Feed(:final inline?) when inline['url'] is String => _web,
    final feed => '${feed.toJson()}',
  },
  if (entity.feed?.inline case final inline? when inline['url'] is String) ...{
    'url': inline['url'],
    'every': inline['every'],
  },
  if (entity.feed == null) 'text': entity.data[_text],
  'actions': [
    for (final MapEntry(key: name, value: action) in entity.actions.entries)
      _actionToForm(name, action),
  ],
};

Map<String, Object?> _actionToForm(String name, EntityAction action) => {
  'name': name,
  'run': action.run,
  if (action.label.isNotEmpty) 'label': action.label,
  if (action.icon.isNotEmpty) 'icon': action.icon,
  for (final MapEntry(:key, :value) in action.bound.entries)
    '$_with$key': value,
};

/// The entity a form row describes. What the form does not show is kept
/// from [was], the entity the row was made from.
Entity userEntityFromForm(
  Map<String, Object?> one,
  Iterable<Operation> operations, {
  Entity? was,
}) {
  final kind = _kind(one);
  final name = '${one['name'] ?? ''}'.trim();
  return Entity(
    id: '${one['id']}',
    category: was?.category ?? userCategory,
    label: name.isEmpty ? '${one['id']}' : name,
    data: {
      for (final MapEntry(:key, :value) in (was?.data ?? const {}).entries)
        if (key != _text) key: value,
      if (kind == _text) _text: '${one['text'] ?? ''}',
    },
    feed: switch (kind) {
      _text => null,
      _web => Feed.inline({
        'url': '${one['url'] ?? ''}',
        'every': switch (one['every']) {
          final num every => every.toInt().clamp(
            HttpFeed.minEvery,
            HttpFeed.maxEvery,
          ),
          _ => 60,
        },
      }),
      _ => was?.feed,
    },
    actions: _actionsFromForm(one['actions'], operations),
    prefab: was?.prefab,
    placed: was?.placed ?? false,
  );
}

Map<String, EntityAction> _actionsFromForm(
  Object? rows,
  Iterable<Operation> operations,
) {
  final actions = <String, EntityAction>{};
  for (final row in rows is List<Object?> ? rows : const []) {
    if (row is! Map) continue;
    final called = '${row['name'] ?? ''}'.replaceAll(
      RegExp('[^A-Za-z0-9_]'),
      '',
    );
    if (called.isEmpty || actions.containsKey(called)) continue;
    if (_actionFromRow(row, operations) case final action?) {
      actions[called] = action;
    }
  }
  return actions;
}

EntityAction? _actionFromRow(Map row, Iterable<Operation> operations) {
  final run = row['run'];
  if (run is! String) return null;
  final bound = {
    for (final MapEntry(:key, :value) in row.entries)
      if (key is String &&
          key.startsWith(_with) &&
          value != null &&
          value != '')
        key.substring(_with.length): value,
  };
  return EntityAction(
    run: run,
    bound: bound,
    args: {
      for (final MapEntry(:key, :value) in _argsOf(operations, run).entries)
        if (!bound.containsKey(key)) key: value,
    },
    label: '${row['label'] ?? ''}',
    icon: '${row['icon'] ?? ''}',
  );
}
