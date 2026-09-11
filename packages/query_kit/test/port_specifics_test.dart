/// Regressions found by review rather than by a ported upstream case.
///
/// Port-only tests live here rather than in a ported suite, so that one Dart
/// file still maps to one upstream file everywhere else
/// (https://github.com/KoTTi97/flutter_query/issues/18). Each case names the
/// finding it pins down.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:query_kit/query_kit.dart';
import 'package:query_kit/src/retryer.dart';
import 'package:query_kit/src/timers.dart';
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
    // A literal, not `1 << 40`: under dart2js a shift past 32 bits is `0`
    // (fifth review, 2026-09-09).
    for (final attempt in [5, 30, 31, 32, 43, 44, 63, 64, 100, 1000000000000]) {
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
    expect(
        client.queryCache.find(filters: QueryFilters(queryKey: key)), isNull);

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
  fourthReview();
  fifthReviewObserver();
  showcaseFindings();
  eighthReview();
  ninthReview();
}

// -----------------------------------------------------------------------------
// Third review, 2026-09-09 (of `c96921f`). Core findings, each reproduced
// before the fix; the binding's are in
// `query_kit_flutter/test/review_regressions_test.dart`.

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
    expect(
        client.queryCache.find(filters: QueryFilters(queryKey: key)), isNull);
    expect(
      client.queryCache
          .find(filters: QueryFilters(queryKey: key, exact: false)),
      isNotNull,
    );
    // The bulk operations keep their prefix default.
    expect(client.queryCache.findAll(filters: QueryFilters(queryKey: key)),
        hasLength(1));
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
        (previous) => (previous ?? 0) + 10,
        filters: QueryFilters(queryKey: prefix),
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

// -----------------------------------------------------------------------------
// Fourth review, 2026-09-09 (of `65a1da6`). Each finding was reproduced
// against the checkout before anything changed; the finding's number is the
// review's.

int _throwingSelect(int value) => throw StateError('select');

void fourthReview() {
  testFakeAsync(
      'C-Q1: reading a key as a supertype of its data throws QueryDataTypeError',
      (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<int>(key, 1);
    // `Query<int>` is a `Query<int?>` and a `Query<num>` to `is`; both used to
    // pass the cache and fail in `setOptions` with a raw `TypeError`.
    expect(
      () => client.observe<int?, int?>(
        QueryObserverOptions(queryKey: key, enabled: Enabled.no),
      ),
      throwsA(isA<QueryDataTypeError>()),
    );
    expect(
      () => client.query<num>(QueryOptions(queryKey: key, queryFn: (_) => 2)),
      throwsA(isA<QueryDataTypeError>()),
    );
    expect(
      () => client.updateQueriesData<num>(
        (previous) => (previous ?? 0) + 1,
        filters: QueryFilters(queryKey: key),
      ),
      throwsA(isA<QueryDataTypeError>()),
    );
    expect(client.getQueryData<int>(key), 1);
    client.clear();
  });

  test('C-Q2: timer durations are clamped to what setTimeout can hold', () {
    // The real reproduction needs `dart compile js`: under node, a
    // `Timer(Duration(days: 30), …)` fires after 1 ms with a
    // `TimeoutOverflowWarning`, ahead of a 200 ms control timer. The VM's
    // timer is 64-bit, so a VM test can only pin the clamp itself.
    expect(maxTimerDuration.inMilliseconds, 0x7FFFFFFF);
    expect(clampTimerDuration(const Duration(days: 30)), maxTimerDuration);
    expect(clampTimerDuration(maxTimerDuration), maxTimerDuration);
    expect(clampTimerDuration(ms(5)), ms(5));
    expect(clampTimerDuration(Duration.zero), Duration.zero);
  });

  testFakeAsync('C-Q2: gc, refetch interval and retry delay all go through it',
      (time) async {
    final client = testClient();
    const beyond = Duration(days: 30);
    final key = queryKey();
    client.setQueryData<int>(key, 1);
    // A 30-day gc timer, armed as the clamp: it fires at 24.8 days.
    client.queryCache.get<int>(key)!.setOptions(client
        .defaultQueryOptions(QueryOptions<int>(
            queryKey: key, gcTime: const GcTime.duration(beyond)))
        .withRetry(RetryPolicy.never));
    client.queryCache.get<int>(key)!.reset();
    await time.advance(maxTimerDuration - ms(1));
    expect(client.queryCache.get<int>(key), isNotNull);
    await time.advance(ms(1));
    expect(client.queryCache.get<int>(key), isNull);

    var fetches = 0;
    final observer = QueryObserver<int, int>(
      client,
      QueryObserverOptions(
        queryKey: queryKey(),
        queryFn: (_) async => ++fetches,
        refetchInterval: const RefetchInterval.every(beyond),
      ),
    );
    final unsubscribe = observer.subscribe((_) {});
    await time.advance(maxTimerDuration);
    expect(fetches, 2);
    unsubscribe();

    var attempts = 0;
    final retried = client.query<int>(QueryOptions(
      queryKey: queryKey(),
      queryFn: (_) async => ++attempts == 1 ? throw StateError('x') : attempts,
      retry: const RetryPolicy.times(1),
      retryDelay: const RetryDelay.fixed(beyond),
    ));
    await time.advance(maxTimerDuration);
    expect(await retried, 2);
    client.clear();
  });

  testFakeAsyncGuarded(
      'C-Q3: a throwing cache listener neither hangs the fetch nor becomes its error',
      (time, uncaught) async {
    final client = testClient();
    final key = queryKey();
    final unsubscribe = client.queryCache.subscribe((event) {
      if (event is QueryUpdated && event.action is QueryFailedAction) {
        throw StateError('listener');
      }
    });
    final result = client.query<int>(QueryOptions(
      queryKey: key,
      queryFn: (_) async => throw StateError('fetch'),
      retry: const RetryPolicy.times(1),
      retryDelay: const RetryDelay.fixed(Duration.zero),
    ));
    result.ignore();
    await time.advance(ms(1));
    await expectLater(
      result,
      throwsA(isA<StateError>().having((e) => e.message, 'message', 'fetch')),
    );
    final state = client.getQueryState<int>(key)!;
    expect(state.status, QueryStatus.error);
    expect(state.fetchStatus, FetchStatus.idle);
    expect(uncaught.whereType<StateError>().map((e) => e.message),
        contains('listener'));
    unsubscribe();
    client.clear();
  });

  testFakeAsyncGuarded(
      'C-Q3: the mutation cache isolates its listeners the same way',
      (time, uncaught) async {
    final client = testClient();
    final unsubscribe = client.mutationCache.subscribe((event) {
      if (event is MutationUpdated && event.action is MutationFailedAction) {
        throw StateError('listener');
      }
    });
    final observer = MutationObserver<int, int, void>(
      client,
      MutationOptions(
        mutationFn: (_) async => throw StateError('mutate'),
        retry: const RetryPolicy.times(1),
        retryDelay: const RetryDelay.fixed(Duration.zero),
      ),
    );
    // And the observer's own listeners, which sit on the same dispatch path.
    final unsubscribeObserver = observer.subscribe((result) {
      if (result.failureCount > 0) {
        throw StateError('observer listener');
      }
    });
    final result = observer.mutateAsync(1);
    result.ignore();
    await time.advance(ms(1));
    await expectLater(
      result,
      throwsA(isA<StateError>().having((e) => e.message, 'message', 'mutate')),
    );
    expect(observer.currentResult.isError, isTrue);
    expect(
      uncaught.whereType<StateError>().map((e) => e.message),
      containsAll(<String>['listener', 'observer listener']),
    );
    unsubscribe();
    unsubscribeObserver();
    observer.reset();
    client.clear();
  });

  testFakeAsync('C-Q3: a throwing retryer hook rejects the fetch',
      (time) async {
    // The last line of defence, once listeners are isolated: a hook that
    // throws for any other reason settles the future instead of leaking out
    // of `_attempt`'s ignored one.
    final focus = AppFocusManager();
    final online = OnlineManager();
    final failing = Retryer<int>(
      fn: () async => throw StateError('x'),
      focusManager: focus,
      onlineManager: online,
      canRun: () => true,
      retry: const RetryPolicy.times(3),
      retryDelay: const RetryDelay.fixed(Duration.zero),
      onFail: (_, __, ___) => throw ArgumentError('onFail'),
    );
    await expectLater(failing.start(), throwsA(isA<ArgumentError>()));

    online.setOnline(false);
    final pausing = Retryer<int>(
      fn: () async => 1,
      focusManager: focus,
      onlineManager: online,
      canRun: () => true,
      onPause: () => throw ArgumentError('onPause'),
    );
    await expectLater(pausing.start(), throwsA(isA<ArgumentError>()));
    expect(pausing.status, RetryerStatus.rejected);
  });

  testFakeAsync('C-Q4: a standing select error is not a new result per build',
      (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<int>(key, 1);
    QueryObserverOptions<int, int> options() => QueryObserverOptions(
        queryKey: key, enabled: Enabled.no, select: _throwingSelect);
    final observer = QueryObserver<int, int>(client, options());
    final failedAt = observer.currentResult.errorUpdatedAt;
    expect(failedAt, time.now);
    var notifications = 0;
    final unsubscribe = observer.subscribe((_) => notifications++);
    await time.flushMicrotasks();
    notifications = 0;
    for (var i = 0; i < 3; i++) {
      await time.advance(ms(1));
      observer.setOptions(options());
    }
    expect(notifications, 0);
    expect(observer.currentResult.errorUpdatedAt, failedAt);
    unsubscribe();
    client.clear();
  });

  testFakeAsync('C-M1: infinite pages are shared structurally on refetch',
      (time) async {
    final client = testClient();
    final observer =
        InfiniteQueryObserver<List<int>, int, InfiniteData<List<int>, int>>(
      client,
      InfiniteQueryObserverOptions(
        queryKey: queryKey(),
        initialPageParam: 0,
        // A fresh list per page, as any real page is.
        pageFn: (context) async => <int>[context.pageParam, 1],
        getNextPageParam: (_, __, param, ___) => param < 1 ? param + 1 : null,
      ),
    );
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    await observer.fetchNextPage();
    final before = observer.currentResult.dataOrNull!;
    expect(before.pages, hasLength(2));
    await observer.refetch();
    final after = observer.currentResult.dataOrNull!;
    expect(after, same(before));

    // One changed page: the other page's instance survives.
    client.setQueryData<InfiniteData<List<int>, int>>(
      observer.currentQuery.queryKey,
      InfiniteData(pages: <List<int>>[
        <int>[0, 1],
        <int>[1, 2]
      ], pageParams: <int>[
        0,
        1
      ]),
    );
    final changed = observer.currentResult.dataOrNull!;
    expect(changed, isNot(same(before)));
    expect(changed.pages[0], same(before.pages[0]));
    expect(changed.pageParams, same(before.pageParams));
    unsubscribe();
    client.clear();
  });

  testFakeAsync('C-M2: an InfiniteQueryOptions pages through client.query',
      (time) async {
    final client = testClient();
    final data = await client.query(InfiniteQueryOptions<int, int>(
      queryKey: queryKey(),
      initialPageParam: 0,
      pages: 2,
      pageFn: (context) async => context.pageParam,
      getNextPageParam: (_, __, param, ___) => param + 1,
    ));
    expect(data.pages, <int>[0, 1]);
    client.clear();
  });

  testFakeAsync(
      'C-Q5: subscribing to a fetch already running reports it as fetching',
      (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<int>(key, 1);
    final hold = Completer<int>();
    final observer = QueryObserver<int, int>(
      client,
      QueryObserverOptions(queryKey: key, queryFn: (_) => hold.future),
    );
    expect(observer.currentResult.fetchStatus, FetchStatus.idle);
    client.refetchQueries(filters: QueryFilters(queryKey: key)).ignore();
    await time.flushMicrotasks();
    // Joins the running fetch, which dispatches nothing.
    final unsubscribe = observer.subscribe((_) {});
    expect(observer.currentQuery.state.fetchStatus, FetchStatus.fetching);
    expect(observer.currentResult.fetchStatus, FetchStatus.fetching);
    hold.complete(2);
    await time.flushMicrotasks();
    expect(observer.currentResult.dataOrNull, 2);
    unsubscribe();
    client.clear();
  });

  testFakeAsync(
      'C-Q6: an immediate retry cancel rejects instead of pausing offline',
      (time) async {
    final focus = AppFocusManager();
    final online = OnlineManager();
    var pauses = 0;
    final retryer = Retryer<int>(
      fn: () async => throw StateError('x'),
      focusManager: focus,
      onlineManager: online,
      canRun: () => true,
      retry: const RetryPolicy.times(3),
      retryDelay: const RetryDelay.fixed(Duration(seconds: 1)),
      onPause: () => pauses++,
    );
    final result = retryer.start();
    await time.flushMicrotasks();
    online.setOnline(false);
    retryer.cancelRetry(immediately: true);
    await expectLater(result, throwsA(isA<StateError>()));
    expect(pauses, 0);
    expect(time.pendingTimers, 0);
  });

  test('C-Q7: an element that does not fit the incoming list is not shared',
      () {
    // A nested `<Object>[1]` is deep-equal to `<int>[1]`, and the recursion
    // runs untyped: the shared `List<Object>` used to be stored into the
    // `List<List<int>>` copy and throw. (The case first stored an `int` into
    // a `List<double>`, which is no mismatch under dart2js, where `1` and
    // `1.0` are one value — fifth review, 2026-09-09.)
    final previousInner = <Object>[1];
    final previous = <Object>[previousInner];
    final shared = replaceEqualDeep<List<List<int>>>(previous, <List<int>>[
      <int>[1]
    ]);
    expect(shared, [
      [1]
    ]);
    expect(shared, isA<List<List<int>>>());
    expect(shared, isNot(same(previous)));
    expect(shared.single, isNot(same(previousInner)));
    // Elements that fit still share.
    final previousFit = <List<num>>[
      <num>[1, 2]
    ];
    expect(
      replaceEqualDeep<List<List<num>>>(previousFit, <List<num>>[
        <num>[1, 2]
      ]),
      same(previousFit),
    );
  });

  testFakeAsync('C-Q8: find survives a predicate that removes the query',
      (time) async {
    final client = testClient();
    client.setQueryData<int>(queryKey(), 1);
    client.setQueryData<int>(queryKey(), 2);
    expect(
      client.queryCache.find(filters: QueryFilters(predicate: (query) {
        client.queryCache.remove(query);
        return false;
      })),
      isNull,
    );
    expect(client.queryCache.queries, isEmpty);
  });

  testFakeAsync('C-M3: clear() settles a mutation paused offline',
      (time) async {
    final client = testClient();
    client.onlineManager.setOnline(false);
    final observer = MutationObserver<int, int, void>(
      client,
      MutationOptions(mutationFn: (v) async => v),
    );
    final result = observer.mutateAsync(1);
    result.ignore();
    await time.flushMicrotasks();
    expect(observer.currentResult.isPaused, isTrue);
    client.clear();
    await expectLater(result, throwsA(isA<CancelledError>()));
    expect(observer.currentResult.isError, isTrue);
    expect(observer.currentResult.isPaused, isFalse);
    expect(time.pendingTimers, 0);
    // Nothing is left to wake up.
    client.onlineManager.setOnline(true);
    await time.advance(const Duration(minutes: 10));
    expect(observer.currentResult.isError, isTrue);
  });

  testFakeAsync('C-M4: a cancel-refetch resets the failure count',
      (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<String>(key, 'ok1');
    var attempts = 0;
    final hold = Completer<String>();
    final observer = QueryObserver<String, String>(
      client,
      QueryObserverOptions(
        queryKey: key,
        queryFn: (_) async {
          attempts++;
          if (attempts == 1) throw StateError('once');
          return hold.future;
        },
        retry: const RetryPolicy.times(3),
        retryDelay: const RetryDelay.fixed(Duration(seconds: 10)),
      ),
    );
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(observer.currentResult.failureCount, 1);
    observer.refetch(cancelRefetch: true).ignore();
    await time.flushMicrotasks();
    expect(observer.currentResult.failureCount, 0);
    expect(observer.currentResult.failureReason, isNull);
    expect(attempts, 2);
    hold.complete('ok2');
    await time.flushMicrotasks();
    expect(observer.currentResult.dataOrNull, 'ok2');
    unsubscribe();
    client.clear();
  });

  testFakeAsync('C-M5: a default function does not make options unequal',
      (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryDefaults(key, QueryDefaults(queryFn: (_) async => 1));
    final queryOptions = QueryOptions<int>(queryKey: key);
    expect(
      client.defaultQueryOptions(queryOptions),
      client.defaultQueryOptions(queryOptions),
    );
    expect(
      client.defaultQueryObserverOptions<int, int>(
          QueryObserverOptions(queryKey: key)),
      client.defaultQueryObserverOptions<int, int>(
          QueryObserverOptions(queryKey: key)),
    );

    client.setMutationDefaults(
        key, MutationDefaults(mutationFn: (v) async => v));
    final mutationOptions = MutationOptions<int, int, void>(mutationKey: key);
    expect(
      client.defaultMutationOptions(mutationOptions),
      client.defaultMutationOptions(mutationOptions),
    );
    final observer = MutationObserver<int, int, void>(client, mutationOptions);
    await observer.mutateAsync(1);
    var updates = 0;
    final unsubscribe = client.mutationCache.subscribe((event) {
      if (event is MutationObserverOptionsUpdated) updates++;
    });
    observer.setOptions(mutationOptions);
    observer.setOptions(mutationOptions);
    expect(updates, 0);

    // The type check the wrapper exists for still holds, and still names the
    // key where it has one.
    await expectLater(
      client.query<String>(QueryOptions(queryKey: key)),
      throwsA(
          isA<QueryDataTypeError>().having((e) => e.queryKey, 'queryKey', key)),
    );
    unsubscribe();
    observer.reset();
    client.clear();
  });

  testFakeAsync('C-M6: a settled mutation with an observer arms no gc timer',
      (time) async {
    final client = testClient();
    final observer = MutationObserver<int, int, void>(
      client,
      MutationOptions(mutationFn: (v) async => v),
    );
    final unsubscribe = observer.subscribe((_) {});
    await observer.mutateAsync(1);
    expect(time.pendingTimers, 0);
    // The observer leaving is what arms it.
    unsubscribe();
    expect(time.pendingTimers, 1);
    await time.advance(const Duration(minutes: 5));
    expect(client.mutationCache.mutations, isEmpty);
  });

  testFakeAsync('C-M7: the paging flags follow a direct setOptions',
      (time) async {
    final client = testClient();
    final key = queryKey();
    InfiniteQueryObserverOptions<int, int, InfiniteData<int, int>> options(
      int? Function(int page, List<int> pages, int param, List<int> params)
          next,
    ) =>
        InfiniteQueryObserverOptions(
          queryKey: key,
          initialPageParam: 0,
          pageFn: (context) async => context.pageParam,
          getNextPageParam: next,
        );
    final observer = InfiniteQueryObserver<int, int, InfiniteData<int, int>>(
      client,
      options((_, __, ___, ____) => null),
    );
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(observer.hasNextPage, isFalse);

    // Any options carrying the paging behaviour are accepted, and the flags
    // read the new paging half — not a copy kept beside the options.
    final paged = client
        .infiniteObserverOptions(options((_, __, param, ___) => param + 1));
    observer.setOptions(paged);
    expect(observer.hasNextPage, isTrue);
    expect(observer.getOptimisticResult(paged).isSuccess, isTrue);
    await observer.fetchNextPage();
    expect(observer.currentResult.dataOrNull?.pages, <int>[0, 1]);
    unsubscribe();
    client.clear();
  });

  // The API decisions that followed the fourth review (PORTING_NOTES, "API
  // decisions (fourth review)"), one case each, named by the decision.

  test('A4: an infinite copyWith keeps the paging half', () {
    final key = queryKey();
    Future<int> page(InfinitePageContext<int> context) async =>
        context.pageParam;
    final options = InfiniteQueryOptions<int, int>(
      queryKey: key,
      pageFn: page,
      initialPageParam: 0,
      getNextPageParam: (_, __, param, ___) => param + 1,
      maxPages: 3,
      pages: 2,
    );
    final copy =
        options.copyWith(staleTime: StaleTime.infinite, initialPageParam: 5);
    expect(copy, isA<InfiniteQueryOptions<int, int>>());
    expect(copy.staleTime, StaleTime.infinite);
    expect(copy.initialPageParam, 5);
    expect(copy.pageFn, same(page));
    expect(copy.getNextPageParam, same(options.getNextPageParam));
    expect(copy.maxPages, 3);
    expect(copy.pages, 2);
    // An infinite query's function is `pageFn`; its behaviour is derived.
    expect(
      () => options.copyWith(
        queryFn: (_) async =>
            const InfiniteData<int, int>(pages: <int>[], pageParams: <int>[]),
      ),
      throwsArgumentError,
    );

    final observerOptions =
        InfiniteQueryObserverOptions<int, int, InfiniteData<int, int>>(
      queryKey: key,
      pageFn: page,
      initialPageParam: 0,
      getNextPageParam: (_, __, param, ___) => param + 1,
      refetchOnMount: RefetchOn.never,
    );
    final observerCopy = observerOptions.copyWith(maxPages: 4);
    expect(
      observerCopy,
      isA<InfiniteQueryObserverOptions<int, int, InfiniteData<int, int>>>(),
    );
    expect(observerCopy.maxPages, 4);
    expect(observerCopy.pageFn, same(page));
    expect(observerCopy.refetchOnMount, RefetchOn.never);
    // An observer refetches as many pages as the query holds.
    expect(() => observerOptions.copyWith(pages: 1), throwsArgumentError);
  });

  testFakeAsync('A6: continueMutation rejects; resumePaused swallows',
      (time) async {
    final client = testClient();
    MutationObserver<String, void, void> failing() =>
        MutationObserver<String, void, void>(
          client,
          MutationOptions<String, void, void>(
            mutationFn: (_) async => throw Exception('boom'),
            retry: RetryPolicy.never,
          ),
        );

    client.onlineManager.setOnline(false);
    failing().mutate(null);
    await time.flushMicrotasks();
    final mutation = client.mutationCache.mutations.single;
    expect(mutation.state.isPaused, isTrue);

    // Upstream's `continue()` rejects with what the mutation settled on.
    client.onlineManager.setOnline(true);
    Object? caught;
    final continued = mutation.continueMutation();
    unawaited(continued.catchError((Object error) => caught = error));
    await time.flushMicrotasks();
    expect(caught, isException);
    expect(mutation.state.status, MutationStatus.error);
    client.mutationCache.remove(mutation);

    // The cache's `resumePaused` is the caller that swallows it.
    client.onlineManager.setOnline(false);
    failing().mutate(null);
    await time.flushMicrotasks();
    final second = client.mutationCache.mutations.single;
    expect(second.state.isPaused, isTrue);
    client.onlineManager.setOnline(true);
    await client.mutationCache.resumePaused();
    // Settles on the retryer, as upstream's `continue()` does; the error
    // callbacks dispatch the state a few microtasks later.
    await time.flushMicrotasks();
    expect(second.state.status, MutationStatus.error);
    client.clear();
  });

  test('A10: build asserts that a success state carries data', () {
    final client = testClient();
    final options = client.defaultQueryOptions<String>(
        QueryOptions<String>(queryKey: queryKey()));
    expect(
      () => client.queryCache.build<String>(
        client,
        options,
        state: const QueryState<String>(status: QueryStatus.success),
      ),
      throwsA(isA<AssertionError>()),
    );
    // With data it is the persistence door, as documented.
    final query = client.queryCache.build<String>(
      client,
      options,
      state: const QueryState<String>(
        status: QueryStatus.success,
        hasData: true,
        data: 'restored',
      ),
    );
    expect(query.state.data, 'restored');
    client.clear();
  });

  testFakeAsync('A11: a held first page param of null refetches from initial',
      (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<InfiniteData<int, int?>>(
      key,
      const InfiniteData<int, int?>(pages: <int>[7], pageParams: <int?>[null]),
    );
    final params = <int?>[];
    final observer = InfiniteQueryObserver<int, int?, InfiniteData<int, int?>>(
      client,
      InfiniteQueryObserverOptions<int, int?, InfiniteData<int, int?>>(
        queryKey: key,
        initialPageParam: 0,
        pageFn: (context) async {
          params.add(context.pageParam);
          return 1;
        },
        getNextPageParam: (_, __, ___, ____) => null,
      ),
    );
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    // Upstream's `oldPageParams[0] ?? options.initialPageParam`.
    expect(params, <int?>[0]);
    expect(observer.currentResult.dataOrNull?.pageParams, <int?>[0]);
    unsubscribe();
    client.clear();
  });

  test('A15: compute wrappers are equal when their function is', () {
    expect(InitialData<int>.compute(_seed), InitialData<int>.compute(_seed));
    expect(
      InitialData<int>.compute(_seed).hashCode,
      InitialData<int>.compute(_seed).hashCode,
    );
    expect(
        InitialData<int>.compute(() => 1) == InitialData<int>.compute(() => 1),
        isFalse);
    expect(
      PlaceholderData<int>.compute(_placeholder),
      PlaceholderData<int>.compute(_placeholder),
    );
    expect(
      PlaceholderData<int>.compute((_, __) => 1) ==
          PlaceholderData<int>.compute((_, __) => 1),
      isFalse,
    );
  });

  test('A16: getQueriesData throws on a type mismatch, like getQueryData', () {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<int>(key, 1);
    expect(
      () => client.getQueriesData<String>(filters: QueryFilters(queryKey: key)),
      throwsA(isA<QueryDataTypeError>().having((e) => e.queryKey, 'key', key)),
    );
    expect(client.getQueriesData<int>(filters: QueryFilters(queryKey: key)),
        [(key, 1)]);
    client.clear();
  });

  testFakeAsync('A20: a missing query function is not retried', (time) async {
    // No gc timer, so a pending timer could only be the retry backoff (the
    // fetch's `finally` arms collection unconditionally, as upstream does).
    final client = testClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(gcTime: GcTime.never),
      ),
    );
    final observer = QueryObserver<String, String>(
      client,
      QueryObserverOptions<String, String>(
        queryKey: queryKey(),
        retry: RetryPolicy.times(3),
        retryDelay: RetryDelay.fixed(ms(100)),
      ),
    );
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    final result = observer.currentResult;
    expect(result, isA<QueryError<String>>());
    expect(
        (result as QueryError<String>).error, isA<MissingQueryFunctionError>());
    expect(observer.currentQuery.state.fetchStatus, FetchStatus.idle);
    // No backoff pending: the one attempt was the answer.
    expect(time.pendingTimers, 0);
    await time.advance(ms(300));
    expect(observer.currentQuery.state.errorUpdateCount, 1);
    unsubscribe();
    client.clear();
  });
}

int? _seed() => 1;

int? _placeholder(int? previousData, Query<int>? previousQuery) => 1;

// -----------------------------------------------------------------------------
// Fifth review, 2026-09-09 (two reviews of `98443be`, merged): the observer,
// structural-sharing and timer findings. `D<n>` is the first review's
// numbering, `F<nn>` the second's; the review's own reproduction suite is
// `docs/reviews/core-review-2026-09-09/repro_test.dart`, and each case below
// names the R-case it ports.

void fifthReviewObserver() {
  test('D1/F09: ceilToMilliseconds rounds up and never arms a zero timer', () {
    expect(ceilToMilliseconds(const Duration(microseconds: 900)), ms(1));
    expect(ceilToMilliseconds(ms(1)), ms(1));
    expect(ceilToMilliseconds(const Duration(microseconds: 1001)), ms(2));
    expect(
        ceilToMilliseconds(const Duration(milliseconds: 29, microseconds: 600)),
        ms(30));
    expect(ceilToMilliseconds(Duration.zero), ms(1));
    expect(ceilToMilliseconds(-ms(5)), ms(1));
  });

  testFakeAsync(
      'D1/F09 (R16): a stale timer truncated to whole milliseconds still '
      'flips isStale', (time) async {
    final client = testClient();
    late QueryObserver<int, int> observer;
    // fake_async keeps microseconds; a real `Timer` is armed in whole
    // milliseconds. This zone models that boundary, as the review's R16 did.
    runZoned(() {
      observer = client.observe<int, int>(QueryObserverOptions(
        queryKey: queryKey(),
        queryFn: (_) => 1,
        staleTime: const StaleTime.duration(Duration(microseconds: 900)),
      ));
      observer.subscribe((_) {});
    },
        zoneSpecification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) =>
              parent.createTimer(zone, ms(duration.inMilliseconds), callback),
        ));
    await time.flushMicrotasks();
    expect(observer.currentResult.isStale, isFalse);
    await time.advance(ms(2));
    expect(observer.currentResult.isStale, isTrue);
    observer.destroy();
    client.clear();
  });

  testFakeAsync(
      'D1/F09 (R03): a 30-day stale time flips isStale on day 30, past the '
      'web timer clamp', (time) async {
    final client = testClient();
    var notifications = 0;
    final observer = client.observe<int, int>(QueryObserverOptions(
      queryKey: queryKey(),
      queryFn: (_) => 1,
      staleTime: const StaleTime.duration(Duration(days: 30)),
    ));
    observer.subscribe((_) => notifications++);
    await time.flushMicrotasks();
    // The clamp fires the timer on day 24.8; the data is still fresh, and
    // the timer used to stop there.
    await time.advance(const Duration(days: 25));
    expect(observer.currentResult.isStale, isFalse);
    expect(time.pendingTimers, 1, reason: 're-armed for the remainder');
    notifications = 0;
    await time.advance(const Duration(days: 6));
    expect(observer.currentQuery.isStaleByTime(observer.options.staleTime),
        isTrue);
    expect(observer.currentResult.isStale, isTrue);
    expect(notifications, 1);
    observer.destroy();
    client.clear();
  });

  test('D2/D11/F01 (R01): typed bytes survive a second cache write', () {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<Uint8List>(key, Uint8List.fromList([1]));
    client.setQueryData<Uint8List>(key, Uint8List.fromList([2]));
    expect(client.getQueryData<Uint8List>(key), [2]);
    client.clear();
  });

  test('D2/D11/F01: typed data is a leaf — never walked, shared by identity',
      () {
    final previous = Float32List.fromList([1]);
    final changed = Float32List.fromList([2]);
    expect(replaceEqualDeep<Float32List>(previous, changed), same(changed));
    // Equal contents are still `next`: a `Uint8Array` is not a plain array
    // for upstream either, and a byte-by-byte walk is not worth the rebuild
    // it would save.
    final same_ = Float32List.fromList([1]);
    expect(replaceEqualDeep<Float32List>(previous, same_), same(same_));
    expect(replaceEqualDeep<Float32List>(previous, previous), same(previous));
    // Nested in a list, the typed element does not stop the rest sharing.
    final inner = <int>[1, 2];
    final shared = replaceEqualDeep<List<Object>>(
      <Object>[
        inner,
        Uint8List.fromList([1])
      ],
      <Object>[
        <int>[1, 2],
        Uint8List.fromList([1])
      ],
    );
    expect(shared[0], same(inner));
    expect(shared[1], isA<Uint8List>());
  });

  testFakeAsync('D2/D11/F01: a select returning typed bytes survives a refetch',
      (time) async {
    final client = testClient();
    var calls = 0;
    final observer = client.observe<List<int>, Uint8List>(QueryObserverOptions(
      queryKey: queryKey(),
      queryFn: (_) => [1, ++calls],
      select: Uint8List.fromList,
    ));
    observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(observer.currentResult, isA<QuerySuccess<Uint8List>>());
    await observer.refetch();
    final result = observer.currentResult;
    expect(result, isA<QuerySuccess<Uint8List>>(), reason: '$result');
    expect(result.dataOrNull, [1, 2]);
    observer.destroy();
    client.clear();
  });

  test('D2/D11/F01 (R14): a narrow empty list can replace a wider previous one',
      () {
    // Empty against empty is "every element shared", and `<num>[]` is not
    // the caller's `List<double>`: the copy, which is — never `previous`.
    final previous = <num>[];
    final replaced = replaceEqualDeep<List<double>>(previous, <double>[]);
    expect(replaced, isA<List<double>>());
    expect(replaced, isNot(same(previous)));
    // Equal but not the caller's type: the copy, which is.
    final widened = replaceEqualDeep<List<double>>(<num>[1], <double>[1.0]);
    expect(widened, isA<List<double>>());
    expect(widened, [1.0]);
    // Deep-equal and the caller's type: shared.
    final doubles = <double>[1.0];
    expect(
        replaceEqualDeep<List<double>>(doubles, <double>[1.0]), same(doubles));
  });

  test('D10/F02 (R02): structural sharing compares sets as multisets', () {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<Set<List<int>>>(key, {
      [1],
      [1],
      [2]
    });
    client.setQueryData<Set<List<int>>>(key, {
      [1],
      [2],
      [2]
    });
    expect(
      client.getQueryData<Set<List<int>>>(key)!.where((x) => x.single == 2),
      hasLength(2),
    );
    client.clear();
  });

  test('D10/F02: set comparison is symmetric and counts multiplicities', () {
    Set<List<int>> twoOnes() => {
          [1],
          [1],
          [2]
        };
    Set<List<int>> twoTwos() => {
          [1],
          [2],
          [2]
        };
    final a = twoOnes();
    final b = twoTwos();
    expect(replaceEqualDeep<Set<List<int>>>(a, b), same(b));
    expect(replaceEqualDeep<Set<List<int>>>(b, a), same(a));
    // The same multiset, built afresh, is shared.
    expect(replaceEqualDeep<Set<List<int>>>(a, twoOnes()), same(a));
    // Nested in a map and in a list.
    final inMap = <String, Set<List<int>>>{'k': twoOnes()};
    final nextMap = <String, Set<List<int>>>{'k': twoTwos()};
    expect(replaceEqualDeep<Map<String, Set<List<int>>>>(inMap, nextMap),
        same(nextMap));
    expect(
      replaceEqualDeep<Map<String, Set<List<int>>>>(
          inMap, <String, Set<List<int>>>{'k': twoOnes()}),
      same(inMap),
    );
    final inList = <Set<List<int>>>[twoOnes()];
    final sharedList = replaceEqualDeep<List<Set<List<int>>>>(
        inList, <Set<List<int>>>[twoTwos()]);
    expect(sharedList.single, isNot(same(inList.single)));
    expect(sharedList.single.where((x) => x.single == 2), hasLength(2));
  });

  test('N5: map and set comparison shares without copying nested lists', () {
    // No allocation is not observable, but the walk's rules are: depth,
    // typed data and `InfiniteData` compare the same way they share.
    final previous = <String, Object>{
      'pages': const InfiniteData<List<int>, int>(pages: [
        [1]
      ], pageParams: [
        0
      ]),
      'bytes': Uint8List.fromList([1]),
    };
    final equal = <String, Object>{
      'pages': const InfiniteData<List<int>, int>(pages: [
        [1]
      ], pageParams: [
        0
      ]),
      'bytes': previous['bytes']!,
    };
    expect(
        replaceEqualDeep<Map<String, Object>>(previous, equal), same(previous));
    final otherBytes = <String, Object>{
      'pages': previous['pages']!,
      'bytes': Uint8List.fromList([1]),
    };
    expect(replaceEqualDeep<Map<String, Object>>(previous, otherBytes),
        same(otherBytes));
  });

  testFakeAsync(
      'D3/F10 (R15): an observer with no select and another data type is '
      'refused, and the shared query is untouched', (time) async {
    final client = testClient();
    final key = queryKey();
    final good = client.observe<int, int>(
        QueryObserverOptions(queryKey: key, queryFn: (_) => 1));
    expect(
      () => client.observe<int, String>(
          QueryObserverOptions(queryKey: key, queryFn: (_) => 1)),
      throwsArgumentError,
    );
    good.subscribe((_) {});
    await time.flushMicrotasks();
    expect(client.getQueryState<int>(key)!.status, QueryStatus.success);
    expect(good.currentResult, isA<QuerySuccess<int>>());
    // Widening is sound without a select; only an unrelated type is not.
    final widened = client.observe<int, num>(
        QueryObserverOptions(queryKey: key, enabled: Enabled.no));
    expect(widened.currentResult.dataOrNull, 1);
    expect(
      () => good.getOptimisticResult(
          QueryObserverOptions(queryKey: key, queryFn: (_) => 1)),
      returnsNormally,
    );
    good.destroy();
    client.clear();
  });

  testFakeAsync('D3/F10: setOptions dropping the select is refused up front',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final observer = client.observe<int, String>(QueryObserverOptions(
      queryKey: key,
      queryFn: (_) => 1,
      select: (value) => '$value',
    ));
    observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(observer.currentResult.dataOrNull, '1');
    expect(
      () => observer
          .setOptions(QueryObserverOptions(queryKey: key, queryFn: (_) => 2)),
      throwsArgumentError,
    );
    expect(observer.options.select, isNotNull);
    expect(
      () => observer.getOptimisticResult(
          QueryObserverOptions(queryKey: key, queryFn: (_) => 2)),
      throwsArgumentError,
    );
    expect(observer.currentResult.dataOrNull, '1');
    expect(client.getQueryState<int>(key)!.status, QueryStatus.success);
    observer.destroy();
    client.clear();
  });

  testFakeAsync(
      'D4/F08 (R12): a paging option that changes hasNextPage notifies',
      (time) async {
    final client = testClient();
    final key = queryKey();
    InfiniteQueryObserverOptions<int, int, InfiniteData<int, int>> options(
            {required bool more}) =>
        InfiniteQueryObserverOptions(
          queryKey: key,
          pageFn: (context) => context.pageParam,
          initialPageParam: 0,
          getNextPageParam: (_, __, param, ___) => more ? param + 1 : null,
          staleTime: StaleTime.infinite,
        );
    final observer = InfiniteQueryObserver<int, int, InfiniteData<int, int>>(
        client, options(more: true));
    var notifications = 0;
    var hasNextPageWhenNotified = true;
    observer.subscribe((_) {
      notifications++;
      hasNextPageWhenNotified = observer.hasNextPage;
    });
    await time.flushMicrotasks();
    expect(observer.hasNextPage, isTrue);
    notifications = 0;
    // The same paging outcome: nothing to say.
    observer.setInfiniteOptions(options(more: true));
    expect(notifications, 0);
    observer.setInfiniteOptions(options(more: false));
    expect(observer.hasNextPage, isFalse);
    expect(notifications, 1);
    expect(hasNextPageWhenNotified, isFalse);
    observer.destroy();
    client.clear();
  });

  testFakeAsync(
      'D4/F08 (R17): a page fetch changing direction in flight notifies',
      (time) async {
    final client = testClient();
    final response = Completer<int>();
    final observer = InfiniteQueryObserver<int, int, InfiniteData<int, int>>(
      client,
      InfiniteQueryObserverOptions(
        queryKey: queryKey(),
        initialPageParam: 0,
        initialData: const InitialData.value(
            InfiniteData<int, int>(pages: [0], pageParams: [0])),
        pageFn: (_) => response.future,
        getNextPageParam: (_, __, param, ___) => param + 1,
        getPreviousPageParam: (_, __, param, ___) => param - 1,
        staleTime: StaleTime.infinite,
      ),
    );
    var notifications = 0;
    var backwardsWhenNotified = false;
    observer.subscribe((_) {
      notifications++;
      backwardsWhenNotified = observer.isFetchingPreviousPage;
    });
    observer.fetchNextPage().ignore();
    await time.flushMicrotasks();
    expect(observer.isFetchingNextPage, isTrue);
    notifications = 0;
    observer.fetchPreviousPage().ignore();
    await time.flushMicrotasks();
    expect(observer.isFetchingPreviousPage, isTrue);
    expect(notifications, greaterThan(0));
    expect(backwardsWhenNotified, isTrue);
    response.complete(1);
    await time.flushMicrotasks();
    observer.destroy();
    client.clear();
  });
}

// -----------------------------------------------------------------------------
// Found by the showcase (`examples/showcase/`, #25, 2026-09-09): its screens
// exercise every feature through real widgets, and what they find in the
// core is reproduced here before it is fixed.
void showcaseFindings() {
  testFakeAsync(
      'select-and-sharing: an observer without select reports the cache\'s '
      'data as written, so a structuralSharing opt-out reaches the reader',
      (time) async {
    final client = testClient();
    var fetches = 0;
    final observer = client.observe<List<int>, List<int>>(QueryObserverOptions(
      queryKey: queryKey(),
      // A fresh but equal list on every fetch.
      queryFn: (_) async {
        fetches++;
        return <int>[1, 2, 3];
      },
      // The opt-out: the cache keeps the new instance.
      structuralSharing: (_, next) => next,
    ));
    observer.subscribe((_) {});
    await time.advance(Duration.zero);
    final first = observer.currentResult.dataOrNull;
    expect(fetches, 1);

    await observer.refetch();
    await time.advance(Duration.zero);
    final cached = observer.currentQuery.state.data;
    final reported = observer.currentResult.dataOrNull;
    expect(fetches, 2);
    // The cache write honoured the hook …
    expect(identical(cached, first), isFalse);
    // … and the observer hands that instance on, as upstream's no-select
    // branch does (`data = state.data`), instead of re-sharing it against the
    // last result and hiding the opt-out from every reader.
    expect(identical(reported, cached), isTrue);
    client.clear();
  });
}

// -----------------------------------------------------------------------------
// Eighth review, 2026-09-10 (of `56950db`). Core findings, each reproduced
// before the fix; the binding's are in
// `query_kit_flutter/test/review_regressions_test.dart`.

void eighthReview() {
  test('E1 setState refuses a success state with no data', () {
    final client = testClient();
    final query = client.queryCache.build<String>(
      client,
      client.defaultQueryOptions(
        QueryObserverOptions<String, String>(queryKey: queryKey()),
      ),
    );
    // The other half of the persistence door, `QueryCache.build`, has always
    // checked this. Accepting it here left the next observer casting `null`
    // to the data type — and it throws in its *constructor*, into whatever
    // zone is running, leaving a reader that never recovers.
    expect(
      () => query.setState(QueryState<String>(
        status: QueryStatus.success,
        fetchStatus: FetchStatus.idle,
        dataUpdatedAt: DateTime.now(),
        errorUpdatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        fetchFailureCount: 0,
        isInvalidated: false,
      )),
      throwsA(isA<ArgumentError>()),
    );
    client.clear();
  });

  test('E2 one subscriber cannot unsubscribe another with an equal tear-off',
      () {
    final client = testClient();
    final watcher = _CacheWatcher();
    final first = client.queryCache.subscribe(watcher.onEvent);
    final second = client.queryCache.subscribe(watcher.onEvent);
    // In JavaScript two functions are never equal, so upstream's `Set` is
    // only an ordered list. In Dart `watcher.onEvent` is `==` to itself, and
    // the two subscriptions collapsed into one: the first unsubscribe
    // silenced the second.
    first();
    client.setQueryData<String>(queryKey(), 'v');
    expect(watcher.calls, greaterThan(0));
    second();
    client.clear();
  });

  testFakeAsync('E3 a silent cancel that nothing replaces lands idle',
      (time) async {
    final client = testClient();
    final gate = Completer<String>();
    // One key, held: `queryKey()` mints a fresh one on every call.
    final key = queryKey();
    final observer = client.observe<String, String>(QueryObserverOptions(
      queryKey: key,
      queryFn: (_) => gate.future,
    ));
    observer.subscribe((_) {});
    await time.advance(Duration.zero);
    expect(observer.currentResult.fetchStatus, FetchStatus.fetching);

    // Reachable from one public call. Upstream leaves the query `fetching`
    // with nothing running and no way out: it never loads again.
    // Not awaited directly: under fake async the clock has to move for the
    // cancelled fetch to settle.
    client
        .cancelQueries(
          filters: QueryFilters(queryKey: key),
          revert: false,
          silent: true,
        )
        .ignore();
    await time.advance(const Duration(milliseconds: 10));
    expect(observer.currentResult.fetchStatus, FetchStatus.idle);

    observer.destroy();
    if (!gate.isCompleted) {
      gate.complete('late');
    }
    client.clear();
  });

  testFakeAsync('E4 unmount() before mount() leaves the client mountable',
      (time) async {
    final client = testClient();
    // The count used to go to -1, and the next `mount()` took it to 0 and
    // subscribed to nothing: focus and reconnect refetching off for good.
    client.unmount();
    client.mount();
    var fetches = 0;
    final observer = client.observe<String, String>(QueryObserverOptions(
      queryKey: queryKey(),
      queryFn: (_) async {
        fetches += 1;
        return 'v';
      },
      refetchOnWindowFocus: RefetchOn.always,
    ));
    observer.subscribe((_) {});
    await time.advance(Duration.zero);
    final afterSubscribe = fetches;
    client.focusManager.setFocused(false);
    client.focusManager.setFocused(true);
    await time.advance(Duration.zero);
    expect(fetches, afterSubscribe + 1);
    observer.destroy();
    client.unmount();
    client.clear();
  });

  testFakeAsync('E5 a missing mutationFn is not retried', (time) async {
    final client = testClient();
    final observer = MutationObserver<String, int, void>(
      client,
      MutationOptions<String, int, void>(
        retry: const RetryPolicy.times(3),
        retryDelay: const RetryDelay.fixed(Duration(seconds: 10)),
      ),
    );
    observer.subscribe((_) {});
    observer.mutate(1);
    // The query twin has answered at once since the fourth review: a missing
    // function is a configuration error, and retrying only delays the
    // message by the whole backoff. The mutation took 30 seconds to say the
    // same thing.
    await time.advance(Duration.zero);
    expect(observer.currentResult.errorOrNull,
        isA<MissingMutationFunctionError>());
    expect(observer.currentResult.isError, isTrue);
    observer.destroy();
    client.clear();
  });

  testFakeAsyncGuarded(
      'E6 a throwing mutation listener leaves the dispatch intact',
      (time, errors) async {
    final events = <MutationCacheEvent>[];
    final client = testClient();
    client.mutationCache.subscribe(events.add);
    final observer = MutationObserver<String, int, void>(
      client,
      MutationOptions<String, int, void>(mutationFn: (v) async => 'v$v'),
    );
    // The eighth review read the mutation's bare notification loop as the
    // query's missing isolation and expected a throw here to skip the rest
    // of the dispatch. It does not: the listener's error is already isolated
    // below the loop. Pinned so the guarantee stays, and so the asymmetry
    // with `Query._dispatch` is not "fixed" without a reason — the query
    // isolates because recomputing *its* result runs user code
    // (`StaleTime.dynamic`, `Enabled.when`, `PlaceholderData.compute`); a
    // mutation result runs none.
    observer.subscribe((_) => throw StateError('a listener of mine threw'));

    observer.mutate(1);
    await time.advance(const Duration(milliseconds: 10));

    expect(events, isNotEmpty);
    expect(observer.currentResult.dataOrNull, 'v1');
    expect(errors.whereType<StateError>(), isNotEmpty);
    observer.destroy();
    client.clear();
  });
}

/// Two subscriptions passing a tear-off of one method on one object.
class _CacheWatcher {
  int calls = 0;

  void onEvent(QueryCacheEvent event) => calls += 1;
}

// -----------------------------------------------------------------------------
// Ninth review, 2026-09-10 (of `f6a9ddd`): four reviews consolidated on
// 2026-09-11 as C1–C59. Each case keeps the name of the probe that found it
// (deep-dive F/P numbers, release-review R numbers) and was red before its
// fix. C4's cases are in `port_lifecycle_test.dart`.

void ninthReview() {
  // C3 — a throwing cache `onError`/`onSettled` left every caller of the
  // fetch pending forever: the hook ran before the operation was completed
  // and `_settle`'s own future is nobody's.
  for (final hook in ['onError', 'onSettled']) {
    testFakeAsyncGuarded(
        'C3 / F1 (R1) a throwing cache $hook still settles every client.query '
        'caller of a failed fetch', (time, uncaught) async {
      final client = testClient(
        queryCache: QueryCache(
          onError: hook == 'onError'
              ? (_, __, ___) => throw StateError('telemetry')
              : null,
          onSettled: hook == 'onSettled'
              ? (_, __, ___, ____) => throw StateError('telemetry')
              : null,
        ),
      );
      final options = QueryOptions<int>(
        queryKey: queryKey(),
        queryFn: (_) => throw StateError('transport'),
      );
      var first = 'pending';
      var joined = 'pending';
      unawaited(client.query(options).then<void>((_) => first = 'data',
          onError: (Object _) => first = 'error'));
      unawaited(client.query(options).then<void>((_) => joined = 'data',
          onError: (Object _) => joined = 'error'));
      await time.advance(const Duration(minutes: 1));
      expect(client.getQueryState<int>(options.queryKey)!.status,
          QueryStatus.error);
      expect([first, joined], ['error', 'error'],
          reason: 'the operation future must settle whatever the hook does');
      // The hook's failure is its own, reported to the zone once — not the
      // fetch's, and not swallowed.
      expect(uncaught.whereType<StateError>().map((e) => e.message),
          ['telemetry']);
      client.clear();
    });
  }

  testFakeAsyncGuarded(
      'C3 / F1 (R1) a throwing cache onSettled on the SUCCESS path still '
      'settles the caller with the data the cache holds',
      (time, uncaught) async {
    final client = testClient(
      queryCache: QueryCache(
        onSettled: (_, __, ___, ____) => throw StateError('telemetry'),
      ),
    );
    final key = queryKey();
    var outcome = 'pending';
    unawaited(client
        .query<int>(QueryOptions(queryKey: key, queryFn: (_) => 42))
        .then<void>((_) => outcome = 'data',
            onError: (Object _) => outcome = 'error'));
    await time.advance(const Duration(minutes: 1));
    expect(client.getQueryData<int>(key), 42);
    // Upstream's `fetch` would reject with the hook error here and dispatch
    // an error over the data it just wrote; the query's state is what the
    // hook was told about, so the caller sees that state.
    expect(outcome, 'data');
    expect(client.getQueryState<int>(key)!.status, QueryStatus.success);
    expect(
        uncaught.whereType<StateError>().map((e) => e.message), ['telemetry']);
    client.clear();
  });

  testFakeAsyncGuarded(
      'C3 / F1 (R1) await client.invalidateQueries() completes when the cache '
      'onError throws', (time, uncaught) async {
    final client = testClient(
      queryCache: QueryCache(
        onError: (_, __, ___) => throw StateError('telemetry'),
      ),
    );
    var calls = 0;
    final observer = client.observe<int, int>(QueryObserverOptions(
      queryKey: queryKey(),
      queryFn: (_) {
        calls++;
        if (calls > 1) throw StateError('transport');
        return calls;
      },
      retry: RetryPolicy.never,
    ));
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(observer.currentResult.dataOrNull, 1);
    var invalidated = false;
    unawaited(client.invalidateQueries().then((_) => invalidated = true));
    await time.advance(const Duration(minutes: 1));
    expect(observer.currentResult, isA<QueryError<int>>());
    expect(invalidated, isTrue,
        reason: 'invalidateQueries awaits the fetch futures');
    expect(
        uncaught.whereType<StateError>().map((e) => e.message), ['telemetry']);
    unsubscribe();
    client.clear();
  });

  // C5 — a mutation removed from the cache inside the `MutationAdded` event
  // was destroyed before it had a retryer, so nothing stopped the run that
  // followed: the full retry policy ran, and offline it parked for good.
  testFakeAsync(
      'C5 / P5 (R7) a mutation removed from the cache inside the '
      'MutationAdded event does not retry after removal', (time) async {
    final client = testClient();
    var attempts = 0;
    final unsubscribe = client.mutationCache.subscribe((event) {
      if (event is MutationAdded) client.mutationCache.remove(event.mutation);
    });
    final observer = MutationObserver<int, int, void>(
      client,
      MutationOptions(
        mutationFn: (_) {
          attempts++;
          throw StateError('fail');
        },
        retry: const RetryPolicy.times(2),
        retryDelay: const RetryDelay.fixed(Duration(seconds: 1)),
      ),
    );
    observer.mutate(42);
    await time.advance(const Duration(seconds: 3));
    expect(client.mutationCache.mutations, isEmpty);
    expect(attempts, lessThanOrEqualTo(1),
        reason: 'a removed mutation must not keep retrying');
    expect(observer.currentResult.isError, isTrue);
    unsubscribe();
    observer.destroy();
    client.clear();
  });

  testFakeAsync(
      'C5 / P5b (R7) the same through build() + remove() + execute(), with '
      'RetryPolicy.always', (time) async {
    final client = testClient();
    var attempts = 0;
    final mutation = client.mutationCache.build<int, int, void>(
      client,
      client.defaultMutationOptions(MutationOptions(
        mutationFn: (_) {
          attempts++;
          throw StateError('fail');
        },
        retry: RetryPolicy.always,
        retryDelay: const RetryDelay.fixed(Duration(seconds: 1)),
      )),
    );
    client.mutationCache.remove(mutation);
    mutation.execute(1).ignore();
    await time.advance(const Duration(seconds: 30));
    expect(attempts, lessThanOrEqualTo(1));
    expect(time.pendingTimers, 0);
    client.clear();
  });

  testFakeAsync(
      'C5 / P5c (R7) removed from MutationAdded while offline, mutateAsync '
      'still settles', (time) async {
    final client = testClient()..mount();
    client.onlineManager.setOnline(false);
    final unsubscribe = client.mutationCache.subscribe((event) {
      if (event is MutationAdded) client.mutationCache.remove(event.mutation);
    });
    final observer = MutationObserver<int, int, void>(
      client,
      MutationOptions(mutationFn: (v) => v),
    );
    Object? settledWith;
    unawaited(observer.mutateAsync(1).then<void>((_) => settledWith = 'data',
        onError: (Object error) => settledWith = error));
    await time.flushMicrotasks();
    expect(client.mutationCache.mutations, isEmpty);
    // A paused run with its retries cancelled rejects on the spot, as one
    // removed during an async `onMutate` has since the fifth review; nothing
    // is in flight and nothing would ever release it.
    expect(settledWith, isA<CancelledError>());
    client.onlineManager.setOnline(true);
    await time.advance(const Duration(days: 1));
    expect(observer.currentResult.isPaused, isFalse);
    expect(time.pendingTimers, 0);
    unsubscribe();
    observer.destroy();
    client.unmount();
    client.clear();
  });
}
