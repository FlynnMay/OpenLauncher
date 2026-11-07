import 'package:openlauncher_domain/layout/layout_model.dart';

/// What commands edit: the layout and the settings kept beside it, by key.
class Document {
  const Document({required this.layout, this.settings = const {}});

  final Layout layout;

  /// Each setting as JSON. A command can only set a key that is here.
  final Map<String, Object?> settings;

  Document copyWith({Layout? layout, Map<String, Object?>? settings}) =>
      Document(
        layout: layout ?? this.layout,
        settings: settings ?? this.settings,
      );
}
