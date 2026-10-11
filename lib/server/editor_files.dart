import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shelf/shelf.dart';

/// Serves the web editor from the app's assets, as `tool/build_editor.sh`
/// lays it out: flat, `/` written as `__`, gzipped, with a `version` file per
/// build.
abstract final class EditorFiles {
  static const _api = 'api';
  static const _folder = 'assets/editor/';

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'json': 'application/json',
    // Required for streaming compilation.
    'wasm': 'application/wasm',
    'png': 'image/png',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
  };

  /// Whether [path] is the editor's rather than the API's.
  static bool owns(String path) => path != _api && !path.startsWith('$_api/');

  /// [bundle] is overridden in tests.
  static Future<Response> serve(Request request, [AssetBundle? bundle]) async {
    bundle ??= rootBundle;
    final path = request.url.path;
    final file = path.isEmpty ? 'index.html' : path;
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
      // Revalidated each time; re-sent only after a new build.
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
