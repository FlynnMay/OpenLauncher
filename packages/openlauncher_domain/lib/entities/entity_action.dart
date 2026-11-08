import 'package:meta/meta.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/json/shallow_equality.dart';
import 'package:openlauncher_domain/sources/source.dart';

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
    this.then,
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

  /// A source of the entity's pack to fetch again once this is done, so what
  /// it changed shows at once.
  final String? then;

  static EntityAction? fromJson(Object? json) => switch (json) {
    {'run': final String run} => EntityAction(
      run: run,
      bound: jsonStringKeyed(json['with']),
      args: _choicesFrom(json['args']),
      label: switch (json['label']) {
        final String label => label,
        _ => '',
      },
      icon: switch (json['icon']) {
        final String icon => icon,
        _ => '',
      },
      then: switch (json['then']) {
        final String then when then.isNotEmpty => then,
        _ => null,
      },
    ),
    _ => null,
  };

  static Map<String, List<String>> _choicesFrom(Object? json) => {
    for (final MapEntry(:key, :value) in jsonStringKeyed(json).entries)
      key: _asStrings(value),
  };

  static List<String> _asStrings(Object? value) => [
    if (value is List)
      for (final choice in value) '$choice',
  ];

  Map<String, Object?> toJson() => {
    'run': run,
    if (bound.isNotEmpty) 'with': bound,
    if (args.isNotEmpty) 'args': args,
    if (label.isNotEmpty) 'label': label,
    if (icon.isNotEmpty) 'icon': icon,
    'then': ?then,
  };

  @override
  bool operator ==(Object other) =>
      other is EntityAction &&
      other.run == run &&
      other.label == label &&
      other.icon == icon &&
      other.then == then &&
      mapsEqual(other.bound, bound) &&
      other.args.length == args.length &&
      args.entries.every((arg) => listsEqual(other.args[arg.key], arg.value));

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
      ? Source(name!, watch: true)
      : switch (shared) {
          final String shared when shared.contains(':') => Source.fromJson(
            inline,
          )?.inPack(shared.substring(0, shared.indexOf(':'))),
          _ => Source.fromJson(inline),
        };

  /// The source and what its fetch is known by, for an entity called [id].
  SourceAt? at(String id) => switch (source) {
    null => null,
    final source => (id: isAddress ? name! : shared ?? id, source: source),
  };

  static Feed? fromJson(Object? json) => switch (json) {
    final String name when name.trim().isNotEmpty => Feed(name.trim()),
    final Map<Object?, Object?> inline => Feed.inline(jsonStringKeyed(inline)),
    _ => null,
  };

  Object? toJson() => name ?? inline;

  @override
  bool operator ==(Object other) =>
      other is Feed &&
      other.name == name &&
      other.shared == shared &&
      mapsEqual(other.inline, inline);

  @override
  int get hashCode => Object.hash(name, shared);
}
