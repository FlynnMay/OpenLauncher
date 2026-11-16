import 'package:openlauncher_domain/sources/source.dart';
import 'package:test/test.dart';

void main() {
  final source = Source.fromJson({
    'url':
        'https://x.test/f?lat={{param.location.latitude}}'
        '&unit={{param.unit}}&k={{settings.key}}',
    'params': {
      'location': {'type': 'location', 'default': '{{settings.location}}'},
      'unit': {'default': "{{settings.unit??'celsius'}}"},
    },
  })!;

  test('params round trip', () {
    expect(Source.fromJson(source.toJson()), source);
    expect(source.params.keys, ['location', 'unit']);
  });

  test('a given value fills its slot, settings slots stay', () {
    final filled = source.filled(
      source.valuesOf({
        'location': {'latitude': 12.5},
        'unit': 'fahrenheit',
      }, const {}),
    );
    expect(
      filled.address,
      'https://x.test/f?lat=12.5&unit=fahrenheit&k={{settings.key}}',
    );
  });

  test('nothing given reads the default over the settings', () {
    final filled = source.filled(
      source.valuesOf(
        {'location': '', 'unit': null},
        {
          'location': {'latitude': 3},
        },
      ),
    );
    expect(filled.address, contains('lat=3&unit=celsius'));
  });

  test('without params it is itself', () {
    final plain = Source.fromJson({'url': 'https://x.test/a'})!;
    expect(identical(plain.filled(const {}), plain), isTrue);
  });
}
