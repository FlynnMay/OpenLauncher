import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/actions/act.dart';
import 'package:openlauncher/core/entities/entity.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// What only the screen an action fired on can do. Null off-screen.
abstract interface class ActionScreen {
  Future<void> openSettings();

  /// Closes the popup the action fired in.
  void close();
}

/// One action being run.
class ActionRun {
  const ActionRun(
    this.ref,
    this.act,
    this.entity,
    this.screen,
    this.held, [
    this.component,
  ]);

  final Ref ref;
  final Act act;

  /// The entity doing it.
  final Entity? entity;
  final ActionScreen? screen;
  final bool held;

  /// The component it fired from, if any.
  final String? component;

  LauncherPlatform get platform => ref.read(launcherPlatformProvider);
}

/// An action an entity category presents.
class ActionRegistry {
  const ActionRegistry({
    required this.name,
    required this.label,
    required this.icon,
    required this.run,
    this.args = const {},
    this.onDevice = false,
  });

  /// The name an [Act] uses. Categories may share a name.
  final String name;
  final String label;

  /// Default icon for a button that does this.
  final String icon;

  /// Extra arguments by name, each with its allowed values (empty = free
  /// text).
  final Map<String, List<String>> args;

  /// True if only the TV can do it. The web editor sends these to the TV.
  final bool onDevice;

  /// Returns a message for the user, or null.
  final Future<String?> Function(ActionRun run) run;
}
