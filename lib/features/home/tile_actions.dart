import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/settings/settings_screen.dart';

/// [act] with the templates in its arguments read in [scope].
Act actIn(Act act, Watch watch, Map<String, Object?> scope) => Act(act.name, {
  for (final MapEntry(:key, :value) in act.args.entries)
    key: value is String && value.contains('{{')
        ? readTemplate(watch, value, scope)
        : value,
});

/// The children of the pane [root] of [owner] whose press can be done as
/// its variables stand.
List<Component> offeredFor(
  Component root,
  String owner,
  Watch watch,
  Iterable<Entity> entities,
) {
  final scope = scopeOf(watch, owner, root.vars, const {}).inner;
  return [
    for (final item in root.children)
      if ((item.on[Trigger.press] ?? const []).every(
        (act) => isProper(actIn(act, watch, scope), entities),
      ))
        item,
  ];
}

/// Runs a tile's triggers.
class TileActions {
  TileActions(
    this._context,
    this._ref,
    this.triggers, {
    this.component,
    this.scope = const {},
    this.popup,
    this.closes = false,
  });

  final BuildContext _context;
  final WidgetRef _ref;
  final Triggers triggers;

  /// Variables that action arguments may read, e.g. `{{source.id}}`.
  final Map<String, Object?> scope;

  final String? component;

  /// The hovering folder the tile is in, if any.
  final String? popup;

  /// Whether a press closes that folder first.
  final bool closes;

  bool has(Trigger trigger) => triggers[trigger]?.isNotEmpty ?? false;

  Future<void> fire(Trigger trigger, {bool held = false}) async {
    final acts = triggers[trigger] ?? const [];
    if (acts.isEmpty || !_context.mounted) return;
    final messenger = ScaffoldMessenger.of(_context);
    final navigator = Navigator.of(_context);
    final actions = _ref.read(actionRunnerProvider);
    final closed = closes && trigger == Trigger.press;
    void close() {
      if (popup case final id?) {
        _ref.read(runtimeVarsProvider.notifier).set(id, openVar, false);
      }
    }

    if (closed) close();
    final screen = _Screen(navigator, closed ? () {} : close);
    for (final act in acts) {
      final told = actIn(act, _ref.read, scope);
      String? message;
      try {
        message = await actions.run(
          told,
          screen: screen,
          held: held,
          component: component,
        );
      } on Object catch (error) {
        final what = actionRegistry(act.name)?.label.toLowerCase() ?? act.name;
        final entity = _ref
            .read(entitiesProvider)
            .value
            ?.byId(told.arg(entityArg));
        message = [
          'Could not $what',
          if (entity != null) ' ${entity.label}',
          ': ${error is FormatException ? error.message : error}',
        ].join();
      }
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }
}

class _Screen implements ActionScreen {
  _Screen(this._navigator, this._close);

  final NavigatorState _navigator;
  final VoidCallback _close;

  @override
  Future<void> openSettings() async {
    if (_navigator.mounted) await SettingsScreen.open(_navigator);
  }

  @override
  void close() {
    _close();
  }
}
