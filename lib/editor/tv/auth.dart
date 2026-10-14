import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:http/http.dart' as http;

/// Thrown when the TV refuses this browser (401): it must pair.
class NeedsPairing implements Exception {
  const NeedsPairing();

  @override
  String toString() => 'This device is not paired with the TV.';
}

/// Every request to the TV goes through this. The browser sends the session
/// cookie on its own; this adds the header the TV requires on writes and
/// turns a refusal into [NeedsPairing].
class SessionClient extends http.BaseClient {
  SessionClient(this._inner, {this._onRefused});

  final http.Client _inner;
  final void Function()? _onRefused;

  /// Marks a request as the editor's own; see the TV's `Authenticator`.
  static const headers = {'x-requested-with': 'openlauncher'};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(headers);
    final response = await _inner.send(request);
    check(response.statusCode);
    return response;
  }

  /// For a request sent outside this client, such as a file upload.
  void check(int status) {
    if (status != 401) return;
    _onRefused?.call();
    throw const NeedsPairing();
  }

  @override
  void close() => _inner.close();
}

/// Whether this browser must pair. Only the TV knows, so it starts false
/// (unless a QR link brought a code) and a refused request sets it.
final pairingNeededProvider = NotifierProvider<PairingNeeded, bool>(
  PairingNeeded.new,
);

class PairingNeeded extends Notifier<bool> {
  @override
  bool build() => ref.read(initialPairCodeProvider) != null;

  void refused() => state = true;

  void paired() => state = false;
}

/// The pairing code a QR scan put in the page's URL (`#pair=123456`).
final initialPairCodeProvider = Provider<String?>((_) => null);

/// Reads the QR link's code. Call before `runApp`: Flutter rewrites the URL's
/// fragment as it starts.
List<Override> authOverrides() => [
  initialPairCodeProvider.overrideWithValue(
    Uri.splitQueryString(Uri.base.fragment)['pair'],
  ),
];
