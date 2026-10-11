import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/entities/entity.dart';

/// The feed that asks a web address.
const httpFeed = 'http';

/// The `http` feed of one entity: what is asked, and how often.
@immutable
class HttpFeed {
  const HttpFeed(this.id, this.address, this.every);

  /// Bounds of the polling interval, in seconds.
  static const minEvery = 10, maxEvery = 24 * 60 * 60;

  /// The entity it is for.
  final String id;
  final Uri address;

  /// Polling interval in seconds.
  final int every;

  /// The http(s) address [url] is, or null.
  static Uri? addressOf(Object? url) => switch (url) {
    final String url => switch (Uri.tryParse(url.trim())) {
      final uri? when uri.isScheme('http') || uri.isScheme('https') => uri,
      _ => null,
    },
    _ => null,
  };

  /// Null unless [entity] has an `http` feed with a web address.
  static HttpFeed? of(Entity entity) {
    final feed = entity.feed;
    if (feed == null || feed.from != httpFeed) return null;
    final address = addressOf(feed.options['url']);
    if (address == null) return null;
    return HttpFeed(entity.id, address, switch (feed.options['every']) {
      final num every => every.toInt().clamp(minEvery, maxEvery),
      _ => 60,
    });
  }

  @override
  bool operator ==(Object other) =>
      other is HttpFeed &&
      other.id == id &&
      other.address == address &&
      other.every == every;

  @override
  int get hashCode => Object.hash(id, address, every);
}
