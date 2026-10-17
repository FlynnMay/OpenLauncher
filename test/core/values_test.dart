import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/components/components.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/entities/entities.dart';
import 'package:openlauncher/core/operations/operations.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/features/components/marquee.dart';
import 'package:openlauncher/features/components/primitives.dart';
import 'package:openlauncher/features/home/styled_box.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

import '../support/packs.dart';

String _render(String source, Map<String, Object?> values) =>
    Template.parse(source).render((root) => values[root]);

Entity _fixed(String id, String text, {String? name}) => Entity(
  id: id,
  category: userCategory,
  label: name ?? id,
  data: {'text': text},
);

Entity _asked(String id, String url, {int every = 60, String? name}) => Entity(
  id: id,
  category: userCategory,
  label: name ?? id,
  feed: Feed.inline({'url': url, 'every': every}),
);

void main() {
  group('templates', () {
    const values = <String, Object?>{
      'lounge': {
        'state': '21.46',
        'attributes': {
          'friendly_name': 'Lounge',
          'readings': [3, 4.0, 5.5],
        },
      },
      'system:weather': {'text': '18°', 'temperature': 17.6},
      'updated': 1760140800,
    };

    test('plain text stands as it is', () {
      expect(_render('Hello', values), 'Hello');
      expect(Template.parse('Hello').roots, isEmpty);
    });

    test('a path reaches into a value', () {
      expect(_render('{{lounge.state}}°', values), '21.46°');
      expect(
        _render('{{ lounge.attributes.friendly_name }}', values),
        'Lounge',
      );
      expect(_render('{{lounge.attributes.readings[1]}}', values), '4');
      expect(_render('{{lounge.attributes.readings.2}}', values), '5.5');
      expect(
        Template.parse('{{lounge.state}} {{system:weather}} {{a-b.c}}').roots,
        {'lounge', 'system:weather', 'a-b'},
      );
    });

    test('a thing of several parts reads by its text', () {
      expect(_render('{{system:weather}}', values), '18°');
      expect(_render('{{lounge}}', values), '');
    });

    test('what there is none of reads as nothing', () {
      expect(_render('[{{nothing.at.all}}]', values), '[]');
      expect(_render('[{{lounge.attributes.readings[9]}}]', values), '[]');
      expect(_render('{{nothing | default:Idle}}', values), 'Idle');
      expect(_render('{{nothing | default:"a b"}}', values), 'a b');
    });

    test('pipes change how a value reads', () {
      expect(_render('{{lounge.state | round}}', values), '21');
      expect(_render('{{lounge.state | round:1}}', values), '21.5');
      expect(
        _render(
          '{{system:weather.temperature | times:1.8 | plus:32 | round}}',
          values,
        ),
        '64',
      );
      expect(
        _render('{{lounge.attributes.friendly_name|upper}}', values),
        'LOUNGE',
      );
      expect(
        _render('{{lounge.attributes.friendly_name|lower}}', values),
        'lounge',
      );
      // Not for this kind of value, or unknown: as it was.
      expect(
        _render('{{lounge.attributes.friendly_name|round}}', values),
        'Lounge',
      );
      expect(_render('{{lounge.state|sparkle}}', values), '21.46');
    });

    test('a time is written to a pattern', () {
      final time = DateTime(2026, 10, 11, 15, 4, 9);
      expect(formatDateTime(time, 'HH:mm:ss'), '15:04:09');
      expect(formatDateTime(time, 'h:mm a'), '3:04 pm');
      expect(
        formatDateTime(time, "EEE d MMM yyyy 'at' H"),
        'Sun 11 Oct 2026 at 15',
      );
      expect(
        _render('{{t | format:h:mm a}}', {
          't': {'epoch': time.millisecondsSinceEpoch},
        }),
        '3:04 pm',
      );
      expect(
        _render('{{t | format:yyyy}}', {'t': '2031-02-03T04:05:06'}),
        '2031',
      );
    });

    test('every single thing in a value has a path', () {
      expect(valuePaths('lounge', values['lounge']), {
        'lounge.state': '21.46',
        'lounge.attributes.friendly_name': 'Lounge',
        'lounge.attributes.readings[0]': 3,
        'lounge.attributes.readings[1]': 4.0,
        'lounge.attributes.readings[2]': 5.5,
      });
      for (final path in valuePaths('lounge', values['lounge']).keys) {
        expect(_render('{{$path}}', values), isNotEmpty);
      }
    });
  });

  group("the user's entities", () {
    test('are saved and read back, the unreadable left out', () {
      final entities = [
        _asked('lounge', 'http://ha/x', every: 30, name: 'Lounge'),
        _fixed('motto', 'Hi'),
      ];
      final saved = [for (final entity in entities) entity.toJson()];
      expect(userEntitiesFromJson(saved), entities);
      expect(
        userEntitiesFromJson([
          ...saved,
          saved.first, // The same id again.
          {'id': 'Not An Id'},
          {'id': 'self'},
          {'name': 'No id'},
          'nonsense',
          {
            'id': 'fast',
            'feed': {'url': 'http://x.test', 'every': 1},
          },
        ]).map((entity) => (entity.id, entity.feed?.source?.every)),
        [('lounge', 30), ('motto', null), ('fast', HttpFeed.minEvery)],
      );
    });

    test('only web addresses are asked', () {
      expect(_asked('a', 'https://x.test/y').feed?.source, isNotNull);
      expect(_asked('a', 'file:///etc/passwd').feed?.source, isNull);
      expect(_asked('a', 'x.test').feed?.source, isNull);
      expect(_fixed('a', 'https://x.test/y').feed, isNull);
    });

    test('are kept in the config', () async {
      final store = MemoryConfigStore();
      final container = ProviderContainer(
        overrides: [
          ...packOverrides,
          configStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      final config = container.read(configProvider.notifier);
      final layout = jsonEncode(
        (await container.read(configProvider.future)).layout,
      );
      await config.patch({
        'entities': [
          {
            'id': 'motto',
            'data': {'text': 'Hi'},
          },
          // Not a name of its own: one templates read.
          {
            'id': 'self',
            'feed': {'url': 'http://x.test'},
          },
        ],
        'place': {'name': 'Perth', 'latitude': -31.95, 'longitude': 115.86},
        // Not set this way: left alone.
        'layout': {'layers': []},
      });
      expect(jsonEncode(store.config.layout), layout);
      final read = LauncherConfig.fromJson(store.config.toJson());
      expect(read.entities.map((entity) => entity.id), ['motto']);
      expect(read.place?.name, 'Perth');
      await config.patch({'place': null});
      expect(store.config.place, isNull);
      expect(store.config.entities, hasLength(1));
    });

    test('the form keeps what it does not show, and makes actions', () {
      final operations = [
        Operation(
          name: 'os://apps/launch',
          label: 'Open an app',
          args: const {'package': []},
          run: (run) async => null,
        ),
        Operation(
          name: 'os://media/command',
          label: 'Tell the media player',
          args: const {
            'command': ['next', 'previous'],
          },
          run: (run) async => null,
        ),
      ];
      const made = Entity(
        id: 'plex',
        category: 'shortcut',
        label: 'Plex',
        data: {'text': 'Plex', 'colour': 'orange'},
        prefab: 'system:app-card',
        actions: {
          'open': EntityAction(
            run: 'os://apps/launch',
            bound: {'package': 'com.plexapp'},
            label: 'Open',
            icon: 'play',
          ),
          'tell': EntityAction(
            run: 'os://media/command',
            args: {
              'command': ['next', 'previous'],
            },
          ),
        },
      );
      final form = userEntityToForm(made);
      expect(userEntityFromForm(form, operations, was: made), made);
      // Binding an argument takes it from what an act may say.
      final bound = userEntityFromForm(
        {
          ...form,
          'kind': 'http',
          'url': 'http://x.test',
          'actions': [
            {
              'name': 'skip',
              'run': 'os://media/command',
              'with:command': 'next',
            },
            {'name': 'skip', 'run': 'os://apps/launch'},
            {'name': '', 'run': 'os://apps/launch'},
          ],
        },
        operations,
        was: made,
      );
      expect(bound.actions, const {
        'skip': EntityAction(
          run: 'os://media/command',
          bound: {'command': 'next'},
        ),
      });
      expect(bound.feed?.source?.every, 60);
      expect(bound.data, {'colour': 'orange'});
    });
  });

  group('values', () {
    late FakeLauncherPlatform platform;
    late List<HttpFeed> asked;

    ProviderContainer container(LauncherConfig config) {
      platform = FakeLauncherPlatform(const [], const []);
      asked = [];
      final container = ProviderContainer(
        overrides: [
          ...packOverrides,
          configStoreProvider.overrideWithValue(MemoryConfigStore(config)),
          launcherPlatformProvider.overrideWithValue(platform),
          nowProvider.overrideWithValue(() => DateTime(2026, 10, 11, 15, 4, 9)),
          jsonFetcherProvider.overrideWithValue(
            (uri) async => {
              'current': {'temperature_2m': 17.6, 'weather_code': 2},
              'daily': {
                'temperature_2m_max': [22.0],
                'temperature_2m_min': [9.0],
              },
            },
          ),
          feedFetcherProvider.overrideWithValue((feed) async {
            asked.add(feed);
            if ('${feed.address}'.contains('broken')) throw Exception('No');
            return {
              'state': '21.46',
              'list': [1, 2],
            };
          }),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    /// How [template] reads once what it is made of has arrived.
    Future<String> reads(ProviderContainer container, String template) async {
      final provider = templateProvider(template);
      final held = container.listen(provider, (_, _) {});
      addTearDown(held.close);
      await container.read(configProvider.future);
      await pumpEventQueue();
      return container.read(provider);
    }

    test('the launcher has the time and the date', () async {
      final c = container(LauncherConfig());
      expect(await reads(c, '{{system:clock.time}}'), '15:04');
      expect(
        await reads(
          c,
          '{{system:clock.hour12}}:{{system:clock.minute}} {{system:clock.ampm}}',
        ),
        '3:4 pm',
      );
      expect(
        await reads(c, '{{system:clock | format:hh:mm:ss a}}'),
        '03:04:09 pm',
      );
      expect(await reads(c, '{{system:clock.date}}'), 'Sunday 11 October');
      expect(
        await reads(c, '{{system:clock.monthName}} {{system:clock.year}}'),
        'October 2026',
      );
    });

    test('what is playing, and nothing when nothing is', () async {
      final c = container(LauncherConfig());
      const template = '{{system:media.title | default:Silence}}';
      expect(await reads(c, template), 'Silence');
      platform.playing = NowPlaying(
        packageName: 'p',
        appLabel: 'Player',
        title: 'Song',
        artist: 'Band',
        playing: true,
      );
      platform.notifyNowPlayingChanged();
      expect(await reads(c, template), 'Song');
      expect(
        await reads(c, '{{system:media.artist}} on {{system:media.app}}'),
        'Band on Player',
      );
    });

    test('the place and its weather, once a place is said', () async {
      var c = container(LauncherConfig());
      expect(await reads(c, '[{{system:location}}{{system:weather}}]'), '[]');
      c = container(
        LauncherConfig(
          place: (name: 'Perth', latitude: -31.95, longitude: 115.86),
        ),
      );
      expect(
        await reads(c, '{{system:location}} {{system:location.latitude}}'),
        'Perth -31.95',
      );
      expect(
        await reads(
          c,
          '{{system:weather}} {{system:weather.description}} {{system:weather.high|round}}',
        ),
        '18° Partly cloudy 22',
      );
    });

    test("the user's own, fixed or asked for", () async {
      final c = container(
        LauncherConfig(
          entities: [
            _fixed('motto', 'Hi'),
            _asked('lounge', 'http://ha.test/x'),
            _asked('broken', 'http://broken.test'),
          ],
        ),
      );
      expect(await reads(c, '{{motto}} there'), 'Hi there');
      expect(asked, isEmpty);
      expect(
        await reads(c, '{{lounge.state | round:1}}° {{lounge.list[1]}}'),
        '21.5° 2',
      );
      expect(asked.map((source) => source.id), ['lounge']);
      expect(await reads(c, '{{broken.state | default:?}}'), '?');
      // Asked once, not over and over.
      expect(asked.map((source) => source.id), ['lounge', 'broken']);
      expect(await reads(c, '{{unheard.of}}'), '');
    });
  });

  testWidgets('the text, picture and meter widgets show values', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...packOverrides,
          launcherPlatformProvider.overrideWithValue(
            FakeLauncherPlatform(const [], const []),
          ),
          configStoreProvider.overrideWithValue(
            MemoryConfigStore(
              LauncherConfig(
                entities: [_fixed('motto', 'Hi'), _fixed('level', '30')],
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Column(
            children: [
              Expanded(
                child: TextComponent(
                  options: {
                    'text': '{{motto}} there',
                    'style': {'color': '#ff0000'},
                  },
                ),
              ),
              Expanded(
                child: PictureComponent(options: {'source': '{{motto.no}}'}),
              ),
              Expanded(
                child: MeterComponent(
                  options: {'value': '{{level}}', 'max': 60},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final text = tester.widget<Text>(find.text('Hi there'));
    expect(text.style?.color, const Color(0xFFFF0000));
    // No picture to show: the mark of an empty one.
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byType(MeterComponent), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text too long is cut short, wrapped or moved along', (
    tester,
  ) async {
    const long = 'A very long line of text that will not fit in the box';
    Future<void> show(Map<String, Object?> options) => tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Center(
            child: SizedBox(
              width: 200,
              height: 60,
              child: TextComponent(
                options: {
                  'style': {'fontSize': 20},
                  ...options,
                },
              ),
            ),
          ),
        ),
      ),
    );
    Text text() => tester.widget<Text>(find.text(long).first);

    await show({'text': long});
    expect(text().overflow, TextOverflow.fade);
    expect(text().maxLines, 1);

    await show({'text': long, 'overflow': 'ellipsis'});
    expect(text().overflow, TextOverflow.ellipsis);

    // 60 high takes two lines of 20 at 1.15, not three.
    await show({'text': long, 'overflow': 'wrap'});
    expect(text().maxLines, 2);

    await show({'text': long, 'overflow': 'scroll'});
    await tester.pump();
    // Twice, so that its start follows its end round.
    expect(find.text(long), findsNWidgets(2));
    final before = tester.getTopLeft(find.text(long).first).dx;
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getTopLeft(find.text(long).first).dx, before - 40);

    // What fits stays still, and is there once.
    await show({'text': 'Short', 'overflow': 'scroll'});
    await tester.pump();
    expect(find.byType(Marquee), findsOneWidget);
    expect(find.text('Short'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('text takes after the looks around it, but for its own', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...packOverrides,
          configStoreProvider.overrideWithValue(MemoryConfigStore()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => StyleScope.under(
              context,
              // The padding is the box's own, and goes no further.
              const {'color': '#ffd700', 'fontSize': 20, 'padding': 40},
              const Column(
                children: [
                  Expanded(child: TextComponent(options: {'text': 'Plain'})),
                  Expanded(
                    child: TextComponent(
                      options: {
                        'text': 'Own',
                        'style': {'color': '#ff0000', 'fontWeight': 'bold'},
                      },
                    ),
                  ),
                  // A value of a look can be read off anything, like any other.
                  Expanded(
                    child: TemplateScope(
                      values: {'tint': '#00ff00', 'big': 30},
                      child: TextComponent(
                        options: {
                          'text': 'Read',
                          'style': {'color': '{{tint}}', 'fontSize': '{{big}}'},
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    TextStyle of(String text) => tester.widget<Text>(find.text(text)).style!;
    expect(
      (of('Plain').color, of('Plain').fontSize),
      (const Color(0xFFFFD700), 20),
    );
    expect(
      (of('Own').color, of('Own').fontSize, of('Own').fontWeight),
      (const Color(0xFFFF0000), 20, FontWeight.w600),
    );
    expect(
      (of('Read').color, of('Read').fontSize),
      (const Color(0xFF00FF00), 30),
    );
    expect(StyleScope.of(tester.element(find.text('Plain'))), {
      'color': '#ffd700',
      'fontSize': 20,
    });
  });
}
