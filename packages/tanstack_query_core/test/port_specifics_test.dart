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

  thirdReview();
}

// -----------------------------------------------------------------------------
// Third review, 2026-09-09 (of `c96921f`). Core findings, each reproduced
// before the fix; the binding's are in
// `tanstack_query_flutter/test/review_regressions_test.dart`.

void thirdReview() {
  testFakeAsync('an Enabled.when built per rebuild does not restart polling',
      (time) async {
    final client = testClient();
    final key = queryKey();
    var fetches = 0;
    QueryObserverOptions<int, int> options() => QueryObserverOptions<int, int>(
          queryKey: key,
          queryFn: (_) async => ++fetches,
          // A new closure every call, as a widget's `build` produces.
          enabled: Enabled.when((_) => true),
          staleTime: StaleTime.dynamic((_) => StaleTime.zero),
          refetchInterval:
              const RefetchInterval.every(Duration(milliseconds: 100)),
        );
    final observer = QueryObserver<int, int>(client, options());
    final unsubscribe = observer.subscribe((_) {});
    // Rebuilding every 50 ms, faster than the 100 ms interval: the timer
    // used to be restarted on every rebuild and never fire.
    for (var i = 0; i < 20; i++) {
      await time.advance(const Duration(milliseconds: 50));
      observer.setOptions(options());
    }
    expect(fetches, greaterThanOrEqualTo(10));
    unsubscribe();
    client.clear();
  });

  testFakeAsync('a throwing retry policy fails the fetch instead of hanging it',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final result = client.query<int>(QueryOptions(
      queryKey: key,
      queryFn: (_) async => throw StateError('fetch'),
      retry: RetryPolicy.when((_, __, ___) => throw ArgumentError('policy')),
    ));
    await expectLater(result, throwsA(isA<ArgumentError>()));
    final state = client.getQueryState<int>(key)!;
    expect(state.status, QueryStatus.error);
    expect(state.fetchStatus, FetchStatus.idle);
    expect(state.error, isA<ArgumentError>());

    // The delay is user code as well. (`query` defaults `retry` to never,
    // as upstream's `fetchQuery` does, so one retry has to be asked for.)
    final delayed = client.query<int>(QueryOptions(
      queryKey: queryKey(),
      queryFn: (_) async => throw StateError('fetch'),
      retry: const RetryPolicy.times(1),
      retryDelay: RetryDelay.custom((_, __) => throw ArgumentError('delay')),
    ));
    await expectLater(delayed, throwsA(isA<ArgumentError>()));
    client.clear();
  });

  testFakeAsync('a retry backoff does not outlive cancel or clear',
      (time) async {
    final client = testClient();
    client
        .query<int>(QueryOptions(
          queryKey: queryKey(),
          queryFn: (_) async => throw StateError('boom'),
          retry: const RetryPolicy.times(3),
          retryDelay: const RetryDelay.fixed(Duration(seconds: 30)),
        ))
        .ignore();
    await time.flushMicrotasks();
    expect(time.pendingTimers, greaterThan(0));
    await client.cancelQueries();
    client.clear();
    expect(time.pendingTimers, 0);
  });

  testFakeAsync('a mutation dropped from the cache stops retrying',
      (time) async {
    final client = testClient();
    var attempts = 0;
    final observer = MutationObserver<int, int, void>(
      client,
      MutationOptions(
        mutationFn: (_) async {
          attempts++;
          throw StateError('boom');
        },
        retry: RetryPolicy.always,
        retryDelay: const RetryDelay.fixed(Duration(seconds: 1)),
      ),
    );
    observer.mutate(1);
    await time.flushMicrotasks();
    expect(attempts, 1);
    client.clear();
    // Cut short: the mutation fails with the error it last saw, right away.
    await time.flushMicrotasks();
    expect(observer.currentResult.isError, isTrue);
    expect(time.pendingTimers, 0);
    await time.advance(const Duration(seconds: 40));
    expect(attempts, 1);
  });

  testFakeAsync('a select returning an equal list is not a change',
      (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<List<int>>(key, <int>[1, 2, 3, 4]);
    QueryObserverOptions<List<int>, List<int>> options() =>
        QueryObserverOptions<List<int>, List<int>>(
          queryKey: key,
          enabled: Enabled.no,
          // A fresh list on every call — the canonical selector.
          select: (list) => list.where((e) => e.isEven).toList(),
        );
    final observer = QueryObserver<List<int>, List<int>>(client, options());
    final first = observer.currentResult.dataOrNull;
    var notifications = 0;
    final unsubscribe = observer.subscribe((_) => notifications++);
    await time.flushMicrotasks();
    for (var i = 0; i < 5; i++) {
      observer.setOptions(options());
      await time.flushMicrotasks();
    }
    expect(notifications, 0);
    expect(observer.currentResult.dataOrNull, same(first));

    // The same for the cache write: a refetch bringing back equal data keeps
    // the instance the cache already held. (The write itself still notifies,
    // because `dataUpdatedAt` moved — a background refetch is a change by
    // design, see #15 — but what it reports is the same list.)
    final cached = client.getQueryData<List<int>>(key);
    client.setQueryData<List<int>>(key, <int>[1, 2, 3, 4]);
    await time.flushMicrotasks();
    expect(observer.currentResult.dataOrNull, same(first));
    expect(client.getQueryData<List<int>>(key), same(cached));
    unsubscribe();
    client.clear();
  });

  testFakeAsync('errorUpdatedAt survives the refetch that follows an error',
      (time) async {
    final client = testClient();
    final key = queryKey();
    var fail = true;
    final options = QueryOptions<int>(
      queryKey: key,
      queryFn: (_) async => fail ? throw StateError('x') : 1,
      retry: RetryPolicy.never,
    );
    await expectLater(client.query(options), throwsA(isA<StateError>()));
    final failedAt = client.getQueryState<int>(key)!.errorUpdatedAt;
    expect(failedAt, isNotNull);

    fail = false;
    final refetch = client.query(options);
    expect(client.getQueryState<int>(key)!.errorUpdatedAt, failedAt);
    await refetch;
    final state = client.getQueryState<int>(key)!;
    expect(state.error, isNull);
    expect(state.errorUpdatedAt, failedAt);
    client.clear();
  });

  testFakeAsync('a reset query nobody observes is still collected',
      (time) async {
    final client = testClient(
      defaultOptions: const DefaultOptions(
        queries:
            QueryDefaults(gcTime: GcTime.duration(Duration(milliseconds: 10))),
      ),
    );
    final key = queryKey();
    client.setQueryData<int>(key, 1);
    client.queryCache.get<int>(key)!.reset();
    await time.advance(const Duration(milliseconds: 20));
    expect(client.queryCache.get<int>(key), isNull);
  });

  testFakeAsync('find matches exactly unless told otherwise', (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<int>(key.append(<Object?>[1]), 1);
    expect(client.queryCache.find(QueryFilters(queryKey: key)), isNull);
    expect(
      client.queryCache.find(QueryFilters(queryKey: key, exact: false)),
      isNotNull,
    );
    // The bulk operations keep their prefix default.
    expect(
        client.queryCache.findAll(QueryFilters(queryKey: key)), hasLength(1));
    client.clear();
  });

  testFakeAsync('initial and placeholder values carry value equality',
      (time) async {
    expect(InitialData<String>.value('x'), InitialData<String>.value('x'));
    expect(
        InitialData<String>.value('x'), isNot(InitialData<String>.value('y')));
    expect(
        PlaceholderData<String>.value('x'), PlaceholderData<String>.value('x'));
    expect(
      InitialData<String>.value('x').hashCode,
      InitialData<String>.value('x').hashCode,
    );
  });

  testFakeAsyncGuarded('a throwing listener is not the query\'s error',
      (time, uncaught) async {
    final client = testClient();
    final key = queryKey();
    final observer = QueryObserver<int, int>(
      client,
      QueryObserverOptions(
        queryKey: key,
        queryFn: (_) async => 1,
        retry: RetryPolicy.never,
      ),
    );
    final unsubscribe = observer.subscribe((result) {
      if (result.isSuccess) {
        throw StateError('listener');
      }
    });
    await time.advance(const Duration(milliseconds: 10));
    final state = client.getQueryState<int>(key)!;
    expect(state.status, QueryStatus.success);
    expect(state.data, 1);
    expect(uncaught, hasLength(1));
    expect(uncaught.single, isA<StateError>());
    unsubscribe();
    client.clear();
  });

  testFakeAsync('a map keyed by a collection is rejected as a key part',
      (time) async {
    expect(
      () => QueryKey(<Object?>[
        <Object?, Object?>{
          <int>[1]: 'a'
        }
      ]),
      throwsA(isA<AssertionError>()),
    );
    // Scalar keys are fine, and equal.
    expect(
      QueryKey(<Object?>[
        <int, String>{1: 'a'}
      ]),
      QueryKey(<Object?>[
        <int, String>{1: 'a'}
      ]),
    );
  });

  testFakeAsync('updateQueriesData writes nothing when a type mismatches',
      (time) async {
    final client = testClient();
    final prefix = queryKey();
    client.setQueryData<int>(prefix.append(<Object?>[1]), 1);
    client.setQueryData<String>(prefix.append(<Object?>[2]), 'x');
    client.setQueryData<int>(prefix.append(<Object?>[3]), 3);
    expect(
      () => client.updateQueriesData<int>(
        QueryFilters(queryKey: prefix),
        (previous) => (previous ?? 0) + 10,
      ),
      throwsA(isA<QueryDataTypeError>()),
    );
    expect(client.getQueryData<int>(prefix.append(<Object?>[1])), 1);
    expect(client.getQueryData<int>(prefix.append(<Object?>[3])), 3);
    client.clear();
  });

  testFakeAsync('only the first pending mutation in a scope may run',
      (time) async {
    final client = testClient();
    final gate = Completer<void>();
    MutationOptions<void, int, void> scoped() => MutationOptions(
          scope: const MutationScope('s'),
          mutationFn: (_) => gate.future,
        );
    final a = client.mutationCache.build<void, int, void>(
        client, client.defaultMutationOptions(scoped()));
    final b = client.mutationCache.build<void, int, void>(
        client, client.defaultMutationOptions(scoped()));
    b.execute(2).ignore();
    await time.flushMicrotasks();
    expect(b.state.status, MutationStatus.pending);
    // `a` was built first, but `b` is the first *pending* one.
    expect(client.mutationCache.canRunMutation(a), isFalse);
    expect(client.mutationCache.canRunMutation(b), isTrue);
    gate.complete();
    await time.flushMicrotasks();
    client.clear();
  });

  testFakeAsync('fetching a page is not a refetch', (time) async {
    final client = testClient();
    var hold = Completer<int>();
    final observer = InfiniteQueryObserver<int, int, InfiniteData<int, int>>(
      client,
      InfiniteQueryObserverOptions(
        queryKey: queryKey(),
        initialPageParam: 0,
        pageFn: (context) => hold.future.then((_) => context.pageParam),
        getNextPageParam: (page, pages, param, params) => param + 1,
      ),
    );
    final unsubscribe = observer.subscribe((_) {});
    hold.complete(0);
    await time.flushMicrotasks();
    expect(observer.currentResult.dataOrNull?.pages, <int>[0]);

    hold = Completer<int>();
    observer.fetchNextPage().ignore();
    await time.flushMicrotasks();
    expect(observer.currentResult.isRefetching, isTrue);
    expect(observer.isFetchingNextPage, isTrue);
    expect(observer.isRefetching, isFalse);

    hold.complete(1);
    await time.flushMicrotasks();
    unsubscribe();
    client.clear();
  });

  testFakeAsync('equal infinite options default to equal options',
      (time) async {
    final client = testClient();
    final key = queryKey();
    Future<int> page(InfinitePageContext<int> context) async => 0;
    int? next(int page, List<int> pages, int param, List<int> params) => null;
    InfiniteQueryObserverOptions<int, int, InfiniteData<int, int>> options() =>
        InfiniteQueryObserverOptions(
          queryKey: key,
          initialPageParam: 0,
          pageFn: page,
          getNextPageParam: next,
          maxPages: 3,
        );
    expect(
      client.defaultQueryObserverOptions(
        client.infiniteObserverOptions(options()),
      ),
      client.defaultQueryObserverOptions(
        client.infiniteObserverOptions(options()),
      ),
    );
  });

  testFakeAsync('a plain setOptions on an infinite observer is refused',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final observer = InfiniteQueryObserver<int, int, InfiniteData<int, int>>(
      client,
      InfiniteQueryObserverOptions(
        queryKey: key,
        initialPageParam: 0,
        pageFn: (context) async => context.pageParam,
        getNextPageParam: (page, pages, param, params) => null,
      ),
    );
    expect(
      () => observer.setOptions(
        QueryObserverOptions<InfiniteData<int, int>, InfiniteData<int, int>>(
          queryKey: key,
        ),
      ),
      throwsUnsupportedError,
    );
    client.clear();
  });

  testFakeAsyncGuarded('a throwing cancel callback does not skip the rest',
      (time, uncaught) async {
    final token = QueryCancelToken();
    var second = false;
    token
      ..onCancel(() => throw StateError('first'))
      ..onCancel(() => second = true);
    token.cancel();
    expect(second, isTrue);
    expect(uncaught.single, isA<StateError>());
  });

  testFakeAsync('a mutation that fails after succeeding drops its data',
      (time) async {
    final client = testClient();
    var fail = false;
    final mutation = client.mutationCache.build<int, int, void>(
      client,
      client.defaultMutationOptions(MutationOptions(
        mutationFn: (v) async => fail ? throw StateError('x') : v,
        retry: RetryPolicy.never,
      )),
    );
    await mutation.execute(1);
    expect(mutation.state.hasData, isTrue);
    fail = true;
    await expectLater(mutation.execute(2), throwsA(isA<StateError>()));
    expect(mutation.state.status, MutationStatus.error);
    expect(mutation.state.hasData, isFalse);
    expect(mutation.state.data, isNull);
    client.clear();
  });

  testFakeAsync('each client owns its notify manager', (time) async {
    expect(
      identical(QueryClient().notifyManager, QueryClient().notifyManager),
      isFalse,
    );
    expect(
      QueryClient(notifyManager: NotifyManager.shared).notifyManager,
      same(NotifyManager.shared),
    );
  });
}
