import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:openlauncher_domain/json/json_decode.dart';
import 'package:openlauncher_domain/sources/http_feed.dart';

// ---------------------------------------------------------------------------
// Public
// ---------------------------------------------------------------------------

final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final tickProvider = Provider.autoDispose.family<DateTime, bool>((
  ref,
  everySecond,
) {
  final now = ref.watch(nowProvider)();
  final left = everySecond
      ? 1000 - now.millisecond
      : 60000 - now.second * 1000 - now.millisecond;
  final next = Timer(Duration(milliseconds: left), ref.invalidateSelf);
  ref.onDispose(next.cancel);
  return now;
});

final feedFetcherProvider = Provider<Future<Object?> Function(HttpFeed)>(
  (ref) =>
      (feed) => _fetchFromWeb(feed).timeout(_longestFetch),
);

const maxFeedBytes = 512 * 1024;

const retryAfterFailure = Duration(seconds: 30);

final feedValueProvider = FutureProvider.autoDispose.family<Object?, HttpFeed>((
  ref,
  feed,
) async {
  final interval = Duration(seconds: feed.every);
  try {
    final value = await ref.watch(feedFetcherProvider)(feed);
    _fetchAgainAfter(ref, interval);
    return value;
  } on Object {
    _fetchAgainAfter(
      ref,
      interval < retryAfterFailure ? interval : retryAfterFailure,
    );
    rethrow;
  }
}, retry: (_, _) => null);

// ---------------------------------------------------------------------------
// Private
// ---------------------------------------------------------------------------

const _longestFetch = Duration(seconds: 15);

Future<Object?> _fetchFromWeb(HttpFeed feed) async {
  final address = feed.address;
  final request = http.Request(feed.method, address)
    ..headers.addAll({
      'accept': 'application/json',
      if (feed.body != null) 'content-type': 'application/json',
      ...feed.headers,
    });
  if (feed.body case final body?) request.body = body;
  final response = await http.Response.fromStream(await request.send());
  if (response.statusCode != 200) {
    throw http.ClientException('Status ${response.statusCode}', address);
  }
  if (response.bodyBytes.length > maxFeedBytes) {
    throw http.ClientException('Too much to take in', address);
  }
  final body = utf8.decode(response.bodyBytes, allowMalformed: true);
  try {
    return await compute(_decodeJson, body);
  } on FormatException {
    return body.trim();
  }
}

Object? _decodeJson(String body) => decodeJson(body, source: 'feed reply');

void _fetchAgainAfter(Ref ref, Duration delay) {
  if (!ref.mounted) return;
  final again = Timer(delay, ref.invalidateSelf);
  ref.onDispose(again.cancel);
}
