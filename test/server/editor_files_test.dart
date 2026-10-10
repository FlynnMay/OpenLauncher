import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/server/editor_files.dart';
import 'package:shelf/shelf.dart';

/// Holds what `tool/build_editor.sh` would have put in the app.
class _Built extends CachingAssetBundle {
  _Built(Map<String, String> files)
    : _files = {
        for (final MapEntry(:key, :value) in files.entries)
          'assets/editor/$key': gzip.encode(utf8.encode(value)),
        'assets/editor/version': utf8.encode('abc\n'),
      };

  final Map<String, List<int>> _files;

  @override
  Future<ByteData> load(String key) async => switch (_files[key]) {
    null => throw FlutterError('Unable to load asset: $key'),
    final bytes => ByteData.sublistView(Uint8List.fromList(bytes)),
  };
}

void main() {
  final built = _Built({
    'index.html': '<html>editor</html>',
    'canvaskit__chromium__canvaskit.wasm': 'wasm',
  });

  Future<Response> get(String path, {Map<String, String>? headers}) =>
      EditorFiles.serve(
        Request('GET', Uri.parse('http://tv/$path'), headers: headers),
        built,
      );

  Future<String> unzipped(Response response) async => utf8.decode(
    gzip.decode(await response.read().expand((chunk) => chunk).toList()),
  );

  test('everything but the API is the editor\'s', () {
    expect(EditorFiles.owns(''), isTrue);
    expect(EditorFiles.owns('main.dart.js'), isTrue);
    expect(EditorFiles.owns('apiary'), isTrue);
    expect(EditorFiles.owns('api'), isFalse);
    expect(EditorFiles.owns('api/state'), isFalse);
  });

  test('serves the page at the root, gzipped as it was built', () async {
    final page = await get('');
    expect(page.statusCode, 200);
    expect(page.headers['content-type'], startsWith('text/html'));
    expect(page.headers['content-encoding'], 'gzip');
    expect(await unzipped(page), '<html>editor</html>');
  });

  test('finds files in folders, and says so when there is none', () async {
    final wasm = await get('canvaskit/chromium/canvaskit.wasm');
    expect(wasm.headers['content-type'], 'application/wasm');
    expect(await unzipped(wasm), 'wasm');
    expect((await get('nothing.js')).statusCode, 404);
  });

  test('is not sent again until it is built again', () async {
    final tag = (await get('')).headers['etag']!;
    expect(tag, '"abc"');
    final again = await get('', headers: {'if-none-match': tag});
    expect(again.statusCode, 304);
  });
}
