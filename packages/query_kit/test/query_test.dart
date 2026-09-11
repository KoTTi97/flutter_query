/// Port of `query-core/src/__tests__/query.test.tsx` at upstream `50680b98c`.
/// Omissions and adaptations: `test/PORTING_NOTES.md`.
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('query', () {
    late QueryClient queryClient;
    late QueryCache queryCache;

    setUp(() {
      queryClient = testClient();
      queryCache = queryClient.queryCache;
      queryClient.mount();
    });

    tearDown(() => queryClient.clear());

    testFakeAsync(
        'constructor should call initialDataUpdatedAt if defined as a function',
        (time) async {
      var calls = 0;
      final key = queryKey();
      final seededAt = time.now.subtract(ms(500));
      await queryClient.query<String>(QueryOptions(
        queryKey: key,
        queryFn: (_) => 'data',
        initialData: const InitialData.value('initial'),
        initialDataUpdatedAtCompute: () {
          calls++;
          return seededAt;
        },
        staleTime: StaleTime.duration(ms(1000)),
      ));
      // Evaluated once, at seeding, and the timestamp it returns is the one
      // the state carries — so the seed is 500 ms old, not brand new.
      expect(calls, 1);
      final state = queryClient.getQueryState<String>(key)!;
      expect(state.dataUpdatedAt, seededAt);
      expect(state.data, 'initial');
    });

    testFakeAsync('should use the longest garbage collection time it has seen',
        (time) async {
      final key = queryKey();
      await queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (_) => 'data',
        gcTime: const GcTime.duration(Duration(milliseconds: 100)),
      ));
      await queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (_) => 'data',
        gcTime: const GcTime.duration(Duration(milliseconds: 200)),
      ));
      await queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (_) => 'data',
        gcTime: const GcTime.duration(Duration(milliseconds: 10)),
      ));
      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;
      expect(query.gcTime, const GcTime.duration(Duration(milliseconds: 200)));
    });

    testFakeAsync(
        'should continue retry after focus regain and resolve all promises',
        (time) async {
      final key = queryKey();

      // make page unfocused
      queryClient.focusManager.setFocused(false);

      var count = 0;
      String? result;

      final promise = queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (_) {
          count++;
          if (count == 3) {
            return 'data$count';
          }
          throw Exception('error$count');
        },
        retry: const RetryTimes(3),
        retryDelay: const RetryDelay.fixed(Duration(milliseconds: 1)),
      ));

      promise.then((data) => result = data).ignore();

      // Check if we do not have a result
      expect(result, isNull);

      // Check if the query is really paused
      await time.advance(ms(50));
      expect(result, isNull);

      // Reset focus to its original value
      queryClient.focusManager.setFocused(null);

      // There should not be a result yet
      expect(result, isNull);

      // By now we should have a value
      await time.advance(ms(50));
      expect(result, 'data3');
    });

    testFakeAsync(
        'should continue retry after reconnect and resolve all promises',
        (time) async {
      final key = queryKey();

      queryClient.onlineManager.setOnline(false);

      var count = 0;
      String? result;

      final promise = queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (_) {
          count++;
          if (count == 3) {
            return 'data$count';
          }
          throw Exception('error$count');
        },
        retry: const RetryTimes(3),
        retryDelay: const RetryDelay.fixed(Duration(milliseconds: 1)),
      ));

      promise.then((data) => result = data).ignore();

      // Check if we do not have a result
      expect(result, isNull);

      // Check if the query is really paused
      await time.advance(ms(1));
      expect(result, isNull);

      // Back online
      queryClient.onlineManager.setOnline(true);
      queryClient.queryCache.onOnline();

      // There should not be a result yet
      expect(result, isNull);

      // Promise should eventually be resolved
      await time.advance(ms(2));
      expect(result, 'data3');
    });

    testFakeAsync(
        'should throw a CancelledError when a paused query is cancelled',
        (time) async {
      final key = queryKey();

      // make page unfocused
      queryClient.focusManager.setFocused(false);
      var count = 0;

      final promise = queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (_) {
          count++;
          throw Exception('error$count');
        },
        retry: const RetryTimes(3),
        retryDelay: const RetryDelay.fixed(Duration(milliseconds: 1)),
      ));
      final caught =
          promise.then<Object?>((_) => null, onError: (Object e) => e);

      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;

      // Check if the query is really paused
      await time.advance(ms(50));
      expect(query.state.fetchStatus, FetchStatus.paused);

      // Cancel query
      query.cancel().ignore();

      // Check if the error is set to the cancelled error
      expect(await caught, isA<CancelledError>());
      queryClient.focusManager.setFocused(null);
    });

    testFakeAsync(
        'should cancel a paused initial fetch when the last observer unsubscribes',
        (time) async {
      final key = queryKey();
      queryClient.onlineManager.setOnline(false);
      var count = 0;

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (context) async {
            context.signal;
            count++;
            await sleep(ms(10));
            return 'data$count';
          },
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;

      expect(query.state.fetchStatus, FetchStatus.paused);
      expect(query.state.status, QueryStatus.pending);

      unsubscribe();

      expect(query.state.fetchStatus, FetchStatus.idle);
      expect(query.state.status, QueryStatus.pending);

      queryClient.onlineManager.setOnline(true);
      queryClient.queryCache.onOnline();

      await time.advance(ms(11));

      expect(query.state.fetchStatus, FetchStatus.idle);
      expect(query.state.status, QueryStatus.pending);
      expect(count, 0);
    });

    testFakeAsync(
        'should not throw a CancelledError when fetchQuery is in progress and '
        'the last observer unsubscribes when AbortSignal is consumed',
        (time) async {
      final key = queryKey();

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) async {
            await sleep(ms(100));
            return 'data';
          },
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(100));

      expect(queryCache.find(filters: QueryFilters(queryKey: key))?.state.data,
          'data');

      final promise = queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (context) async {
          context.signal;
          await sleep(ms(100));
          return 'data2';
        },
      ));

      // Ensure the fetch is in progress
      await time.advance(ms(10));

      // Unsubscribe while fetch is in progress
      unsubscribe();

      await time.advance(ms(90));

      // Fetch should complete successfully without throwing a CancelledError
      expect(await promise, 'data');

      expect(queryCache.find(filters: QueryFilters(queryKey: key))?.state.data,
          'data');
    });

    testFakeAsync('should provide context to queryFn', (time) async {
      final key = queryKey();

      final contexts = <QueryFunctionContext>[];
      queryClient
          .query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (context) async {
              contexts.add(context);
              return 'data';
            },
          ))
          .ignore();

      expect(contexts, hasLength(1));
      final args = contexts.single;
      // Upstream asserts `args.pageParam` is undefined; the port's context
      // has no such field (PORTING_NOTES, `query.test.tsx`).
      expect(args.queryKey, key);
      expect(args.signal, isA<QueryCancelToken>());
      expect(args.client, same(queryClient));
    });

    testFakeAsync(
        'should continue if cancellation is not supported and signal is not consumed',
        (time) async {
      final key = queryKey();

      queryClient
          .query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              await sleep(ms(100));
              return 'data';
            },
          ))
          .ignore();

      await time.advance(ms(10));

      // Subscribe and unsubscribe to simulate cancellation because the last
      // observer unsubscribed
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          enabled: Enabled.no,
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      unsubscribe();

      await time.advance(ms(90));

      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;

      expect(query.state.data, 'data');
      expect(query.state.status, QueryStatus.success);
      expect(query.state.dataUpdateCount, 1);
    });

    testFakeAsync(
        'should not continue when last observer unsubscribed if the signal was consumed',
        (time) async {
      final key = queryKey();

      queryClient
          .query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (context) async {
              final signal = context.signal;
              await sleep(ms(100));
              return signal.isCancelled ? 'aborted' : 'data';
            },
          ))
          .ignore();

      await time.advance(ms(10));

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          enabled: Enabled.no,
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      unsubscribe();

      await time.advance(ms(90));

      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;

      expect(query.state.hasData, isFalse);
      expect(query.state.status, QueryStatus.pending);
      expect(query.state.fetchStatus, FetchStatus.idle);
    });

    testFakeAsync(
        'should provide an AbortSignal to the queryFn that provides info about '
        'the cancellation state', (time) async {
      final key = queryKey();

      var onCancelCalls = 0;
      QueryCancelToken? signal;
      Object? error;

      final promise = queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (context) async {
          signal = context.signal;
          context.signal.onCancel(() => onCancelCalls++);
          await sleep(ms(10));
          throw Exception();
        },
        retry: const RetryTimes(3),
        retryDelay: const RetryDelay.fixed(Duration(milliseconds: 10)),
      ));
      promise.then((_) {}, onError: (Object e) => error = e).ignore();

      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;

      expect(signal, isNotNull);
      expect(signal!.isCancelled, isFalse);
      expect(onCancelCalls, 0);

      query.cancel().ignore();

      await time.advance(ms(100));

      expect(signal!.isCancelled, isTrue);
      expect(onCancelCalls, 1);
      expect(error, isA<CancelledError>());
    });

    testFakeAsync('should not continue if explicitly cancelled', (time) async {
      final key = queryKey();

      var calls = 0;
      Object? error;

      final promise = queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (_) async {
          calls++;
          await sleep(ms(10));
          throw Exception();
        },
        retry: const RetryTimes(3),
        retryDelay: const RetryDelay.fixed(Duration(milliseconds: 10)),
      ));
      promise.then((_) {}, onError: (Object e) => error = e).ignore();

      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;
      query.cancel().ignore();

      await time.advance(ms(100));

      expect(calls, 1);
      expect(error, isA<CancelledError>());
    });

    testFakeAsync('should not error if reset while pending', (time) async {
      final key = queryKey();

      var calls = 0;
      Object? error;

      queryClient
          .query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              calls++;
              await sleep(ms(10));
              throw Exception();
            },
            retry: const RetryTimes(3),
            retryDelay: const RetryDelay.fixed(Duration(milliseconds: 10)),
          ))
          .then((_) {}, onError: (Object e) => error = e)
          .ignore();

      // Ensure the query is pending
      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;
      expect(query.state.status, QueryStatus.pending);

      // Reset the query while it is pending
      query.reset();

      await time.advance(ms(100));

      // The query should
      expect(calls, 1); // have been called,
      expect(query.state.error, isNull); // not have an error, and
      expect(query.state.fetchStatus, FetchStatus.idle); // not be loading, and
      expect(query.state.hasData, isFalse); // have no data

      // the call to query() must reject because it was reset and not reverted
      expect(error, isA<CancelledError>());
    });

    testFakeAsync('should be able to refetch a cancelled query', (time) async {
      final key = queryKey();

      var calls = 0;
      Future<String> queryFn(QueryFunctionContext _) async {
        calls++;
        await sleep(ms(50));
        return 'data';
      }

      queryClient
          .query<String>(QueryOptions<String>(queryKey: key, queryFn: queryFn))
          .ignore();
      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;
      await time.advance(ms(10));
      query.cancel().ignore();
      await time.advance(ms(100));

      expect(calls, 1);
      expect(query.state.error, isA<CancelledError>());
      final result = (query as Query<String>).fetch();
      await time.advance(ms(50));
      expect(await result, 'data');
      expect(query.state.error, isNull);
      expect(calls, 2);
    });

    testFakeAsync('cancelling a resolved query should not have any effect',
        (time) async {
      final key = queryKey();
      await queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (_) => 'data',
      ));
      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;
      query.cancel().ignore();
      await time.advance(ms(10));
      expect(query.state.data, 'data');
    });

    testFakeAsync('cancelling a rejected query should not have any effect',
        (time) async {
      final key = queryKey();
      final error = Exception('error');

      await queryClient
          .query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) => Future<String>.error(error),
          ))
          .then((_) {}, onError: (Object _) {});
      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;
      query.cancel().ignore();
      await time.advance(ms(10));

      expect(query.state.error, same(error));
      expect(query.state.error, isNot(isA<CancelledError>()));
    });

    testFakeAsync('should release the retryer once its fetch has settled',
        (time) async {
      final key = queryKey();
      Future<Object?>? refetch;
      final testCache = QueryCache(
        onSuccess: (_, query) => refetch ??= (query as Query<String>).fetch(),
      );
      final client = testClient(queryCache: testCache);

      final prefetch = client
          .query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              await sleep(ms(10));
              return 'data';
            },
          ))
          .then((_) {}, onError: (Object _) {});
      final query = testCache.find(filters: QueryFilters(queryKey: key))!
          as Query<String>;
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

    testFakeAsync('the previous query status should be kept when refetching',
        (time) async {
      final key = queryKey();

      await queryClient.query<String>(
          QueryOptions<String>(queryKey: key, queryFn: (_) => 'data'));
      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;
      expect(query.state.status, QueryStatus.success);

      await queryClient
          .query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) => Future<String>.error('reject'),
            retry: RetryPolicy.never,
          ))
          .then((_) {}, onError: (Object _) {});
      expect(query.state.status, QueryStatus.error);

      queryClient
          .query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              await sleep(ms(10));
              throw 'reject';
            },
            retry: RetryPolicy.never,
          ))
          .ignore();
      expect(query.state.status, QueryStatus.error);

      await time.advance(ms(10));
      expect(query.state.status, QueryStatus.error);
    });

    testFakeAsync(
        'queries with gcTime 0 should be removed immediately after unsubscribing',
        (time) async {
      final key = queryKey();
      var count = 0;
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            count++;
            return 'data';
          },
          gcTime: const GcTime.duration(Duration.zero),
          staleTime: StaleTime.static,
        ),
      );
      final unsubscribe1 = observer.subscribe((_) {});
      unsubscribe1();

      await time.flushMicrotasks();
      expect(queryCache.find(filters: QueryFilters(queryKey: key)), isNull);
      final unsubscribe2 = observer.subscribe((_) {});
      unsubscribe2();

      await time.flushMicrotasks();
      expect(queryCache.find(filters: QueryFilters(queryKey: key)), isNull);
      // Upstream expects 1: its observer rejoins the query it last watched,
      // which the cache no longer holds, and shows its data without fetching.
      // Here a resubscribe re-resolves the key first, and a collected query
      // has no data left to show, so the second subscription fetches (see
      // PORTING_NOTES, "resubscribe after gc").
      expect(count, 2);
    });

    testFakeAsync('should be garbage collected when unsubscribed to',
        (time) async {
      final key = queryKey();
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
          gcTime: const GcTime.duration(Duration.zero),
        ),
      );
      expect(
          queryCache.find(filters: QueryFilters(queryKey: key))?.state.status,
          QueryStatus.pending);
      final unsubscribe = observer.subscribe((_) {});
      expect(
          queryCache.find(filters: QueryFilters(queryKey: key))?.state.status,
          QueryStatus.pending);
      unsubscribe();

      await time.flushMicrotasks();
      expect(queryCache.find(filters: QueryFilters(queryKey: key)), isNull);
    });

    testFakeAsync(
        'should be garbage collected later when unsubscribed and query is fetching',
        (time) async {
      final key = queryKey();
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) async {
            await sleep(ms(20));
            return 'data';
          },
          gcTime: const GcTime.duration(Duration(milliseconds: 10)),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(20));
      expect(queryCache.find(filters: QueryFilters(queryKey: key))?.state.data,
          'data');
      observer.refetch().ignore();
      unsubscribe();
      // unsubscribe should not remove even though gcTime has elapsed b/c query
      // is still fetching
      expect(queryCache.find(filters: QueryFilters(queryKey: key))?.state.data,
          'data');
      // should be removed after an additional staleTime wait
      await time.advance(ms(30));
      expect(queryCache.find(filters: QueryFilters(queryKey: key)), isNull);
    });

    testFakeAsync(
        'should not be garbage collected unless there are no subscribers',
        (time) async {
      final key = queryKey();
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
          gcTime: const GcTime.duration(Duration.zero),
        ),
      );
      expect(
          queryCache.find(filters: QueryFilters(queryKey: key))?.state.status,
          QueryStatus.pending);
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(100));
      expect(queryCache.find(filters: QueryFilters(queryKey: key))?.state.data,
          'data');
      unsubscribe();
      await time.advance(ms(100));
      expect(queryCache.find(filters: QueryFilters(queryKey: key)), isNull);
      queryClient.setQueryData<String>(key, 'data');
      await time.advance(ms(100));
      expect(queryCache.find(filters: QueryFilters(queryKey: key))?.state.data,
          'data');
    });

    testFakeAsync('should return proper count of observers', (time) async {
      final key = queryKey();
      QueryObserverOptions<String> options() => QueryObserverOptions<String>(
            queryKey: key,
            queryFn: (_) => 'data',
          );
      final observer = queryClient.observe<String, String>(options());
      final observer2 = queryClient.observe<String, String>(options());
      final observer3 = queryClient.observe<String, String>(options());
      final query = queryCache.find(filters: QueryFilters(queryKey: key));

      expect(query?.observersCount, 0);

      final unsubscribe1 = observer.subscribe((_) {});
      final unsubscribe2 = observer2.subscribe((_) {});
      final unsubscribe3 = observer3.subscribe((_) {});
      expect(query?.observersCount, 3);

      unsubscribe3();
      expect(query?.observersCount, 2);

      unsubscribe2();
      expect(query?.observersCount, 1);

      unsubscribe1();
      expect(query?.observersCount, 0);
    });

    testFakeAsync('stores meta object in query', (time) async {
      const meta = <String, String>{'it': 'works'};
      final key = queryKey();

      await queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (_) => 'data',
        meta: meta,
      ));

      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;

      expect(query.meta, same(meta));
      expect(query.options.meta, same(meta));
    });

    testFakeAsync('updates meta object on change', (time) async {
      const meta = <String, String>{'it': 'works'};
      final key = queryKey();
      String queryFn(QueryFunctionContext _) => 'data';

      await queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: queryFn,
        meta: meta,
      ));

      await queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: queryFn,
      ));

      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;

      expect(query.meta, isNull);
      expect(query.options.meta, isNull);
    });

    testFakeAsync('can use default meta', (time) async {
      const meta = <String, String>{'it': 'works'};
      final key = queryKey();
      String queryFn(QueryFunctionContext _) => 'data';

      queryClient.setQueryDefaults(key, const QueryDefaults(meta: meta));

      await queryClient
          .query<String>(QueryOptions<String>(queryKey: key, queryFn: queryFn));

      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;

      expect(query.meta, same(meta));
    });

    testFakeAsync('provides meta object inside query function', (time) async {
      const meta = <String, String>{'it': 'works'};
      final key = queryKey();
      final seen = <Object?>[];

      await queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (context) {
          seen.add(context.meta);
          return 'data';
        },
        meta: meta,
      ));

      expect(seen, [same(meta)]);
    });

    testFakeAsync('should refetch the observer when online method is called',
        (time) async {
      final key = queryKey();

      var fetches = 0;
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: (_) {
            fetches++;
            return 'data';
          },
        ),
      );

      final unsubscribe = observer.subscribe((_) {});
      // Upstream spies on `observer.refetch`; there is no spy here, so the
      // initial fetch is allowed to settle and the *effect* is asserted
      // instead. Asserting mid-flight would prove nothing: a refetch with
      // `cancelRefetch: false` piggybacks on the running one, upstream too.
      await time.flushMicrotasks();
      expect(fetches, 1);
      queryCache.onOnline();
      await time.flushMicrotasks();

      // Should refetch the observer
      expect(fetches, 2);

      unsubscribe();
    });

    testFakeAsync('should not add an existing observer', (time) async {
      final key = queryKey();

      await queryClient.query<String>(
          QueryOptions<String>(queryKey: key, queryFn: (_) => 'data'));
      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;
      expect(query.observersCount, 0);

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(queryKey: key),
      );
      expect(query.observersCount, 0);

      query.addObserver(observer);
      expect(query.observersCount, 1);

      query.addObserver(observer);
      expect(query.observersCount, 1);
    });

    testFakeAsync('should not try to remove an observer that does not exist',
        (time) async {
      final key = queryKey();

      await queryClient.query<String>(
          QueryOptions<String>(queryKey: key, queryFn: (_) => 'data'));
      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(queryKey: key),
      );
      expect(query.observersCount, 0);

      final events = <QueryCacheEvent>[];
      final unsubscribe = queryCache.subscribe(events.add);
      expect(() => query.removeObserver(observer), returnsNormally);
      expect(events, isEmpty);
      unsubscribe();
    });

    testFakeAsync(
        'should notify remaining observers when one unsubscribes during an update',
        (time) async {
      final key = queryKey();
      QueryObserverOptions<String> options() => QueryObserverOptions<String>(
            queryKey: key,
            enabled: Enabled.no,
          );
      final firstObserver = queryClient.observe<String, String>(options());
      final secondObserver = queryClient.observe<String, String>(options());
      final secondResults = <QueryResult<String>>[];

      late void Function() unsubscribeFirst;
      unsubscribeFirst = firstObserver.subscribe((_) => unsubscribeFirst());
      final unsubscribeSecond = secondObserver.subscribe(secondResults.add);

      queryClient.setQueryData<String>(key, 'data');

      expect(secondResults, hasLength(1));
      expect(secondObserver.currentResult.dataOrNull, 'data');

      unsubscribeSecond();
    });

    testFakeAsync(
        'should not change state on invalidate() if already invalidated',
        (time) async {
      final key = queryKey();

      await queryClient.query<String>(
          QueryOptions<String>(queryKey: key, queryFn: (_) => 'data'));
      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;

      query.invalidate();
      expect(query.state.isInvalidated, isTrue);

      final previousState = query.state;

      query.invalidate();

      expect(query.state, same(previousState));
    });

    testFakeAsync('fetch should not dispatch "fetch" query is already fetching',
        (time) async {
      final key = queryKey();

      Future<String> queryFn(QueryFunctionContext _) async {
        await sleep(ms(10));
        return 'data';
      }

      final updates = <String>[];

      queryClient
          .query<String>(QueryOptions<String>(queryKey: key, queryFn: queryFn))
          .ignore();
      await time.advance(ms(10));
      final query = queryCache.find(filters: QueryFilters(queryKey: key))!
          as Query<String>;

      final unsubscribe =
          queryCache.subscribe((event) => updates.add(eventName(event)));

      final options = queryClient.defaultQueryOptions<String>(
          QueryOptions<String>(queryKey: key, queryFn: queryFn));
      query.fetch(options: options).ignore();
      query.fetch(options: options).ignore();
      await time.advance(ms(10));

      expect(updates, <String>[
        'updated', // type: 'fetch'
        'updated', // type: 'success'
      ]);
      unsubscribe();
    });

    testFakeAsync('fetch should throw an error if the queryFn is not defined',
        (time) async {
      final key = queryKey();

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          retry: RetryPolicy.never,
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      await time.advance(ms(10));
      final result = observer.currentResult;
      expect(result, isA<QueryError<String>>());
      expect((result as QueryError<String>).error,
          isA<MissingQueryFunctionError>());
      unsubscribe();
    });

    testFakeAsync(
        'queries should be garbage collected even if they never fetched',
        (time) async {
      final key = queryKey();

      queryClient.setQueryDefaults(
        key,
        const QueryDefaults(
            gcTime: GcTime.duration(Duration(milliseconds: 10))),
      );

      final events = <QueryCacheEvent>[];
      final unsubscribe = queryCache.subscribe(events.add);

      queryClient.setQueryData<String>(key, 'data');
      final query = queryCache.find(filters: QueryFilters(queryKey: key));

      await time.advance(ms(10));
      expect(events.last, isA<QueryRemoved>());
      expect(events.last.query, same(query));

      expect(queryCache.findAll(), isEmpty);

      unsubscribe();
    });

    testFakeAsync('should always revert to idle state (#5968)', (time) async {
      var mockedData = <int>[1];

      final key = queryKey();
      var calls = 0;

      Future<String> queryFn(QueryFunctionContext context) {
        calls++;
        final completer = Completer<String>();
        final timer = Timer(ms(50), () {
          if (!completer.isCompleted) {
            completer.complete(mockedData.join(' - '));
          }
        });
        context.signal.onCancel(() {
          timer.cancel();
          if (!completer.isCompleted) {
            completer.completeError(const CancelledError());
          }
        });
        return completer.future;
      }

      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(queryKey: key, queryFn: queryFn),
      );
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(50)); // let it resolve

      expect(observer.currentResult.dataOrNull, '1');
      expect(observer.currentResult.isFetching, isFalse);

      mockedData = <int>[1, 2]; // update "server" state in the background

      queryClient
          .invalidateQueries(filters: QueryFilters(queryKey: key))
          .ignore();
      await time.advance(ms(5));
      queryClient
          .invalidateQueries(filters: QueryFilters(queryKey: key))
          .ignore();
      await time.advance(ms(5));
      unsubscribe(); // unsubscribe to simulate unmount
      await time.advance(ms(5));

      // reverted to previous data and idle fetchStatus
      final state =
          queryCache.find(filters: QueryFilters(queryKey: key))!.state;
      expect(state.status, QueryStatus.success);
      expect(state.data, '1');
      expect(state.fetchStatus, FetchStatus.idle);

      // set up a new observer to simulate a mount of new component
      final newObserver = queryClient.observe<String, String>(
        QueryObserverOptions<String>(queryKey: key, queryFn: queryFn),
      );
      final seen = <String?>[];
      newObserver.subscribe((result) => seen.add(result.dataOrNull));
      await time.advance(ms(60)); // let it resolve
      expect(seen, contains('1 - 2'));
      expect(calls, greaterThan(1));
    });

    testFakeAsync(
        'should not reject a promise when silently cancelled in the background',
        (time) async {
      final key = queryKey();

      var x = 0;

      queryClient.setQueryData<String>(key, 'initial');
      var calls = 0;
      Future<String> queryFn(QueryFunctionContext _) async {
        calls++;
        await sleep(ms(100));
        return 'data$x';
      }

      final promise = queryClient
          .query<String>(QueryOptions<String>(queryKey: key, queryFn: queryFn));

      await time.flushMicrotasks();
      expect(calls, 1);

      x = 1;

      // cancel ongoing re-fetches
      queryClient.refetchQueries(filters: QueryFilters(queryKey: key)).ignore();

      // The future should not reject
      await time.advance(ms(100));
      expect(await promise, 'data1');

      expect(calls, 2);
    });

    testFakeAsync(
        'should have an error status when setData has any error inside',
        (time) async {
      final key = queryKey();

      var calls = 0;
      queryClient
          .query<String>(QueryOptions<String>(
            queryKey: key,
            queryFn: (_) async {
              calls++;
              await sleep(ms(10));
              return 'data';
            },
            structuralSharing: (_, __) => throw Exception('Any error'),
          ))
          .ignore();

      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;

      expect(calls, 1);
      await time.advance(ms(10));
      expect(query.state.status, QueryStatus.error);
    });

    testFakeAsync('should use queryFn from observer if not provided in options',
        (time) async {
      final key = queryKey();
      Future<String> queryFn(QueryFunctionContext _) async => 'data';
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(queryKey: key, queryFn: queryFn),
      );

      final query = queryCache.build<String>(
        queryClient,
        queryClient
            .defaultQueryOptions<String>(QueryOptions<String>(queryKey: key)),
      );

      query.addObserver(observer);

      await query.fetch();
      expect(query.state.data, 'data');
      expect(query.options.queryFn, same(queryFn));
    });

    testFakeAsync('should call initialData function when it is a function',
        (time) async {
      final key = queryKey();
      var calls = 0;

      final query = queryCache.build<String>(
        queryClient,
        queryClient.defaultQueryOptions<String>(QueryOptions<String>(
          queryKey: key,
          queryFn: (_) => 'data',
          initialData: InitialData<String>.compute(() {
            calls++;
            return 'initial data';
          }),
        )),
      );

      expect(calls, 1);
      expect(query.state.data, 'initial data');
    });

    testFakeAsync('should work with initialDataUpdatedAt set to the epoch',
        (time) async {
      final key = queryKey();
      final epoch = DateTime.fromMillisecondsSinceEpoch(0);

      await queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: (_) => 'data',
        staleTime: StaleTime.static,
        initialData: const InitialData<String>.value('initial'),
        initialDataUpdatedAt: epoch,
      ));

      final state =
          queryCache.find(filters: QueryFilters(queryKey: key))!.state;
      expect(state.data, 'initial');
      expect(state.status, QueryStatus.success);
      expect(state.dataUpdatedAt, epoch);
    });

    testFakeAsync('should update initialData when Query exists without data',
        (time) async {
      final key = queryKey();
      var calls = 0;
      Future<String> queryFn(QueryFunctionContext _) async {
        calls++;
        await sleep(ms(100));
        return 'data';
      }

      final promise = queryClient.query<String>(QueryOptions<String>(
        queryKey: key,
        queryFn: queryFn,
        staleTime: StaleTime.duration(ms(1000)),
      ));

      await time.advance(ms(50));

      var state = queryClient.getQueryState<String>(key)!;
      expect(state.hasData, isFalse);
      expect(state.status, QueryStatus.pending);
      expect(state.fetchStatus, FetchStatus.fetching);

      final updatedAt = DateTime.fromMillisecondsSinceEpoch(10);
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: queryFn,
          staleTime: StaleTime.duration(ms(1000)),
          initialData: const InitialData<String>.value('initialData'),
          initialDataUpdatedAt: updatedAt,
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      state = queryClient.getQueryState<String>(key)!;
      expect(state.data, 'initialData');
      expect(state.dataUpdatedAt, updatedAt);
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

      // resetting should get us back to 'initialData'
      queryCache.find(filters: QueryFilters(queryKey: key))!.reset();

      state = queryClient.getQueryState<String>(key)!;
      expect(state.data, 'initialData');
      expect(state.status, QueryStatus.success);
      expect(state.fetchStatus, FetchStatus.idle);
    });

    testFakeAsync(
        'should not override fetching state when revert happens after new observer subscribes',
        (time) async {
      final key = queryKey();
      var count = 0;

      var calls = 0;
      Future<String> queryFn(QueryFunctionContext context) async {
        // Read `signal` to intentionally consume it so observer-removal uses
        // the revert-cancel path.
        context.signal;
        calls++;
        await sleep(ms(50));
        return 'data${count++}';
      }

      final query = queryCache.build<String>(
        queryClient,
        queryClient.defaultQueryOptions<String>(
            QueryOptions<String>(queryKey: key, queryFn: queryFn)),
      );

      final observer1 = queryClient.observe<String, String>(
        QueryObserverOptions<String>(queryKey: key, queryFn: queryFn),
      );

      query.addObserver(observer1);
      final promise1 = query.fetch();
      final caught1 =
          promise1.then<Object?>((_) => null, onError: (Object e) => e);

      await time.advance(ms(10));

      query.removeObserver(observer1);

      final observer2 = queryClient.observe<String, String>(
        QueryObserverOptions<String>(queryKey: key, queryFn: queryFn),
      );

      query.addObserver(observer2);

      query.fetch().ignore();

      expect(await caught1, isA<CancelledError>());
      await time.advance(ms(50));
      expect(query.state.fetchStatus, FetchStatus.idle);

      expect(calls, 2);

      expect(query.state.status, QueryStatus.success);
      expect(query.state.data, 'data1');
    });

    testFakeAsync(
        'should not increment dataUpdateCount when setting initialData on prefetched query',
        (time) async {
      final key = queryKey();
      String queryFn(QueryFunctionContext _) => 'fetched-data';

      // First prefetch the query (creates query without data)
      queryClient
          .query<String>(QueryOptions<String>(queryKey: key, queryFn: queryFn))
          .ignore();

      final query = queryCache.find(filters: QueryFilters(queryKey: key))!;
      expect(query.state.hasData, isFalse);
      expect(query.state.dataUpdateCount, 0);

      // Now create an observer with initialData
      final observer = queryClient.observe<String, String>(
        QueryObserverOptions<String>(
          queryKey: key,
          queryFn: queryFn,
          initialData: const InitialData<String>.value('initial-data'),
        ),
      );

      // The query should now have the initial data but dataUpdateCount should
      // still be 0 since this was not fetched data but initial data
      expect(query.state.data, 'initial-data');
      expect(query.state.dataUpdateCount, 0);

      // Get the initial state as captured by the observer
      expect(observer.currentResult.dataOrNull, 'initial-data');
      expect(observer.currentResult.isFetchedAfterMount, isFalse);

      // Now trigger a refetch through the observer to simulate real-world usage
      await observer.refetch();

      // After actual fetch, dataUpdateCount should increment
      expect(query.state.dataUpdateCount, 1);
      expect(query.state.data, 'fetched-data');

      // And isFetchedAfterMount should now be true
      expect(observer.currentResult.isFetchedAfterMount, isTrue);
    });
  });
}
