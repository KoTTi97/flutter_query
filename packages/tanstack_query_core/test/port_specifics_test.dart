/// Regressions found by review rather than by a ported upstream case.
///
/// Port-only tests live here rather than in a ported suite, so that one Dart
/// file still maps to one upstream file everywhere else
/// (https://github.com/KoTTi97/flutter_query/issues/18). Each case names the
/// finding it pins down.
library;

import 'dart:async';

import 'package:tanstack_query_core/tanstack_query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  testFakeAsync('nullable query replaces previous non-null data', (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<String?>(key, 'old');
    final returned = await client
        .query<String?>(QueryOptions(queryKey: key, queryFn: (_) => null));
    expect(returned, isNull);
    expect(client.getQueryState<String?>(key)!.hasData, isTrue);
    expect(client.getQueryData<String?>(key), isNull);
    client.clear();
  });
  testFakeAsync('infinite stale time still respects explicit invalidation',
      (time) async {
    final client = testClient();
    final key = queryKey();
    var count = 0;
    final options = QueryOptions<int>(
        queryKey: key, queryFn: (_) => ++count, staleTime: StaleTime.infinite);
    expect(await client.query(options), 1);
    await client.invalidateQueries(
        filters: QueryFilters(queryKey: key), refetchType: RefetchType.none);
    expect(await client.query(options), 2);
    client.clear();
  });
  testFakeAsync('infinite page retry resumes from failed page', (time) async {
    final client = testClient();
    final calls = <int>[];
    var failed = false;
    final result = client.infiniteQuery<int, int>(InfiniteQueryOptions(
      queryKey: queryKey(),
      initialPageParam: 0,
      pages: 3,
      getNextPageParam: (page, pages, param, params) => param + 1,
      retry: RetryPolicy.times(1),
      retryDelay: RetryDelay.fixed(Duration.zero),
      pageFn: (context) {
        calls.add(context.pageParam);
        if (context.pageParam == 1 && !failed) {
          failed = true;
          throw StateError('transient failure');
        }
        return context.pageParam;
      },
    ));
    await time.advance(Duration.zero);
    expect((await result).pages, [0, 1, 2]);
    expect(calls, [0, 1, 1, 2]);
    client.clear();
  });
  testFakeAsync(
      'infinite fetch without signal consumption populates cache after unsubscribe',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final response = Completer<int>();
    final observer = InfiniteQueryObserver<int, int, InfiniteData<int, int>>(
        client,
        InfiniteQueryObserverOptions(
            queryKey: key,
            initialPageParam: 0,
            getNextPageParam: (_, __, ___, ____) => null,
            pageFn: (_) => response.future));
    final unsub = observer.subscribe((_) {});
    await time.flushMicrotasks();
    unsub();
    response.complete(123);
    await time.flushMicrotasks();
    expect(client.getQueryData<InfiniteData<int, int>>(key)?.pages, [123]);
    client.clear();
  });
  testFakeAsync('cancelled retry cannot set query to paused after its delay',
      (time) async {
    final client = testClient();
    final key = queryKey();
    client
        .query<int>(QueryOptions(
            queryKey: key,
            queryFn: (_) => throw StateError('failed'),
            retry: RetryPolicy.times(1),
            retryDelay: RetryDelay.fixed(Duration(seconds: 1))))
        .ignore();
    await time.flushMicrotasks();
    await client.cancelQueries();
    expect(client.getQueryState<int>(key)!.fetchStatus, FetchStatus.idle);
    client.onlineManager.setOnline(false);
    await time.advance(Duration(seconds: 1));
    expect(client.getQueryState<int>(key)!.fetchStatus, FetchStatus.idle);
    client.clear();
  });
}
