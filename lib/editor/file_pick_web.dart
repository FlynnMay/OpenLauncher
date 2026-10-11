import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// A file the user chose. The browser uploads it directly, so it is never
/// held in memory here.
class PickedFile {
  PickedFile._(this._file);

  final web.File _file;

  String get name => _file.name;

  /// Uploads the file with [method] to [uri].
  Future<({int status, String body})> send(String method, Uri uri) async {
    final response = await web.window
        .fetch(
          uri.toString().toJS,
          web.RequestInit(method: method, body: _file),
        )
        .toDart;
    return (
      status: response.status,
      body: (await response.text().toDart).toDart,
    );
  }
}

/// Opens a file dialog for [accept] (as a file input's `accept`); null if
/// cancelled.
Future<PickedFile?> pickFile({required String accept}) {
  final chosen = Completer<PickedFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept;
  void done(PickedFile? file) {
    if (!chosen.isCompleted) chosen.complete(file);
  }

  input.addEventListener(
    'change',
    ((web.Event _) => done(switch (input.files?.item(0)) {
      null => null,
      final file => PickedFile._(file),
    })).toJS,
  );
  input.addEventListener('cancel', ((web.Event _) => done(null)).toJS);
  input.click();
  return chosen.future;
}
