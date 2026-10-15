import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/sources/source.dart';
import 'package:openlauncher/core/sources/source_rows.dart';

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

/// Where an entity's live values come from: one source, written as an
/// address (`launcher://clock`), the name of a source in the same pack
/// (`states`), or in place (`{url: ..., every: 60}`).
@immutable
class Feed {
  const Feed(String this.name, {this.inline, this.shared}) : assert(name != '');

  const Feed.inline(Map<String, Object?> this.inline)
    : name = null,
      shared = null;

  /// An address, or a pack source's name.
  final String? name;

  /// A source written in place, kept as written so a half typed one is not
  /// lost; or the pack source [name] names, once found.
  final Map<String, Object?>? inline;

  /// What a pack source's fetch is known by, once found: `<pack>:<name>`.
  final String? shared;

  bool get isAddress => name?.contains('://') ?? false;

  /// The source, if it can be read: an address, or one written in place.
  Source? get source => isAddress
      ? Source(Uri.parse(name!), watch: true)
      : Source.fromJson(inline);

  /// The source and what its fetch is known by, for an entity called [id].
  SourceAt? at(String id) => switch (source) {
    null => null,
    final source => (id: isAddress ? name! : shared ?? id, source: source),
  };

  static Feed? fromJson(Object? json) => switch (json) {
    final String name when name.trim().isNotEmpty => Feed(name.trim()),
    final Map<Object?, Object?> inline => Feed.inline({
      for (final MapEntry(:key, :value) in inline.entries)
        if (key is String) key: value,
    }),
    _ => null,
  };

  Object? toJson() => name ?? inline;

  @override
  bool operator ==(Object other) =>
      other is Feed &&
      other.name == name &&
      other.shared == shared &&
      mapEquals(other.inline, inline);

  @override
  int get hashCode => Object.hash(name, shared);
}
