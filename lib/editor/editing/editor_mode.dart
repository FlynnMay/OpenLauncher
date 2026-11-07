import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the page's screen is for.
enum EditorMode {
  /// Move things about and add new ones.
  edit,

  /// Use it as the TV would be used. What only the TV can do is shown as a
  /// message instead.
  test,

  /// Use it to control the TV: every action is sent to it.
  remote,
}

final editorModeProvider = NotifierProvider<EditorModeChoice, EditorMode>(
  EditorModeChoice.new,
);

class EditorModeChoice extends Notifier<EditorMode> {
  @override
  EditorMode build() => EditorMode.edit;

  void choose(EditorMode mode) => state = mode;
}
