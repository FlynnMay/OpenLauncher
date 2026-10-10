import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/cards/cards_provider.dart';
import 'package:openlauncher/core/cards/input_artwork.dart';
import 'package:openlauncher/core/config/config_store.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher/server/config_api.dart';
import 'package:openlauncher/server/config_server.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
import 'package:openlauncher/server/custom_icons.dart';
import 'package:openlauncher/server/wallpaper_store.dart';
import 'package:shelf/shelf.dart';

// The smallest valid PNG header is enough: the server only sniffs the type.
final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
]);

void main() {
  late MemoryConfigStore store;
  late Directory tmp;
  late ProviderContainer container;
  late ConfigApi api;

  setUp(() async {
    store = MemoryConfigStore();
    tmp = await Directory.systemTemp.createTemp('openlauncher_test');
    container = ProviderContainer(
      overrides: [
        configStoreProvider.overrideWithValue(store),
        launcherPlatformProvider.overrideWithValue(
          FakeLauncherPlatform(
            [
              InstalledApp(packageName: 'a', label: 'A', isBanner: false),
              InstalledApp(packageName: 'b', label: 'B', isBanner: false),
            ],
            [TvInput(id: 'tv/HW1', label: 'HDMI 1', kind: TvInputKind.hdmi)],
          ),
        ),
        customIconDirProvider.overrideWith((ref) => tmp),
        wallpaperDirProvider.overrideWith(
          (ref) => Directory('${tmp.path}/wallpaper'),
        ),
        configPageProvider.overrideWith((ref) => '<html>page</html>'),
      ],
    );
    // Listened to, as it is in the app, so it keeps following state changes.
    api = container.listen(configApiProvider, (_, _) {}).read();
    addTearDown(() async {
      container.dispose();
      await tmp.delete(recursive: true);
    });
  });

  Future<Response> call(String method, String path, {Object? body}) =>
      api.handle(
        Request(
          method,
          Uri.parse('http://tv$path'),
          body: body is Map ? jsonEncode(body) : body,
        ),
      );

  Future<List<Map<String, dynamic>>> cards() async {
    final response = await call('GET', '/api/state');
    expect(response.statusCode, 200);
    final state = jsonDecode(await response.readAsString());
    return (state['cards'] as List).cast();
  }

  test('serves the page', () async {
    final response = await call('GET', '/');
    expect(response.headers['content-type'], contains('text/html'));
    expect(await response.readAsString(), '<html>page</html>');
  });

  test('state lists every card in display order', () async {
    expect((await cards()).map((c) => c['id']), [
      'input:tv/HW1',
      'app:a',
      'app:b',
    ]);
    expect((await cards()).first, {
      'id': 'input:tv/HW1',
      'kind': 'input',
      'label': 'HDMI 1',
      'hidden': false,
      'customIcon': false,
      'wide': false,
      'icon': isA<String>(),
    });

    // Inputs get built-in line art, served to the page as SVG.
    final icon = (await cards()).first['icon'] as String;
    final response = await call('GET', icon);
    expect(response.headers['content-type'], 'image/svg+xml');
    expect(
      await response.readAsString(),
      inputArtworkSvg(TvInputKind.hdmi, 'HDMI 1'),
    );
    expect((await cards()).last['icon'], isNull);
  });

  test('reordering is saved and changes the TV cards', () async {
    final response = await call(
      'PUT',
      '/api/order',
      body: {
        'order': ['app:b', 'input:tv/HW1', 'app:a'],
      },
    );
    expect(response.statusCode, 200);
    expect(store.config.order, ['app:b', 'input:tv/HW1', 'app:a']);
    final tv = await container.read(cardsProvider.future);
    expect(tv.map((c) => c.id), ['app:b', 'input:tv/HW1', 'app:a']);
  });

  test('hidden cards stay on the page but leave the TV', () async {
    final id = Uri.encodeQueryComponent('input:tv/HW1');
    await call('PUT', '/api/hidden?id=$id', body: {'hidden': true});
    expect((await cards()).first['hidden'], isTrue);
    final tv = await container.read(cardsProvider.future);
    expect(tv.map((c) => c.id), ['app:a', 'app:b']);
  });

  test('custom image upload, download and reset', () async {
    var response = await call('PUT', '/api/icon?id=app:a', body: _png);
    expect(response.statusCode, 200);

    var card = (await cards()).firstWhere((c) => c['id'] == 'app:a');
    expect(card['customIcon'], isTrue);
    expect(card['wide'], isTrue);
    final saved = File(store.config.iconOverrides['app:a']!);
    expect(saved.parent.path, tmp.path);

    response = await call('GET', card['icon'] as String);
    expect(response.headers['content-type'], 'image/png');
    expect(await response.read().expand((b) => b).toList(), _png);

    // A second upload replaces the first file rather than leaving it behind.
    await call('PUT', '/api/icon?id=app:a', body: _png);
    expect(saved.existsSync(), isFalse);
    expect(tmp.listSync(), hasLength(1));

    response = await call('DELETE', '/api/icon?id=app:a');
    expect(response.statusCode, 200);
    expect(store.config.iconOverrides, isEmpty);
    expect(tmp.listSync(), isEmpty);
    card = (await cards()).firstWhere((c) => c['id'] == 'app:a');
    expect(card['customIcon'], isFalse);
  });

  group('wallpaper', () {
    // Just enough of an MP4 for the type to be recognised.
    final mp4 = Uint8List.fromList([
      0,
      0,
      0,
      24,
      ...ascii.encode('ftypisom'),
      ...List.filled(40, 7),
    ]);

    Future<Map<String, dynamic>?> wallpaper() async {
      final response = await call('GET', '/api/state');
      return jsonDecode(await response.readAsString())['wallpaper'];
    }

    test('video upload becomes the wallpaper and can be removed', () async {
      expect(await wallpaper(), isNull);

      var response = await call('PUT', '/api/wallpaper', body: mp4);
      expect(response.statusCode, 200);
      final state = (await wallpaper())!;
      expect(state['kind'], 'video');
      final saved = File(store.config.wallpaper!);
      expect(saved.readAsBytesSync(), mp4);
      expect(
        container.read(wallpaperProvider),
        Wallpaper(saved.path, WallpaperKind.video),
      );

      response = await call('GET', state['url'] as String);
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'video/mp4');
      expect(response.headers['content-length'], '${mp4.length}');

      // A picture replaces the video and removes its file.
      await call('PUT', '/api/wallpaper', body: _png);
      expect((await wallpaper())!['kind'], 'image');
      expect(saved.existsSync(), isFalse);

      response = await call('DELETE', '/api/wallpaper');
      expect(response.statusCode, 200);
      expect(await wallpaper(), isNull);
      expect(store.config.wallpaper, isNull);
      expect(Directory('${tmp.path}/wallpaper').listSync(), isEmpty);
    });

    test('serves byte ranges for video playback', () async {
      await call('PUT', '/api/wallpaper', body: mp4);
      Future<Response> range(String value) => api.handle(
        Request(
          'GET',
          Uri.parse('http://tv/api/wallpaper'),
          headers: {'range': value},
        ),
      );
      Future<List<int>> bytes(Response r) => r.read().expand((b) => b).toList();

      var response = await range('bytes=4-11');
      expect(response.statusCode, 206);
      expect(response.headers['content-range'], 'bytes 4-11/${mp4.length}');
      expect(await bytes(response), mp4.sublist(4, 12));

      response = await range('bytes=50-');
      expect(await bytes(response), mp4.sublist(50));

      response = await range('bytes=-5');
      expect(await bytes(response), mp4.sublist(mp4.length - 5));

      expect((await range('bytes=999-')).statusCode, 416);
    });

    test('rejects files that are not pictures or videos', () async {
      final response = await call(
        'PUT',
        '/api/wallpaper',
        body: utf8.encode('just some text'),
      );
      expect(response.statusCode, 415);
      expect(store.config.wallpaper, isNull);
      expect(Directory('${tmp.path}/wallpaper').listSync(), isEmpty);
      expect((await call('GET', '/api/wallpaper')).statusCode, 404);
    });

    test('recognises WebM and Matroska', () {
      Uint8List ebml(String docType) => Uint8List.fromList([
        0x1A,
        0x45,
        0xDF,
        0xA3,
        0x9F,
        0x42,
        0x82,
        0x84,
        ...ascii.encode(docType),
        ...List.filled(20, 0),
      ]);
      expect(sniffVideoExtension(ebml('webm')), 'webm');
      expect(sniffVideoExtension(ebml('matroska')), 'mkv');
      expect(sniffVideoExtension(_png), isNull);
    });
  });

  test('rejects bad requests', () async {
    Future<int> status(String method, String path, {Object? body}) async =>
        (await call(method, path, body: body)).statusCode;

    expect(await status('GET', '/nope'), 404);
    expect(await status('PUT', '/api/hidden?id=app:zzz', body: {}), 404);
    expect(await status('PUT', '/api/hidden?id=app:a', body: {}), 400);
    expect(await status('PUT', '/api/order', body: 'not json'), 400);
    expect(
      await status(
        'PUT',
        '/api/order',
        body: {
          'order': [1],
        },
      ),
      400,
    );
    expect(
      await status('PUT', '/api/icon?id=app:a', body: utf8.encode('hello')),
      415,
    );
    expect(store.config.iconOverrides, isEmpty);
  });

  test('event stream sends the state now and after each change', () async {
    final response = await call('GET', '/api/events');
    expect(response.headers['content-type'], 'text/event-stream');
    final events = <Map<String, dynamic>>[];
    final sub = response.read().transform(utf8.decoder).listen((chunk) {
      for (final line in const LineSplitter().convert(chunk)) {
        if (line.startsWith('data: ')) {
          events.add(jsonDecode(line.substring(6)));
        }
      }
    });
    addTearDown(sub.cancel);

    await cards();
    await pumpEventQueue();
    expect(events, hasLength(1));

    await call('PUT', '/api/hidden?id=app:a', body: {'hidden': true});
    await pumpEventQueue();
    expect(events, hasLength(2));
    final a = (events.last['cards'] as List).firstWhere(
      (c) => c['id'] == 'app:a',
    );
    expect(a['hidden'], isTrue);
  });

  test('the real server answers over HTTP', () async {
    final server = (await container.read(configServerProvider.future))!;
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.get('127.0.0.1', server.port, '/api/state');
    final response = await request.close();
    expect(response.statusCode, 200);
    final state = jsonDecode(await response.transform(utf8.decoder).join());
    expect(state['cards'], hasLength(3));
  });
}
