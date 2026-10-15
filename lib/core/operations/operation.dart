import 'dart:math';

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

  /// What the entity's action bound and what the act passed, or what an
  /// act that calls the address says.
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

/// One thing the launcher can do, named by its address: `os://<area>/<verb>`
/// for the TV, `launcher://<area>/<verb>` for the launcher's own.
class Operation {
  const Operation({
    required this.name,
    required this.label,
    required this.run,
    this.args = const {},
  });

  static const device = 'os://', launcher = 'launcher://';

  /// Its address, e.g. `os://apps/launch`.
  final String name;

  /// What it does, for whoever defines an action with it.
  final String label;

  /// Arguments by name, each with its allowed values (empty = anything).
  final Map<String, List<String>> args;

  /// Its address up to the verb, e.g. `os://apps`.
  String get area => areaOf(name);

  /// The area of [address].
  static String areaOf(String address) => address.substring(
    0,
    max(address.indexOf('://') + 3, address.lastIndexOf('/')),
  );

  /// Whether only the TV can do it. The web editor sends these to the TV.
  bool get onDevice => name.startsWith(device);

  /// Returns a message for the user, or null.
  final Future<String?> Function(OperationRun run) run;
}
