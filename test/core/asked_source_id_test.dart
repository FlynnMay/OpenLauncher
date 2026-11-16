import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/sources/asked_source_id.dart';

void main() {
  test('is written and read back', () {
    const id = AskedSourceId('system', 'weather', {'unit': 'celsius'});
    expect(id.text, 'system:weather#{"unit":"celsius"}');
    final back = AskedSourceId.parse(id.text)!;
    expect((back.pack, back.source), ('system', 'weather'));
    expect(back.args, id.args);
  });

  test('is not read from what is not written this way', () {
    for (final text in [
      'weather',
      'system:weather',
      'system:weather#',
      'system:weather#[1]',
      'system:weather#{oops',
      'a:b:c#{}',
      'weather#{}',
    ]) {
      expect(AskedSourceId.parse(text), isNull, reason: text);
    }
  });
}
