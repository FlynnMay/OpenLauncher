import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/variables/variables.dart';
import 'package:openlauncher/features/settings/settings_screen.dart';

/// The entity everything below is about: set by a popup opened as an entity's
/// menu, so that its buttons act on that entity.
class ActionSubject extends InheritedWidget {
  const ActionSubject({super.key, required this.entity, required super.child});

  final Entity entity;

  static Entity? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActionSubject>()?.entity;

  @override
  bool updateShouldNotify(ActionSubject oldWidget) =>
      entity != oldWidget.entity;
}

/// The things in [root] that are offered when it is [subject]'s menu:
/// all but those that are pressed to do what cannot be done to it.
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

/// What a tile does on this screen, by what sets it off.
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

  /// The variables the tile can read, which what an action is told may
  /// be written against: `{{source.id}}`.
  final Map<String, Object?> scope;

  /// The id of the component these are the triggers of.
  final String? component;

  /// The entity an action that names none is done to.
  final Entity? subject;

  /// The id of the folder the tile is in, where it is in one that hovers.
  final String? popup;

  /// True where a press closes the popup the tile is in before anything
  /// else: an entity in a folder, a button of an entity's menu.
  final bool closes;

  bool has(Trigger trigger) => triggers[trigger]?.isNotEmpty ?? false;

  Future<void> fire(Trigger trigger, {bool held = false}) async {
    final acts = triggers[trigger] ?? const [];
    if (acts.isEmpty || !_context.mounted) return;
    final messenger = ScaffoldMessenger.of(_context);
    final navigator = Navigator.of(_context);
    final actions = _ref.read(actionRunnerProvider);
    final closed = closes && trigger == Trigger.press;
    // A folder is closed as it is opened: by its variable.
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
          // What it is told, as that reads now.
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
