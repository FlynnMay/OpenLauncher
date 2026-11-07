import 'package:openlauncher_domain/commands/command.dart';
import 'package:openlauncher_domain/commands/document.dart';
import 'package:openlauncher_domain/json/json_read.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';

/// Goes back to the layout the pack starts with, dropping the user's own.
class ResetLayoutToStarting extends Command {
  const ResetLayoutToStarting();

  static const typeName = 'layout.reset';

  @override
  String get type => typeName;

  @override
  Document edit(Document document) => document.copyWith(
    layout:
        document.startingLayout ??
        (throw const CommandRefused('There is no starting layout.')),
    layoutIsTheUsers: false,
  );

  @override
  Command undoing(Document before) => before.layoutIsTheUsers
      ? ReplaceWholeLayout(before.layout)
      : const ResetLayoutToStarting();

  @override
  Map<String, Object?> toJson() => {'type': type};
}

/// Puts a whole layout back as the user's own. It is what undoes a reset.
class ReplaceWholeLayout extends Command {
  const ReplaceWholeLayout(this.layout);

  factory ReplaceWholeLayout.fromJson(Json json) =>
      ReplaceWholeLayout(Layout.fromJson(jsonObject(json['layout'])));

  static const typeName = 'layout.replace';

  final Layout layout;

  @override
  String get type => typeName;

  @override
  Document edit(Document document) =>
      document.copyWith(layout: layout, layoutIsTheUsers: true);

  @override
  Command undoing(Document before) => before.layoutIsTheUsers
      ? ReplaceWholeLayout(before.layout)
      : const ResetLayoutToStarting();

  @override
  Map<String, Object?> toJson() => {'type': type, 'layout': layout.toJson()};
}

final Map<String, CommandReader> layoutResetCommandReaders = {
  ResetLayoutToStarting.typeName: (_) => const ResetLayoutToStarting(),
  ReplaceWholeLayout.typeName: ReplaceWholeLayout.fromJson,
};
