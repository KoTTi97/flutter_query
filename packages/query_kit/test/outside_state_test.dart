/// Port-only: options whose callbacks read state outside the cache (#84).
/// Upstream compares the old and the new `enabled` at the same instant, so a
/// predicate over outside state never reads as changed; here `setOptions`
/// compares against what the observer last *saw*.
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  testFakeAsync(
      'an Enabled.when over outside state takes effect on the next '
      'setOptions, even with the very same options', (time) async {
    final client = testClient();
    var connected = false;
    var fetches = 0;
    final options = QueryObserverOptions<int>(
      queryKey: queryKey(),
      enabled: Enabled.when((_) => connected),
      queryFn: (_) async => ++fetches,
    );
    final observer = QueryObserver<int, int>(client, options);
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(fetches, 0);
    expect(observer.currentResult.isEnabled, isFalse);

    connected = true;
    observer.setOptions(options);
    await time.flushMicrotasks();
    expect(fetches, 1, reason: 're-enabled, and stale: it fetches');
    expect(observer.currentResult.isEnabled, isTrue);

    // And nothing happens when nothing changed.
    observer.setOptions(options);
    await time.flushMicrotasks();
    expect(fetches, 1);

    unsubscribe();
    client.clear();
  });

  testFakeAsync(
      'polling switched off by outside state stops and resumes with '
      'setOptions, through Enabled.when and through RefetchInterval.dynamic',
      (time) async {
    for (final viaEnabled in [true, false]) {
      final client = testClient();
      var writing = false;
      var fetches = 0;
      const second = Duration(seconds: 1);
      final options = QueryObserverOptions<int>(
        queryKey: queryKey(),
        enabled: viaEnabled ? Enabled.when((_) => !writing) : null,
        refetchInterval: viaEnabled
            ? const RefetchInterval.every(second)
            : RefetchInterval.dynamic((_) => writing ? null : second),
        queryFn: (_) async => ++fetches,
      );
      final observer = QueryObserver<int, int>(client, options);
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(second);
      expect(fetches, 2, reason: 'viaEnabled: $viaEnabled');

      writing = true;
      observer.setOptions(options);
      await time.advance(second * 3);
      expect(fetches, 2, reason: 'paused; viaEnabled: $viaEnabled');

      writing = false;
      observer.setOptions(options);
      await time.advance(second);
      expect(fetches, greaterThan(2),
          reason: 'resumed; viaEnabled: $viaEnabled');

      unsubscribe();
      client.clear();
    }
  });
}
