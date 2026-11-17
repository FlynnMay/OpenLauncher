import 'package:openlauncher_domain/sources/source.dart';
import 'package:test/test.dart';

void main() {
  final source = Source.fromJson({
    'url':
        'https://x.test/f?lat={{location.latitude}}'
        '&unit={{unit}}&k={{settings.key}}',
    'variables': {
      'location': {'type': 'location', 'value': '{{settings.location}}'},
      'unit': {'value': "{{settings.unit??'celsius'}}"},
    },
  })!;

  test('variables round trip', () {
    expect(Source.fromJson(source.toJson()), source);
    expect(source.variables.keys, ['location', 'unit']);
  });

  test('a given value fills its slot, settings slots stay', () {
    final filled = source.askedWith({
      'location': {'latitude': 12.5},
      'unit': 'fahrenheit',
    }, const {})!.request;
    expect(
      filled.address,
      'https://x.test/f?lat=12.5&unit=fahrenheit&k={{settings.key}}',
    );
  });

  test('nothing given reads the default over the settings', () {
    final filled = source
        .askedWith(
          {'location': '', 'unit': null},
          {
            'location': {'latitude': 3},
          },
        )!
        .request;
    expect(filled.address, contains('lat=3&unit=celsius'));
  });

  test('without variables it is itself', () {
    final plain = Source.fromJson({'url': 'https://x.test/a'})!;
    expect(
      identical(plain.askedWith(const {}, const {})!.request, plain),
      isTrue,
    );
  });

  test('a required variable with no value means it cannot be asked', () {
    final needs = Source.fromJson({
      'url': 'https://x.test/{{place}}',
      'variables': {
        'place': {'value': '', 'required': true},
      },
    })!;
    expect(needs.askedWith(const {}, const {}), isNull);
    expect(needs.askedWith({'place': ' '}, const {}), isNull);
    expect(
      needs.askedWith({'place': 'a'}, const {})!.request.address,
      'https://x.test/a',
    );
  });
}
