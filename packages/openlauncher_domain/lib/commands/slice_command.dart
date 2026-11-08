import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/document.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/slice/slice.dart';

/// Edits what [edits] point at, in order. The one command for changing the
/// config: a list of edits, one or many, done as one step and undone as one
/// step. It is the operations themselves, so it undoes itself.
class EditSlice extends Command {
  const EditSlice(this.edits);

  factory EditSlice.fromJson(Json json) => EditSlice([
    for (final edit in jsonRequired<List<Object?>>(json, 'edits'))
      SliceEdit.fromJson(jsonObject(edit)),
  ]);

  static const typeName = 'slice.edit';

  final List<SliceEdit> edits;

  @override
  String get type => typeName;

  @override
  Document edit(Document document) {
    var done = document;
    for (final one in edits) {
      done = one.apply(done).document;
    }
    return done;
  }

  @override
  Command undoing(Document before) {
    var done = before;
    final inverse = <SliceEdit>[];
    for (final one in edits) {
      final result = one.apply(done);
      done = result.document;
      inverse.insertAll(0, result.inverse);
    }
    return EditSlice(inverse);
  }

  @override
  Set<String> get areas => {for (final edit in edits) ...edit.areas};

  @override
  Map<String, Object?> toJson() => {
    'type': type,
    'edits': [for (final edit in edits) edit.toJson()],
  };
}
