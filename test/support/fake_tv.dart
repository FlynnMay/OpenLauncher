import 'dart:async';

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

  /// What it was sent that is not a command.
  final sent = <String>[];

  /// When set, it refuses what it is sent.
  bool refuses = false;

  /// When set, it refuses commands, giving this reason.
  String? commandRefusal;

  var _revision = 0;

  Layout get layout => _state.config.layout;

  @override
  Future<int> command(Map<String, Object?> command) async {
    if (commandRefusal case final reason?) throw CommandRefused(reason);
    _hold(commandFromJson(command).apply(layout));
    pushed.add(_state);
    return ++_revision;
  }

  @override
  Future<void> setLayout(Layout layout) async {
    if (refuses) throw Exception('No');
    _hold(layout);
    sent.add('layout');
  }

  @override
  Future<void> setConfig(Map<String, Object?> changed) async =>
      sent.add('config ${changed.keys.join(' ')}');

  void _hold(Layout layout) {
    _state = TvState(
      entities: _state.entities,
      config: _state.config.copyWith(layout: layout),
      visuals: _state.visuals,
      packs: _state.packs,
      widgetProviders: _state.widgetProviders,
      access: _state.access,
      nowPlaying: _state.nowPlaying,
      update: _state.update,
    );
  }
}
