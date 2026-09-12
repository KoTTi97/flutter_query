/// Bounded public-API sequences selected in core-confidence-acceptance.md.
/// Expectations are ownership, serialization and cache contracts, not snapshots
/// of implementation internals. Each generated case names its completion order.
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

const _orders = [
  [0, 1, 2],
  [0, 2, 1],
  [1, 0, 2],
  [1, 2, 0],
  [2, 0, 1],
  [2, 1, 0],
];

void main() {
  for (final reset in [false, true]) {
    for (final obsoleteFails in [false, true]) {
      for (final order in _orders) {
        testFakeAsync(
            'ownership: ${reset ? 'reset' : 'cancel'}, '
            'obsolete errors=$obsoleteFails, completion=$order', (time) async {
          final successes = <int>[];
          final client =
              testClient(queryCache: QueryCache(onSuccess: (data, _) {
            successes.add(data as int);
          }));
          final key = queryKey();
          final responses = <Completer<int>>[];
          final options = QueryOptions<int>(
            queryKey: key,
            queryFn: (_) {
              final response = Completer<int>();
              responses.add(response);
              return response.future;
            },
          );
          final operations = <Future<Object>>[];
          final boundaries = <Future<void>>[];
          for (var i = 0; i < 3; i++) {
            operations.add(client.query(options).then<Object>((value) => value,
                onError: (Object error) => error));
            if (i < 2) {
              boundaries.add(reset
                  ? client.resetQueries()
                  : client.cancelQueries(revert: false));
            }
          }
          final joined = client.query(options);
          await time.flushMicrotasks();
          expect(responses, hasLength(3));
          var latestCompleted = false;
          for (final i in order) {
            if (i < 2 && obsoleteFails) {
              responses[i].completeError(StateError('obsolete:$i'));
            } else {
              responses[i].complete(i + 1);
            }
            latestCompleted |= i == 2;
            await time.flushMicrotasks();
            expect(client.getQueryData<int>(key), latestCompleted ? 3 : null,
                reason: 'after response $i in $order');
            expect(client.isFetching(), latestCompleted ? 0 : 1);
            expect(successes, latestCompleted ? [3] : isEmpty);
          }
          expect(await joined, 3);
          final outcomes = await Future.wait(operations);
          // Reset cancels silently: immediate successors inherit its callers,
          // as the existing cancel/refetch handoff contract specifies. An
          // explicit non-silent cancel rejects the superseded callers.
          expect(outcomes.take(2),
              reset ? everyElement(3) : everyElement(isA<CancelledError>()));
          expect(outcomes.last, 3);
          await Future.wait(boundaries);
          client.clear();
          expect(time.pendingTimers, 0);
        });
      }
    }
  }

  for (final order in [_orders[0], _orders[4]]) {
    for (final firstFails in [false, true]) {
      testFakeAsync('scope: start=$order, removed owner fails=$firstFails',
          (time) async {
        final client = testClient()..mount();
        final transports = List.generate(3, (_) => Completer<int>());
        final callbacks = List.generate(3, (_) => Completer<void>());
        final started = <int>[];
        final settled = <(int?, bool, int, String?)>[];
        final options = MutationOptions<int, int, String>(
          scope: const MutationScope('confidence'),
          retry: RetryPolicy.never,
          onMutate: (v) => 'context:$v',
          mutationFn: (v) {
            started.add(v);
            return transports[v].future;
          },
          onSettled: (data, error, stack, variables, context) {
            settled.add((data, error != null, variables, context));
            return callbacks[variables].future;
          },
        );
        final mutations = List.generate(
            3,
            (_) => client.mutationCache
                .build(client, client.defaultMutationOptions(options)));
        final results = <Future<Object>>[];
        for (final i in order) {
          results.add(mutations[i]
              .execute(i)
              .then<Object>((v) => v, onError: (Object error) => error));
        }
        await time.flushMicrotasks();
        expect(started, [order.first]);
        client.onlineManager.setOnline(false);
        client.mutationCache.remove(mutations[order.first]);
        for (var position = 0; position < 3; position++) {
          final i = order[position];
          final fails = position == 0 && firstFails;
          if (fails) {
            transports[i].completeError(StateError('transport:$i'));
          } else {
            transports[i].complete(i);
          }
          await time.flushMicrotasks();
          expect(started, order.take(position + 1));
          expect(settled.last, (fails ? null : i, fails, i, 'context:$i'));
          // Transport settlement alone must not release its scope.
          expect(settled, hasLength(position + 1));
          callbacks[i].complete();
          await time.flushMicrotasks();
          if (position == 0) {
            expect(started, [i], reason: 'successor is still offline');
            client.onlineManager.setOnline(true);
            await time.flushMicrotasks();
          }
          expect(started, order.take(position < 2 ? position + 2 : 3));
        }
        final outcomes = await Future.wait(results);
        expect(outcomes.first, firstFails ? isA<StateError>() : order.first);
        expect(outcomes.skip(1), order.skip(1));
        client.unmount();
        client.clear();
        expect(client.onlineManager.hasListeners, isFalse);
        expect(client.focusManager.hasListeners, isFalse);
        expect(time.pendingTimers, 0);
      });
    }
  }

  testFakeAsync('selection: 20 placeholder and key-switch lifecycles',
      (time) async {
    final client = testClient();
    for (var cycle = 0; cycle < 20; cycle++) {
      final a = queryKey(), b = queryKey();
      final first = Completer<List<int>>();
      final second = Completer<List<int>>();
      final options = QuerySelectOptions<List<int>, int>(
        queryKey: a,
        queryFn: (_) => first.future,
        select: (raw) => raw.single * 2,
        placeholderData: const PlaceholderData.value([99]),
        staleTime: StaleTime.infinite,
      );
      final observer = client.observe<List<int>, int>(options);
      final off = observer.subscribe((_) {});
      expect(observer.currentResult.dataOrNull, 198);
      expect(observer.currentResult.isPlaceholderData, isTrue);
      expect(client.getQueryState<List<int>>(a)!.hasData, isFalse);
      first.complete([cycle]);
      await time.flushMicrotasks();
      expect(observer.currentResult.dataOrNull, cycle * 2);
      observer.setOptions(options.copyWith(
        queryKey: b,
        queryFn: (_) => second.future,
        placeholderData: const PlaceholderData.keepPrevious(),
      ));
      expect(observer.currentResult.dataOrNull, cycle * 2);
      expect(observer.currentResult.isPlaceholderData, isTrue);
      expect(client.getQueryState<List<int>>(b)!.hasData, isFalse);
      second.complete([cycle + 1]);
      await time.flushMicrotasks();
      expect(observer.currentResult.dataOrNull, (cycle + 1) * 2);
      expect(observer.currentResult.isPlaceholderData, isFalse);
      expect(client.getQueryData<List<int>>(a), [cycle]);
      expect(client.getQueryData<List<int>>(b), [cycle + 1]);
      observer.setOptions(options);
      expect(observer.currentResult.dataOrNull, cycle * 2);
      off();
      observer.destroy();
      client.clear();
      expect(time.pendingTimers, 0, reason: 'cycle $cycle');
    }
  });

  testFakeAsync('collections: 20 equal-result switches and subscription cycles',
      (time) async {
    final client = testClient();
    final oldHandles = <void Function()>[];
    for (var cycle = 0; cycle < 20; cycle++) {
      client.mount();
      final a = queryKey(), b = queryKey();
      client.setQueryData<List<int>>(a, [cycle]);
      client.setQueryData<List<int>>(b, [cycle]);
      final called = <QueryKey>[];
      QuerySelectOptions<List<int>, int> options(QueryKey key, int add) =>
          QuerySelectOptions(
            queryKey: key,
            enabled: Enabled.no,
            select: (raw) => raw.single + add,
            queryFn: (_) {
              called.add(key);
              return [cycle + 1];
            },
          );
      final collection = QueriesObserver<List<int>, int>(
          client, [options(a, 0), options(a, 10)]);
      var notifications = 0;
      void listener(List<QueryResult<int>> _) => notifications++;
      final off1 = collection.subscribe(listener);
      final off2 = collection.subscribe(listener);
      for (final old in oldHandles) {
        old();
      }
      off1();
      off1();
      collection.setQueries([options(b, 0), options(b, 10)]);
      final before = notifications;
      await collection.currentResult.first.refetch();
      expect(called, [b]);
      expect(collection.currentResult.map((r) => r.dataOrNull),
          [cycle + 1, cycle + 11]);
      expect(notifications, greaterThan(before));
      expect(client.getQueryData<List<int>>(a), [cycle]);
      expect(client.getQueryData<List<int>>(b), [cycle + 1]);
      off2();
      final stopped = notifications;
      client.setQueryData<List<int>>(b, [cycle + 2]);
      expect(notifications, stopped);
      collection.destroy();
      oldHandles.addAll([off1, off2]);
      client.unmount();
      client.clear();
      expect(client.focusManager.hasListeners, isFalse);
      expect(client.onlineManager.hasListeners, isFalse);
      expect(time.pendingTimers, 0, reason: 'cycle $cycle');
    }
  });

  testFakeAsync('nullable shared cache survives invalidation and offline retry',
      (time) async {
    final client = testClient()..mount();
    final key = queryKey();
    client.setQueryData<int?>(key, null);
    var calls = 0;
    final failed = Completer<int?>();
    final recovered = Completer<int?>();
    final options = QueryObserverOptions<int?>(
      queryKey: key,
      queryFn: (_) => ++calls == 1 ? failed.future : recovered.future,
      staleTime: StaleTime.infinite,
      retry: const RetryPolicy.times(1),
      retryDelay: RetryDelay.fixed(ms(10)),
    );
    final observers =
        List.generate(2, (_) => client.observe<int?, int?>(options));
    final offs = [for (final observer in observers) observer.subscribe((_) {})];
    expect(calls, 0);
    for (final observer in observers) {
      expect(observer.currentResult, isA<QuerySuccess<int?>>());
    }
    client.onlineManager.setOnline(false);
    await client.invalidateQueries();
    expect(calls, 0);
    expect(client.getQueryState<int?>(key)!.fetchStatus, FetchStatus.paused);
    client.onlineManager.setOnline(true);
    await time.flushMicrotasks();
    expect(calls, 1);
    client.onlineManager.setOnline(false);
    failed.completeError(StateError('temporary'));
    await time.advance(ms(20));
    expect(calls, 1);
    expect(client.getQueryState<int?>(key)!.hasData, isTrue);
    expect(client.getQueryState<int?>(key)!.data, isNull);
    expect(client.getQueryState<int?>(key)!.fetchStatus, FetchStatus.paused);
    client.onlineManager.setOnline(true);
    await time.flushMicrotasks();
    expect(calls, 2);
    recovered.complete(7);
    await time.flushMicrotasks();
    for (final observer in observers) {
      expect(observer.currentResult.dataOrNull, 7);
      expect(observer.currentResult.isStale, isFalse);
      expect(observer.currentResult.fetchStatus, FetchStatus.idle);
    }
    for (final off in offs) {
      off();
    }
    for (final observer in observers) {
      observer.destroy();
    }
    client.unmount();
    client.clear();
    expect(time.pendingTimers, 0);
  });

  testFakeAsync('infinite cancelled offline retry cannot corrupt next page',
      (time) async {
    final client = testClient()..mount();
    final key = queryKey();
    final calls = <int>[];
    client.setQueryData(
        key, InfiniteData<int, int>(pages: [10, 20], pageParams: [1, 2]));
    final observer = InfiniteQueryObserver<int, int, InfiniteData<int, int>>(
      client,
      InfiniteQueryObserverOptions(
        queryKey: key,
        initialPageParam: 1,
        enabled: Enabled.no,
        maxPages: 2,
        staleTime: StaleTime.infinite,
        retry: const RetryPolicy.times(1),
        retryDelay: RetryDelay.fixed(ms(10)),
        pageFn: (ctx) {
          ctx.signal;
          calls.add(ctx.pageParam);
          if (ctx.pageParam == 2) throw StateError('page 2 unavailable');
          return ctx.pageParam * 10;
        },
        getNextPageParam: (_, __, param, ___) => param + 1,
      ),
    );
    final off = observer.subscribe((_) {});
    final refetch = observer.refetch();
    await time.flushMicrotasks();
    expect(calls, [1, 2]);
    client.onlineManager.setOnline(false);
    await time.advance(ms(20));
    expect(observer.currentResult.fetchStatus, FetchStatus.paused);
    await client.cancelQueries();
    await refetch;
    final next = observer.fetchNextPage();
    expect(calls, [1, 2]);
    client.onlineManager.setOnline(true);
    await time.flushMicrotasks();
    final result = await next;
    expect(calls, [1, 2, 3]);
    expect(result.dataOrNull!.pages, [20, 30]);
    expect(result.dataOrNull!.pageParams, [2, 3]);
    expect(client.getInfiniteQueryData<int, int>(key), result.dataOrNull);
    expect(observer.isFetchingNextPage, isFalse);
    await time.advance(ms(100));
    expect(calls, [1, 2, 3]);
    off();
    observer.destroy();
    client.unmount();
    client.clear();
    expect(time.pendingTimers, 0);
  });
}
