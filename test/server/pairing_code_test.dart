import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/server/auth.dart';

void main() {
  var now = DateTime(2026, 10, 14);
  PairingCode code() => PairingCode(clock: () => now);

  void failFive(PairingCode pairing) {
    for (var i = 0; i < 5; i++) {
      expect(pairing.take('nope'), PairAttempt.wrong);
    }
  }

  test('there is no code until the TV shows one, and none after', () {
    final pairing = code();
    expect(pairing.value, isNull);
    expect(pairing.take('123456'), PairAttempt.closed);

    pairing.open();
    final shown = pairing.value!;
    pairing.close();
    expect(pairing.take(shown), PairAttempt.closed);
  });

  test('a code pairs once, then a new one is shown', () {
    final pairing = code()..open();
    final shown = pairing.value!;
    expect(pairing.take(shown), PairAttempt.paired);
    expect(pairing.value, isNot(shown));
    expect(pairing.take(shown), PairAttempt.wrong);
  });

  test('locks double with each round of wrong codes', () {
    final pairing = code()..open();

    failFive(pairing);
    expect(pairing.lockedFor, const Duration(seconds: 30));
    expect(pairing.take(pairing.value!), PairAttempt.locked);

    now = now.add(const Duration(seconds: 30));
    expect(pairing.lockedFor, Duration.zero);
    failFive(pairing);
    expect(pairing.lockedFor, const Duration(minutes: 1));

    now = now.add(const Duration(minutes: 1));
    expect(pairing.take(pairing.value!), PairAttempt.paired);

    // A pairing starts the doubling over.
    failFive(pairing);
    expect(pairing.lockedFor, const Duration(seconds: 30));
  });

  test('a lock is never longer than 15 minutes', () {
    final pairing = code()..open();
    for (var round = 0; round < 12; round++) {
      now = now.add(const Duration(hours: 1));
      failFive(pairing);
    }
    expect(pairing.lockedFor, const Duration(minutes: 15));
  });
}
