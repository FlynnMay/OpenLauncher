/// Edits to the layout as data, and what each session can undo.
library;

import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/slice_command.dart';
import 'package:openlauncher_domain/json/json_read.dart';

export 'command.dart';
export 'command_history.dart';
export 'command_log.dart';
export 'document.dart';
export 'slice_command.dart';

/// Every command there is, by name. A new area of commands adds its own map.
final Map<String, CommandReader> _readers = {
  EditSlice.typeName: EditSlice.fromJson,
};

/// The command [json] describes. Throws [FormatException] if it names none.
Command commandFromJson(Object? json) {
  final map = jsonObject(json);
  final reader =
      _readers[map['type']] ??
      (throw FormatException('"${map['type']}" is not a command'));
  return reader(map);
}
