import 'dart:async';

import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Counts the connectivity/focus callbacks the client is supposed to forward.
///
/// Upstream spies on `queryCache.onFocus` / `onOnline`; Dart has no runtime
/// spies, so the interception is a subclass.
class _SpyCache extends QueryCache {
  int focusCalls = 0;
  int onlineCalls = 0;

  @override
  void onFocus() {
    focusCalls++;
    super.onFocus();
  }

  @override
  void onOnline() {
    onlineCalls++;
    super.onOnline();
  }
}

/// Counts the mutation resumptions the client is supposed to trigger.
class _SpyMutationCache extends MutationCache {
  int resumeCalls = 0;

  @override
  Future<void> resumePausedMutations() {
    resumeCalls++;
    return super.resumePausedMutations();
  }
}

class Boxed {
  const Boxed(this.value);
  final String value;

  @override
  bool operator ==(Object other) => other is Boxed && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Boxed($value)';
}

/// Port of `query/packages/query-core/src/__tests__/queryClient.test.tsx`.
///
/// The upstream file also covers infinite queries, `ensureQueryData`,
/// `skipToken`, persister-driven network modes, mutations, and TypeScript-only
/// "should not type-error" cases. None of those exist in the port (or, for
/// mutations, not yet) — every omission is listed in PORTING_NOTES.md.
void main() {
  late QueryClient queryClient;
  late QueryCache queryCache;

  setUp(() {
    queryClient = QueryClient();
    queryCache = queryClient.queryCache;
    queryClient.mount();
  });

  tearDown(() {
    queryClient.clear();
    queryClient.unmount();
    focusManager.setFocused(null);
    onlineManager.setOnline(true);
  });

  QueryObserverOptions<String, String> str(
    QueryKey key, {
    QueryFn<String>? queryFn,
    GcDuration? gcTime,
    StaleDuration? staleTime,
    RetryOption? retry,
    Enabled? enabled,
    RefetchOn? refetchOnMount,
    Enabled? retryOnMount,
    String? Function()? initialData,
    Object? meta,
  }) => QueryObserverOptions<String, String>(
    queryKey: key,
    queryFn: queryFn,
    gcTime: gcTime,
    staleTime: staleTime,
    retry: retry,
    enabled: enabled,
    refetchOnMount: refetchOnMount,
    retryOnMount: retryOnMount,
    initialData: initialData,
    meta: meta,
  );

  group('defaultOptions', () {
    testFakeAsync('should merge defaultOptions', (time) async {
      final key = queryKey();
      final testClient = QueryClient(
        defaultOptions: QueryDefaults(queryFn: (_) async => 'data'),
      );

      await testClient.prefetchQuery(
        QueryObserverOptions<String, String>(queryKey: key),
      );

      expect(testClient.getQueryData<String>(key), 'data');
    });

    testFakeAsync('should merge defaultOptions when query is added to cache', (
      time,
    ) async {
      final key = queryKey();
      final testClient = QueryClient(
        defaultOptions: const QueryDefaults(gcTime: GcDuration.never),
      );

      await testClient.prefetchQuery(
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async => 'data',
        ),
      );

      expect(testClient.queryCache.find(key)!.options.gcTime, GcDuration.never);
    });

    test('should get defaultOptions', () {
      Future<String> queryFn(QueryFunctionContext _) async => 'data';
      final defaults = QueryDefaults(queryFn: queryFn);
      final testClient = QueryClient(defaultOptions: defaults);

      expect(testClient.defaultOptions, same(defaults));
      expect(testClient.defaultOptions.queryFn, same(queryFn));
    });
  });

  group('setQueryDefaults', () {
    test('should not trigger a fetch', () {
      final key = queryKey();
      queryClient.setQueryDefaults(
        key,
        QueryDefaults(queryFn: (_) async => 'data'),
      );
      expect(queryClient.getQueryData<String>(key), isNull);
    });

    testFakeAsync('should be able to override defaults', (time) async {
      final key = queryKey();
      queryClient.setQueryDefaults(
        key,
        QueryDefaults(queryFn: (_) async => 'data'),
      );
      final observer = QueryObserver<String, String>(queryClient, str(key));
      final result = await observer.refetch();
      expect(result.dataOrNull, 'data');
    });

    testFakeAsync('should match the query key partially', (time) async {
      final key = queryKey();
      queryClient.setQueryDefaults(
        key,
        QueryDefaults(queryFn: (_) async => 'data'),
      );
      final observer = QueryObserver<String, String>(
        queryClient,
        str(QueryKey([...key.parts, 'a'])),
      );
      final result = await observer.refetch();
      expect(result.dataOrNull, 'data');
    });

    testFakeAsync('should not match if the query key is a subset', (
      time,
    ) async {
      final key = queryKey();
      queryClient.setQueryDefaults(
        QueryKey([...key.parts, 'a']),
        QueryDefaults(queryFn: (_) async => 'data'),
      );
      final observer = QueryObserver<String, String>(
        queryClient,
        str(key, retry: RetryOption.never, enabled: Enabled.off),
      );
      final result = await observer.refetch();
      expect(result.status, QueryStatus.error);
    });

    test('should also set defaults for observers', () {
      final key = queryKey();
      queryClient.setQueryDefaults(
        key,
        QueryDefaults(queryFn: (_) async => 'data', enabled: Enabled.off),
      );
      final observer = QueryObserver<String, String>(queryClient, str(key));

      expect(observer.result.status, QueryStatus.pending);
      expect(observer.result.fetchStatus, FetchStatus.idle);
    });

    test('should update existing query defaults', () {
      final key = queryKey();
      queryClient.setQueryDefaults(
        key,
        QueryDefaults(queryFn: (_) async => 'data'),
      );
      queryClient.setQueryDefaults(
        key,
        const QueryDefaults(retry: RetryOption.never),
      );

      final defaults = queryClient.getQueryDefaults(key);
      expect(defaults.retry, RetryOption.never);
      expect(
        defaults.queryFn,
        isNull,
        reason: 'a second registration replaces the first, it does not merge',
      );
    });

    test('should merge defaults registered under different key prefixes', () {
      final key = queryKey();
      final todo = QueryKey([...key.parts, 'todo']);
      final detail = QueryKey([...key.parts, 'todo', 'detail']);

      queryClient.setQueryDefaults(
        todo,
        const QueryDefaults(retry: RetryOption.count(7)),
      );
      queryClient.setQueryDefaults(
        detail,
        const QueryDefaults(
          staleTime: StaleDuration.of(Duration(milliseconds: 5000)),
        ),
      );

      final defaults = queryClient.getQueryDefaults(detail);
      expect(defaults.retry, const RetryOption.count(7));
      expect(
        defaults.staleTime,
        const StaleDuration.of(Duration(milliseconds: 5000)),
      );
    });
  });

  group('setQueryData', () {
    test('should not crash if query could not be found', () {
      final key = queryKey();
      expect(
        () => queryClient.setQueryData<String>(
          QueryKey([...key.parts, 1]),
          (previous) => '${previous ?? ''}James',
        ),
        returnsNormally,
      );
    });

    test('should not crash when a key part is null', () {
      final key = queryKey();
      final withNull = QueryKey([
        ...key.parts,
        {'userId': null},
      ]);
      queryClient.setQueryData<String>(withNull, (_) => 'Old Data');
      expect(
        () => queryClient.setQueryData<String>(withNull, (_) => 'New Data'),
        returnsNormally,
      );
      expect(queryClient.getQueryData<String>(withNull), 'New Data');
    });

    test('should create a new query if query was not found 1', () {
      final key = queryKey();
      queryClient.setQueryData<String>(key, (_) => 'bar');
      expect(queryClient.getQueryData<String>(key), 'bar');
    });

    test('should create a new query if query was not found 2', () {
      final key = queryKey();
      queryClient.setQueryData<String>(key, (_) => 'qux');
      expect(queryClient.getQueryData<String>(key), 'qux');
    });

    test('should not create a new query if the updater returns null', () {
      final key = queryKey();
      expect(queryCache.find(key), isNull);
      queryClient.setQueryData<String>(key, (_) => null);
      expect(queryCache.find(key), isNull);
    });

    test('should not update query data if the updater returns null', () {
      final key = queryKey();
      queryClient.setQueryData<String>(key, (_) => 'qux');
      queryClient.setQueryData<String>(key, (_) => null);
      expect(queryClient.getQueryData<String>(key), 'qux');
    });

    test('should accept an update function', () {
      final key = queryKey();
      var calls = 0;

      queryClient.setQueryData<String>(key, (_) => 'test data');
      queryClient.setQueryData<String>(key, (oldData) {
        calls++;
        return 'new data + $oldData';
      });

      expect(calls, 1);
      expect(queryCache.find(key)!.state.data, 'new data + test data');
    });

    testFakeAsync('should not set isFetching to false', (time) async {
      final key = queryKey();
      unawaited(
        queryClient.prefetchQuery(
          QueryObserverOptions<int, int>(
            queryKey: key,
            queryFn: (_) => sleep(ms(10)).then((_) => 23),
          ),
        ),
      );

      var state = queryClient.getQueryState<int>(key)!;
      expect(state.data, isNull);
      expect(state.fetchStatus, FetchStatus.fetching);

      queryClient.setQueryData<int>(key, (_) => 42);

      state = queryClient.getQueryState<int>(key)!;
      expect(state.data, 42);
      expect(state.fetchStatus, FetchStatus.fetching);

      await time.advance(ms(10));

      state = queryClient.getQueryState<int>(key)!;
      expect(state.data, 23);
      expect(state.fetchStatus, FetchStatus.idle);
    });
  });

  group('setQueriesData', () {
    test('should update all existing, matching queries', () {
      queryClient.setQueryData<int>(const QueryKey(['key', 1]), (_) => 1);
      queryClient.setQueryData<int>(const QueryKey(['key', 2]), (_) => 2);

      final result = queryClient.setQueriesData<int>(
        const QueryFilters(queryKey: QueryKey(['key'])),
        (old) => old == null ? null : old + 5,
      );

      expect(result, [
        (const QueryKey(['key', 1]), 6),
        (const QueryKey(['key', 2]), 7),
      ]);
      expect(queryClient.getQueryData<int>(const QueryKey(['key', 1])), 6);
      expect(queryClient.getQueryData<int>(const QueryKey(['key', 2])), 7);
    });

    test('should accept queryFilters', () {
      queryClient.setQueryData<int>(const QueryKey(['key', 1]), (_) => 1);
      queryClient.setQueryData<int>(const QueryKey(['key', 2]), (_) => 2);
      final query1 = queryCache.find(const QueryKey(['key', 1]))!;

      final result = queryClient.setQueriesData<int>(
        QueryFilters(predicate: (query) => identical(query, query1)),
        (old) => old! + 5,
      );

      expect(result, [
        (const QueryKey(['key', 1]), 6),
      ]);
      expect(queryClient.getQueryData<int>(const QueryKey(['key', 1])), 6);
      expect(queryClient.getQueryData<int>(const QueryKey(['key', 2])), 2);
    });

    test('should not update non existing queries', () {
      final result = queryClient.setQueriesData<String>(
        const QueryFilters(queryKey: QueryKey(['key'])),
        (_) => 'data',
      );

      expect(result, isEmpty);
      expect(queryClient.getQueryData<String>(const QueryKey(['key'])), isNull);
    });
  });

  group('isFetching', () {
    testFakeAsync('should return length of fetching queries', (time) async {
      expect(queryClient.isFetching(), 0);

      unawaited(
        queryClient.prefetchQuery(
          str(queryKey(), queryFn: (_) => sleep(ms(10)).then((_) => 'data')),
        ),
      );
      expect(queryClient.isFetching(), 1);

      unawaited(
        queryClient.prefetchQuery(
          str(queryKey(), queryFn: (_) => sleep(ms(5)).then((_) => 'data')),
        ),
      );
      expect(queryClient.isFetching(), 2);

      await time.advance(ms(5));
      expect(queryClient.isFetching(), 1);

      await time.advance(ms(5));
      expect(queryClient.isFetching(), 0);
    });
  });

  group('isMutating', () {
    testFakeAsync('should return the number of running mutations', (
      time,
    ) async {
      expect(queryClient.isMutating(), 0);

      MutationObserver<String, Object?, Object?>(
        queryClient,
        MutationOptions<String, Object?, Object?>(
          mutationFn: (_, _) => sleep(ms(10)).then((_) => 'data'),
        ),
      ).mutate(null).ignore();
      expect(queryClient.isMutating(), 1);

      MutationObserver<String, Object?, Object?>(
        queryClient,
        MutationOptions<String, Object?, Object?>(
          mutationFn: (_, _) => sleep(ms(5)).then((_) => 'data'),
        ),
      ).mutate(null).ignore();
      expect(queryClient.isMutating(), 2);

      await time.advance(ms(5));
      expect(queryClient.isMutating(), 1);

      await time.advance(ms(5));
      expect(queryClient.isMutating(), 0);
    });
  });

  group('getQueryData', () {
    test('should return the query data if the query is found', () {
      final key = queryKey();
      queryClient.setQueryData<String>(
        QueryKey([...key.parts, 'id']),
        (_) => 'bar',
      );
      expect(
        queryClient.getQueryData<String>(QueryKey([...key.parts, 'id'])),
        'bar',
      );
    });

    test('should return null if the query is not found', () {
      expect(queryClient.getQueryData<String>(queryKey()), isNull);
    });

    test('should match exact by default', () {
      final key = queryKey();
      queryClient.setQueryData<String>(
        QueryKey([...key.parts, 'id']),
        (_) => 'bar',
      );
      expect(queryClient.getQueryData<String>(key), isNull);
    });
  });

  group('query with static staleTime', () {
    testFakeAsync('should return the cached query data if the query is found', (
      time,
    ) async {
      final key = queryKey();
      var calls = 0;

      queryClient.setQueryData<String>(
        QueryKey([...key.parts, 'id']),
        (_) => 'bar',
      );

      final result = await queryClient.query(
        str(
          QueryKey([...key.parts, 'id']),
          queryFn: (_) async {
            calls++;
            return 'data';
          },
          staleTime: StaleDuration.static_,
        ),
      );

      expect(result, 'bar');
      expect(calls, 0);
    });

    testFakeAsync(
      'should return the cached query data if the query is found and the '
      'cached data is falsy',
      (time) async {
        final key = queryKey();
        var calls = 0;

        // Upstream caches `null` here; the port's cache holds non-null values
        // by invariant, so zero stands in as the falsy value.
        queryClient.setQueryData<int>(QueryKey([...key.parts, 'id']), (_) => 0);

        final result = await queryClient.query(
          QueryObserverOptions<int, int>(
            queryKey: QueryKey([...key.parts, 'id']),
            queryFn: (_) async {
              calls++;
              return 5;
            },
            staleTime: StaleDuration.static_,
          ),
        );

        expect(result, 0);
        expect(calls, 0);
      },
    );

    testFakeAsync(
      'should call queryFn and return its results if the query is not found',
      (time) async {
        final key = queryKey();
        var calls = 0;

        final result = await queryClient.query(
          str(
            key,
            queryFn: (_) async {
              calls++;
              return 'data';
            },
            staleTime: StaleDuration.static_,
          ),
        );

        expect(result, 'data');
        expect(calls, 1);
      },
    );

    testFakeAsync('should not fetch when initialData is provided', (
      time,
    ) async {
      final key = queryKey();
      var calls = 0;

      final result = await queryClient.query(
        str(
          key,
          queryFn: (_) async {
            calls++;
            return 'data';
          },
          staleTime: StaleDuration.static_,
          initialData: () => 'initial',
        ),
      );

      expect(result, 'initial');
      expect(calls, 0);
    });

    testFakeAsync('supports manual background revalidation via a second call', (
      time,
    ) async {
      final key = queryKey();
      var value = 'data-1';
      var calls = 0;

      Future<String> queryFn(QueryFunctionContext _) async {
        calls++;
        return value;
      }

      final first = await queryClient.query(
        str(key, queryFn: queryFn, staleTime: StaleDuration.static_),
      );
      expect(first, 'data-1');
      expect(calls, 1);

      value = 'data-2';
      unawaited(
        queryClient
            .query(str(key, queryFn: queryFn, staleTime: StaleDuration.zero))
            .then((_) {}, onError: (Object _, StackTrace _) {}),
      );

      await time.advance(Duration.zero);

      expect(calls, 2);
      expect(queryClient.getQueryData<String>(key), 'data-2');
    });
  });

  group('getQueriesData', () {
    test('should return the query data for all matched queries', () {
      final key1 = queryKey();
      final key2 = queryKey();
      queryClient.setQueryData<int>(QueryKey([...key1.parts, 1]), (_) => 1);
      queryClient.setQueryData<int>(QueryKey([...key1.parts, 2]), (_) => 2);
      queryClient.setQueryData<int>(QueryKey([...key2.parts, 2]), (_) => 2);

      expect(queryClient.getQueriesData<int>(QueryFilters(queryKey: key1)), [
        (QueryKey([...key1.parts, 1]), 1),
        (QueryKey([...key1.parts, 2]), 2),
      ]);
    });

    test('should return an empty list if queries are not found', () {
      expect(
        queryClient.getQueriesData<int>(QueryFilters(queryKey: queryKey())),
        isEmpty,
      );
    });

    test('should accept query filters', () {
      queryClient.setQueryData<int>(const QueryKey(['key', 1]), (_) => 1);
      queryClient.setQueryData<int>(const QueryKey(['key', 2]), (_) => 2);
      final query1 = queryCache.find(const QueryKey(['key', 1]))!;

      final result = queryClient.getQueriesData<int>(
        QueryFilters(predicate: (query) => identical(query, query1)),
      );

      expect(result, [
        (const QueryKey(['key', 1]), 1),
      ]);
    });
  });

  group('fetchQuery', () {
    testFakeAsync('should not retry by default', (time) async {
      final key = queryKey();
      await expectLater(
        queryClient.fetchQuery(
          str(key, queryFn: (_) => Future<String>.error(StateError('error'))),
        ),
        throwsA(isA<StateError>()),
      );
    });

    testFakeAsync('should return the cached data on cache hit', (time) async {
      final key = queryKey();
      Future<String> queryFn(QueryFunctionContext _) async => 'data';

      final first = await queryClient.fetchQuery(str(key, queryFn: queryFn));
      final second = await queryClient.fetchQuery(str(key, queryFn: queryFn));

      expect(second, first);
    });

    testFakeAsync(
      'should read from cache with static staleTime even if invalidated',
      (time) async {
        final key = queryKey();
        var calls = 0;

        Future<Boxed> queryFn(QueryFunctionContext _) async {
          calls++;
          return const Boxed('data');
        }

        final first = await queryClient.fetchQuery(
          QueryObserverOptions<Boxed, Boxed>(
            queryKey: key,
            queryFn: queryFn,
            staleTime: StaleDuration.static_,
          ),
        );

        expect(first.value, 'data');
        expect(calls, 1);

        await queryClient.invalidateQueries(
          filters: QueryFilters(queryKey: key),
          refetchType: QueryRefetchType.none,
        );

        final second = await queryClient.fetchQuery(
          QueryObserverOptions<Boxed, Boxed>(
            queryKey: key,
            queryFn: queryFn,
            staleTime: StaleDuration.static_,
          ),
        );

        expect(calls, 1);
        expect(second, same(first));
      },
    );

    testFakeAsync(
      'should be able to fetch when garbage collection time is set to 0 and '
      'then be removed',
      (time) async {
        final key = queryKey();
        final promise = queryClient.fetchQuery(
          QueryObserverOptions<int, int>(
            queryKey: key,
            queryFn: (_) => sleep(ms(10)).then((_) => 1),
            gcTime: const GcDuration.of(Duration.zero),
          ),
        );
        await time.advance(ms(10));
        await expectLater(promise, completion(1));
        await time.advance(ms(1));
        expect(queryClient.getQueryData<int>(key), isNull);
      },
    );

    testFakeAsync('should keep a query in cache if gc time never collects', (
      time,
    ) async {
      final key = queryKey();
      final promise = queryClient.fetchQuery(
        QueryObserverOptions<int, int>(
          queryKey: key,
          queryFn: (_) => sleep(ms(10)).then((_) => 1),
          gcTime: GcDuration.never,
        ),
      );
      await time.advance(ms(10));
      final cached = queryClient.getQueryData<int>(key);
      await expectLater(promise, completion(1));
      expect(cached, 1);
    });

    testFakeAsync('should not force fetch', (time) async {
      final key = queryKey();

      queryClient.setQueryData<String>(key, (_) => 'og');
      final first = await queryClient.fetchQuery(
        str(
          key,
          queryFn: (_) async => 'new',
          initialData: () => 'initial',
          staleTime: const StaleDuration.of(Duration(milliseconds: 100)),
        ),
      );
      expect(first, 'og');
    });

    testFakeAsync(
      'should only fetch if the data is older then the given stale time',
      (time) async {
        final key = queryKey();
        var count = 0;
        Future<int> queryFn(QueryFunctionContext _) async => ++count;

        queryClient.setQueryData<int>(key, (_) => count);

        QueryObserverOptions<int, int> withStale(Duration staleTime) =>
            QueryObserverOptions<int, int>(
              queryKey: key,
              queryFn: queryFn,
              staleTime: StaleDuration.of(staleTime),
            );

        await expectLater(
          queryClient.fetchQuery(withStale(ms(100))),
          completion(0),
        );
        await time.advance(ms(10));
        await expectLater(
          queryClient.fetchQuery(withStale(ms(10))),
          completion(1),
        );
        await expectLater(
          queryClient.fetchQuery(withStale(ms(10))),
          completion(1),
        );
        await time.advance(ms(10));
        await expectLater(
          queryClient.fetchQuery(withStale(ms(10))),
          completion(2),
        );
      },
    );

    testFakeAsync('should allow new meta', (time) async {
      final key = queryKey();

      Future<Object?> readMeta(QueryFunctionContext context) async =>
          context.meta;

      final first = await queryClient.fetchQuery(
        QueryObserverOptions<Object?, Object?>(
          queryKey: key,
          queryFn: readMeta,
          meta: const {'foo': true},
        ),
      );
      expect(first, const {'foo': true});

      final second = await queryClient.fetchQuery(
        QueryObserverOptions<Object?, Object?>(
          queryKey: key,
          queryFn: readMeta,
          meta: const {'foo': false},
        ),
      );
      expect(second, const {'foo': false});
    });
  });

  group('query', () {
    testFakeAsync('should not retry by default', (time) async {
      final key = queryKey();
      await expectLater(
        queryClient.query(
          str(key, queryFn: (_) => Future<String>.error(StateError('error'))),
        ),
        throwsA(isA<StateError>()),
      );
    });

    testFakeAsync('should return the cached data on cache hit', (time) async {
      final key = queryKey();
      Future<String> queryFn(QueryFunctionContext _) async => 'data';

      final first = await queryClient.query(str(key, queryFn: queryFn));
      final second = await queryClient.query(str(key, queryFn: queryFn));

      expect(second, first);
    });

    testFakeAsync('should fetch when disabled', (time) async {
      final key = queryKey();
      var calls = 0;

      final result = await queryClient.query(
        str(
          key,
          queryFn: (_) async {
            calls++;
            return 'data';
          },
          enabled: Enabled.off,
        ),
      );

      expect(result, 'data');
      expect(calls, 1);
    });

    testFakeAsync('should fetch when disabled by callback', (time) async {
      final key = queryKey();
      var calls = 0;

      final result = await queryClient.query(
        str(
          key,
          queryFn: (_) async {
            calls++;
            return 'data';
          },
          enabled: Enabled.resolve((_) => false),
        ),
      );

      expect(result, 'data');
      expect(calls, 1);
    });

    testFakeAsync('should fetch when disabled and apply select', (time) async {
      final key = queryKey();
      var calls = 0;

      queryClient.setQueryData<String>(key, (_) => 'cached-data');

      final result = await queryClient.query(
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async {
            calls++;
            return 'fetched-data';
          },
          enabled: Enabled.off,
          staleTime: StaleDuration.zero,
          select: (data) => '$data-selected',
        ),
      );

      expect(result, 'fetched-data-selected');
      expect(calls, 1);
    });

    testFakeAsync(
      'should fetch instead of returning initialData when disabled',
      (time) async {
        var calls = 0;

        final result = await queryClient.query(
          str(
            queryKey(),
            queryFn: (_) async {
              calls++;
              return 'fetched-data';
            },
            enabled: Enabled.off,
            initialData: () => 'initial-data',
          ),
        );

        expect(result, 'fetched-data');
        expect(calls, 1);
      },
    );

    testFakeAsync('should fetch when enabled callback returns false', (
      time,
    ) async {
      final key = queryKey();
      var calls = 0;

      queryClient.setQueryData<String>(key, (_) => 'cached-data');

      final result = await queryClient.query(
        str(
          key,
          queryFn: (_) async {
            calls++;
            return 'fetched-data';
          },
          enabled: Enabled.resolve((_) => false),
        ),
      );

      expect(result, 'fetched-data');
      expect(calls, 1);
    });

    testFakeAsync(
      'should fetch when enabled callback returns true and cache is stale',
      (time) async {
        final key = queryKey();
        queryClient.setQueryData<String>(key, (_) => 'old-data');

        await time.advance(ms(1));

        var calls = 0;
        final result = await queryClient.query(
          str(
            key,
            queryFn: (_) async {
              calls++;
              return 'new-data';
            },
            enabled: Enabled.resolve((_) => true),
            staleTime: StaleDuration.zero,
          ),
        );

        expect(result, 'new-data');
        expect(calls, 1);
      },
    );

    testFakeAsync(
      'should read from cache with static staleTime even if invalidated',
      (time) async {
        final key = queryKey();
        var calls = 0;

        Future<Boxed> queryFn(QueryFunctionContext _) async {
          calls++;
          return const Boxed('data');
        }

        final first = await queryClient.query(
          QueryObserverOptions<Boxed, Boxed>(
            queryKey: key,
            queryFn: queryFn,
            staleTime: StaleDuration.static_,
          ),
        );

        expect(first.value, 'data');
        expect(calls, 1);

        await queryClient.invalidateQueries(
          filters: QueryFilters(queryKey: key),
          refetchType: QueryRefetchType.none,
        );

        final second = await queryClient.query(
          QueryObserverOptions<Boxed, Boxed>(
            queryKey: key,
            queryFn: queryFn,
            staleTime: StaleDuration.static_,
          ),
        );

        expect(calls, 1);
        expect(second, same(first));
      },
    );

    testFakeAsync(
      'should be able to fetch when garbage collection time is set to 0 and '
      'then be removed',
      (time) async {
        final key = queryKey();
        final promise = queryClient.query(
          QueryObserverOptions<int, int>(
            queryKey: key,
            queryFn: (_) => sleep(ms(10)).then((_) => 1),
            gcTime: const GcDuration.of(Duration.zero),
          ),
        );
        await time.advance(ms(10));
        await expectLater(promise, completion(1));
        await time.advance(ms(1));
        expect(queryClient.getQueryData<int>(key), isNull);
      },
    );

    testFakeAsync('should keep a query in cache if gc time never collects', (
      time,
    ) async {
      final key = queryKey();
      final promise = queryClient.query(
        QueryObserverOptions<int, int>(
          queryKey: key,
          queryFn: (_) => sleep(ms(10)).then((_) => 1),
          gcTime: GcDuration.never,
        ),
      );
      await time.advance(ms(10));
      final cached = queryClient.getQueryData<int>(key);
      await expectLater(promise, completion(1));
      expect(cached, 1);
    });

    testFakeAsync('should not force fetch', (time) async {
      final key = queryKey();

      queryClient.setQueryData<String>(key, (_) => 'og');
      final first = await queryClient.query(
        str(
          key,
          queryFn: (_) async => 'new',
          initialData: () => 'initial',
          staleTime: const StaleDuration.of(Duration(milliseconds: 100)),
        ),
      );
      expect(first, 'og');
    });

    testFakeAsync(
      'should only fetch if the data is older then the given stale time',
      (time) async {
        final key = queryKey();
        var count = 0;
        Future<int> queryFn(QueryFunctionContext _) async => ++count;

        queryClient.setQueryData<int>(key, (_) => count);

        QueryObserverOptions<int, int> withStale(Duration staleTime) =>
            QueryObserverOptions<int, int>(
              queryKey: key,
              queryFn: queryFn,
              staleTime: StaleDuration.of(staleTime),
            );

        await expectLater(queryClient.query(withStale(ms(100))), completion(0));
        await time.advance(ms(10));
        await expectLater(queryClient.query(withStale(ms(10))), completion(1));
        await expectLater(queryClient.query(withStale(ms(10))), completion(1));
        await time.advance(ms(10));
        await expectLater(queryClient.query(withStale(ms(10))), completion(2));
      },
    );

    testFakeAsync('should evaluate staleTime when provided as a function', (
      time,
    ) async {
      final key = queryKey();
      var staleTimeCalls = 0;

      queryClient.setQueryData<String>(key, (_) => 'old-data');

      await time.advance(ms(1));

      var calls = 0;
      final result = await queryClient.query(
        str(
          key,
          queryFn: (_) async {
            calls++;
            return 'new-data';
          },
          staleTime: StaleDuration.resolve((_) {
            staleTimeCalls++;
            return StaleDuration.zero;
          }),
        ),
      );

      expect(result, 'new-data');
      expect(calls, 1);
      expect(staleTimeCalls, 1);
    });

    testFakeAsync('should allow new meta', (time) async {
      final key = queryKey();

      Future<Object?> readMeta(QueryFunctionContext context) async =>
          context.meta;

      final first = await queryClient.query(
        QueryObserverOptions<Object?, Object?>(
          queryKey: key,
          queryFn: readMeta,
          meta: const {'foo': true},
        ),
      );
      expect(first, const {'foo': true});

      final second = await queryClient.query(
        QueryObserverOptions<Object?, Object?>(
          queryKey: key,
          queryFn: readMeta,
          meta: const {'foo': false},
        ),
      );
      expect(second, const {'foo': false});
    });

    testFakeAsync('should fetch when enabled is true and cache is stale', (
      time,
    ) async {
      final key = queryKey();
      queryClient.setQueryData<String>(key, (_) => 'old-data');

      await time.advance(ms(1));

      var calls = 0;
      final result = await queryClient.query(
        str(
          key,
          queryFn: (_) async {
            calls++;
            return 'new-data';
          },
          enabled: Enabled.on,
          staleTime: StaleDuration.zero,
        ),
      );

      expect(result, 'new-data');
      expect(calls, 1);
    });

    testFakeAsync('should propagate errors', (time) async {
      final key = queryKey();
      await expectLater(
        queryClient.query(
          str(key, queryFn: (_) => Future<String>.error(StateError('error'))),
        ),
        throwsA(isA<StateError>()),
      );
    });

    testFakeAsync('should apply select when data is fresh in cache', (
      time,
    ) async {
      final key = queryKey();
      var calls = 0;

      queryClient.setQueryData<String>(key, (_) => 'cached-data');

      final result = await queryClient.query(
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async {
            calls++;
            return 'fetched-data';
          },
          staleTime: StaleDuration.infinity,
          select: (data) => '$data-selected',
        ),
      );

      expect(result, 'cached-data-selected');
      expect(calls, 0);
    });

    testFakeAsync('should apply select to freshly fetched data', (time) async {
      final key = queryKey();
      var calls = 0;

      final result = await queryClient.query(
        QueryObserverOptions<Boxed, String>(
          queryKey: key,
          queryFn: (_) async {
            calls++;
            return const Boxed('fetched-data');
          },
          select: (data) => data.value.toUpperCase(),
        ),
      );

      expect(result, 'FETCHED-DATA');
      expect(calls, 1);
    });
  });

  group('prefetchQuery', () {
    testFakeAsync('should swallow a thrown error', (time) async {
      final key = queryKey();

      await expectLater(
        queryClient.prefetchQuery(
          str(
            key,
            queryFn: (_) => Future<String>.error(StateError('error')),
            retry: RetryOption.never,
          ),
        ),
        completes,
      );
    });

    testFakeAsync('should be garbage collected after gcTime if unused', (
      time,
    ) async {
      final key = queryKey();

      await queryClient.prefetchQuery(
        str(
          key,
          queryFn: (_) async => 'data',
          gcTime: const GcDuration.of(Duration(milliseconds: 10)),
        ),
      );
      expect(queryCache.find(key)!.state.data, 'data');
      await time.advance(ms(15));
      expect(queryCache.find(key), isNull);
    });
  });

  group('query used for prefetching', () {
    testFakeAsync('should resolve to null when the error is swallowed', (
      time,
    ) async {
      final key = queryKey();

      final result = await queryClient
          .query(
            str(
              key,
              queryFn: (_) => Future<String>.error(StateError('error')),
              retry: RetryOption.never,
            ),
          )
          .then<String?>((value) => value, onError: (Object _) => null);

      expect(result, isNull);
    });

    testFakeAsync('should be garbage collected after gcTime if unused', (
      time,
    ) async {
      final key = queryKey();

      await queryClient
          .query(
            str(
              key,
              queryFn: (_) async => 'data',
              gcTime: const GcDuration.of(Duration(milliseconds: 10)),
            ),
          )
          .then<String?>((value) => value, onError: (Object _) => null);

      expect(queryCache.find(key), isNotNull);
      await time.advance(ms(15));
      expect(queryCache.find(key), isNull);
    });
  });

  group('removeQueries', () {
    testFakeAsync('should not crash when exact is provided', (time) async {
      final key = queryKey();

      await queryClient.prefetchQuery(str(key, queryFn: (_) async => 'data'));
      expect(queryCache.find(key)!.state.data, 'data');

      expect(
        () => queryClient.removeQueries(
          filters: QueryFilters(queryKey: key, exact: true),
        ),
        returnsNormally,
      );

      expect(queryCache.find(key), isNull);
    });
  });

  group('cancelQueries', () {
    testFakeAsync('should revert queries to their previous state', (
      time,
    ) async {
      final key1 = queryKey();
      queryClient.setQueryData<String>(key1, (_) => 'data');

      final pending = queryClient.fetchQuery(
        str(key1, queryFn: (_) => sleep(ms(1000)).then((_) => 'data2')),
      );

      await time.advance(ms(10));

      await queryClient.cancelQueries();

      // With previous data present, an imperative fetch resolves to that data
      // once cancelled.
      await expectLater(pending, completion('data'));

      final state = queryClient.getQueryState<String>(key1)!;
      expect(state.data, 'data');
      expect(state.status, QueryStatus.success);
    });

    testFakeAsync('should not revert if revert option is set to false', (
      time,
    ) async {
      final key1 = queryKey();
      await queryClient.fetchQuery(str(key1, queryFn: (_) async => 'data'));

      unawaited(
        queryClient.prefetchQuery(
          str(key1, queryFn: (_) => sleep(ms(1000)).then((_) => 'data2')),
        ),
      );
      await time.advance(ms(10));

      await queryClient.cancelQueries(
        filters: QueryFilters(queryKey: key1),
        revert: false,
      );

      expect(
        queryClient.getQueryState<String>(key1)!.status,
        QueryStatus.error,
      );
    });

    testFakeAsync(
      'should throw CancelledError for imperative methods when the initial '
      'fetch is cancelled',
      (time) async {
        final key = queryKey();

        final promise = queryClient.fetchQuery(
          QueryObserverOptions<int, int>(
            queryKey: key,
            queryFn: (_) => sleep(ms(50)).then((_) => 25),
          ),
        );
        final rejects = expectLater(promise, throwsA(isA<CancelledError>()));

        await time.advance(ms(10));

        await queryClient.cancelQueries(filters: QueryFilters(queryKey: key));

        // There is no data to resolve with, so it has to reject; the
        // alternative would be a future that never settles.
        await rejects;

        final state = queryClient.getQueryState<int>(key)!;
        expect(state.status, QueryStatus.pending);
        expect(state.fetchStatus, FetchStatus.idle);
        expect(state.data, isNull);
        expect(state.error, isNull);
      },
    );
  });

  group('refetchQueries', () {
    testFakeAsync('should not refetch if all observers are disabled', (
      time,
    ) async {
      final key = queryKey();
      var calls = 0;
      Future<String> queryFn(QueryFunctionContext _) async {
        calls++;
        return 'data';
      }

      await queryClient.fetchQuery(str(key, queryFn: queryFn));
      final observer1 = QueryObserver<String, String>(
        queryClient,
        str(key, queryFn: queryFn, enabled: Enabled.off),
      );
      observer1.subscribe((_) {});
      await queryClient.refetchQueries();
      observer1.destroy();
      expect(calls, 1);
    });

    testFakeAsync('should refetch if at least one observer is enabled', (
      time,
    ) async {
      final key = queryKey();
      var calls = 0;
      Future<String> queryFn(QueryFunctionContext _) async {
        calls++;
        return 'data';
      }

      await queryClient.fetchQuery(str(key, queryFn: queryFn));
      final observer1 = QueryObserver<String, String>(
        queryClient,
        str(key, queryFn: queryFn, enabled: Enabled.off),
      );
      final observer2 = QueryObserver<String, String>(
        queryClient,
        str(key, queryFn: queryFn, refetchOnMount: RefetchOn.never),
      );
      observer1.subscribe((_) {});
      observer2.subscribe((_) {});
      await queryClient.refetchQueries();
      observer1.destroy();
      observer2.destroy();
      expect(calls, 2);
    });

    testFakeAsync('should refetch all queries when no arguments are given', (
      time,
    ) async {
      final key1 = queryKey();
      final key2 = queryKey();
      var calls1 = 0;
      var calls2 = 0;
      Future<String> queryFn1(QueryFunctionContext _) async {
        calls1++;
        return 'data1';
      }

      Future<String> queryFn2(QueryFunctionContext _) async {
        calls2++;
        return 'data2';
      }

      await queryClient.fetchQuery(str(key1, queryFn: queryFn1));
      await queryClient.fetchQuery(str(key2, queryFn: queryFn2));

      final observer1 = QueryObserver<String, String>(
        queryClient,
        str(
          key1,
          queryFn: queryFn1,
          staleTime: StaleDuration.infinity,
          initialData: () => 'initial',
        ),
      );
      final observer2 = QueryObserver<String, String>(
        queryClient,
        str(
          key1,
          queryFn: queryFn1,
          staleTime: StaleDuration.infinity,
          initialData: () => 'initial',
        ),
      );
      observer1.subscribe((_) {});
      observer2.subscribe((_) {});
      await queryClient.refetchQueries();
      observer1.destroy();
      observer2.destroy();

      expect(calls1, 2);
      expect(calls2, 2);
    });

    testFakeAsync('should be able to refetch all fresh queries', (time) async {
      final key1 = queryKey();
      final key2 = queryKey();
      var calls1 = 0;
      var calls2 = 0;
      Future<String> queryFn1(QueryFunctionContext _) async {
        calls1++;
        return 'data1';
      }

      Future<String> queryFn2(QueryFunctionContext _) async {
        calls2++;
        return 'data2';
      }

      await queryClient.fetchQuery(str(key1, queryFn: queryFn1));
      await queryClient.fetchQuery(str(key2, queryFn: queryFn2));

      final observer = QueryObserver<String, String>(
        queryClient,
        str(key1, queryFn: queryFn1, staleTime: StaleDuration.infinity),
      );
      final unsubscribe = observer.subscribe((_) {});
      await queryClient.refetchQueries(
        filters: const QueryFilters(type: QueryTypeFilter.active, stale: false),
      );
      unsubscribe();

      expect(calls1, 2);
      expect(calls2, 1);
    });

    testFakeAsync('should be able to refetch all stale queries', (time) async {
      final key1 = queryKey();
      final key2 = queryKey();
      var calls1 = 0;
      var calls2 = 0;
      Future<String> queryFn1(QueryFunctionContext _) async {
        calls1++;
        return 'data1';
      }

      Future<String> queryFn2(QueryFunctionContext _) async {
        calls2++;
        return 'data2';
      }

      await queryClient.fetchQuery(str(key1, queryFn: queryFn1));
      await queryClient.fetchQuery(str(key2, queryFn: queryFn2));

      final observer = QueryObserver<String, String>(
        queryClient,
        str(key1, queryFn: queryFn1),
      );
      final unsubscribe = observer.subscribe((_) {});
      unawaited(
        queryClient.invalidateQueries(filters: QueryFilters(queryKey: key1)),
      );
      await queryClient.refetchQueries(
        filters: const QueryFilters(stale: true),
      );
      unsubscribe();

      // fetchQuery, observer mount, invalidation (cancels the mount fetch) and
      // this refetch.
      expect(calls1, 4);
      expect(calls2, 1);
    });

    testFakeAsync('should be able to refetch all stale and active queries', (
      time,
    ) async {
      final key1 = queryKey();
      final key2 = queryKey();
      var calls1 = 0;
      var calls2 = 0;
      Future<String> queryFn1(QueryFunctionContext _) async {
        calls1++;
        return 'data1';
      }

      Future<String> queryFn2(QueryFunctionContext _) async {
        calls2++;
        return 'data2';
      }

      await queryClient.fetchQuery(str(key1, queryFn: queryFn1));
      await queryClient.fetchQuery(str(key2, queryFn: queryFn2));
      unawaited(
        queryClient.invalidateQueries(filters: QueryFilters(queryKey: key1)),
      );

      final observer = QueryObserver<String, String>(
        queryClient,
        str(key1, queryFn: queryFn1),
      );
      final unsubscribe = observer.subscribe((_) {});
      await queryClient.refetchQueries(
        filters: const QueryFilters(type: QueryTypeFilter.active, stale: true),
        cancelRefetch: false,
      );
      unsubscribe();

      expect(calls1, 2);
      expect(calls2, 1);
    });

    testFakeAsync('should be able to refetch all active and inactive queries '
        '(refetchQueries())', (time) async {
      final key1 = queryKey();
      final key2 = queryKey();
      var calls1 = 0;
      var calls2 = 0;
      Future<String> queryFn1(QueryFunctionContext _) async {
        calls1++;
        return 'data1';
      }

      Future<String> queryFn2(QueryFunctionContext _) async {
        calls2++;
        return 'data2';
      }

      await queryClient.fetchQuery(str(key1, queryFn: queryFn1));
      await queryClient.fetchQuery(str(key2, queryFn: queryFn2));

      final observer = QueryObserver<String, String>(
        queryClient,
        str(key1, queryFn: queryFn1, staleTime: StaleDuration.infinity),
      );
      final unsubscribe = observer.subscribe((_) {});
      await queryClient.refetchQueries();
      unsubscribe();

      expect(calls1, 2);
      expect(calls2, 2);
    });

    testFakeAsync(
      'should be able to refetch all active and inactive queries (type: all)',
      (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        Future<String> queryFn1(QueryFunctionContext _) async {
          calls1++;
          return 'data1';
        }

        Future<String> queryFn2(QueryFunctionContext _) async {
          calls2++;
          return 'data2';
        }

        await queryClient.fetchQuery(str(key1, queryFn: queryFn1));
        await queryClient.fetchQuery(str(key2, queryFn: queryFn2));

        final observer = QueryObserver<String, String>(
          queryClient,
          str(key1, queryFn: queryFn1, staleTime: StaleDuration.infinity),
        );
        final unsubscribe = observer.subscribe((_) {});
        await queryClient.refetchQueries(
          filters: const QueryFilters(type: QueryTypeFilter.all),
        );
        unsubscribe();

        expect(calls1, 2);
        expect(calls2, 2);
      },
    );

    testFakeAsync('should be able to refetch only active queries', (
      time,
    ) async {
      final key1 = queryKey();
      final key2 = queryKey();
      var calls1 = 0;
      var calls2 = 0;
      Future<String> queryFn1(QueryFunctionContext _) async {
        calls1++;
        return 'data1';
      }

      Future<String> queryFn2(QueryFunctionContext _) async {
        calls2++;
        return 'data2';
      }

      await queryClient.fetchQuery(str(key1, queryFn: queryFn1));
      await queryClient.fetchQuery(str(key2, queryFn: queryFn2));

      final observer = QueryObserver<String, String>(
        queryClient,
        str(key1, queryFn: queryFn1, staleTime: StaleDuration.infinity),
      );
      final unsubscribe = observer.subscribe((_) {});
      await queryClient.refetchQueries(
        filters: const QueryFilters(type: QueryTypeFilter.active),
      );
      unsubscribe();

      expect(calls1, 2);
      expect(calls2, 1);
    });

    testFakeAsync('should be able to refetch only inactive queries', (
      time,
    ) async {
      final key1 = queryKey();
      final key2 = queryKey();
      var calls1 = 0;
      var calls2 = 0;
      Future<String> queryFn1(QueryFunctionContext _) async {
        calls1++;
        return 'data1';
      }

      Future<String> queryFn2(QueryFunctionContext _) async {
        calls2++;
        return 'data2';
      }

      await queryClient.fetchQuery(str(key1, queryFn: queryFn1));
      await queryClient.fetchQuery(str(key2, queryFn: queryFn2));

      final observer = QueryObserver<String, String>(
        queryClient,
        str(key1, queryFn: queryFn1, staleTime: StaleDuration.infinity),
      );
      final unsubscribe = observer.subscribe((_) {});
      await queryClient.refetchQueries(
        filters: const QueryFilters(type: QueryTypeFilter.inactive),
      );
      unsubscribe();

      expect(calls1, 1);
      expect(calls2, 2);
    });

    testFakeAsync(
      'should throw an error if throwOnError option is set to true',
      (time) async {
        final key1 = queryKey();
        final error = StateError('error');

        try {
          await queryClient.fetchQuery(
            str(
              key1,
              queryFn: (_) => Future<String>.error(error),
              retry: RetryOption.never,
            ),
          );
        } on StateError {
          // Expected.
        }

        await expectLater(
          queryClient.refetchQueries(
            filters: QueryFilters(queryKey: key1),
            throwOnError: true,
          ),
          throwsA(same(error)),
        );
      },
    );

    testFakeAsync('should resolve immediately if the query is paused', (
      time,
    ) async {
      final key1 = queryKey();
      var calls = 0;

      await queryClient.fetchQuery(
        str(
          key1,
          queryFn: (_) async {
            calls++;
            return 'data1';
          },
        ),
      );

      onlineManager.setOnline(false);

      // Reaching this point at all is the assertion: the future settles rather
      // than waiting for connectivity that never comes.
      await queryClient.refetchQueries(filters: QueryFilters(queryKey: key1));

      expect(calls, 1);
    });

    testFakeAsync(
      'should refetch while offline if the query networkMode is always',
      (time) async {
        final key1 = queryKey();
        queryClient.setQueryDefaults(
          key1,
          const QueryDefaults(networkMode: NetworkMode.always),
        );
        var calls = 0;

        await queryClient.fetchQuery(
          str(
            key1,
            queryFn: (_) async {
              calls++;
              return 'data1';
            },
          ),
        );

        onlineManager.setOnline(false);

        await queryClient.refetchQueries(filters: QueryFilters(queryKey: key1));

        expect(calls, 2, reason: 'initial fetch plus a refetch while offline');
      },
    );

    testFakeAsync('should not refetch static queries', (time) async {
      final key = queryKey();
      var calls = 0;
      Future<String> queryFn(QueryFunctionContext _) async {
        calls++;
        return 'data1';
      }

      await queryClient.fetchQuery(str(key, queryFn: queryFn));
      expect(calls, 1);

      final observer = QueryObserver<String, String>(
        queryClient,
        str(key, queryFn: queryFn, staleTime: StaleDuration.static_),
      );
      final unsubscribe = observer.subscribe((_) {});
      await queryClient.refetchQueries();

      expect(calls, 1);
      unsubscribe();
    });
  });

  group('invalidateQueries', () {
    testFakeAsync('should refetch active queries by default', (time) async {
      final key1 = queryKey();
      final key2 = queryKey();
      var calls1 = 0;
      var calls2 = 0;
      Future<String> queryFn1(QueryFunctionContext _) async {
        calls1++;
        return 'data1';
      }

      Future<String> queryFn2(QueryFunctionContext _) async {
        calls2++;
        return 'data2';
      }

      await queryClient.fetchQuery(str(key1, queryFn: queryFn1));
      await queryClient.fetchQuery(str(key2, queryFn: queryFn2));

      final observer = QueryObserver<String, String>(
        queryClient,
        str(key1, queryFn: queryFn1, staleTime: StaleDuration.infinity),
      );
      final unsubscribe = observer.subscribe((_) {});
      unawaited(
        queryClient.invalidateQueries(filters: QueryFilters(queryKey: key1)),
      );
      unsubscribe();

      expect(calls1, 2);
      expect(calls2, 1);
    });

    testFakeAsync('should not refetch inactive queries by default', (
      time,
    ) async {
      final key1 = queryKey();
      final key2 = queryKey();
      var calls1 = 0;
      var calls2 = 0;
      Future<String> queryFn1(QueryFunctionContext _) async {
        calls1++;
        return 'data1';
      }

      Future<String> queryFn2(QueryFunctionContext _) async {
        calls2++;
        return 'data2';
      }

      await queryClient.fetchQuery(str(key1, queryFn: queryFn1));
      await queryClient.fetchQuery(str(key2, queryFn: queryFn2));

      final observer = QueryObserver<String, String>(
        queryClient,
        str(key1, enabled: Enabled.off, staleTime: StaleDuration.infinity),
      );
      final unsubscribe = observer.subscribe((_) {});
      unawaited(
        queryClient.invalidateQueries(filters: QueryFilters(queryKey: key1)),
      );
      unsubscribe();

      expect(calls1, 1);
      expect(calls2, 1);
    });

    testFakeAsync(
      'should not refetch active queries when refetchType is none',
      (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        Future<String> queryFn1(QueryFunctionContext _) async {
          calls1++;
          return 'data1';
        }

        Future<String> queryFn2(QueryFunctionContext _) async {
          calls2++;
          return 'data2';
        }

        await queryClient.fetchQuery(str(key1, queryFn: queryFn1));
        await queryClient.fetchQuery(str(key2, queryFn: queryFn2));

        final observer = QueryObserver<String, String>(
          queryClient,
          str(key1, queryFn: queryFn1, staleTime: StaleDuration.infinity),
        );
        final unsubscribe = observer.subscribe((_) {});
        unawaited(
          queryClient.invalidateQueries(
            filters: QueryFilters(queryKey: key1),
            refetchType: QueryRefetchType.none,
          ),
        );
        unsubscribe();

        expect(calls1, 1);
        expect(calls2, 1);
      },
    );

    testFakeAsync(
      'should refetch inactive queries when refetchType is inactive',
      (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        Future<String> queryFn1(QueryFunctionContext _) async {
          calls1++;
          return 'data1';
        }

        Future<String> queryFn2(QueryFunctionContext _) async {
          calls2++;
          return 'data2';
        }

        await queryClient.fetchQuery(str(key1, queryFn: queryFn1));
        await queryClient.fetchQuery(str(key2, queryFn: queryFn2));

        final observer = QueryObserver<String, String>(
          queryClient,
          str(
            key1,
            queryFn: queryFn1,
            staleTime: StaleDuration.infinity,
            refetchOnMount: RefetchOn.never,
          ),
        );
        observer.subscribe((_) {})();

        await queryClient.invalidateQueries(
          filters: QueryFilters(queryKey: key1),
          refetchType: QueryRefetchType.inactive,
        );

        expect(calls1, 2);
        expect(calls2, 1);
      },
    );

    testFakeAsync(
      'should refetch active and inactive queries when refetchType is all',
      (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        Future<String> queryFn1(QueryFunctionContext _) async {
          calls1++;
          return 'data1';
        }

        Future<String> queryFn2(QueryFunctionContext _) async {
          calls2++;
          return 'data2';
        }

        await queryClient.fetchQuery(str(key1, queryFn: queryFn1));
        await queryClient.fetchQuery(str(key2, queryFn: queryFn2));

        final observer = QueryObserver<String, String>(
          queryClient,
          str(key1, queryFn: queryFn1, staleTime: StaleDuration.infinity),
        );
        final unsubscribe = observer.subscribe((_) {});
        unawaited(
          queryClient.invalidateQueries(refetchType: QueryRefetchType.all),
        );
        unsubscribe();

        expect(calls1, 2);
        expect(calls2, 2);
      },
    );

    testFakeAsync(
      'should not refetch disabled inactive queries even if refetchType is all',
      (time) async {
        var calls = 0;
        final observer = QueryObserver<String, String>(
          queryClient,
          str(
            queryKey(),
            queryFn: (_) async {
              calls++;
              return 'data1';
            },
            staleTime: StaleDuration.infinity,
            enabled: Enabled.off,
          ),
        );
        observer.subscribe((_) {})();

        await queryClient.invalidateQueries(refetchType: QueryRefetchType.all);

        expect(calls, 0);
      },
    );

    testFakeAsync(
      'should cancel ongoing fetches if cancelRefetch is set (default value)',
      (time) async {
        final key = queryKey();
        var aborts = 0;
        var fetchCount = 0;

        final observer = QueryObserver<int, int>(
          queryClient,
          QueryObserverOptions<int, int>(
            queryKey: key,
            queryFn: (context) {
              fetchCount++;
              final token = context.cancelToken;
              final completer = Completer<int>();
              Timer(ms(10), () {
                if (!completer.isCompleted) {
                  completer.complete(5);
                }
              });
              token.addListener((_) => aborts++);
              return completer.future;
            },
            initialData: () => 1,
          ),
        );
        observer.subscribe((_) {});

        unawaited(queryClient.refetchQueries());
        await time.advance(ms(10));
        observer.destroy();

        expect(aborts, 1);
        expect(fetchCount, 2);
      },
    );

    testFakeAsync(
      'should not cancel ongoing fetches if cancelRefetch is set to false',
      (time) async {
        final key = queryKey();
        var aborts = 0;
        var fetchCount = 0;

        final observer = QueryObserver<int, int>(
          queryClient,
          QueryObserverOptions<int, int>(
            queryKey: key,
            queryFn: (context) {
              fetchCount++;
              final token = context.cancelToken;
              final completer = Completer<int>();
              Timer(ms(10), () {
                if (!completer.isCompleted) {
                  completer.complete(5);
                }
              });
              token.addListener((_) => aborts++);
              return completer.future;
            },
            initialData: () => 1,
          ),
        );
        observer.subscribe((_) {});

        unawaited(queryClient.refetchQueries(cancelRefetch: false));
        await time.advance(ms(10));
        observer.destroy();

        expect(aborts, 0);
        expect(fetchCount, 1);
      },
    );

    testFakeAsync('should not refetch static queries after invalidation', (
      time,
    ) async {
      final key = queryKey();
      var calls = 0;
      Future<String> queryFn(QueryFunctionContext _) async {
        calls++;
        return 'data1';
      }

      await queryClient.fetchQuery(str(key, queryFn: queryFn));
      expect(calls, 1);

      final observer = QueryObserver<String, String>(
        queryClient,
        str(key, queryFn: queryFn, staleTime: StaleDuration.static_),
      );
      final unsubscribe = observer.subscribe((_) {});
      await queryClient.invalidateQueries();

      expect(calls, 1);
      unsubscribe();
    });
  });

  group('resetQueries', () {
    testFakeAsync('should notify listeners when a query is reset', (
      time,
    ) async {
      final key = queryKey();
      final events = <QueryCacheEvent>[];

      await queryClient.prefetchQuery(str(key, queryFn: (_) async => 'data'));

      queryCache.subscribe(events.add);

      unawaited(queryClient.resetQueries(filters: QueryFilters(queryKey: key)));

      final query = queryCache.find(key);
      expect(events.first, isA<QueryUpdated>());
      expect(events.first.query, same(query));
      expect(
        (events.first as QueryUpdated).action,
        isA<QuerySetStateAction<Object?>>(),
      );
    });

    testFakeAsync('should reset query', (time) async {
      final key = queryKey();

      await queryClient.prefetchQuery(str(key, queryFn: (_) async => 'data'));

      var state = queryClient.getQueryState<String>(key)!;
      expect(state.data, 'data');
      expect(state.status, QueryStatus.success);

      unawaited(queryClient.resetQueries(filters: QueryFilters(queryKey: key)));

      state = queryClient.getQueryState<String>(key)!;
      expect(state.data, isNull);
      expect(state.status, QueryStatus.pending);
      expect(state.fetchStatus, FetchStatus.idle);
    });

    testFakeAsync('should reset query data to initial data if set', (
      time,
    ) async {
      final key = queryKey();

      await queryClient.prefetchQuery(
        str(key, queryFn: (_) async => 'data', initialData: () => 'initial'),
      );

      expect(queryClient.getQueryState<String>(key)!.data, 'data');

      unawaited(queryClient.resetQueries(filters: QueryFilters(queryKey: key)));

      expect(queryClient.getQueryState<String>(key)!.data, 'initial');
    });

    testFakeAsync(
      'should refetch queries matched by a state-dependent predicate',
      (time) async {
        final key = queryKey();
        var calls = 0;
        Future<String> queryFn(QueryFunctionContext _) {
          calls++;
          return calls == 1
              ? Future<String>.error(StateError('error'))
              : Future<String>.value('data');
        }

        await expectLater(
          queryClient.fetchQuery(
            str(key, queryFn: queryFn, retry: RetryOption.never),
          ),
          throwsA(isA<StateError>()),
        );

        final observer = QueryObserver<String, String>(
          queryClient,
          str(
            key,
            queryFn: queryFn,
            retry: RetryOption.never,
            retryOnMount: Enabled.off,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});

        await queryClient.resetQueries(
          filters: QueryFilters(
            predicate: (query) => query.state.status == QueryStatus.error,
          ),
        );

        expect(calls, 2);
        expect(queryClient.getQueryData<String>(key), 'data');

        unsubscribe();
      },
    );

    testFakeAsync('should refetch all active queries', (time) async {
      final key1 = queryKey();
      final key2 = queryKey();
      var calls1 = 0;
      var calls2 = 0;

      final observer1 = QueryObserver<String, String>(
        queryClient,
        str(
          key1,
          queryFn: (_) async {
            calls1++;
            return 'data1';
          },
          enabled: Enabled.on,
        ),
      );
      final observer2 = QueryObserver<String, String>(
        queryClient,
        str(
          key2,
          queryFn: (_) async {
            calls2++;
            return 'data2';
          },
          enabled: Enabled.off,
        ),
      );
      observer1.subscribe((_) {});
      observer2.subscribe((_) {});

      await queryClient.resetQueries();

      observer2.destroy();
      observer1.destroy();

      expect(calls1, 2);
      expect(calls2, 0);
    });
  });

  group('focusManager and onlineManager', () {
    testFakeAsync('should notify the query cache when focused', (time) async {
      final cache = _SpyCache();
      final testClient = QueryClient(queryCache: cache)..mount();

      focusManager.setFocused(false);
      expect(cache.focusCalls, 0);

      focusManager.setFocused(true);
      await time.advance(Duration.zero);
      expect(cache.focusCalls, 1);
      expect(cache.onlineCalls, 0);

      testClient.unmount();
    });

    testFakeAsync('should notify the query cache when online', (time) async {
      final cache = _SpyCache();
      final testClient = QueryClient(queryCache: cache)..mount();

      onlineManager.setOnline(false);
      expect(cache.onlineCalls, 0);

      onlineManager.setOnline(true);
      await time.advance(Duration.zero);
      expect(cache.onlineCalls, 1);
      expect(cache.focusCalls, 0);

      testClient.unmount();
    });

    testFakeAsync(
      'should notify the query cache after multiple mounts and a single '
      'unmount',
      (time) async {
        final cache = _SpyCache();
        final testClient = QueryClient(queryCache: cache)
          ..mount()
          ..mount()
          ..unmount();

        onlineManager.setOnline(false);
        onlineManager.setOnline(true);
        await time.advance(Duration.zero);
        expect(cache.onlineCalls, 1);

        focusManager.setFocused(true);
        await time.advance(Duration.zero);
        expect(cache.focusCalls, 1);

        testClient.unmount();
      },
    );

    testFakeAsync(
      'should not notify the query cache after multiple mounts and unmounts',
      (time) async {
        final cache = _SpyCache();
        QueryClient(queryCache: cache)
          ..mount()
          ..mount()
          ..unmount()
          ..unmount();

        onlineManager.setOnline(false);
        onlineManager.setOnline(true);
        await time.advance(Duration.zero);
        expect(cache.onlineCalls, 0);

        focusManager.setFocused(true);
        await time.advance(Duration.zero);
        expect(cache.focusCalls, 0);
      },
    );

    testFakeAsync('should resume paused mutations when the app comes back on', (
      time,
    ) async {
      final mutations = _SpyMutationCache();
      final testClient = QueryClient(mutationCache: mutations)..mount();

      focusManager.setFocused(false);
      expect(mutations.resumeCalls, 0);

      focusManager.setFocused(true);
      await time.advance(Duration.zero);
      expect(mutations.resumeCalls, 1);

      testClient.unmount();
    });

    testFakeAsync('should resume paused mutations when coming online', (
      time,
    ) async {
      onlineManager.setOnline(false);

      MutationObserver<int, Object?, Object?> build(int value) =>
          MutationObserver<int, Object?, Object?>(
            queryClient,
            MutationOptions<int, Object?, Object?>(
              mutationFn: (_, _) async => value,
            ),
          );

      final observer1 = build(1);
      final observer2 = build(2);
      observer1.mutate(null).ignore();
      observer2.mutate(null).ignore();

      expect(observer1.result.isPaused, isTrue);
      expect(observer2.result.isPaused, isTrue);

      onlineManager.setOnline(true);

      await time.advance(Duration.zero);
      expect(observer1.result.status, MutationStatus.success);
      expect(observer2.result.status, MutationStatus.success);
    });

    testFakeAsync('should resume paused mutations in parallel', (time) async {
      onlineManager.setOnline(false);
      final orders = <String>[];

      MutationObserver<int, Object?, Object?> build(
        String label,
        Duration delay,
        int value,
      ) => MutationObserver<int, Object?, Object?>(
        queryClient,
        MutationOptions<int, Object?, Object?>(
          mutationFn: (_, _) async {
            orders.add('${label}start');
            await sleep(delay);
            orders.add('${label}end');
            return value;
          },
        ),
      );

      final observer1 = build('1', ms(50), 1);
      final observer2 = build('2', ms(20), 2);
      observer1.mutate(null).ignore();
      observer2.mutate(null).ignore();

      expect(observer1.result.isPaused, isTrue);
      expect(observer2.result.isPaused, isTrue);

      onlineManager.setOnline(true);

      await time.advance(ms(50));
      expect(observer1.result.status, MutationStatus.success);
      expect(observer2.result.status, MutationStatus.success);
      expect(orders, ['1start', '2start', '2end', '1end']);
    });

    testFakeAsync(
      'should resume paused mutations one after the other when in the same '
      'scope',
      (time) async {
        onlineManager.setOnline(false);
        final orders = <String>[];

        MutationObserver<int, Object?, Object?> build(
          String label,
          Duration delay,
          int value,
        ) => MutationObserver<int, Object?, Object?>(
          queryClient,
          MutationOptions<int, Object?, Object?>(
            scope: 'scope',
            mutationFn: (_, _) async {
              orders.add('${label}start');
              await sleep(delay);
              orders.add('${label}end');
              return value;
            },
          ),
        );

        final observer1 = build('1', ms(50), 1);
        final observer2 = build('2', ms(20), 2);
        observer1.mutate(null).ignore();
        observer2.mutate(null).ignore();

        expect(observer1.result.isPaused, isTrue);
        expect(observer2.result.isPaused, isTrue);

        onlineManager.setOnline(true);
        queryClient.resumePausedMutations().ignore();

        await time.advance(ms(70));
        expect(observer1.result.status, MutationStatus.success);
        expect(observer2.result.status, MutationStatus.success);
        expect(orders, ['1start', '1end', '2start', '2end']);
      },
    );

    testFakeAsync(
      'should resume when coming online after resumePausedMutations was called '
      'while offline',
      (time) async {
        onlineManager.setOnline(false);

        final observer = MutationObserver<int, Object?, Object?>(
          queryClient,
          MutationOptions<int, Object?, Object?>(mutationFn: (_, _) async => 1),
        );

        observer.mutate(null).ignore();
        expect(observer.result.isPaused, isTrue);

        await queryClient.resumePausedMutations();

        // Still paused, because it is still offline.
        expect(observer.result.isPaused, isTrue);

        onlineManager.setOnline(true);

        await time.advance(Duration.zero);
        expect(observer.result.status, MutationStatus.success);
      },
    );

    testFakeAsync(
      'should resume when coming online after a restored mutation was resumed '
      'while offline',
      (time) async {
        onlineManager.setOnline(false);

        // Upstream dehydrates a paused mutation and hydrates it into a fresh
        // client; the port has no hydration, so the restored state is built
        // directly — which is exactly what hydration would produce.
        final newQueryClient = QueryClient(
          defaultMutationOptionsBag: MutationDefaults(
            mutationFn: (_, _) async => 1,
          ),
        )..mount();

        final restored = newQueryClient.mutationCache
            .build<int, Object?, Object?>(
              newQueryClient.defaultMutationOptions(
                const MutationOptions<int, Object?, Object?>(),
              ),
              state: MutationState<int, Object?, Object?>(
                isPaused: true,
                status: MutationStatus.pending,
                submittedAt: DateTime.utc(2020),
              ),
            );

        expect(restored.state.isPaused, isTrue);

        await newQueryClient.resumePausedMutations();

        onlineManager.setOnline(true);

        await time.advance(Duration.zero);
        expect(restored.state.status, MutationStatus.success);

        newQueryClient.unmount();
      },
    );

    testFakeAsync(
      'should notify the query cache only after resumePausedMutations has '
      'finished when coming online',
      (time) async {
        final key = queryKey();
        var count = 0;
        final results = <String>[];

        final queryObserver = QueryObserver<String, String>(
          queryClient,
          str(
            key,
            queryFn: (_) async {
              count++;
              results.add('data$count');
              await sleep(ms(10));
              return 'data$count';
            },
          ),
        );

        final unsubscribe = queryObserver.subscribe((_) {});

        await time.advance(ms(10));
        expect(queryClient.getQueryData<String>(key), 'data1');

        onlineManager.setOnline(false);

        MutationObserver<int, Object?, Object?> build(
          String label,
          int value, {
          String? scope,
        }) => MutationObserver<int, Object?, Object?>(
          queryClient,
          MutationOptions<int, Object?, Object?>(
            scope: scope,
            mutationFn: (_, _) async {
              results.add('$label-start');
              await sleep(ms(50));
              results.add('$label-end');
              return value;
            },
          ),
        );

        final observer = build('mutation1', 1);
        observer.mutate(null).ignore();
        final observer2 = build('mutation2', 2, scope: 'scope');
        observer2.mutate(null).ignore();
        final observer3 = build('mutation3', 3, scope: 'scope');
        observer3.mutate(null).ignore();

        expect(observer.result.isPaused, isTrue);
        expect(observer2.result.isPaused, isTrue);
        expect(observer3.result.isPaused, isTrue);

        onlineManager.setOnline(true);

        await time.advance(ms(110));
        expect(queryClient.getQueryData<String>(key), 'data2');

        // The refetch triggered by coming back online happens only once every
        // queued write has landed.
        expect(results, [
          'data1',
          'mutation1-start',
          'mutation2-start',
          'mutation1-end',
          'mutation2-end',
          // 3 starts after 2 because they share a scope.
          'mutation3-start',
          'mutation3-end',
          'data2',
        ]);

        unsubscribe();
      },
    );
  });

  group('setMutationDefaults', () {
    test('should update existing mutation defaults', () {
      final key = queryKey();

      queryClient.setMutationDefaults(
        key,
        MutationDefaults(mutationFn: (_, _) async => 'data'),
      );
      queryClient.setMutationDefaults(
        key,
        const MutationDefaults(retry: RetryOption.never),
      );

      final defaults = queryClient.getMutationDefaults(key);
      expect(defaults.retry, RetryOption.never);
      expect(
        defaults.mutationFn,
        isNull,
        reason: 'a second registration replaces the first, it does not merge',
      );
    });

    test(
      'should return only matching defaults when several are registered',
      () {
        final key1 = queryKey();
        final key2 = queryKey();

        queryClient.setMutationDefaults(
          key1,
          const MutationDefaults(retry: RetryOption.count(1)),
        );
        queryClient.setMutationDefaults(
          key2,
          const MutationDefaults(retry: RetryOption.count(2)),
        );

        expect(
          queryClient.getMutationDefaults(key1).retry,
          const RetryOption.count(1),
        );
        expect(
          queryClient.getMutationDefaults(key2).retry,
          const RetryOption.count(2),
        );
      },
    );
  });
}
