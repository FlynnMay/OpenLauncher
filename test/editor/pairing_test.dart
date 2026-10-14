import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlauncher/editor/tv/tv.dart';

void main() {
  testWidgets('a session the TV refuses brings up the pairing screen', (
    tester,
  ) async {
    final sent = <http.BaseRequest>[];
    final container = ProviderContainer(
      overrides: [
        tvApiProvider.overrideWith(
          (ref) => TvApi(
            client: MockClient((request) async {
              sent.add(request);
              return http.Response('', 401);
            }),
            onRefused: () => ref.read(pairingNeededProvider.notifier).refused(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: AuthGate(
            child: Consumer(
              builder: (context, ref, _) {
                ref.watch(tvStateProvider);
                return const Text('editor');
              },
            ),
          ),
        ),
      ),
    );
    expect(find.text('editor'), findsOneWidget);

    await tester.pump();
    await tester.pump();
    expect(find.byType(PairScreen), findsOneWidget);
    expect(container.read(tvStateProvider).error, isA<NeedsPairing>());
    // Not retried: only pairing can fix it.
    expect(sent, hasLength(1));
    expect(
      sent.single.headers,
      containsPair('x-requested-with', 'openlauncher'),
    );
  });

  test('a QR link with a code starts on the pairing screen', () {
    final container = ProviderContainer(
      overrides: [initialPairCodeProvider.overrideWithValue('123456')],
    );
    addTearDown(container.dispose);
    expect(container.read(pairingNeededProvider), isTrue);
  });
}
