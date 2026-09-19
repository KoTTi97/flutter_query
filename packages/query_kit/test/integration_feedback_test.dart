/// Regressions from the integrator's second report (BR64, against `87bc25b`).
/// PORTING_NOTES' "Second integration report" says what each one was.
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  test('A: a memo sees state the combiner captures, through keys', () {
    final client = testClient();
    QueryResult<T> of<T>(T value) {
      final key = queryKey();
      client.setQueryData<T>(key, value);
      return QueryObserver<T, T>(
              client, QueryObserverOptions(queryKey: key, enabled: Enabled.no))
          .currentResult;
    }

    final devices = of<List<String>>(const ['Küche', 'Bad']);
    final status = of<bool>(true);
    final memo = CombineMemo<List<String>>();
    var search = 'k';
    var runs = 0;
    List<String> combineNow() => (devices, status).combine(
          (list, online) {
            runs++;
            return [
              for (final name in list)
                if (name.toLowerCase().contains(search)) name,
            ];
          },
          memo: memo,
          keys: [search],
        ).dataOrNull!;

    expect(combineNow(), ['Küche']);
    expect(combineNow(), ['Küche']);
    expect(runs, 1, reason: 'equal keys, same sources: skipped');
    search = 'b';
    expect(combineNow(), ['Bad']);
    expect(runs, 2);
    client.clear();
  });

  testFakeAsync(
      'B: removing a running mutation lets its request settle, so its signal '
      'is not cancelled; cancel() is what cancels it', (time) async {
    final client = testClient();
    final signals = <QueryCancelToken>[];
    final observer = MutationObserver<int, void, void>(client, MutationOptions(
      mutationFnWithContext: (_, context) {
        signals.add(context.signal);
        return Future.delayed(const Duration(seconds: 1), () => 1);
      },
    ));
    Object? outcome;
    unawaited(observer.mutateAsync(null).then((value) {
      outcome = value;
    }, onError: (Object error) {
      outcome = error;
    }));
    await time.flushMicrotasks();
    client.mutationCache.clear();
    await time.advance(const Duration(seconds: 1));
    expect(outcome, 1, reason: 'the in-flight attempt still settles');
    expect(signals.single.isCancelled, isFalse);
    observer.destroy();
    client.clear();
  });

  testFakeAsync(
      'C: a manual write does not reset consecutiveErrorCount, and a '
      'cancelled fetch does not raise it', (time) async {
    final client = testClient();
    final key = queryKey();
    var hang = false;
    final observer = QueryObserver<int, int>(
        client,
        QueryObserverOptions(
          queryKey: key,
          retry: RetryPolicy.never,
          queryFn: (_) => hang
              ? Completer<int>().future
              : Future<int>.error(StateError('down')),
        ));
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    await observer.currentResult.refetch().then((_) {}, onError: (_) {});
    int count() => client.getQueryState<int>(key)!.consecutiveErrorCount;
    expect(count(), 2);

    // An optimistic patch says nothing about the device.
    client.setQueryData<int>(key, 7);
    expect(count(), 2);

    // Nor does a fetch that was cancelled.
    hang = true;
    unawaited(observer.currentResult.refetch().then((_) {}, onError: (_) {}));
    await time.flushMicrotasks();
    await client.cancelQueries(
        filters: QueryFilters(queryKey: key), revert: false);
    expect(client.getQueryState<int>(key)!.error, isA<CancelledError>());
    await time.flushMicrotasks();
    expect(count(), 2);

    unsubscribe();
    client.clear();
  });

  testFakeAsync('MutationOptions.simple takes a function with context',
      (time) async {
    final client = testClient();
    final observer = MutationObserver(
        client,
        MutationOptions.simple(
          mutationFnWithContext: (String name, context) async =>
              '$name ${context.signal.isCancelled}',
        ));
    expect(await observer.mutateAsync('a'), 'a false');
    observer.destroy();
    client.clear();
  });
}
