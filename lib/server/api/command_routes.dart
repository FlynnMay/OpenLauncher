import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/services/command_service.dart';
import 'package:openlauncher/server/api/api_responses.dart';
import 'package:openlauncher/server/media_store.dart';
import 'package:openlauncher_domain/commands/commands.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

class CommandRoutes implements ApiRoutes {
  CommandRoutes(this._ref);

  final Ref _ref;

  @override
  void addTo(Router router) {
    router
      ..post('/api/commands', _runCommand)
      ..post('/api/commands/undo', _undoLastCommand)
      ..post('/api/commands/redo', _redoLastUndo);
  }

  Future<Response> _runCommand(Request request) async {
    final command = await _withFilePaths(
      commandFromJson(await readJsonObject(request)),
    );
    return revisionResponse(
      _ref
          .read(commandsProvider)
          .run(command, session: editingSessionOf(request)),
    );
  }

  Future<Response> _undoLastCommand(Request request) => revisionResponse(
    _ref.read(commandsProvider).undo(session: editingSessionOf(request)),
  );

  Future<Response> _redoLastUndo(Request request) => revisionResponse(
    _ref.read(commandsProvider).redo(session: editingSessionOf(request)),
  );

  /// Files arrive as ids and are kept as paths.
  Future<Command> _withFilePaths(Command command) async => switch (command) {
    SetConfig(:final values) => SetConfig(
      await _ref.read(mediaStoreProvider).withPaths(values),
    ),
    Batch(:final commands) => Batch([
      for (final each in commands) await _withFilePaths(each),
    ]),
    _ => command,
  };
}
