/// A file the user chose. Its bytes stay with the browser, which sends them
/// itself, so a large video is never held in memory here.
class PickedFile {
  String get name => throw UnsupportedError('No files outside a browser');

  /// Sends the file as the body of a [method] request to [uri]. Answers
  /// with the status and the text of the reply.
  Future<({int status, String body})> send(String method, Uri uri) =>
      throw UnsupportedError('No files outside a browser');
}

/// Lets the user choose a file of the kinds [accept] names, as the `accept`
/// of a file input does (`image/*`, `.mp4`); null if they choose none.
Future<PickedFile?> pickFile({required String accept}) =>
    throw UnsupportedError('No files outside a browser');
