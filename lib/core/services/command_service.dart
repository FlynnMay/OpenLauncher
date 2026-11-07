import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';

/// Who runs commands that no editor sent.
const launcherSession = 'launcher';

/// The one way to change the layout with a [Command]. The web editor has its
/// own, which asks the TV to do it. Each returns the revision the layout is
/// at after, and throws [CommandRefused] if it cannot be done.
abstract interface class Commands {
  /// [session] is who can undo it; the editor's is the device it paired as.
  Future<int> run(Command command, {String session = launcherSession});

  Future<int> undo({String session = launcherSession});

  Future<int> redo({String session = launcherSession});
}

/// Runs commands on the layout this app holds, one at a time.
class CommandService implements Commands {
  CommandService(this._ref);

  final Ref _ref;
  final _history = CommandHistory();
  var _revision = 0;
  Future<void> _queue = Future.value();

  @override
  Future<int> run(Command command, {String session = launcherSession}) =>
      _inTurn(() async {
        _history.recordChange(session, await _apply(command));
        return ++_revision;
      });

  @override
  Future<int> undo({String session = launcherSession}) => _inTurn(() async {
    final command =
        _history.nextUndo(session) ?? (throw const CommandRefused(_noUndo));
    _history.recordUndo(session, await _apply(command));
    return ++_revision;
  });

  @override
  Future<int> redo({String session = launcherSession}) => _inTurn(() async {
    final command =
        _history.nextRedo(session) ?? (throw const CommandRefused(_noRedo));
    _history.recordRedo(session, await _apply(command));
    return ++_revision;
  });

  static const _noUndo = 'There is nothing to undo.';
  static const _noRedo = 'There is nothing to redo.';

  /// Does [command] and returns the one that takes it back.
  Future<Command> _apply(Command command) async {
    final Layout before = (await _ref.read(configProvider.future)).layout;
    final next = command.apply(before);
    final back = command.inverse(before);
    await _ref.read(configProvider.notifier).setLayout(next);
    return back;
  }

  /// Two commands at once would both read the layout before either saved.
  Future<int> _inTurn(Future<int> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}

final commandsProvider = Provider<Commands>(CommandService.new);
