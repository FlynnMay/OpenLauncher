import 'package:flutter/foundation.dart';

/// What can fire a chain of actions.
enum Trigger {
  press('Pressed'),
  hold('Held down'),
  focus('The focus arrives'),
  blur('The focus leaves'),

  /// For things that are shown and hidden: a sidebar, a folder.
  reveal('It is revealed'),
  hide('It is hidden');

  const Trigger(this.label);

  final String label;
}

/// One saved action: an `ActionRegistry` name plus its arguments, such as the
/// `entity` that does it.
@immutable
class Act {
  const Act(this.name, [this.args = const {}]);

  final String name;
  final Map<String, Object?> args;

  /// The argument [key], if it is a string.
  String? arg(String key) => switch (args[key]) {
    final String value => value,
    _ => null,
  };

  static Act? fromJson(Object? json) => switch (json) {
    {'do': final String name} => Act(name, {
      for (final MapEntry(:key, :value) in (json as Map).entries)
        if (key is String && key != 'do') key: value,
    }),
    _ => null,
  };

  Map<String, Object?> toJson() => {'do': name, ...args};

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
