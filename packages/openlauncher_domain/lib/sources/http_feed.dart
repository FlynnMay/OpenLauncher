import 'package:meta/meta.dart';
import 'package:openlauncher_domain/json/shallow_equality.dart';

/// One web source's fetch: what is asked, how often, and what it is known
/// by.
@immutable
class HttpFeed {
  const HttpFeed(
    this.id,
    this.address,
    this.every, {
    this.method = 'GET',
    this.headers = const {},
    this.body,
  });

  /// Bounds of the polling interval, in seconds.
  static const minEvery = 10, maxEvery = 24 * 60 * 60;

  /// A pack's source as `<pack>:<name>`, else the entity it feeds.
  final String id;
  final Uri address;

  /// Polling interval in seconds.
  final int every;

  final String method;

  /// Signed in, so may hold a secret: never leaves the TV.
  final Map<String, String> headers;

  /// Text sent as it is.
  final String? body;

  /// The http(s) address [url] is, or null.
  static Uri? addressOf(Object? url) => switch (url) {
    final String url => switch (Uri.tryParse(url.trim())) {
      final uri?
          when (uri.isScheme('http') || uri.isScheme('https')) &&
              uri.host.isNotEmpty =>
        uri,
      _ => null,
    },
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is HttpFeed &&
      other.id == id &&
      other.address == address &&
      other.every == every &&
      other.method == method &&
      other.body == body &&
      mapsEqual(other.headers, headers);

  @override
  int get hashCode =>
      Object.hash(id, address, every, method, body, headers.length);
}
