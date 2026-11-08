import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';

/// What commands edit: the layout and the settings kept beside it, by key.
class Document {
  const Document({
    required this.layout,
    this.settings = const {},
    this.layoutIsTheUsers = true,
    this.startingLayout,
    this.prefabs = const {},
    this.shippedPrefabs = const {},
  });

  final Layout layout;

  /// Each setting as JSON. A command can only set a key that is here.
  final Map<String, Object?> settings;

  /// False while [layout] is the pack's starting layout, which is not saved.
  final bool layoutIsTheUsers;

  /// The layout the pack starts with, if the app knows it.
  final Layout? startingLayout;

  /// Every prefab in use by id, the packs' and the user's. Read only: a
  /// command changes the user's through the `prefabs` setting.
  final Map<String, Prefab> prefabs;

  /// The prefabs packs ship, by id: what a prefab goes back to when the user's
  /// own copy of it is taken away.
  final Map<String, Prefab> shippedPrefabs;

  Document copyWith({
    Layout? layout,
    Map<String, Object?>? settings,
    bool? layoutIsTheUsers,
    Map<String, Prefab>? prefabs,
  }) => Document(
    layout: layout ?? this.layout,
    settings: settings ?? this.settings,
    layoutIsTheUsers: layoutIsTheUsers ?? this.layoutIsTheUsers,
    startingLayout: startingLayout,
    prefabs: prefabs ?? this.prefabs,
    shippedPrefabs: shippedPrefabs,
  );
}
