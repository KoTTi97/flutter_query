/// Port of `query-core/src/__tests__/queryObserver.test.tsx` at upstream
/// `50680b98c`. Omissions and adaptations: `test/PORTING_NOTES.md`.
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// The shape upstream's cases carry through `select`.
typedef Counted = ({int count});

void main() {
  group('queryObserver', () {
    late QueryClient queryClient;

    setUp(() {
      queryClient = testClient();
      queryClient.mount();
    });

    tearDown(() => queryClient.clear());

    testFakeAsync('should trigger a fetch when subscribed', (time) async {
      final key = queryKey();
      var calls = 0;
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            calls++;
            return 'data';
          },
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      unsubscribe();
      expect(calls, 1);
    });

    testFakeAsync(
        'should go through a pending state even when the queryFn returns synchronously',
        (time) async {
      final key = queryKey();
      var calls = 0;
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            calls++;
            return 'data';
          },
        ),
      );
      final unsubscribe = observer.subscribe((_) {});

      // A synchronous return value is still wrapped in a future, so the query
      // goes through a fetching state before it resolves.
      expect(calls, 1);
      expect(observer.currentResult.status, QueryStatus.pending);
      expect(observer.currentResult.fetchStatus, FetchStatus.fetching);
      expect(observer.currentResult.dataOrNull, isNull);

      await time.flushMicrotasks();

      expect(observer.currentResult.status, QueryStatus.success);
      expect(observer.currentResult.fetchStatus, FetchStatus.idle);
      expect(observer.currentResult.dataOrNull, 'data');

      unsubscribe();
    });

    testFakeAsync('should be able to read latest data after subscribing',
        (time) async {
      final key = queryKey();
      queryClient.setQueryData<String>(key, 'data');
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          enabled: Enabled.no,
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      expect(observer.currentResult.status, QueryStatus.success);
      expect(observer.currentResult.dataOrNull, 'data');

      unsubscribe();
    });

    group('enabled is a callback that initially returns false', () {
      late QueryKey key;
      late bool enabled;
      late int count;

      QueryObserver<String, String> makeObserver() =>
          queryClient.observe<String, String>(
            QueryObserverOptions<String>(
              queryKey: key,
              staleTime: StaleTime.infinite,
              enabled: Enabled.when((_) => enabled),
              queryFn: (_) async {
                await sleep(ms(10));
                count++;
                return 'data';
              },
            ),
          );

      setUp(() {
        key = queryKey();
        count = 0;
        enabled = false;
      });

      testFakeAsync('should not fetch on mount', (time) async {
        final observer = makeObserver();
        final unsubscribe = observer.subscribe((_) {});

        // Has not fetched and is not fetching since it is disabled
        expect(count, 0);
        expect(observer.currentResult.status, QueryStatus.pending);
        expect(observer.currentResult.fetchStatus, FetchStatus.idle);
        expect(observer.currentResult.dataOrNull, isNull);

        unsubscribe();
      });

      testFakeAsync(
          'should not be re-fetched when invalidated with refetchType: all',
          (time) async {
        final observer = makeObserver();
        final unsubscribe = observer.subscribe((_) {});

        queryClient
            .invalidateQueries(
              filters: QueryFilters(queryKey: key),
              refetchType: RefetchType.all,
            )
            .ignore();

        // So we still expect it to not have fetched and not be fetching
        expect(count, 0);
        expect(observer.currentResult.status, QueryStatus.pending);
        expect(observer.currentResult.fetchStatus, FetchStatus.idle);
        expect(observer.currentResult.dataOrNull, isNull);
        await time.advance(ms(10));
        expect(count, 0);

        unsubscribe();
      });

      testFakeAsync('should still trigger a fetch when refetch is called',
          (time) async {
        final observer = makeObserver();
        final unsubscribe = observer.subscribe((_) {});

        expect(enabled, isFalse);

        // Not the same with an explicit refetch: it overrides enabled and
        // triggers a fetch anyway
        observer.refetch().ignore();

        expect(observer.currentResult.status, QueryStatus.pending);
        expect(observer.currentResult.fetchStatus, FetchStatus.fetching);
        expect(observer.currentResult.dataOrNull, isNull);

        await time.advance(ms(10));
        expect(count, 1);
        expect(observer.currentResult.status, QueryStatus.success);
        expect(observer.currentResult.fetchStatus, FetchStatus.idle);
        expect(observer.currentResult.dataOrNull, 'data');

        unsubscribe();
      });

      testFakeAsync(
          'should fetch if unsubscribed, then enabled returns true, and then re-subscribed',
          (time) async {
        final observer = makeObserver();
        var unsubscribe = observer.subscribe((_) {});
        expect(observer.currentResult.status, QueryStatus.pending);
        expect(observer.currentResult.fetchStatus, FetchStatus.idle);
        expect(observer.currentResult.dataOrNull, isNull);

        unsubscribe();

        enabled = true;

        unsubscribe = observer.subscribe((_) {});

        expect(observer.currentResult.status, QueryStatus.pending);
        expect(observer.currentResult.fetchStatus, FetchStatus.fetching);
        expect(observer.currentResult.dataOrNull, isNull);
        await time.advance(ms(10));
        expect(count, 1);

        unsubscribe();
      });

      testFakeAsync(
          'should not be re-fetched if not subscribed to after enabled was '
          'toggled to true (fetchStatus: "idle")', (time) async {
        final observer = makeObserver();
        final unsubscribe = observer.subscribe((_) {});

        // Toggle enabled
        enabled = true;

        unsubscribe();

        queryClient
            .invalidateQueries(
              filters: QueryFilters(queryKey: key),
              refetchType: RefetchType.active,
            )
            .ignore();

        expect(observer.currentResult.status, QueryStatus.pending);
        expect(observer.currentResult.fetchStatus, FetchStatus.idle);
        expect(observer.currentResult.dataOrNull, isNull);
        expect(count, 0);
      });

      testFakeAsync(
          'should not be re-fetched if not subscribed to after enabled was '
          'toggled to true (fetchStatus: "fetching")', (time) async {
        final observer = makeObserver();
        final unsubscribe = observer.subscribe((_) {});

        // Toggle enabled
        enabled = true;

        queryClient
            .invalidateQueries(
              filters: QueryFilters(queryKey: key),
              refetchType: RefetchType.active,
            )
            .ignore();

        expect(observer.currentResult.status, QueryStatus.pending);
        expect(observer.currentResult.fetchStatus, FetchStatus.fetching);
        expect(observer.currentResult.dataOrNull, isNull);
        await time.advance(ms(10));
        expect(count, 1);

        unsubscribe();
      });

      testFakeAsync(
          'should handle that the enabled callback updates the return value',
          (time) async {
        final observer = makeObserver();
        final unsubscribe = observer.subscribe((_) {});

        // Toggle enabled
        enabled = true;

        queryClient
            .invalidateQueries(
              filters: QueryFilters(queryKey: key),
              refetchType: RefetchType.inactive,
            )
            .ignore();

        // should not refetch since it was active and we only refetch inactive
        await time.advance(ms(10));
        expect(count, 0);

        queryClient
            .invalidateQueries(
              filters: QueryFilters(queryKey: key),
              refetchType: RefetchType.active,
            )
            .ignore();

        // should refetch since it was active and we refetch active
        await time.advance(ms(10));
        expect(count, 1);

        // Toggle enabled
        enabled = false;

        // should not refetch since it is not active and we only refetch active
        queryClient
            .invalidateQueries(
              filters: QueryFilters(queryKey: key),
              refetchType: RefetchType.active,
            )
            .ignore();

        await time.advance(ms(10));
        expect(count, 1);

        unsubscribe();
      });
    });

    testFakeAsync(
        'should be able to read latest data when re-subscribing (but not re-fetching)',
        (time) async {
      final key = queryKey();
      var count = 0;
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          staleTime: StaleTime.infinite,
          queryFn: (_) async {
            await sleep(ms(10));
            count++;
            return 'data';
          },
        ),
      );

      var unsubscribe = observer.subscribe((_) {});

      // unsubscribe before data comes in
      unsubscribe();
      expect(count, 0);
      expect(observer.currentResult.status, QueryStatus.pending);
      expect(observer.currentResult.fetchStatus, FetchStatus.fetching);
      expect(observer.currentResult.dataOrNull, isNull);

      await time.advance(ms(10));
      expect(count, 1);

      // re-subscribe after data comes in
      unsubscribe = observer.subscribe((_) {});

      expect(observer.currentResult.status, QueryStatus.success);
      expect(observer.currentResult.dataOrNull, 'data');

      unsubscribe();
    });

    testFakeAsync('should notify when switching query', (time) async {
      final key1 = queryKey();
      final key2 = queryKey();
      final results = <QueryResult<int>>[];
      final observer = queryClient.observe<int, int>(
        QueryObserverOptions<int>(queryKey: key1, queryFn: (_) => 1),
      );
      final unsubscribe = observer.subscribe(results.add);
      await time.flushMicrotasks();
      observer.setOptions(
        QueryObserverOptions<int>(queryKey: key2, queryFn: (_) => 2),
      );
      await time.flushMicrotasks();
      unsubscribe();
      expect(results.length, 4);
      expect(results[0].dataOrNull, isNull);
      expect(results[0].status, QueryStatus.pending);
      expect(results[1].dataOrNull, 1);
      expect(results[1].status, QueryStatus.success);
      expect(results[2].dataOrNull, isNull);
      expect(results[2].status, QueryStatus.pending);
      expect(results[3].dataOrNull, 2);
      expect(results[3].status, QueryStatus.success);
    });

    testFakeAsync('should be able to fetch with a selector', (time) async {
      final key = queryKey();
      final observer = queryClient.observe<Counted, int>(
        QuerySelectOptions<Counted, int>(
          queryKey: key,
          queryFn: (_) => (count: 1),
          select: (data) => data.count,
        ),
      );
      QueryResult<int>? observerResult;
      final unsubscribe = observer.subscribe((result) {
        observerResult = result;
      });
      await time.flushMicrotasks();
      unsubscribe();
      expect(observerResult?.dataOrNull, 1);
    });

    testFakeAsync(
        'should be able to fetch with a selector using the fetch method',
        (time) async {
      final key = queryKey();
      final observer = queryClient.observe<Counted, int>(
        QuerySelectOptions<Counted, int>(
          queryKey: key,
          queryFn: (_) => (count: 1),
          select: (data) => data.count,
        ),
      );
      final observerResult = await observer.refetch();
      expect(observerResult.dataOrNull, 1);
    });

    testFakeAsync('should run the selector again if the data changed',
        (time) async {
      final key = queryKey();
      var count = 0;
      final observer = queryClient.observe<Counted, int>(
        QuerySelectOptions<Counted, int>(
          queryKey: key,
          queryFn: (_) => (count: count),
          select: (data) {
            count++;
            return data.count;
          },
        ),
      );
      final observerResult1 = await observer.refetch();
      final observerResult2 = await observer.refetch();
      expect(count, 2);
      expect(observerResult1.dataOrNull, 0);
      expect(observerResult2.dataOrNull, 1);
    });

    testFakeAsync('should run the selector again if the selector changed',
        (time) async {
      final key = queryKey();
      var count = 0;
      final results = <QueryResult<int>>[];
      Counted queryFn(QueryFunctionContext _) => (count: 1);
      int select1(Counted data) {
        count++;
        return data.count;
      }

      int select2(Counted data) {
        count++;
        return 99;
      }

      final observer = queryClient.observe<Counted, int>(
        QuerySelectOptions<Counted, int>(
          queryKey: key,
          queryFn: queryFn,
          select: select1,
        ),
      );
      final unsubscribe = observer.subscribe(results.add);
      await time.flushMicrotasks();
      observer.setOptions(
        QuerySelectOptions<Counted, int>(
          queryKey: key,
          queryFn: queryFn,
          select: select2,
        ),
      );
      await observer.refetch();
      unsubscribe();
      expect(count, 2);
      expect(results.length, 5);
      expect(results[0].status, QueryStatus.pending);
      expect(results[0].isFetching, isTrue);
      expect(results[0].dataOrNull, isNull);
      expect(results[1].status, QueryStatus.success);
      expect(results[1].isFetching, isFalse);
      expect(results[1].dataOrNull, 1);
      expect(results[2].status, QueryStatus.success);
      expect(results[2].isFetching, isFalse);
      expect(results[2].dataOrNull, 99);
      expect(results[3].status, QueryStatus.success);
      expect(results[3].isFetching, isTrue);
      expect(results[3].dataOrNull, 99);
      expect(results[4].status, QueryStatus.success);
      expect(results[4].isFetching, isFalse);
      expect(results[4].dataOrNull, 99);
    });

    testFakeAsync(
        'should not run the selector again if the data and selector did not change',
        (time) async {
      final key = queryKey();
      var count = 0;
      final results = <QueryResult<int>>[];
      Counted queryFn(QueryFunctionContext _) => (count: 1);
      int select(Counted data) {
        count++;
        return data.count;
      }

      final observer = queryClient.observe<Counted, int>(
        QuerySelectOptions<Counted, int>(
          queryKey: key,
          queryFn: queryFn,
          select: select,
        ),
      );
      final unsubscribe = observer.subscribe(results.add);
      await time.flushMicrotasks();
      observer.setOptions(
        QuerySelectOptions<Counted, int>(
          queryKey: key,
          queryFn: queryFn,
          select: select,
        ),
      );
      await observer.refetch();
      unsubscribe();
      expect(count, 1);
      expect(results.length, 4);
      expect(results[0].status, QueryStatus.pending);
      expect(results[0].isFetching, isTrue);
      expect(results[0].dataOrNull, isNull);
      expect(results[1].status, QueryStatus.success);
      expect(results[1].isFetching, isFalse);
      expect(results[1].dataOrNull, 1);
      expect(results[2].status, QueryStatus.success);
      expect(results[2].isFetching, isTrue);
      expect(results[2].dataOrNull, 1);
      expect(results[3].status, QueryStatus.success);
      expect(results[3].isFetching, isFalse);
      expect(results[3].dataOrNull, 1);
    });

    testFakeAsync(
        'should not run the selector again if the data did not change',
        (time) async {
      final key = queryKey();
      var count = 0;
      final observer = queryClient.observe<Counted, int>(
        QuerySelectOptions<Counted, int>(
          queryKey: key,
          queryFn: (_) => (count: 1),
          select: (data) {
            count++;
            return data.count;
          },
        ),
      );
      final observerResult1 = await observer.refetch();
      final observerResult2 = await observer.refetch();
      expect(count, 1);
      expect(observerResult1.dataOrNull, 1);
      expect(observerResult2.dataOrNull, 1);
    });

    testFakeAsync(
        'should always run the selector again if selector throws an error and '
        'selector is not referentially stable', (time) async {
      final key = queryKey();
      final results = <QueryResult<Counted>>[];
      final observer = queryClient.observe<Counted, Counted>(
        QuerySelectOptions<Counted, Counted>(
          queryKey: key,
          queryFn: (_) async {
            await sleep(ms(10));
            return (count: 1);
          },
          select: (_) => throw Exception('selector error'),
        ),
      );
      final unsubscribe = observer.subscribe(results.add);
      await time.advance(ms(10));
      observer.refetch().ignore();
      await time.advance(ms(10));
      unsubscribe();
      expect(results[0].status, QueryStatus.pending);
      expect(results[0].isFetching, isTrue);
      expect(results[0].dataOrNull, isNull);
      expect(results[1].status, QueryStatus.error);
      expect(results[1].isFetching, isFalse);
      expect(results[1].dataOrNull, isNull);
      expect(results[2].status, QueryStatus.error);
      expect(results[2].isFetching, isTrue);
      expect(results[2].dataOrNull, isNull);
      expect(results[3].status, QueryStatus.error);
      expect(results[3].isFetching, isFalse);
      expect(results[3].dataOrNull, isNull);
    });

    testFakeAsync(
        'should not have isPlaceholderData true when selector throws on placeholder data',
        (time) async {
      final key = queryKey();
      final observer = queryClient.observe<Counted, Counted>(
        QuerySelectOptions<Counted, Counted>(
          queryKey: key,
          queryFn: (_) async {
            await sleep(ms(10));
            return (count: 1);
          },
          placeholderData: const PlaceholderData<Counted>.value((count: 0)),
          select: (_) => throw Exception('selector error'),
        ),
      );

      final result = observer.currentResult;

      expect(result.isError, isTrue);
      expect(result.isPlaceholderData, isFalse);
      expect(result.dataOrNull, isNull);
    });

    testFakeAsync('should return stale data if selector throws an error',
        (time) async {
      final key = queryKey();
      final results = <QueryResult<String>>[];
      var shouldError = false;
      final error = Exception('select error');
      final observer = queryClient.observe<int, String>(
        QuerySelectOptions<int, String>(
          queryKey: key,
          retry: RetryPolicy.never,
          queryFn: (_) async {
            await sleep(ms(10));
            return shouldError ? 2 : 1;
          },
          select: (value) {
            if (shouldError) {
              throw error;
            }
            shouldError = true;
            return '$value';
          },
        ),
      );

      final unsubscribe = observer.subscribe(results.add);
      await time.advance(ms(10));
      observer.refetch().ignore();
      await time.advance(ms(10));
      unsubscribe();

      expect(results[0].status, QueryStatus.pending);
      expect(results[0].isFetching, isTrue);
      expect(results[0].dataOrNull, isNull);
      expect(results[1].status, QueryStatus.success);
      expect(results[1].isFetching, isFalse);
      expect(results[1].dataOrNull, '1');
      expect(results[2].status, QueryStatus.success);
      expect(results[2].isFetching, isTrue);
      expect(results[2].dataOrNull, '1');
      expect(results[3].status, QueryStatus.error);
      expect(results[3].isFetching, isFalse);
      expect(results[3].dataOrNull, '1');
      expect((results[3] as QueryError<String>).error, same(error));
    });

    testFakeAsync(
        'should not leak the select error of the previous query into the result '
        'of a different query', (time) async {
      final key1 = queryKey();
      final key2 = queryKey();
      final observer = queryClient.observe<Counted, Counted>(
        QuerySelectOptions<Counted, Counted>(
          queryKey: key1,
          queryFn: (_) async {
            await sleep(ms(10));
            return (count: 1);
          },
          select: (_) => throw Exception('selector error'),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(10));
      expect(observer.currentResult.status, QueryStatus.error);

      observer.setOptions(
        QuerySelectOptions<Counted, Counted>(
          queryKey: key2,
          queryFn: (_) async {
            await sleep(ms(10));
            return (count: 2);
          },
          select: (data) => data,
        ),
      );

      expect(observer.currentResult.status, QueryStatus.pending);
      expect(observer.currentResult.dataOrNull, isNull);

      await time.advance(ms(10));
      unsubscribe();

      expect(observer.currentResult.status, QueryStatus.success);
      expect(observer.currentResult.dataOrNull, (count: 2));
    });

    testFakeAsync(
        'should not leak a stale select error through the memoized placeholderData path',
        (time) async {
      final keyA = queryKey();
      final keyB = queryKey();
      final keyC = queryKey();
      const placeholder = PlaceholderData<Counted>.value((count: 0));
      final observer = queryClient.observe<Counted, ({int selected})>(
        QuerySelectOptions<Counted, ({int selected})>(
          queryKey: keyA,
          queryFn: (_) async {
            await sleep(ms(10));
            return (count: 1);
          },
          placeholderData: placeholder,
          select: (data) => (selected: data.count),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(10));
      expect(observer.currentResult.status, QueryStatus.success);
      expect(observer.currentResult.dataOrNull, (selected: 1));

      observer.setOptions(
        QuerySelectOptions<Counted, ({int selected})>(
          queryKey: keyB,
          queryFn: (_) async {
            await sleep(ms(10));
            return (count: 2);
          },
          placeholderData: placeholder,
          select: (_) => throw Exception('selector error'),
        ),
      );
      expect(observer.currentResult.status, QueryStatus.error);

      observer.setOptions(
        QuerySelectOptions<Counted, ({int selected})>(
          queryKey: keyC,
          queryFn: (_) async {
            await sleep(ms(10));
            return (count: 3);
          },
          placeholderData: placeholder,
          select: (data) => (selected: data.count),
        ),
      );
      expect(observer.currentResult.status, QueryStatus.success);
      expect(observer.currentResult.dataOrNull, (selected: 0));
      expect(observer.currentResult.isPlaceholderData, isTrue);

      await time.advance(ms(10));
      unsubscribe();

      expect(observer.currentResult.status, QueryStatus.success);
      expect(observer.currentResult.dataOrNull, (selected: 3));
    });

    testFakeAsync('should clear the select error when the query is reset',
        (time) async {
      final key = queryKey();
      var shouldThrow = true;
      final observer = queryClient.observe<Counted, Counted>(
        QuerySelectOptions<Counted, Counted>(
          queryKey: key,
          queryFn: (_) async {
            await sleep(ms(10));
            return (count: 1);
          },
          select: (data) {
            if (shouldThrow) {
              throw Exception('selector error');
            }
            return data;
          },
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(10));
      expect(observer.currentResult.status, QueryStatus.error);

      shouldThrow = false;
      queryClient.resetQueries(filters: QueryFilters(queryKey: key)).ignore();

      expect(observer.currentResult.status, QueryStatus.pending);
      expect(observer.currentResult.dataOrNull, isNull);

      await time.advance(ms(10));
      unsubscribe();

      expect(observer.currentResult.status, QueryStatus.success);
      expect(observer.currentResult.dataOrNull, (count: 1));
    });

    testFakeAsync('should structurally share the selector', (time) async {
      final key = queryKey();
      var count = 0;
      final observer = queryClient.observe<Map<String, int>, Map<String, int>>(
        QuerySelectOptions(
          queryKey: key,
          queryFn: (_) => <String, int>{'count': ++count},
          select: (_) => <String, int>{'myCount': 1},
        ),
      );
      final observerResult1 = await observer.refetch();
      final observerResult2 = await observer.refetch();
      expect(count, 2);
      expect(observerResult1.dataOrNull, same(observerResult2.dataOrNull));
    });

    testFakeAsync('should not trigger a fetch when subscribed and disabled',
        (time) async {
      final key = queryKey();
      var calls = 0;
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            calls++;
            return 'data';
          },
          enabled: Enabled.no,
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      unsubscribe();
      expect(calls, 0);
    });

    testFakeAsync(
        'should not trigger a fetch when subscribed and disabled by callback',
        (time) async {
      final key = queryKey();
      var calls = 0;
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            calls++;
            return 'data';
          },
          enabled: Enabled.when((_) => false),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      unsubscribe();
      expect(calls, 0);
    });

    testFakeAsync('should not trigger a fetch when not subscribed',
        (time) async {
      final key = queryKey();
      var calls = 0;
      queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            calls++;
            return 'data';
          },
        ),
      );
      await time.flushMicrotasks();
      expect(calls, 0);
    });

    testFakeAsync(
        'should be able to watch a query without defining a query function',
        (time) async {
      final key = queryKey();
      var calls = 0;
      String queryFn(QueryFunctionContext _) {
        calls++;
        return 'data';
      }

      final results = <QueryResult<String>>[];
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          enabled: Enabled.no,
        ),
      );
      final unsubscribe = observer.subscribe(results.add);
      await queryClient
          .query<String>(QueryOptions<String>(queryKey: key, queryFn: queryFn));
      await time.flushMicrotasks();
      unsubscribe();
      expect(calls, 1);
      expect(results, hasLength(2));
    });

    testFakeAsync('should accept unresolved query config in update function',
        (time) async {
      final key = queryKey();
      var calls = 0;
      String queryFn(QueryFunctionContext _) {
        calls++;
        return 'data';
      }

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          enabled: Enabled.no,
        ),
      );
      final results = <QueryResult<String>>[];
      final unsubscribe = observer.subscribe(results.add);
      observer.setOptions(
        QueryObserverOptions<String>(
          queryKey: key,
          enabled: Enabled.no,
          staleTime: StaleTime.duration(ms(10)),
        ),
      );
      await queryClient
          .query<String>(QueryOptions<String>(queryKey: key, queryFn: queryFn));
      await time.flushMicrotasks();
      unsubscribe();
      expect(calls, 1);
      expect(results.length, 2);
      expect(results[0].isStale, isFalse);
      expect(results[0].dataOrNull, isNull);
      expect(results[1].isStale, isFalse);
      expect(results[1].dataOrNull, 'data');
    });

    testFakeAsync('should be able to handle multiple subscribers',
        (time) async {
      final key = queryKey();
      var calls = 0;
      String queryFn(QueryFunctionContext _) {
        calls++;
        return 'data';
      }

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          enabled: Enabled.no,
        ),
      );
      final results1 = <QueryResult<String>>[];
      final results2 = <QueryResult<String>>[];
      final unsubscribe1 = observer.subscribe(results1.add);
      final unsubscribe2 = observer.subscribe(results2.add);
      await queryClient
          .query<String>(QueryOptions<String>(queryKey: key, queryFn: queryFn));
      await time.flushMicrotasks();
      unsubscribe1();
      unsubscribe2();
      expect(calls, 1);
      expect(results1.length, 2);
      expect(results2.length, 2);
      expect(results1[0].dataOrNull, isNull);
      expect(results1[1].dataOrNull, 'data');
      expect(results2[0].dataOrNull, isNull);
      expect(results2[1].dataOrNull, 'data');
    });

    testFakeAsync('should stop retry when unsubscribing', (time) async {
      final key = queryKey();
      var count = 0;
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            count++;
            return Future<String>.error('reject');
          },
          retry: const RetryTimes(10),
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 50)),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(50));
      unsubscribe();
      await time.advance(ms(50));
      expect(count, 2);
    });

    testFakeAsync(
        'should clear interval when unsubscribing to a refetchInterval query',
        (time) async {
      final key = queryKey();
      var count = 0;

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            count++;
            return Future<String>.value('data');
          },
          gcTime: const GcTime.duration(Duration.zero),
          refetchInterval: RefetchInterval.every(ms(10)),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      expect(count, 1);
      await time.advance(ms(10));
      expect(count, 2);
      unsubscribe();
      await time.advance(ms(10));
      expect(queryClient.queryCache.find(filters: QueryFilters(queryKey: key)),
          isNull);
      expect(count, 2);
    });

    testFakeAsync(
        'should refetch at the interval returned when refetchInterval is a function',
        (time) async {
      final key = queryKey();
      var count = 0;
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            count++;
            return Future<String>.value('data');
          },
          refetchInterval: RefetchInterval.dynamic((_) => ms(10)),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      expect(count, 1);
      await time.advance(ms(10));
      expect(count, 2);
      unsubscribe();
    });

    testFakeAsync(
        'should call refetchInterval with the query when it is a function',
        (time) async {
      final key = queryKey();
      final seen = <Query<Object?>>[];
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) async {
            await sleep(ms(10));
            return 'data';
          },
          refetchInterval: RefetchInterval.dynamic((query) {
            seen.add(query);
            return ms(10);
          }),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(10));
      expect(
        seen,
        everyElement(
          same(queryClient.queryCache
              .find(filters: QueryFilters(queryKey: key))),
        ),
      );
      expect(seen, isNotEmpty);
      unsubscribe();
    });

    testFakeAsync(
        'should use placeholderData as non-cache data when pending a query with no data',
        (time) async {
      final key = queryKey();
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
          placeholderData: const PlaceholderData<String>.value('placeholder'),
        ),
      );

      expect(observer.currentResult.status, QueryStatus.success);
      expect(observer.currentResult.dataOrNull, 'placeholder');

      final results = <QueryResult<String>>[];

      final unsubscribe = observer.subscribe(results.add);

      await time.flushMicrotasks();
      unsubscribe();

      expect(results.length, 2);
      expect(results[0].status, QueryStatus.success);
      expect(results[0].dataOrNull, 'placeholder');
      expect(results[1].status, QueryStatus.success);
      expect(results[1].dataOrNull, 'data');
    });

    testFakeAsync('should structurally share placeholder data', (time) async {
      final key = queryKey();
      final observer = queryClient.observe<Map<String, int>, Map<String, int>>(
        QueryObserverOptions(
          queryKey: key,
          enabled: Enabled.no,
          queryFn: (_) => <String, int>{},
          placeholderData: PlaceholderData.value(<String, int>{}),
        ),
      );

      final firstData = observer.currentResult.dataOrNull;

      observer.setOptions(QueryObserverOptions(
        queryKey: key,
        placeholderData: PlaceholderData.value(<String, int>{}),
      ));

      final secondData = observer.currentResult.dataOrNull;

      expect(firstData, same(secondData));
    });

    testFakeAsync('should return the current query from getCurrentQuery',
        (time) async {
      final key = queryKey();

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
        ),
      );

      expect(observer.currentQuery.queryKey, key);
    });

    testFakeAsync(
        'should not refetch in background if refetchIntervalInBackground is false',
        (time) async {
      final key = queryKey();
      var calls = 0;

      queryClient.focusManager.setFocused(false);
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            calls++;
            return 'data';
          },
          refetchIntervalInBackground: false,
          refetchInterval: RefetchInterval.every(ms(10)),
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(30));

      expect(calls, 1);

      // Clean-up
      unsubscribe();
      queryClient.focusManager.setFocused(true);
    });

    testFakeAsync(
        'should pass the correct previous queryKey (from prevQuery) to '
        'placeholderData function params with select', (time) async {
      final results = <QueryResult<String>>[];
      final keys = <QueryKey?>[];

      final key1 = queryKey();
      final key2 = queryKey();

      const data1 = (value: 'data1');
      const data2 = (value: 'data2');

      PlaceholderData<({String value})> placeholder() =>
          PlaceholderData<({String value})>.compute((prev, prevQuery) {
            keys.add(prevQuery?.queryKey);
            return prev;
          });

      final observer = queryClient.observe<({String value}), String>(
        QuerySelectOptions<({String value}), String>(
          queryKey: key1,
          queryFn: (_) => data1,
          placeholderData: placeholder(),
          select: (data) => data.value,
        ),
      );

      final unsubscribe = observer.subscribe(results.add);

      await time.flushMicrotasks();

      observer.setOptions(
        QuerySelectOptions<({String value}), String>(
          queryKey: key2,
          queryFn: (_) => data2,
          placeholderData: placeholder(),
          select: (data) => data.value,
        ),
      );

      await time.flushMicrotasks();
      unsubscribe();
      expect(results.length, 4);
      expect(keys.length, 3);
      expect(keys[0], isNull); // First query — pending, idle
      expect(keys[1], isNull); // First query — pending, fetching
      expect(keys[2], key1); // Second query — pending, fetching

      expect(results[0].dataOrNull, isNull);
      expect(results[0].status, QueryStatus.pending);
      expect(results[0].fetchStatus, FetchStatus.fetching);
      expect(results[1].dataOrNull, 'data1');
      expect(results[1].status, QueryStatus.success);
      expect(results[1].fetchStatus, FetchStatus.idle);
      expect(results[2].dataOrNull, 'data1');
      expect(results[2].status, QueryStatus.success);
      expect(results[2].fetchStatus, FetchStatus.fetching);
      expect(results[3].dataOrNull, 'data2');
      expect(results[3].status, QueryStatus.success);
      expect(results[3].fetchStatus, FetchStatus.idle);
    });

    testFakeAsync(
        'should pass the correct previous data to placeholderData function '
        'params when select function is used in conjunction', (time) async {
      final results = <QueryResult<String>>[];

      final key1 = queryKey();
      final key2 = queryKey();

      const data1 = (value: 'data1');
      const data2 = (value: 'data2');

      var selectCount = 0;

      final observer = queryClient.observe<({String value}), String>(
        QuerySelectOptions<({String value}), String>(
          queryKey: key1,
          queryFn: (_) => data1,
          placeholderData:
              PlaceholderData<({String value})>.compute((prev, _) => prev),
          select: (data) {
            selectCount++;
            return data.value;
          },
        ),
      );

      final unsubscribe = observer.subscribe(results.add);

      await time.flushMicrotasks();

      observer.setOptions(
        QuerySelectOptions<({String value}), String>(
          queryKey: key2,
          queryFn: (_) => data2,
          placeholderData:
              PlaceholderData<({String value})>.compute((prev, _) => prev),
          select: (data) {
            selectCount++;
            return data.value;
          },
        ),
      );

      await time.flushMicrotasks();
      unsubscribe();

      expect(results.length, 4);
      expect(results[0].dataOrNull, isNull);
      expect(results[1].dataOrNull, 'data1');
      expect(results[2].dataOrNull, 'data1');
      expect(results[3].dataOrNull, 'data2');

      // it's 3 because select is an inline function
      expect(selectCount, 3);
    });

    testFakeAsync(
        'should use cached selectResult when switching between queries and '
        'placeholderData returns previousData', (time) async {
      final results = <QueryResult<String>>[];

      final key1 = queryKey();
      final key2 = queryKey();

      const data1 = (value: 'data1');
      const data2 = (value: 'data2');

      final selected = <({String value})>[];
      String stableSelect(({String value}) data) {
        selected.add(data);
        return data.value;
      }

      final observer = queryClient.observe<({String value}), String>(
        QuerySelectOptions<({String value}), String>(
          queryKey: key1,
          queryFn: (_) => data1,
          placeholderData:
              PlaceholderData<({String value})>.compute((prev, _) => prev),
          select: stableSelect,
        ),
      );

      final unsubscribe = observer.subscribe(results.add);

      await time.flushMicrotasks();

      observer.setOptions(
        QuerySelectOptions<({String value}), String>(
          queryKey: key2,
          queryFn: (_) => data2,
          placeholderData:
              PlaceholderData<({String value})>.compute((prev, _) => prev),
          select: stableSelect,
        ),
      );

      await time.flushMicrotasks();
      unsubscribe();

      expect(results.length, 4);
      expect(results[0].dataOrNull, isNull);
      expect(results[1].dataOrNull, 'data1');
      expect(results[2].dataOrNull, 'data1');
      expect(results[3].dataOrNull, 'data2');

      expect(selected, <({String value})>[data1, data2]);
    });

    testFakeAsync('should notify cache listeners when setOptions is called',
        (time) async {
      final key = queryKey();

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          enabled: Enabled.no,
        ),
      );

      final events = <QueryCacheEvent>[];
      final unsubscribe = queryClient.queryCache.subscribe(events.add);
      observer.setOptions(
        QueryObserverOptions<String>(
          queryKey: key,
          enabled: Enabled.no,
          refetchInterval: RefetchInterval.every(ms(10)),
        ),
      );

      final query =
          queryClient.queryCache.find(filters: QueryFilters(queryKey: key));
      expect(events, hasLength(1));
      expect(events.single, isA<QueryObserverOptionsUpdated>());
      expect(events.single.query, same(query));
      expect((events.single as QueryObserverOptionsUpdated).observer,
          same(observer));

      unsubscribe();
    });

    testFakeAsync('should not be stale for disabled observers', (time) async {
      final key = queryKey();

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          enabled: Enabled.no,
        ),
      );

      expect(observer.currentResult.isStale, isFalse);
    });

    testFakeAsync('should not schedule timers for disabled observers',
        (time) async {
      final key = queryKey();
      queryClient.setQueryData<String>(
        key,
        'data',
        updatedAt: time.now.subtract(ms(20)),
      );

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          enabled: Enabled.no,
          staleTime: StaleTime.duration(ms(10)),
          refetchInterval: RefetchInterval.every(ms(10)),
        ),
      );

      // Upstream spies on the timeout manager; here the harness counts the
      // timers the zone actually holds. Adding an observer cancels the query's
      // gc timer, and a disabled observer must not schedule a stale timeout or
      // a refetch interval in its place — so nothing at all stays pending.
      final unsubscribe = observer.subscribe((_) {});

      expect(time.pendingTimers, 0);

      unsubscribe();
    });

    testFakeAsync('should allow staleTime as a function', (time) async {
      final key = queryKey();
      final observer = queryClient.observe<({String data, Duration staleTime}),
          ({String data, Duration staleTime})>(
        QueryObserverOptions<({String data, Duration staleTime})>(
          queryKey: key,
          queryFn: (_) async {
            await sleep(ms(5));
            return (data: 'data', staleTime: ms(20));
          },
          staleTime: StaleTime.dynamic(
            (query) => StaleTime.duration(
              (query.state.data as ({String data, Duration staleTime})?)
                      ?.staleTime ??
                  Duration.zero,
            ),
          ),
        ),
      );
      final results = <QueryResult<({String data, Duration staleTime})>>[];
      final unsubscribe = observer.subscribe((result) {
        if (result.dataOrNull != null) {
          results.add(result);
        }
      });

      await time.advance(ms(25));
      expect(results[0].isStale, isFalse);
      await time.advance(ms(1));
      expect(results[1].isStale, isTrue);

      unsubscribe();
    });

    testFakeAsync('should not see queries as stale is staleTime is Static',
        (time) async {
      final key = queryKey();
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) async {
            await sleep(ms(5));
            return 'data';
          },
          staleTime: StaleTime.static,
        ),
      );
      expect(observer.currentResult.isStale, isTrue); // no data = stale

      final results = <QueryResult<String>>[];
      final unsubscribe = observer.subscribe((result) {
        if (result.dataOrNull != null) {
          results.add(result);
        }
      });

      await time.advance(ms(5));
      expect(results[0].isStale, isFalse);

      unsubscribe();
    });

    testFakeAsync(
        'should return true from shouldFetchOnWindowFocus when '
        'refetchOnWindowFocus is true', (time) async {
      final key = queryKey();

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
          refetchOnWindowFocus: RefetchOn.ifStale,
        ),
      );

      expect(observer.shouldFetchOnWindowFocus(), isTrue);
    });

    testFakeAsync(
        'should return false from shouldFetchOnWindowFocus when '
        'refetchOnWindowFocus is false', (time) async {
      final key = queryKey();

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
          refetchOnWindowFocus: RefetchOn.never,
        ),
      );

      expect(observer.shouldFetchOnWindowFocus(), isFalse);
    });

    testFakeAsync(
        'should return true from shouldFetchOnWindowFocus when '
        'refetchOnWindowFocus is "always" even if the query is fresh',
        (time) async {
      final key = queryKey();

      queryClient
          .query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              await sleep(ms(10));
              return 'data';
            },
          ))
          .ignore();
      await time.advance(ms(10));

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) async {
            await sleep(ms(10));
            return 'data';
          },
          staleTime: StaleTime.infinite,
          refetchOnWindowFocus: RefetchOn.always,
        ),
      );

      expect(observer.shouldFetchOnWindowFocus(), isTrue);
    });

    testFakeAsync(
        'should return true from shouldFetchOnWindowFocus when '
        'refetchOnWindowFocus is a function returning true', (time) async {
      final key = queryKey();
      final seen = <Query<Object?>>[];

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
          refetchOnWindowFocus: RefetchOn.when((query) {
            seen.add(query);
            return RefetchOn.ifStale;
          }),
        ),
      );

      expect(observer.shouldFetchOnWindowFocus(), isTrue);
      expect(
        seen,
        everyElement(
          same(queryClient.queryCache
              .find(filters: QueryFilters(queryKey: key))),
        ),
      );
      expect(seen, isNotEmpty);
    });

    testFakeAsync(
        'should return false from shouldFetchOnWindowFocus when '
        'refetchOnWindowFocus is a function returning false', (time) async {
      final key = queryKey();
      final seen = <Query<Object?>>[];

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
          refetchOnWindowFocus: RefetchOn.when((query) {
            seen.add(query);
            return RefetchOn.never;
          }),
        ),
      );

      expect(observer.shouldFetchOnWindowFocus(), isFalse);
      expect(seen, isNotEmpty);
    });

    testFakeAsync(
        'should return true from shouldFetchOnWindowFocus when '
        'refetchOnWindowFocus is a function returning "always" even if the '
        'query is fresh', (time) async {
      final key = queryKey();
      final seen = <Query<Object?>>[];

      queryClient
          .query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              await sleep(ms(10));
              return 'data';
            },
          ))
          .ignore();
      await time.advance(ms(10));

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) async {
            await sleep(ms(10));
            return 'data';
          },
          staleTime: StaleTime.infinite,
          refetchOnWindowFocus: RefetchOn.when((query) {
            seen.add(query);
            return RefetchOn.always;
          }),
        ),
      );

      expect(observer.shouldFetchOnWindowFocus(), isTrue);
      expect(seen, isNotEmpty);
    });

    testFakeAsync(
        'should not refetch on mount when retryOnMount is false and query is '
        'in error state', (time) async {
      final key = queryKey();
      var calls = 0;
      Future<String> queryFn(QueryFunctionContext _) {
        calls++;
        return Future<String>.error('error');
      }

      // First observer causes query to fail
      final firstObserver = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: queryFn,
          retry: RetryPolicy.never,
        ),
      );
      final unsubscribeFirst = firstObserver.subscribe((_) {});

      await time.flushMicrotasks();

      expect(calls, 1);
      expect(queryClient.getQueryState<String>(key)?.status, QueryStatus.error);

      unsubscribeFirst();

      // New observer with retryOnMount: false should not refetch
      final secondObserver = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: queryFn,
          retry: RetryPolicy.never,
          retryOnMount: false,
        ),
      );
      final unsubscribeSecond = secondObserver.subscribe((_) {});

      await time.flushMicrotasks();

      // queryFn should still have been called only once (no refetch)
      expect(calls, 1);

      unsubscribeSecond();
    });

    testFakeAsync(
        'should not refetchOnMount when set to "always" when staleTime is Static',
        (time) async {
      final key = queryKey();
      var calls = 0;
      queryClient.setQueryData<String>(key, 'initial');
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            calls++;
            return 'data';
          },
          staleTime: StaleTime.static,
          refetchOnMount: RefetchOn.always,
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      expect(calls, 0);
      unsubscribe();
    });

    testFakeAsync(
        'should not refetchOnWindowFocus when staleTime is static and query has '
        'background error', (time) async {
      final key = queryKey();
      var callCount = 0;
      Future<String> queryFn(QueryFunctionContext _) {
        callCount++;
        if (callCount == 1) {
          return Future<String>.value('data');
        }
        return Future<String>.error(Exception('background error'));
      }

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: queryFn,
          staleTime: StaleTime.static,
          refetchOnWindowFocus: RefetchOn.ifStale,
          retry: RetryPolicy.never,
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      expect(callCount, 1);
      expect(observer.currentResult.dataOrNull, 'data');
      expect(observer.currentResult.status, QueryStatus.success);

      await observer.refetch();
      await time.flushMicrotasks();
      expect(callCount, 2);
      expect(observer.currentResult.status, QueryStatus.error);
      expect(observer.currentResult.dataOrNull, 'data');

      queryClient.focusManager.setFocused(false);
      queryClient.focusManager.setFocused(true);
      await time.flushMicrotasks();
      expect(callCount, 2);

      unsubscribe();
    });

    testFakeAsync(
        'should refetchOnWindowFocus when query has background error and '
        'staleTime is not static', (time) async {
      final key = queryKey();
      var callCount = 0;
      Future<String> queryFn(QueryFunctionContext _) {
        callCount++;
        if (callCount == 1) {
          return Future<String>.value('data');
        }
        if (callCount == 2) {
          return Future<String>.error(Exception('background error'));
        }
        return Future<String>.value('new data');
      }

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: queryFn,
          staleTime: StaleTime.duration(ms(1000)),
          refetchOnWindowFocus: RefetchOn.ifStale,
          retry: RetryPolicy.never,
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      expect(callCount, 1);
      expect(observer.currentResult.dataOrNull, 'data');
      expect(observer.currentResult.status, QueryStatus.success);

      await observer.refetch();
      await time.flushMicrotasks();
      expect(callCount, 2);
      expect(observer.currentResult.status, QueryStatus.error);
      expect(observer.currentResult.dataOrNull, 'data');

      queryClient.focusManager.setFocused(false);
      queryClient.focusManager.setFocused(true);
      await time.flushMicrotasks();
      expect(callCount, 3);

      unsubscribe();
    });

    testFakeAsync('should return isEnabled depending on enabled being resolved',
        (time) async {
      final key = queryKey();
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
          enabled: Enabled.when((_) => false),
        ),
      );

      expect(observer.currentResult.isEnabled, isFalse);
    });

    testFakeAsync('should return isEnabled as true per default', (time) async {
      final key = queryKey();
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
        ),
      );

      expect(observer.currentResult.isEnabled, isTrue);
    });

    testFakeAsync(
        'should update currentResult when getOptimisticResult is called with '
        'changed data', (time) async {
      final key = queryKey();

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
        ),
      );

      final options = QueryObserverOptions<String>(
        queryKey: key,
        queryFn: (_) => 'data',
      );

      // First render: no data yet
      expect(observer.getOptimisticResult(options).dataOrNull, isNull);

      // Another component sets data (e.g. a dependent query resolved)
      queryClient.setQueryData<String>(key, 'updated');

      // Re-render: getOptimisticResult picks up the new data and updates
      // currentResult
      expect(observer.getOptimisticResult(options).dataOrNull, 'updated');
      expect(observer.currentResult.dataOrNull, 'updated');
    });

    group('StrictMode behavior', () {
      testFakeAsync('should deduplicate calls to queryFn', (time) async {
        final key = queryKey();
        var calls = 0;
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              calls++;
              await sleep(ms(50));
              return 'data';
            },
          ),
        );

        final unsubscribe1 = observer.subscribe((_) {});

        await time.advance(ms(5));
        unsubscribe1();

        // replicate strict mode behavior
        await time.advance(ms(5));
        final unsubscribe2 = observer.subscribe((_) {});

        await time.advance(ms(40));

        final state = queryClient.getQueryState<String>(key)!;
        expect(state.status, QueryStatus.success);
        expect(state.data, 'data');

        expect(calls, 1);

        unsubscribe2();
      });

      testFakeAsync('should resolve with data when signal was consumed',
          (time) async {
        final key = queryKey();
        var calls = 0;
        final observer = queryClient.observe<String, String>(
          QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (context) async {
              context.signal;
              calls++;
              await sleep(ms(50));
              return 'data';
            },
          ),
        );

        final unsubscribe1 = observer.subscribe((_) {});

        await time.advance(ms(5));
        unsubscribe1();

        // replicate strict mode behavior
        await time.advance(ms(5));
        final unsubscribe2 = observer.subscribe((_) {});

        await time.advance(ms(50));

        final state = queryClient.getQueryState<String>(key)!;
        expect(state.status, QueryStatus.success);
        expect(state.data, 'data');

        expect(calls, 2);

        unsubscribe2();
      });
    });
  });
}
