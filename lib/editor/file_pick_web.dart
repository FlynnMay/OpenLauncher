import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// A file the user chose. Its bytes stay with the browser, which sends them
/// itself, so a large video is never held in memory here.
class PickedFile {
  PickedFile._(this._file);

  final web.File _file;

  String get name => _file.name;

  /// Sends the file as the body of a [method] request to [uri]. Answers
  /// with the status and the text of the reply.
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

/// Lets the user choose a file of the kinds [accept] names, as the `accept`
/// of a file input does (`image/*`, `.mp4`); null if they choose none.
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
