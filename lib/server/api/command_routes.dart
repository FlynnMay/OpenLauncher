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
      ..post('/api/commands/redo', _redoLastUndo)
      ..get('/api/commands/log', _commandsAfterRevision);
  }

  Future<Response> _runCommand(Request request) async {
    final body = await readJsonObject(request);
    final command = await _withFilePaths(commandFromJson(body));
    return revisionResponse(
      _ref
          .read(commandsProvider)
          .run(
            command,
            session: editingSessionOf(request),
            basedOn: body['basedOn'] as int?,
          ),
    );
  }

  Future<Response> _undoLastCommand(Request request) => revisionResponse(
    _ref.read(commandsProvider).undo(session: editingSessionOf(request)),
  );

  Future<Response> _redoLastUndo(Request request) => revisionResponse(
    _ref.read(commandsProvider).redo(session: editingSessionOf(request)),
  );

  /// What was done after the revision in `after`, oldest first. `entries` is
  /// null if some of it is no longer kept: read the layout again.
  Future<Response> _commandsAfterRevision(Request request) async {
    final after = int.tryParse(request.url.queryParameters['after'] ?? '');
    if (after == null) throw const FormatException('"after" must be a number');
    final entries = await _ref.read(commandsProvider).entriesAfter(after);
    return jsonResponse({
      'entries': ?entries?.map((entry) => entry.toJson()).toList(),
    });
  }

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
