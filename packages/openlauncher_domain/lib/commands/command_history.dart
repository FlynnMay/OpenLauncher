import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/json/json_read.dart';

/// What each session can undo and redo, as the commands that do it.
class CommandHistory {
  CommandHistory({this.limit = 100});

  /// The history [toJson] wrote. A session whose commands cannot be read has
  /// nothing to undo; [read] makes a command from its JSON.
  factory CommandHistory.fromJson(
    Object? json, {
    required CommandReader read,
    int limit = 100,
  }) {
    final history = CommandHistory(limit: limit);
    for (final MapEntry(:key, :value) in jsonStringKeyed(json).entries) {
      final session = jsonObject(value);
      try {
        history._undo[key] = _commandsIn(session['undo'], read);
        history._redo[key] = _commandsIn(session['redo'], read);
      } on FormatException {
        history._undo.remove(key);
        history._redo.remove(key);
      }
    }
    return history;
  }

  static List<Command> _commandsIn(Object? json, CommandReader read) => [
    if (json is List<Object?>)
      for (final command in json) read(jsonObject(command)),
  ];

  /// What each session can undo and redo, as JSON, oldest first.
  Map<String, Object?> toJson() => {
    for (final session in {..._undo.keys, ..._redo.keys})
      session: {
        'undo': [for (final command in _undo[session] ?? []) command.toJson()],
        'redo': [for (final command in _redo[session] ?? []) command.toJson()],
      },
  };

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
