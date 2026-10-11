import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// What only the screen an action was set off on can do. There is none
/// where there is no screen, and such actions then do nothing.
abstract interface class ActionScreen {
  /// Shows the popup [panelId]; with a [subject], as that entity's menu.
  Future<void> openPanel(String panelId, {Entity? subject});

  Future<void> openSettings();

  /// Closes the popup the action was set off in.
  void close();
}

/// One action as it is being carried out.
class ActionRun {
  const ActionRun(this.ref, this.act, this.entity, this.screen, this.held);

  final Ref ref;
  final Act act;

  /// What it is done to; never null for an action an entity presents.
  final Entity? entity;
  final ActionScreen? screen;
  final bool held;

  LauncherPlatform get platform => ref.read(launcherPlatformProvider);
}

/// A thing that can be done: by an entity, which presents the actions of
/// its kind, or by the launcher itself.
class ActionKind {
  const ActionKind({
    required this.name,
    required this.label,
    required this.icon,
    required this.run,
    this.args = const {},
  });

  /// How an [Act] names it. Kinds of entity may each have an action of the
  /// same name, which is then whichever the entity's kind has.
  final String name;
  final String label;

  /// The name of the picture a button that does this starts with.
  final String icon;

  /// What it is told beside the entity, by the name of each, with what
  /// that is: `panel` (the id of a popup) or the choices there are.
  final Map<String, List<String>> args;

  /// Does it. Returns something to tell the user, if there is anything.
  final Future<String?> Function(ActionRun run) run;
}
