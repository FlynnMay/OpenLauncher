import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher/server/config_api.dart';
import 'package:openlauncher/server/config_server.dart';
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
  final fetched = <Uri>[];

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
        sourceFetcherProvider.overrideWithValue((source) async {
          if (source.url.contains('broken')) throw Exception('No answer');
          return {'state': 'on', 'asked': source.url};
        }),
        jsonFetcherProvider.overrideWithValue((uri) async {
          fetched.add(uri);
          return {
            'results': [
              {
                'name': 'Perth',
                'admin1': 'Western Australia',
                'country': 'Australia',
                'latitude': -31.95,
                'longitude': 115.86,
              },
            ],
          };
        }),
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

  Future<Map<String, dynamic>> state() async {
    final response = await call('GET', '/api/state');
    expect(response.statusCode, 200);
    return jsonDecode(await response.readAsString());
  }

  /// The apps and inputs the page is told about; the launcher's own
  /// Settings card is listed too, after them.
  Future<List<Map<String, dynamic>>> cards() async => [
    for (final Map<String, dynamic> card in (await state())['cards'])
      if (card['kind'] != 'action') card,
  ];

  /// The ids of the cards on the TV's home screen, in order.
  Future<List<String>> onTv() async => [
    for (final entry in (await container.read(
      layoutViewProvider.future,
    )).home.root.contents)
      if (entry is CardEntry && entry.card.kind != CardKind.action)
        entry.card.id,
  ];

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
      'sourceLabel': 'HDMI 1',
      'renamed': false,
      'customIcon': false,
      'iconFrom': null,
      'wide': false,
      'bare': true,
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

  test('state offers the layout and what there is to choose from', () async {
    final page = await state();
    // Nothing has been arranged yet, so every card is in the one section.
    // It sits in the screen's global pane.
    final section = page['layout']['panels'][0]['pane']['items'].single['pane'];
    expect(page['layout']['inbox'], section['id']);
    expect((section['items'] as List).map((i) => i['ref']), [
      'input:tv/HW1',
      'app:a',
      'app:b',
      'launcher:settings',
    ]);
    // No app on this device offers widgets, so that kind is not offered.
    expect((page['widgets'] as List).map((w) => w['type']), [
      'clock',
      'weather',
      'media',
      'text',
      'picture',
      'meter',
      'button',
    ]);
    // The quick actions are a popup in the layout like any folder.
    final menu = (page['layout']['panels'] as List).firstWhere(
      (panel) => panel['id'] == Layout.menuId,
    );
    expect(menu['pane']['items'], hasLength(usualMenu.length));
    expect(page['config']['toasts'], const ToastOptions().toJson());
    expect(page['notificationAccess'], isTrue);
  });

  test('a press from the page is done on the TV', () async {
    final platform =
        container.read(launcherPlatformProvider) as FakeLauncherPlatform;
    Future<Response> press(String what, {String? id, Map? more}) => call(
      'POST',
      '/api/remote${id == null ? '' : '?id=${Uri.encodeQueryComponent(id)}'}',
      body: {'do': what, ...?more},
    );
    Future<Object?> said(Response response) async {
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString());
    }

    await said(await press('open', id: 'app:a'));
    await said(await press('open', id: 'input:tv/HW1'));
    expect(platform.launched, ['a', 'tv/HW1']);
    // Settings is the launcher's own screen, and the page has its own.
    expect((await press('open', id: 'launcher:settings')).statusCode, 400);
    expect((await press('open', id: 'app:gone')).statusCode, 404);
    expect((await press('open')).statusCode, 404);

    await said(await press('info', id: 'app:a'));
    await said(await press('uninstall', id: 'app:b'));
    expect(await said(await press('forceStop', id: 'app:a')), {'done': true});
    platform.canForceStop = false;
    expect(await said(await press('forceStop', id: 'app:a')), {'done': false});
    expect(platform.appActions, ['info a', 'uninstall b', 'stop a']);
    // Only apps have these.
    expect((await press('info', id: 'input:tv/HW1')).statusCode, 400);

    await said(await press('media', more: {'command': 'playPause'}));
    expect(platform.mediaCommands, [MediaCommand.playPause]);
    expect((await press('media', more: {'command': 'louder'})).statusCode, 400);

    platform.homeButtonEnabled = false;
    expect(await said(await press('homeButton')), {
      'enabled': false,
      'canManage': false,
    });
    expect(await said(await press('setup')), {
      'outcome': 'done',
      'detail': null,
    });
    expect(await said(await press('homeButton', more: {'enabled': false})), {
      'enabled': false,
      'canManage': true,
    });
    await said(await press('tvSettings'));
    expect(platform.settingsOpened, 1);

    expect((await press('dance')).statusCode, 400);
  });

  test('what is playing is told, with its cover', () async {
    expect((await state())['nowPlaying'], isNull);

    final cover = File('${tmp.path}/art-1.png')..writeAsBytesSync(_png);
    final platform =
        container.read(launcherPlatformProvider) as FakeLauncherPlatform;
    platform.playing = NowPlaying(
      packageName: 'a',
      appLabel: 'A',
      title: 'Song',
      artist: 'Singer',
      artPath: cover.path,
      playing: true,
    );
    platform.notifyNowPlayingChanged();
    await pumpEventQueue();

    final playing = (await state())['nowPlaying'];
    expect(playing, {
      'package': 'a',
      'app': 'A',
      'title': 'Song',
      'artist': 'Singer',
      'playing': true,
      'art': '/api/media/art?id=art-1.png',
    });
    final art = await call('GET', playing['art']);
    expect(art.statusCode, 200);
    expect(art.headers['content-type'], 'image/png');
    // A cover that has since been replaced is not passed off as the old one.
    expect((await call('GET', '/api/media/art?id=art-0.png')).statusCode, 404);
  });

  test('a new layout is saved, repaired and shown on the TV', () async {
    final response = await call(
      'PUT',
      '/api/layout',
      body: {
        'inbox': 'rest',
        'panels': [
          {
            'id': 'home',
            'sections': [
              {
                'id': 'top',
                'title': 'Favourites',
                'mode': 'grid',
                'columns': 4,
                'items': [
                  {'id': 'i1', 'ref': 'app:b', 'x': 2, 'y': 0, 'w': 9},
                  {'id': 'i2', 'kind': 'panel', 'ref': 'games'},
                  {'id': 'i3', 'kind': 'panel', 'ref': 'nothing'},
                  {
                    'id': 'i4',
                    'kind': 'widget',
                    'ref': 'weather',
                    'options': {'place': 'Perth'},
                  },
                ],
              },
              {'id': 'rest'},
            ],
          },
          {
            'id': 'games',
            'title': 'Games',
            'position': 'bottom',
            'sections': [
              {
                'id': 'in',
                'items': [
                  {'id': 'i5', 'ref': 'app:a'},
                ],
              },
            ],
          },
        ],
      },
    );
    expect(response.statusCode, 200);

    final saved = store.config.layout;
    // The sections an older page sends arrive as panes in the global pane.
    final [top, rest] = saved.home.root.items.map((i) => i.pane!).toList();
    expect((top.mode, top.columns), (PaneMode.grid, 4));
    expect((top.title, saved.inbox), ('Favourites', rest.id));
    // Too wide for the section, and a link to a panel that does not exist.
    expect(top.items.map((i) => i.id), ['i1', 'i2', 'i4']);
    expect((top.items.first.w, top.items.first.x), (4, 0));
    expect(top.items.last.options, {'place': 'Perth'});
    expect(saved.panel('games')!.position, PopupPosition.bottom);

    // On the TV: app:b on top, app:a inside the folder, and the input,
    // which was placed nowhere, in the section for new cards.
    expect(await onTv(), ['app:b', 'input:tv/HW1']);
    final view = await container.read(layoutViewProvider.future);
    final folder = view.home.root.contents.elementAt(1) as PanelEntry;
    expect(folder.preview.single.id, 'app:a');
    final shown = (await state())['layout']['panels'][0]['pane']['items'][1];
    expect((shown['pane']['items'] as List).map((i) => i['ref']), [
      'input:tv/HW1',
      'launcher:settings',
    ]);
  });

  test('a folder card can have a picture, removed with the folder', () async {
    Map<String, Object?> layout(List<Object?> popups) => {
      'panels': [
        {
          'id': 'home',
          'sections': [
            {'id': 's'},
          ],
        },
        ...popups,
      ],
    };
    await call(
      'PUT',
      '/api/layout',
      body: layout([
        {'id': 'games', 'title': 'Games'},
      ]),
    );
    expect(
      (await call('PUT', '/api/icon?id=panel:nope', body: _png)).statusCode,
      404,
    );
    expect(
      (await call('PUT', '/api/icon?id=panel:home', body: _png)).statusCode,
      404,
    );
    expect(
      (await call('PUT', '/api/icon?id=panel:games', body: _png)).statusCode,
      200,
    );

    final url = (await state())['panelIcons']['games'] as String;
    final response = await call('GET', url);
    expect(response.headers['content-type'], 'image/png');
    expect(tmp.listSync(), hasLength(1));

    await call('PUT', '/api/layout', body: layout([]));
    expect(store.config.iconOverrides, isEmpty);
    expect(tmp.listSync(), isEmpty);
    expect((await state())['panelIcons'], isEmpty);
  });

  test('plain settings are set as they are saved', () async {
    var response = await call(
      'PUT',
      '/api/config',
      body: {
        'toasts': {'enabled': false, 'position': 'bottomLeft', 'seconds': 99},
      },
    );
    expect(response.statusCode, 200);
    expect(store.config.toasts.toJson(), {
      'enabled': false,
      'position': 'bottomLeft',
      'seconds': 30,
    });

    // What cannot be read is put right, not refused.
    response = await call('PUT', '/api/config', body: {'toasts': 'loud'});
    expect(response.statusCode, 200);
    expect(store.config.toasts.enabled, isTrue);
    // Only the plain settings are set this way: never the paths of files.
    response = await call(
      'PUT',
      '/api/config',
      body: {
        'wallpapers': ['/etc/passwd'],
      },
    );
    expect(response.statusCode, 400);
    expect(store.config.wallpapers, isEmpty);
  });

  test(
    'the values and the place are settings, and values are asked for',
    () async {
      var response = await call(
        'PUT',
        '/api/config',
        body: {
          'sources': [
            {
              'id': 'lamp',
              'name': 'Lamp',
              'kind': 'http',
              'url': 'http://ha/x',
            },
            {'id': 'motto', 'kind': 'text', 'text': 'Hi'},
            {'id': 'broken', 'kind': 'http', 'url': 'http://broken/x'},
          ],
          'place': {'name': 'Perth', 'latitude': -31.95, 'longitude': 115.86},
        },
      );
      expect(response.statusCode, 200);
      expect(store.config.sources.map((source) => source.id), [
        'lamp',
        'motto',
        'broken',
      ]);
      expect(store.config.place?.name, 'Perth');
      final told = await state();
      expect(told['config']['sources'][0], {
        'id': 'lamp',
        'name': 'Lamp',
        'kind': 'http',
        'url': 'http://ha/x',
        'every': 60,
      });
      expect(told['config']['place']['latitude'], -31.95);
      // The three of the user's own are offered like any other widget.
      expect([
        for (final widget in told['widgets']) widget['type'],
      ], containsAll(['text', 'picture', 'meter']));

      Future<(int, Object?)> value(String id) async {
        final response = await call('GET', '/api/source?id=$id');
        final said = jsonDecode(await response.readAsString()) as Map;
        return (response.statusCode, said['value']);
      }

      final lamp = await value('lamp');
      expect(lamp.$1, 200);
      expect(lamp.$2, {'state': 'on', 'asked': 'http://ha/x'});
      expect(await value('motto'), (200, 'Hi'));
      expect((await value('broken')).$1, 502);
      expect((await value('nobody')).$1, 404);

      // Only what is named is touched; a place is taken away with null.
      response = await call('PUT', '/api/config', body: {'place': null});
      expect(response.statusCode, 200);
      expect(store.config.place, isNull);
      expect(store.config.sources, hasLength(3));

      // A value that cannot be kept is left out; the rest are.
      response = await call(
        'PUT',
        '/api/config',
        body: {
          'sources': [
            {'id': 'time', 'kind': 'text'},
            {'id': 'a'},
            {'id': 'a'},
          ],
        },
      );
      expect(response.statusCode, 200);
      expect(store.config.sources.map((source) => source.id), ['a']);
    },
  );

  test('looks places up for the weather widget', () async {
    final response = await call('GET', '/api/geocode?q=Perth');
    expect(response.statusCode, 200);
    expect(jsonDecode(await response.readAsString()), {
      'places': [
        {
          'name': 'Perth, Western Australia, Australia',
          'latitude': -31.95,
          'longitude': 115.86,
        },
      ],
    });
    expect(fetched.single.queryParameters['name'], 'Perth');
    expect((await call('GET', '/api/geocode?q=')).statusCode, 400);
  });

  test('cards left out of the layout are removed, not put back', () async {
    final page = await state();
    final layout = page['layout'] as Map<String, dynamic>;
    final section = layout['panels'][0]['pane']['items'][0]['pane'];
    // What the page does to remove a card: drop its item and say so.
    (section['items'] as List).removeWhere((i) => i['ref'] == 'input:tv/HW1');
    layout['removed'] = ['input:tv/HW1'];
    expect((await call('PUT', '/api/layout', body: layout)).statusCode, 200);

    expect(await onTv(), ['app:a', 'app:b']);
    final after = await state();
    expect(after['layout']['removed'], ['input:tv/HW1']);
    // Still offered, so it can be added again.
    expect(
      (after['cards'] as List).map((c) => c['id']),
      contains('input:tv/HW1'),
    );

    // Adding it again, twice: a card can be in more than one place.
    final again = after['layout'] as Map<String, dynamic>;
    (again['panels'][0]['pane']['items'][0]['pane']['items'] as List).addAll([
      {'id': 'x1', 'ref': 'input:tv/HW1'},
      {'id': 'x2', 'ref': 'input:tv/HW1'},
    ]);
    await call('PUT', '/api/layout', body: again);
    expect(await onTv(), ['app:a', 'app:b', 'input:tv/HW1', 'input:tv/HW1']);
    expect(store.config.layout.removed, isEmpty);
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

  test('a card can be renamed and given another card\'s picture', () async {
    Future<Map<String, dynamic>> card(String id) async =>
        (await cards()).firstWhere((c) => c['id'] == id);

    var response = await call(
      'PUT',
      '/api/card?id=app:a',
      body: {'name': '  Films ', 'iconFrom': 'input:tv/HW1'},
    );
    expect(response.statusCode, 200);
    var a = await card('app:a');
    expect(a['label'], 'Films');
    expect(a['renamed'], isTrue);
    expect(a['iconFrom'], 'input:tv/HW1');
    expect(a['customIcon'], isTrue);
    response = await call('GET', a['icon'] as String);
    expect(response.headers['content-type'], 'image/svg+xml');

    // Leaving a key out leaves that part alone.
    await call('PUT', '/api/card?id=app:a', body: {'name': null});
    a = await card('app:a');
    expect(a['label'], 'A');
    expect(a['iconFrom'], 'input:tv/HW1');

    // An uploaded picture and a borrowed one replace each other.
    await call('PUT', '/api/icon?id=app:a', body: _png);
    expect(store.config.iconSources, isEmpty);
    await call('PUT', '/api/card?id=app:b', body: {'iconFrom': 'app:a'});
    response = await call('GET', (await card('app:b'))['icon'] as String);
    expect(await response.read().expand((b) => b).toList(), _png);
    await call('PUT', '/api/card?id=app:a', body: {'iconFrom': 'app:b'});
    expect(store.config.iconOverrides, isEmpty);
    expect(tmp.listSync(), isEmpty);

    // "Reset picture" undoes a borrowed one too.
    await call('DELETE', '/api/icon?id=app:a');
    expect(store.config.iconSources, {'app:b': 'app:a'});

    for (final bad in [
      {'iconFrom': 'app:a'},
      {'iconFrom': 'app:nope'},
      {'name': 7},
      {'name': 'x' * 61},
    ]) {
      response = await call('PUT', '/api/card?id=app:a', body: bad);
      expect(response.statusCode, 400, reason: '$bad');
    }
    response = await call('PUT', '/api/card?id=app:nope', body: {'name': 'x'});
    expect(response.statusCode, 404);
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

    /// The first wallpaper, which is the one shown.
    Future<Map<String, dynamic>?> wallpaper() async {
      final response = await call('GET', '/api/state');
      final all = jsonDecode(await response.readAsString())['wallpapers'];
      return (all as List).firstOrNull;
    }

    test('video upload becomes the wallpaper and can be removed', () async {
      expect(await wallpaper(), isNull);

      var response = await call('POST', '/api/wallpapers', body: mp4);
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

      // With none named, all of them go, and their files with them.
      await call('POST', '/api/wallpapers', body: _png);
      response = await call('DELETE', '/api/wallpaper');
      expect(saved.existsSync(), isFalse);
      expect(response.statusCode, 200);
      expect(await wallpaper(), isNull);
      expect(store.config.wallpaper, isNull);
      expect(Directory('${tmp.path}/wallpaper').listSync(), isEmpty);
    });

    test('several wallpapers are kept, ordered, timed and removed', () async {
      Future<List<Map<String, dynamic>>> all() async =>
          ((await state())['wallpapers'] as List).cast();

      expect(
        (await call('POST', '/api/wallpapers', body: mp4)).statusCode,
        200,
      );
      await call('POST', '/api/wallpapers', body: _png);
      var list = await all();
      expect([for (final one in list) one['kind']], ['video', 'image']);
      // The first is the one shown.
      expect(container.read(wallpaperProvider)?.kind, WallpaperKind.video);

      // Each is served by its own name.
      final picture = await call('GET', list[1]['url'] as String);
      expect(picture.headers['content-type'], 'image/png');

      var response = await call(
        'PUT',
        '/api/wallpapers',
        body: {
          'order': [list[1]['id'], list[0]['id']],
          'every': 15,
        },
      );
      expect(response.statusCode, 200);
      expect([for (final one in await all()) one['kind']], ['image', 'video']);
      expect((await state())['wallpaperEvery'], 15);
      expect(store.config.wallpaperEvery, 15);

      response = await call('DELETE', '/api/wallpaper?id=${list[0]['id']}');
      expect(response.statusCode, 200);
      expect([for (final one in await all()) one['kind']], ['image']);
      expect(Directory('${tmp.path}/wallpaper').listSync(), hasLength(1));
      expect(
        (await call('DELETE', '/api/wallpaper?id=nothing.png')).statusCode,
        404,
      );
    });

    test('serves byte ranges for video playback', () async {
      await call('POST', '/api/wallpapers', body: mp4);
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
        'POST',
        '/api/wallpapers',
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
    expect(await status('PUT', '/api/hidden?id=app:a', body: {}), 404);
    expect(await status('DELETE', '/api/icon?id=app:zzz'), 404);
    expect(await status('PUT', '/api/layout', body: 'not json'), 400);
    expect(
      await status(
        'PUT',
        '/api/layout',
        body: {
          'panels': [1],
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

    await call(
      'PUT',
      '/api/config',
      body: {
        'toasts': {'seconds': 9},
      },
    );
    await pumpEventQueue();
    expect(events, hasLength(2));
    expect(events.last['config']['toasts']['seconds'], 9);
  });

  test('the real server answers over HTTP', () async {
    final server = (await container.read(configServerProvider.future))!;
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.get('127.0.0.1', server.port, '/api/state');
    final response = await request.close();
    expect(response.statusCode, 200);
    final state = jsonDecode(await response.transform(utf8.decoder).join());
    expect(state['cards'], hasLength(4));
  });
}
