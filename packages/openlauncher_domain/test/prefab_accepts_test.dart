import 'package:openlauncher_domain/modules/modules.dart';
import 'package:openlauncher_domain/nodes/nodes.dart';
import 'package:openlauncher_domain/prefabs/prefab.dart';
import 'package:openlauncher_domain/variables/variable.dart';
import 'package:test/test.dart';

void main() {
  Prefab card(String id, List<String> accepts) => Prefab(
    id: id,
    name: id,
    root: Node.layout(
      id: 'root',
      vars: {'source': Variable(null, type: VarType.entity, accepts: accepts)},
    ),
  );

  group('an entity variable', () {
    test('lists the categories it takes, and saves them', () {
      final variable = Variable.fromJson({
        'value': null,
        'type': 'entity',
        'accepts': ['app', 'input'],
      });
      expect(variable.accepts, ['app', 'input']);
      expect(variable.takes('app'), isTrue);
      expect(variable.takes('clock'), isFalse);
      expect(Variable.fromJson(variable.toJson()).accepts, variable.accepts);
    });

    test('takes none by default, and writes nothing for it', () {
      final variable = Variable.fromJson({'value': 1, 'type': 'entity'});
      expect(variable.accepts, isEmpty);
      expect(variable.toJson(), {'value': 1, 'type': 'entity'});
    });

    test('keeps them through the form it is edited in', () {
      final rows = variablesToForm({
        'source': const Variable(null, type: VarType.entity, accepts: ['app']),
      });
      expect(variablesFromForm(rows)['source']!.accepts, ['app']);
    });

    test('an instance without its own takes its prefab', () {
      const own = Variable('x');
      const under = Variable(null, type: VarType.entity, accepts: ['app']);
      expect(own.over(under).accepts, ['app']);
    });
  });

  group('a prefab', () {
    test('is the card of the categories its entity variable lists', () {
      final app = card('app-card', ['app', 'input']);
      expect(app.takes('input'), isTrue);
      expect(app.takes('clock'), isFalse);
      expect(card('plain', []).takes('app'), isFalse);
    });

    test('is found for a category, the first by id', () {
      final prefabs = {
        for (final one in [
          card('b-card', ['app']),
          card('a-card', ['app', 'clock']),
          card('c-card', ['media']),
        ])
          one.id: one,
      };
      expect(cardFor(prefabs, 'app')?.id, 'a-card');
      expect(cardFor(prefabs, 'media')?.id, 'c-card');
      expect(cardFor(prefabs, 'zzz'), isNull);
    });

    test('makes an instance holding the entity', () {
      final instance = card('a', ['app']).instance('system:app/x', id: 'i')!;
      expect(instance.handed, ['system:app/x']);
    });
  });
}
