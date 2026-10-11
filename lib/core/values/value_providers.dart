import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:openlauncher/core/entities/entity_data.dart';
import 'package:openlauncher/core/values/data_source.dart';
import 'package:openlauncher/core/values/template.dart';
import 'package:openlauncher/core/variables/scope.dart';

/// What time it is. Replaced in tests.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The time, told again as each second (true) or each minute begins.
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

/// Asks a source's web address for its value: what it answers as JSON, or
/// as plain text where it is not JSON. In a browser the TV is asked to ask.
final sourceFetcherProvider = Provider<Future<Object?> Function(DataSource)>(
  (ref) => (source) async {
    final address = source.address;
    if (address == null) {
      throw const FormatException('Not a web address');
    }
    final response = await http
        .get(address, headers: const {'accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw http.ClientException('Status ${response.statusCode}', address);
    }
    if (response.bodyBytes.length > maxSourceBytes) {
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

/// The most a source may answer with.
const maxSourceBytes = 512 * 1024;

/// What a source of the user's last answered, asked again every so often
/// for as long as something shows it.
final sourceValueProvider = FutureProvider.autoDispose
    .family<Object?, DataSource>(
      (ref, source) async {
        // Also asks again after a failure.
        final again = Timer(
          Duration(seconds: source.every),
          ref.invalidateSelf,
        );
        ref.onDispose(again.cancel);
        return ref.watch(sourceFetcherProvider)(source);
      },
      // Once each time it is due, and no more.
      retry: (_, _) => null,
    );

/// What can be read by the id [root]: the data of the entity with that
/// id, or of the component with it that has variables anyone may read.
/// Null while there is neither.
final valueProvider = Provider.autoDispose.family<Object?, String>(
  (ref, root) =>
      ref.watch(entityDataProvider(root)) ??
      ref.watch(componentDataProvider(root)),
);

/// How the template [source] reads now, with nothing in reach but what
/// can be read by its id. Whatever watches it is told only when that
/// changes, however often the values under it do.
final templateProvider = Provider.autoDispose.family<String, String>(
  (ref, source) => valueText(readTemplate(ref.watch, source, const {})),
);
