import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/operations/operations.dart';

void main() {
  var ran = 0;
  final operation = Operation(
    name: 'launcher://test/do',
    label: 'Do',
    args: const {
      'what': [],
      'mode': ['fast', 'slow'],
    },
    requiredArgs: const {'what'},
    run: (run) async {
      ran++;
      return run.required('what');
    },
  );

  setUp(() => ran = 0);

  test('runs once the required arguments are there', () async {
    expect(await operation.run(const OperationRun({'what': 'x'})), 'x');
    expect(ran, 1);
  });

  test('a missing or empty required argument is refused before it runs', () {
    expect(operation.run(const OperationRun({})), throwsA(isA<BadArguments>()));
    expect(
      operation.run(const OperationRun({'what': ''})),
      throwsA(isA<BadArguments>()),
    );
    expect(ran, 0);
  });

  test('a value outside the allowed ones is refused', () async {
    await expectLater(
      operation.run(const OperationRun({'what': 'x', 'mode': 'wild'})),
      throwsA(isA<BadArguments>()),
    );
    expect(ran, 0);
    await operation.run(const OperationRun({'what': 'x', 'mode': 'fast'}));
    expect(ran, 1);
  });
}
