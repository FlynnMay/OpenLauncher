import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/entities/http_feed.dart';
import 'package:openlauncher/core/sources/os_sources.dart';
import 'package:openlauncher/core/sources/source.dart';
import 'package:openlauncher/core/values/value_providers.dart';

/// A pack's source: `<pack>:<name>`, and what it says.
typedef SourceAt = ({String id, Source source});

/// A source's rows, read again on its interval or change while watched.
final sourceRowsProvider = FutureProvider.autoDispose
    .family<List<Object?>, SourceAt>((ref, at) async {
      final source = at.source;
      if (!source.onDevice) {
        // The same fetch, size cap and interval as an `http` feed.
        return source.rowsOf(
          await ref.watch(
            feedValueProvider(HttpFeed(at.id, source.url, source.every ?? 60))
                .future,
          ),
        );
      }
      if (source.every case final every?) {
        final again = Timer(Duration(seconds: every), ref.invalidateSelf);
        ref.onDispose(again.cancel);
      }
      final query = osSources[source.url.host];
      if (query == null) throw UnsupportedError('No ${source.url}');
      return source.rowsOf(await query(ref, source.watch));
    }, retry: (_, _) => null);
