import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/actions/actions.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
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
        feedFetcherProvider.overrideWithValue((feed) async {
          if (feed.address.host == 'broken') throw Exception('No answer');
          return {'state': 'on', 'asked': '${feed.address}'};
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
  /// Settings entity is listed too, after them.
  Future<List<Map<String, dynamic>>> entities() async => [
    for (final Map<String, dynamic> entity in (await state())['entities'])
      // What the device offers: the apps and the inputs.
      if (entity['category'] == 'app' || entity['category'] == 'input') entity,
  ];

  /// The ids of the entities on the TV's home screen, in order.
  Future<List<String>> onTv() async {
    final all = await container.read(entitiesProvider.future);
    return [
      for (final item in (await container.read(
        layoutViewProvider.future,
      )).home.root.ownContents)
        if (all.byId(item.handed.firstOrNull) case final entity?
            when entity.category == appCategory ||
                entity.category == inputCategory)
          entity.id,
    ];
  }

  test('state lists every entity in display order', () async {
    expect((await entities()).map((c) => c['id']), [
      'input:tv/HW1',
      'app:a',
      'app:b',
    ]);
    expect((await entities()).first, {
      'id': 'input:tv/HW1',
      'category': 'input',
      // What it defines: the operation each action runs, and with what.
      'actions': {
        'open': {
          'run': 'switchInput',
          'with': {'input': '{{self.input}}'},
          'label': 'Open',
          'icon': 'play',
        },
      },
      'prefab': 'app-card',
      'placed': true,
      'label': 'HDMI 1',
      'name': 'HDMI 1',
      'renamed': false,
      'customIcon': false,
      'iconFrom': null,
      // What there is to read of it, its picture as where to fetch it.
      'data': {'input': 'tv/HW1', 'icon': isA<String>(), 'shape': 'line'},
    });

    // Inputs get built-in line art, served to the page as SVG.
    final icon = (await entities()).first['data']['icon'] as String;
    final response = await call('GET', icon);
    expect(response.headers['content-type'], 'image/svg+xml');
    expect(
      await response.readAsString(),
      inputArtworkSvg(TvInputKind.hdmi, 'HDMI 1'),
    );
    expect((await entities()).last['data']['icon'], isNull);
  });

  test('state offers the layout and what there is to choose from', () async {
    final page = await state();
    // Nothing has been arranged yet, so every entity is in the one section.
    // It sits in the screen's global pane.
    final section = page['layout']['layers'][0]['root']['children'].first;
    expect(page['layout']['inbox'], section['id']);
    expect(
      (section['children'] as List).map((i) => i['vars']?['source']?['value']),
      ['input:tv/HW1', 'app:a', 'app:b', 'launcher:settings'],
    );
    // No app on this device offers widgets, so that kind is not offered.
    expect((page['components'] as List).map((w) => w['type']), [
      'text',
      'picture',
      'meter',
      'icon',
      'folder',
      'button',
    ]);
    // The quick actions are a pane docked on the home layer, like any
    // folder.
    final menu = (page['layout']['layers'][0]['root']['children'] as List)
        .firstWhere((pane) => pane['id'] == Layout.menuId);
    expect(menu['options']['dock'], 'center');
    expect(menu['children'], hasLength(defaultMenu.length));
    // And the home layer's layout is an entity that can be told to add and
    // remove.
    final home = (page['entities'] as List).firstWhere(
      (entity) => entity['id'] == Layout.homeId,
    );
    expect(home['category'], 'layout');
    expect(page['config']['toasts'], const ToastOptions().toJson());
    expect(page['notificationAccess'], isTrue);
  });

  test('an action sent by the page is done on the TV', () async {
    final platform =
        container.read(launcherPlatformProvider) as FakeLauncherPlatform;
    Future<Response> act(String what, {String? on, Map? more}) =>
        call('POST', '/api/act', body: {'do': what, 'entity': ?on, ...?more});
    Future<Object?> said(Response response) async {
      expect(response.statusCode, 200);
      return jsonDecode(await response.readAsString())['message'];
    }

    await said(await act('open', on: 'app:a'));
    await said(await act('open', on: 'input:tv/HW1'));
    expect(platform.launched, ['a', 'tv/HW1']);
    // Settings opens on a screen, and there is none here: nothing is done.
    await said(await act('open', on: 'launcher:settings'));
    // An improper payload is declined: an entity that is not there, or none
    // named.
    expect((await act('open', on: 'app:gone')).statusCode, 400);
    expect((await act('open')).statusCode, 400);
    expect((await act('open', on: '')).statusCode, 400);
    expect(platform.launched, hasLength(2));

    await said(await act('info', on: 'app:a'));
    await said(await act('uninstall', on: 'app:b'));
    expect(await said(await act('forceStop', on: 'app:a')), 'A was stopped.');
    // What the TV cannot do itself, it shows the way to, and says so.
    platform.canForceStop = false;
    expect(
      await said(await act('forceStop', on: 'app:a')),
      startsWith('Choose "Force stop"'),
    );
    expect(platform.appActions, ['info a', 'uninstall b', 'stop a', 'info a']);
    // Only apps have these.
    expect((await act('info', on: 'input:tv/HW1')).statusCode, 400);

    await said(await act('playPause', on: 'media'));
    expect(platform.mediaCommands, [MediaCommand.playPause]);

    // How the Home button stands is part of the state.
    platform.homeButtonEnabled = false;
    container.invalidate(homeButtonEnabledProvider);
    expect((await state())['homeButton'], {
      'enabled': false,
      'canManage': false,
    });
    // The system's actions name it too; no owner is guessed.
    expect((await act('setup')).statusCode, 400);
    expect((await act('playPause')).statusCode, 400);
    expect(
      await said(await act('setup', on: 'system')),
      startsWith('All set\n'),
    );
    expect((await state())['homeButton'], {'enabled': true, 'canManage': true});
    await said(await act('homeButton', on: 'system', more: {'enabled': false}));
    expect((await state())['homeButton'], {
      'enabled': false,
      'canManage': true,
    });
    await said(await act('tvSettings', on: 'system'));
    expect(platform.settingsOpened, 1);

    // What is not the device's doing is done all the same: a variable set.
    await said(
      await act(
        'set',
        on: 'variables',
        more: {'of': 'lamp', 'var': 'on', 'value': true},
      ),
    );
    expect(
      (await act('set', more: {'of': 'lamp', 'var': 'on'})).statusCode,
      400,
    );

    expect((await act('dance', on: 'system')).statusCode, 400);
    expect((await call('POST', '/api/act', body: {})).statusCode, 400);
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
        'layers': [
          {
            'id': 'home',
            'root': {
              'id': 'home/root',
              'kind': 'pane',
              'options': {'mode': 'free', 'columns': 12},
              'children': [
                {
                  'id': 'top',
                  'kind': 'pane',
                  'options': {
                    'title': 'Favourites',
                    'mode': 'grid',
                    'columns': 4,
                  },
                  'children': [
                    {
                      'id': 'i1',
                      'prefab': 'app-card',
                      'vars': {
                        'source': {'value': 'app:b', 'type': 'entity'},
                      },
                      'transform': {'x': 2, 'y': 0, 'w': 9},
                    },
                    {
                      'id': 'i2',
                      'prefab': 'folder-card',
                      'vars': {
                        'source': {'value': 'games', 'type': 'entity'},
                      },
                    },
                    {
                      'id': 'i3',
                      'prefab': 'folder-card',
                      'vars': {
                        'source': {'value': 'nothing', 'type': 'entity'},
                      },
                    },
                    {
                      'id': 'i4',
                      'prefab': 'weather',
                      'vars': {
                        'source': {'value': 'weather', 'type': 'entity'},
                      },
                    },
                  ],
                },
                {'id': 'rest', 'kind': 'pane'},
                {
                  'id': 'games',
                  'kind': 'pane',
                  'options': {'title': 'Games', 'dock': 'bottom'},
                  'children': [
                    {
                      'id': 'i5',
                      'prefab': 'app-card',
                      'vars': {
                        'source': {'value': 'app:a', 'type': 'entity'},
                      },
                    },
                  ],
                },
              ],
            },
          },
        ],
      },
    );
    expect(response.statusCode, 200);

    final saved = store.config.layout;
    final [top, rest, games] = saved.home.root.children;
    expect((top.mode, top.columns), (PaneMode.grid, 4));
    expect((top.title, saved.inbox), ('Favourites', rest.id));
    // Too wide for the pane, and a link to a panel that does not exist.
    expect(top.children.map((i) => i.id), ['i1', 'i2', 'i4']);
    expect((top.children.first.w, top.children.first.x), (4, 0));
    expect(
      (top.children.last.prefab, top.children.last.handed.firstOrNull),
      ('weather', 'weather'),
    );
    expect((games.dock, games.hovers), ('bottom', true));

    // On the TV: app:b on top, app:a inside the folder, and the input,
    // which was placed nowhere, in the pane for new entities.
    expect(await onTv(), ['app:b', 'input:tv/HW1']);
    final view = await container.read(layoutViewProvider.future);
    final folder = view.home.root.contents.elementAt(1);
    expect(folder.prefab, folderPrefabId);
    expect(
      view
          .pane(folder.handed.firstOrNull!)!
          .contents
          .map((entry) => entry.handed.firstOrNull),
      ['app:a'],
    );
    final shown = (await state())['layout']['layers'][0]['root']['children'][1];
    expect(
      (shown['children'] as List).map((i) => i['vars']?['source']?['value']),
      ['input:tv/HW1', 'launcher:settings'],
    );
  });

  test('a folder entity can have a picture, removed with the folder', () async {
    Map<String, Object?> layout(List<Object?> folders) => {
      'layers': [
        {
          'id': 'home',
          'root': {'id': 'home/root', 'kind': 'pane', 'children': folders},
        },
      ],
    };
    await call(
      'PUT',
      '/api/layout',
      body: layout([
        {
          'id': 'games',
          'kind': 'pane',
          'options': {'title': 'Games', 'dock': 'center'},
        },
      ]),
    );
    expect(
      (await call('PUT', '/api/icon?id=folder:nope', body: _png)).statusCode,
      404,
    );
    expect(
      (await call(
        'PUT',
        '/api/icon?id=folder:home/root',
        body: _png,
      )).statusCode,
      404,
    );
    expect(
      (await call('PUT', '/api/icon?id=folder:games', body: _png)).statusCode,
      200,
    );

    final url = (await state())['folderIcons']['games'] as String;
    final response = await call('GET', url);
    expect(response.headers['content-type'], 'image/png');
    expect(tmp.listSync(), hasLength(1));

    await call('PUT', '/api/layout', body: layout([]));
    expect(store.config.iconOverrides, isEmpty);
    expect(tmp.listSync(), isEmpty);
    expect((await state())['folderIcons'], isEmpty);
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
          'entities': [
            {
              'id': 'lamp',
              'label': 'Lamp',
              'feed': {'from': 'http', 'url': 'http://ha/x'},
            },
            {
              'id': 'motto',
              'data': {'text': 'Hi'},
            },
            {
              'id': 'broken',
              'feed': {'from': 'http', 'url': 'http://broken/x'},
            },
          ],
          'place': {'name': 'Perth', 'latitude': -31.95, 'longitude': 115.86},
        },
      );
      expect(response.statusCode, 200);
      expect(store.config.entities.map((entity) => entity.id), [
        'lamp',
        'motto',
        'broken',
      ]);
      expect(store.config.place?.name, 'Perth');
      final told = await state();
      expect(told['config']['entities'][0], {
        'id': 'lamp',
        'category': 'value',
        'label': 'Lamp',
        'feed': {'from': 'http', 'url': 'http://ha/x'},
      });
      // They are entities like the rest.
      expect([
        for (final entity in told['entities']) entity['id'],
      ], containsAll(['lamp', 'motto', 'broken']));
      expect(told['config']['place']['latitude'], -31.95);
      // The three of the user's own are offered like any other widget.
      expect([
        for (final widget in told['components']) widget['type'],
      ], containsAll(['text', 'picture', 'meter']));

      Future<(int, Object?)> value(String id) async {
        final response = await call('GET', '/api/feed?id=$id');
        final said = jsonDecode(await response.readAsString()) as Map;
        return (response.statusCode, said['value']);
      }

      final lamp = await value('lamp');
      expect(lamp.$1, 200);
      expect(lamp.$2, {'state': 'on', 'asked': 'http://ha/x'});
      // Fixed text is the entity's own data; there is nothing to fetch.
      expect((await value('motto')).$1, 404);
      expect((await value('broken')).$1, 502);
      expect((await value('nobody')).$1, 404);

      // Only what is named is touched; a place is taken away with null.
      response = await call('PUT', '/api/config', body: {'place': null});
      expect(response.statusCode, 200);
      expect(store.config.place, isNull);
      expect(store.config.entities, hasLength(3));

      // A value that cannot be kept is left out; the rest are.
      response = await call(
        'PUT',
        '/api/config',
        body: {
          'entities': [
            {'id': 'clock'},
            {'id': 'a'},
            {'id': 'a'},
          ],
        },
      );
      expect(response.statusCode, 200);
      expect(store.config.entities.map((entity) => entity.id), ['a']);
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

  test('entities left out of the layout are removed, not put back', () async {
    final page = await state();
    final layout = page['layout'] as Map<String, dynamic>;
    final section = layout['layers'][0]['root']['children'][0];
    // What the page does to remove an entity: drop its item and say so.
    (section['children'] as List).removeWhere(
      (i) => i['vars']?['source']?['value'] == 'input:tv/HW1',
    );
    layout['removed'] = ['input:tv/HW1'];
    expect((await call('PUT', '/api/layout', body: layout)).statusCode, 200);

    expect(await onTv(), ['app:a', 'app:b']);
    final after = await state();
    expect(after['layout']['removed'], ['input:tv/HW1']);
    // Still offered, so it can be added again.
    expect(
      (after['entities'] as List).map((c) => c['id']),
      contains('input:tv/HW1'),
    );

    // Adding it again, twice: an entity can be in more than one place.
    final again = after['layout'] as Map<String, dynamic>;
    (again['layers'][0]['root']['children'][0]['children'] as List).addAll([
      for (final id in ['x1', 'x2'])
        {
          'id': id,
          'prefab': 'app-card',
          'vars': {
            'source': {'value': 'input:tv/HW1', 'type': 'entity'},
          },
        },
    ]);
    await call('PUT', '/api/layout', body: again);
    expect(await onTv(), ['app:a', 'app:b', 'input:tv/HW1', 'input:tv/HW1']);
    expect(store.config.layout.removed, isEmpty);
  });

  test('custom image upload, download and reset', () async {
    var response = await call('PUT', '/api/icon?id=app:a', body: _png);
    expect(response.statusCode, 200);

    var entity = (await entities()).firstWhere((c) => c['id'] == 'app:a');
    expect(entity['customIcon'], isTrue);
    expect(entity['data']['shape'], 'banner');
    final saved = File(store.config.iconOverrides['app:a']!);
    expect(saved.parent.path, tmp.path);

    response = await call('GET', entity['data']['icon'] as String);
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
    entity = (await entities()).firstWhere((c) => c['id'] == 'app:a');
    expect(entity['customIcon'], isFalse);
  });

  test(
    'an entity can be renamed and given another entity\'s picture',
    () async {
      Future<Map<String, dynamic>> entity(String id) async =>
          (await entities()).firstWhere((c) => c['id'] == id);

      var response = await call(
        'PUT',
        '/api/entity?id=app:a',
        body: {'name': '  Films ', 'iconFrom': 'input:tv/HW1'},
      );
      expect(response.statusCode, 200);
      var a = await entity('app:a');
      expect(a['label'], 'Films');
      expect(a['renamed'], isTrue);
      expect(a['iconFrom'], 'input:tv/HW1');
      expect(a['customIcon'], isTrue);
      response = await call('GET', a['data']['icon'] as String);
      expect(response.headers['content-type'], 'image/svg+xml');

      // Leaving a key out leaves that part alone.
      await call('PUT', '/api/entity?id=app:a', body: {'name': null});
      a = await entity('app:a');
      expect(a['label'], 'A');
      expect(a['iconFrom'], 'input:tv/HW1');

      // An uploaded picture and a borrowed one replace each other.
      await call('PUT', '/api/icon?id=app:a', body: _png);
      expect(store.config.iconSources, isEmpty);
      await call('PUT', '/api/entity?id=app:b', body: {'iconFrom': 'app:a'});
      response = await call(
        'GET',
        (await entity('app:b'))['data']['icon'] as String,
      );
      expect(await response.read().expand((b) => b).toList(), _png);
      await call('PUT', '/api/entity?id=app:a', body: {'iconFrom': 'app:b'});
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
        response = await call('PUT', '/api/entity?id=app:a', body: bad);
        expect(response.statusCode, 400, reason: '$bad');
      }
      response = await call(
        'PUT',
        '/api/entity?id=app:nope',
        body: {'name': 'x'},
      );
      expect(response.statusCode, 404);
    },
  );

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

      // Past the end there is nothing to send. (Asked with no end, as
      // `bytes=999-`, shelf_static sends the whole file instead.)
      expect((await range('bytes=999-1200')).statusCode, 416);
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
          'layers': [1],
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

    await entities();
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
    // An input, two apps, the launcher's settings, and those there is one
    // of: the clock, the weather, the place, the media player, the system,
    // the layers, the variables and the layout.
    expect(state['entities'], hasLength(12));
  });
}
