import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openlauncher/core/values/value_providers.dart';
import 'package:openlauncher_domain/sources/http_feed.dart';

// ---------------------------------------------------------------------------
// Public
// ---------------------------------------------------------------------------

void main() {
  test('a failed fetch is tried again soon, not after its interval', () {
    fakeAsync((async) {
      final fetches = _CountedFetches(failing: true);
      final container = _containerFetchingWith(fetches);
      container.listen(feedValueProvider(_halfHourly), (_, _) {});
      async.flushMicrotasks();
      expect(fetches.count, 1);

      async.elapse(retryAfterFailure - const Duration(seconds: 1));
      expect(fetches.count, 1);
      async.elapse(const Duration(seconds: 2));
      expect(fetches.count, 2);
    });
  });

  test('a fetch that worked waits its whole interval', () {
    fakeAsync((async) {
      final fetches = _CountedFetches(failing: false);
      final container = _containerFetchingWith(fetches);
      container.listen(feedValueProvider(_halfHourly), (_, _) {});
      async.flushMicrotasks();

      async.elapse(const Duration(minutes: 29));
      expect(fetches.count, 1);
      async.elapse(const Duration(minutes: 2));
      expect(fetches.count, 2);
    });
  });
}

// ---------------------------------------------------------------------------
// Private
// ---------------------------------------------------------------------------

final _halfHourly = HttpFeed(
  'system:weather',
  Uri.parse('https://example.com/forecast'),
  1800,
);

class _CountedFetches {
  _CountedFetches({required this.failing});

  final bool failing;
  var count = 0;

  Future<Object?> fetch(HttpFeed feed) async {
    count++;
    if (failing) throw Exception('No network yet');
    return const {'ok': true};
  }
}

ProviderContainer _containerFetchingWith(_CountedFetches fetches) {
  final container = ProviderContainer(
    overrides: [feedFetcherProvider.overrideWithValue(fetches.fetch)],
  );
  addTearDown(container.dispose);
  return container;
}
