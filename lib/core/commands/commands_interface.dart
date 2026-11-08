import 'dart:async';

import 'package:openlauncher_domain/commands/commands.dart';

/// Who runs commands that no editor sent.
const launcherSession = 'launcher';

/// The one way to change the layout with a [Command]. The web editor has its
/// own, which asks the TV to do it. Each returns the revision the layout is
/// at after, and throws [CommandRefused] if it cannot be done.
abstract interface class Commands {
  /// [session] is who can undo it; the editor's is the device it paired as.
  /// [basedOn] is the revision of the layout the command was made by looking
  /// at; it is refused if someone else has changed the layout since.
  Future<int> run(
    Command command, {
    String session = launcherSession,
    int? basedOn,
  });

  /// How many commands have been done.
  int get revision;

  Future<int> undo({String session = launcherSession});

  Future<int> redo({String session = launcherSession});

  /// Each command as it is done, by anyone.
  Stream<CommandLogEntry> get entries;

  /// What was done after [revision], oldest first; null if some of it is no
  /// longer kept.
  Future<List<CommandLogEntry>?> entriesAfter(int revision);
}
