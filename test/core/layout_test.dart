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

Panel _home(Pane root) => Panel(id: 'home', root: root);

void main() {
  group('placeItems', () {
    test('flow fills rows in order and wraps', () {
      final placed = placeItems(
        [_item('a'), _item('b', w: 2), _item('c'), _item('d')],
        3,
        PaneMode.flow,
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
        PaneMode.flow,
      );
      expect(placed, const [
        Placement(0, 0, 1, 2),
        Placement(1, 0, 2, 1),
        Placement(1, 1, 1, 1),
        Placement(2, 1, 1, 1),
      ]);
    });

    test('an item wider than the section is cut down to fit', () {
      expect(placeItems([_item('a', w: 4)], 2, PaneMode.flow), const [
        Placement(0, 0, 2, 1),
      ]);
    });

    test('grid keeps positions and leaves gaps', () {
      final placed = placeItems(
        [_item('a', x: 2, y: 1), _item('b', x: 0, y: 0)],
        4,
        PaneMode.grid,
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
        PaneMode.grid,
      );
      expect(placed, const [
        Placement(0, 0, 2, 1),
        Placement(2, 0, 1, 1),
        Placement(3, 0, 1, 1),
        Placement(0, 1, 2, 1),
      ]);
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
        PaneMode.free,
      );
      // What has no position lines up below what has, not on top of it.
      expect(placed, const [
        Placement(0.5, 0.25, 1.5, 0.75),
        Placement(1, 0.5, 1, 1),
        Placement(0, 2, 1, 1),
      ]);
      expect(rowCount(placed), 3);
    });

    test('several without a position fill rows under the rest', () {
      final placed = placeItems(
        [
          _item('placed', x: 0, y: 0, h: 1.2),
          _item('a', w: 2),
          _item('b', w: 2, h: 2),
          _item('c'),
        ],
        4,
        PaneMode.free,
      );
      expect(placed.skip(1), const [
        Placement(0, 2, 2, 1),
        Placement(2, 2, 2, 2),
        Placement(0, 4, 1, 1),
      ]);
    });
  });

  group('panes', () {
    Pane pane(
      String id, {
      PaneMode mode = PaneMode.flow,
      List<LayoutItem>? items,
    }) => Pane(id: id, mode: mode, columns: 4, items: items ?? const []);

    test('nest, and are found with what is in them', () {
      final root = pane(
        'global',
        mode: PaneMode.free,
        items: [
          _item('loose', ref: 'app:a'),
          LayoutItem.pane(
            pane(
              'outer',
              items: [
                _item('in-outer', ref: 'app:b'),
                LayoutItem.pane(
                  pane('inner', items: [_item('in-inner', ref: 'app:c')]),
                ),
              ],
            ),
            x: 0.5,
            y: 1,
            w: 3,
            h: 2.5,
          ),
        ],
      );
      expect(root.panes.map((p) => p.id), ['global', 'outer', 'inner']);
      // A card can sit in the global pane, outside every other.
      expect(root.contents.map((i) => i.ref), ['app:a', 'app:b', 'app:c']);

      final layout = Layout(inbox: 'inner', panels: [_home(root)]).normalised();
      expect(layout.inbox, 'inner');
      final outer = layout.home.root.items.last;
      expect((outer.x, outer.y, outer.w, outer.h), (0.5, 1, 3, 2.5));
      final json = layout.toJson();
      expect(Layout.fromJson(json).normalised().toJson(), json);

      // New cards turn up in the inbox, however deep it is.
      final shown = layout.withCards(['app:a', 'app:b', 'app:c', 'app:new']);
      final inner = shown.home.root.panes.last;
      expect(inner.items.map((i) => i.ref), ['app:c', 'app:new']);
      // Removing a card takes it out of every pane.
      expect(shown.without({'app:b', 'app:c'}).home.items.map((i) => i.ref), [
        'app:a',
        'app:new',
      ]);
    });

    test('normalised repairs what is wrong and keeps what is right', () {
      Pane nest(int depth) => pane(
        'p$depth',
        items: [
          _item('card$depth', ref: 'app:$depth'),
          if (depth < 6) LayoutItem.pane(nest(depth + 1)),
        ],
      );
      final layout = Layout(
        inbox: 'nowhere',
        panels: [
          Panel(
            id: 'left',
            root: Pane(
              id: 'rail',
              columns: 4,
              items: [
                _item('a', w: 3),
                LayoutItem.pane(pane('in-rail', items: [_item('b')])),
              ],
            ),
          ),
          Panel(
            id: 'games',
            title: 'Games',
            root: pane(
              'rail',
              mode: PaneMode.grid,
              items: [
                _item('a', x: 9, y: 2, w: 2, h: 99),
                _item('half', x: 1),
                _item('gone', kind: ItemKind.panel, ref: 'missing'),
                _item('open', kind: ItemKind.panel, ref: 'games'),
                const LayoutItem(id: 'empty', kind: ItemKind.pane, ref: 'x'),
                LayoutItem.pane(nest(2)),
              ],
            ),
          ),
          Panel.empty('games', title: 'Duplicate'),
        ],
      ).normalised();

      expect(layout.panels.map((p) => p.id), ['home', 'left', 'games']);
      // Home was missing: it gets a global pane, which becomes the inbox.
      expect(layout.inbox, layout.home.root.id);
      expect(layout.home.root.mode, PaneMode.grid);

      // A sidebar is a pane like any other: it keeps its columns, its
      // widths and the pane inside it.
      final rail = layout.panel('left')!.root;
      expect(rail.columns, 4);
      expect(rail.items.map((i) => (i.id, i.kind, i.w)), [
        ('a', ItemKind.card, 3),
        ('pane:in-rail', ItemKind.pane, 1),
      ]);
      expect(rail.items.last.pane!.items.single.id, 'b');

      final games = layout.panel('games')!;
      expect(games.title, 'Games');
      expect(games.root.id, isNot(rail.id));
      final [a, half, open, nested] = games.root.items;
      expect(a.id, isNot('a'));
      expect((a.x, a.y, a.w, a.h), (2, 2, 2, Pane.maxRows));
      expect((half.x, half.y), (null, null));
      expect(open.ref, 'games');
      // Panes deeper than allowed give their contents to the last that is.
      final depths = games.root.panes.map((p) => p.id).toList();
      expect(depths, hasLength(Pane.maxDepth));
      expect(nested.pane!.contents.map((i) => i.ref), [
        for (var depth = 2; depth <= 6; depth++) 'app:$depth',
      ]);
      final ids = [
        for (final panel in layout.panels)
          for (final p in panel.root.panes) ...p.items.map((i) => i.id),
      ];
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('fractions survive repair in a free pane and nowhere else', () {
      Pane of(String id, PaneMode mode) => Pane(
        id: id,
        mode: mode,
        columns: 4,
        items: [_item('$id-a', x: 3.6, y: 0.3, w: 1.5, h: 0.1)],
      );
      final layout = Layout(
        inbox: 'f',
        panels: [
          _home(
            pane(
              'global',
              items: [
                LayoutItem.pane(of('f', PaneMode.free)),
                LayoutItem.pane(of('g', PaneMode.grid)),
              ],
            ),
          ),
        ],
      ).normalised();
      final [free, grid] = layout.home.items.toList();
      // Kept inside the pane, and no smaller than a quarter cell.
      expect((free.x, free.y, free.w, free.h), (2.5, 0.3, 1.5, 0.25));
      expect((grid.x, grid.y, grid.w, grid.h), (2, 0, 2, 1));
    });

    test('rejects what is not a layout', () {
      expect(
        () => Layout.fromJson(const {'panels': 'no'}),
        throwsFormatException,
      );
      expect(
        () => Layout.fromJson(const {
          'panels': [
            {
              'id': 'home',
              'pane': {
                'id': 's',
                'items': [
                  {'id': 1, 'ref': 'app:a'},
                ],
              },
            },
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('layouts from before panes', () {
    Map<String, Object?> section(
      String id, {
      int items = 0,
      Object? style,
      String title = '',
    }) => {
      'id': id,
      'title': title,
      'columns': 6,
      'style': ?style,
      'items': [
        for (var i = 0; i < items; i++) {'id': '$id$i', 'ref': 'app:$id$i'},
      ],
    };

    test('sections become panes where they were', () {
      final layout = Layout.fromJson({
        'inbox': 'rest',
        'panels': [
          {
            'id': 'home',
            'sections': [
              section(
                'top',
                items: 6,
                title: 'Favourites',
                style: {'border': '#ffffffff'},
              ),
              section('rest', items: 13),
            ],
          },
          {
            'id': 'left',
            'sections': [section('r1', items: 1), section('r2', items: 2)],
          },
          {
            'id': 'folder',
            'sections': [section('only', items: 3)],
          },
        ],
      }).normalised();

      final global = layout.home.root;
      expect(
        (global.mode, global.columns),
        (PaneMode.free, Pane.globalColumns),
      );
      final [top, rest] = global.items;
      expect((top.pane!.title, top.pane!.columns), ('Favourites', 6));
      expect(layout.inbox, 'rest');
      // Inside the screen's old margins, one under the other, full width.
      for (final item in [top, rest]) {
        expect(item.x, closeTo(0.59, 0.01));
        expect(item.w, closeTo(10.82, 0.01));
      }
      expect(top.y, closeTo(1.35, 0.01));
      expect(rest.y!, greaterThan(top.y! + top.h));
      // One row of six cards against three rows of them.
      expect(rest.h, greaterThan(top.h));

      // A rail keeps its things, in one list; a plain folder keeps its look.
      expect(layout.panel('left')!.root.items, hasLength(3));
      final folder = layout.panel('folder')!.root;
      expect((folder.id, folder.items.length), ('only', 3));
    });

    test('a new home screen is one pane as tall as the screen', () {
      final layout = Layout.initial(['app:b', 'app:gone'])
          .withCards(['app:a', 'app:b']);
      final item = layout.home.root.items.single;
      expect(item.pane!.items.map((i) => i.ref), ['app:b', 'app:a']);
      expect(layout.inbox, item.pane!.id);
      // From under the top margin to the bottom one, on a 540-high screen.
      expect(item.h, closeTo(7.7, 0.1));
    });
  });

  test('a pane keeps the spacing it is given, within reason', () {
    Pane pane(String id, double? spacing) =>
        Pane(id: id, spacing: spacing, items: [_item('$id-a')]);
    final layout = Layout(
      inbox: 'a',
      panels: [
        _home(
          Pane(
            id: 'global',
            spacing: 4,
            items: [
              LayoutItem.pane(pane('a', null)),
              LayoutItem.pane(pane('b', 0)),
              LayoutItem.pane(pane('c', 500)),
            ],
          ),
        ),
      ],
    ).normalised();
    final panes = layout.home.root.panes.toList();
    expect(panes.map((p) => p.spacing), [4, null, 0, Pane.maxSpacing]);
    // Unset, it is the usual gap, wider across than down.
    expect((panes[1].spacingX, panes[1].spacingY), (20, 16));
    expect((panes[2].spacingX, panes[2].spacingY), (0, 0));
    final json = layout.toJson();
    expect(Layout.fromJson(json).toJson(), json);
    expect(layout.withCards(['app:x']).home.root.spacing, 4);
  });

  test('a pane keeps the padding it is given, within reason', () {
    final layout = Layout.fromJson(const {
      'panels': [
        {
          'id': 'home',
          'pane': {
            'id': 'global',
            'padding': 24,
            'items': [
              {
                'id': 'i',
                'kind': 'pane',
                'pane': {'id': 'a', 'padding': 900},
              },
              {
                'id': 'j',
                'kind': 'pane',
                'pane': {'id': 'b'},
              },
            ],
          },
        },
      ],
    }).normalised();
    expect(layout.home.root.panes.map((p) => p.padding), [
      24,
      Pane.maxPadding,
      null,
    ]);
    final json = layout.toJson();
    expect(Layout.fromJson(json).toJson(), json);
  });

  test('a card can be told to hide its name, and stays told', () {
    final layout = Layout.fromJson(const {
      'panels': [
        {
          'id': 'home',
          'pane': {
            'id': 'global',
            'items': [
              {'id': 'a', 'ref': 'app:a', 'hideName': true},
              {'id': 'b', 'ref': 'app:b'},
            ],
          },
        },
      ],
    }).normalised();
    expect(layout.home.items.map((i) => i.hideName), [true, false]);
    final items = (layout.toJson()['panels'] as List).first['pane']['items'];
    expect(items[0]['hideName'], isTrue);
    expect((items[1] as Map).containsKey('hideName'), isFalse);
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
          _home(const Pane(id: 'global').withItems([_item('x', ref: 'app:b')])),
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
  });

  group('resolveLayout', () {
    final cards = [_card('a'), _card('b'), _card('c')];

    test('matches items to cards, folders, widgets and panes', () {
      final config = LauncherConfig(
        iconOverrides: {'panel:games': '/games.png'},
        layout: Layout(
          inbox: 'main',
          removed: const {'app:c'},
          panels: [
            _home(
              Pane(
                id: 'global',
                items: [
                  _item('folder', kind: ItemKind.panel, ref: 'games'),
                  _item('clock', kind: ItemKind.widget, ref: 'clock'),
                  LayoutItem.pane(const Pane(id: 'main')),
                ],
              ),
            ),
            Panel(
              id: 'games',
              title: 'Games',
              root: Pane(id: 'inside', items: [_item('app:b')]),
            ),
          ],
        ),
      );
      final view = resolveLayout(cards, config);
      final [folder, clock, pane] = view.home.root.entries;

      folder as PanelEntry;
      expect(folder.label, 'Games');
      expect(folder.icon, '/games.png');
      expect(folder.preview.map((c) => c.id), ['app:b']);
      expect(clock, isA<WidgetEntry>());
      // The card placed nowhere turns up in the inbox pane; the removed
      // one does not.
      final inside = (pane as PaneEntry).view.entries.single as CardEntry;
      expect(inside.card.id, 'app:a');
      expect(view.home.root.contents, hasLength(3));
      expect(view.bars, isEmpty);
    });

    test('the same card can be in several places', () {
      final config = LauncherConfig(
        layout: Layout(
          inbox: 'global',
          panels: [
            _home(
              Pane(
                id: 'global',
                items: [
                  _item('one', ref: 'app:a'),
                  _item('two', ref: 'app:a'),
                ],
              ),
            ),
          ],
        ).normalised(),
      );
      final entries = resolveLayout(cards, config).home.root.entries;
      expect(entries.map((e) => (e as CardEntry).card.id), [
        'app:a',
        'app:a',
        'app:b',
        'app:c',
      ]);
    });
  });

  group('sidebars and what panes decide', () {
    test('there is one for each edge, each with its usual size', () {
      final left = Panel.empty(Layout.leftId);
      final top = Panel.empty(Layout.topId);
      expect(left.kind, PanelKind.sidebar);
      expect(
        (left.edge, left.openWidth, left.openHeight, left.closedSize),
        (BarEdge.left, 260, Panel.fill, 96),
      );
      // Along a side it starts as a line of small rows.
      expect(left.root.rowHeight, Pane.barRowHeight);
      expect(left.root.itemLook, TileLook.row);
      expect(
        (top.edge, top.openWidth, top.openHeight, top.closedSize),
        (BarEdge.top, Panel.fill, 120, 0),
      );
      expect(Panel.kindOf('bottom'), PanelKind.sidebar);
      expect(Panel.kindOf('elsewhere'), PanelKind.popup);
    });

    test('sizes are written, read back and kept within bounds', () {
      final layout = Layout(
        inbox: 'main',
        panels: [
          Panel.empty(Layout.homeId),
          Panel.empty(
            Layout.rightId,
            width: Panel.fill,
            height: 300,
            closed: 0,
          ),
          Panel.empty(Layout.bottomId, height: 5000, closed: -3),
        ],
      ).normalised();
      final copy = Layout.fromJson(layout.toJson());
      final right = copy.panel(Layout.rightId)!;
      expect((right.width, right.height, right.closed), (Panel.fill, 300, 0));
      final bottom = copy.panel(Layout.bottomId)!;
      expect((bottom.height, bottom.closed), (Panel.maxExtent, 0));
      expect(bottom.width, isNull);
    });

    test('a sidebar saved before they were panes still looks like one', () {
      final old = Layout.fromJson(const {
        'inbox': 'home/root',
        'panels': [
          {
            'id': 'left',
            'pane': {
              'id': 'left/root',
              'columns': 1,
              'items': [
                {'id': 'a', 'ref': 'app:a'},
              ],
            },
          },
        ],
      });
      final root = old.panel('left')!.root;
      expect(
        (root.rowHeight, root.itemLook, root.itemW),
        (36, TileLook.row, 1),
      );
      // Once written by this version it is taken as it is.
      final plain = Layout(
        inbox: 'x',
        panels: [
          Panel(
            id: 'left',
            root: const Pane(id: 'left/root'),
          ),
        ],
      );
      expect(
        Layout.fromJson(plain.toJson()).panel('left')!.root.itemLook,
        isNull,
      );
    });

    test('a pane decides for its cards without changing what they say', () {
      final pane = Pane(
        id: 'p',
        itemLook: TileLook.row,
        itemW: 2,
        itemNames: false,
        items: [
          _item('a', w: 3, h: 2),
          _item('clock', kind: ItemKind.widget, ref: 'clock', w: 4),
          LayoutItem.pane(const Pane(id: 'inner'), w: 5),
        ],
      );
      final [card, widget, inner] = pane.shown;
      expect(
        (card.look, card.w, card.h, card.hideName),
        (TileLook.row, 2, 2, true),
      );
      // Only cards and folders are decided for.
      expect((widget.w, inner.w), (4, 5));
      // What the card says is still there for when the pane stops.
      expect((pane.items.first.w, pane.items.first.look), (3, TileLook.card));
      expect(
        pane.copyWith(itemLook: null, itemW: null, itemNames: null).decides,
        isFalse,
      );
      // And all of it survives being written and read.
      final copy = Pane.fromJson(pane.copyWith(rowHeight: 40.0).toJson());
      expect(
        (copy.itemLook, copy.itemW, copy.itemNames, copy.rowHeight),
        (TileLook.row, 2, false, 40),
      );
    });

    test('a pane keeps how round each of its corners is', () {
      final pane = Pane(id: 'p', corners: const [0, 8, 500, -2]);
      final layout = Layout(
        inbox: 'p',
        panels: [Panel(id: Layout.homeId, root: pane)],
      ).normalised();
      // Each within what a corner can be.
      expect(layout.home.root.corners, [0, 8, Pane.maxCorner, 0]);
      expect(Pane.fromJson(layout.home.root.toJson()).corners, [
        0,
        8,
        Pane.maxCorner,
        0,
      ]);
      // Anything but four numbers is the usual.
      expect(
        Pane.fromJson(const {
          'id': 'p',
          'corners': [1, 2],
        }).corners,
        isNull,
      );
      expect(pane.copyWith(corners: null).corners, isNull);
    });

    test('what is drawn is what the pane decides', () {
      final view = resolveLayout(
        const [
          LauncherCard(
            id: 'app:a',
            kind: CardKind.app,
            target: 'a',
            label: 'A',
          ),
        ],
        LauncherConfig(
          layout: Layout(
            inbox: 'main',
            panels: [
              Panel(
                id: Layout.homeId,
                root: Pane(
                  id: 'main',
                  itemLook: TileLook.row,
                  items: [_item('a', ref: 'app:a')],
                ),
              ),
            ],
          ),
        ),
      );
      expect(view.home.root.entries.single.item.look, TileLook.row);
    });
  });

  group('LauncherConfig', () {
    test('survives a JSON round trip', () {
      final config = LauncherConfig(
        layout: Layout.initial(['app:a']).without({'app:b'}),
        iconOverrides: {'app:a': '/x.png'},
        wallpapers: ['/w.mp4', '/x.png'],
        wallpaperEvery: 30,
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
      expect(copy.wallpaperEvery, 30);
      expect(copy.copyWith(wallpapers: const []).wallpaper, isNull);
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
      // The one wallpaper older configs had is the first of the list now.
      expect(config.wallpapers, ['/w.png']);
      expect(config.wallpaperEvery, 0);
      expect(config.layout.home.root.items, hasLength(1));
    });
  });
}
