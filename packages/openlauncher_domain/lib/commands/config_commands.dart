import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/document.dart';
import 'package:openlauncher_domain/json/json_read.dart';

/// Sets settings, each key to a whole new value. Its inverse sets the same
/// keys back to what they were.
class SetConfig extends Command {
  const SetConfig(this.values);

  factory SetConfig.fromJson(Json json) =>
      SetConfig(jsonObject(json['values']));

  static const typeName = 'config.set';

  final Map<String, Object?> values;

  @override
  String get type => typeName;

  @override
  Document edit(Document document) {
    final unknown = values.keys.where(
      (key) => !document.settings.containsKey(key),
    );
    if (unknown.isNotEmpty) {
      throw CommandRefused('Not a setting: ${unknown.join(', ')}');
    }
    return document.copyWith(settings: {...document.settings, ...values});
  }

  @override
  Command undoing(Document before) =>
      SetConfig({for (final key in values.keys) key: before.settings[key]});

  @override
  Map<String, Object?> toJson() => {'type': type, 'values': values};
}

/// Commands done as one step: one undo takes back all of them.
class Batch extends Command {
  const Batch(this.commands);

  factory Batch.fromJson(Json json, CommandReader read) => Batch([
    for (final entry in jsonRequired<List<Object?>>(json, 'commands'))
      read(jsonObject(entry)),
  ]);

  static const typeName = 'batch';

  final List<Command> commands;

  @override
  String get type => typeName;

  @override
  Document edit(Document document) =>
      commands.fold(document, (current, command) => command.edit(current));

  @override
  Command undoing(Document before) {
    final undos = <Command>[];
    var current = before;
    for (final command in commands) {
      undos.add(command.undoing(current));
      current = command.edit(current);
    }
    return Batch(undos.reversed.toList());
  }

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'commands': [for (final command in commands) command.toJson()],
  };
}
