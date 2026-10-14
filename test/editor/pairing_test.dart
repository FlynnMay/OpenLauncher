import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openlauncher/editor/tv/tv.dart';

void main() {
  testWidgets('a token the TV refuses brings back the pairing screen', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        tvApiProvider.overrideWith(
          (ref) => TvApi(
            client: MockClient((_) async => http.Response('', 401)),
            token: () => ref.read(authTokenProvider),
            unpaired: () => ref.read(authTokenProvider.notifier).set(null),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(authTokenProvider.notifier).set('revoked');

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
    expect(container.read(authTokenProvider), isNull);
    expect(container.read(tvStateProvider).error, isA<NeedsPairing>());
  });
}
