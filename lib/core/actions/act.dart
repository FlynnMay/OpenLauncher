import 'package:flutter/foundation.dart';

/// What can set a thing on the screen off.
enum Trigger {
  press('Pressed'),
  hold('Held down'),
  focus('The focus arrives'),
  blur('The focus leaves');

  const Trigger(this.label);

  final String label;
}

/// One thing to do, as it is saved: the name of an `ActionKind` and
/// whatever that kind is told beside, such as the `card` it is done to. An
/// action that names no card is done to the card it was set off from.
@immutable
class Act {
  const Act(this.name, [this.args = const {}]);

  final String name;
  final Map<String, Object?> args;

  /// What it is told under [key], if that is text.
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

/// What a thing does, by what sets it off. A trigger with an empty list
/// does nothing, whatever the thing would have done of itself.
typedef Triggers = Map<Trigger, List<Act>>;

/// Never throws: what is not understood is left out.
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
