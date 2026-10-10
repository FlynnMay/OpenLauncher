import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';

LayoutItem _item(
  String id, {
  ItemKind kind = ItemKind.card,
  String? ref,
  double w = 1,
  double h = 1,
  double? x,
  double? y,
}) => LayoutItem(id: id, kind: kind, ref: ref ?? id, w: w, h: h, x: x, y: y);

LauncherCard _card(String name) => LauncherCard(
  id: 'app:$name',
  kind: CardKind.app,
  target: name,
  label: name,
);

void main() {
  group('placeItems', () {
    test('flow fills rows in order and wraps', () {
      final placed = placeItems(
        [_item('a'), _item('b', w: 2), _item('c'), _item('d')],
        3,
        SectionMode.flow,
      );
      expect(placed, const [
        Placement(0, 0, 1, 1),
        Placement(1, 0, 2, 1),
        Placement(0, 1, 1, 1),
        Placement(1, 1, 1, 1),
      ]);
      expect(rowCount(placed), 2);
    });

    test('flow goes around a tall item and never goes back', () {
      final placed = placeItems(
        [_item('tall', h: 2), _item('wide', w: 2), _item('c'), _item('d')],
        3,
        SectionMode.flow,
      );
      expect(placed, const [
        Placement(0, 0, 1, 2),
        Placement(1, 0, 2, 1),
        Placement(1, 1, 1, 1),
        Placement(2, 1, 1, 1),
      ]);
    });

    test('an item wider than the section is cut down to fit', () {
      expect(placeItems([_item('a', w: 4)], 2, SectionMode.flow), const [
        Placement(0, 0, 2, 1),
      ]);
    });

    test('grid keeps positions and leaves gaps', () {
      final placed = placeItems(
        [_item('a', x: 2, y: 1), _item('b', x: 0, y: 0)],
        4,
        SectionMode.grid,
      );
      expect(placed, const [Placement(2, 1, 1, 1), Placement(0, 0, 1, 1)]);
    });

    test('grid moves aside what has no position or collides', () {
      final placed = placeItems(
        [
          _item('first', x: 0, y: 0, w: 2),
          _item('clash', x: 1, y: 0),
          _item('new'),
          _item('off', x: 3, y: 0, w: 2),
        ],
        4,
        SectionMode.grid,
      );
      expect(placed, const [
        Placement(0, 0, 2, 1),
        Placement(2, 0, 1, 1),
        Placement(3, 0, 1, 1),
        Placement(0, 1, 2, 1),
      ]);
    });
  });

  group('Layout', () {
    test('normalised repairs what is wrong and keeps what is right', () {
      final layout = Layout(
        inbox: 'nowhere',
        panels: [
          Panel(
            id: 'left',
            sections: [
              Section(id: 's', columns: 4, items: [_item('a', w: 3)]),
            ],
          ),
          Panel(
            id: 'games',
            title: 'Games',
            sections: [
              Section(
                id: 's',
                mode: SectionMode.grid,
                columns: 3,
                items: [
                  _item('a', x: 9, y: 2, w: 2, h: 9),
                  _item('half', x: 1),
                  _item('gone', kind: ItemKind.panel, ref: 'missing'),
                  _item('open', kind: ItemKind.panel, ref: 'games'),
                ],
              ),
            ],
          ),
          const Panel(id: 'games', title: 'Duplicate'),
        ],
      ).normalised();

      expect(layout.panels.map((p) => p.id), ['home', 'left', 'games']);
      // Home was missing: it gets a section, which becomes the inbox.
      expect(layout.inbox, layout.home.sections.single.id);

      final rail = layout.panel('left')!.sections.single;
      expect((rail.columns, rail.items.single.w), (1, 1));

      final games = layout.panel('games')!;
      expect(games.title, 'Games');
      final section = games.sections.single;
      expect(section.id, isNot(rail.id));
      final [a, half, open] = section.items;
      expect(a.id, isNot(rail.items.single.id));
      expect((a.x, a.y, a.w, a.h), (1, 2, 2, Section.maxSpan));
      expect((half.x, half.y), (null, null));
      expect(open.ref, 'games');
    });

    test('survives JSON and rejects what is not a layout', () {
      final layout = Layout(
        inbox: 'main',
        panels: [
          Panel(
            id: 'home',
            sections: [
              Section(
                id: 'main',
                title: 'Favourites',
                mode: SectionMode.grid,
                columns: 6,
                items: [
                  _item('a', x: 1, y: 2, w: 2),
                  const LayoutItem(
                    id: 'w',
                    kind: ItemKind.widget,
                    ref: 'clock',
                    options: {'seconds': true},
                  ),
                ],
              ),
            ],
          ),
          const Panel(
            id: 'p',
            title: 'Games',
            position: PopupPosition.bottom,
            size: PopupSize.large,
          ),
        ],
      );
      final copy = Layout.fromJson(layout.toJson());
      expect(copy.toJson(), layout.toJson());
      expect(copy.panel('p')!.position, PopupPosition.bottom);
      expect(copy.home.sections.single.items.last.options, {'seconds': true});

      expect(
        () => Layout.fromJson(const {'panels': 'no'}),
        throwsFormatException,
      );
      expect(
        () => Layout.fromJson(const {
          'panels': [
            {
              'id': 'home',
              'sections': [
                {
                  'id': 's',
                  'items': [
                    {'id': 1, 'ref': 'app:a'},
                  ],
                },
              ],
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('withCards drops missing cards and puts new ones in the inbox', () {
      final layout = Layout.initial(['app:b', 'app:gone'])
          .withCards(['app:a', 'app:b']);
      expect(layout.home.items.map((i) => i.ref), ['app:b', 'app:a']);
      expect(layout.home.items.map((i) => i.id).toSet(), hasLength(2));
    });
  });

  group('free placement', () {
    test('items are where they say, fractions and overlaps included', () {
      final placed = placeItems(
        [
          _item('a', x: 0.5, y: 0.25, w: 1.5, h: 0.75),
          _item('b', x: 1, y: 0.5),
          _item('c'),
        ],
        4,
        SectionMode.free,
      );
      expect(placed, const [
        Placement(0.5, 0.25, 1.5, 0.75),
        Placement(1, 0.5, 1, 1),
        Placement(0, 0, 1, 1),
      ]);
      expect(rowCount(placed), 1.5);
    });

    test('fractions survive repair in a free section and nowhere else', () {
      Section section(String id, SectionMode mode) => Section(
        id: id,
        mode: mode,
        columns: 4,
        items: [_item('$id-a', x: 3.6, y: 0.3, w: 1.5, h: 0.1)],
      );
      final layout = Layout(
        inbox: 'f',
        panels: [
          Panel(
            id: 'home',
            sections: [
              section('f', SectionMode.free),
              section('g', SectionMode.grid),
            ],
          ),
        ],
      ).normalised();
      final [free, grid] = layout.home.sections
          .map((s) => s.items.single)
          .toList();
      // Kept inside the section, and no smaller than a quarter cell.
      expect((free.x, free.y, free.w, free.h), (2.5, 0.3, 1.5, 0.25));
      expect((grid.x, grid.y, grid.w, grid.h), (2, 0, 2, 1));
      final json = layout.toJson();
      expect(Layout.fromJson(json).toJson(), json);
      expect(
        (json['panels'] as List).first['sections'][1]['items'][0]['w'],
        isA<int>(),
      );
    });
  });

  group('removed cards', () {
    test('stay off until placed again', () {
      final layout = Layout.initial(['app:a', 'app:b']).without({'app:b'});
      expect(layout.removed, {'app:b'});
      final shown = layout.withCards(['app:a', 'app:b', 'app:c']);
      expect(shown.home.items.map((i) => i.ref), ['app:a', 'app:c']);

      // Placing it again is all it takes.
      final again = Layout(
        inbox: layout.inbox,
        removed: layout.removed,
        panels: [
          layout.home.withSections([
            layout.home.sections.single.withItems([_item('x', ref: 'app:b')]),
          ]),
        ],
      ).normalised();
      expect(again.removed, isEmpty);
    });
  });

  group('BoxStyle', () {
    test('reads the page\'s colours and writes them back the same', () {
      final style = BoxStyle.fromJson(const {
        'colors': ['#3d5afecc', '#000000'],
        'angle': 495,
        'border': '#FFFFFF55',
      });
      expect(style.colors, [0xCC3D5AFE, 0xFF000000]);
      expect(style.angle, 135);
      expect(style.border, 0x55FFFFFF);
      expect(style.toJson(), {
        'colors': ['#3d5afecc', '#000000ff'],
        'angle': 135,
        'border': '#ffffff55',
      });
    });

    test('leaves out what it does not understand', () {
      expect(BoxStyle.fromJson('red').isEmpty, isTrue);
      final style = BoxStyle.fromJson(const {
        'colors': ['red', 7, '#12345', '#abcdef'],
        'border': 'none',
      });
      expect(style.colors, [0xFFABCDEF]);
      expect(style.border, isNull);
      // One colour is flat: no angle to speak of.
      expect(style.toJson(), {
        'colors': ['#abcdefff'],
      });
    });

    test('sections and items keep their style through repair and JSON', () {
      final layout = Layout.fromJson(const {
        'panels': [
          {
            'id': 'home',
            'sections': [
              {
                'id': 's',
                'style': {
                  'colors': ['#11223344', '#55667788'],
                  'angle': 90,
                },
                'items': [
                  {
                    'id': 'i',
                    'ref': 'app:a',
                    'style': {'border': '#ffd54fff'},
                  },
                ],
              },
            ],
          },
        ],
      }).normalised().withCards(['app:a', 'app:b']);
      final section = layout.home.sections.single;
      expect(section.style.colors, [0x44112233, 0x88556677]);
      expect(section.items.first.style.border, 0xFFFFD54F);
      expect(section.items.last.style.isEmpty, isTrue);
      final json = Layout.fromJson(layout.toJson()).toJson();
      expect(json, layout.toJson());
      expect((json['panels'] as List).first['sections'][0]['style'], {
        'colors': ['#11223344', '#55667788'],
        'angle': 90,
      });
    });
  });

  group('resolveLayout', () {
    final cards = [_card('a'), _card('b'), _card('c')];

    test('matches items to cards, folders and widgets', () {
      final config = LauncherConfig(
        iconOverrides: {'panel:games': '/games.png'},
        layout: Layout(
          inbox: 'main',
          removed: const {'app:c'},
          panels: [
            Panel(
              id: 'home',
              sections: [
                Section(
                  id: 'main',
                  items: [
                    _item('folder', kind: ItemKind.panel, ref: 'games'),
                    _item('clock', kind: ItemKind.widget, ref: 'clock'),
                  ],
                ),
              ],
            ),
            Panel(
              id: 'games',
              title: 'Games',
              sections: [
                Section(id: 'inside', items: [_item('app:b')]),
              ],
            ),
          ],
        ),
      );
      final view = resolveLayout(cards, config);
      final [folder, clock, unplaced] = view.home.sections.single.entries;

      folder as PanelEntry;
      expect(folder.label, 'Games');
      expect(folder.icon, '/games.png');
      expect(folder.preview.map((c) => c.id), ['app:b']);

      expect(clock, isA<WidgetEntry>());
      // The card placed nowhere turns up in the inbox; the removed one
      // does not.
      expect((unplaced as CardEntry).card.id, 'app:a');
      expect(view.sidebar(Layout.leftId), isNull);
    });

    test('the same card can be in several places', () {
      final config = LauncherConfig(
        layout: Layout(
          inbox: 'main',
          panels: [
            Panel(
              id: 'home',
              sections: [
                Section(
                  id: 'main',
                  items: [
                    _item('one', ref: 'app:a'),
                    _item('two', ref: 'app:a'),
                  ],
                ),
              ],
            ),
          ],
        ).normalised(),
      );
      final entries = resolveLayout(cards, config).home.sections.single.entries;
      expect(entries.map((e) => (e as CardEntry).card.id), [
        'app:a',
        'app:a',
        'app:b',
        'app:c',
      ]);
    });
  });

  group('LauncherConfig', () {
    test('survives a JSON round trip', () {
      final config = LauncherConfig(
        layout: Layout.initial(['app:a']).without({'app:b'}),
        iconOverrides: {'app:a': '/x.png'},
        wallpaper: '/w.mp4',
        contextMenu: [CardAction.uninstall, CardAction.open],
        toasts: const ToastOptions(
          enabled: false,
          position: ToastPosition.bottomLeft,
          seconds: 9,
        ),
      );
      final copy = LauncherConfig.fromJson(config.toJson());
      expect(copy.toJson(), config.toJson());
      expect(copy.layout.removed, {'app:b'});
      expect(copy.copyWith(iconOverrides: {}).wallpaper, '/w.mp4');
      expect(copy.copyWith(wallpaper: null).wallpaper, isNull);
    });

    test('a config from before layouts keeps its card order', () {
      final config = LauncherConfig.fromJson(const {
        'order': ['app:b', 'app:a'],
        'hidden': ['app:b', 'app:c'],
        'contextMenu': ['open', 'hide'],
      });
      // What used to be hidden is now removed, wherever it was.
      expect(config.layout.home.items.map((i) => i.ref), ['app:a']);
      expect(config.layout.removed, {'app:b', 'app:c'});
      expect(config.contextMenu, [CardAction.open, CardAction.remove]);
      expect(config.toasts.enabled, isTrue);
    });

    test('a broken layout does not lose the rest', () {
      final config = LauncherConfig.fromJson(const {
        'layout': {'panels': 7},
        'wallpaper': '/w.png',
      });
      expect(config.wallpaper, '/w.png');
      expect(config.layout.home.sections, hasLength(1));
    });
  });
}
