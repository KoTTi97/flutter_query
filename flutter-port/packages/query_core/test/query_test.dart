import 'dart:async';

import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Counts how often the query asks this observer to refetch.
///
/// Upstream spies on `observer.refetch`; Dart has no runtime spies, so the
/// interception is a subclass.
class _SpyObserver extends QueryObserver<String, String> {
  _SpyObserver(super.client, super.options);

  int quietRefetches = 0;

  @override
  void refetchQuietly() {
    quietRefetches++;
    super.refetchQuietly();
  }
}

/// Port of `query/packages/query-core/src/__tests__/query.test.tsx`.
///
/// Six upstream cases have no counterpart here (hydration, undefined query
/// data, server-side retry, JSON-serializability logging, persister, non-array
/// query keys) — see PORTING_NOTES.md for why each one is out of scope.
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

  QueryObserverOptions<String, String> options(
    QueryKey key, {
    QueryFn<String>? queryFn,
    GcDuration? gcTime,
    StaleDuration? staleTime,
    RetryOption? retry,
    RetryDelay? retryDelay,
    Enabled? enabled,
    String? Function()? initialData,
    DateTime? Function()? initialDataUpdatedAt,
    Object? meta,
    String Function(String? oldData, String newData)? structuralSharing,
  }) => QueryObserverOptions<String, String>(
    queryKey: key,
    queryFn: queryFn,
    gcTime: gcTime,
    staleTime: staleTime,
    retry: retry,
    retryDelay: retryDelay,
    enabled: enabled,
    initialData: initialData,
    initialDataUpdatedAt: initialDataUpdatedAt,
    meta: meta,
    structuralSharing: structuralSharing,
  );

  testFakeAsync('should use the longest garbage collection time it has seen', (
    time,
  ) async {
    final key = queryKey();
    await queryClient.prefetchQuery(
      options(
        key,
        queryFn: (_) async => 'data',
        gcTime: const GcDuration.of(Duration(milliseconds: 100)),
      ),
    );
    await queryClient.prefetchQuery(
      options(
        key,
        queryFn: (_) async => 'data',
        gcTime: const GcDuration.of(Duration(milliseconds: 200)),
      ),
    );
    await queryClient.prefetchQuery(
      options(
        key,
        queryFn: (_) async => 'data',
        gcTime: const GcDuration.of(Duration(milliseconds: 10)),
      ),
    );

    expect(
      queryCache.find(key)!.gcTime,
      const GcDuration.of(Duration(milliseconds: 200)),
    );
  });

  testFakeAsync(
    'should continue retry after focus regain and resolve all promises',
    (time) async {
      final key = queryKey();

      // Make the app unfocused.
      focusManager.setFocused(false);

      var count = 0;
      String? result;

      final promise = queryClient.fetchQuery(
        options(
          key,
          queryFn: (_) async {
            count++;
            if (count == 3) {
              return 'data$count';
            }
            throw StateError('error$count');
          },
          retry: const RetryOption.count(3),
          retryDelay: const RetryDelay.of(Duration(milliseconds: 1)),
        ),
      );
      unawaited(promise.then((data) => result = data));

      expect(result, isNull);

      // Check that the query really is paused.
      await time.advance(ms(50));
      expect(result, isNull);

      focusManager.setFocused(null);

      expect(result, isNull, reason: 'the resume has not run yet');

      await time.advance(ms(50));
      expect(result, 'data3');
    },
  );

  testFakeAsync(
    'should continue retry after reconnect and resolve all promises',
    (time) async {
      final key = queryKey();

      onlineManager.setOnline(false);

      var count = 0;
      String? result;

      final promise = queryClient.fetchQuery(
        options(
          key,
          queryFn: (_) async {
            count++;
            if (count == 3) {
              return 'data$count';
            }
            throw StateError('error$count');
          },
          retry: const RetryOption.count(3),
          retryDelay: const RetryDelay.of(Duration(milliseconds: 1)),
        ),
      );
      unawaited(promise.then((data) => result = data));

      expect(result, isNull);

      await time.advance(ms(1));
      expect(result, isNull);

      onlineManager.setOnline(true);
      queryCache.onOnline();

      expect(result, isNull);

      await time.advance(ms(2));
      expect(result, 'data3');
    },
  );

  testFakeAsync(
    'should throw a CancelledError when a paused query is cancelled',
    (time) async {
      final key = queryKey();

      focusManager.setFocused(false);
      var count = 0;

      final promise = queryClient.fetchQuery(
        options(
          key,
          queryFn: (_) async {
            count++;
            throw StateError('error$count');
          },
          retry: const RetryOption.count(3),
          retryDelay: const RetryDelay.of(Duration(milliseconds: 1)),
        ),
      );
      final rejects = expectLater(promise, throwsA(isA<CancelledError>()));

      final query = queryCache.find(key)!;

      await time.advance(ms(50));
      expect(query.state.fetchStatus, FetchStatus.paused);

      unawaited(query.cancel());

      await rejects;
    },
  );

  testFakeAsync(
    'should cancel a paused initial fetch when the last observer unsubscribes',
    (time) async {
      final key = queryKey();
      onlineManager.setOnline(false);
      var count = 0;

      final observer = QueryObserver<String, String>(
        queryClient,
        options(
          key,
          queryFn: (context) async {
            final _ = context.cancelToken;
            count++;
            await sleep(ms(10));
            return 'data$count';
          },
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      final query = queryCache.find(key)!;

      expect(query.state.fetchStatus, FetchStatus.paused);
      expect(query.state.status, QueryStatus.pending);

      unsubscribe();

      expect(query.state.fetchStatus, FetchStatus.idle);
      expect(query.state.status, QueryStatus.pending);

      onlineManager.setOnline(true);
      queryCache.onOnline();

      await time.advance(ms(11));

      expect(query.state.fetchStatus, FetchStatus.idle);
      expect(query.state.status, QueryStatus.pending);
      expect(count, 0);
    },
  );

  testFakeAsync(
    'should not throw a CancelledError when fetchQuery is in progress and the '
    'last observer unsubscribes when the cancel token is consumed',
    (time) async {
      final key = queryKey();

      final observer = QueryObserver<String, String>(
        queryClient,
        options(key, queryFn: (_) => sleep(ms(100)).then((_) => 'data')),
      );

      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(100));

      expect(queryCache.find(key)!.state.data, 'data');

      final promise = queryClient.fetchQuery(
        options(
          key,
          queryFn: (context) {
            final _ = context.cancelToken;
            return sleep(ms(100)).then((_) => 'data2');
          },
        ),
      );

      // Ensure the fetch is in progress.
      await time.advance(ms(10));

      // Unsubscribe while the fetch is in progress.
      unsubscribe();

      await time.advance(ms(90));

      // The fetch reverts rather than failing, so the caller gets the data that
      // was already there.
      await expectLater(promise, completion('data'));
      expect(queryCache.find(key)!.state.data, 'data');
    },
  );

  testFakeAsync('should provide context to queryFn', (time) async {
    final key = queryKey();
    final contexts = <QueryFunctionContext>[];

    unawaited(
      queryClient.prefetchQuery(
        options(
          key,
          queryFn: (context) async {
            contexts.add(context);
            return 'data';
          },
        ),
      ),
    );

    expect(contexts, hasLength(1));
    expect(contexts.single.queryKey, key);
    expect(contexts.single.cancelToken, isA<QueryCancelToken>());
    await time.flushMicrotasks();
  });

  testFakeAsync(
    'should continue if cancellation is not supported and the cancel token is '
    'not consumed',
    (time) async {
      final key = queryKey();

      unawaited(
        queryClient.prefetchQuery(
          options(key, queryFn: (_) => sleep(ms(100)).then((_) => 'data')),
        ),
      );

      await time.advance(ms(10));

      // Subscribe and unsubscribe to simulate the last observer leaving.
      final observer = QueryObserver<String, String>(
        queryClient,
        options(key, enabled: Enabled.off),
      );
      observer.subscribe((_) {})();

      await time.advance(ms(90));

      final query = queryCache.find(key)!;
      expect(query.state.data, 'data');
      expect(query.state.status, QueryStatus.success);
      expect(query.state.dataUpdateCount, 1);
    },
  );

  testFakeAsync(
    'should not continue when last observer unsubscribed if the cancel token '
    'was consumed',
    (time) async {
      final key = queryKey();

      unawaited(
        queryClient.prefetchQuery(
          options(
            key,
            queryFn: (context) {
              final token = context.cancelToken;
              return sleep(
                ms(100),
              ).then((_) => token.isCancelled ? 'aborted' : 'data');
            },
          ),
        ),
      );

      await time.advance(ms(10));

      final observer = QueryObserver<String, String>(
        queryClient,
        options(key, enabled: Enabled.off),
      );
      observer.subscribe((_) {})();

      await time.advance(ms(90));

      final query = queryCache.find(key)!;
      expect(query.state.data, isNull);
      expect(query.state.status, QueryStatus.pending);
      expect(query.state.fetchStatus, FetchStatus.idle);
    },
  );

  testFakeAsync('should provide a cancel token to the queryFn that reports the '
      'cancellation state', (time) async {
    final key = queryKey();
    QueryCancelToken? seenToken;
    var firstListener = 0;
    var secondListener = 0;

    final promise = queryClient.fetchQuery(
      options(
        key,
        queryFn: (context) async {
          final token = context.cancelToken;
          seenToken = token;
          token.addListener((_) => firstListener++);
          token.addListener((_) => secondListener++);
          await sleep(ms(10));
          throw StateError('failed');
        },
        retry: const RetryOption.count(3),
        retryDelay: const RetryDelay.of(Duration(milliseconds: 10)),
      ),
    );
    final rejects = expectLater(promise, throwsA(isA<CancelledError>()));

    final query = queryCache.find(key)!;

    expect(seenToken, isNotNull, reason: 'the queryFn ran synchronously');
    expect(seenToken!.isCancelled, isFalse);
    expect(firstListener, 0);
    expect(secondListener, 0);

    unawaited(query.cancel());

    await time.advance(ms(100));

    expect(seenToken!.isCancelled, isTrue);
    expect(firstListener, 1);
    expect(secondListener, 1);
    await rejects;
  });

  testFakeAsync('should not continue if explicitly cancelled', (time) async {
    final key = queryKey();
    var calls = 0;

    final promise = queryClient.fetchQuery(
      options(
        key,
        queryFn: (_) async {
          calls++;
          await sleep(ms(10));
          throw StateError('failed');
        },
        retry: const RetryOption.count(3),
        retryDelay: const RetryDelay.of(Duration(milliseconds: 10)),
      ),
    );
    final rejects = expectLater(promise, throwsA(isA<CancelledError>()));

    unawaited(queryCache.find(key)!.cancel());

    await time.advance(ms(100));

    expect(calls, 1);
    await rejects;
  });

  testFakeAsync('should not error if reset while pending', (time) async {
    final key = queryKey();
    var calls = 0;

    final promise = queryClient.fetchQuery(
      options(
        key,
        queryFn: (_) async {
          calls++;
          await sleep(ms(10));
          throw StateError('failed');
        },
        retry: const RetryOption.count(3),
        retryDelay: const RetryDelay.of(Duration(milliseconds: 10)),
      ),
    );
    // The call must still reject: it was reset, not reverted, so there is no
    // data to resolve with.
    final rejects = expectLater(promise, throwsA(isA<CancelledError>()));

    final query = queryCache.find(key)!;
    expect(query.state.status, QueryStatus.pending);

    query.reset();

    await time.advance(ms(100));

    expect(calls, 1, reason: 'it was called');
    expect(query.state.error, isNull, reason: 'but did not record an error');
    expect(query.state.fetchStatus, FetchStatus.idle);
    expect(query.state.data, isNull);
    await rejects;
  });

  testFakeAsync('should be able to refetch a cancelled query', (time) async {
    final key = queryKey();
    var calls = 0;

    unawaited(
      queryClient.prefetchQuery(
        options(
          key,
          queryFn: (_) {
            calls++;
            return sleep(ms(50)).then((_) => 'data');
          },
        ),
      ),
    );
    final query = queryCache.find(key)! as Query<String>;

    await time.advance(ms(10));
    unawaited(query.cancel());
    await time.advance(ms(100));

    expect(calls, 1);
    expect(query.state.error, isA<CancelledError>());

    final result = query.fetch();
    await time.advance(ms(50));
    await expectLater(result, completion('data'));
    expect(query.state.error, isNull);
    expect(calls, 2);
  });

  testFakeAsync('cancelling a resolved query should not have any effect', (
    time,
  ) async {
    final key = queryKey();
    await queryClient.prefetchQuery(options(key, queryFn: (_) async => 'data'));

    final query = queryCache.find(key)!;
    unawaited(query.cancel());
    await time.advance(ms(10));

    expect(query.state.data, 'data');
  });

  testFakeAsync('cancelling a rejected query should not have any effect', (
    time,
  ) async {
    final key = queryKey();
    final error = StateError('error');

    await queryClient.prefetchQuery(
      options(key, queryFn: (_) => Future<String>.error(error)),
    );

    final query = queryCache.find(key)!;
    unawaited(query.cancel());
    await time.advance(ms(10));

    expect(query.state.error, same(error));
    expect(query.state.error, isNot(isA<CancelledError>()));
  });

  testFakeAsync('should release the retryer once its fetch has settled', (
    time,
  ) async {
    final key = queryKey();
    Future<Object?>? refetch;

    final testCache = QueryCache(
      onSuccess: (_, query) => refetch ??= query.fetch(),
    );
    final testClient = QueryClient(queryCache: testCache);

    final prefetch = testClient.prefetchQuery(
      options(key, queryFn: (_) => sleep(ms(10)).then((_) => 'data')),
    );
    final query = testCache.find(key)!;
    final firstFuture = query.future;
    expect(firstFuture, isNotNull);

    await time.advance(ms(10));
    await prefetch;
    expect(query.future, isNotNull);
    expect(query.future, isNot(same(firstFuture)));

    await time.advance(ms(10));
    await refetch;
    expect(query.state.data, 'data');
    expect(query.future, isNull);
  });

  testFakeAsync('the previous query status should be kept when refetching', (
    time,
  ) async {
    final key = queryKey();

    await queryClient.prefetchQuery(options(key, queryFn: (_) async => 'data'));
    final query = queryCache.find(key)!;
    expect(query.state.status, QueryStatus.success);

    await queryClient.prefetchQuery(
      options(
        key,
        queryFn: (_) => Future<String>.error('reject'),
        retry: RetryOption.never,
      ),
    );
    expect(query.state.status, QueryStatus.error);

    unawaited(
      queryClient.prefetchQuery(
        options(
          key,
          queryFn: (_) =>
              sleep(ms(10)).then((_) => Future<String>.error('reject')),
          retry: RetryOption.never,
        ),
      ),
    );
    expect(query.state.status, QueryStatus.error);

    await time.advance(ms(10));
    expect(query.state.status, QueryStatus.error);
  });

  testFakeAsync(
    'queries with gcTime 0 should be removed immediately after unsubscribing',
    (time) async {
      final key = queryKey();
      var count = 0;

      final observer = QueryObserver<String, String>(
        queryClient,
        options(
          key,
          queryFn: (_) async {
            count++;
            return 'data';
          },
          gcTime: const GcDuration.of(Duration.zero),
          staleTime: StaleDuration.infinity,
        ),
      );

      observer.subscribe((_) {})();
      await time.advance(Duration.zero);
      expect(queryCache.find(key), isNull);

      observer.subscribe((_) {})();
      await time.advance(Duration.zero);
      expect(queryCache.find(key), isNull);
      expect(count, 1);
    },
  );

  testFakeAsync('should be garbage collected when unsubscribed to', (
    time,
  ) async {
    final key = queryKey();
    final observer = QueryObserver<String, String>(
      queryClient,
      options(
        key,
        queryFn: (_) async => 'data',
        gcTime: const GcDuration.of(Duration.zero),
      ),
    );

    expect(queryCache.find(key)!.state.status, QueryStatus.pending);
    final unsubscribe = observer.subscribe((_) {});
    expect(queryCache.find(key)!.state.status, QueryStatus.pending);
    unsubscribe();

    await time.advance(Duration.zero);
    expect(queryCache.find(key), isNull);
  });

  testFakeAsync(
    'should be garbage collected later when unsubscribed and query is fetching',
    (time) async {
      final key = queryKey();
      final observer = QueryObserver<String, String>(
        queryClient,
        options(
          key,
          queryFn: (_) => sleep(ms(20)).then((_) => 'data'),
          gcTime: const GcDuration.of(Duration(milliseconds: 10)),
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(20));
      expect(queryCache.find(key)!.state.data, 'data');

      unawaited(observer.refetch());
      unsubscribe();

      // Unsubscribing must not remove it even though the gc time has elapsed,
      // because the query is still fetching.
      expect(queryCache.find(key)!.state.data, 'data');

      await time.advance(ms(30));
      expect(queryCache.find(key), isNull);
    },
  );

  testFakeAsync(
    'should not be garbage collected unless there are no subscribers',
    (time) async {
      final key = queryKey();
      final observer = QueryObserver<String, String>(
        queryClient,
        options(
          key,
          queryFn: (_) async => 'data',
          gcTime: const GcDuration.of(Duration.zero),
        ),
      );

      expect(queryCache.find(key)!.state.status, QueryStatus.pending);
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(100));
      expect(queryCache.find(key)!.state.data, 'data');

      unsubscribe();
      await time.advance(ms(100));
      expect(queryCache.find(key), isNull);

      queryClient.setQueryData<String>(key, (_) => 'data');
      await time.advance(ms(100));
      expect(queryCache.find(key)!.state.data, 'data');
    },
  );

  test('should return proper count of observers', () {
    final key = queryKey();
    QueryObserver<String, String> build() => QueryObserver<String, String>(
      queryClient,
      options(key, queryFn: (_) async => 'data'),
    );

    final observer = build();
    final observer2 = build();
    final observer3 = build();
    final query = queryCache.find(key)!;

    expect(query.observersCount, 0);

    final unsubscribe1 = observer.subscribe((_) {});
    final unsubscribe2 = observer2.subscribe((_) {});
    final unsubscribe3 = observer3.subscribe((_) {});
    expect(query.observersCount, 3);

    unsubscribe3();
    expect(query.observersCount, 2);

    unsubscribe2();
    expect(query.observersCount, 1);

    unsubscribe1();
    expect(query.observersCount, 0);
  });

  testFakeAsync('stores meta object in query', (time) async {
    const meta = {'it': 'works'};
    final key = queryKey();

    await queryClient.prefetchQuery(
      options(key, queryFn: (_) async => 'data', meta: meta),
    );

    final query = queryCache.find(key)!;
    expect(query.meta, same(meta));
    expect(query.options.meta, same(meta));
  });

  testFakeAsync('updates meta object on change', (time) async {
    const meta = {'it': 'works'};
    final key = queryKey();
    Future<String> queryFn(QueryFunctionContext _) async => 'data';

    await queryClient.prefetchQuery(options(key, queryFn: queryFn, meta: meta));
    await queryClient.prefetchQuery(options(key, queryFn: queryFn));

    final query = queryCache.find(key)!;
    expect(query.meta, isNull);
    expect(query.options.meta, isNull);
  });

  testFakeAsync('can use default meta', (time) async {
    const meta = {'it': 'works'};
    final key = queryKey();

    queryClient.setQueryDefaults(key, const QueryDefaults(meta: meta));

    await queryClient.prefetchQuery(options(key, queryFn: (_) async => 'data'));

    expect(queryCache.find(key)!.meta, same(meta));
  });

  testFakeAsync('provides meta object inside query function', (time) async {
    const meta = {'it': 'works'};
    final key = queryKey();
    Object? seen;

    await queryClient.prefetchQuery(
      options(
        key,
        queryFn: (context) async {
          seen = context.meta;
          return 'data';
        },
        meta: meta,
      ),
    );

    expect(seen, same(meta));
  });

  test('should refetch the observer when online method is called', () {
    final key = queryKey();

    final observer = _SpyObserver(
      queryClient,
      options(key, queryFn: (_) async => 'data'),
    );

    final unsubscribe = observer.subscribe((_) {});
    queryCache.onOnline();

    expect(observer.quietRefetches, 1);

    unsubscribe();
  });

  testFakeAsync('should not add an existing observer', (time) async {
    final key = queryKey();

    await queryClient.prefetchQuery(options(key, queryFn: (_) async => 'data'));
    final query = queryCache.find(key)!;
    expect(query.observersCount, 0);

    final observer = QueryObserver<String, String>(queryClient, options(key));
    expect(query.observersCount, 0);

    query.addObserver(observer);
    expect(query.observersCount, 1);

    query.addObserver(observer);
    expect(query.observersCount, 1);
  });

  testFakeAsync('should not try to remove an observer that does not exist', (
    time,
  ) async {
    final key = queryKey();

    await queryClient.prefetchQuery(options(key, queryFn: (_) async => 'data'));
    final query = queryCache.find(key)!;
    final observer = QueryObserver<String, String>(queryClient, options(key));
    expect(query.observersCount, 0);

    final events = <QueryCacheEvent>[];
    final unsubscribe = queryCache.subscribe(events.add);

    expect(() => query.removeObserver(observer), returnsNormally);
    expect(events, isEmpty);

    unsubscribe();
  });

  test(
    'should notify remaining observers when one unsubscribes during an update',
    () {
      final key = queryKey();
      final firstObserver = QueryObserver<String, String>(
        queryClient,
        options(key, enabled: Enabled.off),
      );
      final secondObserver = QueryObserver<String, String>(
        queryClient,
        options(key, enabled: Enabled.off),
      );
      var secondNotifications = 0;

      late void Function() unsubscribeFirst;
      unsubscribeFirst = firstObserver.subscribe((_) => unsubscribeFirst());
      final unsubscribeSecond = secondObserver.subscribe(
        (_) => secondNotifications++,
      );

      queryClient.setQueryData<String>(key, (_) => 'data');

      expect(secondNotifications, 1);
      expect(secondObserver.result.dataOrNull, 'data');

      unsubscribeSecond();
    },
  );

  testFakeAsync(
    'should not change state on invalidate() if already invalidated',
    (time) async {
      final key = queryKey();

      await queryClient.prefetchQuery(
        options(key, queryFn: (_) async => 'data'),
      );
      final query = queryCache.find(key)!;

      query.invalidate();
      expect(query.state.isInvalidated, isTrue);

      final previousState = query.state;

      query.invalidate();

      expect(query.state, same(previousState));
    },
  );

  testFakeAsync('fetch should not dispatch "fetch" when already fetching', (
    time,
  ) async {
    final key = queryKey();
    Future<String> queryFn(QueryFunctionContext _) =>
        sleep(ms(10)).then((_) => 'data');

    final updates = <String>[];

    unawaited(queryClient.prefetchQuery(options(key, queryFn: queryFn)));
    await time.advance(ms(10));
    final query = queryCache.find(key)! as Query<String>;

    final unsubscribe = queryCache.subscribe(
      (event) => updates.add(eventName(event)),
    );

    query.fetch().ignore();
    query.fetch().ignore();
    await time.advance(ms(10));

    expect(updates, <String>[
      'updated', // type: fetch
      'updated', // type: success
    ]);
    unsubscribe();
  });

  testFakeAsync('fetch should throw an error if the queryFn is not defined', (
    time,
  ) async {
    final key = queryKey();

    final observer = QueryObserver<String, String>(
      queryClient,
      options(key, retry: RetryOption.never),
    );

    final unsubscribe = observer.subscribe((_) {});

    await time.advance(ms(10));

    expect(observer.result, isA<QueryError<String>>());
    expect(
      (observer.result as QueryError<String>).error,
      isA<MissingQueryFunctionError>(),
    );
    unsubscribe();
  });

  testFakeAsync(
    'constructor should call initialDataUpdatedAt if defined as a function',
    (time) async {
      final key = queryKey();
      var calls = 0;

      await queryClient.prefetchQuery(
        options(
          key,
          queryFn: (_) async => 'data',
          initialData: () => 'initial',
          initialDataUpdatedAt: () {
            calls++;
            return null;
          },
        ),
      );

      expect(calls, greaterThan(0));
    },
  );

  testFakeAsync('should work with initialDataUpdatedAt set to the epoch', (
    time,
  ) async {
    final key = queryKey();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    await queryClient.prefetchQuery(
      options(
        key,
        queryFn: (_) async => 'data',
        staleTime: StaleDuration.infinity,
        initialData: () => 'initial',
        initialDataUpdatedAt: () => epoch,
      ),
    );

    final state = queryCache.find(key)!.state;
    expect(state.data, 'initial');
    expect(state.status, QueryStatus.success);
    expect(state.dataUpdatedAt, epoch);
  });

  testFakeAsync(
    'queries should be garbage collected even if they never fetched',
    (time) async {
      final key = queryKey();

      queryClient.setQueryDefaults(
        key,
        const QueryDefaults(gcTime: GcDuration.of(Duration(milliseconds: 10))),
      );

      final events = <QueryCacheEvent>[];
      final unsubscribe = queryCache.subscribe(events.add);

      queryClient.setQueryData<String>(key, (_) => 'data');
      final query = queryCache.find(key);

      await time.advance(ms(10));

      expect(events.last, isA<QueryRemoved>());
      expect(events.last.query, same(query));
      expect(queryCache.findAll(), isEmpty);

      unsubscribe();
    },
  );

  testFakeAsync('should always revert to idle state (#5968)', (time) async {
    var mockedData = <int>[1];
    final key = queryKey();

    Future<String> queryFn(QueryFunctionContext context) {
      final token = context.cancelToken;
      final completer = Completer<String>();
      final timer = Timer(ms(50), () {
        if (!completer.isCompleted) {
          completer.complete(mockedData.join(' - '));
        }
      });
      token.addListener((error) {
        timer.cancel();
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      });
      return completer.future;
    }

    final observer = QueryObserver<String, String>(
      queryClient,
      options(key, queryFn: queryFn),
    );
    final unsubscribe = observer.subscribe((_) {});
    await time.advance(ms(50));

    expect(observer.result.dataOrNull, '1');
    expect(observer.result.fetchStatus, FetchStatus.idle);

    mockedData = <int>[1, 2]; // Update "server" state in the background.

    unawaited(
      queryClient.invalidateQueries(filters: QueryFilters(queryKey: key)),
    );
    await time.advance(ms(5));
    unawaited(
      queryClient.invalidateQueries(filters: QueryFilters(queryKey: key)),
    );
    await time.advance(ms(5));
    unsubscribe(); // Simulate an unmount.
    await time.advance(ms(5));

    // Reverted to the previous data and an idle fetch status.
    final state = queryCache.find(key)!.state;
    expect(state.status, QueryStatus.success);
    expect(state.data, '1');
    expect(state.fetchStatus, FetchStatus.idle);

    // A new observer, simulating a new widget mounting.
    final newObserver = QueryObserver<String, String>(
      queryClient,
      options(key, queryFn: queryFn),
    );
    final seen = <String?>[];
    newObserver.subscribe((result) => seen.add(result.dataOrNull));
    await time.advance(ms(60));

    expect(seen, contains('1 - 2'));
  });

  testFakeAsync(
    'should not reject a promise when silently cancelled in the background',
    (time) async {
      final key = queryKey();
      var x = 0;
      var calls = 0;

      queryClient.setQueryData<String>(key, (_) => 'initial');

      final promise = queryClient.fetchQuery(
        options(
          key,
          queryFn: (_) {
            calls++;
            return sleep(ms(100)).then((_) => 'data$x');
          },
        ),
      );

      await time.advance(Duration.zero);
      expect(calls, 1);

      x = 1;

      // Cancel the ongoing refetch by starting another one.
      unawaited(
        queryClient.refetchQueries(filters: QueryFilters(queryKey: key)),
      );

      await time.advance(ms(100));
      await expectLater(promise, completion('data1'));

      expect(calls, 2);
    },
  );

  testFakeAsync(
    'should have an error status when setData has any error inside',
    (time) async {
      final key = queryKey();
      var calls = 0;

      unawaited(
        queryClient.prefetchQuery(
          options(
            key,
            queryFn: (_) {
              calls++;
              return sleep(ms(10)).then((_) => 'data');
            },
            structuralSharing: (_, _) => throw StateError('Any error'),
          ),
        ),
      );

      final query = queryCache.find(key)!;

      expect(calls, 1);
      await time.advance(ms(10));
      expect(query.state.status, QueryStatus.error);
    },
  );

  testFakeAsync('should use queryFn from observer if not provided in options', (
    time,
  ) async {
    final key = queryKey();
    Future<String> queryFn(QueryFunctionContext _) async => 'data';

    final observer = QueryObserver<String, String>(
      queryClient,
      options(key, queryFn: queryFn),
    );

    final query = Query<String>(
      queryKey: key,
      host: queryCache,
      options: queryClient.defaultQueryOptions(options(key)),
    );

    query.addObserver(observer);

    await query.fetch();
    expect(query.state.data, 'data');
    expect(query.options.queryFn, same(queryFn));
  });

  test('should call initialData function when it is a function', () {
    final key = queryKey();
    var calls = 0;

    final query = Query<String>(
      queryKey: key,
      host: queryCache,
      options: queryClient.defaultQueryOptions(
        options(
          key,
          queryFn: (_) async => 'data',
          initialData: () {
            calls++;
            return 'initial data';
          },
        ),
      ),
    );

    expect(calls, 1);
    expect(query.state.data, 'initial data');
  });

  testFakeAsync('should update initialData when Query exists without data', (
    time,
  ) async {
    final key = queryKey();
    var calls = 0;
    final seededAt = DateTime.utc(2020);

    Future<String> queryFn(QueryFunctionContext _) {
      calls++;
      return sleep(ms(100)).then((_) => 'data');
    }

    final promise = queryClient.prefetchQuery(
      options(
        key,
        queryFn: queryFn,
        staleTime: const StaleDuration.of(Duration(milliseconds: 1000)),
      ),
    );

    await time.advance(ms(50));

    var state = queryClient.getQueryState<String>(key)!;
    expect(state.data, isNull);
    expect(state.status, QueryStatus.pending);
    expect(state.fetchStatus, FetchStatus.fetching);

    final observer = QueryObserver<String, String>(
      queryClient,
      options(
        key,
        queryFn: queryFn,
        staleTime: const StaleDuration.of(Duration(milliseconds: 1000)),
        initialData: () => 'initialData',
        initialDataUpdatedAt: () => seededAt,
      ),
    );

    final unsubscribe = observer.subscribe((_) {});

    state = queryClient.getQueryState<String>(key)!;
    expect(state.data, 'initialData');
    expect(state.dataUpdatedAt, seededAt);
    expect(state.status, QueryStatus.success);
    expect(state.fetchStatus, FetchStatus.fetching);

    await time.advance(ms(50));
    await promise;

    state = queryClient.getQueryState<String>(key)!;
    expect(state.data, 'data');
    expect(state.status, QueryStatus.success);
    expect(state.fetchStatus, FetchStatus.idle);
    expect(calls, 1);

    unsubscribe();

    // Resetting should get us back to 'initialData'.
    queryCache.find(key)!.reset();

    state = queryClient.getQueryState<String>(key)!;
    expect(state.data, 'initialData');
    expect(state.status, QueryStatus.success);
    expect(state.fetchStatus, FetchStatus.idle);
  });

  testFakeAsync(
    'should not override fetching state when revert happens after new observer '
    'subscribes',
    (time) async {
      final key = queryKey();
      var count = 0;

      Future<String> queryFn(QueryFunctionContext context) async {
        // Consume the token so observer removal takes the revert-cancel path.
        final _ = context.cancelToken;
        await sleep(ms(50));
        return 'data${count++}';
      }

      final query = Query<String>(
        queryKey: key,
        host: queryCache,
        options: queryClient.defaultQueryOptions(
          options(key, queryFn: queryFn),
        ),
      );

      final observer1 = QueryObserver<String, String>(
        queryClient,
        options(key, queryFn: queryFn),
      );

      query.addObserver(observer1);
      final promise1 = query.fetch();
      final rejects = expectLater(promise1, throwsA(isA<CancelledError>()));

      await time.advance(ms(10));

      query.removeObserver(observer1);

      final observer2 = QueryObserver<String, String>(
        queryClient,
        options(key, queryFn: queryFn),
      );

      query.addObserver(observer2);

      query.fetch().ignore();

      await rejects;
      await time.advance(ms(50));

      expect(query.state.fetchStatus, FetchStatus.idle);
      expect(count, 2);
      expect(query.state.status, QueryStatus.success);
      expect(query.state.data, 'data1');
    },
  );

  testFakeAsync(
    'should not increment dataUpdateCount when setting initialData on a '
    'prefetched query',
    (time) async {
      final key = queryKey();
      Future<String> queryFn(QueryFunctionContext _) async => 'fetched-data';

      // Prefetch first, which creates the query without data.
      unawaited(queryClient.prefetchQuery(options(key, queryFn: queryFn)));

      final query = queryCache.find(key)!;
      expect(query.state.data, isNull);
      expect(query.state.dataUpdateCount, 0);

      final observer = QueryObserver<String, String>(
        queryClient,
        options(key, queryFn: queryFn, initialData: () => 'initial-data'),
      );

      // The query now holds the initial data, but dataUpdateCount stays at zero
      // because nothing was fetched.
      expect(query.state.data, 'initial-data');
      expect(query.state.dataUpdateCount, 0);

      expect(observer.result.dataOrNull, 'initial-data');
      expect(observer.result.isFetchedAfterMount, isFalse);

      await observer.refetch();

      expect(query.state.dataUpdateCount, 1);
      expect(query.state.data, 'fetched-data');
      expect(observer.result.isFetchedAfterMount, isTrue);
    },
  );
}
