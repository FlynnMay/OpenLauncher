/// What only the screen an action fired on can do. Null off-screen.
abstract interface class ActionScreen {
  Future<void> openSettings();

  /// Closes the popup the action fired in.
  void close();
}

/// One operation being run.
class OperationRun {
  const OperationRun(
    this.args, {
    this.screen,
    this.held = false,
    this.component,
  });

  /// What the entity's action bound and what the act passed.
  final Map<String, Object?> args;
  final ActionScreen? screen;
  final bool held;

  /// The component it fired from, if any.
  final String? component;

  /// The argument [key], if it is a string.
  String? arg(String key) => switch (args[key]) {
    final String value => value,
    _ => null,
  };

  /// The argument [key] as a number; 0 if it is none.
  double number(String key) => switch (args[key]) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text) ?? 0,
    _ => 0,
  };

  /// The argument [key] as a yes or no.
  bool flag(String key, {bool otherwise = false}) => switch (args[key]) {
    true || 'true' => true,
    false || 'false' => false,
    _ => otherwise,
  };
}

/// One thing code can do. An entity's action runs it by [name].
class Operation {
  const Operation({
    required this.name,
    required this.label,
    required this.run,
    this.args = const {},
    this.onDevice = false,
  });

  final String name;

  /// What it does, for whoever defines an action with it.
  final String label;

  /// Arguments by name, each with its allowed values (empty = anything).
  final Map<String, List<String>> args;

  /// True if only the TV can do it. The web editor sends these to the TV.
  final bool onDevice;

  /// Returns a message for the user, or null.
  final Future<String?> Function(OperationRun run) run;
}
