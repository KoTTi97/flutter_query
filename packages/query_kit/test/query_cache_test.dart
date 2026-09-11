/// Port of `query-core/src/__tests__/queryCache.test.tsx` at upstream
/// `50680b98c`. Omissions and adaptations: `test/PORTING_NOTES.md`.
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('queryCache', () {
    late QueryClient queryClient;
    late QueryCache queryCache;

    setUp(() {
      queryClient = testClient();
      queryCache = queryClient.queryCache;
    });

    tearDown(() => queryClient.clear());

    group('subscribe', () {
      testFakeAsync('should pass the correct query', (time) async {
        final key = queryKey();
        final events = <QueryCacheEvent>[];
        final unsubscribe = queryCache.subscribe(events.add);
        queryClient.setQueryData<String>(key, 'foo');
        final query = queryCache.find(filters: QueryFilters(queryKey: key));
        expect(events.first, isA<QueryAdded>());
        expect(events.first.query, same(query));
        unsubscribe();
      });

      testFakeAsync('should notify listeners when new query is added',
          (time) async {
        final key = queryKey();
        final events = <QueryCacheEvent>[];
        queryCache.subscribe(events.add);
        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: key,
              queryFn: (_) async {
                await sleep(ms(100));
                return 'data';
              },
            ))
            .ignore();
        await time.advance(ms(100));
        final query = queryCache.find(filters: QueryFilters(queryKey: key));
        expect(events.first, isA<QueryAdded>());
        expect(events.first.query, same(query));
      });

      testFakeAsync('should notify query cache when a query becomes stale',
          (time) async {
        final key = queryKey();
        final events = <String>[];
        final queries = <Query<Object?>>[];
        final unsubscribe = queryCache.subscribe((event) {
          events.add(eventName(event));
          queries.add(event.query);
        });

        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => 'data',
            staleTime: StaleTime.duration(ms(10)),
          ),
        );

        final unsubscribeObserver = observer.subscribe((_) {});

        await time.advance(ms(11));
        expect(events.length, 8);

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

        final cachedQuery =
            queryCache.find(filters: QueryFilters(queryKey: key));
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
        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: key,
              queryFn: (_) async {
                await sleep(ms(100));
                return 'data';
              },
            ))
            .ignore();
        await time.advance(ms(100));
        final query = queryCache.find(filters: QueryFilters(queryKey: key));
        expect(events.first, isA<QueryAdded>());
        expect(events.first.query, same(query));
      });

      testFakeAsync(
          'should notify subscribers when new query with initialData is added',
          (time) async {
        final key = queryKey();
        final events = <QueryCacheEvent>[];
        queryCache.subscribe(events.add);
        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: key,
              queryFn: (_) async {
                await sleep(ms(100));
                return 'data';
              },
              initialData: const InitialData<String>.value('initial'),
            ))
            .ignore();
        await time.advance(ms(100));
        final query = queryCache.find(filters: QueryFilters(queryKey: key));
        expect(events.first, isA<QueryAdded>());
        expect(events.first.query, same(query));
      });

      testFakeAsync('should be able to limit cache size', (time) async {
        final testCache = QueryCache();

        final unsubscribe = testCache.subscribe((event) {
          if (event is QueryAdded) {
            if (testCache.queries.length > 2) {
              for (final query in testCache.findAll(
                filters: QueryFilters(
                  type: QueryTypeFilter.inactive,
                  predicate: (q) => !identical(q, event.query),
                ),
              )) {
                testCache.remove(query);
              }
            }
          }
        });

        final client = testClient(queryCache: testCache);

        final key1 = queryKey();
        final key2 = queryKey();
        final key3 = queryKey();
        client
            .query<String>(QueryOptions<String>(
              queryKey: key1,
              queryFn: (_) async {
                await sleep(ms(100));
                return 'data1';
              },
            ))
            .ignore();
        expect(testCache.findAll().length, 1);
        client
            .query<String>(QueryOptions<String>(
              queryKey: key2,
              queryFn: (_) async {
                await sleep(ms(100));
                return 'data2';
              },
            ))
            .ignore();
        expect(testCache.findAll().length, 2);
        client
            .query<String>(QueryOptions<String>(
              queryKey: key3,
              queryFn: (_) async {
                await sleep(ms(100));
                return 'data3';
              },
            ))
            .ignore();
        await time.advance(ms(100));
        expect(testCache.findAll().length, 1);
        expect(testCache.findAll().first.state.data, 'data3');

        unsubscribe();
      });
    });

    group('find', () {
      testFakeAsync('find should filter correctly', (time) async {
        final key = queryKey();
        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: key,
              queryFn: (_) async {
                await sleep(ms(100));
                return 'data1';
              },
            ))
            .ignore();
        await time.advance(ms(100));
        final query = queryCache.find(filters: QueryFilters(queryKey: key))!;
        expect(query.state.data, 'data1');
      });

      testFakeAsync('find should filter correctly with exact set to false',
          (time) async {
        final key = queryKey();
        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: key,
              queryFn: (_) async {
                await sleep(ms(100));
                return 'data1';
              },
            ))
            .ignore();
        await time.advance(ms(100));
        final query = queryCache.find(
            filters: QueryFilters(queryKey: key, exact: false))!;
        expect(query.state.data, 'data1');
      });
    });

    group('findAll', () {
      testFakeAsync('should filter correctly', (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        final keyFetching = queryKey();
        Future<String> after(Duration duration, String data) async {
          await sleep(duration);
          return data;
        }

        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: key1,
              queryFn: (_) => after(ms(100), 'data1'),
            ))
            .ignore();
        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: key2,
              queryFn: (_) => after(ms(100), 'data2'),
            ))
            .ignore();
        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: QueryKey(<Object?>[
                <String, String>{'a': 'a', 'b': 'b'}
              ]),
              queryFn: (_) => after(ms(100), 'data3'),
            ))
            .ignore();
        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: QueryKey(<Object?>['posts', 1]),
              queryFn: (_) => after(ms(100), 'data4'),
            ))
            .ignore();
        await time.advance(ms(100));
        queryClient
            .invalidateQueries(filters: QueryFilters(queryKey: key2))
            .ignore();
        final query1 = queryCache.find(filters: QueryFilters(queryKey: key1))!;
        final query2 = queryCache.find(filters: QueryFilters(queryKey: key2))!;
        final query3 = queryCache.find(
            filters: QueryFilters(
                queryKey: QueryKey(<Object?>[
          <String, String>{'a': 'a', 'b': 'b'}
        ])))!;
        final query4 = queryCache.find(
            filters: QueryFilters(queryKey: QueryKey(<Object?>['posts', 1])))!;

        expect(queryCache.findAll(filters: QueryFilters(queryKey: key1)),
            [query1]);
        // wrapping in an extra array doesn't yield the same results anymore
        // since v4 because keys need to be an array
        expect(
          queryCache.findAll(
              filters: QueryFilters(queryKey: QueryKey(<Object?>[key1.parts]))),
          isEmpty,
        );
        expect(queryCache.findAll(), [query1, query2, query3, query4]);
        expect(queryCache.findAll(filters: const QueryFilters()),
            [query1, query2, query3, query4]);
        expect(
          queryCache.findAll(
              filters:
                  QueryFilters(queryKey: key1, type: QueryTypeFilter.inactive)),
          [query1],
        );
        expect(
          queryCache.findAll(
              filters:
                  QueryFilters(queryKey: key1, type: QueryTypeFilter.active)),
          isEmpty,
        );
        expect(
            queryCache.findAll(
                filters: QueryFilters(queryKey: key1, stale: true)),
            isEmpty);
        expect(
            queryCache.findAll(
                filters: QueryFilters(queryKey: key1, stale: false)),
            [query1]);
        expect(
          queryCache.findAll(
              filters: QueryFilters(
                  queryKey: key1, stale: false, type: QueryTypeFilter.active)),
          isEmpty,
        );
        expect(
          queryCache.findAll(
              filters: QueryFilters(
                  queryKey: key1,
                  stale: false,
                  type: QueryTypeFilter.inactive)),
          [query1],
        );
        expect(
          queryCache.findAll(
              filters: QueryFilters(
            queryKey: key1,
            stale: false,
            type: QueryTypeFilter.inactive,
            exact: true,
          )),
          [query1],
        );

        expect(queryCache.findAll(filters: QueryFilters(queryKey: key2)),
            [query2]);
        expect(
            queryCache.findAll(
                filters: QueryFilters(queryKey: key2, stale: null)),
            [query2]);
        expect(
            queryCache.findAll(
                filters: QueryFilters(queryKey: key2, stale: true)),
            [query2]);
        expect(
            queryCache.findAll(
                filters: QueryFilters(queryKey: key2, stale: false)),
            isEmpty);
        expect(
          queryCache.findAll(
              filters: QueryFilters(
                  queryKey: QueryKey(<Object?>[
            <String, String>{'b': 'b'}
          ]))),
          [query3],
        );
        expect(
          queryCache.findAll(
              filters: QueryFilters(
            queryKey: QueryKey(<Object?>[
              <String, String>{'a': 'a'}
            ]),
            exact: false,
          )),
          [query3],
        );
        expect(
          queryCache.findAll(
              filters: QueryFilters(
            queryKey: QueryKey(<Object?>[
              <String, String>{'a': 'a'}
            ]),
            exact: true,
          )),
          isEmpty,
        );
        expect(
          queryCache.findAll(
              filters: QueryFilters(
            queryKey: QueryKey(<Object?>[
              <String, String>{'a': 'a', 'b': 'b'}
            ]),
            exact: true,
          )),
          [query3],
        );
        expect(
          queryCache.findAll(
              filters: QueryFilters(
                  queryKey: QueryKey(<Object?>[
            <String, String>{'a': 'a', 'b': 'b'}
          ]))),
          [query3],
        );
        expect(
          queryCache.findAll(
              filters: QueryFilters(
                  queryKey: QueryKey(<Object?>[
            <String, String>{'a': 'a', 'b': 'b', 'c': 'c'}
          ]))),
          isEmpty,
        );
        expect(
          queryCache.findAll(
              filters: QueryFilters(
            queryKey: QueryKey(<Object?>[
              <String, String>{'a': 'a'}
            ]),
            stale: false,
          )),
          [query3],
        );
        expect(
          queryCache.findAll(
              filters: QueryFilters(
            queryKey: QueryKey(<Object?>[
              <String, String>{'a': 'a'}
            ]),
            stale: true,
          )),
          isEmpty,
        );
        expect(
          queryCache.findAll(
              filters: QueryFilters(
            queryKey: QueryKey(<Object?>[
              <String, String>{'a': 'a'}
            ]),
            type: QueryTypeFilter.active,
          )),
          isEmpty,
        );
        expect(
          queryCache.findAll(
              filters: QueryFilters(
            queryKey: QueryKey(<Object?>[
              <String, String>{'a': 'a'}
            ]),
            type: QueryTypeFilter.inactive,
          )),
          [query3],
        );
        expect(
          queryCache.findAll(
              filters:
                  QueryFilters(predicate: (query) => identical(query, query3))),
          [query3],
        );
        expect(
            queryCache.findAll(
                filters: QueryFilters(queryKey: QueryKey(<Object?>['posts']))),
            [query4]);

        expect(
          queryCache.findAll(
              filters: const QueryFilters(fetchStatus: FetchStatus.idle)),
          [query1, query2, query3, query4],
        );
        expect(
          queryCache.findAll(
              filters: QueryFilters(queryKey: key2, fetchStatus: null)),
          [query2],
        );

        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: keyFetching,
              queryFn: (_) => after(ms(20), 'dataFetching'),
            ))
            .ignore();
        expect(
          queryCache.findAll(
              filters: const QueryFilters(fetchStatus: FetchStatus.fetching)),
          [queryCache.find(filters: QueryFilters(queryKey: keyFetching))],
        );
        await time.advance(ms(20));
        expect(
          queryCache.findAll(
              filters: const QueryFilters(fetchStatus: FetchStatus.fetching)),
          isEmpty,
        );
      });

      testFakeAsync('should return all the queries when no filters are defined',
          (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        await queryClient.query<String>(QueryOptions<String>(
          queryKey: key1,
          queryFn: (_) => 'data1',
        ));
        await queryClient.query<String>(QueryOptions<String>(
          queryKey: key2,
          queryFn: (_) => 'data2',
        ));
        expect(queryCache.findAll().length, 2);
      });
    });

    group('QueryCacheConfig error callbacks', () {
      testFakeAsync('should call onError and onSettled when a query errors',
          (time) async {
        final key = queryKey();
        final successes = <(Object?, Query<Object?>)>[];
        final errors = <(Object, Query<Object?>)>[];
        final settled = <(Object?, Object?, Query<Object?>)>[];
        final testCache = QueryCache(
          onSuccess: (data, query) => successes.add((data, query)),
          onError: (error, _, query) => errors.add((error, query)),
          onSettled: (data, error, _, query) =>
              settled.add((data, error, query)),
        );
        final testClientWithCache = testClient(queryCache: testCache);
        testClientWithCache
            .query<String>(QueryOptions<String>(
              queryKey: key,
              queryFn: (_) async {
                await sleep(ms(100));
                throw 'error';
              },
            ))
            .ignore();
        await time.advance(ms(100));
        final query = testCache.find(filters: QueryFilters(queryKey: key));
        expect(errors, [('error', query)]);
        expect(successes, isEmpty);
        expect(settled, [(null, 'error', query)]);
      });
    });

    group('QueryCacheConfig success callbacks', () {
      testFakeAsync(
          'should call onSuccess and onSettled when a query is successful',
          (time) async {
        final key = queryKey();
        final successes = <(Object?, Query<Object?>)>[];
        final errors = <(Object, Query<Object?>)>[];
        final settled = <(Object?, Object?, Query<Object?>)>[];
        final testCache = QueryCache(
          onSuccess: (data, query) => successes.add((data, query)),
          onError: (error, _, query) => errors.add((error, query)),
          onSettled: (data, error, _, query) =>
              settled.add((data, error, query)),
        );
        final testClientWithCache = testClient(queryCache: testCache);
        testClientWithCache
            .query<Map<String, int>>(QueryOptions<Map<String, int>>(
              queryKey: key,
              queryFn: (_) async {
                await sleep(ms(100));
                return <String, int>{'data': 5};
              },
            ))
            .ignore();
        await time.advance(ms(100));
        final query = testCache.find(filters: QueryFilters(queryKey: key));
        // Records compare their fields with `==`, and two equal Dart maps are
        // not `==`, so the payload is asserted field by field.
        expect(successes, hasLength(1));
        expect(successes.single.$1, equals(<String, int>{'data': 5}));
        expect(successes.single.$2, same(query));
        expect(errors, isEmpty);
        expect(settled, hasLength(1));
        expect(settled.single.$1, equals(<String, int>{'data': 5}));
        expect(settled.single.$2, isNull);
        expect(settled.single.$3, same(query));
      });
    });

    group('QueryCache.remove', () {
      testFakeAsync(
          'should only delete the instance currently stored under its key',
          (time) async {
        final key = queryKey();
        final options = queryClient
            .defaultQueryOptions<String>(QueryOptions<String>(queryKey: key));

        final staleQuery = queryCache.build<String>(queryClient, options);
        queryCache.remove(staleQuery);

        final currentQuery = queryCache.build<String>(queryClient, options);
        expect(currentQuery, isNot(same(staleQuery)));

        queryCache.remove(staleQuery);

        expect(queryCache.get<String>(key), same(currentQuery));
      });
    });

    group('QueryCache.add', () {
      testFakeAsync('should not try to add a query already added to the cache',
          (time) async {
        final key = queryKey();

        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: key,
              queryFn: (_) async {
                await sleep(ms(100));
                return 'data1';
              },
            ))
            .ignore();
        await time.advance(ms(100));

        final query = queryCache.findAll().first;
        final duplicate = Query<String>(
          client: queryClient,
          cache: queryCache,
          queryKey: key,
          options: queryClient
              .defaultQueryOptions<String>(QueryOptions<String>(queryKey: key)),
        );

        queryCache.add(duplicate);
        expect(queryCache.queries.length, 1);
        expect(queryCache.queries.single, same(query));
      });
    });
  });
}
