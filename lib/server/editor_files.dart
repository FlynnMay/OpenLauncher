import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';

/// Serves the web editor (`lib/editor`) under `/editor/`, from the app's
/// assets, where `tool/build_editor.sh` puts it: one flat folder, `/` in a
/// path written `__`, every file gzipped, and a `version` that changes with
/// each build.
abstract final class EditorFiles {
  static const _mount = 'editor';
  static const _folder = 'assets/editor/';

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'json': 'application/json',
    // Browsers only compile it while it downloads if it is called this.
    'wasm': 'application/wasm',
    'png': 'image/png',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
  };

  /// Whether a request for [path] is one for the editor.
  static bool owns(String path) =>
      path == _mount || path.startsWith('$_mount/');

  /// Answers from [bundle], which is the app's own unless a test says so.
  static Future<Response> serve(Request request, [AssetBundle? bundle]) async {
    bundle ??= rootBundle;
    final path = request.url.path;
    // The page's own addresses are relative to the folder.
    if (path == _mount) return Response.movedPermanently('/$_mount/');
    final file = switch (path.substring(_mount.length + 1)) {
      '' => 'index.html',
      final file => file,
    };
    final ByteData data;
    final String tag;
    try {
      tag = '"${(await bundle.loadString('${_folder}version')).trim()}"';
      data = await bundle.load(_folder + file.replaceAll('/', '__'));
    } on FlutterError {
      return Response.notFound('Not found');
    }
    final headers = {
      'etag': tag,
      // Asked about each time, and only sent again after a new build.
      'cache-control': 'no-cache',
    };
    if (request.headers['if-none-match'] == tag) {
      return Response.notModified(headers: headers);
    }
    return Response.ok(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      headers: {
        ...headers,
        'content-type':
            _types[file.split('.').last] ?? 'application/octet-stream',
        'content-encoding': 'gzip',
      },
    );
  }
}
