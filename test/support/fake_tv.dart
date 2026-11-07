import 'dart:async';
import 'dart:convert';

import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/tv/tv.dart';
import 'package:openlauncher_domain/commands/commands.dart';

/// A TV for the editor's tests. It does what it is sent, as the real one does:
/// a command is done to its layout, and the page is told the new state.
class FakeTv extends TvApi {
  FakeTv(TvState state) : _state = state {
    pushed.add(state);
  }

  TvState _state;

  /// What the TV tells the page, as it does after every change.
  final pushed = StreamController<TvState>();

  /// What it was sent, a short phrase for each.
  final sent = <String>[];

  /// When set, it refuses commands, giving this reason.
  String? commandRefusal;

  var _revision = 0;
  var _history = CommandHistory();

  /// The TV starting again forgets what could be undone.
  void restart() => _history = CommandHistory();

  Layout get layout => _state.config.layout;

  LauncherConfig get config => _state.config;

  @override
  Future<int> command(Map<String, Object?> command) async {
    if (commandRefusal case final reason?) throw CommandRefused(reason);
    final done = commandFromJson(command);
    sent.add(describeCommand(done));
    _history.recordChange(_session, _applyAndReturnUndo(done));
    return _pushed();
  }

  @override
  Future<int> undoCommand() async {
    final undo =
        _history.nextUndo(_session) ??
        (throw const CommandRefused('There is nothing to undo.'));
    sent.add('undo');
    _history.recordUndo(_session, _applyAndReturnUndo(undo));
    return _pushed();
  }

  @override
  Future<int> redoCommand() async {
    final redo =
        _history.nextRedo(_session) ??
        (throw const CommandRefused('There is nothing to redo.'));
    sent.add('redo');
    _history.recordRedo(_session, _applyAndReturnUndo(redo));
    return _pushed();
  }

  @override
  Future<void> revertLayout() async => sent.add('revert');

  static const _session = 'editor';

  /// Does [command] and returns the one that takes it back.
  Command _applyAndReturnUndo(Command command) {
    final before = Document(layout: layout, settings: config.open);
    final after = command.edit(before);
    final back = command.undoing(before);
    _state = _stateWith(
      config
          .patched({
            for (final MapEntry(:key, :value) in after.settings.entries)
              if (jsonEncode(value) != jsonEncode(before.settings[key]))
                key: value,
          })
          .copyWith(layout: after.layout),
    );
    return back;
  }

  int _pushed() {
    pushed.add(_state);
    return ++_revision;
  }

  TvState _stateWith(LauncherConfig config) => TvState(
    entities: _state.entities,
    config: config,
    visuals: _state.visuals,
    packs: _state.packs,
    widgetProviders: _state.widgetProviders,
    access: _state.access,
    nowPlaying: _state.nowPlaying,
    update: _state.update,
  );
}

/// A command in a word or two, for what a test expects the TV was sent.
String describeCommand(Command command) => switch (command) {
  SetConfig(:final values) => 'config ${values.keys.join(' ')}',
  Batch(:final commands) => commands.map(describeCommand).join(' + '),
  LayoutCommand() => 'layout',
  _ => command.type,
};
