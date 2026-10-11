import 'package:openlauncher/core/components/component_option.dart';
import 'package:openlauncher/core/entities/built_in_entities.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/core/entities/entity_action.dart';
import 'package:openlauncher/core/entities/http_feed.dart';
import 'package:openlauncher/core/layout/layout_ids.dart';
import 'package:openlauncher/core/operations/operation.dart';

/// The most entities a user can make.
const maxUserEntities = 24;

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

const _text = 'text';

String _kind(Map<String, Object?> one) => '${one['kind'] ?? httpFeed}';

// A bound argument's key in an action's form row.
const _with = 'with:';

/// The editor's form for the user's entities, over [userEntityToForm]. An
/// action is offered [operations] to run.
ComponentOption userEntityOptions(
  Iterable<Operation> operations,
) => ComponentOption(
  'entities',
  'Add an entity',
  OptionKind.list,
  heading: 'name',
  asks: 'Name of the entity',
  blank: const {'name': 'Value'},
  max: maxUserEntities,
  fields: (one) => [
    const ComponentOption('name', 'Name', OptionKind.text),
    ComponentOption(
      'kind',
      'Its value comes from',
      OptionKind.choice,
      usual: httpFeed,
      choices: {
        httpFeed: 'Web address (JSON)',
        _text: 'Fixed text',
        // A feed written by hand is kept.
        if (!const {httpFeed, _text}.contains(_kind(one)))
          _kind(one): _kind(one),
      },
    ),
    ComponentOption(
      'text',
      'Text',
      OptionKind.text,
      when: (one) => _kind(one) == _text,
    ),
    ComponentOption(
      'url',
      'Web address',
      OptionKind.text,
      when: (one) => _kind(one) == httpFeed,
    ),
    // Polled by the TV while something shows it.
    ComponentOption(
      'every',
      'Seconds between asking',
      OptionKind.number,
      usual: 60,
      min: HttpFeed.minEvery,
      max: 3600,
      step: 10,
      when: (one) => _kind(one) == httpFeed,
    ),
    ComponentOption(
      'actions',
      'Add an action',
      OptionKind.list,
      heading: 'name',
      asks: 'Name of the action',
      blank: {'name': 'do', 'run': operations.firstOrNull?.name},
      fields: (action) => [
        ComponentOption(
          'run',
          'Runs',
          OptionKind.choice,
          choices: {
            // Keeps one this build does not know.
            if (action['run'] case final String run) run: run,
            for (final operation in operations) operation.name: operation.label,
          },
        ),
        const ComponentOption('label', 'Label', OptionKind.text),
        const ComponentOption('icon', 'Icon', OptionKind.icon),
        // What is left empty, the act may say.
        for (final MapEntry(key: name, value: choices)
            in (operations
                        .where((one) => one.name == action['run'])
                        .firstOrNull
                        ?.args ??
                    const <String, List<String>>{})
                .entries)
          choices.isEmpty
              ? ComponentOption('$_with$name', name, OptionKind.template)
              : ComponentOption(
                  '$_with$name',
                  name,
                  OptionKind.choice,
                  unset: 'Said by the act',
                  choices: {for (final choice in choices) choice: choice},
                ),
      ],
    ),
  ],
);

/// [entity] as a row of the form.
Map<String, Object?> userEntityToForm(Entity entity) => {
  'id': entity.id,
  'name': entity.label,
  'kind': entity.feed?.from ?? _text,
  if (entity.feed?.from == httpFeed) ...{
    'url': entity.feed!.options['url'],
    'every': entity.feed!.options['every'],
  },
  if (entity.feed == null) 'text': entity.data[_text],
  'actions': [
    for (final MapEntry(key: name, value: action) in entity.actions.entries)
      {
        'name': name,
        'run': action.run,
        if (action.label.isNotEmpty) 'label': action.label,
        if (action.icon.isNotEmpty) 'icon': action.icon,
        for (final MapEntry(:key, :value) in action.bound.entries)
          '$_with$key': value,
      },
  ],
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
  final actions = <String, EntityAction>{};
  if (one['actions'] case final List<Object?> rows) {
    for (final row in rows) {
      if (row is! Map) continue;
      final called = '${row['name'] ?? ''}'.replaceAll(
        RegExp('[^A-Za-z0-9_]'),
        '',
      );
      final run = row['run'];
      if (called.isEmpty || run is! String || actions.containsKey(called)) {
        continue;
      }
      final takes =
          operations.where((one) => one.name == run).firstOrNull?.args ??
          const <String, List<String>>{};
      final bound = {
        for (final MapEntry(:key, :value) in row.entries)
          if (key is String &&
              key.startsWith(_with) &&
              value != null &&
              value != '')
            key.substring(_with.length): value,
      };
      actions[called] = EntityAction(
        run: run,
        bound: bound,
        args: {
          for (final MapEntry(:key, :value) in takes.entries)
            if (!bound.containsKey(key)) key: value,
        },
        label: '${row['label'] ?? ''}',
        icon: '${row['icon'] ?? ''}',
      );
    }
  }
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
      httpFeed => Feed(httpFeed, {
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
    actions: actions,
    prefab: was?.prefab,
    placed: was?.placed ?? false,
  );
}
