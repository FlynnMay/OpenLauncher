import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/main.dart';
import 'package:openlauncher/editor/tv/tv.dart';

class _Tv extends TvApi {
  final files = <MediaFile>[];

  @override
  Future<void> setLayout(Layout layout) async {}

  @override
  Future<void> setConfig(Map<String, Object?> changed) async {}

  @override
  Future<List<MediaFile>> media() async => [...files];

  @override
  Future<void> deleteMedia(String id) async =>
      files.removeWhere((file) => file.id == id);

  @override
  Future<int> deleteUnusedMedia() async {
    final before = files.length;
    files.removeWhere((file) => !file.used);
    return before - files.length;
  }
}

MediaFile _file(String id, int bytes, {required bool used}) =>
    (id: id, url: 'http://tv/api/media/$id', bytes: bytes, used: used);

void main() {
  Future<void> pump(WidgetTester tester, _Tv tv, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...tvOverrides,
          tvApiProvider.overrideWithValue(tv),
          tvStateProvider.overrideWith(
            (ref) => Stream.value(
              TvState(
                entities: const [
                  Entity(id: 'app:a', category: appCategory, label: 'Alpha'),
                ],
                config: LauncherConfig(layout: Layout.initial(['app:a'])),
                components: const [],
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: EditorScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the toolbar fits a phone', (tester) async {
    await pump(tester, _Tv(), const Size(360, 800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the media manager lists every file and deletes the unused', (
    tester,
  ) async {
    final tv = _Tv()
      ..files.addAll([
        _file('w.mp4', 3 << 20, used: true),
        _file('a.mkv', 2048, used: false),
        _file('b.mkv', 1024, used: false),
      ]);
    await pump(tester, tv, const Size(1600, 900));
    await tester.tap(find.byTooltip('Media'));
    await tester.pumpAndSettle();
    expect(find.text('3 files, 2 unused (3 KB)'), findsOneWidget);
    expect(find.text('3.0 MB'), findsOneWidget);
    expect(find.text('Unused'), findsNWidgets(2));

    // One at a time.
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    expect(tv.files.map((file) => file.id), ['w.mp4', 'b.mkv']);
    expect(find.text('2 files, 1 unused (1 KB)'), findsOneWidget);

    // Or all at once, once confirmed.
    await tester.tap(find.text('Delete unused'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(tv.files.single.id, 'w.mp4');
    expect(find.text('1 files, 0 unused (0 KB)'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Delete unused'),
              matching: find.bySubtype<FilledButton>(),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  test('files travel as ids and are URLs here', () async {
    final asked = <http.Request>[];
    final api = TvApi(
      client: MockClient.streaming((request, body) async {
        if (request.url.path == '/api/events') {
          final state = {
            'entities': [],
            'layout': Layout.initial().toJson(),
            'config': {
              'iconOverrides': {'app:a': 'picture-1.png'},
              'wallpapers': ['wallpaper-2.mp4'],
              'names': {'app:a': 'Films'},
              'wallpaperEvery': 5,
            },
            'components': [],
            'widgetProviders': [],
          };
          return http.StreamedResponse(
            Stream.value(utf8.encode('data: ${jsonEncode(state)}\n\n')),
            200,
          );
        }
        asked.add(
          http.Request(request.method, request.url)
            ..bodyBytes = await body.toBytes(),
        );
        return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
      }),
    );
    final config = (await api.states().first).config;
    final picture = config.iconOverrides['app:a']!;
    expect(Uri.parse(picture).path, '/api/media/picture-1.png');
    expect(Uri.parse(config.wallpaper!).path, '/api/media/wallpaper-2.mp4');
    expect(config.names, {'app:a': 'Films'});
    expect(config.wallpaperEvery, 5);

    await api.setConfig({
      'iconOverrides': config.iconOverrides,
      'wallpapers': config.wallpapers,
      'names': config.names,
    });
    expect(asked.single.url.path, '/api/config');
    expect(jsonDecode(asked.single.body), {
      'iconOverrides': {'app:a': 'picture-1.png'},
      'wallpapers': ['wallpaper-2.mp4'],
      'names': {'app:a': 'Films'},
    });
  });
}
