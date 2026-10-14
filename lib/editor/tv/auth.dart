import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:http/http.dart' as http;

/// The TV answered 401.
class NeedsPairing implements Exception {
  const NeedsPairing();

  @override
  String toString() => 'This device is not paired with the TV.';
}

/// Adds the write header and turns a 401 into [NeedsPairing]. The browser
/// sends the cookie itself.
class SessionClient extends http.BaseClient {
  SessionClient(this._inner, {this._onRefused});

  final http.Client _inner;
  final void Function()? _onRefused;

  static const headers = {'x-requested-with': 'openlauncher'};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(headers);
    final response = await _inner.send(request);
    check(response.statusCode);
    return response;
  }

  /// For requests sent outside this client (uploads).
  void check(int status) {
    if (status != 401) return;
    _onRefused?.call();
    throw const NeedsPairing();
  }

  @override
  void close() => _inner.close();
}

/// Starts false, as only the TV knows, unless a QR link brought a code.
final pairingNeededProvider = NotifierProvider<PairingNeeded, bool>(
  PairingNeeded.new,
);

class PairingNeeded extends Notifier<bool> {
  @override
  bool build() => ref.read(initialPairCodeProvider) != null;

  void refused() => state = true;

  void paired() => state = false;
}

/// From the QR link's `#pair=`.
final initialPairCodeProvider = Provider<String?>((_) => null);

/// Call before `runApp`: Flutter rewrites the URL fragment on start.
List<Override> authOverrides() => [
  initialPairCodeProvider.overrideWithValue(
    Uri.splitQueryString(Uri.base.fragment)['pair'],
  ),
];
