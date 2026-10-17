import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/access/access.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/core/packs/packs.dart';
import 'package:openlauncher/core/updates/updates.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
import 'package:openlauncher/platform/launcher_platform.dart';
import 'package:openlauncher/server/auth.dart';
import 'package:openlauncher/server/auth_store.dart';
import 'package:openlauncher/server/config_api.dart';
import 'package:openlauncher/server/config_server.dart';
import 'package:openlauncher/server/media_store.dart';
import 'package:shelf/shelf.dart';

import '../support/packs.dart';
import '../support/updates.dart';

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
  late String token;
  final fetched = <Uri>[];

  setUp(() async {
    store = MemoryConfigStore(startingConfig);
    tmp = await Directory.systemTemp.createTemp('openlauncher_test');
    container = ProviderContainer(
      overrides: [
        configStoreProvider.overrideWithValue(store),
        authStoreProvider.overrideWithValue(MemoryAuthStore()),
        launcherPlatformProvider.overrideWithValue(
          FakeLauncherPlatform(
            [
              InstalledApp(packageName: 'a', label: 'A', isBanner: false),
              InstalledApp(packageName: 'b', label: 'B', isBanner: false),
            ],
            [TvInput(id: 'tv/HW1', label: 'HDMI 1', kind: TvInputKind.hdmi)],
          ),
        ),
        mediaDirProvider.overrideWith(
          (ref, use) => Directory('${tmp.path}/${use.folder}'),
        ),
        packsDirProvider.overrideWith((ref) => Directory('${tmp.path}/packs')),
        bundledPacksProvider.overrideWithValue(
          BundledPacks({
            'core': packZip('core'),
            'system': folderZip('system'),
          }),
        ),
        updateSourceProvider.overrideWithValue(
          FakeUpdateSource(release(later)),
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
    // Pair a device so the tests can reach the API, as a browser would.
    final auth = container.read(authProvider);
    auth.pairing.open();
    token = (await auth.pair(auth.pairing.value!, 'test')).token;
    addTearDown(() async {
      await closePacks(container);
      await tmp.delete(recursive: true);
    });
  });

  // localhost is one of the TV's own addresses, so the host check passes.
  Future<Response> call(String method, String path, {Object? body}) =>
      api.handle(
        Request(
          method,
          Uri.parse('http://localhost$path'),
          headers: {
            'host': 'localhost',
            'cookie': '${Authenticator.cookie}=$token',
            Authenticator.writeHeader: 'test',
            if (body is Map) 'content-type': 'application/json',
          },
          body: body is Map ? jsonEncode(body) : body,
        ),
      );

  Future<Map<String, dynamic>> state() async {
    final response = await call('GET', '/api/state');
    expect(response.statusCode, 200);
    return jsonDecode(await response.readAsString());
  }

  /// Uploads [bytes] for [use] and returns the file's id.
  Future<String> upload(Object bytes, {String use = 'picture'}) async {
    final response = await call('POST', '/api/media?as=$use', body: bytes);
    expect(response.statusCode, 200);
    return jsonDecode(await response.readAsString())['id'];
  }

  /// Every uploaded file, as the media manager is told of them.
  Future<List<Map<String, dynamic>>> media() async {
    final response = await call('GET', '/api/media');
    return (jsonDecode(await response.readAsString())['files'] as List).cast();
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
      'system:input/tv/HW1',
      'system:app/a',
      'system:app/b',
    ]);
    expect((await entities()).first, {
      'id': 'system:input/tv/HW1',
      'category': 'input',
      // What it defines: the operation each action runs, and with what.
      'actions': {
        'open': {
          'run': 'os://inputs/switch',
          'with': {'input': '{{self.input}}'},
          'label': 'Open',
          'icon': 'material:play_arrow',
        },
      },
      'prefab': 'system:app-card',
      'placed': true,
      'label': 'HDMI 1',
      'name': 'HDMI 1',
      // What there is to read of it, its picture as where to fetch it.
      'data': {
        'input': 'tv/HW1',
        'icon': isA<String>(),
        'shape': 'line',
        'number': '1',
      },
    });

    // Inputs get the System pack's line art, served to the page as SVG.
    final icon = (await entities()).first['data']['icon'] as String;
    final response = await call('GET', icon);
    expect(response.headers['content-type'], 'image/svg+xml');
    expect(
      await response.readAsString(),
      File('packs/system/images/input-hdmi.svg').readAsStringSync(),
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
      [
        'system:input/tv/HW1',
        'system:app/a',
        'system:app/b',
        'system:settings',
      ],
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
    // The quick actions are an instance of the System pack's menu.
    final menu = (page['layout']['layers'][0]['root']['children'] as List)
        .firstWhere((item) => item['id'] == 'quick-actions');
    expect(menu['prefab'], 'system:quick-actions');
    expect(page['ownLayout'], isFalse);
    // The layout is the launcher's, called by address, not an entity.
    expect(
      (page['entities'] as List).map((entity) => entity['id']),
      isNot(contains(Layout.homeId)),
    );
    expect(page['config']['toasts'], const ToastOptions().toJson());
    expect(page['access'], {'homeButton': true, 'notifications': true});
  });

  test('the layout is reverted to the System pack\'s', () async {
    List<Object?> ids(Map<String, dynamic> page) => [
      for (final item in page['layout']['layers'][0]['root']['children'])
        item['id'],
    ];
    final start = await state();
    expect(ids(start), ['main', 'quick-actions']);

    // Edited, it is the user's and saved.
    final layout = (start['layout'] as Map).cast<String, Object?>();
    (layout['layers'] as List)[0]['root']['children'].removeLast();
    expect((await call('PUT', '/api/layout', body: layout)).statusCode, 200);
    expect(ids(await state()), ['main']);
    expect((await state())['ownLayout'], isTrue);
    expect(store.config.toJson(), contains('layout'));

    // Reverted, it is read from the pack again and not saved.
    expect((await call('DELETE', '/api/layout')).statusCode, 200);
    final reverted = await state();
    expect(ids(reverted), ['main', 'quick-actions']);
    expect(reverted['ownLayout'], isFalse);
    expect(store.config.toJson(), isNot(contains('layout')));
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

    await said(await act('open', on: 'system:app/a'));
    await said(await act('open', on: 'system:input/tv/HW1'));
    expect(platform.launched, ['a', 'tv/HW1']);
    // Settings opens on a screen, and there is none here: nothing is done.
    await said(await act('open', on: 'system:settings'));
    // An improper payload is declined: an entity that is not there, or none
    // named.
    expect((await act('open', on: 'system:app/gone')).statusCode, 400);
    expect((await act('open')).statusCode, 400);
    expect((await act('open', on: '')).statusCode, 400);
    expect(platform.launched, hasLength(2));

    await said(await act('info', on: 'system:app/a'));
    await said(await act('uninstall', on: 'system:app/b'));
    expect(platform.appActions, ['info a', 'uninstall b']);
    // Only apps have these.
    expect((await act('info', on: 'system:input/tv/HW1')).statusCode, 400);

    await said(await act('playPause', on: 'system:media'));
    expect(platform.mediaCommands, [MediaCommand.playPause]);

    // What the TV's settings allow is part of the state.
    platform.access[Access.homeButton] = false;
    container.invalidate(accessProvider);
    expect((await state())['access'], {
      'homeButton': false,
      'notifications': true,
    });
    // The device's actions name it too; no owner is guessed.
    expect((await act('access')).statusCode, 400);
    expect((await act('playPause')).statusCode, 400);
    // The TV shows the screen for it; which permission has to be said.
    final change = {'access': 'homeButton'};
    expect(
      await said(await act('access', on: 'system:device', more: change)),
      isNull,
    );
    expect(platform.accessChanged, [Access.homeButton]);
    expect((await act('access', on: 'system:device')).statusCode, 502);
    platform.noAccessScreen = true;
    expect(
      await said(await act('access', on: 'system:device', more: change)),
      startsWith('This TV has no screen for it\n'),
    );
    await said(await act('tvSettings', on: 'system:device'));
    expect(platform.tvSettingsOpened, 1);

    // What is not the device's doing is done all the same: a variable set.
    await said(
      await call(
        'POST',
        '/api/act',
        body: {
          'run': 'launcher://variables/set',
          'with': {'of': 'lamp', 'var': 'on', 'value': true},
        },
      ),
    );
    expect(
      (await act('set', more: {'of': 'lamp', 'var': 'on'})).statusCode,
      400,
    );

    expect((await act('dance', on: 'system:device')).statusCode, 400);
    expect((await call('POST', '/api/act', body: {})).statusCode, 400);
  });

  test(
    'the page is told of updates, and has the TV check and install',
    () async {
      expect((await state())['update'], containsPair('available', false));
      final checked = await call(
        'POST',
        '/api/act',
        body: {'do': 'check', 'entity': 'system:updates'},
      );
      expect(
        jsonDecode(await checked.readAsString())['message'],
        startsWith('Update available'),
      );
      expect((await state())['update'], {
        'current': appVersion,
        'latest': later,
        'available': true,
        'notes': 'Fixes.',
        'status': 'idle',
        'progress': 0,
        'error': null,
      });

      await call(
        'POST',
        '/api/act',
        body: {'do': 'install', 'entity': 'system:updates'},
      );
      final platform =
          container.read(launcherPlatformProvider) as FakeLauncherPlatform;
      expect(platform.installed, ['/cache/update.apk']);
      // What is done about them is a setting like any other.
      await call(
        'PUT',
        '/api/config',
        body: {
          'updates': {'mode': 'auto'},
        },
      );
      expect(store.config.updates.mode, UpdateMode.auto);
    },
  );

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
      'art': '/api/playing/art?id=art-1.png',
    });
    final art = await call('GET', playing['art']);
    expect(art.statusCode, 200);
    expect(art.headers['content-type'], 'image/png');
    // A cover that has since been replaced is not passed off as the old one.
    expect(
      (await call('GET', '/api/playing/art?id=art-0.png')).statusCode,
      404,
    );
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
                      'prefab': 'system:app-card',
                      'vars': {
                        'source': {'value': 'system:app/b', 'type': 'entity'},
                      },
                      'transform': {'x': 2, 'y': 0, 'w': 9},
                    },
                    {
                      'id': 'i2',
                      'prefab': 'system:folder-card',
                      'vars': {
                        'source': {'value': 'games', 'type': 'entity'},
                      },
                    },
                    {
                      'id': 'i3',
                      'prefab': 'system:folder-card',
                      'vars': {
                        'source': {'value': 'nothing', 'type': 'entity'},
                      },
                    },
                    {
                      'id': 'i4',
                      'prefab': 'system:weather',
                      'vars': {
                        'source': {'value': 'system:weather', 'type': 'entity'},
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
                      'prefab': 'system:app-card',
                      'vars': {
                        'source': {'value': 'system:app/a', 'type': 'entity'},
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
    // Too wide for the pane. A card for a folder that does not exist is
    // kept, but not drawn.
    expect(top.children.map((i) => i.id), ['i1', 'i2', 'i3', 'i4']);
    expect((top.children.first.w, top.children.first.x), (4, 0));
    expect(
      (top.children.last.prefab, top.children.last.handed.firstOrNull),
      ('system:weather', 'system:weather'),
    );
    expect((games.dock, games.hovers), ('bottom', true));

    // On the TV: app:b on top, app:a inside the folder, and the input,
    // which was placed nowhere, in the pane for new entities.
    expect(await onTv(), ['system:app/b', 'system:input/tv/HW1']);
    final view = await container.read(layoutViewProvider.future);
    expect(view.all.map((item) => item.id), isNot(contains('i3')));
    final folder = view.home.root.contents.elementAt(1);
    expect(folder.prefab, folderPrefabId);
    expect(
      view
          .pane(folder.handed.firstOrNull!)!
          .contents
          .map((entry) => entry.handed.firstOrNull),
      ['system:app/a'],
    );
    final shown = (await state())['layout']['layers'][0]['root']['children'][1];
    expect(
      (shown['children'] as List).map((i) => i['vars']?['source']?['value']),
      ['system:input/tv/HW1', 'system:settings'],
    );
  });

  test(
    'a folder\'s picture goes with the folder, and its file stays',
    () async {
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
      final id = await upload(_png);
      await call(
        'PUT',
        '/api/config',
        body: {
          'iconOverrides': {'folder:games': id},
        },
      );
      expect((await state())['config']['iconOverrides'], {'folder:games': id});
      final response = await call('GET', '/api/media/$id');
      expect(response.headers['content-type'], 'image/png');

      await call('PUT', '/api/layout', body: layout([]));
      expect(store.config.iconOverrides, isEmpty);
      // Only the media manager deletes files.
      expect(await media(), [
        {'id': id, 'bytes': _png.length, 'used': false},
      ]);
    },
  );

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
    // Files are named by id, never by path.
    response = await call(
      'PUT',
      '/api/config',
      body: {
        'wallpapers': ['/etc/passwd', '../config.json'],
        'iconOverrides': {'system:app/a': '/etc/passwd'},
      },
    );
    expect(response.statusCode, 200);
    expect(store.config.wallpapers, isEmpty);
    expect(store.config.iconOverrides, isEmpty);
    expect((await call('PUT', '/api/config', body: {'v': 1})).statusCode, 400);
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
              'feed': {'url': 'http://ha/x'},
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
        'feed': {'url': 'http://ha/x'},
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
            {'id': 'self'},
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
      (i) => i['vars']?['source']?['value'] == 'system:input/tv/HW1',
    );
    layout['removed'] = ['system:input/tv/HW1'];
    expect((await call('PUT', '/api/layout', body: layout)).statusCode, 200);

    expect(await onTv(), ['system:app/a', 'system:app/b']);
    final after = await state();
    expect(after['layout']['removed'], ['system:input/tv/HW1']);
    // Still offered, so it can be added again.
    expect(
      (after['entities'] as List).map((c) => c['id']),
      contains('system:input/tv/HW1'),
    );

    // Adding it again, twice: an entity can be in more than one place.
    final again = after['layout'] as Map<String, dynamic>;
    (again['layers'][0]['root']['children'][0]['children'] as List).addAll([
      for (final id in ['x1', 'x2'])
        {
          'id': id,
          'prefab': 'system:app-card',
          'vars': {
            'source': {'value': 'system:input/tv/HW1', 'type': 'entity'},
          },
        },
    ]);
    await call('PUT', '/api/layout', body: again);
    expect(await onTv(), [
      'system:app/a',
      'system:app/b',
      'system:input/tv/HW1',
      'system:input/tv/HW1',
    ]);
    expect(store.config.layout.removed, isEmpty);
  });

  test('an uploaded picture is used once the config points at it', () async {
    final id = await upload(_png);
    expect(store.config.iconOverrides, isEmpty);
    expect((await media()).single['used'], isFalse);

    var response = await call(
      'PUT',
      '/api/config',
      body: {
        'iconOverrides': {'system:app/a': id},
      },
    );
    expect(response.statusCode, 200);
    final entity = (await entities()).firstWhere(
      (c) => c['id'] == 'system:app/a',
    );
    expect(entity['data']['shape'], 'banner');
    final saved = File(store.config.iconOverrides['system:app/a']!);
    expect(saved.parent.path, '${tmp.path}/custom-icons');
    response = await call('GET', entity['data']['icon'] as String);
    expect(response.headers['content-type'], 'image/png');
    expect(await response.read().expand((b) => b).toList(), _png);
    expect((await state())['config']['iconOverrides'], {'system:app/a': id});
    expect((await media()).single['used'], isTrue);

    // A file in use is not deleted.
    expect((await call('DELETE', '/api/media?id=$id')).statusCode, 409);

    // A second picture leaves the first on the TV, unused.
    final second = await upload(_png);
    await call(
      'PUT',
      '/api/config',
      body: {
        'iconOverrides': {'system:app/a': second},
      },
    );
    expect(saved.existsSync(), isTrue);
    expect(
      {for (final file in await media()) file['id']: file['used']},
      {id: false, second: true},
    );

    // Deleting the unused takes only those.
    response = await call('DELETE', '/api/media');
    expect(jsonDecode(await response.readAsString()), {'deleted': 1});
    expect((await media()).single['id'], second);
    expect((await call('DELETE', '/api/media?id=$id')).statusCode, 404);

    // An id with no file points at nothing.
    await call(
      'PUT',
      '/api/config',
      body: {
        'iconOverrides': {'system:app/a': id},
      },
    );
    expect(store.config.iconOverrides, isEmpty);
  });

  test('an entity is renamed and given another entity\'s picture', () async {
    Future<Map<String, dynamic>> entity(String id) async =>
        (await entities()).firstWhere((c) => c['id'] == id);

    var response = await call(
      'PUT',
      '/api/config',
      body: {
        'names': {'system:app/a': 'Films'},
        'iconSources': {'system:app/a': 'system:input/tv/HW1'},
      },
    );
    expect(response.statusCode, 200);
    var a = await entity('system:app/a');
    expect(a['label'], 'Films');
    response = await call('GET', a['data']['icon'] as String);
    expect(response.headers['content-type'], 'image/svg+xml');
    final config = (await state())['config'];
    expect(config['names'], {'system:app/a': 'Films'});
    expect(config['iconSources'], {'system:app/a': 'system:input/tv/HW1'});

    // A key left out is left alone.
    await call('PUT', '/api/config', body: {'names': {}});
    a = await entity('system:app/a');
    expect(a['label'], 'A');
    expect(store.config.iconSources, {'system:app/a': 'system:input/tv/HW1'});

    response = await call(
      'PUT',
      '/api/config',
      body: {
        'names': {'system:app/a': 'x' * 61},
      },
    );
    expect(response.statusCode, 400);
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

    Future<List<String>> wallpapers() async =>
        ((await state())['config']['wallpapers'] as List).cast();

    test(
      'an uploaded video is the wallpaper once the config lists it',
      () async {
        expect(await wallpapers(), isEmpty);

        final id = await upload(mp4, use: 'wallpaper');
        expect(id, endsWith('.mp4'));
        expect(store.config.wallpaper, isNull);
        var response = await call(
          'PUT',
          '/api/config',
          body: {
            'wallpapers': [id],
          },
        );
        expect(response.statusCode, 200);
        expect(await wallpapers(), [id]);
        final saved = File(store.config.wallpaper!);
        expect(saved.readAsBytesSync(), mp4);
        expect(
          container.read(wallpaperProvider),
          Wallpaper(saved.path, WallpaperKind.video),
        );

        response = await call('GET', '/api/media/$id');
        expect(response.statusCode, 200);
        expect(response.headers['content-type'], 'video/mp4');
        expect(response.headers['content-length'], '${mp4.length}');

        // Off the list, its file stays until it is deleted as media.
        await call('PUT', '/api/config', body: {'wallpapers': []});
        expect(store.config.wallpaper, isNull);
        expect(saved.existsSync(), isTrue);
        expect((await call('DELETE', '/api/media?id=$id')).statusCode, 200);
        expect(saved.existsSync(), isFalse);
      },
    );

    test('several wallpapers are kept in the order given, and timed', () async {
      final video = await upload(mp4, use: 'wallpaper');
      final picture = await upload(_png, use: 'wallpaper');
      await call(
        'PUT',
        '/api/config',
        body: {
          'wallpapers': [video, picture],
          'wallpaperEvery': 15,
        },
      );
      // The first is the one shown.
      expect(container.read(wallpaperProvider)?.kind, WallpaperKind.video);
      expect(store.config.wallpaperEvery, 15);
      expect((await state())['config']['wallpaperEvery'], 15);

      await call(
        'PUT',
        '/api/config',
        body: {
          'wallpapers': [picture, video, 'nothing.png'],
        },
      );
      expect(await wallpapers(), [picture, video]);
      expect(store.config.wallpaperEvery, 15);

      await call(
        'PUT',
        '/api/config',
        body: {'wallpapers': List.filled(20, picture)},
      );
      expect(store.config.wallpapers, hasLength(LauncherConfig.maxWallpapers));
    });

    test('serves byte ranges for video playback', () async {
      final id = await upload(mp4, use: 'wallpaper');
      Future<Response> range(String value) => api.handle(
        Request(
          'GET',
          Uri.parse('http://localhost/api/media/$id'),
          headers: {
            'host': 'localhost',
            'range': value,
            'cookie': '${Authenticator.cookie}=$token',
          },
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
      var response = await call(
        'POST',
        '/api/media?as=wallpaper',
        body: utf8.encode('just some text'),
      );
      expect(response.statusCode, 415);
      // A video is not a picture.
      response = await call('POST', '/api/media?as=picture', body: mp4);
      expect(response.statusCode, 415);
      expect((await call('POST', '/api/media', body: _png)).statusCode, 400);
      expect(await media(), isEmpty);
      expect(Directory('${tmp.path}/wallpaper').listSync(), isEmpty);
      expect((await call('GET', '/api/media/nothing.png')).statusCode, 404);
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
    expect(await status('GET', '/api/icon?id=app:zzz'), 404);
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
      await status('POST', '/api/media?as=picture', body: utf8.encode('hello')),
      415,
    );
  });

  test('packs are listed, served, installed and removed', () async {
    Future<List<Object?>> packs() async => [
      for (final Map pack in (await state())['packs']) pack['id'],
    ];
    expect(await packs(), ['core', 'system']);
    expect((await state())['packs'].first, {
      'id': 'core',
      'name': 'Pack core',
      'version': '1',
      'author': '',
      'licence': '',
      'source': '',
      'requires': <Object?>[],
      'categories': <String, Object?>{},
      'builtIn': true,
      'bytes': isPositive,
      'files': ['fonts/core.ttf', 'icons/core.json'],
    });

    // A pack's files are read by the editor from the TV.
    var response = await call('GET', '/api/packs/core/icons/core.json');
    expect(response.statusCode, 200);
    expect(response.headers['cache-control'], 'no-cache');
    expect(jsonDecode(await response.readAsString())['font'], 'core.ttf');
    response = await call('GET', '/api/packs/core/fonts/core.ttf');
    expect(await response.read().expand((chunk) => chunk).toList(), fontBytes);
    for (final path in [
      '/api/packs/core/icons/none.json',
      '/api/packs/none/pack.json',
      '/api/packs/core',
      '/api/packs/core/%2e%2e/%2e%2e/config.json',
    ]) {
      expect((await call('GET', path)).statusCode, 404, reason: path);
    }

    response = await call('POST', '/api/packs', body: packZip('mdi'));
    expect(response.statusCode, 200);
    expect(jsonDecode(await response.readAsString()), {'id': 'mdi'});
    // By name: a built-in pack is listed like any other.
    expect(await packs(), ['core', 'mdi', 'system']);

    response = await call('POST', '/api/packs', body: [1, 2, 3]);
    expect(response.statusCode, 415);
    expect(jsonDecode(await response.readAsString()), {
      'error': 'Not a zip file',
    });

    expect((await call('DELETE', '/api/packs')).statusCode, 400);
    expect((await call('DELETE', '/api/packs?id=none')).statusCode, 404);
    expect((await call('DELETE', '/api/packs?id=core')).statusCode, 409);
    expect((await call('DELETE', '/api/packs?id=system')).statusCode, 409);
    expect((await call('DELETE', '/api/packs?id=mdi')).statusCode, 200);
    expect(await packs(), ['core', 'system']);
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
    request.headers.set('cookie', '${Authenticator.cookie}=$token');
    final response = await request.close();
    expect(response.statusCode, 200);
    final state = jsonDecode(await response.transform(utf8.decoder).join());
    // An input, two apps, the launcher's settings, and those there is one
    // of: the clock, the weather, the place, the media player, the device
    // and updates.
    expect(state['entities'], hasLength(10));
  });

  test('a forwarded host does not pass the host check', () async {
    final server = (await container.read(configServerProvider.future))!;
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.get('127.0.0.1', server.port, '/api/state');
    request.headers
      ..host = 'attacker.example'
      ..set('x-forwarded-host', 'localhost')
      ..set('cookie', '${Authenticator.cookie}=$token');
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, 403);
  });

  group('pairing', () {
    final session = '${Authenticator.cookie}=';

    // A request without the shared [call]'s session or host.
    Future<Response> raw(
      String method,
      String path, {
      String host = 'localhost',
      Map<String, String> headers = const {},
      Object? body,
    }) => api.handle(
      Request(
        method,
        Uri.parse('http://$host$path'),
        headers: {'host': host, ...headers},
        body: body,
      ),
    );

    Future<Response> pair(String code) => raw(
      'POST',
      '/api/pair',
      headers: {
        Authenticator.writeHeader: 'test',
        'content-type': 'application/json',
      },
      body: jsonEncode({'code': code, 'label': 'phone'}),
    );

    test(
      'the API refuses a request with no session, and clears a bad one',
      () async {
        expect((await raw('GET', '/api/state')).statusCode, 401);
        final bad = await raw(
          'GET',
          '/api/state',
          headers: {'cookie': '${session}not-a-real-token'},
        );
        expect(bad.statusCode, 401);
        expect(bad.headers['set-cookie'], contains('Max-Age=0'));
      },
    );

    test('the API refuses a request to another host', () async {
      final response = await raw(
        'GET',
        '/api/state',
        host: 'attacker.example',
        headers: {'cookie': '$session$token'},
      );
      expect(response.statusCode, 403);
    });

    test('a token in the query is not accepted', () async {
      final response = await raw(
        'GET',
        '/api/state?t=${Uri.encodeQueryComponent(token)}',
      );
      expect(response.statusCode, 401);
    });

    test('the editor page itself loads without a session', () async {
      // Not served in tests (no bundle), but the guard must let it through
      // rather than answer 401/403.
      final status = (await raw('GET', '/')).statusCode;
      expect(status, isNot(401));
      expect(status, isNot(403));
    });

    test('a write without the editor header is refused', () async {
      final response = await raw(
        'PUT',
        '/api/config',
        headers: {
          'cookie': '$session$token',
          'content-type': 'application/json',
        },
        body: jsonEncode({'names': <String, String>{}}),
      );
      expect(response.statusCode, 403);
    });

    test('a write from another origin is refused', () async {
      final response = await raw(
        'PUT',
        '/api/config',
        headers: {
          'cookie': '$session$token',
          Authenticator.writeHeader: 'test',
          'origin': 'http://attacker.example',
          'content-type': 'application/json',
        },
        body: jsonEncode({'names': <String, String>{}}),
      );
      expect(response.statusCode, 403);
    });

    test('a write from the TV\'s own page is let through', () async {
      final response = await raw(
        'PUT',
        '/api/config',
        headers: {
          'cookie': '$session$token',
          Authenticator.writeHeader: 'test',
          'origin': 'http://localhost',
          'content-type': 'application/json',
        },
        body: jsonEncode({'names': <String, String>{}}),
      );
      expect(response.statusCode, 200);
    });

    test('a large pairing request is refused unread', () async {
      final response = await raw(
        'POST',
        '/api/pair',
        headers: {Authenticator.writeHeader: 'test'},
        body: Stream.value(List.filled(64 * 1024, 32)),
      );
      expect(response.statusCode, 413);
    });

    test('a long name is refused without using up the code', () async {
      final code = container.read(authProvider).pairing.value!;
      final long = await raw(
        'POST',
        '/api/pair',
        headers: {Authenticator.writeHeader: 'test'},
        body: jsonEncode({'code': code, 'label': 'x' * 61}),
      );
      expect(long.statusCode, 400);
      expect((await pair(code)).statusCode, 200);
    });

    test('the wrong code is refused', () async {
      expect((await pair('nope')).statusCode, 403);
    });

    test('pairing is refused while the TV is not showing a code', () async {
      final pairing = container.read(authProvider).pairing;
      final code = pairing.value!;
      pairing.close();
      final response = await pair(code);
      expect(response.statusCode, 403);
      expect(await response.readAsString(), contains('closed'));
    });

    test('too many wrong codes lock pairing, even for the right one', () async {
      final pairing = container.read(authProvider).pairing;
      for (var i = 0; i < 5; i++) {
        expect((await pair('nope')).statusCode, 403);
      }
      final locked = await pair(pairing.value!);
      expect(locked.statusCode, 429);
      expect(int.parse(locked.headers['retry-after']!), greaterThan(0));
    });

    test('the right code sets a usable session cookie', () async {
      final paired = await pair(container.read(authProvider).pairing.value!);
      expect(paired.statusCode, 200);
      final cookie = paired.headers['set-cookie']!;
      expect(cookie, contains('HttpOnly'));
      expect(cookie, contains('SameSite=Strict'));
      // The token is in the cookie only, out of reach of the page's scripts.
      expect(await paired.readAsString(), isNot(contains('token')));
      final used = await raw(
        'GET',
        '/api/state',
        headers: {'cookie': cookie.split(';').first},
      );
      expect(used.statusCode, 200);
    });

    test('a device can be listed and revoked', () async {
      final listed =
          jsonDecode(
                await (await call('GET', '/api/devices')).readAsString(),
              )['devices']
              as List;
      expect(listed, hasLength(1));
      expect(listed.first['label'], 'test');

      await call('DELETE', '/api/devices?id=${listed.first['id']}');
      // The session that was revoked no longer works.
      expect((await call('GET', '/api/state')).statusCode, 401);
    });

    test('revoking a device ends its open event stream', () async {
      final events = await call('GET', '/api/events');
      expect(events.statusCode, 200);
      var ended = false;
      final reading = events.read().listen(null, onDone: () => ended = true);
      addTearDown(reading.cancel);
      await pumpEventQueue();
      expect(ended, isFalse);

      final id = (await container.read(authProvider).devices()).first['id'];
      await container.read(authProvider).revoke(id! as String);
      await pumpEventQueue();
      expect(ended, isTrue);
    });
  });
}
