import 'dart:async';

import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Port of `query/packages/query-core/src/__tests__/queryCache.test.tsx`.
///
/// Divergences are recorded in PORTING_NOTES.md; the two `build` cases about
/// `queryHash` have no counterpart because the port has no hash.
void main() {
  late QueryClient queryClient;
  late QueryCache queryCache;

  setUp(() {
    queryClient = QueryClient();
    queryCache = queryClient.queryCache;
  });

  tearDown(() => queryClient.clear());

  group('subscribe', () {
    test('should pass the correct query', () {
      final key = queryKey();
      final events = <QueryCacheEvent>[];
      final unsubscribe = queryCache.subscribe(events.add);

      queryClient.setQueryData<String>(key, (_) => 'foo');

      final query = queryCache.find(key);
      expect(events.first, isA<QueryAdded>());
      expect(events.first.query, same(query));
      unsubscribe();
    });

    testFakeAsync('should notify listeners when new query is added', (
      time,
    ) async {
      final key = queryKey();
      final events = <QueryCacheEvent>[];
      queryCache.subscribe(events.add);

      unawaited(
        queryClient.prefetchQuery(
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: (_) => sleep(ms(100)).then((_) => 'data'),
          ),
        ),
      );
      await time.advance(ms(100));

      expect(events.first, isA<QueryAdded>());
      expect(events.first.query, same(queryCache.find(key)));
    });

    testFakeAsync('should notify query cache when a query becomes stale', (
      time,
    ) async {
      final key = queryKey();
      final events = <String>[];
      final queries = <Query<Object?>>[];
      final unsubscribe = queryCache.subscribe((event) {
        events.add(eventName(event));
        queries.add(event.query);
      });

      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async => 'data',
          staleTime: const StaleDuration.of(Duration(milliseconds: 10)),
        ),
      );

      final unsubscribeObserver = observer.subscribe((_) {});

      await time.advance(ms(11));

      expect(events, <String>[
        'added', // 1. Query added -> loading
        'observerResultsUpdated', // 2. Observer result updated -> loading
        'observerAdded', // 3. Observer added
        'observerResultsUpdated', // 4. Observer result updated -> fetching
        'updated', // 5. Query updated -> fetching
        'observerResultsUpdated', // 6. Observer result updated -> success
        'updated', // 7. Query updated -> success
        'observerResultsUpdated', // 8. Observer result updated -> stale
      ]);

      final cachedQuery = queryCache.find(key);
      for (final query in queries) {
        expect(query, same(cachedQuery));
      }

      unsubscribe();
      unsubscribeObserver();
    });

    testFakeAsync(
      'should include the queryCache and query when notifying listeners',
      (time) async {
        final key = queryKey();
        final events = <QueryCacheEvent>[];
        queryCache.subscribe(events.add);

        unawaited(
          queryClient.prefetchQuery(
            QueryObserverOptions<String, String>(
              queryKey: key,
              queryFn: (_) => sleep(ms(100)).then((_) => 'data'),
            ),
          ),
        );
        await time.advance(ms(100));

        expect(events.first, isA<QueryAdded>());
        expect(events.first.query, same(queryCache.find(key)));
      },
    );

    testFakeAsync(
      'should notify subscribers when new query with initialData is added',
      (time) async {
        final key = queryKey();
        final events = <QueryCacheEvent>[];
        queryCache.subscribe(events.add);

        unawaited(
          queryClient.prefetchQuery(
            QueryObserverOptions<String, String>(
              queryKey: key,
              queryFn: (_) => sleep(ms(100)).then((_) => 'data'),
              initialData: () => 'initial',
            ),
          ),
        );
        await time.advance(ms(100));

        expect(events.first, isA<QueryAdded>());
        expect(events.first.query, same(queryCache.find(key)));
      },
    );

    testFakeAsync('should be able to limit cache size', (time) async {
      final testCache = QueryCache();

      final unsubscribe = testCache.subscribe((event) {
        if (event is! QueryAdded) {
          return;
        }
        if (testCache.queries.length > 2) {
          for (final query in testCache.findAll(
            QueryFilters(
              type: QueryTypeFilter.inactive,
              predicate: (query) => !identical(query, event.query),
            ),
          )) {
            testCache.remove(query);
          }
        }
      });

      final testClient = QueryClient(queryCache: testCache);

      final key1 = queryKey();
      final key2 = queryKey();
      final key3 = queryKey();

      unawaited(
        testClient.prefetchQuery(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            queryFn: (_) => sleep(ms(100)).then((_) => 'data1'),
          ),
        ),
      );
      expect(testCache.findAll(), hasLength(1));

      unawaited(
        testClient.prefetchQuery(
          QueryObserverOptions<String, String>(
            queryKey: key2,
            queryFn: (_) => sleep(ms(100)).then((_) => 'data2'),
          ),
        ),
      );
      expect(testCache.findAll(), hasLength(2));

      unawaited(
        testClient.prefetchQuery(
          QueryObserverOptions<String, String>(
            queryKey: key3,
            queryFn: (_) => sleep(ms(100)).then((_) => 'data3'),
          ),
        ),
      );
      await time.advance(ms(100));

      expect(testCache.findAll(), hasLength(1));
      expect(testCache.findAll().first.state.data, 'data3');

      unsubscribe();
    });
  });

  group('find', () {
    testFakeAsync('find should filter correctly', (time) async {
      final key = queryKey();
      unawaited(
        queryClient.prefetchQuery(
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: (_) => sleep(ms(100)).then((_) => 'data1'),
          ),
        ),
      );
      await time.advance(ms(100));

      expect(queryCache.find(key)!.state.data, 'data1');
    });

    testFakeAsync('find should filter correctly with exact set to false', (
      time,
    ) async {
      final key = queryKey();
      unawaited(
        queryClient.prefetchQuery(
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: (_) => sleep(ms(100)).then((_) => 'data1'),
          ),
        ),
      );
      await time.advance(ms(100));

      final query = queryCache.find(key, filters: const QueryFilters());
      expect(query!.state.data, 'data1');
    });
  });

  group('findAll', () {
    testFakeAsync('should filter correctly', (time) async {
      final key1 = queryKey();
      final key2 = queryKey();
      final keyFetching = queryKey();

      Future<void> prefetch(QueryKey key, String data, Duration delay) =>
          queryClient.prefetchQuery(
            QueryObserverOptions<String, String>(
              queryKey: key,
              queryFn: (_) => sleep(delay).then((_) => data),
            ),
          );

      unawaited(prefetch(key1, 'data1', ms(100)));
      unawaited(prefetch(key2, 'data2', ms(100)));
      unawaited(
        prefetch(
          const QueryKey([
            {'a': 'a', 'b': 'b'},
          ]),
          'data3',
          ms(100),
        ),
      );
      unawaited(prefetch(const QueryKey(['posts', 1]), 'data4', ms(100)));
      await time.advance(ms(100));

      unawaited(
        queryClient.invalidateQueries(filters: QueryFilters(queryKey: key2)),
      );

      final query1 = queryCache.find(key1)!;
      final query2 = queryCache.find(key2)!;
      final query3 = queryCache.find(
        const QueryKey([
          {'a': 'a', 'b': 'b'},
        ]),
      )!;
      final query4 = queryCache.find(const QueryKey(['posts', 1]))!;

      expect(queryCache.findAll(QueryFilters(queryKey: key1)), [query1]);
      // Wrapping the key in another array does not match: keys are arrays, so
      // this asks for a key whose first part is itself that array.
      expect(
        queryCache.findAll(QueryFilters(queryKey: QueryKey([key1.parts]))),
        isEmpty,
      );
      expect(queryCache.findAll(), [query1, query2, query3, query4]);
      expect(queryCache.findAll(const QueryFilters()), [
        query1,
        query2,
        query3,
        query4,
      ]);
      expect(
        queryCache.findAll(
          QueryFilters(queryKey: key1, type: QueryTypeFilter.inactive),
        ),
        [query1],
      );
      expect(
        queryCache.findAll(
          QueryFilters(queryKey: key1, type: QueryTypeFilter.active),
        ),
        isEmpty,
      );
      expect(
        queryCache.findAll(QueryFilters(queryKey: key1, stale: true)),
        isEmpty,
      );
      expect(queryCache.findAll(QueryFilters(queryKey: key1, stale: false)), [
        query1,
      ]);
      expect(
        queryCache.findAll(
          QueryFilters(
            queryKey: key1,
            stale: false,
            type: QueryTypeFilter.active,
          ),
        ),
        isEmpty,
      );
      expect(
        queryCache.findAll(
          QueryFilters(
            queryKey: key1,
            stale: false,
            type: QueryTypeFilter.inactive,
          ),
        ),
        [query1],
      );
      expect(
        queryCache.findAll(
          QueryFilters(
            queryKey: key1,
            stale: false,
            type: QueryTypeFilter.inactive,
            exact: true,
          ),
        ),
        [query1],
      );

      expect(queryCache.findAll(QueryFilters(queryKey: key2)), [query2]);
      expect(queryCache.findAll(QueryFilters(queryKey: key2, stale: null)), [
        query2,
      ]);
      expect(queryCache.findAll(QueryFilters(queryKey: key2, stale: true)), [
        query2,
      ]);
      expect(
        queryCache.findAll(QueryFilters(queryKey: key2, stale: false)),
        isEmpty,
      );
      expect(
        queryCache.findAll(
          const QueryFilters(
            queryKey: QueryKey([
              {'b': 'b'},
            ]),
          ),
        ),
        [query3],
      );
      expect(
        queryCache.findAll(
          const QueryFilters(
            queryKey: QueryKey([
              {'a': 'a'},
            ]),
            exact: false,
          ),
        ),
        [query3],
      );
      expect(
        queryCache.findAll(
          const QueryFilters(
            queryKey: QueryKey([
              {'a': 'a'},
            ]),
            exact: true,
          ),
        ),
        isEmpty,
      );
      expect(
        queryCache.findAll(
          const QueryFilters(
            queryKey: QueryKey([
              {'a': 'a', 'b': 'b'},
            ]),
            exact: true,
          ),
        ),
        [query3],
      );
      expect(
        queryCache.findAll(
          const QueryFilters(
            queryKey: QueryKey([
              {'a': 'a', 'b': 'b'},
            ]),
          ),
        ),
        [query3],
      );
      expect(
        queryCache.findAll(
          const QueryFilters(
            queryKey: QueryKey([
              {'a': 'a', 'b': 'b', 'c': 'c'},
            ]),
          ),
        ),
        isEmpty,
      );
      expect(
        queryCache.findAll(
          const QueryFilters(
            queryKey: QueryKey([
              {'a': 'a'},
            ]),
            stale: false,
          ),
        ),
        [query3],
      );
      expect(
        queryCache.findAll(
          const QueryFilters(
            queryKey: QueryKey([
              {'a': 'a'},
            ]),
            stale: true,
          ),
        ),
        isEmpty,
      );
      expect(
        queryCache.findAll(
          const QueryFilters(
            queryKey: QueryKey([
              {'a': 'a'},
            ]),
            type: QueryTypeFilter.active,
          ),
        ),
        isEmpty,
      );
      expect(
        queryCache.findAll(
          const QueryFilters(
            queryKey: QueryKey([
              {'a': 'a'},
            ]),
            type: QueryTypeFilter.inactive,
          ),
        ),
        [query3],
      );
      expect(
        queryCache.findAll(
          QueryFilters(predicate: (query) => identical(query, query3)),
        ),
        [query3],
      );
      expect(
        queryCache.findAll(const QueryFilters(queryKey: QueryKey(['posts']))),
        [query4],
      );

      expect(
        queryCache.findAll(const QueryFilters(fetchStatus: FetchStatus.idle)),
        [query1, query2, query3, query4],
      );
      expect(
        queryCache.findAll(QueryFilters(queryKey: key2, fetchStatus: null)),
        [query2],
      );

      unawaited(prefetch(keyFetching, 'dataFetching', ms(20)));
      expect(
        queryCache.findAll(
          const QueryFilters(fetchStatus: FetchStatus.fetching),
        ),
        [queryCache.find(keyFetching)],
      );
      await time.advance(ms(20));
      expect(
        queryCache.findAll(
          const QueryFilters(fetchStatus: FetchStatus.fetching),
        ),
        isEmpty,
      );
    });

    testFakeAsync('should return all the queries when no filters are defined', (
      time,
    ) async {
      final key1 = queryKey();
      final key2 = queryKey();
      await queryClient.prefetchQuery(
        QueryObserverOptions<String, String>(
          queryKey: key1,
          queryFn: (_) async => 'data1',
        ),
      );
      await queryClient.prefetchQuery(
        QueryObserverOptions<String, String>(
          queryKey: key2,
          queryFn: (_) async => 'data2',
        ),
      );
      expect(queryCache.findAll(), hasLength(2));
    });
  });

  group('QueryCacheConfig error callbacks', () {
    testFakeAsync('should call onError and onSettled when a query errors', (
      time,
    ) async {
      final key = queryKey();
      final successes = <Object?>[];
      final errors = <Object?>[];
      final settled = <(Object?, Object?)>[];

      final testCache = QueryCache(
        onSuccess: (data, _) => successes.add(data),
        onError: (error, _, _) => errors.add(error),
        onSettled: (data, error, _) => settled.add((data, error)),
      );
      final testClient = QueryClient(queryCache: testCache);

      unawaited(
        testClient.prefetchQuery(
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: (_) =>
                sleep(ms(100)).then((_) => Future<String>.error('error')),
          ),
        ),
      );
      await time.advance(ms(100));

      expect(errors, ['error']);
      expect(successes, isEmpty);
      expect(settled, [(null, 'error')]);
    });
  });

  group('QueryCacheConfig success callbacks', () {
    testFakeAsync(
      'should call onSuccess and onSettled when a query is successful',
      (time) async {
        final key = queryKey();
        final successes = <Object?>[];
        final errors = <Object?>[];
        final settled = <(Object?, Object?)>[];

        final testCache = QueryCache(
          onSuccess: (data, _) => successes.add(data),
          onError: (error, _, _) => errors.add(error),
          onSettled: (data, error, _) => settled.add((data, error)),
        );
        final testClient = QueryClient(queryCache: testCache);

        unawaited(
          testClient.prefetchQuery(
            QueryObserverOptions<int, int>(
              queryKey: key,
              queryFn: (_) => sleep(ms(100)).then((_) => 5),
            ),
          ),
        );
        await time.advance(ms(100));

        expect(successes, [5]);
        expect(errors, isEmpty);
        expect(settled, [(5, null)]);
      },
    );
  });

  group('QueryCache.remove', () {
    test('should only delete the instance currently stored under its key', () {
      final key = queryKey();
      final options = queryClient.defaultQueryOptions(
        QueryObserverOptions<String, String>(queryKey: key),
      );

      final staleQuery = queryCache.build<String>(options);
      queryCache.remove(staleQuery);

      final currentQuery = queryCache.build<String>(options);
      expect(currentQuery, isNot(same(staleQuery)));

      queryCache.remove(staleQuery);

      expect(queryCache.get<String>(key), same(currentQuery));
    });
  });

  group('QueryCache.add', () {
    testFakeAsync('should not try to add a query already added to the cache', (
      time,
    ) async {
      final key = queryKey();

      unawaited(
        queryClient.prefetchQuery(
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: (_) => sleep(ms(100)).then((_) => 'data1'),
          ),
        ),
      );
      await time.advance(ms(100));

      final query = queryCache.findAll().first;
      // Upstream clones the query object; here a second instance under the same
      // key is the equivalent — `add` must leave the original in place.
      final duplicate = Query<String>(
        queryKey: key,
        host: queryCache,
        options: queryClient.defaultQueryOptions(
          QueryObserverOptions<String, String>(queryKey: key),
        ),
      );

      queryCache.add(duplicate);
      expect(queryCache.queries, hasLength(1));
      expect(queryCache.queries.single, same(query));
    });
  });
}
