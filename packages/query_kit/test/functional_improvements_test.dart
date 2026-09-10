import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  testFakeAsync(
      'query collection can replace options during its first notification',
      (time) async {
    final client = testClient();
    final options =
        QueryObserverOptions<int, int>(queryKey: queryKey(), queryFn: (_) => 1);
    final observer = QueriesObserver<int, int>(client, [options]);
    var changed = false;
    final unsubscribe = observer.subscribe((_) {
      if (!changed) {
        changed = true;
        observer.setQueries([options]);
      }
    });
    await time.flushMicrotasks();
    unsubscribe();
    expect(observer.observers.single.hasListeners, isFalse);
    expect(client.queryCache.get<int>(options.queryKey)!.observersCount, 0);
    observer.destroy();
    client.clear();
  });

  testFakeAsyncGuarded(
      'throwing collection listeners do not skip other listeners',
      (time, errors) async {
    final client = testClient();
    final key = queryKey();
    final queries = QueriesObserver<int, int>(
        client, [QueryObserverOptions(queryKey: key, enabled: Enabled.no)]);
    queries.subscribe((_) => throw StateError('query listener'));
    var queryEvents = 0;
    queries.subscribe((_) => queryEvents++);
    client.setQueryData(key, 1);
    expect(queryEvents, 1);
    final mutations = MutationStateObserver<int>(client, select: (_) => 1);
    mutations.subscribe((_) => throw StateError('mutation listener'));
    var mutationEvents = 0;
    mutations.subscribe((_) => mutationEvents++);
    expect(
        await executeMutation<int, void, void>(
            client, MutationOptions(mutationFn: (_) => 1), null),
        1);
    expect(mutationEvents, 1);
    expect(errors, hasLength(2));
    queries.destroy();
    mutations.destroy();
    client.clear();
  });

  testFakeAsync('revalidation returns cached data and deduplicates refreshes',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final response = Completer<int>();
    var calls = 0;
    client.setQueryData(key, 1);
    final options = QueryOptions<int>(
        queryKey: key,
        queryFn: (_) {
          calls++;
          return response.future;
        });
    expect(await client.query(options, revalidateIfStale: true), 1);
    expect(await client.query(options, revalidateIfStale: true), 1);
    expect(calls, 1);
    expect(client.isFetching(), 1);
    response.complete(2);
    await time.flushMicrotasks();
    expect(client.getQueryData<int>(key), 2);
    expect(client.isFetching(), 0);
    client.clear();
  });

  testFakeAsync('revalidation waits for missing data; default waits for stale',
      (time) async {
    final client = testClient();
    for (final hasData in [false, true]) {
      final key = queryKey();
      final response = Completer<int>();
      if (hasData) client.setQueryData(key, 1);
      var settled = false;
      final future = client
          .query(
              QueryOptions<int>(queryKey: key, queryFn: (_) => response.future),
              revalidateIfStale: !hasData)
          .then((value) {
        settled = true;
        return value;
      });
      await time.flushMicrotasks();
      expect(settled, isFalse);
      response.complete(2);
      expect(await future, 2);
    }
    client.clear();
  });

  testFakeAsyncGuarded('nullable cached data survives a failed revalidation',
      (time, uncaught) async {
    var errors = 0;
    final client =
        testClient(queryCache: QueryCache(onError: (_, __, ___) => errors++));
    final key = queryKey();
    final failure = StateError('offline');
    client.setQueryData<int?>(key, null);
    expect(
        await client.query<int?>(
          QueryOptions(queryKey: key, queryFn: (_) => throw failure),
          revalidateIfStale: true,
        ),
        isNull);
    await time.flushMicrotasks();
    expect(client.getQueryState<int?>(key)!.hasData, isTrue);
    expect(client.getQueryState<int?>(key)!.error, same(failure));
    expect(errors, 1);
    expect(uncaught, isEmpty);
    client.clear();
  });

  testFakeAsync('fresh and static data do not revalidate', (time) async {
    final client = testClient();
    for (final staleTime in [
      const StaleTime.duration(Duration(minutes: 1)),
      StaleTime.static,
      StaleTime.infinite
    ]) {
      final key = queryKey();
      client.setQueryData(key, 1);
      if (staleTime == StaleTime.static) {
        await client.invalidateQueries(
            filters: QueryFilters(queryKey: key),
            refetchType: RefetchType.none);
      }
      expect(
          await client.query(
              QueryOptions<int>(
                queryKey: key,
                staleTime: staleTime,
                queryFn: (_) => throw StateError('must not fetch'),
              ),
              revalidateIfStale: true),
          1);
    }
    client.clear();
  });

  testFakeAsync('infinite revalidation retains pages and typed cache reads',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final response = Completer<int>();
    final data = InfiniteData<int, int>(pages: [1, 2], pageParams: [0, 1]);
    client.setQueryData(key, data);
    final calls = <int>[];
    final options = InfiniteQueryOptions<int, int>(
      queryKey: key,
      initialPageParam: 0,
      getNextPageParam: (_, __, param, ___) => param + 1,
      pageFn: (context) {
        calls.add(context.pageParam);
        return context.pageParam == 0 ? response.future : 20;
      },
    );
    expect(await client.infiniteQuery(options, revalidateIfStale: true),
        same(data));
    expect(client.getInfiniteQueryData<int, int>(key), same(data));
    expect(client.getInfiniteQueryData<int, int>(queryKey()), isNull);
    expect(() => client.getInfiniteQueryData<String, int>(key),
        throwsA(isA<QueryDataTypeError>()));
    response.complete(10);
    await time.flushMicrotasks();
    expect(client.getInfiniteQueryData<int, int>(key)!.pages, [10, 20]);
    expect(calls, [0, 1]);
    client.clear();
  });

  testFakeAsync('keepPrevious preserves placeholder semantics across keys',
      (time) async {
    final client = testClient();
    final oldKey = queryKey();
    final newKey = queryKey();
    client.setQueryData(oldKey, 1);
    final observer = QueryObserver<int, int>(
        client, QueryObserverOptions(queryKey: oldKey, enabled: Enabled.no));
    final unsubscribe = observer.subscribe((_) {});
    observer.setOptions(QueryObserverOptions(
        queryKey: newKey,
        enabled: Enabled.no,
        placeholderData: const PlaceholderData.keepPrevious()));
    expect(observer.currentResult.dataOrNull, 1);
    expect(observer.currentResult.isPlaceholderData, isTrue);
    expect(client.getQueryState<int>(newKey)!.hasData, isFalse);
    expect(
        const PlaceholderData<int?>.keepPrevious().provide(null, null).hasData,
        isFalse);
    unsubscribe();
    client.clear();
  });

  testFakeAsync('mutation selection tracks concurrent runs and filters',
      (time) async {
    final client = testClient();
    final other = testClient();
    final key = queryKey();
    final observer = MutationStateObserver<String?>(client,
        filters:
            MutationFilters(mutationKey: key, status: MutationStatus.pending),
        select: (mutation) => mutation.state.variables as String?);
    final events = <List<String?>>[];
    final unsubscribe = observer.subscribe(events.add);
    final a = Completer<int>();
    final b = Completer<int>();
    final first = executeMutation<int, String, void>(client,
        MutationOptions(mutationKey: key, mutationFn: (_) => a.future), 'a');
    final second = executeMutation<int, String, void>(client,
        MutationOptions(mutationKey: key, mutationFn: (_) => b.future), 'b');
    await time.flushMicrotasks();
    expect(observer.currentResult, ['a', 'b']);
    expect(() => observer.currentResult.add('x'), throwsUnsupportedError);
    final count = events.length;
    await executeMutation<int, String, void>(other,
        MutationOptions(mutationKey: key, mutationFn: (_) => 3), 'other');
    expect(events.length, count);
    a.complete(1);
    await first;
    expect(observer.currentResult, ['b']);
    b.complete(2);
    await second;
    expect(observer.currentResult, isEmpty);
    observer.setOptions(
        filters: MutationFilters(mutationKey: key),
        select: (mutation) => '${mutation.state.data}');
    expect(observer.currentResult, ['1', '2']);
    client.mutationCache.clear();
    expect(observer.currentResult, isEmpty);
    unsubscribe();
    expect(client.mutationCache.hasListeners, isFalse);
    observer.destroy();
    client.clear();
    other.clear();
  });

  testFakeAsync('equivalent mutation selections retain list identity',
      (time) async {
    final client = testClient();
    final response = Completer<int>();
    final observer =
        MutationStateObserver<List<String>>(client, select: (_) => ['same']);
    var events = 0;
    final unsubscribe = observer.subscribe((_) => events++);
    final future = executeMutation<int, void, void>(
        client, MutationOptions(mutationFn: (_) => response.future), null);
    await time.flushMicrotasks();
    final before = observer.currentResult;
    final count = events;
    response.complete(1);
    await future;
    expect(observer.currentResult, same(before));
    expect(events, count);
    unsubscribe();
    client.clear();
  });

  for (final seconds in [4, 5, 6]) {
    testFakeAsync('focus refetch threshold after $seconds seconds',
        (time) async {
      final focus = AppFocusManager(
          refetchMinBackgroundDuration: const Duration(seconds: 5));
      final client = QueryClient(focusManager: focus)..mount();
      var calls = 0;
      final observer = QueryObserver<int, int>(client,
          QueryObserverOptions(queryKey: queryKey(), queryFn: (_) => ++calls));
      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      focus.setFocused(false);
      await time.advance(Duration(seconds: seconds));
      focus.setFocused(true);
      expect(focus.isFocused(), isTrue);
      await time.flushMicrotasks();
      expect(calls, seconds < 5 ? 1 : 2);
      unsubscribe();
      client.unmount();
      client.clear();
    });
  }

  testFakeAsync(
      'short focus absence still resumes paused queries and mutations',
      (time) async {
    final focus = AppFocusManager(
        refetchMinBackgroundDuration: const Duration(seconds: 5));
    final client = QueryClient(focusManager: focus)..mount();
    var attempts = 0;
    final observer = QueryObserver<int, int>(
        client,
        QueryObserverOptions(
            queryKey: queryKey(),
            queryFn: (_) {
              if (++attempts == 1) throw StateError('retry');
              return 2;
            },
            retry: const RetryPolicy.times(1),
            retryDelay: RetryDelay.fixed(ms(100))));
    final unsubscribe = observer.subscribe((_) {});
    focus.setFocused(false);
    await time.advance(ms(200));
    expect(observer.currentResult.fetchStatus, FetchStatus.paused);
    // networkMode.always allows an initial attempt while unfocused; retry waits.
    var mutations = 0;
    final mutation = executeMutation<int, void, void>(
        client,
        MutationOptions(
            mutationFn: (_) {
              if (++mutations == 1) throw StateError('retry');
              return 1;
            },
            retry: const RetryPolicy.times(1),
            retryDelay: RetryDelay.fixed(ms(100))),
        null);
    await time.advance(ms(200));
    focus.setFocused(true);
    await time.flushMicrotasks();
    expect(await mutation, 1);
    expect(observer.currentResult.dataOrNull, 2);
    expect(attempts, 2);
    unsubscribe();
    client.unmount();
    client.clear();
  });

  testFakeAsync('a reconnect refetches whatever the focus threshold suppressed',
      (time) async {
    // The threshold gates focus only. `onOnline` never sees the flag, so a
    // reconnect inside a suppressed window must still refetch.
    final focus = AppFocusManager(
        refetchMinBackgroundDuration: const Duration(seconds: 5));
    final online = OnlineManager();
    final client = QueryClient(focusManager: focus, onlineManager: online)
      ..mount();
    var calls = 0;
    final observer = QueryObserver<int, int>(
        client,
        QueryObserverOptions(
            queryKey: queryKey(),
            queryFn: (_) => ++calls,
            refetchOnReconnect: RefetchOn.always));
    final unsubscribe = observer.subscribe((_) {});
    await time.flushMicrotasks();
    expect(calls, 1);

    focus.setFocused(false);
    online.setOnline(false);
    await time.advance(ms(200));
    online.setOnline(true);
    await time.flushMicrotasks();
    expect(calls, 2, reason: 'a reconnect is not gated by the focus threshold');

    // The short absence still suppresses the focus refetch itself.
    focus.setFocused(true);
    await time.flushMicrotasks();
    expect(calls, 2);
    expect(focus.shouldRefetchOnFocus, isFalse);

    unsubscribe();
    client.unmount();
    client.clear();
  });

  testFakeAsync('revalidation prefers stale data over an error, twice over',
      (time) async {
    final client = testClient();
    final key = queryKey();
    var calls = 0;
    final options = QueryOptions<int>(
        queryKey: key,
        queryFn: (_) {
          calls++;
          throw StateError('down');
        },
        staleTime: StaleTime.zero,
        retry: RetryPolicy.never);
    client.setQueryData<int>(key, 1);

    // First revalidation: cached data wins, the failure lands in the state.
    expect(await client.query(options, revalidateIfStale: true), 1);
    await time.flushMicrotasks();
    expect(calls, 1);
    final state = client.getQueryState<int>(key)!;
    expect(state.status, QueryStatus.error);
    expect(state.hasData, isTrue, reason: 'the stale data survives the error');

    // Already in error, still holding data: it resolves rather than throws.
    expect(await client.query(options, revalidateIfStale: true), 1);
    await time.flushMicrotasks();
    expect(calls, 2);

    // Without the flag the same call surfaces the error.
    await expectLater(client.query(options), throwsStateError);

    client.clear();
  });

  testFakeAsync('lazy seed timestamp runs only for actual seed data',
      (time) async {
    final client = testClient();
    final key = queryKey();
    var calls = 0;
    final timestamp = time.now.subtract(const Duration(minutes: 2));
    final options = QueryObserverOptions<int, int>(
        queryKey: key,
        enabled: Enabled.no,
        initialData: const InitialData.value(1),
        initialDataUpdatedAtCompute: () {
          calls++;
          return timestamp;
        },
        staleTime: const StaleTime.duration(Duration(minutes: 1)));
    final observer = QueryObserver<int, int>(client, options);
    observer.setOptions(options.copyWith());
    expect(calls, 1);
    expect(observer.currentResult.isStale, isFalse); // disabled observer
    expect(client.getQueryState<int>(key)!.dataUpdatedAt, timestamp);
    expect(observer.currentQuery.isStaleByTime(options.staleTime!), isTrue);
    final noSeed = QueryObserver<int, int>(
        client,
        options.copyWith(
            queryKey: queryKey(),
            initialData: InitialData.compute(() => null)));
    expect(calls, 1);
    final copy = options.copyWith(initialDataUpdatedAt: time.now);
    expect(copy.initialDataUpdatedAtCompute, isNull);
    expect(
        () => client.defaultQueryOptions(QueryOptions<int>(
            queryKey: queryKey(),
            initialDataUpdatedAt: timestamp,
            initialDataUpdatedAtCompute: () => timestamp)),
        throwsArgumentError);
    observer.destroy();
    noSeed.destroy();
    client.clear();
  });

  testFakeAsync('infinite lazy timestamp survives defaulting and copyWith',
      (time) async {
    final client = testClient();
    final key = queryKey();
    var calls = 0;
    final options =
        InfiniteQueryObserverOptions<int, int, InfiniteData<int, int>>(
            queryKey: key,
            pageFn: (_) => 1,
            initialPageParam: 0,
            getNextPageParam: (_, __, ___, ____) => null,
            initialData:
                InitialData.value(InfiniteData(pages: [1], pageParams: [0])),
            initialDataUpdatedAtCompute: () {
              calls++;
              return null;
            },
            enabled: Enabled.no);
    final observer = InfiniteQueryObserver<int, int, InfiniteData<int, int>>(
        client, options.copyWith());
    expect(calls, 1);
    expect(client.getQueryState<InfiniteData<int, int>>(key)!.dataUpdatedAt,
        time.now);
    observer.destroy();
    client.clear();
  });
}
