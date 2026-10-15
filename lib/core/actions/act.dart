import 'package:flutter/foundation.dart';

/// What can fire a chain of actions.
enum Trigger {
  press('On press'),
  hold('On hold'),
  focus('On focus'),
  blur('On blur'),

  /// For things that are shown and hidden: a sidebar, a folder.
  reveal('On show'),
  hide('On hide');

  const Trigger(this.label);

  final String label;
}

/// The argument naming the entity that does an action. Every act has one.
const entityArg = 'entity';

/// [entityArg] for the entity a tile's `source` variable holds.
const sourceEntity = '{{source.id}}';

/// One saved action: either an entity's action by name, with the
/// [entityArg] that defines and does it and its other arguments
/// (`{"do": "open", "entity": "..."}`), or an address called directly with
/// what it is told (`{"run": "launcher://layers/new", "with": {...}}`).
@immutable
class Act {
  const Act(this.name, [this.args = const {}]);

  /// An action's name, or an address.
  final String name;
  final Map<String, Object?> args;

  /// Whether it calls an address rather than an entity's action.
  bool get isAddress => name.contains('://');

  /// The argument [key], if it is a string.
  String? arg(String key) => switch (args[key]) {
    final String value => value,
    _ => null,
  };

  static Act? fromJson(Object? json) => switch (json) {
    {'run': final String address} when address.contains('://') => Act(
      address,
      switch (json['with']) {
        final Map<Object?, Object?> told => {
          for (final MapEntry(:key, :value) in told.entries)
            if (key is String) key: value,
        },
        _ => const {},
      },
    ),
    {'do': final String name} => Act(name, {
      for (final MapEntry(:key, :value) in (json as Map).entries)
        if (key is String && key != 'do') key: value,
    }),
    _ => null,
  };

  Map<String, Object?> toJson() => isAddress
      ? {'run': name, if (args.isNotEmpty) 'with': args}
      : {'do': name, ...args};

  @override
  bool operator ==(Object other) =>
      other is Act && other.name == name && mapEquals(other.args, args);

  @override
  int get hashCode => Object.hash(name, Object.hashAllUnordered(args.keys));
}

/// Actions per trigger. An empty list disables the prefab's default.
typedef Triggers = Map<Trigger, List<Act>>;

/// Skips what it cannot read. Never throws.
Triggers triggersFromJson(Object? json) => {
  if (json is Map)
    for (final trigger in Trigger.values)
      if (json[trigger.name] case final List<Object?> acts)
        trigger: [for (final act in acts) ?Act.fromJson(act)],
};

Map<String, Object?> triggersToJson(Triggers triggers) => {
  for (final MapEntry(key: trigger, value: acts) in triggers.entries)
    trigger.name: [for (final act in acts) act.toJson()],
};
