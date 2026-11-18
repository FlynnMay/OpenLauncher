import 'package:openlauncher_domain/entities/entity_action.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:test/test.dart';

void main() {
  group('a node', () {
    test('is protected as a child, and its modules are private', () {
      final node = Node.fromJson({'id': 'card'});
      expect(node.access, NodeAccess.protected);
      expect(node.accessOfModule('style'), NodeAccess.private);
      expect(node.toJson(), {'id': 'card'});
    });

    test('keeps the levels it was given', () {
      final node = Node.fromJson({
        'id': 'card',
        'access': 'public',
        'moduleAccess': {'style': 'public', 'layout': 'protected'},
      });
      expect(node.access, NodeAccess.public);
      expect(node.accessOfModule('style'), NodeAccess.public);
      expect(node.accessOfModule('layout'), NodeAccess.protected);
      expect(Node.fromJson(node.toJson()).toJson(), node.toJson());
      expect(node.copyWith(name: 'x').access, NodeAccess.public);
      expect(node.withVariant('row').moduleAccess, node.moduleAccess);
    });

    test('ignores a level it does not know, and one that says nothing', () {
      final node = Node.fromJson({
        'id': 'card',
        'access': 'secret',
        'moduleAccess': {'style': 'private', 'layout': 'nope', 'dock': 3},
      });
      expect(node.access, NodeAccess.protected);
      expect(node.moduleAccess, isEmpty);
    });
  });

  group('an action', () {
    test('can be told to run by anyone unless it says', () {
      final action = EntityAction.fromJson({'run': 'os://x'})!;
      expect(action.access, NodeAccess.public);
      expect(action.toJson(), {'run': 'os://x'});
    });

    test('keeps a level it was given', () {
      final action = EntityAction.fromJson({
        'run': 'os://x',
        'access': 'private',
      })!;
      expect(action.access, NodeAccess.private);
      expect(action.toJson()['access'], 'private');
      expect(action, isNot(EntityAction.fromJson({'run': 'os://x'})));
    });
  });
}
