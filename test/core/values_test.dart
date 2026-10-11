import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/values/values.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/features/widgets/marquee.dart';
import 'package:openlauncher/features/widgets/primitive_widgets.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

String _render(String source, Map<String, Object?> values) =>
    Template.parse(source).render((root) => values[root]);

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
      'weather': {'text': '18°', 'temperature': 17.6},
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
      expect(Template.parse('{{lounge.state}} {{weather}} {{a-b.c}}').roots, {
        'lounge',
        'weather',
        'a-b',
      });
    });

    test('a thing of several parts reads by its text', () {
      expect(_render('{{weather}}', values), '18°');
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
          '{{weather.temperature | times:1.8 | plus:32 | round}}',
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

  group('sources', () {
    test('are saved and read back, the unreadable left out', () {
      const sources = [
        DataSource(id: 'lounge', name: 'Lounge', url: 'http://ha/x', every: 30),
        DataSource(id: 'motto', kind: SourceKind.text, text: 'Hi'),
      ];
      final saved = [for (final source in sources) source.toJson()];
      expect(DataSource.listFromJson(saved), sources);
      expect(
        DataSource.listFromJson([
          ...saved,
          saved.first, // The same id again.
          {'id': 'Not An Id'},
          {'id': 'time'},
          {'name': 'No id'},
          'nonsense',
          {'id': 'fast', 'every': 1},
        ], taken: builtInRoots).map((source) => (source.id, source.every)),
        [('lounge', 30), ('motto', 60), ('fast', DataSource.minEvery)],
      );
    });

    test('only web addresses are asked', () {
      expect(
        const DataSource(id: 'a', url: 'https://x.test/y').address,
        isNotNull,
      );
      expect(
        const DataSource(id: 'a', url: 'file:///etc/passwd').address,
        isNull,
      );
      expect(const DataSource(id: 'a', url: 'x.test').address, isNull);
    });

    test('are kept in the config', () async {
      final store = MemoryConfigStore();
      final container = ProviderContainer(
        overrides: [configStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final config = container.read(configProvider.notifier);
      await config.setSources(const [
        DataSource(id: 'motto', kind: SourceKind.text, text: 'Hi'),
        DataSource(id: 'weather', url: 'http://x.test'),
      ]);
      await config.setPlace((
        name: 'Perth',
        latitude: -31.95,
        longitude: 115.86,
      ));
      final read = LauncherConfig.fromJson(store.config.toJson());
      expect(read.sources.map((source) => source.id), ['motto']);
      expect(read.place?.name, 'Perth');
      await config.setPlace(null);
      expect(store.config.place, isNull);
      expect(store.config.sources, hasLength(1));
    });
  });

  group('values', () {
    late FakeLauncherPlatform platform;
    late List<DataSource> asked;

    ProviderContainer container(LauncherConfig config) {
      platform = FakeLauncherPlatform(const [], const []);
      asked = [];
      final container = ProviderContainer(
        overrides: [
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
          sourceFetcherProvider.overrideWithValue((source) async {
            asked.add(source);
            if (source.url.contains('broken')) throw Exception('No');
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
      expect(await reads(c, '{{time}}'), '15:04');
      expect(
        await reads(c, '{{time.hour12}}:{{time.minute}} {{time.ampm}}'),
        '3:4 pm',
      );
      expect(await reads(c, '{{time | format:hh:mm:ss a}}'), '03:04:09 pm');
      expect(await reads(c, '{{date}}'), 'Sunday 11 October');
      expect(
        await reads(c, '{{date.monthName}} {{date.year}}'),
        'October 2026',
      );
    });

    test('what is playing, and nothing when nothing is', () async {
      final c = container(LauncherConfig());
      const template = '{{nowPlaying.title | default:Silence}}';
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
        await reads(c, '{{nowPlaying.artist}} on {{nowPlaying.app}}'),
        'Band on Player',
      );
    });

    test('the place and its weather, once a place is said', () async {
      var c = container(LauncherConfig());
      expect(await reads(c, '[{{location}}{{weather}}]'), '[]');
      c = container(
        LauncherConfig(
          place: (name: 'Perth', latitude: -31.95, longitude: 115.86),
        ),
      );
      expect(
        await reads(c, '{{location}} {{location.latitude}}'),
        'Perth -31.95',
      );
      expect(
        await reads(
          c,
          '{{weather}} {{weather.description}} {{weather.high|round}}',
        ),
        '18° Partly cloudy 22',
      );
    });

    test("the user's own, fixed or asked for", () async {
      final c = container(
        LauncherConfig(
          sources: const [
            DataSource(id: 'motto', kind: SourceKind.text, text: 'Hi'),
            DataSource(id: 'lounge', url: 'http://ha.test/x'),
            DataSource(id: 'broken', url: 'http://broken.test'),
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
          configStoreProvider.overrideWithValue(
            MemoryConfigStore(
              LauncherConfig(
                sources: const [
                  DataSource(id: 'motto', kind: SourceKind.text, text: 'Hi'),
                  DataSource(id: 'level', kind: SourceKind.text, text: '30'),
                ],
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Column(
            children: [
              Expanded(
                child: TextWidget(
                  options: {'text': '{{motto}} there', 'colour': '#ff0000'},
                ),
              ),
              Expanded(
                child: PictureWidget(options: {'source': '{{motto.no}}'}),
              ),
              Expanded(
                child: MeterWidget(options: {'value': '{{level}}', 'max': 60}),
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
    expect(find.byType(MeterWidget), findsOneWidget);
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
              child: TextWidget(options: {'size': 20, ...options}),
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
}
