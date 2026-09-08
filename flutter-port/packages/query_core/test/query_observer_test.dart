import 'dart:async';

import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// A value type, so results compare by value the way the port expects (D5).
class Counted {
  const Counted(this.count);
  final int count;

  @override
  bool operator ==(Object other) => other is Counted && other.count == count;

  @override
  int get hashCode => count.hashCode;

  @override
  String toString() => 'Counted($count)';
}

class Selected {
  const Selected(this.myCount);
  final int myCount;

  @override
  bool operator ==(Object other) =>
      other is Selected && other.myCount == myCount;

  @override
  int get hashCode => myCount.hashCode;

  @override
  String toString() => 'Selected($myCount)';
}

/// Carries its own staleness, for the `staleTime` callback case.
class Payload {
  const Payload(this.data, this.staleTime);
  final String data;
  final int staleTime;

  @override
  bool operator ==(Object other) =>
      other is Payload && other.data == data && other.staleTime == staleTime;

  @override
  int get hashCode => Object.hash(data, staleTime);
}

/// Port of `query/packages/query-core/src/__tests__/queryObserver.test.tsx`.
///
/// Twenty upstream cases have no counterpart: everything about
/// `placeholderData`, `notifyOnChangeProps`, `trackResult`/`trackProp`,
/// `getOptimisticResult`/`fetchOptimistic`/`_optimisticResults`, observer-level
/// `throwOnError`, and structural sharing of the select result. Each is a
/// feature the port drops by design — see PORTING_NOTES.md.
void main() {
  late QueryClient queryClient;
  late QueryCache cache;

  setUp(() {
    queryClient = QueryClient();
    cache = queryClient.queryCache;
    queryClient.mount();
  });

  tearDown(() {
    queryClient.clear();
    queryClient.unmount();
    focusManager.setFocused(null);
  });

  test('should trigger a fetch when subscribed', () {
    final key = queryKey();
    var calls = 0;
    final observer = QueryObserver<String, String>(
      queryClient,
      QueryObserverOptions<String, String>(
        queryKey: key,
        queryFn: (_) async {
          calls++;
          return 'data';
        },
      ),
    );
    observer.subscribe((_) {})();
    expect(calls, 1);
  });

  testFakeAsync(
    'should go through a pending state even when the queryFn returns '
    'synchronously',
    (time) async {
      final key = queryKey();
      var calls = 0;
      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async {
            calls++;
            return 'data';
          },
        ),
      );
      final unsubscribe = observer.subscribe((_) {});

      // A value returned without awaiting is still delivered through a future,
      // so the query passes through a fetching state first.
      expect(calls, 1);
      expect(observer.result.status, QueryStatus.pending);
      expect(observer.result.fetchStatus, FetchStatus.fetching);
      expect(observer.result.dataOrNull, isNull);

      await time.advance(Duration.zero);

      expect(observer.result.status, QueryStatus.success);
      expect(observer.result.fetchStatus, FetchStatus.idle);
      expect(observer.result.dataOrNull, 'data');

      unsubscribe();
    },
  );

  test('should be able to read latest data after subscribing', () {
    final key = queryKey();
    queryClient.setQueryData<String>(key, (_) => 'data');
    final observer = QueryObserver<String, String>(
      queryClient,
      QueryObserverOptions<String, String>(queryKey: key, enabled: Enabled.off),
    );

    final unsubscribe = observer.subscribe((_) {});

    expect(observer.result.status, QueryStatus.success);
    expect(observer.result.dataOrNull, 'data');

    unsubscribe();
  });

  group('enabled is a callback that initially returns false', () {
    late QueryObserver<String, String> observer;
    late bool enabled;
    late int count;
    late QueryKey key;

    setUp(() {
      key = queryKey();
      count = 0;
      enabled = false;

      observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          staleTime: StaleDuration.infinity,
          enabled: Enabled.resolve((_) => enabled),
          queryFn: (_) => sleep(ms(10)).then((_) {
            count++;
            return 'data';
          }),
        ),
      );
    });

    test('should not fetch on mount', () {
      final unsubscribe = observer.subscribe((_) {});

      expect(count, 0);
      expect(observer.result.status, QueryStatus.pending);
      expect(observer.result.fetchStatus, FetchStatus.idle);
      expect(observer.result.dataOrNull, isNull);

      unsubscribe();
    });

    testFakeAsync(
      'should not be re-fetched when invalidated with refetchType: all',
      (time) async {
        final unsubscribe = observer.subscribe((_) {});

        unawaited(
          queryClient.invalidateQueries(
            filters: QueryFilters(queryKey: key),
            refetchType: QueryRefetchType.all,
          ),
        );

        expect(count, 0);
        expect(observer.result.status, QueryStatus.pending);
        expect(observer.result.fetchStatus, FetchStatus.idle);
        expect(observer.result.dataOrNull, isNull);
        await time.advance(ms(10));
        expect(count, 0);

        unsubscribe();
      },
    );

    testFakeAsync('should still trigger a fetch when refetch is called', (
      time,
    ) async {
      final unsubscribe = observer.subscribe((_) {});

      expect(enabled, isFalse);

      // An explicit refetch overrides `enabled` and fetches anyway.
      unawaited(observer.refetch());

      expect(observer.result.status, QueryStatus.pending);
      expect(observer.result.fetchStatus, FetchStatus.fetching);
      expect(observer.result.dataOrNull, isNull);

      await time.advance(ms(10));
      expect(count, 1);
      expect(observer.result.status, QueryStatus.success);
      expect(observer.result.fetchStatus, FetchStatus.idle);
      expect(observer.result.dataOrNull, 'data');

      unsubscribe();
    });

    testFakeAsync(
      'should fetch if unsubscribed, then enabled returns true, and then '
      're-subscribed',
      (time) async {
        var unsubscribe = observer.subscribe((_) {});
        expect(observer.result.status, QueryStatus.pending);
        expect(observer.result.fetchStatus, FetchStatus.idle);

        unsubscribe();

        enabled = true;

        unsubscribe = observer.subscribe((_) {});

        expect(observer.result.status, QueryStatus.pending);
        expect(observer.result.fetchStatus, FetchStatus.fetching);
        await time.advance(ms(10));
        expect(count, 1);

        unsubscribe();
      },
    );

    test(
      'should not be re-fetched if not subscribed to after enabled was toggled '
      'to true (fetchStatus: idle)',
      () {
        final unsubscribe = observer.subscribe((_) {});

        enabled = true;

        unsubscribe();

        unawaited(
          queryClient.invalidateQueries(
            filters: QueryFilters(queryKey: key),
            refetchType: QueryRefetchType.active,
          ),
        );

        expect(observer.result.status, QueryStatus.pending);
        expect(observer.result.fetchStatus, FetchStatus.idle);
        expect(count, 0);
      },
    );

    testFakeAsync(
      'should not be re-fetched if not subscribed to after enabled was toggled '
      'to true (fetchStatus: fetching)',
      (time) async {
        final unsubscribe = observer.subscribe((_) {});

        enabled = true;

        unawaited(
          queryClient.invalidateQueries(
            filters: QueryFilters(queryKey: key),
            refetchType: QueryRefetchType.active,
          ),
        );

        expect(observer.result.status, QueryStatus.pending);
        expect(observer.result.fetchStatus, FetchStatus.fetching);
        await time.advance(ms(10));
        expect(count, 1);

        unsubscribe();
      },
    );

    testFakeAsync(
      'should handle that the enabled callback updates the return value',
      (time) async {
        final unsubscribe = observer.subscribe((_) {});

        enabled = true;

        unawaited(
          queryClient.invalidateQueries(
            filters: QueryFilters(queryKey: key),
            refetchType: QueryRefetchType.inactive,
          ),
        );

        // No refetch: it is active, and only inactive queries were asked to.
        await time.advance(ms(10));
        expect(count, 0);

        unawaited(
          queryClient.invalidateQueries(
            filters: QueryFilters(queryKey: key),
            refetchType: QueryRefetchType.active,
          ),
        );

        await time.advance(ms(10));
        expect(count, 1);

        enabled = false;

        // No refetch: it is no longer active.
        unawaited(
          queryClient.invalidateQueries(
            filters: QueryFilters(queryKey: key),
            refetchType: QueryRefetchType.active,
          ),
        );

        await time.advance(ms(10));
        expect(count, 1);

        unsubscribe();
      },
    );
  });

  testFakeAsync(
    'should be able to read latest data when re-subscribing (but not '
    're-fetching)',
    (time) async {
      final key = queryKey();
      var count = 0;
      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          staleTime: StaleDuration.infinity,
          queryFn: (_) => sleep(ms(10)).then((_) {
            count++;
            return 'data';
          }),
        ),
      );

      var unsubscribe = observer.subscribe((_) {});

      // Unsubscribe before the data arrives.
      unsubscribe();
      expect(count, 0);
      expect(observer.result.status, QueryStatus.pending);
      expect(observer.result.fetchStatus, FetchStatus.fetching);

      await time.advance(ms(10));
      expect(count, 1);

      // Re-subscribe after the data has arrived.
      unsubscribe = observer.subscribe((_) {});

      expect(observer.result.status, QueryStatus.success);
      expect(observer.result.dataOrNull, 'data');

      unsubscribe();
    },
  );

  testFakeAsync('should notify when switching query', (time) async {
    final key1 = queryKey();
    final key2 = queryKey();
    final results = <QueryResult<int>>[];

    final observer = QueryObserver<int, int>(
      queryClient,
      QueryObserverOptions<int, int>(queryKey: key1, queryFn: (_) async => 1),
    );
    final unsubscribe = observer.subscribe(results.add);

    await time.advance(Duration.zero);
    observer.setOptions(
      QueryObserverOptions<int, int>(queryKey: key2, queryFn: (_) async => 2),
    );
    await time.advance(Duration.zero);
    unsubscribe();

    expect(results, hasLength(4));
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
    final observer = QueryObserver<Counted, Selected>(
      queryClient,
      QueryObserverOptions<Counted, Selected>(
        queryKey: key,
        queryFn: (_) async => const Counted(1),
        select: (data) => Selected(data.count),
      ),
    );

    QueryResult<Selected>? observed;
    final unsubscribe = observer.subscribe((result) => observed = result);
    await time.advance(Duration.zero);
    unsubscribe();

    expect(observed!.dataOrNull, const Selected(1));
  });

  testFakeAsync(
    'should be able to fetch with a selector using the fetch method',
    (time) async {
      final key = queryKey();
      final observer = QueryObserver<Counted, Selected>(
        queryClient,
        QueryObserverOptions<Counted, Selected>(
          queryKey: key,
          queryFn: (_) async => const Counted(1),
          select: (data) => Selected(data.count),
        ),
      );

      final result = await observer.refetch();
      expect(result.dataOrNull, const Selected(1));
    },
  );

  testFakeAsync('should run the selector again if the data changed', (
    time,
  ) async {
    final key = queryKey();
    var count = 0;
    final observer = QueryObserver<Counted, Selected>(
      queryClient,
      QueryObserverOptions<Counted, Selected>(
        queryKey: key,
        queryFn: (_) async => Counted(count),
        select: (data) {
          count++;
          return Selected(data.count);
        },
      ),
    );

    final result1 = await observer.refetch();
    final result2 = await observer.refetch();

    expect(count, 2);
    expect(result1.dataOrNull, const Selected(0));
    expect(result2.dataOrNull, const Selected(1));
  });

  testFakeAsync('should run the selector again if the selector changed', (
    time,
  ) async {
    final key = queryKey();
    var count = 0;
    final results = <QueryResult<Selected>>[];

    Future<Counted> queryFn(QueryFunctionContext _) async => const Counted(1);
    Selected select1(Counted data) {
      count++;
      return Selected(data.count);
    }

    Selected select2(Counted _) {
      count++;
      return const Selected(99);
    }

    final observer = QueryObserver<Counted, Selected>(
      queryClient,
      QueryObserverOptions<Counted, Selected>(
        queryKey: key,
        queryFn: queryFn,
        select: select1,
      ),
    );
    final unsubscribe = observer.subscribe(results.add);

    await time.advance(Duration.zero);
    observer.setOptions(
      QueryObserverOptions<Counted, Selected>(
        queryKey: key,
        queryFn: queryFn,
        select: select2,
      ),
    );
    await observer.refetch();
    unsubscribe();

    expect(count, 2);
    expect(results, hasLength(5));
    expect(results[0].status, QueryStatus.pending);
    expect(results[0].isFetching, isTrue);
    expect(results[0].dataOrNull, isNull);
    expect(results[1].status, QueryStatus.success);
    expect(results[1].isFetching, isFalse);
    expect(results[1].dataOrNull, const Selected(1));
    expect(results[2].status, QueryStatus.success);
    expect(results[2].isFetching, isFalse);
    expect(results[2].dataOrNull, const Selected(99));
    expect(results[3].status, QueryStatus.success);
    expect(results[3].isFetching, isTrue);
    expect(results[3].dataOrNull, const Selected(99));
    expect(results[4].status, QueryStatus.success);
    expect(results[4].isFetching, isFalse);
    expect(results[4].dataOrNull, const Selected(99));
  });

  testFakeAsync(
    'should not run the selector again if the data and selector did not change',
    (time) async {
      final key = queryKey();
      var count = 0;
      final results = <QueryResult<Selected>>[];

      Future<Counted> queryFn(QueryFunctionContext _) async => const Counted(1);
      Selected select(Counted data) {
        count++;
        return Selected(data.count);
      }

      final observer = QueryObserver<Counted, Selected>(
        queryClient,
        QueryObserverOptions<Counted, Selected>(
          queryKey: key,
          queryFn: queryFn,
          select: select,
        ),
      );
      final unsubscribe = observer.subscribe(results.add);

      await time.advance(Duration.zero);
      observer.setOptions(
        QueryObserverOptions<Counted, Selected>(
          queryKey: key,
          queryFn: queryFn,
          select: select,
        ),
      );
      await observer.refetch();
      unsubscribe();

      expect(count, 1);
      expect(results, hasLength(4));
      expect(results[0].status, QueryStatus.pending);
      expect(results[0].isFetching, isTrue);
      expect(results[0].dataOrNull, isNull);
      expect(results[1].status, QueryStatus.success);
      expect(results[1].isFetching, isFalse);
      expect(results[1].dataOrNull, const Selected(1));
      expect(results[2].status, QueryStatus.success);
      expect(results[2].isFetching, isTrue);
      expect(results[2].dataOrNull, const Selected(1));
      expect(results[3].status, QueryStatus.success);
      expect(results[3].isFetching, isFalse);
      expect(results[3].dataOrNull, const Selected(1));
    },
  );

  testFakeAsync(
    'should not run the selector again if the data did not change',
    (time) async {
      final key = queryKey();
      var count = 0;
      const shared = Counted(1);

      final observer = QueryObserver<Counted, Selected>(
        queryClient,
        QueryObserverOptions<Counted, Selected>(
          queryKey: key,
          queryFn: (_) async => shared,
          select: (data) {
            count++;
            return Selected(data.count);
          },
        ),
      );

      final result1 = await observer.refetch();
      final result2 = await observer.refetch();

      expect(count, 1);
      expect(result1.dataOrNull, const Selected(1));
      expect(result2.dataOrNull, const Selected(1));
    },
  );

  testFakeAsync(
    'should always run the selector again if selector throws an error and '
    'selector is not referentially stable',
    (time) async {
      final key = queryKey();
      final results = <QueryResult<Counted>>[];

      final observer = QueryObserver<Counted, Counted>(
        queryClient,
        QueryObserverOptions<Counted, Counted>(
          queryKey: key,
          queryFn: (_) => sleep(ms(10)).then((_) => Counted(1)),
          select: (_) => throw StateError('selector error'),
        ),
      );
      final unsubscribe = observer.subscribe(results.add);

      await time.advance(ms(10));
      unawaited(observer.refetch());
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
    },
  );

  testFakeAsync('should return stale data if selector throws an error', (
    time,
  ) async {
    final key = queryKey();
    final results = <QueryResult<String>>[];
    var shouldError = false;
    final error = StateError('select error');

    final observer = QueryObserver<int, String>(
      queryClient,
      QueryObserverOptions<int, String>(
        queryKey: key,
        retry: RetryOption.never,
        queryFn: (_) => sleep(ms(10)).then((_) => shouldError ? 2 : 1),
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
    unawaited(observer.refetch());
    await time.advance(ms(10));
    unsubscribe();

    expect(results[0].status, QueryStatus.pending);
    expect(results[0].isFetching, isTrue);
    expect(results[0].dataOrNull, isNull);
    expect(results[0].errorOrNull, isNull);

    expect(results[1].status, QueryStatus.success);
    expect(results[1].isFetching, isFalse);
    expect(results[1].dataOrNull, '1');

    expect(results[2].status, QueryStatus.success);
    expect(results[2].isFetching, isTrue);
    expect(results[2].dataOrNull, '1');

    expect(results[3].status, QueryStatus.error);
    expect(results[3].isFetching, isFalse);
    expect(results[3].dataOrNull, '1');
    expect(results[3].errorOrNull, same(error));
  });

  testFakeAsync(
    'should not leak the select error of the previous query into the result of '
    'a different query',
    (time) async {
      final key1 = queryKey();
      final key2 = queryKey();

      final observer = QueryObserver<Counted, Counted>(
        queryClient,
        QueryObserverOptions<Counted, Counted>(
          queryKey: key1,
          queryFn: (_) => sleep(ms(10)).then((_) => const Counted(1)),
          select: (_) => throw StateError('selector error'),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(10));
      expect(observer.result.status, QueryStatus.error);

      observer.setOptions(
        QueryObserverOptions<Counted, Counted>(
          queryKey: key2,
          queryFn: (_) => sleep(ms(10)).then((_) => const Counted(2)),
          select: (data) => data,
        ),
      );

      expect(observer.result.status, QueryStatus.pending);
      expect(observer.result.dataOrNull, isNull);
      expect(observer.result.errorOrNull, isNull);

      await time.advance(ms(10));
      unsubscribe();

      expect(observer.result.status, QueryStatus.success);
      expect(observer.result.dataOrNull, const Counted(2));
      expect(observer.result.errorOrNull, isNull);
    },
  );

  testFakeAsync('should clear the select error when the query is reset', (
    time,
  ) async {
    final key = queryKey();
    var shouldThrow = true;

    final observer = QueryObserver<Counted, Counted>(
      queryClient,
      QueryObserverOptions<Counted, Counted>(
        queryKey: key,
        queryFn: (_) => sleep(ms(10)).then((_) => const Counted(1)),
        select: (data) {
          if (shouldThrow) {
            throw StateError('selector error');
          }
          return data;
        },
      ),
    );
    final unsubscribe = observer.subscribe((_) {});
    await time.advance(ms(10));
    expect(observer.result.status, QueryStatus.error);

    shouldThrow = false;
    unawaited(queryClient.resetQueries(filters: QueryFilters(queryKey: key)));

    expect(observer.result.status, QueryStatus.pending);
    expect(observer.result.dataOrNull, isNull);
    expect(observer.result.errorOrNull, isNull);

    await time.advance(ms(10));
    unsubscribe();

    expect(observer.result.status, QueryStatus.success);
    expect(observer.result.dataOrNull, const Counted(1));
    expect(observer.result.errorOrNull, isNull);
  });

  testFakeAsync('should not trigger a fetch when subscribed and disabled', (
    time,
  ) async {
    final key = queryKey();
    var calls = 0;
    final observer = QueryObserver<String, String>(
      queryClient,
      QueryObserverOptions<String, String>(
        queryKey: key,
        queryFn: (_) async {
          calls++;
          return 'data';
        },
        enabled: Enabled.off,
      ),
    );
    final unsubscribe = observer.subscribe((_) {});
    await time.advance(Duration.zero);
    unsubscribe();
    expect(calls, 0);
  });

  testFakeAsync(
    'should not trigger a fetch when subscribed and disabled by callback',
    (time) async {
      final key = queryKey();
      var calls = 0;
      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async {
            calls++;
            return 'data';
          },
          enabled: Enabled.resolve((_) => false),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(Duration.zero);
      unsubscribe();
      expect(calls, 0);
    },
  );

  testFakeAsync('should not trigger a fetch when not subscribed', (time) async {
    final key = queryKey();
    var calls = 0;
    QueryObserver<String, String>(
      queryClient,
      QueryObserverOptions<String, String>(
        queryKey: key,
        queryFn: (_) async {
          calls++;
          return 'data';
        },
      ),
    );
    await time.advance(Duration.zero);
    expect(calls, 0);
  });

  testFakeAsync(
    'should be able to watch a query without defining a query function',
    (time) async {
      final key = queryKey();
      var calls = 0;
      var notifications = 0;

      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          enabled: Enabled.off,
        ),
      );
      final unsubscribe = observer.subscribe((_) => notifications++);

      await queryClient.fetchQuery(
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async {
            calls++;
            return 'data';
          },
        ),
      );
      await time.advance(Duration.zero);
      unsubscribe();

      expect(calls, 1);
      expect(notifications, 2);
    },
  );

  testFakeAsync('should accept unresolved query config in update function', (
    time,
  ) async {
    final key = queryKey();
    var calls = 0;
    final results = <QueryResult<String>>[];

    final observer = QueryObserver<String, String>(
      queryClient,
      QueryObserverOptions<String, String>(queryKey: key, enabled: Enabled.off),
    );
    final unsubscribe = observer.subscribe(results.add);

    observer.setOptions(
      QueryObserverOptions<String, String>(
        queryKey: key,
        enabled: Enabled.off,
        staleTime: const StaleDuration.of(Duration(milliseconds: 10)),
      ),
    );
    await queryClient.fetchQuery(
      QueryObserverOptions<String, String>(
        queryKey: key,
        queryFn: (_) async {
          calls++;
          return 'data';
        },
      ),
    );
    await time.advance(Duration.zero);
    unsubscribe();

    expect(calls, 1);
    expect(results, hasLength(2));
    expect(results[0].isStale, isFalse);
    expect(results[0].dataOrNull, isNull);
    expect(results[1].isStale, isFalse);
    expect(results[1].dataOrNull, 'data');
  });

  testFakeAsync('should be able to handle multiple subscribers', (time) async {
    final key = queryKey();
    var calls = 0;
    final results1 = <QueryResult<String>>[];
    final results2 = <QueryResult<String>>[];

    final observer = QueryObserver<String, String>(
      queryClient,
      QueryObserverOptions<String, String>(queryKey: key, enabled: Enabled.off),
    );
    final unsubscribe1 = observer.subscribe(results1.add);
    final unsubscribe2 = observer.subscribe(results2.add);

    await queryClient.fetchQuery(
      QueryObserverOptions<String, String>(
        queryKey: key,
        queryFn: (_) async {
          calls++;
          return 'data';
        },
      ),
    );
    await time.advance(Duration.zero);
    unsubscribe1();
    unsubscribe2();

    expect(calls, 1);
    expect(results1, hasLength(2));
    expect(results2, hasLength(2));
    expect(results1[0].dataOrNull, isNull);
    expect(results1[1].dataOrNull, 'data');
    expect(results2[0].dataOrNull, isNull);
    expect(results2[1].dataOrNull, 'data');
  });

  testFakeAsync('should stop retry when unsubscribing', (time) async {
    final key = queryKey();
    var count = 0;

    final observer = QueryObserver<String, String>(
      queryClient,
      QueryObserverOptions<String, String>(
        queryKey: key,
        queryFn: (_) {
          count++;
          return Future<String>.error('reject');
        },
        retry: const RetryOption.count(10),
        retryDelay: const RetryDelay.of(Duration(milliseconds: 50)),
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

      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async {
            count++;
            return 'data';
          },
          gcTime: const GcDuration.of(Duration.zero),
          refetchInterval: const RefetchInterval.every(
            Duration(milliseconds: 10),
          ),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      expect(count, 1);
      await time.advance(ms(10));
      expect(count, 2);
      unsubscribe();
      await time.advance(ms(10));
      expect(cache.find(key), isNull);
      expect(count, 2);
    },
  );

  testFakeAsync(
    'should refetch at the interval returned when refetchInterval is a function',
    (time) async {
      final key = queryKey();
      var count = 0;

      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async {
            count++;
            return 'data';
          },
          refetchInterval: RefetchInterval.resolve((_) => ms(10)),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      expect(count, 1);
      await time.advance(ms(10));
      expect(count, 2);
      unsubscribe();
    },
  );

  testFakeAsync(
    'should call refetchInterval with the query when it is a function',
    (time) async {
      final key = queryKey();
      final seen = <Object>[];

      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) => sleep(ms(10)).then((_) => 'data'),
          refetchInterval: RefetchInterval.resolve((query) {
            seen.add(query);
            return ms(10);
          }),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(10));

      expect(seen, isNotEmpty);
      expect(seen.every((query) => identical(query, cache.find(key))), isTrue);
      unsubscribe();
    },
  );

  test('should notify cache listeners when setOptions is called', () {
    final key = queryKey();

    final observer = QueryObserver<String, String>(
      queryClient,
      QueryObserverOptions<String, String>(queryKey: key, enabled: Enabled.off),
    );

    final events = <QueryCacheEvent>[];
    final unsubscribe = cache.subscribe(events.add);

    observer.setOptions(
      QueryObserverOptions<String, String>(
        queryKey: key,
        enabled: Enabled.off,
        refetchInterval: const RefetchInterval.every(
          Duration(milliseconds: 10),
        ),
      ),
    );

    expect(events, hasLength(1));
    final event = events.single as QueryObserverOptionsUpdated;
    expect(event.query, same(cache.find(key)));
    expect(event.observer, same(observer));

    unsubscribe();
  });

  test('should not be stale for disabled observers', () {
    final key = queryKey();
    final observer = QueryObserver<String, String>(
      queryClient,
      QueryObserverOptions<String, String>(queryKey: key, enabled: Enabled.off),
    );

    expect(observer.result.isStale, isFalse);
  });

  testFakeAsync('should allow staleTime as a function', (time) async {
    final key = queryKey();
    final observer = QueryObserver<Payload, Payload>(
      queryClient,
      QueryObserverOptions<Payload, Payload>(
        queryKey: key,
        queryFn: (_) => sleep(ms(5)).then((_) => const Payload('data', 20)),
        staleTime: StaleDuration.resolve((query) {
          final data = (query as Query<Payload>).state.data;
          return data == null
              ? StaleDuration.zero
              : StaleDuration.of(ms(data.staleTime));
        }),
      ),
    );

    final results = <QueryResult<Payload>>[];
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

  testFakeAsync('should not see queries as stale if staleTime is static', (
    time,
  ) async {
    final key = queryKey();
    final observer = QueryObserver<String, String>(
      queryClient,
      QueryObserverOptions<String, String>(
        queryKey: key,
        queryFn: (_) => sleep(ms(5)).then((_) => 'data'),
        staleTime: StaleDuration.static_,
      ),
    );

    expect(observer.result.isStale, isTrue, reason: 'no data is stale');

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

  test(
    'should return true from shouldFetchOnAppFocus when refetchOnAppFocus is '
    'ifStale',
    () {
      final key = queryKey();
      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async => 'data',
          refetchOnAppFocus: RefetchOn.ifStale,
        ),
      );

      expect(observer.shouldFetchOnAppFocus(), isTrue);
    },
  );

  test(
    'should return false from shouldFetchOnAppFocus when refetchOnAppFocus is '
    'never',
    () {
      final key = queryKey();
      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async => 'data',
          refetchOnAppFocus: RefetchOn.never,
        ),
      );

      expect(observer.shouldFetchOnAppFocus(), isFalse);
    },
  );

  testFakeAsync(
    'should return true from shouldFetchOnAppFocus when refetchOnAppFocus is '
    'always even if the query is fresh',
    (time) async {
      final key = queryKey();

      unawaited(
        queryClient.prefetchQuery(
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: (_) => sleep(ms(10)).then((_) => 'data'),
          ),
        ),
      );
      await time.advance(ms(10));

      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) => sleep(ms(10)).then((_) => 'data'),
          staleTime: StaleDuration.infinity,
          refetchOnAppFocus: RefetchOn.always,
        ),
      );

      expect(observer.shouldFetchOnAppFocus(), isTrue);
    },
  );

  test(
    'should return true from shouldFetchOnAppFocus when refetchOnAppFocus is a '
    'function returning ifStale',
    () {
      final key = queryKey();
      final seen = <Object>[];

      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async => 'data',
          refetchOnAppFocus: RefetchOn.resolve((query) {
            seen.add(query);
            return RefetchOn.ifStale;
          }),
        ),
      );

      expect(observer.shouldFetchOnAppFocus(), isTrue);
      expect(seen.single, same(cache.find(key)));
    },
  );

  test(
    'should return false from shouldFetchOnAppFocus when refetchOnAppFocus is a '
    'function returning never',
    () {
      final key = queryKey();
      final seen = <Object>[];

      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async => 'data',
          refetchOnAppFocus: RefetchOn.resolve((query) {
            seen.add(query);
            return RefetchOn.never;
          }),
        ),
      );

      expect(observer.shouldFetchOnAppFocus(), isFalse);
      expect(seen.single, same(cache.find(key)));
    },
  );

  testFakeAsync(
    'should return true from shouldFetchOnAppFocus when refetchOnAppFocus is a '
    'function returning always even if the query is fresh',
    (time) async {
      final key = queryKey();
      final seen = <Object>[];

      unawaited(
        queryClient.prefetchQuery(
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: (_) => sleep(ms(10)).then((_) => 'data'),
          ),
        ),
      );
      await time.advance(ms(10));

      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) => sleep(ms(10)).then((_) => 'data'),
          staleTime: StaleDuration.infinity,
          refetchOnAppFocus: RefetchOn.resolve((query) {
            seen.add(query);
            return RefetchOn.always;
          }),
        ),
      );

      expect(observer.shouldFetchOnAppFocus(), isTrue);
      expect(seen.single, same(cache.find(key)));
    },
  );

  test('should return the current query from currentQuery', () {
    final key = queryKey();
    final observer = QueryObserver<String, String>(
      queryClient,
      QueryObserverOptions<String, String>(
        queryKey: key,
        queryFn: (_) async => 'data',
      ),
    );

    expect(observer.currentQuery.queryKey, key);
  });

  testFakeAsync(
    'should not refetch in background if refetchIntervalInBackground is false',
    (time) async {
      final key = queryKey();
      var calls = 0;

      focusManager.setFocused(false);
      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async {
            calls++;
            return 'data';
          },
          refetchIntervalInBackground: false,
          refetchInterval: const RefetchInterval.every(
            Duration(milliseconds: 10),
          ),
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(30));

      expect(calls, 1);

      unsubscribe();
    },
  );

  testFakeAsync(
    'should not refetch on mount when retryOnMount is false and query is in '
    'error state',
    (time) async {
      final key = queryKey();
      var calls = 0;
      Future<String> queryFn(QueryFunctionContext _) {
        calls++;
        return Future<String>.error('error');
      }

      final firstObserver = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: queryFn,
          retry: RetryOption.never,
        ),
      );
      final unsubscribeFirst = firstObserver.subscribe((_) {});

      await time.advance(Duration.zero);

      expect(calls, 1);
      expect(queryClient.getQueryState<String>(key)!.status, QueryStatus.error);

      unsubscribeFirst();

      final secondObserver = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: queryFn,
          retry: RetryOption.never,
          retryOnMount: Enabled.off,
        ),
      );
      final unsubscribeSecond = secondObserver.subscribe((_) {});

      await time.advance(Duration.zero);

      expect(calls, 1, reason: 'no refetch');

      unsubscribeSecond();
    },
  );

  testFakeAsync(
    'should not refetchOnMount when set to always when staleTime is static',
    (time) async {
      final key = queryKey();
      var calls = 0;

      queryClient.setQueryData<String>(key, (_) => 'initial');

      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) async {
            calls++;
            return 'data';
          },
          staleTime: StaleDuration.static_,
          refetchOnMount: RefetchOn.always,
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(Duration.zero);
      expect(calls, 0);
      unsubscribe();
    },
  );

  testFakeAsync(
    'should not refetchOnAppFocus when staleTime is static and query has a '
    'background error',
    (time) async {
      final key = queryKey();
      var calls = 0;

      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) {
            calls++;
            return calls == 1
                ? Future<String>.value('data')
                : Future<String>.error(StateError('background error'));
          },
          staleTime: StaleDuration.static_,
          refetchOnAppFocus: RefetchOn.ifStale,
          retry: RetryOption.never,
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      await time.advance(Duration.zero);
      expect(calls, 1);
      expect(observer.result.dataOrNull, 'data');
      expect(observer.result.status, QueryStatus.success);

      await observer.refetch();
      await time.advance(Duration.zero);
      expect(calls, 2);
      expect(observer.result.status, QueryStatus.error);
      expect(observer.result.dataOrNull, 'data');

      focusManager.setFocused(false);
      focusManager.setFocused(true);
      await time.advance(Duration.zero);
      expect(calls, 2);

      unsubscribe();
    },
  );

  testFakeAsync(
    'should refetchOnAppFocus when query has a background error and staleTime '
    'is not static',
    (time) async {
      final key = queryKey();
      var calls = 0;

      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) {
            calls++;
            return switch (calls) {
              1 => Future<String>.value('data'),
              2 => Future<String>.error(StateError('background error')),
              _ => Future<String>.value('new data'),
            };
          },
          staleTime: const StaleDuration.of(Duration(milliseconds: 1000)),
          refetchOnAppFocus: RefetchOn.ifStale,
          retry: RetryOption.never,
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      await time.advance(Duration.zero);
      expect(calls, 1);
      expect(observer.result.dataOrNull, 'data');
      expect(observer.result.status, QueryStatus.success);

      await observer.refetch();
      await time.advance(Duration.zero);
      expect(calls, 2);
      expect(observer.result.status, QueryStatus.error);
      expect(observer.result.dataOrNull, 'data');

      focusManager.setFocused(false);
      focusManager.setFocused(true);
      await time.advance(Duration.zero);
      expect(calls, 3);

      unsubscribe();
    },
  );

  test('should return isEnabled depending on enabled being resolved', () {
    final key = queryKey();
    final observer = QueryObserver<String, String>(
      queryClient,
      QueryObserverOptions<String, String>(
        queryKey: key,
        queryFn: (_) async => 'data',
        enabled: Enabled.resolve((_) => false),
      ),
    );

    expect(observer.result.isEnabled, isFalse);
  });

  test('should return isEnabled as true per default', () {
    final key = queryKey();
    final observer = QueryObserver<String, String>(
      queryClient,
      QueryObserverOptions<String, String>(
        queryKey: key,
        queryFn: (_) async => 'data',
      ),
    );

    expect(observer.result.isEnabled, isTrue);
  });

  group('remount behaviour', () {
    testFakeAsync('should deduplicate calls to queryFn', (time) async {
      final key = queryKey();
      var calls = 0;

      final observer = QueryObserver<String, String>(
        queryClient,
        QueryObserverOptions<String, String>(
          queryKey: key,
          queryFn: (_) {
            calls++;
            return sleep(ms(50)).then((_) => 'data');
          },
        ),
      );

      final unsubscribe1 = observer.subscribe((_) {});

      await time.advance(ms(5));
      unsubscribe1();

      await time.advance(ms(5));
      final unsubscribe2 = observer.subscribe((_) {});

      await time.advance(ms(40));

      final state = queryClient.getQueryState<String>(key)!;
      expect(state.status, QueryStatus.success);
      expect(state.data, 'data');
      expect(calls, 1);

      unsubscribe2();
    });

    testFakeAsync(
      'should resolve with data when the cancel token was consumed',
      (time) async {
        final key = queryKey();
        var calls = 0;

        final observer = QueryObserver<String, String>(
          queryClient,
          QueryObserverOptions<String, String>(
            queryKey: key,
            queryFn: (context) {
              final _ = context.cancelToken;
              calls++;
              return sleep(ms(50)).then((_) => 'data');
            },
          ),
        );

        final unsubscribe1 = observer.subscribe((_) {});

        await time.advance(ms(5));
        unsubscribe1();

        await time.advance(ms(5));
        final unsubscribe2 = observer.subscribe((_) {});

        await time.advance(ms(50));

        final state = queryClient.getQueryState<String>(key)!;
        expect(state.status, QueryStatus.success);
        expect(state.data, 'data');
        expect(
          calls,
          2,
          reason: 'a consumed token means the first fetch really was aborted',
        );

        unsubscribe2();
      },
    );
  });
}
