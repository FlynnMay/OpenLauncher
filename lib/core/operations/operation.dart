import 'dart:math';

/// What only the screen an action fired on can do. Null off-screen.
abstract interface class ActionScreen {
  Future<void> openSettings();
}

/// An operation was handed arguments it cannot do anything with.
class BadArguments extends FormatException {
  const BadArguments(super.message);
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

  /// The argument [key]. Only for one the operation declares in `requiredArgs`:
  /// [Operation.run] has checked it is there.
  String required(String key) => '${args[key]}';

  /// The argument [key] as a number; null if it was not given.
  double? optionalNumber(String key) =>
      args.containsKey(key) ? number(key) : null;

  /// The argument [key] as a yes or no; null if it is neither.
  bool? optionalFlag(String key) => switch (args[key]) {
    true || 'true' => true,
    false || 'false' => false,
    _ => null,
  };

  /// The argument [key] as a number; 0 if it is none.
  double number(String key) => switch (args[key]) {
    final num number => number.toDouble(),
    final String text => double.tryParse(text) ?? 0,
    _ => 0,
  };
}

/// One thing the launcher can do, named by its address: `os://<area>/<verb>`
/// for the TV, `launcher://<area>/<verb>` for the launcher's own.
class Operation {
  const Operation({
    required this.address,
    required this.label,
    required this._run,
    this.args = const {},
    this.requiredArgs = const {},
  });

  static const device = 'os://', launcher = 'launcher://';

  /// Its address, e.g. `os://apps/launch`.
  final String address;

  /// What it does, for whoever defines an action with it.
  final String label;

  /// Arguments by name, each with its allowed values (empty = anything).
  final Map<String, List<String>> args;

  /// The arguments it cannot run without, a subset of [args]' names.
  final Set<String> requiredArgs;

  final Future<String?> Function(OperationRun run) _run;

  /// Its address up to the verb, e.g. `os://apps`.
  String get area => areaOf(address);

  /// The area of [address].
  static String areaOf(String address) => address.substring(
    0,
    max(address.indexOf('://') + 3, address.lastIndexOf('/')),
  );

  /// Whether only the TV can do it. The web editor sends these to the TV.
  bool get onDevice => address.startsWith(device);

  /// Does it, once [run]'s arguments check out. Returns a message for the
  /// user, or null. Throws [BadArguments] if a required argument is missing
  /// or one is not among the values allowed for it.
  Future<String?> run(OperationRun run) async {
    _check(run.args);
    return _run(run);
  }

  void _check(Map<String, Object?> given) {
    for (final name in requiredArgs) {
      if (_isBlank(given[name])) throw BadArguments('$name was not given');
    }
    for (final MapEntry(key: name, value: allowed) in args.entries) {
      final value = given[name];
      if (allowed.isEmpty || _isBlank(value)) continue;
      if (!allowed.contains('$value')) {
        throw BadArguments(
          '"$value" is not a $name; use ${allowed.join(', ')}',
        );
      }
    }
  }

  static bool _isBlank(Object? value) => value == null || value == '';
}
