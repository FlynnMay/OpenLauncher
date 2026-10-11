import 'package:flutter/foundation.dart';

/// An action an entity defines: the operation it runs and the arguments it
/// binds from the entity's own values.
@immutable
class EntityAction {
  const EntityAction({
    required this.run,
    this.bound = const {},
    this.args = const {},
    this.label = '',
    this.icon = '',
  });

  /// The `OperationsRegistry` name.
  final String run;

  /// Arguments it gives the operation, saved as `with`. A template reads the
  /// entity as `self`, e.g. `{{self.package}}`.
  final Map<String, Object?> bound;

  /// Arguments an act may add, each with its allowed values (empty =
  /// anything).
  final Map<String, List<String>> args;

  /// Display name; empty for the name it goes by.
  final String label;

  /// Default icon for a button that does this.
  final String icon;

  static EntityAction? fromJson(Object? json) => switch (json) {
    {'run': final String run} => EntityAction(
      run: run,
      bound: switch (json['with']) {
        final Map<Object?, Object?> bound => {
          for (final MapEntry(:key, :value) in bound.entries)
            if (key is String) key: value,
        },
        _ => const {},
      },
      args: switch (json['args']) {
        final Map<Object?, Object?> args => {
          for (final MapEntry(:key, :value) in args.entries)
            if (key is String)
              key: [
                if (value is List)
                  for (final choice in value) '$choice',
              ],
        },
        _ => const {},
      },
      label: switch (json['label']) {
        final String label => label,
        _ => '',
      },
      icon: switch (json['icon']) {
        final String icon => icon,
        _ => '',
      },
    ),
    _ => null,
  };

  Map<String, Object?> toJson() => {
    'run': run,
    if (bound.isNotEmpty) 'with': bound,
    if (args.isNotEmpty) 'args': args,
    if (label.isNotEmpty) 'label': label,
    if (icon.isNotEmpty) 'icon': icon,
  };

  @override
  bool operator ==(Object other) =>
      other is EntityAction &&
      other.run == run &&
      other.label == label &&
      other.icon == icon &&
      mapEquals(other.bound, bound) &&
      other.args.length == args.length &&
      args.entries.every((arg) => listEquals(other.args[arg.key], arg.value));

  @override
  int get hashCode => Object.hash(run, label, icon);
}

/// Where an entity's live values come from: a `feeds` name and what that
/// feed is told, e.g. `{from: http, url: ..., every: 60}`.
@immutable
class Feed {
  const Feed(this.from, [this.options = const {}]);

  final String from;
  final Map<String, Object?> options;

  static Feed? fromJson(Object? json) => switch (json) {
    {'from': final String from} => Feed(from, {
      for (final MapEntry(:key, :value) in (json as Map).entries)
        if (key is String && key != 'from') key: value,
    }),
    _ => null,
  };

  Map<String, Object?> toJson() => {'from': from, ...options};

  @override
  bool operator ==(Object other) =>
      other is Feed && other.from == from && mapEquals(other.options, options);

  @override
  int get hashCode => Object.hash(from, Object.hashAllUnordered(options.keys));
}
