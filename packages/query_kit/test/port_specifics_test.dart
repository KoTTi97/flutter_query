/// Regressions found by review rather than by a ported upstream case.
///
/// Port-only tests live here rather than in a ported suite, so that one Dart
/// file still maps to one upstream file everywhere else
/// (https://github.com/KoTTi97/flutter_query/issues/18). Each case names the
/// finding it pins down.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:query_kit/query_kit.dart';
import 'package:query_kit/src/retryer.dart';
import 'package:query_kit/src/structural_sharing.dart' show sharingBucketOf;
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
      QuerySelectOptions(
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
      QuerySelectOptions(
        queryKey: key,
        enabled: Enabled.no,
        placeholderData: placeholder,
        select: (v) => v * 2,
      ),
    );
    expect(observer.currentResult.dataOrNull, 4);
    observer.setOptions(QuerySelectOptions(
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

  testFakeAsync(
      'AR-03: InitialData.compute is consulted on every options update until '
      'the query holds data, as upstream does', (time) async {
    final client = testClient();
    String? seed;
    var calls = 0;
    final options = QueryObserverOptions<String>(
      queryKey: queryKey(),
      queryFn: (_) async => throw StateError('boom'),
      retry: RetryPolicy.never,
      initialData: InitialData<String>.compute(() {
        calls++;
        return seed;
      }),
    );

    // One call from `QueryCache.build`, one from the observer's own
    // `setOptions` — upstream's constructor and `#currentQuery.setOptions`.
    final observer = client.observe<String, String>(options);
    expect(calls, 2);
    for (var i = 0; i < 100; i++) {
      observer.setOptions(options);
    }
    expect(calls, 102);
    final unsubscribe = observer.subscribe((_) {});
    expect(calls, 103, reason: 'a fetch passes options through setOptions');
    await time.advance(ms(10));
    final query = observer.currentQuery;
    expect(query.state.status, QueryStatus.error);
    expect(calls, 103);

    // A seed that becomes available replaces an error held without data, as
    // upstream's `successState` does (TanStack/query#9743): a late seed is
    // data the query never had, and the counters say what happened.
    seed = 'late';
    observer.setOptions(options);
    expect(calls, 104);
    expect(query.state.status, QueryStatus.success);
    expect(query.state.data, 'late');
    expect(query.state.error, isNull);
    expect(query.state.dataUpdateCount, 0);
    expect(query.state.errorUpdateCount, 1);
    expect(query.resetState.data, 'late');

    // Once the query holds data the callback is never consulted again — not
    // by a rebuild, and not by a fetch that fails.
    for (var i = 0; i < 100; i++) {
      observer.setOptions(options);
    }
    observer.refetch().ignore();
    await time.advance(ms(10));
    expect(query.state.status, QueryStatus.error);
    expect(query.state.data, 'late');
    expect(calls, 104);
    unsubscribe();
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
  fidelityReview();
  finalReview();
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
    QueryObserverOptions<int> options() => QueryObserverOptions<int>(
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
      retryDelay: RetryDelay.dynamic((_, __) => throw ArgumentError('delay')),
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
    QuerySelectOptions<List<int>, List<int>> options() =>
        QuerySelectOptions<List<int>, List<int>>(
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
    InfiniteQueryObserverOptions<int, int> options() =>
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
        QueryObserverOptions<InfiniteData<int, int>>(
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
    QuerySelectOptions<int, int> options() => QuerySelectOptions(
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
    InfiniteQueryObserverOptions<int, int> options(
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
            InfiniteData<int, int>(pages: <int>[], pageParams: <int>[]),
      ),
      throwsArgumentError,
    );

    final observerOptions = InfiniteQueryObserverOptions<int, int>(
      queryKey: key,
      pageFn: page,
      initialPageParam: 0,
      getNextPageParam: (_, __, param, ___) => param + 1,
      refetchOnMount: RefetchOn.never,
    );
    final observerCopy = observerOptions.copyWith(maxPages: 4);
    expect(
      observerCopy,
      isA<InfiniteQueryObserverOptions<int, int>>(),
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

    // Upstream's `continue()` rejects with what the mutation settled on, and
    // so does this one. The future is `execute`'s, which completes after the
    // error callbacks have run (ninth review, C10), not the retryer's
    // transport future, which completed before the first of them.
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
    // Settles *after* the callbacks, not on the retryer: since C10 the future
    // `continueMutation` hands back is `execute`'s own, so by the time this
    // await returns the error callbacks have run and the state has moved —
    // which is what `resumePausedMutations` promises a reconnect refetch
    // queued behind it.
    expect(second.state.status, MutationStatus.error);
    await time.flushMicrotasks();
    client.clear();
  });

  test('A10: build refuses a success state that carries no data', () {
    final client = testClient();
    final options = client.defaultQueryOptions<String>(
        QueryOptions<String>(queryKey: queryKey()));
    // An `ArgumentError` in every build mode since the ninth review (C8); it
    // was an `assert` here, which a release build skipped.
    expect(
      () => client.queryCache.build<String>(
        client,
        options,
        state: const QueryState<String>(status: QueryStatus.success),
      ),
      throwsArgumentError,
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
      InfiniteData<int, int?>(pages: <int>[7], pageParams: <int?>[null]),
    );
    final params = <int?>[];
    final observer = InfiniteQueryObserver<int, int?, InfiniteData<int, int?>>(
      client,
      InfiniteQueryObserverOptions<int, int?>(
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
    // No gc timer, so a pending timer could only be the retry backoff:
    // `GcTime.never` arms none, and the fetch's `finally` arms one only when
    // the query has no observers left — where upstream arms it
    // unconditionally (`query.ts:818`) — and this query keeps its observer
    // for the whole case (comment corrected in the pre-release review,
    // 2026-09-12).
    final client = testClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(gcTime: GcTime.never),
      ),
    );
    final observer = QueryObserver<String, String>(
      client,
      QueryObserverOptions<String>(
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
    final observer = client.observe<List<int>, Uint8List>(QuerySelectOptions(
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

  test(
      'AR-09: an element type the copy refused once does not stop a later '
      'element that fits', () {
    // `_Wide(1) == _Narrow(1)`, so the walk shares `previous`'s `_Wide` into
    // a `List<_Narrow>` copy, which refuses it; the refusal is remembered per
    // runtime type, and the `_Narrow` at index 1 is still shared.
    final previous = <_Wide>[_Wide(1), _Narrow(2)];
    final next = <_Narrow>[_Narrow(1), _Narrow(2)];
    final result = replaceEqualDeep<List<_Wide>>(previous, next);
    expect(result, isA<List<_Narrow>>());
    expect(result, isNot(same(previous)));
    expect(result[0], same(next[0]));
    expect(result[1], same(previous[1]));
    // The all-refused case on the VM: a `List<double>` copy with `next`'s
    // values. On the web an `int` is a `double`, nothing is refused and
    // `previous` itself comes back — equal either way, so only the values
    // are pinned here (R14 pins the VM shape).
    final widened =
        replaceEqualDeep<List<num>>(<int>[1, 2, 3], <double>[1.0, 2.0, 3.0]);
    expect(widened, [1.0, 2.0, 3.0]);
  });

  test(
      'AR-01: a set of value-equal members is shared by its own equality, '
      'whatever its order', () {
    final client = testClient();
    final key = queryKey();
    final ids = <int>{1, 2, 3};
    client.setQueryData<Set<int>>(key, ids);
    client.setQueryData<Set<int>>(key, <int>{3, 2, 1});
    expect(client.getQueryData<Set<int>>(key), same(ids));
    client.setQueryData<Set<int>>(key, <int>{1, 2, 4});
    expect(client.getQueryData<Set<int>>(key), isNot(same(ids)));
    expect(client.getQueryData<Set<int>>(key), <int>{1, 2, 4});
    client.clear();
    // `1 == 1.0` and both hash alike: shared, as the walk always said.
    final nums = <num>{1, 2};
    expect(replaceEqualDeep<Set<num>>(nums, <num>{1.0, 2.0}), same(nums));
    // A set of lists still goes through the deep walk, still as multisets.
    final lists = <List<int>>{
      [1],
      [1],
      [2]
    };
    expect(
        replaceEqualDeep<Set<List<int>>>(lists, <List<int>>{
          [2],
          [1],
          [1]
        }),
        same(lists));
    expect(
        replaceEqualDeep<Set<List<int>>>(lists, <List<int>>{
          [2],
          [2],
          [1]
        }),
        isNot(same(lists)));
  });

  test(
      'AR-01: a key with a set part compares by the set\'s own equality '
      'first, and hashes consistently', () {
    final a = QueryKey(<Object?>[
      'tasks',
      <int>{1, 2, 3}
    ]);
    final b = QueryKey(<Object?>[
      'tasks',
      <int>{3, 2, 1}
    ]);
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
    expect(
        a,
        isNot(equals(QueryKey(<Object?>[
          'tasks',
          <int>{1, 2, 4}
        ]))));
    // Sets of lists — distinct members under the set's equality — are still
    // multisets, and `==` still agrees with `hashCode`.
    final twoOnes = QueryKey(<Object?>[
      <List<int>>{
        [1],
        [1],
        [2]
      }
    ]);
    final twoOnesAgain = QueryKey(<Object?>[
      <List<int>>{
        [2],
        [1],
        [1]
      }
    ]);
    final twoTwos = QueryKey(<Object?>[
      <List<int>>{
        [1],
        [2],
        [2]
      }
    ]);
    expect(twoOnes, equals(twoOnesAgain));
    expect(twoOnes.hashCode, twoOnesAgain.hashCode);
    expect(twoOnes, isNot(equals(twoTwos)));
    final client = testClient();
    client.setQueryData<int>(a, 1);
    expect(client.getQueryData<int>(b), 1);
    client.clear();
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
      'pages': InfiniteData<List<int>, int>(pages: [
        [1]
      ], pageParams: [
        0
      ]),
      'bytes': Uint8List.fromList([1]),
    };
    final equal = <String, Object>{
      'pages': InfiniteData<List<int>, int>(pages: [
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
    // Since ADR-0001 a plain shape has one slot, so `QueryObserver<int,
    // String>` without a select is a compile error at every natural call
    // site; the one way past the types is covariance — a
    // `QueryObserverOptions<Never>` is a `QueryObserverOptionsBase<int,
    // String>` — and the observer still refuses it at the door.
    expect(
      () => client
          .observe<int, String>(QueryObserverOptions<Never>(queryKey: key)),
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
    final observer = client.observe<int, String>(QuerySelectOptions(
      queryKey: key,
      queryFn: (_) => 1,
      select: (value) => '$value',
    ));
    observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(observer.currentResult.dataOrNull, '1');
    // The plain shape reaches an `<int, String>` observer only as
    // `QueryObserverOptions<Never>` (see D3/F10 above).
    expect(
      () => observer.setOptions(QueryObserverOptions<Never>(queryKey: key)),
      throwsArgumentError,
    );
    expect(observer.options.select, isNotNull);
    expect(
      () => observer
          .getOptimisticResult(QueryObserverOptions<Never>(queryKey: key)),
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
    InfiniteQueryObserverOptions<int, int> options({required bool more}) =>
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
        initialData: InitialData.value(
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
        QueryObserverOptions<String>(queryKey: queryKey()),
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
    // with nothing running until something calls `fetch()` again: its own
    // `finally` clears `#retryer` (`query.ts:813-816`), so the next fetch
    // does start and dispatches its way out — the state is wrong in the
    // meantime, and every read of it in between reports a fetch that is not
    // happening, which is why `idle` is the better answer here (comment
    // corrected in the pre-release review, 2026-09-12: it said "for good").
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
  // C1 — one type slot for a plain query, two for a select (ADR-0001). The
  // old `QueryObserverOptions<TQueryData, TData>` carried `TData` only in its
  // optional `select`, so a literal without one inferred `TData` to `dynamic`
  // and put a `Query<dynamic>` in the cache. Now the plain shape has one
  // slot, anchored by `queryFn`, and the select shape's `select` is required
  // — a `QuerySelectOptions` without one is a compile error
  // (`missing_required_argument`), which is documented rather than tested.
  testFakeAsync('C1: a plain literal makes a QueryObserver<int, int>',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final observer = QueryObserver(
        client, QueryObserverOptions(queryKey: key, queryFn: (_) async => 1));
    expect(observer, isA<QueryObserver<int, int>>());
    expect(client.queryCache.find(filters: QueryFilters(queryKey: key)),
        isA<Query<int>>());
    observer.destroy();
    client.clear();
  });

  testFakeAsync('C1: a select literal makes a QueryObserver<int, String>',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final observer = QueryObserver(
        client,
        QuerySelectOptions(
            queryKey: key, queryFn: (_) async => 1, select: (n) => '$n'));
    expect(observer, isA<QueryObserver<int, String>>());
    expect(client.queryCache.find(filters: QueryFilters(queryKey: key)),
        isA<Query<int>>());
    observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(observer.currentResult.dataOrNull, '1');
    observer.destroy();
    client.clear();
  });

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

  // C6 — an observer's unsubscribe handle called twice removed *another*
  // registration of the same listener and ran the last-listener teardown
  // under a subscriber still present. `Subscribable` already guarded.
  testFakeAsync(
      'C6 / F2 (R2) a QueryObserver unsubscribe handle called twice does not '
      'remove another registration of the same listener', (time) async {
    final client = testClient();
    final key = queryKey();
    final observer = client.observe<int, int>(
        QueryObserverOptions(queryKey: key, enabled: Enabled.no));
    var notifications = 0;
    void listener(QueryResult<int> _) => notifications++;
    final first = observer.subscribe(listener);
    final second = observer.subscribe(listener);
    notifications = 0;
    first();
    first();
    client.setQueryData(key, 42);
    expect(observer.hasListeners, isTrue,
        reason: 'the second registration is still subscribed');
    expect(notifications, 1);
    expect(time.pendingTimers, 0,
        reason: 'a subscribed observer keeps the gc timer off');
    second();
    client.clear();
  });

  testFakeAsync(
      'C6 / P1 (R2) a MutationObserver unsubscribe handle called twice '
      'removes nothing the second time', (time) async {
    final client = testClient();
    final observer = MutationObserver<int, int, void>(
        client, MutationOptions(mutationFn: (value) => value));
    final seen = <MutationStatus>[];
    void listener(MutationResult<int, int> result) => seen.add(result.status);
    final first = observer.subscribe(listener);
    final second = observer.subscribe(listener);
    first();
    first();
    expect(observer.hasListeners, isTrue,
        reason: 'the second registration must survive the first handle '
            'being called twice');
    await observer.mutateAsync(42);
    expect(seen, contains(MutationStatus.success));
    second();
    observer.destroy();
    client.clear();
  });

  // C7 — one memo keyed on (function, data type) served the query wrapper
  // and the mutation wrapper of one default function from the same slot.
  test(
      'C7 / F4 / P4a (R6) one function as query default and mutation '
      'default: the adapted wrappers do not collide (either order)', () {
    Object? common(Object? value) => 42;
    for (final queryFirst in [true, false]) {
      final client = testClient(
        defaultOptions: DefaultOptions(
          queries: QueryDefaults(queryFn: common),
          mutations: MutationDefaults(mutationFn: common),
        ),
      );
      void queries() =>
          client.defaultQueryOptions<int>(QueryOptions(queryKey: queryKey()));
      void mutations() => client
          .defaultMutationOptions<int, String, void>(const MutationOptions());
      if (queryFirst) {
        expect(queries, returnsNormally);
        expect(mutations, returnsNormally, reason: 'query first');
      } else {
        expect(mutations, returnsNormally);
        expect(queries, returnsNormally, reason: 'mutation first');
      }
      client.clear();
    }
  });

  testFakeAsync(
      'C7 / P4b (R6) mutation default first, then query default: the query '
      'calls the query wrapper with its context', (time) async {
    final client = testClient();
    final seen = <Object?>[];
    Object? common(Object? value) {
      seen.add(value);
      return 42;
    }

    client.setDefaultOptions(DefaultOptions(
      queries: QueryDefaults(queryFn: common),
      mutations: MutationDefaults(mutationFn: common),
    ));
    final mutationOptions = client
        .defaultMutationOptions<int, String, void>(const MutationOptions());
    expect(await mutationOptions.mutationFn!('vars'), 42);
    expect(seen.last, 'vars');
    expect(await client.query<int>(QueryOptions(queryKey: queryKey())), 42);
    expect(seen.last, isA<QueryFunctionContext>());
    client.clear();
  });

  // C8 — `build(state:)` only asserted; a release build accepted the state
  // and the next observer died on `type 'Null' is not a subtype of 'int'`.
  test(
      'C8 / F5 (R11) build(state:) rejects a success state without data the '
      'way setState does: an ArgumentError, not an assert', () {
    final client = testClient();
    final key = queryKey();
    expect(
      () => client.queryCache.build<int>(
        client,
        client.defaultQueryOptions(QueryOptions<int>(queryKey: key)),
        state: const QueryState<int>(status: QueryStatus.success),
      ),
      throwsArgumentError,
    );
    expect(client.queryCache.queries, isEmpty);
    client.clear();
  });

  // C9 — a removed query's silent cancel put its fetch status back to idle
  // with a dispatch, *after* the cache's `QueryRemoved`.
  testFakeAsync(
      'C9 / F6 clear() during a fetch: no QueryUpdated after QueryRemoved',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final events = <String>[];
    client.queryCache.subscribe((event) {
      final action =
          event is QueryUpdated ? ':${event.action.runtimeType}' : '';
      events.add('${eventName(event)}$action');
    });
    final gate = Completer<int>();
    client
        .query<int>(QueryOptions(queryKey: key, queryFn: (_) => gate.future))
        .ignore();
    await time.flushMicrotasks();
    client.clear();
    await time.flushMicrotasks();
    final removedAt = events.lastIndexOf('removed');
    expect(removedAt, isNonNegative);
    expect(events.sublist(removedAt + 1), isEmpty,
        reason: 'events after removal: $events');
    client.clear();
  });

  testFakeAsync(
      'C9 / F6 removeQueries() during a fetch: a subscribed observer is not '
      'notified from a query that already left the cache', (time) async {
    final client = testClient();
    final key = queryKey();
    final gate = Completer<int>();
    final observer = client.observe<int, int>(QueryObserverOptions(
      queryKey: key,
      queryFn: (_) => gate.future,
    ));
    final results = <QueryResult<int>>[];
    final unsubscribe = observer.subscribe(results.add);
    await time.flushMicrotasks();
    final removedEvents = <QueryCacheEvent>[];
    client.queryCache.subscribe((event) {
      if (event is QueryUpdated && event.query.queryKey == key) {
        removedEvents.add(event);
      }
    });
    client.removeQueries(filters: QueryFilters(queryKey: key));
    final before = results.length;
    await time.flushMicrotasks();
    expect(removedEvents, isEmpty,
        reason: 'a removed query dispatched: '
            '${removedEvents.map((e) => (e as QueryUpdated).action)}');
    expect(results.length, before);
    unsubscribe();
    client.clear();
  });

  // C13 — the paging flags were only re-asked when the paging functions
  // changed, on the assumption that an equal result means equal data; a
  // `select` that collapses the change broke it.
  testFakeAsync(
      'C13 / P1 (R5) hasNextPage flips on a same-timestamp write whose '
      'selected result is unchanged: the listener is told', (time) async {
    final client = testClient();
    final key = queryKey();
    final stamp = DateTime.utc(2026);
    client.setQueryData(
        key, InfiniteData<int, int>(pages: [1], pageParams: [0]),
        updatedAt: stamp);
    final observer = InfiniteQueryObserver<int, int, int>(
      client,
      InfiniteQuerySelectOptions(
        queryKey: key,
        pageFn: (_) => 1,
        initialPageParam: 0,
        getNextPageParam: (last, _, __, ___) => last == 1 ? 1 : null,
        select: (data) => data.pages.length,
        enabled: Enabled.no,
      ),
    );
    var notifications = 0;
    final unsubscribe = observer.subscribe((_) => notifications++);
    client.setQueryData(
        key, InfiniteData<int, int>(pages: [1], pageParams: [0]),
        updatedAt: stamp);
    notifications = 0;
    expect(observer.hasNextPage, isTrue);
    client.setQueryData(
        key, InfiniteData<int, int>(pages: [2], pageParams: [0]),
        updatedAt: stamp);
    expect(observer.hasNextPage, isFalse);
    expect(notifications, 1,
        reason: 'hasNextPage flipped true -> false; upstream carries it on '
            'the result and would have notified');
    unsubscribe();
    client.clear();
  });

  testFakeAsync('C13 / P11 (R5) hasPreviousPage flips the same way',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final stamp = DateTime.utc(2026);
    client.setQueryData(
        key, InfiniteData<int, int>(pages: [1], pageParams: [0]),
        updatedAt: stamp);
    final observer = InfiniteQueryObserver<int, int, int>(
      client,
      InfiniteQuerySelectOptions(
        queryKey: key,
        pageFn: (_) => 1,
        initialPageParam: 0,
        getNextPageParam: (_, __, ___, ____) => null,
        getPreviousPageParam: (first, _, __, ___) => first == 1 ? -1 : null,
        select: (data) => data.pages.length,
        enabled: Enabled.no,
      ),
    );
    var notifications = 0;
    final unsubscribe = observer.subscribe((_) => notifications++);
    client.setQueryData(
        key, InfiniteData<int, int>(pages: [1], pageParams: [0]),
        updatedAt: stamp);
    notifications = 0;
    expect(observer.hasPreviousPage, isTrue);
    client.setQueryData(
        key, InfiniteData<int, int>(pages: [2], pageParams: [0]),
        updatedAt: stamp);
    expect(observer.hasPreviousPage, isFalse);
    expect(notifications, 1);
    unsubscribe();
    client.clear();
  });

  // C14 — the `select` memo compared with `identical` while the options
  // compare with `==`: an instance-method tear-off re-ran on every
  // `setOptions` that changed nothing.
  testFakeAsync(
      'C14 / P12 an instance-method tear-off select is not re-run per '
      'setOptions (== but not identical)', (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData(key, <int>[1, 2, 3]);
    final selector = _Selector();
    QuerySelectOptions<List<int>, int> options() =>
        QuerySelectOptions<List<int>, int>(
          queryKey: key,
          enabled: Enabled.no,
          select: selector.length,
        );
    final observer = QueryObserver<List<int>, int>(client, options());
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    final before = selector.calls;
    var events = 0;
    final unsubscribeCache = client.queryCache.subscribe((event) {
      if (event is QueryObserverOptionsUpdated) events++;
    });
    for (var i = 0; i < 5; i++) {
      observer.setOptions(options());
    }
    unsubscribeCache();
    expect(events, 0, reason: 'defaulted options compare select by ==');
    expect(selector.calls - before, 0,
        reason: 'tear-off select was re-run on each setOptions');
    expect(observer.currentResult.dataOrNull, 3);
    unsubscribe();
    client.clear();
  });

  // C16 — `onCancel` on an already-cancelled token ran the callback
  // unisolated, so its throw escaped into the query function registering
  // it; `cancel()`'s loop had isolated and reported to the zone all along.
  testFakeAsyncGuarded(
      'C16 / O3 onCancel on an already-cancelled token isolates a throwing '
      'callback like the loop path does', (time, uncaught) async {
    final token = QueryCancelToken();
    token.cancel();
    expect(
        () => token.onCancel(() => throw StateError('late')), returnsNormally);
    await time.flushMicrotasks();
    expect(uncaught.whereType<StateError>(), hasLength(1));
  });

  // C20 — the `InfiniteData` a fetch wrote held two growable lists, so
  // `getInfiniteQueryData(key)!.pages.add(…)` grew the cache behind the
  // observers' backs; and `flatten<T>()` cast each page blindly.
  testFakeAsync(
      'C20 / P5 the pages and pageParams a fetch writes are unmodifiable',
      (time) async {
    final client = testClient();
    final key = queryKey();
    await client.infiniteQuery<List<int>, int>(InfiniteQueryOptions(
      queryKey: key,
      initialPageParam: 0,
      getNextPageParam: (page, pages, param, params) => param + 1,
      pageFn: (context) async => [context.pageParam],
    ));
    final data = client.getInfiniteQueryData<List<int>, int>(key)!;
    expect(() => data.pages.add([99]), throwsUnsupportedError);
    expect(() => data.pageParams.add(99), throwsUnsupportedError);
    expect(data.pages, [
      [0]
    ]);
    // `==` is over the two lists' contents, not their identity, so a const
    // expectation of the ported suites still matches a sealed fetch result
    // (a page that is itself a list compares by `==`, as it always did).
    final intKey = queryKey();
    await client.infiniteQuery<int, int>(InfiniteQueryOptions(
      queryKey: intKey,
      initialPageParam: 0,
      getNextPageParam: (_, __, param, ___) => param < 1 ? param + 1 : null,
      pageFn: (context) async => context.pageParam,
      pages: 2,
    ));
    expect(client.getInfiniteQueryData<int, int>(intKey),
        InfiniteData<int, int>(pages: [0, 1], pageParams: [0, 1]));
    client.clear();
  });

  testFakeAsync(
      'C20 / P5 a structurally shared refetch result is unmodifiable too, '
      'and an unchanged list keeps its identity', (time) async {
    final client = testClient();
    final key = queryKey();
    await client.infiniteQuery<List<int>, int>(InfiniteQueryOptions(
      queryKey: key,
      initialPageParam: 0,
      getNextPageParam: (_, __, param, ___) => param < 1 ? param + 1 : null,
      pageFn: (context) async => [context.pageParam],
      pages: 2,
    ));
    final before = client.getInfiniteQueryData<List<int>, int>(key)!;
    // A growable write with one changed page: the walk copies the pages
    // list, keeps the params list, and the copy in the cache is sealed.
    client.setQueryData<InfiniteData<List<int>, int>>(
      key,
      InfiniteData(pages: <List<int>>[
        <int>[0],
        <int>[7]
      ], pageParams: <int>[
        0,
        1
      ]),
    );
    final after = client.getInfiniteQueryData<List<int>, int>(key)!;
    expect(after.pages[0], same(before.pages[0]));
    expect(after.pageParams, same(before.pageParams));
    expect(() => after.pages.add([99]), throwsUnsupportedError);
    client.clear();
  });

  test(
      'C20 / P5 flatten<T>() over pages that are not Iterable<T> throws an '
      'ArgumentError naming the page type and the cure', () {
    final data = InfiniteData<int, int>(pages: [1, 2], pageParams: [0, 1]);
    expect(
        () => data.flatten<int>(),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(contains('Iterable<int>'), contains('int'),
                contains('select')))));
    final nested = InfiniteData<List<int>, int>(pages: [
      [1],
      [2, 3]
    ], pageParams: [
      0,
      1
    ]);
    expect(nested.flatten<int>(), [1, 2, 3]);
    expect(nested.flatten<dynamic>(), [1, 2, 3]);
    expect(() => nested.flatten<String>(), throwsArgumentError);
  });

  // C23.2 — `MutationState ==` compared `errorStackTrace`, which never
  // compares equal by value; `QueryState` had left its traces out.
  test('C23.2 two MutationStates differing only in errorStackTrace are equal',
      () {
    final error = StateError('x');
    final a = MutationState<int, int, void>(
        status: MutationStatus.error,
        error: error,
        errorStackTrace: StackTrace.current);
    final b = MutationState<int, int, void>(
        status: MutationStatus.error,
        error: error,
        errorStackTrace: StackTrace.current);
    expect(a.errorStackTrace, isNot(same(b.errorStackTrace)));
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.copyWith(), a);
  });

  // C23.9 — `setQueryData(key, 'x')` infers `String` against a query holding
  // `String?`; the error now names the cure.
  testFakeAsync(
      'C23.9 setQueryData against a nullable query names the type argument '
      'to write', (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<String?>(key, null);
    expect(
        () => client.setQueryData(key, 'x'),
        throwsA(isA<QueryDataTypeError>().having((e) => e.toString(), 'message',
            contains('setQueryData<String?>'))));
    expect(
        () => client.setQueryData<int>(key, 1),
        throwsA(isA<QueryDataTypeError>().having(
            (e) => e.toString(), 'message', isNot(contains('setQueryData<')))),
        reason: 'only the nullability mismatch has this one cure');
    client.setQueryData<String?>(key, 'x');
    expect(client.getQueryData<String?>(key), 'x');
    client.clear();
  });

  // C23.1 — the option values, filters, options and mutation results print
  // as what they were written as, not `Instance of '…'`.
  test('C23.1 toString reads as the source form, unset fields skipped', () {
    expect('${StaleTime.duration(const Duration(seconds: 5))}',
        'StaleTime.duration(0:00:05.000000)');
    expect('${StaleTime.static}', 'StaleTime.static');
    expect('${GcTime.never}', 'GcTime.never');
    expect('${Enabled.no}', 'Enabled.no');
    expect('${RetryPolicy.times(3)}', 'RetryPolicy.times(3)');
    expect('${RetryDelay.fixed(const Duration(seconds: 1))}',
        'RetryDelay.fixed(0:00:01.000000)');
    expect('${RetryDelay.defaultValue}',
        'RetryDelay.exponential(base: 0:00:01.000000, maximum: 0:00:30.000000)');
    expect('${RefetchOn.ifStale}', 'RefetchOn.ifStale');
    expect('${RefetchInterval.every(const Duration(seconds: 1))}',
        'RefetchInterval.every(0:00:01.000000)');
    expect('${InitialData<int>.value(1)}', 'InitialData.value(1)');
    expect('${PlaceholderData<int>.keepPrevious()}',
        'PlaceholderData.keepPrevious()');
    expect(
        '${RetryDelay.dynamic(_oneSecond)}', contains('RetryDelay.dynamic('));

    final key = queryKey();
    expect('${QueryOptions<int>(queryKey: key, staleTime: StaleTime.static)}',
        'QueryOptions<int>($key, staleTime: StaleTime.static)');
    expect(
        '${QuerySelectOptions<int, String>(queryKey: key, select: _stringify, retryOnMount: false)}',
        allOf(startsWith('QuerySelectOptions<int, String>($key, select: '),
            endsWith(', retryOnMount: false)')));
    expect(
        '${InfiniteQueryObserverOptions<int, int>(queryKey: key, pageFn: _page, initialPageParam: 0, getNextPageParam: _next, maxPages: 3)}',
        allOf(
            startsWith('InfiniteQueryObserverOptions<int, int>($key, pageFn: '),
            contains(', initialPageParam: 0, '),
            endsWith(', maxPages: 3)'),
            isNot(contains('behavior'))));
    expect('${const QueryFilters(exact: true, type: QueryTypeFilter.active)}',
        'QueryFilters(exact: true, type: QueryTypeFilter.active)');
    expect('${const MutationFilters()}', 'MutationFilters()');

    final client = testClient();
    final observer = MutationObserver<int, String, void>(
        client, MutationOptions(mutationFn: (v) => v.length));
    expect('${observer.currentResult}', 'MutationIdle<int, String>()');
    client.clear();
  });

  // C54 — a query held its cache twice: state and fetch events went to the
  // cache that built it, observer events to `client.queryCache`. The two are
  // the same object on every path the port takes, but `QueryCache.build` is
  // public, so one query could send its two kinds of event to two caches.
  test(
      'C54 a query built by a foreign cache sends its observer events there '
      'too, not to its client\'s cache', () {
    final foreign = QueryCache();
    final client = testClient();
    final key = queryKey();
    final onForeign = <QueryCacheEvent>[];
    final onClients = <QueryCacheEvent>[];
    foreign.subscribe(onForeign.add);
    client.queryCache.subscribe(onClients.add);

    final query = foreign.build<int>(
      client,
      client.defaultQueryOptions(QueryOptions<int>(queryKey: key)),
    );
    final observer = _StubObserverRef(client, key);
    query.addObserver(observer);
    query.removeObserver(observer);

    expect(onForeign.whereType<QueryObserverAdded>(), hasLength(1));
    expect(onForeign.whereType<QueryObserverRemoved>(), hasLength(1));
    expect(onClients, isEmpty,
        reason: 'the client\'s own cache never held this query');
    foreign.clear();
    client.clear();
  });

  // C50: every listener list in the core is now one `ListenerRegistry`, and
  // its loop skips a listener an earlier one removed — which is what
  // upstream's `Set.forEach` does and what six of the eight hand-written
  // loops did not.
  testFakeAsync(
      'an observer listener unsubscribed by an earlier one is not '
      'called', (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<int>(key, 1);
    final observer = QueryObserver<int, int>(
      client,
      QueryObserverOptions<int>(queryKey: key, enabled: Enabled.no),
    );
    late void Function() removeSecond;
    final seenBySecond = <int?>[];
    final removeFirst = observer.subscribe((_) => removeSecond());
    removeSecond = observer.subscribe((result) {
      seenBySecond.add(result.dataOrNull);
    });

    client.setQueryData<int>(key, 2);
    await time.advance(Duration.zero);

    expect(seenBySecond, isEmpty,
        reason: 'the first listener unsubscribed it before it was reached');
    removeFirst();
    observer.destroy();
    client.clear();
  });

  testFakeAsync('a cache listener unsubscribed by an earlier one is not called',
      (time) async {
    final client = testClient();
    final key = queryKey();
    late void Function() removeSecond;
    final seenBySecond = <QueryCacheEvent>[];
    final removeFirst = client.queryCache.subscribe((_) => removeSecond());
    removeSecond = client.queryCache.subscribe(seenBySecond.add);

    client.setQueryData<int>(key, 1);
    await time.advance(Duration.zero);

    expect(seenBySecond, isEmpty);
    removeFirst();
    client.clear();
  });

  // Pre-release verification, 2026-09-12: a dynamic option that throws on
  // the first subscribe (AR-02). Each kind is asked at a different point of
  // `_onSubscribe` — before the fetch on mount (`Enabled.when`,
  // `StaleTime.dynamic`, `RefetchOn.when`) or after it (`PlaceholderData
  // .compute`, `RefetchInterval.dynamic`) — so all five are pinned. The
  // options are healthy at construction and break before the subscribe, as
  // a widget's state going null between a build and a listen does.
  for (final (kind, build) in <(
    String,
    QueryObserverOptions<int> Function(QueryKey key, bool Function() broken)
  )>[
    (
      'Enabled.when',
      (key, broken) => QueryObserverOptions(
            queryKey: key,
            queryFn: (_) => 1,
            enabled: Enabled.when(
                (_) => broken() ? throw StateError('enabled') : true),
          )
    ),
    (
      'StaleTime.dynamic',
      (key, broken) => QueryObserverOptions(
            queryKey: key,
            queryFn: (_) => 1,
            initialData: const InitialData.value(0),
            staleTime: StaleTime.dynamic((_) => broken()
                ? throw StateError('staleTime')
                : const StaleTime.duration(Duration(seconds: 10))),
          )
    ),
    (
      'PlaceholderData.compute',
      (key, broken) => QueryObserverOptions(
            queryKey: key,
            queryFn: (_) => sleep(ms(10)).then((_) => 1),
            // `null` at construction: a placeholder that was shown is
            // memoised and never asked again, one that was not is.
            placeholderData: PlaceholderData.compute(
                (_, __) => broken() ? throw StateError('placeholder') : null),
          )
    ),
    (
      'RefetchOn.when',
      (key, broken) => QueryObserverOptions(
            queryKey: key,
            queryFn: (_) => 1,
            initialData: const InitialData.value(0),
            refetchOnMount: RefetchOn.when((_) => broken()
                ? throw StateError('refetchOnMount')
                : RefetchOn.always),
          )
    ),
    (
      'RefetchInterval.dynamic',
      (key, broken) => QueryObserverOptions(
            queryKey: key,
            queryFn: (_) => sleep(ms(10)).then((_) => 1),
            refetchInterval: RefetchInterval.dynamic((_) => broken()
                ? throw StateError('refetchInterval')
                : const Duration(seconds: 1)),
          )
    ),
  ]) {
    testFakeAsyncGuarded(
        'AR-02 a $kind throwing on the first subscribe leaves nothing behind',
        (time, uncaught) async {
      final client = testClient();
      var broken = false;
      final observer =
          client.observe<int, int>(build(queryKey(), () => broken));
      final query = observer.currentQuery;
      broken = true;
      var calls = 0;
      expect(() => observer.subscribe((_) => calls++), throwsStateError);
      expect(observer.hasListeners, isFalse);
      expect(query.observersCount, 0);
      // The interval is computed after the fetch on mount started, so that
      // listener may have heard `fetching` once; nothing after the throw.
      final callsAtThrow = calls;
      await time.advance(ms(50));
      expect(calls, callsAtThrow);
      // The observer is usable again once the option no longer throws.
      broken = false;
      final unsubscribe = observer.subscribe((_) => calls++);
      await time.advance(ms(50));
      expect(observer.hasListeners, isTrue);
      expect(query.observersCount, 1);
      unsubscribe();
      client.clear();
      expect(time.pendingTimers, 0);
    });
  }

  testFakeAsyncGuarded(
      'AR-02 a QueriesObserver member throwing on subscribe leaves no member '
      'subscribed', (time, uncaught) async {
    final client = testClient();
    var broken = false;
    final observer = QueriesObserver<int, int>(client, [
      QueryObserverOptions(queryKey: queryKey(), queryFn: (_) => 1),
      QueryObserverOptions(
        queryKey: queryKey(),
        queryFn: (_) => 2,
        enabled:
            Enabled.when((_) => broken ? throw StateError('member') : true),
      ),
    ]);
    broken = true;
    expect(() => observer.subscribe((_) {}), throwsStateError);
    expect(observer.hasListeners, isFalse);
    for (final member in observer.observers) {
      expect(member.hasListeners, isFalse);
      expect(member.currentQuery.observersCount, 0);
    }
    await time.advance(ms(50));
    observer.destroy();
    client.clear();
    expect(time.pendingTimers, 0);
  });

  testFakeAsync(
      'AR-05 a throwing InitialData.compute leaves setOptions untaken, on the '
      'same query and across a key switch', (time) async {
    final client = testClient();
    final a = queryKey();
    final b = queryKey();
    // `b` exists with no data, so the seed is computed when it is joined.
    client.queryCache.build(
        client, client.defaultQueryOptions(QueryOptions<int>(queryKey: b)));
    final queryB = client.queryCache.get<int>(b)!;
    final observer = client.observe<int, int>(
        QueryObserverOptions(queryKey: a, enabled: Enabled.no));
    final queryA = observer.currentQuery;
    final unsubscribe = observer.subscribe((_) {});
    final options = observer.options;
    final queryOptions = queryA.options;
    final events = <String>[];
    final stop = client.queryCache.subscribe((e) => events.add(eventName(e)));

    for (final key in [a, b]) {
      expect(
          () => observer.setOptions(QueryObserverOptions<int>(
                queryKey: key,
                enabled: Enabled.no,
                initialData:
                    InitialData.compute(() => throw StateError('seed')),
              )),
          throwsStateError);
      expect(identical(observer.options, options), isTrue);
      expect(identical(observer.currentQuery, queryA), isTrue);
      expect(identical(queryA.options, queryOptions), isTrue);
      expect(queryA.observersCount, 1);
      expect(queryB.observersCount, 0);
    }
    // The same-key attempt touches nothing; the switch is undone, so the
    // cache saw the observer leave `b` again and nothing else.
    expect(events, [
      'observerRemoved',
      'observerAdded',
      'observerRemoved',
      'observerAdded',
    ]);
    stop();
    unsubscribe();
    client.clear();
  });

  testFakeAsync(
      'AR-12 every bulk operation reports a throwing predicate through its '
      'future', (time) async {
    final client = testClient();
    client.setQueryData<int>(queryKey(), 1);
    final filters = QueryFilters(predicate: (_) => throw StateError('pred'));
    for (final operation in <Future<void> Function()>[
      () => client.cancelQueries(filters: filters),
      () => client.refetchQueries(filters: filters),
      () => client.invalidateQueries(filters: filters),
      () => client.resetQueries(filters: filters),
    ]) {
      late final Future<void> future;
      expect(() => future = operation(), returnsNormally);
      await expectLater(future, throwsStateError);
    }
    client.clear();
  });

  // IN-01 — `InfiniteData` took two lists of different lengths and said
  // nothing; `hasNextPage` then threw a `RangeError` out of a plain getter,
  // and with a collapsing `select` the same `RangeError` was raised inside
  // `Query._dispatch`'s observer loop and reported to the zone, naming
  // nothing that pointed back at the write that caused it.
  test('IN-01 InfiniteData refuses two lists of different lengths, naming both',
      () {
    expect(
      () => InfiniteData<int, int>(pages: <int>[1, 2], pageParams: <int>[1]),
      throwsA(isA<ArgumentError>().having(
        (e) => e.message,
        'message',
        allOf(contains('2 pages'), contains('1 page param')),
      )),
    );
    expect(
      () => InfiniteData<int, int>(pages: <int>[1], pageParams: <int>[1, 2]),
      throwsA(isA<ArgumentError>().having(
        (e) => e.message,
        'message',
        allOf(contains('1 page'), contains('2 page param')),
      )),
    );
  });

  test('IN-01 copyWith is the same door: trimming one list alone is refused',
      () {
    final aligned =
        InfiniteData<int, int>(pages: <int>[1, 2], pageParams: <int>[1, 2]);
    expect(() => aligned.copyWith(pages: <int>[1]), throwsArgumentError);
    expect(() => aligned.copyWith(pageParams: <int>[1]), throwsArgumentError);
    // Both together still pass.
    expect(aligned.copyWith(pages: <int>[1], pageParams: <int>[1]).pages,
        <int>[1]);
  });

  testFakeAsyncGuarded(
      'IN-01 a setQueryData updater that drops a page param fails at the call '
      'site, not later inside a dispatch', (time, uncaught) async {
    final client = testClient();
    final key = queryKey();
    final observer = InfiniteQueryObserver<int, int, int>(
      client,
      InfiniteQuerySelectOptions<int, int, int>(
        queryKey: key,
        initialPageParam: 0,
        pageFn: _page,
        getNextPageParam: (_, __, param, ___) => param + 1,
        // The collapsing select of the reproduction: the result stays
        // value-equal, so the paging check is what reads the two lists.
        select: (data) => data.pages.length,
        enabled: Enabled.no,
      ),
    );
    final unsubscribe = observer.subscribe((_) {});
    client.setQueryData<InfiniteData<int, int>>(
      key,
      InfiniteData<int, int>(pages: <int>[1, 2], pageParams: <int>[1, 2]),
    );
    await time.flushMicrotasks();

    expect(
      () => client.updateQueryData<InfiniteData<int, int>>(
        key,
        // The realistic way in: trim the pages and forget the params.
        (previous) => previous!.copyWith(pages: previous.pages.sublist(0, 1)),
      ),
      throwsArgumentError,
    );
    await time.flushMicrotasks();
    // The cache still holds the aligned pair, and the failure never reached
    // the zone through an observer loop.
    expect(client.getInfiniteQueryData<int, int>(key)!.pages, <int>[1, 2]);
    expect(uncaught, isEmpty);
    expect(observer.hasNextPage, isTrue);
    unsubscribe();
    client.clear();
  });

  // MU-03 — `MutationCache.build`'s doc said the twin was closed with the
  // same door as `QueryCache.build`'s, and it was not: a restored `success`
  // state with no data went in, and `MutationState` then reported success
  // holding nothing.
  testFakeAsync(
      'MU-03 a restored success state must carry data, as the query '
      'twin must', (time) async {
    final client = testClient();
    final options = client.defaultMutationOptions(
      MutationOptions<String, int, void>(mutationFn: (v) async => '$v'),
    );
    expect(
      () => client.mutationCache.build<String, int, void>(
        client,
        options,
        state: const MutationState<String, int, void>(
          status: MutationStatus.success,
          variables: 1,
          hasVariables: true,
        ),
      ),
      throwsArgumentError,
    );
    // The same state, refused by the mutation's own constructor door too.
    expect(
      () => Mutation<String, int, void>(
        client: client,
        cache: client.mutationCache,
        mutationId: 99,
        options: options,
        state: const MutationState<String, int, void>(
          status: MutationStatus.success,
          variables: 1,
          hasVariables: true,
        ),
      ),
      throwsArgumentError,
    );
    // With data it is the persistence door, as documented.
    final restored = client.mutationCache.build<String, int, void>(
      client,
      options,
      state: const MutationState<String, int, void>(
        status: MutationStatus.success,
        variables: 1,
        hasVariables: true,
        hasData: true,
        data: 'restored',
      ),
    );
    expect(restored.state.data, 'restored');
    client.clear();
  });

  // QE-02 — a snapshot taken mid-fetch was installed verbatim: nothing ran,
  // yet `isFetching()` counted it and gc never collected it.
  testFakeAsync(
      'QE-02 a restored fetching state is normalised to idle at the build door',
      (time) async {
    final client = testClient();
    for (final restored in <FetchStatus>[
      FetchStatus.fetching,
      FetchStatus.paused,
    ]) {
      final key = queryKey();
      final options =
          client.defaultQueryOptions<int>(QueryOptions<int>(queryKey: key));
      final query = client.queryCache.build<int>(
        client,
        options,
        state: QueryState<int>(
          status: QueryStatus.success,
          hasData: true,
          data: 1,
          dataUpdateCount: 1,
          dataUpdatedAt: DateTime.utc(2026),
          fetchStatus: restored,
        ),
      );
      expect(query.state.fetchStatus, FetchStatus.idle,
          reason: 'no fetch survives the process that started it');
      expect(query.state.data, 1, reason: 'the rest of the state is untouched');
      expect(client.isFetching(), 0);
    }
    // And the entry is collectable, which a `fetching` one never was.
    await time.advance(const Duration(minutes: 10));
    expect(client.queryCache.queries, isEmpty);
    client.clear();
  });

  testFakeAsync('QE-02 Query.setState installs the fetch status it is given',
      (time) async {
    // The other half of a restore, and upstream's other half too: a merge
    // into an existing query keeps an actively fetching status.
    final client = testClient();
    final key = queryKey();
    client.setQueryData<int>(key, 1);
    final query = client.queryCache.get<int>(key)!;
    query.setState(QueryState<int>(
      status: QueryStatus.success,
      hasData: true,
      data: 2,
      dataUpdateCount: 1,
      dataUpdatedAt: DateTime.utc(2026),
      fetchStatus: FetchStatus.fetching,
    ));
    expect(query.state.fetchStatus, FetchStatus.fetching);
    query.setState(QueryState<int>(
      status: QueryStatus.success,
      hasData: true,
      data: 2,
      dataUpdateCount: 1,
      dataUpdatedAt: DateTime.utc(2026),
    ));
    client.clear();
  });

  // MU-02 — a restored `pending` head with `isPaused: false` could never be
  // resumed: `resumePausedMutations` only continues paused runs, so the
  // entry blocked its scope for good, and with it every reconnect refetch
  // behind `mount()`'s awaited `resumePausedMutations()`.
  testFakeAsync(
      'MU-02 a restored pending state is normalised to paused at the build '
      'door', (time) async {
    final client = testClient();
    final restored = client.mutationCache.build<int, int, void>(
      client,
      client.defaultMutationOptions(
        MutationOptions<int, int, void>(mutationFn: (v) async => v),
      ),
      state: const MutationState<int, int, void>(
        status: MutationStatus.pending,
        variables: 1,
        hasVariables: true,
      ),
    );
    expect(restored.state.isPaused, isTrue);
    expect(restored.state.status, MutationStatus.pending);
    // Paused is resumable: that is the whole point of the flip.
    await client.resumePausedMutations();
    expect(restored.state.status, MutationStatus.success);
    expect(restored.state.data, 1);
    client.clear();
  });

  testFakeAsync(
      'MU-02 a restored pending mutation no longer blocks the reconnect '
      'refetch behind mount()', (time) async {
    final client = testClient();
    client.mount();
    final scope = MutationScope('mu-02');
    final key = queryKey();
    var fetches = 0;
    final observer = QueryObserver<int, int>(
      client,
      QueryObserverOptions(
        queryKey: key,
        queryFn: (_) => ++fetches,
        staleTime: StaleTime.zero,
        refetchOnReconnect: RefetchOn.always,
      ),
    );
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(fetches, 1);

    // What a persister writes for a mutation that was in flight when the app
    // died, restored into a scope a live mutation also uses.
    client.mutationCache.build<int, int, void>(
      client,
      client.defaultMutationOptions(
        MutationOptions<int, int, void>(
            scope: scope, mutationFn: (v) async => v),
      ),
      state: const MutationState<int, int, void>(
        status: MutationStatus.pending,
        variables: 7,
        hasVariables: true,
      ),
    );
    final live = client.mutationCache.build<int, int, void>(
      client,
      client.defaultMutationOptions(
        MutationOptions<int, int, void>(
            scope: scope, mutationFn: (v) async => v),
      ),
    );
    live.execute(2).ignore();
    await time.flushMicrotasks();

    client.onlineManager.setOnline(false);
    client.onlineManager.setOnline(true);
    await time.advance(const Duration(minutes: 10));

    expect(fetches, 2,
        reason: 'the reconnect refetch is not held hostage by a restored '
            'mutation nobody could resume');
    unsubscribe();
    client.unmount();
    client.clear();
  });

  // AR-04 — `isActive`/`isStatic` walked the live observer list while
  // resolving user predicates, so a predicate with a subscription side
  // effect threw `ConcurrentModificationError` out of every filtered bulk
  // operation.
  testFakeAsync(
      'AR-04 an enabled predicate that unsubscribes a sibling does not break '
      'isFetching', (time) async {
    final client = testClient();
    final key = queryKey();
    void Function()? siblingUnsubscribe;
    var armed = false;
    // The meddling observer subscribes first, so the walk is still inside the
    // list when the predicate removes the one behind it.
    final meddling = QueryObserver<int, int>(
      client,
      QueryObserverOptions(
        queryKey: key,
        queryFn: (_) => 1,
        enabled: Enabled.when((_) {
          if (armed) {
            armed = false;
            siblingUnsubscribe?.call();
          }
          return false;
        }),
      ),
    );
    final sibling = QueryObserver<int, int>(
      client,
      QueryObserverOptions(queryKey: key, queryFn: (_) => 1),
    );
    final unsubscribe = meddling.subscribe((_) {});
    siblingUnsubscribe = sibling.subscribe((_) {});
    await time.flushMicrotasks();

    armed = true;
    expect(
      () => client.isFetching(
          filters: const QueryFilters(type: QueryTypeFilter.active)),
      returnsNormally,
    );
    expect(armed, isFalse, reason: 'the predicate really did run and remove');
    unsubscribe();
    client.clear();
  });

  testFakeAsync(
      'AR-04 a staleTime callback that unsubscribes a sibling does not break '
      'refetchQueries', (time) async {
    final client = testClient();
    final key = queryKey();
    void Function()? siblingUnsubscribe;
    var armed = false;
    final meddling = QueryObserver<int, int>(
      client,
      QueryObserverOptions(
        queryKey: key,
        queryFn: (_) => 1,
        staleTime: StaleTime.dynamic((_) {
          if (armed) {
            armed = false;
            siblingUnsubscribe?.call();
          }
          return StaleTime.zero;
        }),
      ),
    );
    final sibling = QueryObserver<int, int>(
      client,
      QueryObserverOptions(queryKey: key, queryFn: (_) => 1),
    );
    final unsubscribe = meddling.subscribe((_) {});
    siblingUnsubscribe = sibling.subscribe((_) {});
    await time.flushMicrotasks();

    armed = true;
    await expectLater(
      client.refetchQueries(filters: QueryFilters(queryKey: key)),
      completes,
    );
    expect(armed, isFalse, reason: 'the callback really did run and remove');
    unsubscribe();
    client.clear();
  });

  // QE-03 — `clear()` delivered one scheduled flush per removed entry to a
  // subscriber wrapped in `batchCalls`, where `removeQueries` delivered one
  // for the call.
  testFakeAsync('QE-03 clear() batches its removals like removeQueries does',
      (time) async {
    final client = testClient();
    var flushes = 0;
    client.notifyManager.setScheduler((callback) {
      flushes++;
      callback();
    });
    for (var i = 0; i < 3; i++) {
      client.setQueryData<int>(QueryKey(<Object?>['qe-03', i]), i);
    }
    final unsubscribe =
        client.queryCache.subscribe(client.notifyManager.batchCalls((_) {}));

    client.removeQueries(
      filters: QueryFilters(queryKey: QueryKey(<Object?>['qe-03', 0])),
    );
    expect(flushes, 1);

    flushes = 0;
    client.clear();
    expect(flushes, 1, reason: 'one flush for the call, not one per entry');
    unsubscribe();
  });

  // Fidelity P11 — the `signal` getter told the query on every read, where
  // upstream's `addConsumeAwareSignal` consumes exactly once.
  testFakeAsync(
      'P11 a FetchContext consumes its signal once across repeated accesses',
      (time) async {
    final token = QueryCancelToken();
    var reads = 0;
    final context = FetchContext<int>(
      client: testClient(),
      queryKey: queryKey(),
      options: testClient().defaultQueryOptions(
          QueryOptions<int>(queryKey: queryKey(), queryFn: (_) => 1)),
      state: const QueryState<int>(),
      fetchOptions: null,
      fetchFn: () async => 1,
      signal: token,
      onSignalRead: () => reads++,
    );
    expect(context.signal, same(token));
    expect(context.signal, same(token));
    expect(reads, 1);
  });
}

/// The eight members [Query] asks of an observer, answered with the quietest
/// value each: enough to attach and detach without the query fetching or
/// refetching. Only C54's case needs one.
class _StubObserverRef implements QueryObserverRef {
  _StubObserverRef(this.client, this.key);

  final QueryClient client;
  final QueryKey key;

  @override
  void onQueryUpdate() {}

  @override
  bool get isEnabledForQuery => false;

  @override
  bool get isStaticForQuery => false;

  @override
  bool get currentResultIsStale => false;

  @override
  bool shouldFetchOnWindowFocus() => false;

  @override
  bool shouldFetchOnReconnect() => false;

  @override
  void refetchOnEvent() {}

  @override
  DefaultedQueryOptions<Object?> get observerQueryOptions =>
      client.defaultQueryOptions(QueryOptions<int>(queryKey: key));
}

Duration _oneSecond(int failureCount, Object error) =>
    const Duration(seconds: 1);
String _stringify(int n) => '$n';
int _page(InfinitePageContext<int> context) => context.pageParam;
int? _next(int page, List<int> pages, int param, List<int> params) => null;

class _Selector {
  int calls = 0;
  int length(List<int> data) {
    calls++;
    return data.length;
  }
}

/// Value-equal across the hierarchy: a `_Wide(1)` equals a `_Narrow(1)`, so
/// the sharing walk hands a `_Wide` to a `List<_Narrow>` copy (AR-09).
class _Wide {
  _Wide(this.value);
  final int value;
  @override
  bool operator ==(Object other) => other is _Wide && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

class _Narrow extends _Wide {
  _Narrow(super.value);
}

// -----------------------------------------------------------------------------
// Fidelity review, 2026-09-12. Three behavioural gaps between `query.ts` /
// `queryObserver.ts` at `50680b98c` and this port, each reproduced before the
// fix. The ported cases they belong to are in `query_test.dart` and
// `query_client_test.dart`; these are the parts that have no upstream case,
// because upstream expresses them with `skipToken` and an untyped
// `structuralSharing`.

void fidelityReview() {
  // FI-01's two cases pinned `isDisabled` consulting `enabled` with no
  // observer attached. That was reverted by the final review of the same
  // day; `F2 …` and `F3 …` in `finalReview` below pin what replaced it.

  testFakeAsync(
      'FI-04 a fetch with no query function of its own borrows an '
      "observer's", (time) async {
    final client = testClient();
    final key = queryKey();
    var fetches = 0;
    Future<String> queryFn(QueryFunctionContext _) async {
      fetches++;
      return 'observed';
    }

    final observer = client.observe<String, String>(
      QueryObserverOptions<String>(queryKey: key, queryFn: queryFn),
    );
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(fetches, 1);

    // The one way a query with observers can have no query function of its
    // own: an imperative call that carries none. Upstream reaches the same
    // branch by constructing a `Query` with no options at all, which cannot
    // happen here — a `Query` is always the cache's entry for its key, and
    // the observer wrote its own options into it.
    expect(
      await client.query<String>(QueryOptions<String>(queryKey: key)),
      'observed',
    );
    expect(fetches, 2);
    expect(client.queryCache.get<String>(key)!.options.queryFn, same(queryFn));
    unsubscribe();
    client.clear();
  });

  testFakeAsync('FI-05 a structuralSharing opt-out reaches select output',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final observer = client.observe<List<String>, List<String>>(
      QuerySelectOptions<List<String>, List<String>>(
        queryKey: key,
        // A fresh but equal list on every fetch.
        queryFn: (_) => <String>['a', 'b'],
        // A fresh but equal list on every selection.
        select: List<String>.of,
        // The opt-out. Upstream's `replaceData` routes `structuralSharing`
        // for the selected value too; this port always ran the selection
        // through `replaceEqualDeep`, so the reader was handed the first
        // instance forever and the switch was invisible to it. Spelled
        // `noStructuralSharing()` since F4: only the recognised opt-out
        // reaches the selection.
        structuralSharing: noStructuralSharing(),
      ),
    );
    observer.subscribe((_) {});
    await time.flushMicrotasks();
    final first = observer.currentResult.dataOrNull;
    await observer.refetch();
    await time.flushMicrotasks();
    expect(identical(observer.currentResult.dataOrNull, first), isFalse);
    expect(observer.currentResult.dataOrNull, <String>['a', 'b']);
    observer.destroy();
    client.clear();
  });

  testFakeAsync('FI-05 the default still shares select output', (time) async {
    final client = testClient();
    final key = queryKey();
    final observer = client.observe<List<String>, List<String>>(
      QuerySelectOptions<List<String>, List<String>>(
        queryKey: key,
        queryFn: (_) => <String>['a', 'b'],
        select: List<String>.of,
      ),
    );
    observer.subscribe((_) {});
    await time.flushMicrotasks();
    final first = observer.currentResult.dataOrNull;
    await observer.refetch();
    await time.flushMicrotasks();
    expect(identical(observer.currentResult.dataOrNull, first), isTrue);
    observer.destroy();
    client.clear();
  });
}

// -----------------------------------------------------------------------------
// Final review of the pre-release branch, 2026-09-12. Defects the round's own
// fixes introduced (F1–F6), each reproduced with the reviewer's probe before
// anything changed, and each regression below red against the tree it fixes.

/// A value class: `==` by [value], two instances apart by identity.
final class _Valued {
  _Valued(this.value);
  final int value;
  @override
  bool operator ==(Object other) => other is _Valued && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// A list whose `==` only compares lengths — looser than the sharing walk.
final class _LengthEqualList extends ListBase<String> {
  _LengthEqualList(this._items);
  final List<String> _items;
  @override
  int get length => _items.length;
  @override
  set length(int value) => _items.length = value;
  @override
  String operator [](int index) => _items[index];
  @override
  void operator []=(int index, String value) => _items[index] = value;
  @override
  bool operator ==(Object other) =>
      other is _LengthEqualList && other.length == length;
  @override
  int get hashCode => length.hashCode;
}

/// A set that answers only `length`, iteration and `add`: every method whose
/// answer depends on an equality policy throws, as `MapKeySet.lookup` does.
final class _MembersOnlySet<E> extends SetBase<E> {
  _MembersOnlySet(Iterable<E> members) : _members = members.toList();
  final List<E> _members;
  @override
  bool add(E value) {
    _members.add(value);
    return true;
  }

  @override
  Iterator<E> get iterator => _members.iterator;
  @override
  int get length => _members.length;
  @override
  bool contains(Object? element) => throw UnsupportedError('contains');
  @override
  E? lookup(Object? element) => throw UnsupportedError('lookup');
  @override
  bool remove(Object? value) => throw UnsupportedError('remove');
  @override
  bool containsAll(Iterable<Object?> other) =>
      throw UnsupportedError('containsAll');
  @override
  Set<E> toSet() => _MembersOnlySet<E>(_members);
}

/// A hand-written set whose `lookup` returns its argument rather than the
/// stored member — what dart2js's default set does for numbers.
final class _ArgumentLookupSet extends SetBase<String> {
  _ArgumentLookupSet(this._base);
  final Set<String> _base;
  @override
  bool add(String value) => _base.add(value);
  @override
  bool contains(Object? element) => _base.contains(element);
  @override
  Iterator<String> get iterator => _base.iterator;
  @override
  int get length => _base.length;
  @override
  String? lookup(Object? element) =>
      contains(element) ? element as String : null;
  @override
  bool remove(Object? value) => _base.remove(value);
  @override
  Set<String> toSet() => _ArgumentLookupSet(_base.toSet());
}

int _caseInsensitive(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());

void finalReview() {
  test(
      'F1 a set with its own equality policy is compared by the walk, not by '
      'its own lookup', () {
    // A case-insensitive `SplayTreeSet` calls "Alpha" and "alpha" the same
    // member, and `containsAll` asks the set. The walk compares with `==`.
    final splayPrevious = SplayTreeSet<String>(_caseInsensitive)..add('Alpha');
    final splayNext = SplayTreeSet<String>(_caseInsensitive)..add('alpha');
    expect(replaceEqualDeep<Set<String>>(splayPrevious, splayNext),
        same(splayNext));

    // The same through `equals:`/`hashCode:`.
    LinkedHashSet<String> caseless(String member) => LinkedHashSet<String>(
          equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
          hashCode: (value) => value.toLowerCase().hashCode,
        )..add(member);
    final hashedNext = caseless('alpha');
    expect(replaceEqualDeep<Set<String>>(caseless('Alpha'), hashedNext),
        same(hashedNext));

    // Equal members under `==` are still shared, whatever the set's policy.
    final kept = SplayTreeSet<String>(_caseInsensitive)..add('Alpha');
    expect(
        replaceEqualDeep<Set<String>>(
            kept, SplayTreeSet<String>(_caseInsensitive)..add('Alpha')),
        same(kept));
  });

  test(
      'F1 members a set holds apart, or a policy pairs, are still compared '
      'by the walk', () {
    // Two `==` members an identity set can hold apart. Both are `==` to the
    // same member of the other set: a comparison that did not consume each
    // partner once would call `{V(1), V(1)}` "equal" to `{V(1), V(2)}`.
    final twice = Set<Object?>.identity()
      ..add(_Valued(1))
      ..add(_Valued(1));
    final previous = <Object?>{_Valued(1), _Valued(2)};
    expect(replaceEqualDeep<Set<Object?>>(previous, twice), same(twice));
    expect(replaceEqualDeep<Set<Object?>>(twice, previous), same(previous));

    // A collection member that is not the very instance goes to the walk,
    // which still shares it when it is deep-equal.
    final lists = <Object?>{
      <int>[1],
      <int>[2],
    };
    expect(
        replaceEqualDeep<Set<Object?>>(lists, <Object?>{
          <int>[2],
          <int>[1],
        }),
        same(lists));
    expect(
        replaceEqualDeep<Set<Object?>>(lists, <Object?>{
          <int>[2],
          <int>[3],
        }),
        isNot(same(lists)));

    // A collection whose own `==` is looser than the walk — here, equal by
    // length — is still compared by walking it, as it always was: a pair the
    // walk would reject is not accepted on `==`'s word.
    final loose = <Object?>{
      _LengthEqualList(<String>['a'])
    };
    final changed = <Object?>{
      _LengthEqualList(<String>['b'])
    };
    expect(replaceEqualDeep<Set<Object?>>(loose, changed), same(changed));

    // A `null` member, which `lookup` cannot report, is decided by the walk.
    final withNull = <Object?>{null, 1};
    expect(replaceEqualDeep<Set<Object?>>(withNull, <Object?>{1, null}),
        same(withNull));
    expect(replaceEqualDeep<Set<Object?>>(withNull, <Object?>{1, 2}),
        isNot(same(withNull)));
  });

  test('F1 a refetch that changes a member of such a set is reported', () {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<SplayTreeSet<String>>(
        key, SplayTreeSet<String>(_caseInsensitive)..add('Alpha'));
    client.setQueryData<SplayTreeSet<String>>(
        key, SplayTreeSet<String>(_caseInsensitive)..add('alpha'));
    expect(client.getQueryData<SplayTreeSet<String>>(key)!.single, 'alpha');
    client.clear();
  });

  test(
      "F1 a QueryKey's set part is frozen to default equality, so its own "
      'set shortcut stays sound', () {
    // `QueryKey` keeps a `containsAll` shortcut the sharing walk lost. It is
    // sound there because `_freeze` copies every set part into
    // `Set.unmodifiable`, a default-equality set, whatever policy the caller's
    // set had.
    QueryKey splay(String member) => QueryKey(<Object?>[
          SplayTreeSet<String>(_caseInsensitive)..add(member),
        ]);
    QueryKey hashed(String member) => QueryKey(<Object?>[
          LinkedHashSet<String>(
            equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
            hashCode: (value) => value.toLowerCase().hashCode,
          )..add(member),
        ]);
    expect(splay('Alpha'), isNot(equals(splay('alpha'))));
    expect(splay('Alpha').hashCode, isNot(splay('alpha').hashCode));
    expect(hashed('Alpha'), isNot(equals(hashed('alpha'))));
    expect(splay('Alpha'), equals(splay('Alpha')));
    expect(splay('Alpha').hashCode, splay('Alpha').hashCode);
    // And the two policies agree with each other once frozen.
    expect(splay('Alpha'), equals(hashed('Alpha')));
  });

  testFakeAsync(
      'F2 refetchQueries(all) refetches an unobserved query whose last '
      'observer was Enabled.no', (time) async {
    final client = testClient();
    final key = queryKey();
    var fetches = 0;
    final observer = client.observe<String, String>(
      QueryObserverOptions<String>(
        queryKey: key,
        queryFn: (_) {
          fetches++;
          return 'fetched';
        },
        enabled: Enabled.no,
      ),
    );
    client.setQueryData(key, 'seed');
    observer.subscribe((_) {})();
    await time.flushMicrotasks();

    final query = client.queryCache.get<String>(key)!;
    // `Enabled.no` is upstream's `enabled: false`, which never reaches the
    // no-observer arm upstream: a seeded query is refetched. The FI-01 fix
    // read it as `skipToken` and skipped the query for good.
    expect(query.isDisabled(), isFalse);
    await client.refetchQueries(
      filters: const QueryFilters(type: QueryTypeFilter.all),
    );
    expect(fetches, 1);
    expect(query.state.data, 'fetched');

    await client.invalidateQueries(refetchType: RefetchType.all);
    expect(fetches, 2);

    // Upstream's other half is kept: never fetched means disabled.
    final idleKey = queryKey();
    client.observe<String, String>(QueryObserverOptions<String>(
      queryKey: idleKey,
      queryFn: (_) {
        fetches++;
        return 'fetched';
      },
      enabled: Enabled.no,
    ))
      ..subscribe((_) {})()
      ..destroy();
    expect(client.queryCache.get<String>(idleKey)!.isDisabled(), isTrue);
    await client.refetchQueries(
      filters: const QueryFilters(type: QueryTypeFilter.all),
    );
    expect(fetches, 3, reason: 'only the seeded query was refetched again');
    client.clear();
  });

  testFakeAsync(
      'F3 an Enabled.when predicate is not called once its observer is gone',
      (time) async {
    final client = testClient();
    final key = queryKey();
    var calls = 0;
    var observerGone = false;
    final observer = client.observe<String, String>(
      QueryObserverOptions<String>(
        queryKey: key,
        queryFn: (_) => 'fetched',
        enabled: Enabled.when((_) {
          calls++;
          // A predicate over state its owner tears down with it.
          if (observerGone) {
            throw StateError('read after dispose');
          }
          return false;
        }),
      ),
    );
    client.setQueryData(key, 'seed');
    observer.subscribe((_) {})();
    await time.flushMicrotasks();
    observerGone = true;
    final before = calls;

    final query = client.queryCache.get<String>(key)!;
    expect(query.isDisabled(), isFalse);
    await client.refetchQueries(
      filters: const QueryFilters(type: QueryTypeFilter.all),
    );
    await client.invalidateQueries(refetchType: RefetchType.all);
    expect(calls, before,
        reason: 'nothing observes the query; its predicate is not asked');
    client.clear();
  });

  testFakeAsync(
      "F4 a sharing hook of the user's own leaves select output shared",
      (time) async {
    for (final hook in <StructuralSharing<String>>[
      // A hook that shares, in its own way.
      (previous, next) =>
          previous != null && previous == next ? previous : next,
      // And the one the docs used to call "off": a hook, not the opt-out.
      (_, next) => next,
    ]) {
      final client = testClient();
      final key = queryKey();
      final observer = client.observe<String, List<String>>(
        QuerySelectOptions<String, List<String>>(
          queryKey: key,
          queryFn: (_) => 'a1',
          structuralSharing: hook,
          // A fresh list each time, equal whenever the first letter is.
          select: (data) => <String>[data.substring(0, 1)],
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      client.setQueryData<String>(key, 'a1');
      final first = observer.currentResult.dataOrNull;
      // The input changes, so the selector runs again and builds a new list.
      client.setQueryData<String>(key, 'a2');
      expect(observer.currentResult.dataOrNull, same(first),
          reason: 'the hook governs the cache write; it did not ask for the '
              'selection to go unshared');
      unsubscribe();
      client.clear();
    }
  });

  testFakeAsync(
      'F4 noStructuralSharing() turns select output sharing off, set on the '
      'query or through the defaults', (time) async {
    for (final throughDefaults in <bool>[false, true]) {
      final client = testClient();
      if (throughDefaults) {
        client.setDefaultOptions(DefaultOptions(
          queries: QueryDefaults(structuralSharing: noStructuralSharing()),
        ));
      }
      final key = queryKey();
      final observer = client.observe<String, List<String>>(
        QuerySelectOptions<String, List<String>>(
          queryKey: key,
          queryFn: (_) => 'a1',
          structuralSharing:
              throughDefaults ? null : noStructuralSharing<String>(),
          select: (data) => <String>[data.substring(0, 1)],
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      client.setQueryData<String>(key, 'a1');
      final first = observer.currentResult.dataOrNull;
      client.setQueryData<String>(key, 'a2');
      expect(observer.currentResult.dataOrNull, isNot(same(first)),
          reason: 'throughDefaults: $throughDefaults');
      expect(observer.currentResult.dataOrNull, <String>['a']);
      unsubscribe();
      client.clear();
    }

    // The cache write is off too, and the opt-out is one stable instance per
    // data type, so options built with it compare equal across rebuilds.
    final client = testClient();
    final key = queryKey();
    final options = QueryOptions<List<int>>(
        queryKey: key, structuralSharing: noStructuralSharing());
    client.queryCache.build(client, client.defaultQueryOptions(options));
    client.setQueryData<List<int>>(key, <int>[1]);
    final written = <int>[1];
    client.setQueryData<List<int>>(key, written);
    expect(client.getQueryData<List<int>>(key), same(written));
    expect(noStructuralSharing<List<int>>(),
        same(noStructuralSharing<List<int>>()));
    expect(
        client.defaultQueryOptions(options),
        client.defaultQueryOptions(QueryOptions<List<int>>(
            queryKey: key, structuralSharing: noStructuralSharing())));
    client.clear();
  });

  testFakeAsync(
      'F5 a void or nullable mutation restores as success without data; a '
      'non-nullable one is still refused', (time) async {
    final client = testClient();
    final voidMutation = client.mutationCache.build<void, int, void>(
      client,
      client.defaultMutationOptions(
          MutationOptions<void, int, void>(mutationFn: (_) async {})),
      state: const MutationState<void, int, void>(
        status: MutationStatus.success,
        variables: 1,
        hasVariables: true,
      ),
    );
    expect(voidMutation.state.status, MutationStatus.success);
    final voidObserver = MutationObserver<void, int, void>(
      client,
      MutationOptions<void, int, void>(mutationFn: (_) async {}),
    );
    expect(voidObserver.currentResult.isSuccess, isFalse);

    final nullable = client.mutationCache.build<String?, int, void>(
      client,
      client.defaultMutationOptions(
          MutationOptions<String?, int, void>(mutationFn: (_) async => null)),
      state: const MutationState<String?, int, void>(
        status: MutationStatus.success,
        variables: 1,
        hasVariables: true,
      ),
    );
    expect(nullable.state.data, isNull);

    expect(
      () => client.mutationCache.build<String, int, void>(
        client,
        client.defaultMutationOptions(
            MutationOptions<String, int, void>(mutationFn: (v) async => '$v')),
        state: const MutationState<String, int, void>(
          status: MutationStatus.success,
          variables: 1,
          hasVariables: true,
        ),
      ),
      throwsArgumentError,
    );
    client.clear();
  });

  testFakeAsync(
      'F5 the query twin, revised by R2-3: a successful query state must hold '
      'data whatever its type; one that resolved to null says so with hasData',
      (time) async {
    final client = testClient();
    // Refused through both doors, for `void`, nullable and non-nullable data
    // alike. F5 had accepted the first two; a `select` to a non-nullable type
    // then threw in the observer's constructor.
    void refusedByBuild<T>() => expect(
          () => client.queryCache.build<T>(
            client,
            client.defaultQueryOptions(QueryOptions<T>(queryKey: queryKey())),
            state: QueryState<T>(status: QueryStatus.success),
          ),
          throwsArgumentError,
          reason: '$T',
        );
    refusedByBuild<void>();
    refusedByBuild<String?>();
    refusedByBuild<String>();

    final nullableKey = queryKey();
    client.setQueryData<String?>(nullableKey, 'seed');
    final query = client.queryCache.get<String?>(nullableKey)!;
    expect(
      () => query
          .setState(const QueryState<String?>(status: QueryStatus.success)),
      throwsArgumentError,
    );
    expect(query.state.data, 'seed', reason: 'a refused state changes nothing');

    // A query that resolved to nothing is restored with `hasData: true`.
    client.queryCache.build<void>(
      client,
      client.defaultQueryOptions(QueryOptions<void>(queryKey: queryKey())),
      state: const QueryState<void>(status: QueryStatus.success, hasData: true),
    );
    query.setState(const QueryState<String?>(
        status: QueryStatus.success, hasData: true, data: null));
    final observer = client.observe<String?, String?>(
      QueryObserverOptions<String?>(
        queryKey: nullableKey,
        queryFn: (_) => null,
        enabled: Enabled.no,
      ),
    );
    expect(observer.currentResult.isSuccess, isTrue);
    expect(observer.currentResult.dataOrNull, isNull);
    client.clear();
  });

  testFakeAsync(
      'F6 removing a restored scope head releases the queue it was blocking, '
      'even if its scope moves before the release runs', (time) async {
    final client = testClient();
    var ran = 0;
    MutationOptions<String, String, void> scoped(String scope) =>
        MutationOptions<String, String, void>(
          scope: MutationScope(scope),
          mutationFn: (v) async {
            ran++;
            return v;
          },
        );
    MutationState<String, String, void> pending(String variables) =>
        MutationState<String, String, void>(
          status: MutationStatus.pending,
          variables: variables,
          hasVariables: true,
        );

    final head = client.mutationCache.build<String, String, void>(
      client,
      client.defaultMutationOptions(scoped('queue')),
      state: pending('head'),
    );
    final waiter = client.mutationCache.build<String, String, void>(
      client,
      client.defaultMutationOptions(scoped('queue')),
      state: pending('waiter'),
    );

    client.mutationCache.remove(head);
    // Between the removal and its microtask, the removed entry moves scope.
    head.setOptions(client.defaultMutationOptions(scoped('elsewhere')));
    await time.advance(ms(10));

    expect(ran, 1, reason: 'the queue the head was blocking is released');
    expect(waiter.state.status, MutationStatus.success);
    expect(waiter.state.data, 'waiter');
    client.clear();
    await time.advance(ms(10));
  });

  test(
      'R2-1 a default set against a SplayTreeSet<double> holding both 0.0 and '
      '-0.0 is not equal, on every platform', () {
    // dart2js's default set answers `lookup` with its argument for numbers,
    // and `0.0 == -0.0`: a lookup round trip paired both of `next`'s zeros
    // with `previous`'s one and never looked for `3.0`.
    final previous = <double>{0.0, 1.0, 3.0};
    final next = SplayTreeSet<double>()..addAll(<double>[-0.0, 0.0, 1.0]);
    expect(next, hasLength(3), reason: 'compareTo keeps -0.0 and 0.0 apart');
    expect(replaceEqualDeep<Set<double>>(previous, next), same(next));
    expect(replaceEqualDeep<Set<double>>(next, previous), same(previous));

    final client = testClient();
    final key = queryKey();
    client.setQueryData<Set<double>>(key, previous);
    client.setQueryData<Set<double>>(key, next);
    expect(client.getQueryData<Set<double>>(key), same(next));
    client.clear();

    // Equal members are still shared across the two set types.
    final zeros = <double>{0.0, 1.0};
    expect(
        replaceEqualDeep<Set<double>>(
            zeros, SplayTreeSet<double>()..addAll(<double>[1.0, 0.0])),
        same(zeros));
  });

  test(
      "R2-2 set comparison asks a set for its length and members only, never "
      'its lookup, contains or remove', () {
    // `package:collection`'s `MapKeySet.lookup` throws; so does every
    // policy-dependent method of this set.
    final previous = _MembersOnlySet<Object?>(<Object?>[
      'a',
      <int>[1],
      null
    ]);
    final same_ = _MembersOnlySet<Object?>(<Object?>[
      <int>[1],
      null,
      'a'
    ]);
    final changed = _MembersOnlySet<Object?>(<Object?>[
      'a',
      <int>[2],
      null
    ]);
    expect(replaceEqualDeep<Set<Object?>>(previous, same_), same(previous));
    expect(replaceEqualDeep<Set<Object?>>(previous, changed), same(changed));
    // Nested inside the shapes the walk descends into, too.
    final nested = <String, Object?>{
      'ids': <Object?>[previous]
    };
    expect(
        replaceEqualDeep<Map<String, Object?>>(nested, <String, Object?>{
          'ids': <Object?>[same_]
        }),
        same(nested));

    final client = testClient();
    final key = queryKey();
    client.setQueryData<Set<Object?>>(key, previous);
    expect(
        () => client.setQueryData<Set<Object?>>(key, changed), returnsNormally);
    expect(client.getQueryData<Set<Object?>>(key), same(changed));
    client.clear();
  });

  test(
      "R2-4 a hand-written set whose lookup returns its argument cannot "
      'reopen F1', () {
    final previous = _ArgumentLookupSet(LinkedHashSet<String>(
      equals: (a, b) => a.toLowerCase() == b.toLowerCase(),
      hashCode: (value) => value.toLowerCase().hashCode,
    )..add('Alpha'));
    final next = <String>{'alpha'};
    expect(replaceEqualDeep<Set<String>>(previous, next), same(next));
    expect(replaceEqualDeep<Set<String>>(next, previous), same(previous));
  });

  test(
      'R3-1 a set walk spreads fractional doubles across buckets instead of '
      'piling them into a few', () {
    // The walk buckets members in a map that spreads its keys by their low
    // bits. On the VM a fractional double hashes to a value whose low bits
    // barely vary (`0.5` is `0x3fe000003fe00000`): 10 000 half-integers
    // shared 64 low-12-bit patterns, so nearly every member landed in the
    // same few slots and each comparison probed a long chain — 1.6 s per
    // cache write at 50 000 members. The cost lives inside the map, so it is
    // pinned here by the spread of the keys it is given, not by a clock.
    for (final entry in <String, double Function(int)>{
      'half-integers': (i) => i + 0.5,
      'quarters': (i) => i / 4,
      'prices': (i) => i / 100,
    }.entries) {
      final lowBits = <int>{
        for (var i = 0; i < 10000; i++)
          sharingBucketOf(entry.value(i), 0) & 0xfff,
      };
      expect(lowBits.length, greaterThan(3000),
          reason:
              '${entry.key}: ${lowBits.length} of 4096 low-12-bit patterns');
    }
  });

  test(
      'R3-1 follow-up: keys and nested data holding a fractional double spread '
      'their hash codes', () {
    // Dart's composite hashes combine through a 29-bit mask, and a VM
    // fractional double varies only in its high hash bits, so a leaf hash
    // passed straight into `Object.hashAll` collapsed: 10 000 keys
    // `['price', i + 0.5]` shared 396 hash codes, and every `setQueryData`
    // and lookup on them scanned a long chain (140 ms for 10 000, 1.7 s for
    // 50 000, against 15 ms and 86 ms for int keys). Leaves are spread before
    // they are combined, in the key and in the sharing walk alike. Counted,
    // not timed. The collapse is the VM's: compiled to JavaScript a double
    // hashes by value, so the raw version passes there too.
    const n = 10000;
    final keyHashes = <int>{
      for (var i = 0; i < n; i++) QueryKey(['price', i + 0.5]).hashCode,
    };
    expect(keyHashes.length, greaterThan(9000),
        reason: '${keyHashes.length} distinct hash codes for $n price keys');

    for (final entry in <String, Object Function(int)>{
      'maps {price: i + 0.5}': (i) => {'price': i + 0.5},
      'sets {i + 0.5}': (i) => {i + 0.5},
      'lists [1.0, i + 0.5]': (i) => [1.0, i + 0.5],
    }.entries) {
      final buckets = <int>{
        for (var i = 0; i < n; i++) sharingBucketOf(entry.value(i), 0),
      };
      expect(buckets.length, greaterThan(9000),
          reason: '${entry.key}: ${buckets.length} distinct buckets for $n');
    }
  });

  test(
      "R2-1 a QueryKey's set part agrees with == and hashCode for signed "
      'zeros, int and double, NaN and fractions, on every platform', () {
    // `QueryKey` keeps `containsAll`, on sets `_freeze` rebuilt with default
    // equality. Pinned where dart2js differs: numbers hash by value there,
    // `1` and `1.0` are one value, and `identical(nan, nan)` is false.
    const values = <Object>[
      0.0,
      -0.0,
      0,
      1,
      1.0,
      double.nan,
      0.5,
      -1.5,
      1e300,
      double.infinity,
    ];
    final shapes = <List<Object>>[
      for (final a in values) ...<List<Object>>[
        <Object>[a],
        for (final b in values) <Object>[a, b],
      ],
    ];
    for (final left in shapes) {
      for (final right in shapes) {
        final setLeft = QueryKey(<Object?>[left.toSet()]);
        final setRight = QueryKey(<Object?>[right.toSet()]);
        final equal = setLeft == setRight;
        expect(setRight == setLeft, equal, reason: '$left vs $right');
        if (equal) {
          expect(setLeft.hashCode, setRight.hashCode,
              reason: '$left vs $right');
        }
        // The set part answers what a multiset of its frozen members does
        // under the element rule every other part uses.
        final frozenLeft = (setLeft.parts.single! as Set<Object?>).toList();
        final frozenRight = (setRight.parts.single! as Set<Object?>).toList();
        var multisetEqual = frozenLeft.length == frozenRight.length;
        final unmatched = frozenLeft.toList();
        for (final member in frozenRight) {
          if (!multisetEqual) break;
          final index = unmatched.indexWhere((other) =>
              QueryKey(<Object?>[other]) == QueryKey(<Object?>[member]));
          if (index < 0) {
            multisetEqual = false;
          } else {
            unmatched.removeAt(index);
          }
        }
        expect(equal, multisetEqual, reason: '$left vs $right');
      }
    }
    expect(
        QueryKey(<Object?>[
          <Object?>{0.0}
        ]),
        QueryKey(<Object?>[
          <Object?>{-0.0}
        ]));
    expect(
        QueryKey(<Object?>[
          <Object?>{1}
        ]),
        QueryKey(<Object?>[
          <Object?>{1.0}
        ]));
  });

  testFakeAsync(
      'R2-3 a restored success-without-data query is refused, and one that '
      'resolved to null reaches a select to a non-nullable type', (time) async {
    for (final door in <String>['build', 'setState']) {
      final client = testClient();
      final key = queryKey();
      void restore(QueryState<int?> state) {
        if (door == 'build') {
          client.queryCache.build<int?>(
            client,
            client.defaultQueryOptions(QueryOptions<int?>(queryKey: key)),
            state: state,
          );
        } else {
          client.setQueryData<int?>(key, 1);
          client.queryCache.get<int?>(key)!.setState(state);
        }
      }

      expect(() => restore(const QueryState<int?>(status: QueryStatus.success)),
          throwsArgumentError,
          reason: door);
      client.clear();

      restore(const QueryState<int?>(
          status: QueryStatus.success, hasData: true, data: null));
      for (final enabled in <Enabled?>[null, Enabled.no]) {
        final observer = client.observe<int?, String>(
          QuerySelectOptions<int?, String>(
            queryKey: key,
            queryFn: (_) async => 7,
            enabled: enabled,
            staleTime: StaleTime.infinite,
            select: (value) => value?.toString() ?? 'none',
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        expect(observer.currentResult.dataOrNull, 'none',
            reason: '$door, enabled: $enabled');
        unsubscribe();
        observer.destroy();
      }
      client.clear();
    }
  });

  testFakeAsync(
      'R2-3 the mutation twin: a void or nullable success without data is '
      'safe on every path that reads it', (time) async {
    Future<void> probe<T>(MutationFn<T, int> mutationFn) async {
      final settled = <String>[];
      final client = testClient(
        mutationCache: MutationCache(
          onSuccess: (data, _, __, ___) => settled.add('cache $data'),
        ),
      );
      final key = queryKey();
      final options = MutationOptions<T, int, void>(
          mutationKey: key, mutationFn: mutationFn);
      final restored = client.mutationCache.build<T, int, void>(
        client,
        client.defaultMutationOptions(options),
        state: MutationState<T, int, void>(
          status: MutationStatus.success,
          variables: 1,
          hasVariables: true,
          isPaused: true,
        ),
      );

      // `MutationStateObserver`'s select gets the mutation itself, typed
      // `Object?`: nothing casts the data into a selection's type for it.
      final statuses = MutationStateObserver<MutationStatus>(client,
          filters: MutationFilters(mutationKey: key),
          select: (mutation) => mutation.state.status);
      final data = MutationStateObserver<String>(client,
          filters: MutationFilters(mutationKey: key),
          select: (mutation) => '${mutation.state.data}');
      final unsubscribeStatuses = statuses.subscribe((_) {});
      expect(statuses.currentResult, <MutationStatus>[MutationStatus.success]);
      expect(data.currentResult, <String>['null']);

      // Nothing resumes a settled entry, so no callback sees it.
      await client.resumePausedMutations();
      expect(settled, isEmpty, reason: '$T');

      // A `MutationObserver` only ever reflects mutations it ran itself, and
      // its result, callbacks and getters read its own `TData`.
      final observer = MutationObserver<T, int, void>(client, options);
      final unsubscribe = observer.subscribe((_) {});
      expect(observer.currentResult.isIdle, isTrue, reason: '$T');
      final calls = <String>[];
      observer.mutate(2,
          callbacks: MutateCallbacks<T, int, void>(
            onSuccess: (value, _, __) => calls.add('success $value'),
            onSettled: (value, _, __, ___, ____) => calls.add('settled $value'),
          ));
      await time.flushMicrotasks();
      expect(observer.currentResult.isSuccess, isTrue, reason: '$T');
      expect(observer.currentResult.dataOrNull, isNull);
      expect(calls, <String>['success null', 'settled null'], reason: '$T');
      expect(settled, <String>['cache null'], reason: '$T');

      // Running the restored entry again settles it with data.
      await restored.execute(3);
      expect(restored.state.hasData, isTrue, reason: '$T');

      unsubscribe();
      unsubscribeStatuses();
      observer.destroy();
      client.clear();
    }

    await probe<void>((_) async {});
    await probe<int?>((_) async => null);
  });
}
