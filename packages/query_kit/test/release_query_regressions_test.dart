import 'dart:async';
import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';
import 'test_utils.dart';

void main() {
  testFakeAsync('QER1 clear from failed event leaves no retry timer',
      (time) async {
    final client = testClient();
    client.queryCache.subscribe((event) {
      if (event is QueryUpdated && event.action is QueryFailedAction) {
        client.clear();
      }
    });
    final result = client.query<int>(QueryOptions(
      queryKey: queryKey(),
      queryFn: (_) => throw StateError('offline'),
      retry: const RetryPolicy.times(3),
      retryDelay: const RetryDelay.fixed(Duration(seconds: 30)),
    ));
    result.ignore();
    await time.flushMicrotasks();
    expect(client.queryCache.queries, isEmpty);
    await expectLater(result, throwsA(isA<CancelledError>()));
    expect(time.pendingTimers, 0);
  });

  testFakeAsync('QER2 clear from retry policy emits nothing after removal',
      (time) async {
    final client = testClient();
    final events = <QueryCacheEvent>[];
    client.queryCache.subscribe(events.add);
    final result = client.query<int>(QueryOptions(
      queryKey: queryKey(),
      queryFn: (_) => throw StateError('failure'),
      retry: RetryPolicy.when((_, __, ___) {
        client.clear();
        return true;
      }),
      retryDelay: const RetryDelay.fixed(Duration(seconds: 30)),
    ));
    result.ignore();
    await time.flushMicrotasks();
    await expectLater(result, throwsA(isA<CancelledError>()));
    final removed = events.indexWhere((event) => event is QueryRemoved);
    expect(events.skip(removed + 1), isEmpty);
    expect(time.pendingTimers, 0);
  });

  testFakeAsync('QER3 cancel then immediate fetch preserves successor status',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final gates = <Completer<int>>[];
    final options = QueryOptions<int>(
        queryKey: key,
        queryFn: (_) {
          final gate = Completer<int>();
          gates.add(gate);
          return gate.future;
        });
    client.query(options).ignore();
    final cancelled = client.cancelQueries(revert: false);
    final second = client.query(options);
    second.ignore();
    await cancelled;
    await time.flushMicrotasks();
    expect(gates.length, 2);
    expect(client.getQueryState<int>(key)!.fetchStatus, FetchStatus.fetching);
    expect(client.isFetching(), 1);
    gates.last.complete(2);
    expect(await second, 2);
    client.clear();
  });

  testFakeAsync('QER4 cache rejects readding a terminally removed query',
      (time) async {
    final client = testClient(
        defaultOptions: const DefaultOptions(
            queries: QueryDefaults(
                gcTime: GcTime.duration(Duration(milliseconds: 5)))));
    final key = queryKey();
    client.setQueryData<int>(key, 1);
    final query = client.queryCache.get<int>(key)!;
    client.queryCache.remove(query);
    expect(() => client.queryCache.add(query), throwsStateError);
    query.reset();
    await time.advance(ms(10));
    expect(client.queryCache.queries, isEmpty);
    client.clear();
  });

  testFakeAsync('QER5 initialData reentrancy keeps returned query canonical',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final result = client.query<int>(QueryOptions(
      queryKey: key,
      initialData: InitialData.compute(() {
        client.setQueryData<int>(key, 1);
        return 2;
      }),
      queryFn: (_) => 3,
    ));
    expect(await result, 3);
    expect(client.getQueryData<int>(key), 3);
    client.clear();
    expect(time.pendingTimers, 0);
  });

  testFakeAsync('QER6 removal from QueryAdded prevents detached fetch',
      (time) async {
    final client = testClient();
    var calls = 0;
    client.queryCache.subscribe((event) {
      if (event is QueryAdded) client.queryCache.remove(event.query);
    });
    final result = client.query<int>(
        QueryOptions(queryKey: queryKey(), queryFn: (_) => ++calls));
    result.ignore();
    await time.flushMicrotasks();
    expect(calls, 0);
    await expectLater(result, throwsA(isA<CancelledError>()));
    client.clear();
  });

  testFakeAsyncGuarded(
      'QER7 throwing reconnect policy does not block unrelated paused query',
      (time, errors) async {
    final client = testClient()..mount();
    final broken = client.observe<int, int>(QueryObserverOptions(
      queryKey: queryKey(),
      queryFn: (_) => 1,
      refetchOnReconnect: RefetchOn.when((_) => throw StateError('policy')),
    ));
    final unsubscribe = broken.subscribe((_) {});
    await time.flushMicrotasks();
    client.onlineManager.setOnline(false);
    var healthyCalls = 0;
    final key = queryKey();
    final healthy = client.query<int>(
        QueryOptions(queryKey: key, queryFn: (_) => ++healthyCalls));
    healthy.ignore();
    client.onlineManager.setOnline(true);
    await time.flushMicrotasks();
    expect(errors, hasLength(1));
    expect(healthyCalls, 1);
    expect(await healthy, 1);
    unsubscribe();
    client.unmount();
    client.clear();
  });

  testFakeAsync(
      'QER8 obsolete async request does not change current signal ownership',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final oldPreparation = Completer<void>();
    final newResponse = Completer<int>();
    var calls = 0;
    var oldSawCancellation = false;
    final observer = client.observe<int, int>(QueryObserverOptions(
      queryKey: key,
      queryFn: (context) async {
        if (++calls == 1) {
          await oldPreparation.future;
          oldSawCancellation = context.signal.isCancelled;
          return 1;
        }
        return newResponse.future;
      },
    ));
    final unsubscribe = observer.subscribe((_) {});
    await client.cancelQueries();
    observer.refetch().ignore();
    // Cancelled work resumes from an auth/preparation step after fetch 2 began.
    oldPreparation.complete();
    await time.flushMicrotasks();
    expect(oldSawCancellation, isTrue);
    unsubscribe();
    newResponse.complete(2);
    await time.flushMicrotasks();
    expect(client.getQueryData<int>(key), 2);
    client.clear();
  });

  testFakeAsync(
      'QER9 persistence build rejects null data for nonnullable query',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final options = QueryOptions<int>(
        queryKey: key, queryFn: (_) => 1, staleTime: StaleTime.static);
    expect(
        () => client.queryCache.build<int>(
            client, client.defaultQueryOptions(options),
            state: const QueryState<int>(
                hasData: true, status: QueryStatus.success)),
        throwsArgumentError);
    client.clear();
  });

  testFakeAsync('QER10 setState rejects null data for nonnullable query',
      (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<int>(key, 1);
    expect(
        () => client.queryCache.get<int>(key)!.setState(
            const QueryState<int>(hasData: true, status: QueryStatus.success)),
        throwsArgumentError);
    client.clear();
  });

  testFakeAsync(
      'QER11 rejected invalid state preserves ordinary reads and observers',
      (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<int>(key, 1);
    expect(
        () => client.queryCache.get<int>(key)!.setState(
            const QueryState<int>(hasData: true, status: QueryStatus.success)),
        throwsArgumentError);
    expect(client.getQueryData<int>(key), 1);
    final observer = client.observe<int, int>(
        QueryObserverOptions(queryKey: key, enabled: Enabled.no));
    expect(observer.currentResult.dataOrNull, 1);
    observer.destroy();
    client.clear();
  });

  testFakeAsyncGuarded(
      'QER12 a throwing manager listener does not strand client offline',
      (time, errors) async {
    final manager = OnlineManager();
    final removeBad = manager.subscribe((online) {
      if (online) throw StateError('listener');
    });
    final client = QueryClient(onlineManager: manager)..mount();
    manager.setOnline(false);
    var calls = 0;
    final result = client.query<int>(
        QueryOptions(queryKey: queryKey(), queryFn: (_) => ++calls));
    result.ignore();
    manager.setOnline(true);
    expect(errors, hasLength(1));
    await time.flushMicrotasks();
    // Reasserting the true state cannot redeliver the missed notification.
    manager.setOnline(true);
    await time.flushMicrotasks();
    expect(calls, 1);
    removeBad();
    client.unmount();
    client.clear();
  });

  testFakeAsync(
      'QER13 stale cancellation preserves deduplication and successor data',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final responses = <Completer<int>>[];
    final options = QueryOptions<int>(
        queryKey: key,
        queryFn: (_) {
          final response = Completer<int>();
          responses.add(response);
          return response.future;
        });
    client.query(options).ignore();
    final cancellation = client.cancelQueries(revert: false);
    final second = client.query(options);
    second.ignore();
    await cancellation;
    await time.flushMicrotasks();
    final third = client.query(options);
    third.ignore();
    expect(responses, hasLength(2),
        reason: 'the third caller must join the successor');
    responses[1].complete(2);
    expect(await second, 2);
    expect(await third, 2);
    responses[0].complete(1);
    await time.flushMicrotasks();
    expect(client.getQueryData<int>(key), 2,
        reason: 'the cancelled response cannot replace the successor');
    client.clear();
  });

  testFakeAsync('QER14 cached nullable null remains valid through persistence',
      (time) async {
    final client = testClient();
    final key = queryKey();
    client.queryCache.build<int?>(
        client, client.defaultQueryOptions(QueryOptions<int?>(queryKey: key)),
        state:
            const QueryState<int?>(hasData: true, status: QueryStatus.success));
    expect(
        await client.query<int?>(
            QueryOptions(queryKey: key, staleTime: StaleTime.static)),
        isNull);
    final observer = client.observe<int?, int?>(
        QueryObserverOptions(queryKey: key, enabled: Enabled.no));
    expect(observer.currentResult, isA<QuerySuccess<int?>>());
    observer.destroy();
    client.clear();
  });

  testFakeAsync(
      'QER15 awaiting cancellation before replacement remains healthy',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final pending = Completer<int>();
    client
        .query<int>(QueryOptions(queryKey: key, queryFn: (_) => pending.future))
        .ignore();
    await client.cancelQueries(revert: false);
    expect(
        await client.query<int>(QueryOptions(queryKey: key, queryFn: (_) => 2)),
        2);
    expect(client.getQueryData<int>(key), 2);
    client.clear();
    expect(time.pendingTimers, 0);
  });

  testFakeAsync(
      'QER16 imperative fetch preserves an observer nondefault retry policy',
      (time) async {
    final client = testClient();
    final key = queryKey();
    var fail = false;
    var calls = 0;
    int fetcher(QueryFunctionContext _) {
      calls++;
      if (fail) throw StateError('failure');
      return 1;
    }

    final observer = client.observe<int, int>(QueryObserverOptions(
      queryKey: key,
      queryFn: fetcher,
      retry: RetryPolicy.never,
    ));
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    await client.query<int>(QueryOptions(queryKey: key, queryFn: fetcher));
    fail = true;
    final before = calls;
    client.invalidateQueries().ignore();
    await time.advance(const Duration(seconds: 10));
    expect(calls - before, 1, reason: 'observer explicitly disabled retries');
    unsubscribe();
    client.clear();
  });

  testFakeAsyncGuarded(
      'QER17 throwing focus policy does not block unrelated paused retry',
      (time, errors) async {
    final client = testClient()..mount();
    final broken = client.observe<int, int>(QueryObserverOptions(
      queryKey: queryKey(),
      queryFn: (_) => 1,
      refetchOnWindowFocus:
          RefetchOn.when((_) => throw StateError('focus policy')),
    ));
    final unsubscribe = broken.subscribe((_) {});
    await time.flushMicrotasks();
    client.focusManager.setFocused(false);
    var calls = 0;
    final result = client.query<int>(QueryOptions(
      queryKey: queryKey(),
      queryFn: (_) {
        if (++calls == 1) throw StateError('retry');
        return calls;
      },
      retry: const RetryPolicy.times(1),
      retryDelay: const RetryDelay.fixed(Duration.zero),
    ));
    result.ignore();
    await time.advance(ms(1));
    expect(calls, 1);
    client.focusManager.setFocused(true);
    await time.flushMicrotasks();
    expect(errors, hasLength(1));
    expect(calls, 2);
    expect(await result, 2);
    unsubscribe();
    client.unmount();
    client.clear();
  });

  test('QER18 removing one duplicate registration skips only that registration',
      () {
    final manager = OnlineManager();
    var calls = 0;
    void listener(bool _) {
      calls++;
    }

    late void Function() removeSecond;
    manager.subscribe((_) => removeSecond());
    removeSecond = manager.subscribe(listener);
    final removeThird = manager.subscribe(listener);
    manager.setOnline(false);
    expect(calls, 1, reason: 'only the third registration remains subscribed');
    removeThird();
  });

  // QE-01 (pre-release verification, 2026-09-12): a cancel delivered
  // synchronously from the `fetch` notification while the fetch cannot start
  // (offline, `NetworkMode.online`) used to leave the query `paused` with no
  // retryer to release it — never collected, skipped by `refetchQueries`
  // when unobserved, deaf to reconnect. `Retryer.start` now returns at once
  // when the retryer was settled before it started.
  group('QE-01 cancel from the fetch notification while offline', () {
    QueryOptions<String> offlineOptions(QueryKey key) => QueryOptions<String>(
          queryKey: key,
          queryFn: (_) async => 'data',
          gcTime: GcTime.duration(ms(100)),
        );

    void Function() onFetchOf(
      QueryClient client,
      QueryKey key,
      void Function(Query<Object?> query) callback,
    ) {
      var fired = false;
      return client.queryCache.subscribe((event) {
        if (fired) return;
        if (event case QueryUpdated(:final query, action: QueryFetchAction())) {
          if (query.queryKey == key) {
            fired = true;
            callback(query);
          }
        }
      });
    }

    testFakeAsync('cancelQueries from a cache listener leaves the query idle',
        (time) async {
      final client = testClient()..mount();
      client.onlineManager.setOnline(false);
      final key = queryKey();
      final unsubscribe = onFetchOf(client, key, (_) {
        client.cancelQueries(filters: QueryFilters(queryKey: key)).ignore();
      });
      client.query<String>(offlineOptions(key)).ignore();
      await time.advance(ms(10));
      final query =
          client.queryCache.find(filters: QueryFilters(queryKey: key));
      expect(query!.state.fetchStatus, FetchStatus.idle,
          reason: 'nothing runs: the fetch was cancelled before it started');
      unsubscribe();
      client.unmount();
      client.clear();
    });

    testFakeAsync(
        'a cancelled never-started query is collected and refetchable',
        (time) async {
      final client = testClient()..mount();
      client.onlineManager.setOnline(false);
      final key = queryKey();
      final unsubscribe = onFetchOf(
        client,
        key,
        (query) => query.cancel(revert: true).ignore(),
      );
      client.query<String>(offlineOptions(key)).ignore();
      await time.advance(ms(10));
      unsubscribe();
      client.onlineManager.setOnline(true);
      await time.flushMicrotasks();
      final query =
          client.queryCache.find(filters: QueryFilters(queryKey: key));
      expect(query!.state.fetchStatus, FetchStatus.idle);
      await time.advance(ms(150));
      expect(client.queryCache.queries, isEmpty,
          reason: 'an idle, unobserved entry is collected after gcTime');
      client.unmount();
      client.clear();
    });

    testFakeAsync('an observer that cancels on paused does not stay paused',
        (time) async {
      final client = testClient()..mount();
      client.onlineManager.setOnline(false);
      final key = queryKey();
      final observer = client.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) async => 'data',
          gcTime: GcTime.duration(ms(100)),
        ),
      );
      final seen = <FetchStatus>[];
      var cancelled = false;
      final unsubscribe = observer.subscribe((result) {
        seen.add(result.fetchStatus);
        if (!cancelled && result.fetchStatus == FetchStatus.paused) {
          cancelled = true;
          client.cancelQueries(filters: QueryFilters(queryKey: key)).ignore();
        }
      });
      await time.advance(ms(10));
      expect(observer.currentResult.fetchStatus, FetchStatus.idle,
          reason: 'delivered: $seen');
      unsubscribe();
      client.unmount();
      client.clear();
    });
  });
}
