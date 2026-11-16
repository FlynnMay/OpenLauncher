import 'package:openlauncher_domain/variables/variable.dart';
import 'package:test/test.dart';

void main() {
  final location = Variable.fromJson({'value': '', 'type': 'system:location'});
  final weather = Variable.fromJson({
    'value': 'system:weather',
    'type': 'entity',
    'with': {'location': '{{location}}', 'unit': '{{unit}}'},
  });

  test('a type that is no plain one is a premade field', () {
    expect(location.type, VarType.field);
    expect(location.field, 'system:location');
    expect(Variable.fromJson({'value': 1, 'type': 'number'}).field, isNull);
    expect(location.toJson(), {'value': '', 'type': 'system:location'});
  });

  test('an entity says what it is asked with', () {
    expect(weather.type, VarType.entity);
    expect(weather.args, {'location': '{{location}}', 'unit': '{{unit}}'});
    expect(Variable.fromJson(weather.toJson()).args, weather.args);
  });

  test('an instance value keeps the type, field and arguments', () {
    final own = location.withValue({'name': 'Perth'});
    expect((own.type, own.field), (VarType.field, 'system:location'));
    expect(own.value, {'name': 'Perth'});
  });

  test(
    'the form keeps a field type, its value and what an entity is asked with',
    () {
      final form = variablesToForm({
        'location': Variable(
          {'name': 'Perth'},
          type: VarType.field,
          field: 'system:location',
        ),
        'source': weather,
      });
      expect(form[0]['type'], 'system:location');
      expect(form[0]['value'], {'name': 'Perth'});
      expect(form[1]['with'], [
        {'name': 'location', 'value': '{{location}}'},
        {'name': 'unit', 'value': '{{unit}}'},
      ]);
      final back = variablesFromForm(form);
      expect(back['location']!.field, 'system:location');
      expect(back['location']!.value, {'name': 'Perth'});
      expect(back['source']!.args, weather.args);
    },
  );

  test('an instance value of the same type is asked as its prefab asks', () {
    const own = Variable('system:weather', type: VarType.entity);
    expect(own.over(weather).args, weather.args);
    const none = Variable('x', type: VarType.number);
    expect(none.over(weather).args, isEmpty);
    expect(
      Variable(
        'y',
        type: VarType.entity,
        args: const {'a': '1'},
      ).over(weather).args,
      {'a': '1'},
    );
  });
}
