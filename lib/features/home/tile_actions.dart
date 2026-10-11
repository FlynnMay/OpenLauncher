import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/popup_panel.dart';
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
List<Entry> offeredFor(PaneView root, Entity subject, ActionRunner actions) => [
  for (final entry in root.entries)
    if ((triggersOf(entry.item)[Trigger.press] ?? const []).every(
      (act) => actions.applies(act, subject),
    ))
      entry,
];

/// What a tile does on this screen, by what sets it off.
class TileActions {
  TileActions(
    this._context,
    this._ref,
    this.triggers, {
    this.component,
    this.subject,
    this.inPopup = false,
    this.closes = false,
  });

  final BuildContext _context;
  final WidgetRef _ref;
  final Triggers triggers;

  /// The id of the component these are the triggers of.
  final String? component;

  /// The entity an action that names none is done to.
  final Entity? subject;
  final bool inPopup;

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
    if (closed) navigator.pop();
    final screen = _Screen(navigator, _ref, inPopup && !closed);
    for (final act in acts) {
      String? message;
      try {
        message = await actions.run(
          act,
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
  _Screen(this._navigator, this._ref, this._inPopup);

  final NavigatorState _navigator;
  final WidgetRef _ref;
  bool _inPopup;

  @override
  Future<void> openPanel(String panelId, {Entity? subject}) async {
    if (!_navigator.mounted) return;
    if (subject != null) {
      // A menu with nothing in it for this entity is not shown at all.
      final view = _ref.read(layoutViewProvider).value?.panels[panelId];
      if (view == null ||
          offeredFor(
            view.root,
            subject,
            _ref.read(actionRunnerProvider),
          ).isEmpty) {
        return;
      }
    }
    await showPanelPopup(_navigator.context, panelId, subject: subject);
  }

  @override
  Future<void> openSettings() async {
    if (_navigator.mounted) await SettingsScreen.open(_navigator);
  }

  @override
  void close() {
    if (_inPopup && _navigator.mounted) _navigator.pop();
    _inPopup = false;
  }
}
