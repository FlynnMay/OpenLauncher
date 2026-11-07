import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';

/// An edit to the layout, as data: it can be sent, kept and undone.
abstract class Command {
  const Command();

  /// Its name in JSON, e.g. `screen.add`.
  String get type;

  Map<String, Object?> toJson();

  /// The layout once this is done. Throws [CommandRefused] if it cannot be.
  Layout apply(Layout layout);

  /// The command that puts [before] back after this has been applied to it.
  Command inverse(Layout before);
}

/// A command that cannot be done to the layout as it is.
class CommandRefused implements Exception {
  const CommandRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads one kind of command from its JSON.
typedef CommandReader = Command Function(Json json);
