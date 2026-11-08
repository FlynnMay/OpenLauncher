import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/layout/screen.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';
import 'package:openlauncher_domain/slice/slice.dart';
import 'package:test/test.dart';

Prefab cardPrefab() => Prefab(
  id: 'card',
  name: 'Card',
  root: Node.layout(
    id: 'root',
    children: [
      const Node(
        id: 'image',
        modules: {
          'picture': {'fit': 'cover'},
        },
      ),
      const Node(
        id: 'name',
        modules: {
          'text': {'size': 18},
        },
      ),
    ],
  ),
  variants: const {
    'row': PrefabVariant('Row', {
      'name': {
        'modules': {
          'text': {'size': 14},
        },
      },
    }),
  },
);

Node card(String id, [Overrides overrides = const {}]) => Node.of(
  'app:$id',
  id: id,
  prefab: 'card',
  variable: 'what',
).copyWith(overrides: overrides);

Document document() {
  final prefab = cardPrefab();
  return Document(
    layout: Layout(
      inbox: 'main',
      startup: const Startup('home'),
      screens: [
        Screen(
          id: 'home',
          root: Node.layout(
            id: 'main',
            children: [
              card('a'),
              card('b', {
                'image': {
                  'modules': {
                    'picture': {'fit': 'contain'},
                  },
                },
              }),
              Node.layout(id: 'shelf', children: [card('c')]),
            ],
          ),
        ),
      ],
    ),
    settings: {
      'prefabs': [prefab.toJson()],
    },
    prefabs: {prefab.id: prefab},
  );
}

Object? fitOf(Node node) => node.modules['picture']?['fit'];

List<String> ids(Document doc, String container) => [
  for (final child in doc.layout.node(container)!.children) child.id,
];

/// Applies the edits that undo, in order.
Document undone(Document after, List<SliceEdit> inverse) {
  var doc = after;
  for (final edit in inverse) {
    doc = edit.apply(doc).document;
  }
  return doc;
}

void main() {
  stepFourTests();
  stepThreeTests();
  stepTwoTests();
  group('Address', () {
    test('is read and written back', () {
      for (final text in [
        '/',
        'prefab:card/',
        'prefab:card/image',
        'prefab:card@row/name',
        'prefab:system:card/image',
        'layout:a',
        'layout:a/image',
      ]) {
        expect(Address.parse(text).toString(), text);
      }
    });

    test('refuses what is not one', () {
      expect(() => Address.parse('nope'), throwsA(isA<CommandRefused>()));
      expect(() => Address.parse('layout:'), throwsA(isA<CommandRefused>()));
    });
  });

  group('editing fields', () {
    test('a prefab child is changed for the prefab, and undone', () {
      final before = document();
      final slice = Slice.load(before, 'prefab:card/image')
        ..edit('picture', 'fit', 'contain');
      expect(fitOf(slice.node), 'contain');
      final saved = slice.save();
      final result = saved.apply(before);
      final prefab = result.document.prefabs['card']!;
      expect(
        fitOf(prefab.root.all.firstWhere((n) => n.id == 'image')),
        'contain',
      );
      expect(result.document.layout.toJson(), before.layout.toJson());
      final back = undone(result.document, result.inverse);
      expect(
        fitOf(
          back.prefabs['card']!.root.all.firstWhere((n) => n.id == 'image'),
        ),
        'cover',
      );
    });

    test(
      'a variant keeps its own overrides, and one equal to the base clears',
      () {
        final before = document();
        final set = (Slice.load(
          before,
          'prefab:card@row/name',
        )..edit('text', 'size', 20)).save().apply(before).document;
        expect(set.prefabs['card']!.variants['row']!.overrides['name'], {
          'modules': {
            'text': {'size': 20},
          },
        });
        final cleared = (Slice.load(
          set,
          'prefab:card@row/name',
        )..edit('text', 'size', 18)).save().apply(set).document;
        expect(cleared.prefabs['card']!.variants['row']!.overrides, isEmpty);
        expect(
          cleared.prefabs['card']!.root.all
              .firstWhere((n) => n.id == 'name')
              .modules['text'],
          {'size': 18},
        );
      },
    );

    test('an instance child changes only that instance', () {
      final before = document();
      final result = (Slice.load(
        before,
        'layout:a/image',
      )..edit('picture', 'fit', 'contain')).save().apply(before);
      final layout = result.document.layout;
      expect(layout.node('a')!.overrides['image'], isNotEmpty);
      expect(layout.node('b')!.overrides, before.layout.node('b')!.overrides);
      expect(
        result.document.prefabs['card']!.toJson(),
        before.prefabs['card']!.toJson(),
      );
      final back = undone(result.document, result.inverse);
      expect(back.layout.node('a')!.overrides, isEmpty);
    });

    test('reverting an instance child hands it back to the prefab', () {
      final before = document();
      final reverted = (Slice.load(
        before,
        'layout:b/image',
      )..revert('picture', 'fit')).save().apply(before).document;
      expect(reverted.layout.node('b')!.overrides, isEmpty);
    });

    test('the view of an instance child is as the instance draws it', () {
      expect(fitOf(Slice.load(document(), 'layout:b/image').node), 'contain');
      expect(fitOf(Slice.load(document(), 'layout:a/image').node), 'cover');
    });

    test('a missing address or child is refused', () {
      expect(
        () => Slice.load(document(), 'layout:zzz'),
        throwsA(isA<CommandRefused>()),
      );
      expect(
        () => Slice.load(document(), 'prefab:card/zzz'),
        throwsA(isA<CommandRefused>()),
      );
      expect(
        () => Slice.load(document(), 'prefab:none/'),
        throwsA(isA<CommandRefused>()),
      );
    });
  });

  group('cut, copy and paste', () {
    test(
      'a cut keeps its ids and goes where it is pasted, undone in two steps',
      () {
        final before = document();
        final cut = Slice.load(before, 'layout:b');
        final clip = cut.cut();
        expect((clip as NodeClip).cut, isTrue);
        final removed = cut.save().apply(before);
        expect(ids(removed.document, 'main'), ['a', 'shelf']);

        final paste = Slice.load(removed.document, 'layout:c')
          ..pasteAfter(clip);
        final pasted = paste.save().apply(removed.document);
        expect(ids(pasted.document, 'shelf'), ['c', 'b']);

        final one = undone(pasted.document, pasted.inverse);
        expect(ids(one, 'shelf'), ['c']);
        final two = undone(one, removed.inverse);
        expect(two.layout.toJson(), before.layout.toJson());
      },
    );

    test('a copy of something with no entity gets a new id', () {
      final before = document();
      final plain = Document(
        layout: before.layout.withContainer(
          'main',
          (main) => main.copyWith(
            children: [
              ...main.children,
              Node.layout(id: 'spacer'),
            ],
          ),
        ),
        settings: before.settings,
        prefabs: before.prefabs,
      );
      final clip = Slice.load(plain, 'layout:spacer').copy();
      final result = (Slice.load(
        plain,
        'layout:spacer',
      )..pasteAfter(clip)).save().apply(plain);
      expect(ids(result.document, 'main').last, 'spacer-2');
      expect(
        undone(result.document, result.inverse).layout.toJson(),
        plain.layout.toJson(),
      );
    });

    test('a copy of a card that holds an entity places it a second time', () {
      final before = document();
      final clip = Slice.load(before, 'layout:a').copy();
      final result = (Slice.load(
        before,
        'layout:b',
      )..pasteAfter(clip)).save().apply(before);
      expect(ids(result.document, 'main'), ['a', 'b', 'a-2', 'shelf']);
      expect(result.document.layout.node('a-2')!.handed, ['app:a']);
      expect(
        undone(result.document, result.inverse).layout.toJson(),
        before.layout.toJson(),
      );
    });

    test('pasting into a place that cannot hold it is refused', () {
      final before = document();
      final clip = Slice.load(before, 'layout:a').cut();
      expect(
        () => Slice.load(before, 'layout:b').pasteInto(clip),
        throwsA(isA<CommandRefused>()),
      );
    });

    test('a module is copied from one node and pasted on another', () {
      final before = document();
      final clip = Slice.load(
        before,
        'prefab:card/image',
      ).copyModule('picture');
      final result = (Slice.load(
        before,
        'prefab:card/name',
      )..pasteModule(clip)).save().apply(before);
      final name = result.document.prefabs['card']!.root.all.firstWhere(
        (n) => n.id == 'name',
      );
      expect(name.modules['picture'], {'fit': 'cover'});
      final back = undone(result.document, result.inverse);
      expect(
        back.prefabs['card']!.root.all
            .firstWhere((n) => n.id == 'name')
            .modules['picture'],
        isNull,
      );
    });

    test(
      'a child of a prefab, shown through an instance, cannot be lifted out',
      () {
        expect(
          () => Slice.load(document(), 'layout:a/image').cut(),
          throwsA(isA<CommandRefused>()),
        );
      },
    );

    test('a prefab cannot take a copy of itself', () {
      final before = document();
      final clip = NodeClip(card('x'));
      expect(
        () => (Slice.load(
          before,
          'prefab:card/image',
        )..pasteAfter(clip)).save().apply(before),
        throwsA(isA<CommandRefused>()),
      );
    });

    test('cutting and pasting inside a prefab works', () {
      final before = document();
      final slice = Slice.load(before, 'prefab:card/image');
      final clip = slice.cut();
      final removed = slice.save().apply(before);
      final pasted = (Slice.load(
        removed.document,
        'prefab:card/name',
      )..pasteAfter(clip)).save().apply(removed.document).document;
      expect(
        [for (final c in pasted.prefabs['card']!.root.children) c.id],
        ['name', 'image'],
      );
    });
  });

  group('as data', () {
    test('an edit survives JSON and does the same', () {
      final before = document();
      final clip = Slice.load(before, 'layout:b').cut();
      final slice = Slice.load(before, 'layout:c')
        ..edit('picture', 'fit', 'contain')
        ..pasteAfter(clip);
      final edit = slice.save();
      final read = SliceEdit.fromJson(edit.toJson());
      expect(read.toJson(), edit.toJson());
      expect(
        read.apply(before).document.layout.toJson(),
        edit.apply(before).document.layout.toJson(),
      );
    });

    test('an operation that is not one is refused', () {
      expect(
        () => SliceOp.fromJson({'op': 'explode'}),
        throwsA(isA<CommandRefused>()),
      );
    });
  });
}

void stepTwoTests() {
  group('sizing', () {
    test('a width is kept inside the container and touches only that node', () {
      final before = document();
      final result = (Slice.load(
        before,
        'layout:a',
      )..size('w', 99)).save().apply(before);
      expect(result.document.layout.node('a')!.w, lessThanOrEqualTo(5));
      expect(
        result.document.layout.node('b')!.toJson(),
        before.layout.node('b')!.toJson(),
      );
      expect(
        undone(result.document, result.inverse).layout.toJson(),
        before.layout.toJson(),
      );
    });

    test('a screen root has no size to set', () {
      expect(
        () => Slice.load(document(), 'layout:main').size('w', 2),
        throwsA(isA<CommandRefused>()),
      );
    });
  });

  group('whole module values', () {
    test('a module is set to new values and taken off', () {
      final before = document();
      final set =
          (Slice.load(before, 'prefab:card/name')
                ..setModule('text', {'size': 30, 'weight': 700}))
              .save()
              .apply(before)
              .document;
      expect(Slice.load(set, 'prefab:card/name').node.modules['text'], {
        'size': 30,
        'weight': 700,
      });
      final off = (Slice.load(
        set,
        'prefab:card/name',
      )..setModule('text', null)).save().apply(set).document;
      expect(Slice.load(off, 'prefab:card/name').node.modules['text'], isNull);
    });

    test(
      'a change to a node is kept as the modules that came out different',
      () {
        final before = document();
        final slice = Slice.load(before, 'prefab:card/image')
          ..change(
            (node) => node
                .withValue('picture', 'fit', 'contain')
                .withValue('text', 'size', 9),
          );
        expect(slice.save().ops, hasLength(2));
        final done = slice.save().apply(before).document;
        final image = Slice.load(done, 'prefab:card/image').node;
        expect(image.modules['picture']!['fit'], 'contain');
        expect(image.modules['text']!['size'], 9);
      },
    );
  });

  group('instances', () {
    test('an instance is unpacked into plain nodes, and undone', () {
      final before = document();
      final result = (Slice.load(
        before,
        'layout:a',
      )..unpack()).save().apply(before);
      expect(result.document.layout.node('a')!.isInstance, isFalse);
      final back = undone(result.document, result.inverse);
      expect(back.layout.node('a')!.isInstance, isTrue);
    });

    test('something that is not an instance cannot be unpacked', () {
      expect(
        () => Slice.load(document(), 'layout:shelf').unpack(),
        throwsA(isA<CommandRefused>()),
      );
    });
  });

  group('EditSlice', () {
    test('is the same edit as a command, undone as one step', () {
      final before = document();
      final one = Slice.load(before, 'layout:a/image')
        ..edit('picture', 'fit', 'contain');
      final two = Slice.load(before, 'layout:b/image')
        ..revert('picture', 'fit');
      final command = EditSlice([one.save(), two.save()]);
      final read = commandFromJson(command.toJson());
      final after = read.edit(before);
      expect(after.layout.node('a')!.overrides, isNotEmpty);
      expect(after.layout.node('b')!.overrides, isEmpty);
      final back = read.undoing(before).edit(after);
      expect(back.layout.toJson(), before.layout.toJson());
    });
  });
}

void stepThreeTests() {
  Document withShipped() {
    final base = document();
    return Document(
      layout: base.layout,
      settings: {'prefabs': const []},
      prefabs: base.prefabs,
      shippedPrefabs: base.prefabs,
    );
  }

  group('moving and docking', () {
    test('a move is a cut and an insert in one command, undone as one', () {
      final before = document();
      final clip = NodeClip(before.layout.node('b')!, cut: true);
      final command = EditSlice([
        const SliceEdit(LayoutAddress('b'), [RemoveNode()]),
        SliceEdit(LayoutAddress('c'), [Insert(Where.after, clip)]),
      ]);
      final after = command.edit(before);
      expect(ids(after, 'main'), ['a', 'shelf']);
      expect(ids(after, 'shelf'), ['c', 'b']);
      expect(
        command.undoing(before).edit(after).layout.toJson(),
        before.layout.toJson(),
      );
    });

    test('a node dropped on a grid takes the cell it is given', () {
      final before = document();
      final grid = Document(
        layout: before.layout.withContainer(
          'shelf',
          (shelf) => shelf.copyWith(children: const []).withModule('layout', {
            'mode': 'grid',
            'columns': 4,
          }),
        ),
        settings: before.settings,
        prefabs: before.prefabs,
      );
      final clip = NodeClip(card('n'));
      final result = SliceEdit(const LayoutAddress('shelf'), [
        Insert(Where.into, clip, x: 2, y: 1),
      ]).apply(grid);
      final placed = result.document.layout.node('n')!;
      expect((placed.x, placed.y), (2, 1));
    });

    test('a docked container is put in as it is, taking no cell', () {
      final before = document();
      final docked = Node.layout(id: 'drawer')
          .withModule('dock', {'position': 'left'});
      final result = SliceEdit(const LayoutAddress('main'), [
        Insert(Where.into, NodeClip(docked)),
      ]).apply(before);
      final drawer = result.document.layout.node('drawer')!;
      expect(drawer.modules['sizing'], isNull);
      expect(
        SliceEdit(const LayoutAddress('drawer'), const [
          RemoveNode(),
        ]).apply(result.document).document.layout.node('drawer'),
        isNull,
      );
    });
  });

  group('the prefab library', () {
    test('a new prefab is saved and a revert takes it away again', () {
      final before = withShipped();
      final prefab = Prefab(
        id: 'fresh',
        name: 'Fresh',
        root: Node.layout(id: 'root'),
      );
      final result = SliceEdit(PrefabAddress('fresh'), [
        SavePrefab(prefab),
      ]).apply(before);
      expect(result.document.prefabs.containsKey('fresh'), isTrue);
      expect(result.document.settings['prefabs'], hasLength(1));
      final back = undone(result.document, result.inverse);
      expect(back.prefabs.containsKey('fresh'), isFalse);
      expect(back.settings['prefabs'], isEmpty);
    });

    test('the user\'s copy of a pack prefab goes back to the pack\'s', () {
      final before = withShipped();
      final edited = cardPrefab().copyWith(name: 'Mine');
      final saved = SliceEdit(PrefabAddress('card'), [
        SavePrefab(edited),
      ]).apply(before).document;
      expect(saved.prefabs['card']!.name, 'Mine');
      final reverted = const SliceEdit(PrefabAddress('card'), [
        RevertPrefab(),
      ]).apply(saved);
      expect(reverted.document.prefabs['card']!.name, 'Card');
      expect(reverted.document.settings['prefabs'], isEmpty);
      expect(
        undone(reverted.document, reverted.inverse).prefabs['card']!.name,
        'Mine',
      );
    });

    test(
      'deleting a prefab unpacks its instances, and undo brings them back',
      () {
        final before = document();
        final result = const SliceEdit(PrefabAddress('card'), [
          DeletePrefab(),
        ]).apply(before);
        expect(result.document.layout.node('a')?.isInstance ?? false, isFalse);
        expect(result.document.prefabs.containsKey('card'), isFalse);
        final back = undone(result.document, result.inverse);
        expect(back.layout.node('a')!.isInstance, isTrue);
        expect(back.prefabs.containsKey('card'), isTrue);
      },
    );

    test('a pack\'s prefab is reverted, not deleted', () {
      expect(
        () => const SliceEdit(PrefabAddress('card'), [
          DeletePrefab(),
        ]).apply(withShipped()),
        throwsA(isA<CommandRefused>()),
      );
    });

    test('a child is renamed and what names it follows', () {
      final before = document();
      final result = const SliceEdit(PrefabAddress('card', child: 'image'), [
        RenameChild('picture'),
      ]).apply(before);
      final prefab = result.document.prefabs['card']!;
      expect(prefab.root.all.map((n) => n.id), contains('picture'));
      expect(prefab.root.all.map((n) => n.id), isNot(contains('image')));
      expect(result.document.layout.node('b')!.overrides.keys, ['picture']);
      final back = undone(result.document, result.inverse);
      expect(back.layout.node('b')!.overrides.keys, ['image']);
    });

    test('another part of the prefab with that name refuses a rename', () {
      expect(
        () => const SliceEdit(PrefabAddress('card', child: 'image'), [
          RenameChild('name'),
        ]).apply(document()),
        throwsA(isA<CommandRefused>()),
      );
    });

    test('a container is made a prefab, and the undo puts it back', () {
      final before = document();
      final result = const SliceEdit(LayoutAddress('shelf'), [
        MakePrefab('made', 'Made'),
      ]).apply(before);
      expect(result.document.layout.node('shelf')!.prefab, 'made');
      expect(result.document.prefabs.containsKey('made'), isTrue);
      final back = undone(result.document, result.inverse);
      expect(back.layout.toJson(), before.layout.toJson());
      expect(back.prefabs.containsKey('made'), isFalse);
    });

    test(
      'the inbox made a prefab moves to a container, and an id is not reused',
      () {
        final before = document();
        final inShelf = Document(
          layout: before.layout.copyWith(inbox: 'shelf'),
          settings: before.settings,
          prefabs: before.prefabs,
        );
        final moved = const SliceEdit(LayoutAddress('shelf'), [
          MakePrefab('made', 'Made'),
        ]).apply(inShelf);
        expect(moved.document.layout.inbox, isNot('shelf'));
        expect(
          moved.document.layout.node(moved.document.layout.inbox),
          isNotNull,
        );
        expect(undone(moved.document, moved.inverse).layout.inbox, 'shelf');
        expect(
          () => const SliceEdit(LayoutAddress('main'), [
            MakePrefab('made', 'Made'),
          ]).apply(before),
          throwsA(isA<CommandRefused>()),
        );
        expect(
          () => const SliceEdit(LayoutAddress('shelf'), [
            MakePrefab('card', 'Card'),
          ]).apply(before),
          throwsA(isA<CommandRefused>()),
        );
      },
    );
  });

  group('the layout as a whole', () {
    test('the removed apps and the inbox are set and undone', () {
      final before = document();
      final result = const SliceEdit(ConfigAddress(), [
        SetRemoved({'app:z'}),
        SetInbox('shelf'),
      ]).apply(before);
      expect(result.document.layout.removed, {'app:z'});
      expect(result.document.layout.inbox, 'shelf');
      final back = undone(result.document, result.inverse);
      expect(back.layout.removed, before.layout.removed);
      expect(back.layout.inbox, before.layout.inbox);
    });
  });
}

void stepFourTests() {
  Document withSettings() => Document(
    layout: document().layout,
    settings: {
      'names': {'a': 'Alpha'},
      'wallpaperEvery': 0,
      'iconOverrides': <String, Object?>{},
    },
    startingLayout: Layout.blank(),
  );

  group('settings', () {
    test('a whole value is set and the old one comes back', () {
      final before = withSettings();
      final result = const SliceEdit(ConfigAddress(), [
        SetSetting('wallpaperEvery', 5),
      ]).apply(before);
      expect(result.document.settings['wallpaperEvery'], 5);
      expect(
        undone(result.document, result.inverse).settings['wallpaperEvery'],
        0,
      );
    });

    test('one entry of a map is set, and taken away again by its undo', () {
      final before = withSettings();
      final result = const SliceEdit(ConfigAddress(), [
        SetEntry('names', 'b', 'Beta'),
        SetEntry('names', 'a', null),
      ]).apply(before);
      expect(result.document.settings['names'], {'b': 'Beta'});
      expect(undone(result.document, result.inverse).settings['names'], {
        'a': 'Alpha',
      });
    });

    test('something that is not a setting is refused', () {
      expect(
        () => const SliceEdit(ConfigAddress(), [
          SetSetting('layout', 1),
        ]).apply(withSettings()),
        throwsA(isA<CommandRefused>()),
      );
      expect(
        () => const SliceEdit(ConfigAddress(), [
          SetEntry('wallpaperEvery', 'x', 1),
        ]).apply(withSettings()),
        throwsA(isA<CommandRefused>()),
      );
    });
  });

  group('the layout as the user\'s own', () {
    test('a reset goes to the starting layout, and its undo brings the user\'s back', () {
      final before = withSettings();
      final reset = const SliceEdit(ConfigAddress(), [
        ResetLayout(),
      ]).apply(before);
      expect(reset.document.layoutIsTheUsers, isFalse);
      final back = undone(reset.document, reset.inverse);
      expect(back.layoutIsTheUsers, isTrue);
      expect(back.layout.toJson(), before.layout.toJson());
    });

    test('a reset with no starting layout is refused', () {
      expect(
        () => const SliceEdit(ConfigAddress(), [
          ResetLayout(),
        ]).apply(Document(layout: document().layout)),
        throwsA(isA<CommandRefused>()),
      );
    });
  });
}
