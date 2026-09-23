/// Regressions of the release review of 2026-09-23, core query side: the
/// query, its retryer, the observers, their options and results, infinite
/// queries, `QueriesObserver` and `combine`. One test (or group) per finding,
/// named after its ID; PORTING_NOTES' "Release review 2026-09-23 — core query
/// side" has a row for each.
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A value class with identity equality whose `shareWith` is correct: it
/// returns a new instance equal in content to `this`, never `previous`.
class _Box implements StructurallyShareable<_Box> {
  _Box(this.items);
  final List<int> items;
  @override
  _Box shareWith(_Box previous) =>
      _Box(replaceEqualDeep<List<int>>(previous.items, items));
}

void main() {
  group('CORE-2 / L2-5 the #84 baseline is what setOptions last saw', () {
    testFakeAsync(
        'CORE-2a: getOptimisticResult(next) then setOptions(next), '
        'enabled no -> yes, fetches as upstream does', (time) async {
      final client = testClient();
      final key = queryKey();
      var calls = 0;
      QueryObserverOptions<int> opts(Enabled e) => QueryObserverOptions(
            queryKey: key,
            enabled: e,
            queryFn: (_) async => ++calls,
          );
      final observer = QueryObserver<int, int>(client, opts(Enabled.no));
      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      expect(calls, 0);
      final next = opts(Enabled.yes);
      observer.getOptimisticResult(next); // useBaseQuery's order
      observer.setOptions(next);
      await time.flushMicrotasks();
      expect(calls, 1);
      unsubscribe();
      client.clear();
    });

    testFakeAsync(
        'CORE-2b: an outside-state flip is not swallowed by a query update '
        'before the rebuild', (time) async {
      final client = testClient();
      final key = queryKey();
      var flag = false;
      var calls = 0;
      final options = QueryObserverOptions<int>(
        queryKey: key,
        enabled: Enabled.when((_) => flag),
        queryFn: (_) async => ++calls,
      );
      final observer = QueryObserver<int, int>(client, options);
      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      flag = true;
      await client.invalidateQueries(
          filters: QueryFilters(queryKey: key), refetchType: RefetchType.none);
      observer.setOptions(options); // the rebuild
      await time.flushMicrotasks();
      expect(calls, 1);
      unsubscribe();
      client.clear();
    });

    testFakeAsync(
        'L2-5: the preview of a re-enabled outside-state predicate shows the '
        'fetch setOptions is about to start', (time) async {
      final client = testClient();
      var connected = false;
      final options = QueryObserverOptions<int>(
        queryKey: queryKey(),
        enabled: Enabled.when((_) => connected),
        queryFn: (_) async => 1,
      );
      final observer = QueryObserver<int, int>(client, options);
      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      connected = true;
      expect(observer.getOptimisticResult(options).isFetching, isTrue);
      observer.setOptions(options);
      await time.flushMicrotasks();
      expect(observer.currentResult.dataOrNull, 1);
      unsubscribe();
      client.clear();
    });
  });

  testFakeAsync(
      'L2-1: a setOptions rolled back by a throwing InitialData.compute keeps '
      'the previous key\'s fetch', (time) async {
    final client = testClient();
    final keyA = queryKey();
    final keyB = queryKey();
    client.queryCache.build<int>(
        client,
        client.defaultQueryOptions<int>(
            QueryOptions<int>(queryKey: keyB, queryFn: (_) async => 0)));
    var completed = false;
    final observer = QueryObserver<int, int>(
        client,
        QueryObserverOptions<int>(
          queryKey: keyA,
          queryFn: (ctx) async {
            ctx.signal;
            await sleep(ms(100));
            completed = true;
            return 1;
          },
        ));
    final unsubscribe = observer.subscribe((_) {});
    await time.advance(ms(10));
    expect(
        () => observer.setOptions(QueryObserverOptions<int>(
              queryKey: keyB,
              queryFn: (_) async => 2,
              initialData: InitialData.compute(() => throw StateError('seed')),
            )),
        throwsStateError);
    expect(observer.currentQuery.queryKey, keyA);
    await time.advance(ms(200));
    expect(completed, isTrue);
    expect(observer.currentQuery.state.data, 1);
    expect(observer.currentResult.dataOrNull, 1);
    unsubscribe();
    client.clear();
  });

  group('L2-2 a keepPrevious placeholder is not the new key\'s stale data', () {
    String select(int v) {
      if (v == 2) throw StateError('bad');
      return 'v$v';
    }

    String otherSelect(int v) {
      if (v == 2) throw StateError('bad');
      return 'v$v';
    }

    QuerySelectOptions<int, String> opts(
            QueryKey key, int value, String Function(int) selector) =>
        QuerySelectOptions<int, String>(
          queryKey: key,
          queryFn: (_) async {
            await sleep(ms(10));
            return value;
          },
          select: selector,
          placeholderData: const PlaceholderData.keepPrevious(),
        );

    for (final (name, second) in [
      ('the memoised selection', select),
      ('a selection re-run over the placeholder', otherSelect),
    ]) {
      testFakeAsync('through $name', (time) async {
        final client = testClient();
        final keyA = queryKey();
        final keyB = queryKey();
        final observer =
            QueryObserver<int, String>(client, opts(keyA, 1, select));
        final unsubscribe = observer.subscribe((_) {});
        await time.advance(ms(20));
        expect(observer.currentResult.dataOrNull, 'v1');
        observer.setOptions(opts(keyB, 2, second));
        expect(observer.currentResult.isPlaceholderData, isTrue);
        expect(observer.currentResult.dataOrNull, 'v1');
        await time.advance(ms(20));
        final error = observer.currentResult as QueryError<String>;
        expect(error.hasStaleData, isFalse,
            reason: 'staleData=${error.staleData}');
        expect(error.isLoadingError, isTrue);
        expect(error.isRefetchError, isFalse);
        unsubscribe();
        client.clear();
      });
    }
  });

  group('L1-1 a CancelledError the query function throws is an ordinary error',
      () {
    QueryOptions<int> innerOptions(QueryKey inner) => QueryOptions<int>(
          queryKey: inner,
          queryFn: (_) async {
            await sleep(ms(100));
            return 1;
          },
        );

    testFakeAsync('a reverting cancel of the query it awaits (client.query)',
        (time) async {
      final client = testClient();
      final inner = queryKey();
      final outer = queryKey();
      Object? outerError;
      client
          .query(QueryOptions<int>(
              queryKey: outer,
              queryFn: (ctx) async =>
                  await ctx.client.query(innerOptions(inner)) + 1))
          .then<void>((_) {}, onError: (Object e) => outerError = e)
          .ignore();
      await time.advance(ms(10));
      await client.cancelQueries(filters: QueryFilters(queryKey: inner));
      await time.advance(ms(10));
      expect(outerError, isA<CancelledError>());
      final state = client.getQueryState<int>(outer)!;
      expect(state.fetchStatus, FetchStatus.idle);
      expect(state.status, QueryStatus.error);
      expect(state.error, isA<CancelledError>());
      // A propagated cancel is no failure of the outer query's own source,
      // so it does not count towards giving up (the C rule, kept).
      expect(state.consecutiveErrorCount, 0);
      expect(client.isFetching(), 0);
      await time.advance(const Duration(minutes: 30));
      expect(client.queryCache.peek(outer), isNull,
          reason: 'an idle entry nobody observes is collected');
    });

    testFakeAsync('a silent cancel (reset) of the query it awaits, observed',
        (time) async {
      final client = testClient();
      final inner = queryKey();
      final outer = queryKey();
      final observer = client.observe<int, int>(QueryObserverOptions<int>(
        queryKey: outer,
        retry: RetryPolicy.never,
        queryFn: (ctx) async => await ctx.client.query(innerOptions(inner)) + 1,
      ));
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(10));
      await client.resetQueries(filters: QueryFilters(queryKey: inner));
      await time.advance(ms(10));
      expect(observer.currentQuery.state.fetchStatus, FetchStatus.idle);
      expect(observer.currentResult.isFetching, isFalse);
      expect(observer.currentResult, isA<QueryError<int>>());
      unsubscribe();
      client.clear();
    });

    testFakeAsync('the query\'s own cancel still reverts and stays silent',
        (time) async {
      final client = testClient();
      final key = queryKey();
      client.setQueryData<int>(key, 7);
      final observer = client.observe<int, int>(QueryObserverOptions<int>(
        queryKey: key,
        queryFn: (_) async {
          await sleep(ms(100));
          return 8;
        },
      ));
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(10));
      expect(observer.currentResult.isFetching, isTrue);
      await client.cancelQueries(filters: QueryFilters(queryKey: key));
      expect(observer.currentResult.dataOrNull, 7);
      expect(observer.currentResult.isFetching, isFalse);
      expect(observer.currentResult.isError, isFalse);
      await time.advance(ms(200));
      expect(observer.currentResult.dataOrNull, 7);
      unsubscribe();
      client.clear();
    });
  });

  group('CORE-1 a correct shareWith on a class without value ==', () {
    test('the walk takes its result', () {
      final previous = _Box([1, 2, 3]);
      final next = _Box([1, 2, 4]);
      final shared = replaceEqualDeep<_Box>(previous, next);
      expect(shared, isNot(same(previous)));
      expect(shared.items, [1, 2, 4]);
    });

    testFakeAsync('a refetch through it succeeds', (time) async {
      final client = testClient();
      var n = 0;
      final observer = QueryObserver<_Box, _Box>(
          client,
          QueryObserverOptions(
            queryKey: queryKey(),
            retry: RetryPolicy.never,
            queryFn: (_) async => _Box([1, 2, ++n]),
          ));
      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      await observer.refetch();
      expect(observer.currentResult.isSuccess, isTrue,
          reason: '${observer.currentQuery.state.error}');
      expect(observer.currentResult.dataOrNull?.items, [1, 2, 2]);
      unsubscribe();
      client.clear();
    });
  });

  group('L3-1 a plain fetch of an infinite key borrows the paging', () {
    InfiniteQueryObserverOptions<int, int> feed(
            QueryKey key, List<int> calls) =>
        InfiniteQueryObserverOptions<int, int>(
          queryKey: key,
          pageFn: (context) async {
            calls.add(context.pageParam);
            await sleep(ms(10));
            return context.pageParam * 10;
          },
          initialPageParam: 1,
          getNextPageParam: (page, pages, param, params) => param + 1,
        );

    testFakeAsync('client.query with no query function', (time) async {
      final client = testClient();
      final key = queryKey();
      final calls = <int>[];
      final observer = InfiniteQueryObserver(client, feed(key, calls));
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(10));
      observer.fetchNextPage().ignore();
      await time.advance(ms(10));
      expect(observer.currentResult.dataOrNull?.pages, [10, 20]);
      Object? error;
      InfiniteData<int, int>? data;
      client
          .query<InfiniteData<int, int>>(QueryOptions(
              queryKey: key,
              staleTime: StaleTime.zero,
              retry: RetryPolicy.never))
          .then((value) => data = value, onError: (Object e) => error = e)
          .ignore();
      await time.advance(ms(50));
      expect(error, isNull);
      expect(data?.pages, [10, 20]);
      expect(observer.currentResult.isSuccess, isTrue);
      unsubscribe();
      client.clear();
    });

    testFakeAsync('a select-only reader, and an invalidation after it',
        (time) async {
      final client = testClient();
      final key = queryKey();
      final calls = <int>[];
      final observer = InfiniteQueryObserver(client, feed(key, calls));
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(10));
      observer.fetchNextPage().ignore();
      await time.advance(ms(10));
      calls.clear();
      final reader = QueryObserver<InfiniteData<int, int>, int>(
          client,
          QuerySelectOptions<InfiniteData<int, int>, int>(
              queryKey: key, select: (d) => d.pages.length));
      final stopReading = reader.subscribe((_) {});
      await time.advance(ms(50));
      expect(reader.currentResult.isSuccess, isTrue,
          reason: '${reader.currentResult}');
      expect(reader.currentResult.dataOrNull, 2);
      expect(observer.currentResult.isSuccess, isTrue);
      expect(calls, [1, 2], reason: 'the mount refetched both pages');
      calls.clear();
      client.invalidateQueries(filters: QueryFilters(queryKey: key)).ignore();
      await time.advance(ms(50));
      expect(calls, [1, 2]);
      expect(observer.currentResult.isSuccess, isTrue);
      stopReading();
      unsubscribe();
      client.clear();
    });
  });

  testFakeAsync(
      'L3-3: a setQueries that throws in a member\'s setOptions leaves the '
      'collection as it was', (time) async {
    final client = testClient();
    final k1 = queryKey();
    final k2 = queryKey();
    var k2Fetches = 0;
    final observer = QueriesObserver<int, int>(client, [
      QueryObserverOptions<int>(
          queryKey: k1,
          retry: RetryPolicy.never,
          queryFn: (_) async {
            await sleep(ms(10));
            throw StateError('x');
          }),
    ]);
    final unsubscribe = observer.subscribe((_) {});
    await time.advance(ms(20));
    final before = observer.observers.single;
    expect(
        () => observer.setQueries([
              QueryObserverOptions<int>(
                  queryKey: k1,
                  queryFn: (_) async => 1,
                  initialData:
                      InitialData.compute(() => throw StateError('seed'))),
              QueryObserverOptions<int>(
                  queryKey: k2,
                  queryFn: (_) async {
                    k2Fetches++;
                    return 2;
                  }),
            ]),
        throwsStateError);
    expect(observer.observers, [same(before)]);
    expect(observer.currentResult, hasLength(1));
    expect(before.hasListeners, isTrue);
    await time.advance(ms(20));
    expect(k2Fetches, 0, reason: 'k2 was never taken on');
    expect(client.queryCache.peek(k2)?.observersCount ?? 0, 0);

    // The next setQueries works from the unchanged collection.
    observer.setQueries([
      QueryObserverOptions<int>(queryKey: k1, queryFn: (_) async => 1),
      QueryObserverOptions<int>(
          queryKey: k2,
          queryFn: (_) async {
            k2Fetches++;
            return 2;
          }),
    ]);
    await time.advance(ms(20));
    expect(k2Fetches, 1);
    expect(observer.currentResult, hasLength(2));
    unsubscribe();
    client.clear();
  });

  testFakeAsync(
      'LIB-5: CombinedResult.refetch and retry pass cancelRefetch through, so '
      'two combinations sharing a source fetch it once', (time) async {
    final client = testClient();
    var shared = 0;
    var fail = false;
    QueryObserver<int, int> observe(Future<int> Function() fn) =>
        QueryObserver<int, int>(
            client,
            QueryObserverOptions<int>(
              queryKey: queryKey(),
              retry: RetryPolicy.never,
              queryFn: (_) => fn(),
            ));
    final common = observe(() async {
      shared++;
      await sleep(ms(10));
      if (fail) throw StateError('down');
      return shared;
    });
    final a = observe(() async => 1);
    final b = observe(() async => 2);
    final unsubscribe = [
      for (final o in [common, a, b]) o.subscribe((_) {})
    ];
    await time.advance(ms(20));
    expect(shared, 1);
    CombinedResult<int> first() =>
        (common.currentResult, a.currentResult).combine((x, y) => x + y);
    CombinedResult<int> second() =>
        (common.currentResult, b.currentResult).combine((x, y) => x + y);

    Future.wait([
      first().refetch(cancelRefetch: false),
      second().refetch(cancelRefetch: false),
    ]).ignore();
    await time.advance(ms(20));
    expect(shared, 2, reason: 'the second refetch joined the first');

    // The default still cancels and starts again, as a single refetch does.
    Future.wait([first().refetch(), second().refetch()]).ignore();
    await time.advance(ms(20));
    expect(shared, 4);

    fail = true;
    common.refetch().ignore();
    await time.advance(ms(20));
    expect((first() as CombinedData<int>).refetchError, isA<StateError>());
    fail = false;
    Future.wait([
      first().retry(cancelRefetch: false),
      second().retry(cancelRefetch: false),
    ]).ignore();
    await time.advance(ms(20));
    expect(shared, 6, reason: 'one failed refetch, then one joined retry');
    for (final u in unsubscribe) {
      u();
    }
    client.clear();
  });

  group('L2-4 / L3-2 value equality is symmetric across type arguments', () {
    void symmetric(Object a, Object b) {
      expect(a == b, b == a, reason: '$a vs $b');
      if (a == b) expect(a.hashCode, b.hashCode);
    }

    test('L2-4: InitialData and PlaceholderData', () {
      int compute() => 1;
      Null placeholder(Object? previous, Object? query) => null;
      symmetric(const InitialDataValue<num>(1), const InitialDataValue<int>(1));
      symmetric(
          InitialDataCompute<num>(compute), InitialDataCompute<int>(compute));
      symmetric(const PlaceholderDataKeepPrevious<num>(),
          const PlaceholderDataKeepPrevious<int>());
      symmetric(const PlaceholderDataValue<num>(1),
          const PlaceholderDataValue<int>(1));
      symmetric(PlaceholderDataCompute<int>(placeholder),
          PlaceholderDataCompute<num>(placeholder));
      // Same type arguments stay equal.
      expect(const InitialDataValue<int>(1), const InitialDataValue<int>(1));
      expect(const PlaceholderDataValue<int>(1),
          const PlaceholderDataValue<int>(1));
    });

    test('L3-2: InfiniteData', () {
      final a = InfiniteData<int, int>(pages: const [], pageParams: const []);
      final b = InfiniteData<num, int>(pages: const [], pageParams: const []);
      symmetric(a, b);
      expect(a, InfiniteData<int, int>(pages: const [], pageParams: const []));
    });
  });

  testFakeAsync(
      'L2-3: a StaleTime.dynamic over outside state re-arms the stale timer '
      'on setOptions', (time) async {
    final client = testClient();
    var fresh = const Duration(hours: 1);
    final options = QueryObserverOptions<int>(
      queryKey: queryKey(),
      staleTime: StaleTime.dynamic((_) => StaleTime.duration(fresh)),
      queryFn: (_) async => 1,
    );
    final observer = QueryObserver<int, int>(client, options);
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(observer.currentResult.isStale, isFalse);
    fresh = const Duration(seconds: 1);
    observer.setOptions(options);
    await time.advance(const Duration(seconds: 5));
    expect(observer.currentResult.isStale, isTrue);
    expect(observer.currentQuery.isStale(), isTrue);
    unsubscribe();
    client.clear();
  });

  testFakeAsync(
      'LIB-2: after a manual write the result is a success and still carries '
      'the failures in a row', (time) async {
    final client = testClient();
    final key = queryKey();
    final observer = QueryObserver<int, int>(
        client,
        QueryObserverOptions<int>(
          queryKey: key,
          retry: RetryPolicy.never,
          queryFn: (_) async => throw StateError('unreachable'),
        ));
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    for (var i = 0; i < 2; i++) {
      observer.refetch().ignore();
      await time.flushMicrotasks();
    }
    expect(observer.currentResult, isA<QueryError<int>>());
    expect(observer.currentResult.consecutiveErrorCount, 3);

    client.setQueryData<int>(key, 1);
    await time.flushMicrotasks();
    expect(observer.currentResult, isA<QuerySuccess<int>>(),
        reason: 'upstream: a manual write clears the error');
    expect(observer.currentResult.consecutiveErrorCount, 3,
        reason: 'but not the count a "gave up" is read from');
    expect(observer.currentResult.consecutiveErrorCount,
        observer.currentQuery.state.consecutiveErrorCount);
    unsubscribe();
    client.clear();
  });

  test(
      'LIB-3: withSelect carries every field of the plain options over to '
      'the select shape', () {
    final client = testClient();
    Future<int> fetch(QueryFunctionContext context) async => 1;
    int share(int? previous, int next) => next;
    DateTime? updatedAt() => null;
    String select(int data) => '$data';
    final plain = QueryObserverOptions<int>(
      queryKey: queryKey(),
      queryFn: fetch,
      enabled: Enabled.no,
      staleTime: StaleTime.infinite,
      gcTime: GcTime.never,
      retry: RetryPolicy.never,
      retryDelay: const RetryDelay.fixed(Duration(seconds: 1)),
      networkMode: NetworkMode.always,
      initialData: const InitialDataValue<int>(1),
      initialDataUpdatedAtCompute: updatedAt,
      structuralSharing: share,
      meta: 'meta',
      placeholderData: const PlaceholderDataValue<int>(0),
      refetchOnMount: RefetchOn.never,
      refetchOnWindowFocus: RefetchOn.always,
      refetchOnReconnect: RefetchOn.never,
      refetchInterval: const RefetchInterval.every(Duration(minutes: 1)),
      refetchIntervalInBackground: true,
      retryOnMount: false,
    );
    final derived = plain.withSelect(select);
    expect(derived, isA<QuerySelectOptions<int, String>>());
    expect(derived.select, same(select));

    // Every field the plain options show is shown again, with the same
    // value, plus the select — a field a future edit forgets to carry over
    // is missing from the derived string.
    Map<String, String> fields(Object options) => {
          for (final match
              in RegExp(r', (\w+): ([^,]*)').allMatches(options.toString()))
            match.group(1)!: match.group(2)!,
        };
    final plainFields = fields(plain);
    expect(plainFields.length, 18, reason: 'every field set but two');
    expect(fields(derived)..remove('select'), plainFields);

    // And resolved, the two spellings are the same options.
    final spelledOut = QuerySelectOptions<int, String>(
      queryKey: plain.queryKey,
      select: select,
      queryFn: fetch,
      enabled: Enabled.no,
      staleTime: StaleTime.infinite,
      gcTime: GcTime.never,
      retry: RetryPolicy.never,
      retryDelay: const RetryDelay.fixed(Duration(seconds: 1)),
      networkMode: NetworkMode.always,
      initialData: const InitialDataValue<int>(1),
      initialDataUpdatedAtCompute: updatedAt,
      structuralSharing: share,
      meta: 'meta',
      placeholderData: const PlaceholderDataValue<int>(0),
      refetchOnMount: RefetchOn.never,
      refetchOnWindowFocus: RefetchOn.always,
      refetchOnReconnect: RefetchOn.never,
      refetchInterval: const RefetchInterval.every(Duration(minutes: 1)),
      refetchIntervalInBackground: true,
      retryOnMount: false,
    );
    expect(client.defaultQueryObserverOptions(derived),
        client.defaultQueryObserverOptions(spelledOut));

    // The paged shape, the same way.
    final paged = InfiniteQueryObserverOptions<int, int>(
      queryKey: queryKey(),
      pageFn: (context) async => context.pageParam,
      initialPageParam: 0,
      getNextPageParam: (page, pages, pageParam, pageParams) => pageParam + 1,
      getPreviousPageParam: (page, pages, pageParam, pageParams) => null,
      maxPages: 3,
      enabled: Enabled.no,
      staleTime: StaleTime.infinite,
      gcTime: GcTime.never,
      retry: RetryPolicy.never,
      networkMode: NetworkMode.always,
      meta: 'meta',
      refetchOnMount: RefetchOn.never,
      refetchIntervalInBackground: true,
      retryOnMount: false,
    );
    final pagedDerived =
        paged.withSelect((data) => data.pages.fold(0, (a, b) => a + b));
    expect(pagedDerived, isA<InfiniteQuerySelectOptions<int, int, int>>());
    final pagedFields = fields(paged);
    expect(pagedFields.length, greaterThanOrEqualTo(10));
    expect(fields(pagedDerived)..remove('select'), pagedFields);
    client.clear();
  });
}
