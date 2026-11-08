import 'package:openlauncher_domain/commands/document.dart';
import 'package:openlauncher_domain/json/json_read.dart';

/// An edit to the [Document], as data: it can be sent, kept and undone.
abstract class Command {
  const Command();

  /// Its name in JSON, e.g. `screen.add`.
  String get type;

  Map<String, Object?> toJson();

  /// The document once this is done. Throws [CommandRefused] if it cannot be.
  Document edit(Document document);

  /// The command that puts [before] back after this has been done to it.
  Command undoing(Document before);

  /// What this changes, as areas of the document: two commands conflict only
  /// if their areas overlap (see [areasOverlap]). A command that does not say
  /// changes everything.
  Set<String> get areas => const {everywhere};
}

/// The area of a command that may change any of the document.
const everywhere = '*';

/// The area of a command that changes the layout as a whole, or in many places:
/// it overlaps every node and screen.
const wholeLayout = 'layout';

/// Whether two sets of areas overlap: an area overlaps itself and the areas
/// inside it (`node:a` and `node:a/image`), and [wholeLayout] overlaps every
/// node and screen.
bool areasOverlap(Set<String> these, Set<String> those) => these.any(
  (one) => those.any((other) => _overlap(one, other) || _overlap(other, one)),
);

bool _overlap(String one, String other) =>
    one == everywhere ||
    one == other ||
    other.startsWith('$one/') ||
    one == wholeLayout &&
        (other.startsWith('node:') || other.startsWith('screen:'));

/// A command that cannot be done to the layout as it is.
class CommandRefused implements Exception {
  const CommandRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads one kind of command from its JSON.
typedef CommandReader = Command Function(Json json);
