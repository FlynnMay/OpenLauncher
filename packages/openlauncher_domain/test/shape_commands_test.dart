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
  moduleCommandTests();
  leafTests();
  scopeTests();

  test('each command survives JSON and undoes', () {
    final before = home();
    for (final command in [
      const ReshapeNode('a', w: 2, h: 2),
      const SetSizing({'a', 'b'}, 'flex', 1),
      const SetInbox('p'),
    ]) {
      final read = sentAndRead(command) as LayoutCommand;
      expect(read.toJson(), command.toJson());
      final after = read.apply(before);
      expect(read.inverse(before).apply(after).toJson(), before.toJson());
    }
  });

  test('a node that is gone refuses', () {
    expect(
      () => const ReshapeNode('x', w: 1, h: 1).apply(home()),
      throwsA(isA<CommandRefused>()),
    );
    expect(
      () => const SetSizing({'x'}, 'w', 1).apply(home()),
      throwsA(isA<CommandRefused>()),
    );
  });
}

void moduleCommandTests() {
  test('module commands read from JSON, set a value and undo it', () {
    final before = home();
    final document = Document(layout: before);
    final command = commandFromJson(
      const SetModuleValue({'a'}, 'sizing', 'flex', 2).toJson(),
    );
    final after = command.edit(document);
    expect(after.layout.node('a')!.modules['sizing']?['flex'], 2);
    final back = command.undoing(document).edit(after);
    expect(back.layout.toJson(), before.toJson());
  });

  test('unpacking something that is not an instance is refused', () {
    expect(
      () => const UnpackInstance('p').edit(Document(layout: home())),
      throwsA(isA<CommandRefused>()),
    );
  });
}

void leafTests() {
  test('a leaf node can be reshaped and sized', () {
    final leaf = const Node(id: 'leaf');
    final layout = Layout(
      inbox: 'p',
      screens: [
        Screen(
          id: 'home',
          root: Node.layout(id: 'p', children: [leaf]),
        ),
      ],
    );
    expect(const ReshapeNode('leaf', w: 2, h: 2).apply(layout), isNotNull);
    expect(const SetSizing({'leaf'}, 'flex', 1).apply(layout), isNotNull);
  });
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
