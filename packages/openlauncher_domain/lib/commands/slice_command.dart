import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/config_commands.dart';
import 'package:openlauncher_domain/commands/document.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/slice/slice.dart';

/// Edits what a [SliceEdit] points at. The one command for changing nodes and
/// prefabs: it is the operations themselves, so it undoes itself.
class EditSlice extends Command {
  const EditSlice(this.slice);

  factory EditSlice.fromJson(Json json) =>
      EditSlice(SliceEdit.fromJson(jsonObject(json['edit'])));

  static const typeName = 'slice.edit';

  final SliceEdit slice;

  /// One command for several edits, so one undo takes back all of them.
  static Command of(List<SliceEdit> edits) => edits.length == 1
      ? EditSlice(edits.single)
      : Batch([for (final edit in edits) EditSlice(edit)]);

  @override
  String get type => typeName;

  @override
  Document edit(Document document) => slice.apply(document).document;

  @override
  Command undoing(Document before) => EditSlice.of(slice.apply(before).inverse);

  @override
  Map<String, Object?> toJson() => {'type': type, 'edit': slice.toJson()};
}
