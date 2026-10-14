import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/editor/tv/token_store.dart';

/// Thrown by the API when this browser has no valid token: it must pair.
class NeedsPairing implements Exception {
  const NeedsPairing();

  @override
  String toString() => 'This device is not paired with the TV.';
}

/// This browser's session token, or null until it pairs. Kept in the
/// browser's storage so it stays trusted across visits.
final authTokenProvider = NotifierProvider<AuthTokenNotifier, String?>(
  AuthTokenNotifier.new,
);

class AuthTokenNotifier extends Notifier<String?> {
  @override
  String? build() => loadToken();

  void set(String? token) {
    saveToken(token);
    state = token;
  }
}

/// The pairing code taken from the page's URL fragment when a QR scan opened
/// it, so it can pair without typing. Overridden in [main].
final initialPairCodeProvider = Provider<String?>((_) => null);
