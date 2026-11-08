import 'package:openlauncher_domain/commands/commands.dart';
import 'package:openlauncher_domain/layout/layout_model.dart';
import 'package:openlauncher_domain/layout/screen.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
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
