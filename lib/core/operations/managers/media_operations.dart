import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// Commands for whatever is playing.
class MediaOperationsManager implements OperationsManager {
  MediaOperationsManager(this._platform);

  final LauncherPlatform _platform;

  @override
  late final List<Operation> operations = [
    Operation(
      name: 'os://media/command',
      label: 'Tell the media player',
      args: {
        'command': [for (final command in MediaCommand.values) command.name],
      },
      run: (run) async {
        final command = MediaCommand.values.asNameMap()[run.arg('command')];
        if (command == null) {
          throw FormatException('No media command "${run.args['command']}"');
        }
        await _platform.sendMediaCommand(command);
        return null;
      },
    ),
  ];
}
