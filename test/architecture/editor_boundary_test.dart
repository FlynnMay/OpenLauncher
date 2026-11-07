import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The web editor and the launcher talk through the TV's server. These keep
/// the editor from reaching past that.
void main() {
  final editorFiles = [
    for (final file in Directory('lib/editor').listSync(recursive: true))
      if (file is File && file.path.endsWith('.dart')) file,
  ];

  List<String> filesMatching(
    Pattern pattern, {
    bool Function(File file) except = _nowhere,
  }) => [
    for (final file in editorFiles)
      if (!except(file) && file.readAsStringSync().contains(pattern)) file.path,
  ];

  bool inTvAdapter(File file) => file.path.startsWith('lib/editor/tv/');

  test('the editor does not use the services that act on the TV', () {
    expect(filesMatching("package:openlauncher/core/services/"), isEmpty);
  });

  test('only the TV adapter touches the server and the platform', () {
    expect(
      filesMatching(
        RegExp("package:openlauncher/(server|platform)/"),
        except: inTvAdapter,
      ),
      isEmpty,
    );
  });

  test('the editor changes the layout by commands, not by writing it', () {
    expect(
      filesMatching(
        RegExp(r'\.(setLayout|revertLayout|addItem|removeEntity)\('),
      ),
      isEmpty,
    );
  });
}

bool _nowhere(File file) => false;
