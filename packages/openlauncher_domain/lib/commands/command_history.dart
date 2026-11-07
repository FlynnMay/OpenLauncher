import 'package:openlauncher_domain/commands/command.dart';

/// What each session can undo and redo, as the commands that do it.
class CommandHistory {
  CommandHistory({this.limit = 100});

  final int limit;
  final _undo = <String, List<Command>>{};
  final _redo = <String, List<Command>>{};

  /// [session] changed the layout; [undo] takes that back. What it had undone is
  /// no longer to be redone.
  void recordChange(String session, Command undo) {
    _stack(_undo, session).add(undo);
    _redo.remove(session);
    if (_undo[session]!.length > limit) _undo[session]!.removeAt(0);
  }

  Command? nextUndo(String session) => _undo[session]?.lastOrNull;

  /// The command from [nextUndo] was run; [redo] puts back what it undid.
  void recordUndo(String session, Command redo) {
    _undo[session]!.removeLast();
    _stack(_redo, session).add(redo);
  }

  Command? nextRedo(String session) => _redo[session]?.lastOrNull;

  /// The command from [nextRedo] was run; [undo] takes it back again.
  void recordRedo(String session, Command undo) {
    _redo[session]!.removeLast();
    _stack(_undo, session).add(undo);
  }

  List<Command> _stack(Map<String, List<Command>> stacks, String session) =>
      stacks.putIfAbsent(session, () => []);
}
