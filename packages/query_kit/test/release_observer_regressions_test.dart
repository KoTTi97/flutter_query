import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:query_kit/src/listener_registry.dart';
import 'package:query_kit/src/subscribable.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

class _ReviewRegistry extends Subscribable<void Function()> {
  void notify() {
    for (final listener in List.of(listeners)) {
      listener();
    }
  }
}

void main() {
  testFakeAsync(
      'OI17 registry skips a removed duplicate registration during delivery',
      (time) async {
    final registry = ListenerRegistry<void Function()>();
    final seen = <String>[];
    late void Function() removeFirstB;
    registry.add(() {
      seen.add('a');
      removeFirstB();
    });
    void b() => seen.add('b');
    removeFirstB = registry.add(b);
    registry.add(b);
    registry.notify((listener) => listener());
    registry.clear();
    expect(seen, ['a', 'b']);
  });

  testFakeAsyncGuarded(
      'OI18 registry isolates errors and skips distinct removed listeners',
      (time, errors) async {
    final registry = ListenerRegistry<void Function()>();
    final seen = <String>[];
    late void Function() remove;
    registry.add(() {
      remove();
      throw StateError('broken');
    });
    remove = registry.add(() => seen.add('removed'));
    registry.add(() => seen.add('healthy'));
    registry.notify((listener) => listener());
    registry.clear();
    expect(seen, ['healthy']);
    expect(errors, hasLength(1));
  });

  testFakeAsync('OI16 duplicate listener handle removes its own position',
      (time) async {
    final registry = _ReviewRegistry();
    final seen = <String>[];
    void a() => seen.add('a');
    void b() => seen.add('b');
    final first = registry.subscribe(a);
    final middle = registry.subscribe(b);
    final last = registry.subscribe(a);
    last();
    registry.notify();
    first();
    middle();
    expect(seen, ['a', 'b']);
  });

  testFakeAsync(
    'OI01 optimistic different key cannot contaminate active selector',
    (time) async {
      final client = testClient();
      final a = queryKey(), b = queryKey();
      client.setQueryData(a, 1);
      client.setQueryData(b, 2);
      String select(int value) => 'value=$value';
      final opts = QuerySelectOptions<int, String>(
        queryKey: a,
        select: select,
        enabled: Enabled.no,
      );
      final observer = QueryObserver<int, String>(client, opts);
      final unsubscribe = observer.subscribe((_) {});
      expect(
        observer.getOptimisticResult(opts.copyWith(queryKey: b)).dataOrNull,
        'value=2',
      );
      observer.setOptions(opts);
      final actual = observer.currentResult.dataOrNull;
      unsubscribe();
      client.clear();
      expect(actual, 'value=1');
    },
  );

  testFakeAsync(
    'OI02 equal result replacement must update per-index refetch target',
    (time) async {
      final client = testClient();
      final a = queryKey(), b = queryKey();
      client.setQueryData(a, 1);
      client.setQueryData(b, 1);
      final called = <String>[];
      final first = QueryObserverOptions<int>(
        queryKey: a,
        enabled: Enabled.no,
        queryFn: (_) {
          called.add('a');
          return 1;
        },
      );
      final second = QueryObserverOptions<int>(
        queryKey: b,
        enabled: Enabled.no,
        queryFn: (_) {
          called.add('b');
          return 1;
        },
      );
      final observer = QueriesObserver<int, int>(client, [first]);
      final unsubscribe = observer.subscribe((_) {});
      observer.setQueries([second]);
      await observer.currentResult.single.refetch();
      unsubscribe();
      client.clear();
      expect(called, ['b']);
    },
  );

  testFakeAsync(
    'OI03 collection reentrant update must not deliver obsolete final result',
    (time) async {
      final client = testClient();
      final key = queryKey();
      client.setQueryData(key, 0);
      final observer = QueriesObserver<int, int>(client, [
        QueryObserverOptions(queryKey: key, enabled: Enabled.no),
      ]);
      final first = observer.subscribe((results) {
        if (results.single.dataOrNull == 1) client.setQueryData(key, 2);
      });
      final received = <int?>[];
      final second = observer.subscribe(
        (results) => received.add(results.single.dataOrNull),
      );
      client.setQueryData(key, 1);
      final finalData = observer.currentResult.single.dataOrNull;
      first();
      second();
      client.clear();
      expect(
        received.last,
        finalData,
        reason: 'received=$received, final=$finalData',
      );
    },
  );

  testFakeAsync(
    'OI04 observer destroy within initial notification leaves no polling timer',
    (time) async {
      final client = testClient();
      var calls = 0;
      final observer = QueryObserver<int, int>(
        client,
        QueryObserverOptions(
          queryKey: queryKey(),
          queryFn: (_) => ++calls,
          refetchInterval: RefetchInterval.every(ms(10)),
        ),
      );
      observer.subscribe((_) => observer.destroy());
      await time.advance(ms(40));
      observer.destroy();
      client.clear();
      expect(calls, 1);
    },
  );

  testFakeAsync(
    'OI05 obsolete unsubscribe cannot remove new registration after destroy',
    (time) async {
      final client = testClient();
      final key = queryKey();
      final observer = QueryObserver<int, int>(
        client,
        QueryObserverOptions(queryKey: key, enabled: Enabled.no),
      );
      final received = <int?>[];
      void listener(QueryResult<int> r) => received.add(r.dataOrNull);
      final old = observer.subscribe(listener);
      observer.destroy();
      final current = observer.subscribe(listener);
      old();
      client.setQueryData(key, 1);
      final listening = observer.hasListeners;
      current();
      client.clear();
      expect(listening, isTrue);
      expect(received, [1]);
    },
  );

  testFakeAsync(
    'OI06 single observer reentrancy must not duplicate newer result',
    (time) async {
      final client = testClient();
      final key = queryKey();
      client.setQueryData(key, 0);
      final observer = QueryObserver<int, int>(
        client,
        QueryObserverOptions(queryKey: key, enabled: Enabled.no),
      );
      final first = observer.subscribe((result) {
        if (result.dataOrNull == 1) client.setQueryData(key, 2);
      });
      final received = <int?>[];
      final second = observer.subscribe((r) => received.add(r.dataOrNull));
      client.setQueryData(key, 1);
      first();
      second();
      client.clear();
      expect(
        received.toSet().length,
        received.length,
        reason: 'received=$received',
      );
    },
  );

  testFakeAsync(
    'OI07 optimistic infinite preview retains committed paging actions',
    (time) async {
      final client = testClient();
      final a = queryKey(), b = queryKey();
      client.setQueryData(
        a,
        InfiniteData<int, int>(pages: [1], pageParams: [1]),
      );
      client.setQueryData(
        b,
        InfiniteData<int, int>(pages: [9], pageParams: [9]),
      );
      final options = InfiniteQueryObserverOptions<int, int>(
        queryKey: a,
        initialPageParam: 1,
        enabled: Enabled.no,
        pageFn: (ctx) => ctx.pageParam,
        getNextPageParam: (page, _, __, ___) => page < 9 ? page + 1 : null,
      );
      final observer = InfiniteQueryObserver<int, int, InfiniteData<int, int>>(
        client,
        options,
      );
      final result = observer.getOptimisticInfiniteResult(
        options.copyWith(queryKey: b),
      );
      final next = observer.hasNextPage;
      observer.destroy();
      client.clear();
      expect(result.dataOrNull!.pages, [9]);
      expect(next, isTrue);
    },
  );

  testFakeAsyncGuarded(
    'OI08 throwing batched callback must not discard unrelated callbacks',
    (time, errors) async {
      final manager = NotifyManager();
      final seen = <String>[];
      manager.batch(() {
        manager.schedule(() => throw StateError('broken listener'));
        manager.schedule(() => seen.add('healthy listener'));
      });
      await time.flushMicrotasks();
      expect(errors, hasLength(1));
      expect(seen, ['healthy listener']);
    },
  );

  testFakeAsync(
    'OI09 infinite simultaneous opposite paging cancellation is coherent',
    (time) async {
      final client = testClient();
      final key = queryKey();
      client.setQueryData(
        key,
        InfiniteData<int, int>(pages: [1], pageParams: [1]),
      );
      final pending = <int, Completer<int>>{};
      final observer = InfiniteQueryObserver<int, int, InfiniteData<int, int>>(
        client,
        InfiniteQueryObserverOptions<int, int>(
          queryKey: key,
          initialPageParam: 1,
          enabled: Enabled.no,
          pageFn: (ctx) {
            ctx.signal;
            return (pending[ctx.pageParam] = Completer<int>()).future;
          },
          getNextPageParam: (_, __, p, ___) => p + 1,
          getPreviousPageParam: (_, __, p, ___) => p - 1,
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      final next = observer.fetchNextPage();
      final previous = observer.fetchPreviousPage();
      expect(observer.isFetchingNextPage, isFalse);
      expect(observer.isFetchingPreviousPage, isTrue);
      pending[0]!.complete(0);
      final completed = await previous;
      expect(completed.dataOrNull!.pages, [0, 1]);
      expect((await next).dataOrNull!.pages, [0, 1]);
      pending[2]!.complete(2);
      await time.flushMicrotasks();
      expect(observer.currentResult.dataOrNull!.pages, [0, 1]);
      expect(observer.isFetchingPreviousPage, isFalse);
      unsubscribe();
      client.clear();
    },
  );

  testFakeAsync(
    'OI10 infinite refetch retry keeps completed progress with maxPages',
    (time) async {
      final client = testClient();
      final calls = <int>[];
      var failed = false;
      final pending = client.infiniteQuery<int, int>(
        InfiniteQueryOptions(
          queryKey: queryKey(),
          initialPageParam: 1,
          pages: 4,
          maxPages: 2,
          retry: RetryPolicy.times(1),
          retryDelay: RetryDelay.fixed(ms(1)),
          pageFn: (ctx) {
            calls.add(ctx.pageParam);
            if (ctx.pageParam == 3 && !failed) {
              failed = true;
              throw StateError('transient');
            }
            return ctx.pageParam;
          },
          getNextPageParam: (_, __, p, ___) => p + 1,
        ),
      );
      await time.advance(ms(1));
      final data = await pending;
      client.clear();
      expect(data.pages, [3, 4]);
      expect(data.pageParams, [3, 4]);
      expect(calls, [1, 2, 3, 3, 4]);
    },
  );

  testFakeAsync(
    'OI11 consumed signal stops remaining pages after explicit cancellation',
    (time) async {
      final client = testClient();
      final key = queryKey();
      final page = Completer<int>();
      final called = <int>[];
      final observer = InfiniteQueryObserver<int, int, InfiniteData<int, int>>(
        client,
        InfiniteQueryObserverOptions<int, int>(
          queryKey: key,
          initialPageParam: 1,
          enabled: Enabled.no,
          initialData: InitialData.value(
            InfiniteData<int, int>(pages: [1, 2, 3], pageParams: [1, 2, 3]),
          ),
          pageFn: (ctx) {
            called.add(ctx.pageParam);
            ctx.signal;
            return page.future;
          },
          getNextPageParam: (_, __, p, ___) => p + 1,
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      final fetch = observer.refetch();
      await observer.currentQuery.cancel(revert: true);
      page.complete(10);
      await fetch;
      await time.flushMicrotasks();
      expect(called, [1]);
      expect(observer.currentResult.dataOrNull!.pages, [1, 2, 3]);
      unsubscribe();
      client.clear();
    },
  );

  testFakeAsync(
    'OI12 stale deadline and disabled polling transition work at fractional ms',
    (time) async {
      final client = testClient();
      var calls = 0;
      final options = QueryObserverOptions<int>(
        queryKey: queryKey(),
        queryFn: (_) => ++calls,
        initialData: const InitialData.value(0),
        staleTime: const StaleTime.duration(Duration(microseconds: 1500)),
        refetchInterval: RefetchInterval.every(ms(10)),
      );
      final observer = QueryObserver<int, int>(client, options);
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(1));
      expect(observer.currentResult.isStale, isFalse);
      await time.advance(ms(1));
      expect(observer.currentResult.isStale, isTrue);
      observer.setOptions(options.copyWith(enabled: Enabled.no));
      await time.advance(ms(30));
      expect(calls, 0);
      observer.setOptions(options);
      await time.advance(ms(20));
      expect(calls, 3);
      unsubscribe();
      final baseline = calls;
      await time.advance(ms(30));
      expect(calls, baseline);
      client.clear();
    },
  );

  testFakeAsync(
    'OI13 dropping widening select over placeholder must accept raw subtype',
    (time) async {
      final client = testClient();
      final key = queryKey();
      final observer = QueryObserver<int, num>(
        client,
        QuerySelectOptions<int, num>(
          queryKey: key,
          enabled: Enabled.no,
          placeholderData: const PlaceholderData.value(1),
          select: (v) => v + 0.5,
        ),
      );
      expect(observer.currentResult.dataOrNull, 1.5);
      Object? error;
      try {
        observer.setOptions(
          QueryObserverOptions<int>(
            queryKey: key,
            enabled: Enabled.no,
            placeholderData: const PlaceholderData.value(2),
          ),
        );
      } catch (caught) {
        error = caught;
      }
      final data = observer.currentResult.dataOrNull;
      observer.destroy();
      client.clear();
      expect(error, isNull);
      expect(data, 2);
    },
  );

  testFakeAsync(
    'OI14 rejected query key type switch must preserve usable old options',
    (time) async {
      final client = testClient();
      final a = queryKey(), b = queryKey();
      client.setQueryData(b, 'wrong type');
      final initial = QueryObserverOptions<int>(
        queryKey: a,
        enabled: Enabled.no,
        queryFn: (_) => 7,
      );
      final observer = QueryObserver<int, int>(client, initial);
      expect(
        () => observer.setOptions(initial.copyWith(queryKey: b)),
        throwsA(isA<QueryDataTypeError>()),
      );
      final optionsKey = observer.options.queryKey;
      Object? refetchError;
      QueryResult<int>? refetched;
      try {
        refetched = await observer.refetch();
      } catch (caught) {
        refetchError = caught;
      }
      observer.destroy();
      client.clear();
      expect(optionsKey, a, reason: 'refetch also threw $refetchError');
      expect(refetched?.dataOrNull, 7);
    },
  );

  testFakeAsync(
    'OI15 collection repeated key occurrences preserve separate selection',
    (time) async {
      final client = testClient();
      final key = queryKey();
      client.setQueryData(key, 2);
      final observer = QueriesObserver<int, int>(client, [
        QuerySelectOptions<int, int>(
          queryKey: key,
          enabled: Enabled.no,
          select: (v) => v + 1,
        ),
        QuerySelectOptions<int, int>(
          queryKey: key,
          enabled: Enabled.no,
          select: (v) => v * 10,
        ),
      ]);
      final unsubscribe = observer.subscribe((_) {});
      client.setQueryData(key, 3);
      expect(observer.currentResult.map((r) => r.dataOrNull), [4, 30]);
      expect(identical(observer.observers[0], observer.observers[1]), isFalse);
      unsubscribe();
      client.clear();
    },
  );

  // OB-01 (pre-release verification, 2026-09-12): the selection memo did not
  // know which query it was computed for, so after a key change a throwing
  // `select` reported the *previous* key's selection as this key's
  // `staleData`, with `isRefetchError` true. Upstream keeps `#selectResult`
  // the same way; the port stamps both memos with their query. A selector
  // swap on the same key still reports the old selection as stale data of
  // that query, as the ported "should return stale data if selector throws"
  // requires.
  group('OB-01 a throwing select after a key change', () {
    QuerySelectOptions<({int id, String? city}), String> cityOf(
      QueryKey key, {
      Enabled enabled = Enabled.no,
      QueryFn<({int id, String? city})>? queryFn,
    }) =>
        QuerySelectOptions<({int id, String? city}), String>(
          queryKey: key,
          enabled: enabled,
          queryFn: queryFn,
          staleTime: StaleTime.infinite,
          select: (user) => user.city!,
        );

    testFakeAsync('reports a loading error of the new key, not stale data',
        (time) async {
      final client = testClient();
      final a = queryKey();
      final b = queryKey();
      client.setQueryData<({int id, String? city})>(a, (id: 1, city: 'Berlin'));
      client.setQueryData<({int id, String? city})>(b, (id: 2, city: null));
      final observer =
          client.observe<({int id, String? city}), String>(cityOf(a));
      final unsubscribe = observer.subscribe((_) {});
      expect(observer.currentResult.dataOrNull, 'Berlin');

      observer.setOptions(cityOf(b));
      final result = observer.currentResult;
      expect(result, isA<QueryError<String>>());
      final error = result as QueryError<String>;
      expect(error.hasStaleData, isFalse,
          reason: 'staleData=${error.staleData}');
      expect(error.isLoadingError, isTrue);
      expect(error.isRefetchError, isFalse);
      unsubscribe();
      client.clear();
    });

    testFakeAsync('the same through a preview of the other key', (time) async {
      final client = testClient();
      final a = queryKey();
      final b = queryKey();
      client.setQueryData<({int id, String? city})>(a, (id: 1, city: 'Berlin'));
      client.setQueryData<({int id, String? city})>(b, (id: 2, city: null));
      final observer =
          client.observe<({int id, String? city}), String>(cityOf(a));
      final unsubscribe = observer.subscribe((_) {});

      final preview = observer.getOptimisticResult(cityOf(b));
      expect(preview, isA<QueryError<String>>());
      expect((preview as QueryError<String>).hasStaleData, isFalse,
          reason: 'preview staleData=${preview.staleData}');

      observer.setOptions(cityOf(a));
      expect(observer.currentResult.dataOrNull, 'Berlin',
          reason: 'committing key A again reuses its own selection');
      unsubscribe();
      client.clear();
    });

    testFakeAsync('a selector swap on the same key keeps its stale data',
        (time) async {
      final client = testClient();
      final key = queryKey();
      client.setQueryData<int>(key, 1);
      final observer = client.observe<int, String>(
        QuerySelectOptions<int, String>(
          queryKey: key,
          enabled: Enabled.no,
          select: (v) => 'v$v',
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      expect(observer.currentResult.dataOrNull, 'v1');
      observer.setOptions(
        QuerySelectOptions<int, String>(
          queryKey: key,
          enabled: Enabled.no,
          select: (_) => throw StateError('v2 cannot'),
        ),
      );
      final result = observer.currentResult as QueryError<String>;
      expect(result.staleData, 'v1');
      expect(result.isRefetchError, isTrue);
      unsubscribe();
      client.clear();
    });
  });
}
