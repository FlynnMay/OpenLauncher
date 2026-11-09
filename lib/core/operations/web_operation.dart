import 'package:openlauncher/core/operations/operation.dart';
import 'package:openlauncher/core/services/services.dart';

/// Whether [address] is the web's: an `http://` or `https://` address is a
/// request to it, made by the TV, which holds the secrets.
bool isWebAddress(String address) =>
    address.startsWith('http://') || address.startsWith('https://');

/// What running any `http(s)://` address does. The address itself is the
/// `url` argument.
Operation webOperation(HttpService http) => Operation(
  address: 'https://',
  label: 'Make a web request',
  args: {
    'url': const [],
    'method': HttpService.methods,
    'auth': const [],
    'headers': const [],
    'body': const [],
  },
  requiredArgs: const {'url'},
  run: (run) => http.request(
    entityId: run.entityId,
    method: (run.arg('method') ?? 'GET').toUpperCase(),
    url: run.required('url'),
    auth: run.arg('auth'),
    headers: _headersOf(run.args['headers']),
    body: run.args['body'],
  ),
);

Map<String, String> _headersOf(Object? headers) => {
  if (headers is Map)
    for (final MapEntry(:key, :value) in headers.entries) '$key': '$value',
};
