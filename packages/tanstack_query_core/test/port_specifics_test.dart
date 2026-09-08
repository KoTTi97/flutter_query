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

  // ---------------------------------------------------------------------------
  // Second review, 2026-09-09.

  testFakeAsync(
      'async onMutate accepts the nullable result its signature declares',
      (time) async {
    final client = testClient();
    var called = false;
    final observer = MutationObserver<int, int, String>(
      client,
      MutationOptions(
        mutationFn: (v) {
          called = true;
          return v;
        },
        // `Future<String?>`, which is not a `Future<String>`.
        onMutate: (v) async => v > 0 ? 'snapshot' : null,
      ),
    );
    expect(await observer.mutateAsync(1), 1);
    expect(called, isTrue);
    expect(observer.currentResult.isSuccess, isTrue);
    client.clear();
  });

  testFakeAsync(
      'a missing mutationFn reaches the error state and the callbacks',
      (time) async {
    final client = testClient();
    var errors = 0;
    final observer = MutationObserver<int, int, void>(
      client,
      MutationOptions(onError: (_, __, ___, ____) => errors++),
    );
    await expectLater(
      observer.mutateAsync(1),
      throwsA(isA<MissingMutationFunctionError>()),
    );
    expect(observer.currentResult.isError, isTrue);
    expect(errors, 1);
    observer.reset();
    client.clear();
  });

  testFakeAsync(
      'a listener that starts the next mutation cannot steal the previous callbacks',
      (time) async {
    final client = testClient();
    final log = <String>[];
    final observer = MutationObserver<int, int, void>(
      client,
      MutationOptions(mutationFn: (v) => v),
    );
    final unsubscribe = observer.subscribe((result) {
      if (result.isSuccess && result.dataOrNull == 1) {
        observer.mutate(
          2,
          callbacks: MutateCallbacks(
            onSuccess: (v, _, __) => log.add('second:$v'),
          ),
        );
      }
    });
    await observer.mutateAsync(
      1,
      callbacks: MutateCallbacks(onSuccess: (v, _, __) => log.add('first:$v')),
    );
    await time.flushMicrotasks();
    expect(log, ['first:1', 'second:2']);
    unsubscribe();
    client.clear();
  });

  testFakeAsync('a scope id cannot collide with an unscoped mutation',
      (time) async {
    final client = testClient();
    final blocker = Completer<int>();
    var secondStarted = false;
    final first = client.mutationCache.build<int, int, void>(
      client,
      client.defaultMutationOptions(
        MutationOptions(mutationFn: (_) => blocker.future),
      ),
    );
    final second = client.mutationCache.build<int, int, void>(
      client,
      client.defaultMutationOptions(
        MutationOptions(
          scope: MutationScope(first.mutationId),
          mutationFn: (v) {
            secondStarted = true;
            return v;
          },
        ),
      ),
    );
    first.execute(1).ignore();
    second.execute(2).ignore();
    await time.flushMicrotasks();
    expect(secondStarted, isTrue);
    blocker.complete(1);
    await time.flushMicrotasks();
    client.clear();
  });

  testFakeAsync('a retry calls the mutationFn set while the mutation ran',
      (time) async {
    final client = testClient();
    var oldCalls = 0;
    var newCalls = 0;
    final observer = MutationObserver<int, int, void>(
      client,
      MutationOptions(
        mutationFn: (_) {
          oldCalls++;
          throw StateError('old');
        },
        retry: RetryPolicy.times(1),
        retryDelay: RetryDelay.fixed(ms(10)),
      ),
    );
    final result = observer.mutateAsync(1);
    result.ignore();
    await time.flushMicrotasks();
    observer.setOptions(MutationOptions(
      mutationFn: (v) {
        newCalls++;
        return v;
      },
      retry: RetryPolicy.times(1),
    ));
    await time.advance(ms(10));
    expect(await result, 1);
    expect(oldCalls, 1);
    expect(newCalls, 1);
    observer.reset();
    client.clear();
  });

  test('the default backoff stays capped however many times it has failed', () {
    final error = StateError('offline');
    for (final attempt in [5, 30, 31, 32, 43, 44, 63, 64, 100, 1 << 40]) {
      expect(
        RetryDelay.defaultValue.resolve(attempt, error),
        const Duration(seconds: 30),
        reason: 'attempt $attempt',
      );
    }
    expect(
        RetryDelay.defaultValue.resolve(0, error), const Duration(seconds: 1));
    expect(
        RetryDelay.defaultValue.resolve(3, error), const Duration(seconds: 8));
    expect(
      const RetryDelay.exponential(base: Duration.zero).resolve(70, error),
      Duration.zero,
    );
  });

  test('equal keys hash equally, nested sets included', () {
    final a = QueryKey([
      {
        [1],
        [1],
        [2]
      }
    ]);
    final b = QueryKey([
      {
        [1],
        [2],
        [2]
      }
    ]);
    final c = QueryKey([
      {
        [2],
        [1],
        [1]
      }
    ]);
    expect(a == b, isFalse);
    expect(a == c, isTrue);
    expect(a.hashCode, c.hashCode);
  });

  testFakeAsync('networkMode.always does not refetch on reconnect by default',
      (time) async {
    final client = testClient();
    client.mount();
    var calls = 0;
    final observer = QueryObserver<int, int>(
      client,
      QueryObserverOptions(
        queryKey: queryKey(),
        queryFn: (_) => ++calls,
        networkMode: NetworkMode.always,
      ),
    );
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(calls, 1);
    client.onlineManager.setOnline(false);
    client.onlineManager.setOnline(true);
    await time.flushMicrotasks();
    expect(calls, 1);
    expect(observer.options.refetchOnReconnect, RefetchOn.never);
    unsubscribe();
    client.unmount();
    client.clear();
  });

  testFakeAsync('removing a failing select recovers to the raw data',
      (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<int>(key, 3);
    final observer = QueryObserver<int, int>(
      client,
      QueryObserverOptions(
        queryKey: key,
        enabled: Enabled.no,
        select: (_) => throw StateError('selector'),
      ),
    );
    expect(observer.currentResult.isError, isTrue);
    observer
        .setOptions(QueryObserverOptions(queryKey: key, enabled: Enabled.no));
    expect(observer.currentResult.isSuccess, isTrue);
    expect(observer.currentResult.dataOrNull, 3);
    client.clear();
  });

  testFakeAsync('a changed select is applied to a retained placeholder',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final placeholder = PlaceholderData<int>.value(2);
    final observer = QueryObserver<int, int>(
      client,
      QueryObserverOptions(
        queryKey: key,
        enabled: Enabled.no,
        placeholderData: placeholder,
        select: (v) => v * 2,
      ),
    );
    expect(observer.currentResult.dataOrNull, 4);
    observer.setOptions(QueryObserverOptions(
      queryKey: key,
      enabled: Enabled.no,
      placeholderData: placeholder,
      select: (v) => v * 3,
    ));
    expect(observer.currentResult.dataOrNull, 6);
    expect(observer.currentResult.isPlaceholderData, isTrue);
    client.clear();
  });

  testFakeAsync('resubscribing after gc joins the current cache entry',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final observer = QueryObserver<int, int>(
      client,
      QueryObserverOptions(
        queryKey: key,
        initialData: InitialData.value(1),
        staleTime: StaleTime.infinite,
        gcTime: GcTime.duration(ms(1)),
      ),
    );
    var unsubscribe = observer.subscribe((_) {});
    unsubscribe();
    await time.advance(ms(2));
    expect(client.queryCache.find(QueryFilters(queryKey: key)), isNull);

    client.setQueryData<int>(key, 2);
    unsubscribe = observer.subscribe((_) {});
    expect(observer.currentResult.dataOrNull, 2);
    expect(identical(observer.currentQuery, client.queryCache.get<int>(key)),
        isTrue);
    unsubscribe();
    client.clear();
  });

  testFakeAsync('InitialData.value(null) seeds a nullable query', (time) async {
    final client = testClient();
    final observer = QueryObserver<String?, String?>(
      client,
      QueryObserverOptions(
        queryKey: queryKey(),
        enabled: Enabled.no,
        initialData: const InitialData.value(null),
      ),
    );
    expect(observer.currentResult.isSuccess, isTrue);
    expect(observer.currentQuery.state.hasData, isTrue);
    expect(observer.currentQuery.state.data, isNull);

    // The callback form keeps upstream's "return undefined to skip" idiom.
    final skipped = QueryObserver<String?, String?>(
      client,
      QueryObserverOptions(
        queryKey: queryKey(),
        enabled: Enabled.no,
        initialData: InitialData.compute(() => null),
      ),
    );
    expect(skipped.currentResult.isPending, isTrue);
    client.clear();
  });

  testFakeAsync('PlaceholderData.value(null) is a placeholder', (time) async {
    final client = testClient();
    final observer = QueryObserver<String?, String?>(
      client,
      QueryObserverOptions(
        queryKey: queryKey(),
        enabled: Enabled.no,
        placeholderData: const PlaceholderData.value(null),
      ),
    );
    expect(observer.currentResult.isSuccess, isTrue);
    expect(observer.currentResult.isPlaceholderData, isTrue);

    final skipped = QueryObserver<String?, String?>(
      client,
      QueryObserverOptions(
        queryKey: queryKey(),
        enabled: Enabled.no,
        placeholderData: PlaceholderData.compute((_, __) => null),
      ),
    );
    expect(skipped.currentResult.isPending, isTrue);
    client.clear();
  });
}
