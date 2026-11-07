import 'package:openlauncher_domain/layout/layout_model.dart';

/// What commands edit: the layout and the settings kept beside it, by key.
class Document {
  const Document({
    required this.layout,
    this.settings = const {},
    this.layoutIsTheUsers = true,
    this.startingLayout,
  });

  final Layout layout;

  /// Each setting as JSON. A command can only set a key that is here.
  final Map<String, Object?> settings;

  /// False while [layout] is the pack's starting layout, which is not saved.
  final bool layoutIsTheUsers;

  /// The layout the pack starts with, if the app knows it.
  final Layout? startingLayout;

  Document copyWith({
    Layout? layout,
    Map<String, Object?>? settings,
    bool? layoutIsTheUsers,
  }) => Document(
    layout: layout ?? this.layout,
    settings: settings ?? this.settings,
    layoutIsTheUsers: layoutIsTheUsers ?? this.layoutIsTheUsers,
    startingLayout: startingLayout,
  );
}
