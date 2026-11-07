import 'dart:async';

import 'package:openlauncher_domain/json/json_read.dart';

/// How a command came to be done.
enum CommandAction { run, undo, redo }

/// One command the layout was changed by, in the order they happened.
class CommandLogEntry {
  const CommandLogEntry({
    required this.revision,
    required this.session,
    required this.action,
    required this.command,
  });

  factory CommandLogEntry.fromJson(Json json) => CommandLogEntry(
    revision: jsonRequired<int>(json, 'revision'),
    session: jsonRequired<String>(json, 'session'),
    action: jsonNamed(
      CommandAction.values,
      json['action'] as String?,
      CommandAction.run,
    ),
    command: jsonObject(json['command']),
  );

  /// The layout's revision once this was done.
  final int revision;

  /// Who did it: the device that paired, or the launcher itself.
  final String session;

  final CommandAction action;

  /// The command that was done, as JSON. For an undo or a redo, it is the one
  /// that took the earlier change back or put it again.
  final Map<String, Object?> command;

  Map<String, Object?> toJson() => {
    'revision': revision,
    'session': session,
    'action': action.name,
    'command': command,
  };
}

/// The newest commands done, and a count of them, which is the revision.
class CommandLog {
  CommandLog({this.limit = 200});

  final int limit;
  final _entries = <CommandLogEntry>[];
  final _added = StreamController<CommandLogEntry>.broadcast(sync: true);
  var _revision = 0;

  int get revision => _revision;

  /// Each entry as it is recorded.
  Stream<CommandLogEntry> get added => _added.stream;

  CommandLogEntry record({
    required String session,
    required CommandAction action,
    required Map<String, Object?> command,
  }) {
    final entry = CommandLogEntry(
      revision: ++_revision,
      session: session,
      action: action,
      command: command,
    );
    _entries.add(entry);
    if (_entries.length > limit) _entries.removeAt(0);
    _added.add(entry);
    return entry;
  }

  /// What was done after [revision], oldest first. Null if some of it is no
  /// longer kept, so a caller that missed it must read the layout again.
  List<CommandLogEntry>? after(int revision) {
    final oldestKept = _entries.firstOrNull?.revision ?? _revision + 1;
    if (revision < oldestKept - 1) return null;
    return [
      for (final entry in _entries)
        if (entry.revision > revision) entry,
    ];
  }

  void close() => _added.close();
}
