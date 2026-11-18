import 'package:openlauncher_domain/entities/entity.dart';
import 'package:openlauncher_domain/entities/entity_node.dart';
import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:test/test.dart';

void main() {
  const app = {
    'id': 'system:app/com.example.tv',
    'category': 'app',
    'label': 'Example',
    'name': 'Example TV',
    'placed': true,
    'data': {
      'package': 'com.example.tv',
      'shape': 'banner',
      'nested': {'a': 1},
    },
    'actions': {
      'open': {
        'run': 'os://apps/launch',
        'with': {'package': '{{self.package}}'},
        'label': 'Open',
        'access': 'protected',
      },
    },
  };

  group('an entity as a node', () {
    test('keeps what it was: the label, the category, the inbox', () {
      final node = nodeFromEntityJson(app)!;
      expect(node.id, 'system:app/com.example.tv');
      expect(node.name, 'Example');
      expect(node.category, 'app');
      expect(node.inbox, isTrue);
      expect(node.isInstance, isFalse);
    });

    test('has its data as public variables and the device name as one', () {
      final node = nodeFromEntityJson(app)!;
      expect(node.vars['package']!.value, 'com.example.tv');
      expect(node.vars['package']!.access, NodeAccess.public);
      expect(node.vars['nested']!.value, {'a': 1});
      expect(node.vars[deviceNameKey]!.value, 'Example TV');
    });

    test('has a device name that is its label unless said', () {
      final node = nodeFromEntityJson({'id': 'x', 'label': 'Lamp'})!;
      expect(node.vars[deviceNameKey]!.value, 'Lamp');
    });

    test('has actions and a feed as modules', () {
      final node = nodeFromEntityJson({...app, 'feed': 'launcher://clock'})!;
      expect(node.actions['open']!.run, 'os://apps/launch');
      expect(node.actions['open']!.access, NodeAccess.protected);
      expect(node.feed!.name, 'launcher://clock');
      expect(node.has('actions'), isTrue);
      expect(node.has('feed'), isTrue);
    });

    test('has a feed written in place', () {
      final node = nodeFromEntityJson({
        'id': 'x',
        'feed': {'url': 'https://x.test', 'every': 60},
      })!;
      expect(node.feed!.inline, {'url': 'https://x.test', 'every': 60});
    });

    test('writes the JSON it was read from', () {
      for (final json in [
        app,
        {...app, 'feed': 'launcher://clock'},
        {'id': 'x', 'label': 'Lamp'},
        {
          'id': 'y',
          'feed': {'url': 'https://x.test'},
          'data': {'text': 'hi'},
        },
      ]) {
        expect(
          entityJsonOf(nodeFromEntityJson(json)!),
          Entity.fromJson(json)!.toJson(),
        );
      }
    });

    test('is nothing without an id', () {
      expect(nodeFromEntityJson({'label': 'x'}), isNull);
      expect(nodeFromEntityJson('x'), isNull);
    });
  });

  group('a node', () {
    test('saves its category and inbox only when set', () {
      expect(Node.fromJson({'id': 'a'}).toJson(), {'id': 'a'});
      final json = {'id': 'a', 'category': 'app', 'inbox': true};
      expect(Node.fromJson(json).toJson(), json);
    });

    test('keeps them when copied', () {
      final node = Node.fromJson({'id': 'a', 'category': 'c', 'inbox': true});
      final copy = node.copyWith(name: 'n').withVariant('v');
      expect((copy.category, copy.inbox), ('c', true));
    });

    test('is not offered feed or actions as modules to add', () {
      for (final name in ['feed', 'actions']) {
        expect(moduleNamed(name)!.use, ModuleUse.generated);
      }
    });
  });
}
