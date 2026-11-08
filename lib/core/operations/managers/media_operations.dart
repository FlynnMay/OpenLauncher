import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/operations/operations_manager.dart';
import 'package:openlauncher/core/services/services.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// Commands for whatever is playing.
class MediaOperationsManager extends OperationsManager {
  MediaOperationsManager(this._media);

  final MediaService _media;

  @override
  String get area => 'os://media';

  @override
  late final List<Operation> operations = [
    operation(
      'command',
      label: 'Tell the media player',
      args: {
        'command': [for (final command in MediaCommand.values) command.name],
      },
      requiredArgs: const {'command'},
      run: (run) =>
          _media.send(MediaCommand.values.byName(run.required('command'))),
    ),
  ];
}
