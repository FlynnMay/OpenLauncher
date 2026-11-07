/// Edits to the layout as data, and what each session can undo.
library;

import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/screen_commands.dart';
import 'package:openlauncher_domain/json/json_read.dart';

export 'command.dart';
export 'command_history.dart';
export 'screen_commands.dart';

/// Every command there is, by name. A new area of commands adds its own map.
final Map<String, CommandReader> _readers = {...screenCommandReaders};

/// The command [json] describes. Throws [FormatException] if it names none.
Command commandFromJson(Object? json) {
  final map = jsonObject(json);
  _checkTarget(map['target']);
  final reader =
      _readers[map['type']] ??
      (throw FormatException('"${map['type']}" is not a command'));
  return reader(map);
}

void _checkTarget(Object? target) {
  if (target != null && target != 'layout') {
    throw const FormatException('A command can only edit the layout so far');
  }
}
