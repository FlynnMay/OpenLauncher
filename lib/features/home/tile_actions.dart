import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/settings/settings_screen.dart';

/// The entity a menu was opened for; its buttons act on it.
class ActionSubject extends InheritedWidget {
  const ActionSubject({super.key, required this.entity, required super.child});

  final Entity entity;

  static Entity? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActionSubject>()?.entity;

  @override
  bool updateShouldNotify(ActionSubject oldWidget) =>
      entity != oldWidget.entity;
}

/// The children of [root] whose actions all apply to [subject].
List<Component> offeredFor(
  Component root,
  Entity subject,
  ActionRunner actions,
) => [
  for (final item in root.children)
    if ((item.on[Trigger.press] ?? const []).every(
      (act) => actions.applies(act, subject),
    ))
      item,
];

/// Runs a tile's triggers.
class TileActions {
  TileActions(
    this._context,
    this._ref,
    this.triggers, {
    this.component,
    this.scope = const {},
    this.subject,
    this.popup,
    this.closes = false,
  });

  final BuildContext _context;
  final WidgetRef _ref;
  final Triggers triggers;

  /// Variables that action arguments may read, e.g. `{{source.id}}`.
  final Map<String, Object?> scope;

  final String? component;

  /// The default entity for actions that name none.
  final Entity? subject;

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
      String? message;
      try {
        message = await actions.run(
          // Arguments with templates evaluated.
          Act(act.name, {
            for (final MapEntry(:key, :value) in act.args.entries)
              key: value is String && value.contains('{{')
                  ? readTemplate(_ref.read, value, scope)
                  : value,
          }),
          subject: subject,
          screen: screen,
          held: held,
          component: component,
        );
      } on Object catch (error) {
        final what = actionKind(act.name)?.label.toLowerCase() ?? act.name;
        message = [
          'Could not $what',
          if (subject case final entity?) ' ${entity.label}',
          ': $error',
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
