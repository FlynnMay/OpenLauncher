import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/prefabs/prefabs.dart';
import 'package:openlauncher_domain/commands/commands.dart';

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
        _history.recordChange(
          session,
          await _applyAndSaveReturningUndo(command),
        );
        return ++_revision;
      });

  @override
  Future<int> undo({String session = launcherSession}) => _inTurn(() async {
    final command =
        _history.nextUndo(session) ?? (throw const CommandRefused(_noUndo));
    _history.recordUndo(session, await _applyAndSaveReturningUndo(command));
    return ++_revision;
  });

  @override
  Future<int> redo({String session = launcherSession}) => _inTurn(() async {
    final command =
        _history.nextRedo(session) ?? (throw const CommandRefused(_noRedo));
    _history.recordRedo(session, await _applyAndSaveReturningUndo(command));
    return ++_revision;
  });

  static const _noUndo = 'There is nothing to undo.';
  static const _noRedo = 'There is nothing to redo.';

  /// Does [command] and returns the one that takes it back.
  Future<Command> _applyAndSaveReturningUndo(Command command) async {
    final config = await _ref.read(configProvider.future);
    final before = Document(
      layout: await _layoutAsEdited(config),
      settings: config.open,
    );
    final after = command.edit(before);
    final back = command.undoing(before);
    final changed = _changedSettings(before, after);
    if (LauncherConfig.settingsValidationError(changed) case final reason?) {
      throw CommandRefused(reason);
    }
    final controller = _ref.read(configProvider.notifier);
    if (!identical(after.layout, before.layout)) {
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
    final result = _queue.then((_) => work());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }
}

final commandsProvider = Provider<Commands>(CommandService.new);
