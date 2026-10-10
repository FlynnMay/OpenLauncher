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

  test('knows which addresses are the editor\'s', () {
    expect(EditorFiles.owns('editor'), isTrue);
    expect(EditorFiles.owns('editor/main.dart.js'), isTrue);
    expect(EditorFiles.owns('editors'), isFalse);
    expect(EditorFiles.owns('api/state'), isFalse);
  });

  test('serves the page at the folder, gzipped as it was built', () async {
    expect((await get('editor')).headers['location'], '/editor/');
    final page = await get('editor/');
    expect(page.statusCode, 200);
    expect(page.headers['content-type'], startsWith('text/html'));
    expect(page.headers['content-encoding'], 'gzip');
    expect(await unzipped(page), '<html>editor</html>');
  });

  test('finds files in folders, and says so when there is none', () async {
    final wasm = await get('editor/canvaskit/chromium/canvaskit.wasm');
    expect(wasm.headers['content-type'], 'application/wasm');
    expect(await unzipped(wasm), 'wasm');
    expect((await get('editor/nothing.js')).statusCode, 404);
  });

  test('is not sent again until it is built again', () async {
    final tag = (await get('editor/')).headers['etag']!;
    expect(tag, '"abc"');
    final again = await get('editor/', headers: {'if-none-match': tag});
    expect(again.statusCode, 304);
  });
}
