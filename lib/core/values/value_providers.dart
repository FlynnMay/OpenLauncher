import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:openlauncher_domain/sources/http_feed.dart';

/// The current time. Overridden in tests.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The time, updated each second (true) or each minute.
final tickProvider = Provider.autoDispose.family<DateTime, bool>((
  ref,
  seconds,
) {
  final now = ref.watch(nowProvider)();
  final left = seconds
      ? 1000 - now.millisecond
      : 60000 - now.second * 1000 - now.millisecond;
  final next = Timer(Duration(milliseconds: left), ref.invalidateSelf);
  ref.onDispose(next.cancel);
  return now;
});

/// Fetches a feed's address as JSON, or text if it is not JSON. In a browser
/// the TV fetches it.
final feedFetcherProvider = Provider<Future<Object?> Function(HttpFeed)>(
  (ref) => (feed) async {
    final address = feed.address;
    final response = await http
        .get(address, headers: const {'accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw http.ClientException('Status ${response.statusCode}', address);
    }
    if (response.bodyBytes.length > maxFeedBytes) {
      throw http.ClientException('Too much to take in', address);
    }
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    try {
      return jsonDecode(body);
    } on FormatException {
      return body.trim();
    }
  },
);

/// Largest accepted response.
const maxFeedBytes = 512 * 1024;

/// A feed's latest value, re-fetched on its interval while watched.
final feedValueProvider = FutureProvider.autoDispose.family<Object?, HttpFeed>(
  (ref, feed) async {
    // Also retries after a failure.
    final again = Timer(Duration(seconds: feed.every), ref.invalidateSelf);
    ref.onDispose(again.cancel);
    return ref.watch(feedFetcherProvider)(feed);
  },
  // No extra retries.
  retry: (_, _) => null,
);
