import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';

void main() {
  test('the release named in the code is the one in pubspec.yaml', () {
    final version = RegExp(
      r'^version:\s*(\S+)$',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
    expect(appVersion, version);
    // Plain X.Y.Z: the Android version code is worked out from it.
    expect(appVersion, matches(RegExp(r'^\d+\.\d{1,2}\.\d{1,2}$')));
  });

  test('a config is saved with its format and the release that wrote it', () {
    final written = LauncherConfig().toJson();
    expect((written['v'], written['app']), (saveVersion, appVersion));
    expect(LauncherConfig.fromJson(written).toJson(), written);
  });

  group('a save from a newer release', () {
    final newer = {
      'v': saveVersion + 1,
      'app': '9.0.0',
      'wallpapers': ['/w.png'],
      'layout': {'v': saveVersion + 1, 'layers': <Object?>[]},
    };

    test('is not read, and says which release wrote it', () {
      expect(isNewer(newer), isTrue);
      expect(
        () => migrate(newer),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('9.0.0'), contains(appVersion)),
          ),
        ),
      );
      // Not read in part either.
      expect(() => LauncherConfig.fromJson(newer), throwsFormatException);
      expect(
        () => migrate({'v': saveVersion + 1}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('newer'),
          ),
        ),
      );
    });

    test('nor is its layout sent on its own', () {
      expect(
        () => Layout.fromJson({'v': saveVersion + 1, 'layers': <Object?>[]}),
        throwsFormatException,
      );
    });
  });

  group('a step', () {
    final steps = [
      Migration(
        from: saveVersion,
        to: saveVersion + 1,
        since: '0.2.0',
        what: 'Wallpapers are called backdrops.',
        rules: [
          (save, device) => save['backdrops'] = save.remove('wallpapers'),
        ],
      ),
      Migration(
        from: saveVersion + 1,
        to: saveVersion + 2,
        since: '0.3.0',
        what: 'A layout names who made it.',
        rules: [(save, device) => (save['layout']! as Map)['by'] = 'me'],
      ),
    ];
    final old = {
      'v': saveVersion,
      'wallpapers': ['/w.png'],
      'layout': {'v': saveVersion, 'layers': <Object?>[]},
    };

    test('is run on an older save, in order, and the save restamped', () {
      final next = migrate(old, steps: steps);
      expect(next, {
        'v': saveVersion + 2,
        'backdrops': ['/w.png'],
        'layout': {'v': saveVersion + 2, 'layers': <Object?>[], 'by': 'me'},
      });
      // The save handed in is left as it was.
      expect(old['wallpapers'], ['/w.png']);
    });

    test('is not run on a save already past it', () {
      final later = {...old, 'v': saveVersion + 1, 'layout': null};
      expect(pending(later, steps: steps).map((step) => step.since), ['0.3.0']);
    });

    test('a current save is returned as it is', () {
      expect(migrate(old), same(old));
    });

    test('ends at the current format, each starting where the last ended', () {
      expect(migrations.first.from, 1);
      expect(migrations.last.to, saveVersion);
      for (final (index, step) in migrations.indexed.skip(1)) {
        expect(step.from, migrations[index - 1].to);
      }
    });
  });

  test('1 to 2: force stop and automatic setup are taken out', () {
    Map<String, Object?> button(String id, List<Map<String, Object?>> acts) => {
      'id': id,
      'kind': 'button',
      'on': {'press': acts},
    };
    const source = '{{source.id}}';
    final save = {
      'v': 1,
      'entities': [
        {
          'id': 'mine',
          'actions': {
            'forceStop': {'run': 'launchApp'},
            'kill': {'run': 'forceStopApp'},
          },
        },
      ],
      'layout': {
        'v': 1,
        'layers': [
          {
            'id': 'home',
            'root': {
              'id': 'root',
              'kind': 'pane',
              'children': [
                button('open', [
                  {'do': 'open', 'entity': source},
                ]),
                button('stop', [
                  {'do': 'forceStop', 'entity': source},
                ]),
                button('both', [
                  {'do': 'forceStop', 'entity': 'app:a'},
                  {'do': 'open', 'entity': 'app:a'},
                ]),
                button('setup', [
                  {'do': 'setup', 'entity': 'system'},
                ]),
                button('home', [
                  {'do': 'homeButton', 'entity': 'system', 'enabled': true},
                ]),
                // The user's own action of that name is left alone; one
                // that ran what is gone goes.
                button('own', [
                  {'do': 'forceStop', 'entity': 'mine'},
                ]),
                button('kill', [
                  {'do': 'kill', 'entity': 'mine'},
                ]),
                // Not a button: it stays, doing nothing on a press.
                {
                  'id': 'card',
                  'prefab': 'app-card',
                  'on': {
                    'press': [
                      {'do': 'forceStop', 'entity': source},
                    ],
                  },
                },
              ],
            },
          },
        ],
      },
      'prefabs': [
        {
          'id': 'p',
          'name': 'P',
          'root': {
            'id': 'p',
            'kind': 'pane',
            'children': [
              button('stop', [
                {'do': 'forceStop', 'entity': source},
              ]),
            ],
          },
        },
      ],
    };
    final next = migrate(save, steps: [migrations.first]);
    expect(next['v'], 2);
    final root = (next['layout']! as Map)['layers'][0]['root'] as Map;
    expect(root['children'], [
      button('open', [
        {'do': 'open', 'entity': source},
      ]),
      button('both', [
        {'do': 'open', 'entity': 'app:a'},
      ]),
      button('home', [
        {'do': 'access', 'entity': 'system', 'access': 'homeButton'},
      ]),
      button('own', [
        {'do': 'forceStop', 'entity': 'mine'},
      ]),
      {
        'id': 'card',
        'prefab': 'app-card',
        'on': {'press': <Object?>[]},
      },
    ]);
    expect((next['prefabs']! as List)[0]['root']['children'], isEmpty);
    expect((next['entities']! as List)[0]['actions'], {
      'forceStop': {'run': 'launchApp'},
    });
  });
}
