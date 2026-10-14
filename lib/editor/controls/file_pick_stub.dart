/// A file the user chose. The browser uploads it directly, so it is never
/// held in memory here.
class PickedFile {
  String get name => throw UnsupportedError('No files outside a browser');

  /// Uploads the file with [method] to [uri].
  Future<({int status, String body})> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
  }) => throw UnsupportedError('No files outside a browser');
}

/// Opens a file dialog for [accept] (as a file input's `accept`); null if
/// cancelled.
Future<PickedFile?> pickFile({required String accept}) =>
    throw UnsupportedError('No files outside a browser');
