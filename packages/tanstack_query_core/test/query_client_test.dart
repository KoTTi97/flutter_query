/// Port of `query-core/src/__tests__/queryClient.test.tsx` at upstream
/// `50680b98c`. Omissions and adaptations: `test/PORTING_NOTES.md`.
library;

import 'package:tanstack_query_core/tanstack_query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('queryClient', () {
    late QueryClient queryClient;
    late QueryCache queryCache;

    setUp(() {
      queryClient = testClient();
      queryCache = queryClient.queryCache;
      queryClient.mount();
    });

    tearDown(() {
      queryClient.clear();
      queryClient.unmount();
    });

    group('defaultOptions', () {
      testFakeAsync('should merge defaultOptions', (time) async {
        final key = queryKey();

        String queryFn(QueryFunctionContext _) => 'data';
        final client = testClient(
          defaultOptions:
              DefaultOptions(queries: QueryDefaults(queryFn: queryFn)),
        );

        expect(
          () => client.query<String>(QueryOptions<String>(queryKey: key)),
          returnsNormally,
        );
      });

      testFakeAsync('should merge defaultOptions when query is added to cache',
          (time) async {
        final key = queryKey();

        final client = testClient(
          defaultOptions: const DefaultOptions(
              queries: QueryDefaults(gcTime: GcTime.never)),
        );

        await client.query<String>(QueryOptions<String>(
          queryKey: key,
          queryFn: (_) => Future<String>.value('data'),
        ));
        final newQuery = client.queryCache.find(QueryFilters(queryKey: key));
        expect(newQuery?.options.gcTime, GcTime.never);
      });

      testFakeAsync('should get defaultOptions', (time) async {
        String queryFn(QueryFunctionContext _) => 'data';
        final defaultOptions =
            DefaultOptions(queries: QueryDefaults(queryFn: queryFn));
        final client = testClient(defaultOptions: defaultOptions);
        expect(client.getDefaultOptions().queries?.queryFn, same(queryFn));
      });
    });

    group('setQueryDefaults', () {
      testFakeAsync('should not trigger a fetch', (time) async {
        final key = queryKey();
        queryClient.setQueryDefaults(
          key,
          QueryDefaults(queryFn: (_) => 'data'),
        );
        expect(queryClient.getQueryData<String>(key), isNull);
      });

      testFakeAsync('should be able to override defaults', (time) async {
        final key = queryKey();
        queryClient.setQueryDefaults(
          key,
          QueryDefaults(queryFn: (_) => 'data'),
        );
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(queryKey: key),
        );
        final result = await observer.refetch();
        expect(result.dataOrNull, 'data');
      });

      testFakeAsync('should match the query key partially', (time) async {
        final key = queryKey();
        queryClient.setQueryDefaults(
          key,
          QueryDefaults(queryFn: (_) => 'data'),
        );
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
              queryKey: key.append(<Object?>['a'])),
        );
        final result = await observer.refetch();
        expect(result.dataOrNull, 'data');
      });

      testFakeAsync('should not match if the query key is a subset',
          (time) async {
        final key = queryKey();
        queryClient.setQueryDefaults(
          key.append(<Object?>['a']),
          QueryDefaults(queryFn: (_) => 'data'),
        );
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key,
            retry: RetryPolicy.never,
            enabled: Enabled.no,
          ),
        );
        final result = await observer.refetch();
        expect(result.status, QueryStatus.error);
      });

      testFakeAsync('should also set defaults for observers', (time) async {
        final key = queryKey();
        queryClient.setQueryDefaults(
          key,
          QueryDefaults(queryFn: (_) => 'data', enabled: Enabled.no),
        );
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(queryKey: key),
        );
        expect(observer.currentResult.status, QueryStatus.pending);
        expect(observer.currentResult.fetchStatus, FetchStatus.idle);
      });

      testFakeAsync('should update existing query defaults', (time) async {
        final key = queryKey();
        queryClient.setQueryDefaults(
          key,
          QueryDefaults(queryFn: (_) => 'data'),
        );
        queryClient.setQueryDefaults(
          key,
          const QueryDefaults(retry: RetryPolicy.never),
        );
        expect(queryClient.getQueryDefaults(key)?.retry, RetryPolicy.never);
      });

      testFakeAsync('should merge defaultOptions', (time) async {
        final key = queryKey();

        queryClient.setQueryDefaults(
          key.append(<Object?>['todo']),
          const QueryDefaults(retry: RetryPolicy.never),
        );
        queryClient.setQueryDefaults(
          key.append(<Object?>['todo']).append(<Object?>['detail']),
          QueryDefaults(staleTime: StaleTime.duration(ms(5000))),
        );

        final defaults = queryClient.getQueryDefaults(
            key.append(<Object?>['todo']).append(<Object?>['detail']));
        expect(defaults?.retry, RetryPolicy.never);
        expect(defaults?.staleTime, StaleTime.duration(ms(5000)));
      });
    });

    group('setQueryData', () {
      testFakeAsync('should not crash if query could not be found',
          (time) async {
        final key = queryKey();
        expect(
          () => queryClient.updateQueryData<Map<String, Object?>>(
            key.append(<Object?>[
              <String, Object?>{'userId': 1}
            ]),
            (previous) => <String, Object?>{...?previous, 'name': 'James'},
          ),
          returnsNormally,
        );
      });

      testFakeAsync('should not crash when variable is null', (time) async {
        final key = queryKey();
        final nullKey = key.append(<Object?>[
          <String, Object?>{'userId': null}
        ]);
        queryClient.setQueryData<String>(nullKey, 'Old Data');
        expect(
          () => queryClient.setQueryData<String>(nullKey, 'New Data'),
          returnsNormally,
        );
      });

      testFakeAsync('should create a new query if query was not found 1',
          (time) async {
        final key = queryKey();
        queryClient.setQueryData<String>(key, 'bar');
        expect(queryClient.getQueryData<String>(key), 'bar');
      });

      testFakeAsync('should create a new query if query was not found 2',
          (time) async {
        final key = queryKey();
        queryClient.setQueryData<String>(key, 'qux');
        expect(queryClient.getQueryData<String>(key), 'qux');
      });

      testFakeAsync(
          'should not create a new query if query was not found and updater '
          'returns undefined', (time) async {
        final key = queryKey();
        expect(queryCache.find(QueryFilters(queryKey: key)), isNull);
        queryClient.updateQueryData<String>(key, (_) => null);
        expect(queryCache.find(QueryFilters(queryKey: key)), isNull);
      });

      testFakeAsync('should not update query data if updater returns undefined',
          (time) async {
        final key = queryKey();
        queryClient.setQueryData<String>(key, 'qux');
        queryClient.updateQueryData<String>(key, (_) => null);
        expect(queryClient.getQueryData<String>(key), 'qux');
      });

      testFakeAsync('should accept an update function', (time) async {
        final key = queryKey();

        var called = false;

        queryClient.setQueryData<String>(key, 'test data');
        queryClient.updateQueryData<String>(key, (oldData) {
          called = true;
          return 'new data + $oldData';
        });

        expect(called, isTrue);
        expect(queryCache.find(QueryFilters(queryKey: key))!.state.data,
            'new data + test data');
      });

      testFakeAsync(
          'should set the new data without comparison if structuralSharing is '
          'not set', (time) async {
        final key = queryKey();

        final oldData = <String, bool>{'value': true};
        final newData = <String, bool>{'value': true};
        queryClient.setQueryData<Map<String, bool>>(key, oldData);
        queryClient.setQueryData<Map<String, bool>>(key, newData);

        expect(queryCache.find(QueryFilters(queryKey: key))!.state.data,
            same(newData));
      });

      testFakeAsync(
          'should apply a custom structuralSharing function when provided',
          (time) async {
        final key = queryKey();

        queryClient.setDefaultOptions(
          DefaultOptions(
            queries: QueryDefaults(
              structuralSharing: (Object? previous, Object? next) {
                if (previous == null) {
                  return next;
                }
                return (previous as Map<String, DateTime>)['value'] ==
                        (next as Map<String, DateTime>)['value']
                    ? previous
                    : next;
              },
            ),
          ),
        );

        final oldData = <String, DateTime>{'value': DateTime(2022, 7, 19)};
        final newData = <String, DateTime>{'value': DateTime(2022, 7, 19)};
        queryClient.setQueryData<Map<String, DateTime>>(key, oldData);
        queryClient.setQueryData<Map<String, DateTime>>(key, newData);

        expect(queryCache.find(QueryFilters(queryKey: key))!.state.data,
            same(oldData));

        final distinctData = <String, DateTime>{
          'value': DateTime(2021, 12, 25)
        };
        queryClient.setQueryData<Map<String, DateTime>>(key, distinctData);

        expect(queryCache.find(QueryFilters(queryKey: key))!.state.data,
            same(distinctData));
      });

      testFakeAsync('should not set isFetching to false', (time) async {
        final key = queryKey();
        queryClient
            .query<int>(QueryOptions<int>(
              queryKey: key,
              queryFn: (_) async {
                await sleep(ms(10));
                return 23;
              },
            ))
            .ignore();
        var state = queryClient.getQueryState<int>(key)!;
        expect(state.hasData, isFalse);
        expect(state.fetchStatus, FetchStatus.fetching);
        queryClient.setQueryData<int>(key, 42);
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
      testFakeAsync('should update all existing, matching queries',
          (time) async {
        queryClient.setQueryData<int>(QueryKey(<Object?>['key', 1]), 1);
        queryClient.setQueryData<int>(QueryKey(<Object?>['key', 2]), 2);

        final result = queryClient.updateQueriesData<int>(
          QueryFilters(queryKey: QueryKey(<Object?>['key'])),
          (old) => old == null ? null : old + 5,
        );

        expect(result, [
          (QueryKey(<Object?>['key', 1]), 6),
          (QueryKey(<Object?>['key', 2]), 7),
        ]);
        expect(queryClient.getQueryData<int>(QueryKey(<Object?>['key', 1])), 6);
        expect(queryClient.getQueryData<int>(QueryKey(<Object?>['key', 2])), 7);
      });

      testFakeAsync('should accept queryFilters', (time) async {
        queryClient.setQueryData<int>(QueryKey(<Object?>['key', 1]), 1);
        queryClient.setQueryData<int>(QueryKey(<Object?>['key', 2]), 2);
        final query1 = queryCache
            .find(QueryFilters(queryKey: QueryKey(<Object?>['key', 1])))!;

        final result = queryClient.updateQueriesData<int>(
          QueryFilters(predicate: (query) => identical(query, query1)),
          (old) => old! + 5,
        );

        expect(result, [
          (QueryKey(<Object?>['key', 1]), 6),
        ]);
        expect(queryClient.getQueryData<int>(QueryKey(<Object?>['key', 1])), 6);
        expect(queryClient.getQueryData<int>(QueryKey(<Object?>['key', 2])), 2);
      });

      testFakeAsync('should not update non existing queries', (time) async {
        final result = queryClient.updateQueriesData<String>(
          QueryFilters(queryKey: QueryKey(<Object?>['key'])),
          (_) => 'data',
        );

        expect(result, isEmpty);
        expect(queryClient.getQueryData<String>(QueryKey(<Object?>['key'])),
            isNull);
      });
    });

    group('isFetching', () {
      testFakeAsync('should return length of fetching queries', (time) async {
        expect(queryClient.isFetching(), 0);
        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: queryKey(),
              queryFn: (_) async {
                await sleep(ms(10));
                return 'data';
              },
            ))
            .ignore();
        expect(queryClient.isFetching(), 1);
        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: queryKey(),
              queryFn: (_) async {
                await sleep(ms(5));
                return 'data';
              },
            ))
            .ignore();
        expect(queryClient.isFetching(), 2);
        await time.advance(ms(5));
        expect(queryClient.isFetching(), 1);
        await time.advance(ms(5));
        expect(queryClient.isFetching(), 0);
      });
    });

    group('isMutating', () {
      testFakeAsync('should return length of mutating', (time) async {
        expect(queryClient.isMutating(), 0);
        MutationObserver<String, void, void>(
          queryClient,
          MutationOptions<String, void, void>(
            mutationFn: (_) async {
              await sleep(ms(10));
              return 'data';
            },
          ),
        ).mutate(null);
        expect(queryClient.isMutating(), 1);
        MutationObserver<String, void, void>(
          queryClient,
          MutationOptions<String, void, void>(
            mutationFn: (_) async {
              await sleep(ms(5));
              return 'data';
            },
          ),
        ).mutate(null);
        expect(queryClient.isMutating(), 2);
        await time.advance(ms(5));
        expect(queryClient.isMutating(), 1);
        await time.advance(ms(5));
        expect(queryClient.isMutating(), 0);
      });
    });

    group('getQueryData', () {
      testFakeAsync('should return the query data if the query is found',
          (time) async {
        final key = queryKey();
        queryClient.setQueryData<String>(key.append(<Object?>['id']), 'bar');
        expect(queryClient.getQueryData<String>(key.append(<Object?>['id'])),
            'bar');
      });

      testFakeAsync('should return undefined if the query is not found',
          (time) async {
        final key = queryKey();
        expect(queryClient.getQueryData<String>(key), isNull);
      });

      testFakeAsync('should match exact by default', (time) async {
        final key = queryKey();
        queryClient.setQueryData<String>(key.append(<Object?>['id']), 'bar');
        expect(queryClient.getQueryData<String>(key), isNull);
      });
    });

    group('query with static staleTime', () {
      testFakeAsync('should return the cached query data if the query is found',
          (time) async {
        final key = queryKey();
        var calls = 0;

        queryClient.setQueryData<String>(key.append(<Object?>['id']), 'bar');

        expect(
          await queryClient.query<String>(QueryOptions<String>(
            queryKey: key.append(<Object?>['id']),
            queryFn: (_) {
              calls++;
              return Future<String>.value('data');
            },
            staleTime: StaleTime.static,
          )),
          'bar',
        );
        expect(calls, 0);
      });

      testFakeAsync(
          'should call queryFn and return its results if the query is not found',
          (time) async {
        final key = queryKey();
        var calls = 0;

        expect(
          await queryClient.query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) {
              calls++;
              return Future<String>.value('data');
            },
            staleTime: StaleTime.static,
          )),
          'data',
        );
        expect(calls, 1);
      });

      testFakeAsync('should not fetch when initialData is provided',
          (time) async {
        final key = queryKey();
        var calls = 0;

        expect(
          await queryClient.query<String>(QueryOptions<String>(
            queryKey: key.append(<Object?>['id']),
            queryFn: (_) {
              calls++;
              return Future<String>.value('data');
            },
            staleTime: StaleTime.static,
            initialData: const InitialData<String>.value('initial'),
          )),
          'initial',
        );

        expect(calls, 0);
      });

      testFakeAsync(
          'supports manual background revalidation via a second query call',
          (time) async {
        final key = queryKey();
        var value = 'data-1';
        var calls = 0;
        Future<String> queryFn(QueryFunctionContext _) {
          calls++;
          return Future<String>.value(value);
        }

        expect(
          await queryClient.query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: queryFn,
            staleTime: StaleTime.static,
          )),
          'data-1',
        );
        expect(calls, 1);

        value = 'data-2';
        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: key,
              queryFn: queryFn,
              staleTime: StaleTime.zero,
            ))
            .ignore();

        await time.flushMicrotasks();

        expect(calls, 2);
        expect(queryClient.getQueryData<String>(key), 'data-2');
      });
    });

    group('getQueriesData', () {
      testFakeAsync('should return the query data for all matched queries',
          (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        queryClient.setQueryData<int>(key1.append(<Object?>[1]), 1);
        queryClient.setQueryData<int>(key1.append(<Object?>[2]), 2);
        queryClient.setQueryData<int>(key2.append(<Object?>[2]), 2);
        expect(queryClient.getQueriesData<int>(QueryFilters(queryKey: key1)), [
          (key1.append(<Object?>[1]), 1),
          (key1.append(<Object?>[2]), 2),
        ]);
      });

      testFakeAsync('should return empty array if queries are not found',
          (time) async {
        final key = queryKey();
        expect(queryClient.getQueriesData<int>(QueryFilters(queryKey: key)),
            isEmpty);
      });

      testFakeAsync('should accept query filters', (time) async {
        queryClient.setQueryData<int>(QueryKey(<Object?>['key', 1]), 1);
        queryClient.setQueryData<int>(QueryKey(<Object?>['key', 2]), 2);
        final query1 = queryCache
            .find(QueryFilters(queryKey: QueryKey(<Object?>['key', 1])))!;

        final result = queryClient.getQueriesData<int>(
          QueryFilters(predicate: (query) => identical(query, query1)),
        );

        expect(result, [
          (QueryKey(<Object?>['key', 1]), 1),
        ]);
      });
    });

    group('query', () {
      // https://github.com/tannerlinsley/react-query/issues/652
      testFakeAsync('should not retry by default', (time) async {
        final key = queryKey();

        await expectLater(
          queryClient.query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) => throw Exception('error'),
          )),
          throwsA(isA<Exception>()),
        );
      });

      testFakeAsync('should return the cached data on cache hit', (time) async {
        final key = queryKey();

        Future<String> fetchFn(QueryFunctionContext _) async => 'data';
        final first = await queryClient.query<String>(
            QueryOptions<String>(queryKey: key, queryFn: fetchFn));
        final second = await queryClient.query<String>(
            QueryOptions<String>(queryKey: key, queryFn: fetchFn));

        expect(second, same(first));
      });

      testFakeAsync('should fetch when disabled', (time) async {
        final key = queryKey();
        var calls = 0;

        expect(
          await queryClient.query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) {
              calls++;
              return Future<String>.value('data');
            },
            // `enabled` is not part of the imperative contract and is ignored.
            enabled: Enabled.no,
          )),
          'data',
        );

        expect(calls, 1);
      });

      testFakeAsync('should fetch when disabled by callback', (time) async {
        final key = queryKey();
        var calls = 0;

        expect(
          await queryClient.query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) {
              calls++;
              return Future<String>.value('data');
            },
            enabled: Enabled.when((_) => false),
          )),
          'data',
        );

        expect(calls, 1);
      });

      testFakeAsync(
          'should fetch instead of returning initialData when disabled',
          (time) async {
        var calls = 0;

        expect(
          await queryClient.query<String>(QueryOptions<String>(
            queryKey: queryKey(),
            queryFn: (_) {
              calls++;
              return Future<String>.value('fetched-data');
            },
            enabled: Enabled.no,
            initialData: const InitialData<String>.value('initial-data'),
          )),
          'fetched-data',
        );

        expect(calls, 1);
      });

      testFakeAsync('should fetch when enabled callback returns false',
          (time) async {
        final key = queryKey();
        var calls = 0;

        queryClient.setQueryData<String>(key, 'cached-data');

        expect(
          await queryClient.query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) {
              calls++;
              return Future<String>.value('fetched-data');
            },
            enabled: Enabled.when((_) => false),
          )),
          'fetched-data',
        );
        expect(calls, 1);
      });

      testFakeAsync(
          'should fetch when enabled callback returns true and cache is stale',
          (time) async {
        final key = queryKey();

        queryClient.setQueryData<String>(key, 'old-data');

        await time.advance(ms(1));

        var calls = 0;

        expect(
          await queryClient.query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) {
              calls++;
              return Future<String>.value('new-data');
            },
            enabled: Enabled.when((_) => true),
            staleTime: StaleTime.zero,
          )),
          'new-data',
        );
        expect(calls, 1);
      });

      testFakeAsync(
          'should read from cache with static staleTime even if invalidated',
          (time) async {
        final key = queryKey();
        var calls = 0;

        Future<Map<String, String>> fetchFn(QueryFunctionContext _) {
          calls++;
          return Future<Map<String, String>>.value(
              <String, String>{'data': 'data'});
        }

        final first = await queryClient.query<Map<String, String>>(
          QueryOptions<Map<String, String>>(
            queryKey: key,
            queryFn: fetchFn,
            staleTime: StaleTime.static,
          ),
        );

        expect(first['data'], 'data');
        expect(calls, 1);

        await queryClient.invalidateQueries(
          filters: QueryFilters(queryKey: key),
          refetchType: RefetchType.none,
        );

        final second = await queryClient.query<Map<String, String>>(
          QueryOptions<Map<String, String>>(
            queryKey: key,
            queryFn: fetchFn,
            staleTime: StaleTime.static,
          ),
        );

        expect(calls, 1);
        expect(second, same(first));
      });

      testFakeAsync(
          'should be able to fetch when garbage collection time is set to 0 and '
          'then be removed', (time) async {
        final key1 = queryKey();
        final promise = queryClient.query<int>(QueryOptions<int>(
          queryKey: key1,
          queryFn: (_) async {
            await sleep(ms(10));
            return 1;
          },
          gcTime: const GcTime.duration(Duration.zero),
        ));
        await time.advance(ms(10));
        expect(await promise, 1);
        await time.advance(ms(1));
        expect(queryClient.getQueryData<int>(key1), isNull);
      });

      testFakeAsync(
          'should keep a query in cache if garbage collection time is Infinity',
          (time) async {
        final key1 = queryKey();
        final promise = queryClient.query<int>(QueryOptions<int>(
          queryKey: key1,
          queryFn: (_) async {
            await sleep(ms(10));
            return 1;
          },
          gcTime: GcTime.never,
        ));
        await time.advance(ms(10));
        final result2 = queryClient.getQueryData<int>(key1);
        expect(await promise, 1);
        expect(result2, 1);
      });

      testFakeAsync('should not force fetch', (time) async {
        final key = queryKey();

        queryClient.setQueryData<String>(key, 'og');
        final first = await queryClient.query<String>(QueryOptions<String>(
          queryKey: key,
          queryFn: (_) async => 'new',
          initialData: const InitialData<String>.value('initial'),
          staleTime: StaleTime.duration(ms(100)),
        ));
        expect(first, 'og');
      });

      testFakeAsync(
          'should only fetch if the data is older then the given stale time',
          (time) async {
        final key = queryKey();

        var count = 0;
        int queryFn(QueryFunctionContext _) => ++count;

        queryClient.setQueryData<int>(key, count);
        expect(
          await queryClient.query<int>(QueryOptions<int>(
            queryKey: key,
            queryFn: queryFn,
            staleTime: StaleTime.duration(ms(100)),
          )),
          0,
        );
        await time.advance(ms(10));
        expect(
          await queryClient.query<int>(QueryOptions<int>(
            queryKey: key,
            queryFn: queryFn,
            staleTime: StaleTime.duration(ms(10)),
          )),
          1,
        );
        expect(
          await queryClient.query<int>(QueryOptions<int>(
            queryKey: key,
            queryFn: queryFn,
            staleTime: StaleTime.duration(ms(10)),
          )),
          1,
        );
        await time.advance(ms(10));
        expect(
          await queryClient.query<int>(QueryOptions<int>(
            queryKey: key,
            queryFn: queryFn,
            staleTime: StaleTime.duration(ms(10)),
          )),
          2,
        );
      });

      testFakeAsync('should evaluate staleTime when provided as a function',
          (time) async {
        final key = queryKey();
        var staleTimeCalls = 0;

        queryClient.setQueryData<String>(key, 'old-data');

        await time.advance(ms(1));

        var calls = 0;

        expect(
          await queryClient.query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) {
              calls++;
              return Future<String>.value('new-data');
            },
            staleTime: StaleTime.dynamic((_) {
              staleTimeCalls++;
              return StaleTime.zero;
            }),
          )),
          'new-data',
        );
        expect(calls, 1);
        expect(staleTimeCalls, 1);
      });

      testFakeAsync('should allow new meta', (time) async {
        final key = queryKey();

        final first = await queryClient.query<Object?>(QueryOptions<Object?>(
          queryKey: key,
          queryFn: (context) => Future<Object?>.value(context.meta),
          meta: const <String, bool>{'foo': true},
        ));
        expect(first, const <String, bool>{'foo': true});

        final second = await queryClient.query<Object?>(QueryOptions<Object?>(
          queryKey: key,
          queryFn: (context) => Future<Object?>.value(context.meta),
          meta: const <String, bool>{'foo': false},
        ));
        expect(second, const <String, bool>{'foo': false});
      });

      testFakeAsync('should fetch when enabled is true and cache is stale',
          (time) async {
        final key = queryKey();

        queryClient.setQueryData<String>(key, 'old-data');

        await time.advance(ms(1));

        var calls = 0;

        expect(
          await queryClient.query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) {
              calls++;
              return Future<String>.value('new-data');
            },
            enabled: Enabled.yes,
            staleTime: StaleTime.zero,
          )),
          'new-data',
        );
        expect(calls, 1);
      });

      testFakeAsync('should propagate errors', (time) async {
        final key = queryKey();

        await expectLater(
          queryClient.query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) => throw Exception('error'),
          )),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('query used for prefetching', () {
      testFakeAsync('should resolve to nothing when the error is ignored',
          (time) async {
        final key = queryKey();

        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: key,
              queryFn: (_) => throw Exception('error'),
              retry: RetryPolicy.never,
            ))
            .ignore();

        await time.flushMicrotasks();

        expect(queryClient.getQueryData<String>(key), isNull);
        expect(queryCache.find(QueryFilters(queryKey: key))?.state.status,
            QueryStatus.error);
      });

      testFakeAsync('should be garbage collected after gcTime if unused',
          (time) async {
        final key = queryKey();

        await queryClient.query<String>(QueryOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
          gcTime: const GcTime.duration(Duration(milliseconds: 10)),
        ));
        expect(queryCache.find(QueryFilters(queryKey: key)), isNotNull);
        await time.advance(ms(15));
        expect(queryCache.find(QueryFilters(queryKey: key)), isNull);
      });
    });

    group('removeQueries', () {
      testFakeAsync('should not crash when exact is provided', (time) async {
        final key = queryKey();

        // check the query was added to the cache
        await queryClient.query<String>(QueryOptions<String>(
          queryKey: key,
          queryFn: (_) async => 'data',
        ));
        expect(
            queryCache.find(QueryFilters(queryKey: key))?.state.data, 'data');

        // check the error doesn't occur
        expect(
          () => queryClient
              .removeQueries(QueryFilters(queryKey: key, exact: true)),
          returnsNormally,
        );

        // check query was successfully removed
        expect(queryCache.find(QueryFilters(queryKey: key)), isNull);
      });
    });

    group('cancelQueries', () {
      testFakeAsync('should revert queries to their previous state',
          (time) async {
        final key1 = queryKey();
        queryClient.setQueryData<String>(key1, 'data');

        final pending = queryClient.query<String>(QueryOptions<String>(
          queryKey: key1,
          queryFn: (_) async {
            await sleep(ms(1000));
            return 'data2';
          },
        ));

        await time.advance(ms(10));

        await queryClient.cancelQueries();

        // with previous data present, an imperative fetch resolves to that data
        // after the cancel
        expect(await pending, 'data');

        final state1 = queryClient.getQueryState<String>(key1)!;
        expect(state1.data, 'data');
        expect(state1.status, QueryStatus.success);
      });

      testFakeAsync('should not revert if revert option is set to false',
          (time) async {
        final key1 = queryKey();
        await queryClient.query<String>(QueryOptions<String>(
          queryKey: key1,
          queryFn: (_) => 'data',
        ));
        queryClient
            .query<String>(QueryOptions<String>(
              queryKey: key1,
              queryFn: (_) async {
                await sleep(ms(1000));
                return 'data2';
              },
            ))
            .ignore();
        await time.advance(ms(10));
        await queryClient.cancelQueries(
          filters: QueryFilters(queryKey: key1),
          revert: false,
        );
        expect(
            queryClient.getQueryState<String>(key1)?.status, QueryStatus.error);
      });

      testFakeAsync(
          'should throw CancelledError for imperative methods when initial fetch '
          'is cancelled', (time) async {
        final key = queryKey();

        final promise = queryClient.query<int>(QueryOptions<int>(
          queryKey: key,
          queryFn: (_) async {
            await sleep(ms(50));
            return 25;
          },
        ));
        final caught =
            promise.then<Object?>((_) => null, onError: (Object e) => e);

        await time.advance(ms(10));

        await queryClient.cancelQueries(filters: QueryFilters(queryKey: key));

        // we have to reject here because we cannot resolve with "no data"; the
        // alternative would be a future that never completes
        expect(await caught, isA<CancelledError>());

        // however, the query was correctly reverted to its pending state
        final state = queryClient.getQueryState<int>(key)!;
        expect(state.status, QueryStatus.pending);
        expect(state.fetchStatus, FetchStatus.idle);
        expect(state.hasData, isFalse);
        expect(state.error, isNull);
      });
    });

    group('refetchQueries', () {
      testFakeAsync('should not refetch if all observers are disabled',
          (time) async {
        final key = queryKey();
        var calls = 0;
        String queryFn(QueryFunctionContext _) {
          calls++;
          return 'data';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key, queryFn: queryFn));
        final observer1 = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: queryFn,
            enabled: Enabled.no,
          ),
        );
        observer1.subscribe((_) {});
        await queryClient.refetchQueries();
        observer1.destroy();
        expect(calls, 1);
      });

      testFakeAsync('should refetch if at least one observer is enabled',
          (time) async {
        final key = queryKey();
        var calls = 0;
        String queryFn(QueryFunctionContext _) {
          calls++;
          return 'data';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key, queryFn: queryFn));
        final observer1 = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: queryFn,
            enabled: Enabled.no,
          ),
        );
        final observer2 = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: queryFn,
            refetchOnMount: RefetchOn.never,
          ),
        );
        observer1.subscribe((_) {});
        observer2.subscribe((_) {});
        await queryClient.refetchQueries();
        observer1.destroy();
        observer2.destroy();
        expect(calls, 2);
      });

      testFakeAsync('should refetch all queries when no arguments are given',
          (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key2, queryFn: queryFn2));
        final observer1 = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            queryFn: queryFn1,
            staleTime: StaleTime.infinite,
            initialData: const InitialData<String>.value('initial'),
          ),
        );
        final observer2 = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            queryFn: queryFn1,
            staleTime: StaleTime.infinite,
            initialData: const InitialData<String>.value('initial'),
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

      testFakeAsync('should be able to refetch all fresh queries',
          (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key2, queryFn: queryFn2));
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            queryFn: queryFn1,
            staleTime: StaleTime.infinite,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        await queryClient.refetchQueries(
          filters: const QueryFilters(
            type: QueryTypeFilter.active,
            stale: false,
          ),
        );
        unsubscribe();
        expect(calls1, 2);
        expect(calls2, 1);
      });

      testFakeAsync('should be able to refetch all stale queries',
          (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key2, queryFn: queryFn2));
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
              queryKey: key1, queryFn: queryFn1),
        );
        final unsubscribe = observer.subscribe((_) {});
        queryClient
            .invalidateQueries(filters: QueryFilters(queryKey: key1))
            .ignore();
        await queryClient.refetchQueries(
            filters: const QueryFilters(stale: true));
        unsubscribe();
        // query(), observer mount, invalidation (cancels the observer's mount
        // fetch) and refetch
        expect(calls1, 4);
        expect(calls2, 1);
      });

      testFakeAsync('should be able to refetch all stale and active queries',
          (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key2, queryFn: queryFn2));
        queryClient
            .invalidateQueries(filters: QueryFilters(queryKey: key1))
            .ignore();
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
              queryKey: key1, queryFn: queryFn1),
        );
        final unsubscribe = observer.subscribe((_) {});
        await queryClient.refetchQueries(
          filters: const QueryFilters(
            type: QueryTypeFilter.active,
            stale: true,
          ),
          cancelRefetch: false,
        );
        unsubscribe();
        expect(calls1, 2);
        expect(calls2, 1);
      });

      testFakeAsync(
          'should be able to refetch all active and inactive queries '
          '(queryClient.refetchQueries()', (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key2, queryFn: queryFn2));
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            queryFn: queryFn1,
            staleTime: StaleTime.infinite,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        await queryClient.refetchQueries();
        unsubscribe();
        expect(calls1, 2);
        expect(calls2, 2);
      });

      testFakeAsync(
          'should be able to refetch all active and inactive queries '
          '(queryClient.refetchQueries({ type: "all" }))', (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key2, queryFn: queryFn2));
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            queryFn: queryFn1,
            staleTime: StaleTime.infinite,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        await queryClient.refetchQueries(
            filters: const QueryFilters(type: QueryTypeFilter.all));
        unsubscribe();
        expect(calls1, 2);
        expect(calls2, 2);
      });

      testFakeAsync('should be able to refetch only active queries',
          (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key2, queryFn: queryFn2));
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            queryFn: queryFn1,
            staleTime: StaleTime.infinite,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        await queryClient.refetchQueries(
            filters: const QueryFilters(type: QueryTypeFilter.active));
        unsubscribe();
        expect(calls1, 2);
        expect(calls2, 1);
      });

      testFakeAsync('should be able to refetch only inactive queries',
          (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key2, queryFn: queryFn2));
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            queryFn: queryFn1,
            staleTime: StaleTime.infinite,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        await queryClient.refetchQueries(
            filters: const QueryFilters(type: QueryTypeFilter.inactive));
        unsubscribe();
        expect(calls1, 1);
        expect(calls2, 2);
      });

      testFakeAsync('should resolve Promise immediately if query is paused',
          (time) async {
        final key1 = queryKey();
        var calls1 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        queryClient.onlineManager.setOnline(false);

        await queryClient.refetchQueries(filters: QueryFilters(queryKey: key1));

        // reaching this point means the future resolved rather than hanging on
        // a fetch that cannot run
        expect(calls1, 1);
        queryClient.onlineManager.setOnline(true);
      });

      testFakeAsync(
          'should refetch if query we are offline but query networkMode is always',
          (time) async {
        final key1 = queryKey();
        queryClient.setQueryDefaults(
          key1,
          const QueryDefaults(networkMode: NetworkMode.always),
        );
        var calls1 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        queryClient.onlineManager.setOnline(false);

        await queryClient.refetchQueries(filters: QueryFilters(queryKey: key1));

        // initial fetch + refetch (even though we are offline)
        expect(calls1, 2);
        queryClient.onlineManager.setOnline(true);
      });

      testFakeAsync('should not refetch static queries', (time) async {
        final key = queryKey();
        var calls = 0;
        String queryFn(QueryFunctionContext _) {
          calls++;
          return 'data1';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key, queryFn: queryFn));

        expect(calls, 1);

        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: queryFn,
            staleTime: StaleTime.static,
          ),
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
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key2, queryFn: queryFn2));
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            queryFn: queryFn1,
            staleTime: StaleTime.infinite,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        queryClient
            .invalidateQueries(filters: QueryFilters(queryKey: key1))
            .ignore();
        unsubscribe();
        expect(calls1, 2);
        expect(calls2, 1);
      });

      testFakeAsync('should not refetch inactive queries by default',
          (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key2, queryFn: queryFn2));
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            enabled: Enabled.no,
            staleTime: StaleTime.infinite,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        queryClient
            .invalidateQueries(filters: QueryFilters(queryKey: key1))
            .ignore();
        unsubscribe();
        expect(calls1, 1);
        expect(calls2, 1);
      });

      testFakeAsync(
          'should not refetch active queries when "refetch" is "none"',
          (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key2, queryFn: queryFn2));
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            queryFn: queryFn1,
            staleTime: StaleTime.infinite,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        queryClient
            .invalidateQueries(
              filters: QueryFilters(queryKey: key1),
              refetchType: RefetchType.none,
            )
            .ignore();
        unsubscribe();
        expect(calls1, 1);
        expect(calls2, 1);
      });

      testFakeAsync(
          'should refetch inactive queries when "refetch" is "inactive"',
          (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key2, queryFn: queryFn2));
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            queryFn: queryFn1,
            staleTime: StaleTime.infinite,
            refetchOnMount: RefetchOn.never,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        unsubscribe();

        await queryClient.invalidateQueries(
          filters: QueryFilters(queryKey: key1),
          refetchType: RefetchType.inactive,
        );
        expect(calls1, 2);
        expect(calls2, 1);
      });

      testFakeAsync(
          'should refetch active and inactive queries when "refetch" is "all"',
          (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key1, queryFn: queryFn1));
        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key2, queryFn: queryFn2));
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            queryFn: queryFn1,
            staleTime: StaleTime.infinite,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        queryClient.invalidateQueries(refetchType: RefetchType.all).ignore();
        unsubscribe();
        expect(calls1, 2);
        expect(calls2, 2);
      });

      testFakeAsync(
          'should not refetch disabled inactive queries even if "refetchType" is "all"',
          (time) async {
        var calls = 0;
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: queryKey(),
            queryFn: (_) {
              calls++;
              return 'data1';
            },
            staleTime: StaleTime.infinite,
            enabled: Enabled.no,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        unsubscribe();
        await queryClient.invalidateQueries(refetchType: RefetchType.all);
        expect(calls, 0);
      });

      testFakeAsync(
          'should cancel ongoing fetches if cancelRefetch option is set (default value)',
          (time) async {
        final key = queryKey();
        var cancels = 0;
        var fetchCount = 0;
        final observer = queryClient.observe<int, int>(
          QueryObserverOptions<int, int>(
            queryKey: key,
            queryFn: (context) async {
              fetchCount++;
              context.signal.onCancel(() => cancels++);
              await sleep(ms(10));
              return 5;
            },
            initialData: const InitialData<int>.value(1),
          ),
        );
        observer.subscribe((_) {});

        queryClient.refetchQueries().ignore();
        await time.advance(ms(10));
        observer.destroy();
        expect(cancels, 1);
        expect(fetchCount, 2);
      });

      testFakeAsync(
          'should not cancel ongoing fetches if cancelRefetch option is set to false',
          (time) async {
        final key = queryKey();
        var cancels = 0;
        var fetchCount = 0;
        final observer = queryClient.observe<int, int>(
          QueryObserverOptions<int, int>(
            queryKey: key,
            queryFn: (context) async {
              fetchCount++;
              context.signal.onCancel(() => cancels++);
              await sleep(ms(10));
              return 5;
            },
            initialData: const InitialData<int>.value(1),
          ),
        );
        observer.subscribe((_) {});

        queryClient.refetchQueries(cancelRefetch: false).ignore();
        await time.advance(ms(10));
        observer.destroy();
        expect(cancels, 0);
        expect(fetchCount, 1);
      });

      testFakeAsync('should not refetch static queries after invalidation',
          (time) async {
        final key = queryKey();
        var calls = 0;
        String queryFn(QueryFunctionContext _) {
          calls++;
          return 'data1';
        }

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key, queryFn: queryFn));

        expect(calls, 1);

        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: queryFn,
            staleTime: StaleTime.static,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        await queryClient.invalidateQueries();

        expect(calls, 1);
        unsubscribe();
      });
    });

    group('resetQueries', () {
      testFakeAsync('should notify listeners when a query is reset',
          (time) async {
        final key = queryKey();

        final events = <QueryCacheEvent>[];

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key, queryFn: (_) => 'data'));

        queryCache.subscribe(events.add);

        queryClient.resetQueries(filters: QueryFilters(queryKey: key)).ignore();

        final query = queryCache.find(QueryFilters(queryKey: key));
        expect(events.first, isA<QueryUpdated>());
        expect(events.first.query, same(query));
        expect((events.first as QueryUpdated).action,
            isA<QuerySetStateAction<Object?>>());
      });

      testFakeAsync('should reset query', (time) async {
        final key = queryKey();

        await queryClient.query<String>(
            QueryOptions<String>(queryKey: key, queryFn: (_) => 'data'));

        var state = queryClient.getQueryState<String>(key)!;
        expect(state.data, 'data');
        expect(state.status, QueryStatus.success);

        queryClient.resetQueries(filters: QueryFilters(queryKey: key)).ignore();

        state = queryClient.getQueryState<String>(key)!;

        expect(state.hasData, isFalse);
        expect(state.status, QueryStatus.pending);
        expect(state.fetchStatus, FetchStatus.idle);
      });

      testFakeAsync('should reset query data to initial data if set',
          (time) async {
        final key = queryKey();

        await queryClient.query<String>(QueryOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
          initialData: const InitialData<String>.value('initial'),
        ));

        var state = queryClient.getQueryState<String>(key)!;
        expect(state.data, 'data');

        queryClient.resetQueries(filters: QueryFilters(queryKey: key)).ignore();

        state = queryClient.getQueryState<String>(key)!;

        expect(state.data, 'initial');
      });

      testFakeAsync(
          'should refetch queries matched by a state-dependent predicate',
          (time) async {
        final key = queryKey();
        var calls = 0;
        Future<String> queryFn(QueryFunctionContext _) {
          calls++;
          if (calls == 1) {
            return Future<String>.error(Exception('error'));
          }
          return Future<String>.value('data');
        }

        await expectLater(
          queryClient.query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: queryFn,
            retry: RetryPolicy.never,
          )),
          throwsA(isA<Exception>()),
        );

        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: queryFn,
            retry: RetryPolicy.never,
            retryOnMount: false,
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
      });

      testFakeAsync('should refetch all active queries', (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        var calls1 = 0;
        var calls2 = 0;
        String queryFn1(QueryFunctionContext _) {
          calls1++;
          return 'data1';
        }

        String queryFn2(QueryFunctionContext _) {
          calls2++;
          return 'data2';
        }

        final observer1 = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key1,
            queryFn: queryFn1,
            enabled: Enabled.yes,
          ),
        );
        final observer2 = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key2,
            queryFn: queryFn2,
            enabled: Enabled.no,
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

    group('setMutationDefaults', () {
      testFakeAsync('should update existing mutation defaults', (time) async {
        final key = queryKey();
        queryClient.setMutationDefaults(
          key,
          MutationDefaults(mutationFn: (_) async => 'data'),
        );
        queryClient.setMutationDefaults(
          key,
          const MutationDefaults(retry: RetryPolicy.never),
        );
        expect(queryClient.getMutationDefaults(key)?.retry, RetryPolicy.never);
      });

      testFakeAsync(
          'should return only matching defaults when multiple mutation defaults '
          'are set', (time) async {
        final key1 = queryKey();
        final key2 = queryKey();
        queryClient.setMutationDefaults(
          key1,
          const MutationDefaults(retry: RetryTimes(1)),
        );
        queryClient.setMutationDefaults(
          key2,
          const MutationDefaults(retry: RetryTimes(2)),
        );

        expect(
            queryClient.getMutationDefaults(key1)?.retry, const RetryTimes(1));
        expect(
            queryClient.getMutationDefaults(key2)?.retry, const RetryTimes(2));
      });
    });

    group('focusManager and onlineManager', () {
      testFakeAsync('should notify queryCache and mutationCache if focused',
          (time) async {
        // Upstream spies on `queryCache.onFocus` and
        // `mutationCache.resumePausedMutations`. There are no spies here, so
        // this asserts the effect the query half actually has; the mutation
        // half is unobservable without a paused mutation, and is covered by the
        // online cases below, which observe a real resumption.
        final client = testClient();
        client.mount();
        var calls = 0;
        final observer = client.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: queryKey(),
            queryFn: (_) {
              calls++;
              return 'data';
            },
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        await time.flushMicrotasks();
        expect(calls, 1);

        client.focusManager.setFocused(false);
        await time.flushMicrotasks();
        expect(calls, 1);

        client.focusManager.setFocused(true);
        await time.flushMicrotasks();
        expect(calls, 2);

        unsubscribe();
        client.unmount();
      });

      testFakeAsync('should notify queryCache and mutationCache if online',
          (time) async {
        final client = testClient();
        client.mount();
        var calls = 0;
        final observer = client.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: queryKey(),
            queryFn: (_) {
              calls++;
              return 'data';
            },
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        await time.flushMicrotasks();
        expect(calls, 1);

        client.onlineManager.setOnline(false);
        await time.flushMicrotasks();
        expect(calls, 1);

        client.onlineManager.setOnline(true);
        await time.flushMicrotasks();
        expect(calls, 2);

        unsubscribe();
        client.unmount();
      });

      testFakeAsync('should resume paused mutations when coming online',
          (time) async {
        queryClient.onlineManager.setOnline(false);

        final observer1 = MutationObserver<int, void, void>(
          queryClient,
          MutationOptions<int, void, void>(
              mutationFn: (_) => Future<int>.value(1)),
        );
        final observer2 = MutationObserver<int, void, void>(
          queryClient,
          MutationOptions<int, void, void>(
              mutationFn: (_) => Future<int>.value(2)),
        );
        observer1.mutate(null);
        observer2.mutate(null);

        expect(observer1.currentResult.isPaused, isTrue);
        expect(observer2.currentResult.isPaused, isTrue);

        queryClient.onlineManager.setOnline(true);

        await time.flushMicrotasks();
        expect(observer1.currentResult.status, MutationStatus.success);
        expect(observer2.currentResult.status, MutationStatus.success);
      });

      testFakeAsync('should resume paused mutations in parallel', (time) async {
        queryClient.onlineManager.setOnline(false);

        final orders = <String>[];

        final observer1 = MutationObserver<int, void, void>(
          queryClient,
          MutationOptions<int, void, void>(
            mutationFn: (_) async {
              orders.add('1start');
              await sleep(ms(50));
              orders.add('1end');
              return 1;
            },
          ),
        );
        final observer2 = MutationObserver<int, void, void>(
          queryClient,
          MutationOptions<int, void, void>(
            mutationFn: (_) async {
              orders.add('2start');
              await sleep(ms(20));
              orders.add('2end');
              return 2;
            },
          ),
        );
        observer1.mutate(null);
        observer2.mutate(null);

        expect(observer1.currentResult.isPaused, isTrue);
        expect(observer2.currentResult.isPaused, isTrue);

        queryClient.onlineManager.setOnline(true);

        await time.advance(ms(50));
        expect(observer1.currentResult.status, MutationStatus.success);
        expect(observer2.currentResult.status, MutationStatus.success);

        expect(orders, <String>['1start', '2start', '2end', '1end']);
      });

      testFakeAsync(
          'should resume paused mutations one after the other when in the same '
          'scope when invoked manually at the same time', (time) async {
        queryClient.onlineManager.setOnline(false);

        final orders = <String>[];

        final observer1 = MutationObserver<int, void, void>(
          queryClient,
          MutationOptions<int, void, void>(
            scope: const MutationScope('scope'),
            mutationFn: (_) async {
              orders.add('1start');
              await sleep(ms(50));
              orders.add('1end');
              return 1;
            },
          ),
        );
        final observer2 = MutationObserver<int, void, void>(
          queryClient,
          MutationOptions<int, void, void>(
            scope: const MutationScope('scope'),
            mutationFn: (_) async {
              orders.add('2start');
              await sleep(ms(20));
              orders.add('2end');
              return 2;
            },
          ),
        );
        observer1.mutate(null);
        observer2.mutate(null);

        expect(observer1.currentResult.isPaused, isTrue);
        expect(observer2.currentResult.isPaused, isTrue);

        queryClient.onlineManager.setOnline(true);
        queryClient.resumePausedMutations().ignore();

        await time.advance(ms(70));
        expect(observer1.currentResult.status, MutationStatus.success);
        expect(observer2.currentResult.status, MutationStatus.success);

        expect(orders, <String>['1start', '1end', '2start', '2end']);
      });

      testFakeAsync(
          'should resumePausedMutations when coming online after having called '
          'resumePausedMutations while offline', (time) async {
        queryClient.onlineManager.setOnline(false);

        final observer = MutationObserver<int, void, void>(
          queryClient,
          MutationOptions<int, void, void>(
              mutationFn: (_) => Future<int>.value(1)),
        );

        observer.mutate(null);

        expect(observer.currentResult.isPaused, isTrue);

        await queryClient.resumePausedMutations();

        // still paused because we are still offline
        expect(observer.currentResult.isPaused, isTrue);

        queryClient.onlineManager.setOnline(true);

        await time.flushMicrotasks();
        expect(observer.currentResult.status, MutationStatus.success);
      });

      testFakeAsync(
          'should notify queryCache after resumePausedMutations has finished when '
          'coming online', (time) async {
        final key = queryKey();

        var count = 0;
        final results = <String>[];

        final queryObserver = queryClient.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: key,
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

        queryClient.onlineManager.setOnline(false);

        final observer = MutationObserver<int, void, void>(
          queryClient,
          MutationOptions<int, void, void>(
            mutationFn: (_) async {
              results.add('mutation1-start');
              await sleep(ms(50));
              results.add('mutation1-end');
              return 1;
            },
          ),
        );

        observer.mutate(null);

        final observer2 = MutationObserver<int, void, void>(
          queryClient,
          MutationOptions<int, void, void>(
            scope: const MutationScope('scope'),
            mutationFn: (_) async {
              results.add('mutation2-start');
              await sleep(ms(50));
              results.add('mutation2-end');
              return 2;
            },
          ),
        );

        observer2.mutate(null);

        final observer3 = MutationObserver<int, void, void>(
          queryClient,
          MutationOptions<int, void, void>(
            scope: const MutationScope('scope'),
            mutationFn: (_) async {
              results.add('mutation3-start');
              await sleep(ms(50));
              results.add('mutation3-end');
              return 3;
            },
          ),
        );

        observer3.mutate(null);

        expect(observer.currentResult.isPaused, isTrue);
        expect(observer2.currentResult.isPaused, isTrue);
        expect(observer3.currentResult.isPaused, isTrue);
        queryClient.onlineManager.setOnline(true);

        await time.advance(ms(110));
        expect(queryClient.getQueryData<String>(key), 'data2');

        // the refetch that coming online triggers happens after the mutations
        // have finished
        expect(results, <String>[
          'data1',
          'mutation1-start',
          'mutation2-start',
          'mutation1-end',
          'mutation2-end',
          'mutation3-start', // 3 starts after 2 because they share a scope
          'mutation3-end',
          'data2',
        ]);

        unsubscribe();
      });

      testFakeAsync(
          'should notify queryCache and mutationCache after multiple mounts and '
          'single unmount', (time) async {
        final client = testClient();
        client.mount();
        client.mount();
        client.unmount();

        var calls = 0;
        final observer = client.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: queryKey(),
            queryFn: (_) {
              calls++;
              return 'data';
            },
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        await time.flushMicrotasks();
        expect(calls, 1);

        client.onlineManager.setOnline(false);
        client.onlineManager.setOnline(true);
        await time.flushMicrotasks();
        expect(calls, 2);

        client.focusManager.setFocused(false);
        client.focusManager.setFocused(true);
        await time.flushMicrotasks();
        expect(calls, 3);

        unsubscribe();
        client.unmount();
      });

      testFakeAsync(
          'should not notify queryCache and mutationCache after multiple '
          'mounts/unmounts', (time) async {
        final client = testClient();
        client.mount();
        client.mount();
        client.unmount();
        client.unmount();

        var calls = 0;
        final observer = client.observe<String, String>(
          QueryObserverOptions<String, String>(
            queryKey: queryKey(),
            queryFn: (_) {
              calls++;
              return 'data';
            },
          ),
        );
        final unsubscribe = observer.subscribe((_) {});
        await time.flushMicrotasks();
        expect(calls, 1);

        client.onlineManager.setOnline(false);
        client.onlineManager.setOnline(true);
        await time.flushMicrotasks();
        expect(calls, 1);

        client.focusManager.setFocused(false);
        client.focusManager.setFocused(true);
        await time.flushMicrotasks();
        expect(calls, 1);

        unsubscribe();
      });
    });

    group('infiniteQuery with static staleTime', () {
      testFakeAsync('should return the cached query data if the query is found',
          (time) async {
        final key = queryKey();
        var calls = 0;

        queryClient.setQueryData<InfiniteData<String, int>>(
          key.append(<Object?>['id']),
          const InfiniteData<String, int>(
            pages: <String>['bar'],
            pageParams: <int>[0],
          ),
        );

        expect(
          await queryClient.infiniteQuery<String, int>(
            InfiniteQueryOptions<String, int>(
              queryKey: key.append(<Object?>['id']),
              pageFn: (_) {
                calls++;
                return Future<String>.value('data');
              },
              staleTime: StaleTime.static,
              initialPageParam: 1,
              getNextPageParam: (_, __, ___, ____) => null,
            ),
          ),
          const InfiniteData<String, int>(
            pages: <String>['bar'],
            pageParams: <int>[0],
          ),
        );
        expect(calls, 0);
      });

      testFakeAsync(
          'should fetch the query and return its results if the query is not found',
          (time) async {
        final key = queryKey();
        var calls = 0;

        expect(
          await queryClient.infiniteQuery<String, int>(
            InfiniteQueryOptions<String, int>(
              queryKey: key.append(<Object?>['id']),
              pageFn: (_) {
                calls++;
                return Future<String>.value('data');
              },
              staleTime: StaleTime.static,
              initialPageParam: 1,
              getNextPageParam: (_, __, ___, ____) => null,
            ),
          ),
          const InfiniteData<String, int>(
            pages: <String>['data'],
            pageParams: <int>[1],
          ),
        );
        expect(calls, 1);
      });
    });

    group('infiniteQuery', () {
      testFakeAsync('should return infinite query data', (time) async {
        final key = queryKey();
        final result = await queryClient.infiniteQuery<int, int>(
          InfiniteQueryOptions<int, int>(
            queryKey: key,
            initialPageParam: 10,
            pageFn: (context) => context.pageParam,
            getNextPageParam: (_, __, ___, ____) => null,
          ),
        );
        final cached = queryClient.getQueryData<InfiniteData<int, int>>(key);

        const expected =
            InfiniteData<int, int>(pages: <int>[10], pageParams: <int>[10]);

        expect(result, expected);
        expect(cached, expected);
      });

      testFakeAsync('should fetch when disabled', (time) async {
        final key = queryKey();
        var calls = 0;

        expect(
          await queryClient.infiniteQuery<int, int>(
            InfiniteQueryOptions<int, int>(
              queryKey: key,
              pageFn: (context) {
                calls++;
                return context.pageParam;
              },
              initialPageParam: 0,
              getNextPageParam: (_, __, ___, ____) => null,
              // `enabled` is not part of the imperative contract.
              enabled: Enabled.no,
            ),
          ),
          const InfiniteData<int, int>(pages: <int>[0], pageParams: <int>[0]),
        );

        expect(calls, 1);
      });

      testFakeAsync(
          'should evaluate staleTime callback and refetch when it returns stale',
          (time) async {
        final key = queryKey();

        queryClient.setQueryData<InfiniteData<String, int>>(
          key,
          const InfiniteData<String, int>(
            pages: <String>['old-page'],
            pageParams: <int>[0],
          ),
        );

        await time.advance(ms(1));

        var calls = 0;
        var staleTimeCalls = 0;

        final result = await queryClient.infiniteQuery<String, int>(
          InfiniteQueryOptions<String, int>(
            queryKey: key,
            pageFn: (context) {
              calls++;
              return Future<String>.value('new-page-${context.pageParam}');
            },
            initialPageParam: 0,
            getNextPageParam: (_, __, ___, ____) => null,
            staleTime: StaleTime.dynamic((_) {
              staleTimeCalls++;
              return StaleTime.zero;
            }),
          ),
        );

        expect(
          result,
          const InfiniteData<String, int>(
            pages: <String>['new-page-0'],
            pageParams: <int>[0],
          ),
        );
        expect(staleTimeCalls, greaterThan(0));
        expect(calls, 1);
      });

      testFakeAsync(
          'should read from cache with static staleTime even if invalidated',
          (time) async {
        final key = queryKey();
        var calls = 0;

        Future<String> pageFn(InfinitePageContext<int> context) {
          calls++;
          return Future<String>.value('fetched-${context.pageParam}');
        }

        final first = await queryClient.infiniteQuery<String, int>(
          InfiniteQueryOptions<String, int>(
            queryKey: key,
            pageFn: pageFn,
            initialPageParam: 0,
            getNextPageParam: (_, __, ___, ____) => null,
            staleTime: StaleTime.static,
          ),
        );

        expect(
          first,
          const InfiniteData<String, int>(
            pages: <String>['fetched-0'],
            pageParams: <int>[0],
          ),
        );
        expect(calls, 1);

        await queryClient.invalidateQueries(
          filters: QueryFilters(queryKey: key),
          refetchType: RefetchType.none,
        );

        final second = await queryClient.infiniteQuery<String, int>(
          InfiniteQueryOptions<String, int>(
            queryKey: key,
            pageFn: pageFn,
            initialPageParam: 0,
            getNextPageParam: (_, __, ___, ____) => null,
            staleTime: StaleTime.static,
          ),
        );

        expect(calls, 1);
        expect(second, same(first));
      });
    });

    group('infiniteQuery used for prefetching', () {
      testFakeAsync('should return infinite query data', (time) async {
        final key = queryKey();

        await queryClient.infiniteQuery<int, int>(
          InfiniteQueryOptions<int, int>(
            queryKey: key,
            pageFn: (context) => context.pageParam,
            initialPageParam: 10,
            getNextPageParam: (_, __, ___, ____) => null,
          ),
        );

        expect(
          queryClient.getQueryData<InfiniteData<int, int>>(key),
          const InfiniteData<int, int>(pages: <int>[10], pageParams: <int>[10]),
        );
      });

      testFakeAsync('should prefetch multiple pages', (time) async {
        final key = queryKey();

        await queryClient.infiniteQuery<String, int>(
          InfiniteQueryOptions<String, int>(
            queryKey: key,
            pageFn: (context) => '${context.pageParam}',
            getNextPageParam: (_, __, lastPageParam, ___) => lastPageParam + 5,
            initialPageParam: 10,
            pages: 3,
          ),
        );

        expect(
          queryClient.getQueryData<InfiniteData<String, int>>(key),
          const InfiniteData<String, int>(
            pages: <String>['10', '15', '20'],
            pageParams: <int>[10, 15, 20],
          ),
        );
      });

      testFakeAsync('should stop prefetching if getNextPageParam returns null',
          (time) async {
        final key = queryKey();
        var calls = 0;

        await queryClient.infiniteQuery<String, int>(
          InfiniteQueryOptions<String, int>(
            queryKey: key,
            pageFn: (context) => '${context.pageParam}',
            getNextPageParam: (_, __, lastPageParam, ___) {
              calls++;
              return lastPageParam >= 20 ? null : lastPageParam + 5;
            },
            initialPageParam: 10,
            pages: 5,
          ),
        );

        expect(
          queryClient.getQueryData<InfiniteData<String, int>>(key),
          const InfiniteData<String, int>(
            pages: <String>['10', '15', '20'],
            pageParams: <int>[10, 15, 20],
          ),
        );

        // this check ensures the fetch loop exits early
        expect(calls, 3);
      });
    });
  });
}
