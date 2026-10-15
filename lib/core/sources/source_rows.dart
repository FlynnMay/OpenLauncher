import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/http_feed.dart';
import 'package:openlauncher/core/sources/source.dart';
import 'package:openlauncher/core/sources/source_endpoints.dart';
import 'package:openlauncher/core/values/value_providers.dart';

/// A source, and what its fetch is known by: `<pack>:<name>` for a pack's,
/// so every reader shares one, else the entity it feeds.
typedef SourceAt = ({String id, Source source});

/// A source's answer, read again on its interval or change while watched.
final sourceValueProvider = FutureProvider.autoDispose
    .family<Object?, SourceAt>((ref, at) async {
      final source = at.source;
      if (!source.answeredHere) {
        // The same fetch, size cap and interval for every web source.
        return ref.watch(
          feedValueProvider(HttpFeed(at.id, source.url, source.every ?? 60))
              .future,
        );
      }
      if (source.every case final every?) {
        final again = Timer(Duration(seconds: every), ref.invalidateSelf);
        ref.onDispose(again.cancel);
      }
      final endpoint = sourceEndpoints[source.endpoint];
      if (endpoint == null) throw UnsupportedError('Nothing at ${source.url}');
      return endpoint(ref, source.watch);
    }, retry: (_, _) => null);

/// A source's rows, as its answer changes.
final sourceRowsProvider = FutureProvider.autoDispose
    .family<List<Object?>, SourceAt>(
      (ref, at) async =>
          at.source.rowsOf(await ref.watch(sourceValueProvider(at).future)),
      retry: (_, _) => null,
    );
