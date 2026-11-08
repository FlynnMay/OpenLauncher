import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/commands/command_history_store.dart';
import 'package:openlauncher/core/commands/commands_interface.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher_domain/commands/commands.dart';

/// Runs commands on the layout this app holds, one at a time.
class CommandRunner implements Commands {
  CommandRunner(this._ref);

  final Ref _ref;
  var _history = CommandHistory();
  final _log = CommandLog();
  Future<void> _queue = Future.value();

  /// What the sessions could undo before the app last stopped.
  late final Future<void> _restored = _restoreHistory();

  Future<void> _restoreHistory() async {
    try {
      _history = CommandHistory.fromJson(
        await _ref.read(commandHistoryStoreProvider).load(),
        read: commandFromJson,
      );
    } on Object catch (error) {
      debugPrint('Starting without the undo history: $error');
    }
  }

  /// Kept after every change, so a restart loses nothing. A failure to keep it
  /// does not fail the change.
  Future<void> _saveHistory() async {
    try {
      await _ref.read(commandHistoryStoreProvider).save(_history.toJson());
    } on Object catch (error) {
      debugPrint('Could not keep the undo history: $error');
    }
  }

  @override
  Future<int> run(
    Command command, {
    String session = launcherSession,
    int? basedOn,
  }) => _inTurn(() async {
    if (basedOn != null) _refuseIfOthersChangedSince(basedOn, session);
    _history.recordChange(session, await _applyAndSaveReturningUndo(command));
    return _logged(session, CommandAction.run, command);
  });

  @override
  Future<int> undo({String session = launcherSession}) => _inTurn(() async {
    final command =
        _history.nextUndo(session) ?? (throw const CommandRefused(_noUndo));
    _history.recordUndo(session, await _applyAndSaveReturningUndo(command));
    return _logged(session, CommandAction.undo, command);
  });

  @override
  Future<int> redo({String session = launcherSession}) => _inTurn(() async {
    final command =
        _history.nextRedo(session) ?? (throw const CommandRefused(_noRedo));
    _history.recordRedo(session, await _applyAndSaveReturningUndo(command));
    return _logged(session, CommandAction.redo, command);
  });

  /// The layout [session] looked at has been changed by someone else, or too
  /// long ago to tell: what it is making would overwrite their work.
  void _refuseIfOthersChangedSince(int revision, String session) {
    final since = _log.after(revision);
    if (since == null || since.any((entry) => entry.session != session)) {
      throw const CommandRefused(staleView);
    }
  }

  static const staleView =
      'Someone else changed the layout. It has been reloaded; try again.';

  @override
  int get revision => _log.revision;

  void close() => _log.close();

  @override
  Stream<CommandLogEntry> get entries => _log.added;

  @override
  Future<List<CommandLogEntry>?> entriesAfter(int revision) async =>
      _log.after(revision);

  /// Records that [command] was done and returns the revision it left.
  int _logged(String session, CommandAction action, Command command) => _log
      .record(session: session, action: action, command: command.toJson())
      .revision;

  static const _noUndo = 'There is nothing to undo.';
  static const _noRedo = 'There is nothing to redo.';

  /// Does [command] and returns the one that takes it back.
  Future<Command> _applyAndSaveReturningUndo(Command command) async {
    final config = await _ref.read(configProvider.future);
    final before = Document(
      layout: await _layoutAsEdited(config),
      settings: config.open,
      layoutIsTheUsers: config.ownLayout,
      startingLayout: (await _ref.read(startingLayoutProvider.future)).layout,
      prefabs: _ref.read(prefabsProvider),
      shippedPrefabs: _ref.read(shippedPrefabsProvider),
    );
    final after = command.edit(before);
    final back = command.undoing(before);
    final changed = _changedSettings(before, after);
    if (LauncherConfig.settingsValidationError(changed) case final reason?) {
      throw CommandRefused(reason);
    }
    final controller = _ref.read(configProvider.notifier);
    if (before.layoutIsTheUsers && !after.layoutIsTheUsers) {
      await controller.revertLayout();
    } else if (!identical(after.layout, before.layout)) {
      await controller.setLayout(after.layout);
    }
    if (changed.isNotEmpty) await controller.patch(changed);
    return back;
  }

  static Map<String, Object?> _changedSettings(
    Document before,
    Document after,
  ) => {
    for (final MapEntry(:key, :value) in after.settings.entries)
      if (jsonEncode(value) != jsonEncode(before.settings[key])) key: value,
  };

  /// The layout as the editor shows it: the saved one, with the entities not
  /// placed yet in the inbox. A command's ids can name those, so it is run on
  /// this, and saving the result places them, as saving from the editor does.
  Future<Layout> _layoutAsEdited(LauncherConfig config) async {
    final entities = await _ref.read(entitiesProvider.future);
    return layoutWith(config.layout, entities, _ref.read(prefabsProvider));
  }

  /// Two commands at once would both read the layout before either saved.
  Future<int> _inTurn(Future<int> Function() work) {
    final result = _queue.then((_) async {
      await _restored;
      final revision = await work();
      await _saveHistory();
      return revision;
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}
