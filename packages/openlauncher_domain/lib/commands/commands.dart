/// Edits to the layout as data, and what each session can undo.
library;

import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/config_commands.dart';
import 'package:openlauncher_domain/commands/layout_reset_commands.dart';
import 'package:openlauncher_domain/commands/node_commands.dart';
import 'package:openlauncher_domain/commands/prefab_commands.dart';
import 'package:openlauncher_domain/commands/prefab_library_commands.dart';
import 'package:openlauncher_domain/commands/scope_commands.dart';
import 'package:openlauncher_domain/commands/screen_commands.dart';
import 'package:openlauncher_domain/commands/shape_commands.dart';
import 'package:openlauncher_domain/commands/slice_command.dart';
import 'package:openlauncher_domain/json/json_read.dart';

export 'command.dart';
export 'command_history.dart';
export 'command_log.dart';
export 'config_commands.dart';
export 'document.dart';
export 'layout_reset_commands.dart';
export 'node_commands.dart';
export 'prefab_commands.dart';
export 'prefab_library_commands.dart';
export 'scope_commands.dart';
export 'screen_commands.dart';
export 'shape_commands.dart';
export 'slice_command.dart';

/// Every command there is, by name. A new area of commands adds its own map.
final Map<String, CommandReader> _readers = {
  ...nodeCommandReaders,
  ...screenCommandReaders,
  ...shapeCommandReaders,
  ...layoutResetCommandReaders,
  ...prefabCommandReaders,
  ...prefabLibraryCommandReaders,
  EditSlice.typeName: EditSlice.fromJson,
  SetConfig.typeName: SetConfig.fromJson,
  InPrefab.typeName: (json) => InPrefab.fromJson(json, commandFromJson),
  Batch.typeName: (json) => Batch.fromJson(json, commandFromJson),
};

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
