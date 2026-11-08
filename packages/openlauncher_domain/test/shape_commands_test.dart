import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/layout/screen.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';
import 'package:test/test.dart';

Node card(String id) =>
    Node.of('app:$id', id: id, prefab: 'card', variable: 'what');

Layout home() => Layout(
  inbox: 'p',
  screens: [
    Screen(
      id: 'home',
      root: Node.layout(id: 'p', children: [card('a'), card('b')]),
    ),
  ],
);

Command sentAndRead(Command command) => commandFromJson(command.toJson());

void main() {
  scopeTests();
  libraryTests();
}

void scopeTests() {
  Prefab shelf() => Prefab(
    id: 'shelf',
    name: 'Shelf',
    root: Node.layout(id: 'root', children: [card('a'), card('b')]),
  );

  Document documentWith(Prefab prefab) => Document(
    layout: home(),
    settings: {
      'prefabs': [prefab.toJson()],
    },
    prefabs: {prefab.id: prefab},
  );

  test('a command in a prefab changes only that prefab, and undoes', () {
    final before = documentWith(shelf());
    final command = commandFromJson(
      InPrefab('shelf', null, const RemoveNodes(['a'])).toJson(),
    );
    final after = command.edit(before);
    final saved = Prefab.listFromJson(after.settings['prefabs']).single;
    expect(saved.root.children.map((part) => part.id), ['b']);
    expect(after.layout.toJson(), before.layout.toJson());
    final back = command.undoing(before).edit(after);
    expect(
      Prefab.listFromJson(back.settings['prefabs']).single.root.children,
      hasLength(2),
    );
  });

  test('a prefab that is gone refuses', () {
    expect(
      () => const InPrefab(
        'none',
        null,
        RemoveNodes(['a']),
      ).edit(Document(layout: home())),
      throwsA(isA<CommandRefused>()),
    );
  });
}

void libraryTests() {
  Layout twoContainers() => Layout(
    inbox: 'top',
    startup: const Startup('home'),
    screens: [
      Screen(
        id: 'home',
        root: Node.layout(
          id: 'top',
          children: [
            Node.layout(id: 'shelf', children: [card('a')]),
          ],
        ),
      ),
    ],
  );

  test('a container is made a prefab, and the undo puts it back', () {
    final before = Document(layout: twoContainers(), settings: {'prefabs': []});
    final command = commandFromJson(
      const MakePrefab('shelf', 'made', 'Made').toJson(),
    );
    final after = command.edit(before);
    expect(Prefab.listFromJson(after.settings['prefabs']).single.id, 'made');
    expect(after.layout.node('shelf')!.prefab, 'made');
    final back = command.undoing(before).edit(after);
    expect(back.layout.toJson(), before.layout.toJson());
    expect(back.settings['prefabs'], isEmpty);
  });

  test('the inbox cannot become an instance', () {
    expect(
      () => const MakePrefab(
        'top',
        'made',
        'Made',
      ).edit(Document(layout: twoContainers(), settings: {'prefabs': []})),
      throwsA(isA<CommandRefused>()),
    );
  });

  test('a made prefab is deleted, and its instance unpacked', () {
    final made = const MakePrefab(
      'shelf',
      'made',
      'Made',
    ).edit(Document(layout: twoContainers(), settings: {'prefabs': []}));
    final document = made.copyWith(
      layout: made.layout,
      settings: made.settings,
    );
    final withPrefabs = Document(
      layout: document.layout,
      settings: document.settings,
      prefabs: {
        for (final prefab in Prefab.listFromJson(document.settings['prefabs']))
          prefab.id: prefab,
      },
    );
    final after = const DeletePrefab('made').edit(withPrefabs);
    expect(after.settings['prefabs'], isEmpty);
    expect(after.layout.node('shelf')!.prefab, isNull);
  });
}
