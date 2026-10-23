import 'package:flutter/foundation.dart';

/// What can fire a chain of actions.
enum Trigger {
  press('On press'),
  hold('On hold'),
  focus('On focus'),
  blur('On blur'),

  /// For things that are shown and hidden: a docked container.
  reveal('On show'),
  hide('On hide');

  const Trigger(this.label);

  final String label;
}

/// The argument naming the entity that does an action. Every act has one.
const entityArg = 'entity';

/// One saved action: an entity's action by name (`{"do": "open", "entity":
/// "..."}`), or an address called directly (`{"run":
/// "launcher://overlay/open", "with": {...}}`).
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
      _stringKeyed(json['with']),
    ),
    {'do': final String name} => Act(name, _stringKeyed(json)..remove('do')),
    _ => null,
  };

  static Map<String, Object?> _stringKeyed(Object? json) => {
    if (json is Map<Object?, Object?>)
      for (final MapEntry(:key, :value) in json.entries)
        if (key is String) key: value,
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
        trigger: _actsFromJson(acts),
};

List<Act> _actsFromJson(List<Object?> json) => [
  for (final act in json) ?Act.fromJson(act),
];

Map<String, Object?> triggersToJson(Triggers triggers) => {
  for (final MapEntry(key: trigger, value: acts) in triggers.entries)
    trigger.name: _actsToJson(acts),
};

List<Object?> _actsToJson(List<Act> acts) => [
  for (final act in acts) act.toJson(),
];
