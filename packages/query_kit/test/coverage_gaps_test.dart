/// Port-only: public behaviour no ported case and no review regression
/// reached — error paths, the retryer's cancel-during-decision windows, and
/// getters and messages a user reads. Each case names the branch it holds.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:query_kit/query_kit.dart';
// Internal plumbing the package does not export: the retryer, and the
// structural-sharing bucket the suite pins.
import 'package:query_kit/src/hashing.dart' show spreadHash;
import 'package:query_kit/src/retryer.dart';
import 'package:query_kit/src/structural_sharing.dart' show sharingBucketOf;
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('QueriesObserver', () {
    test('refuses plain options when the data types differ', () {
      final client = testClient();
      // A plain shape reports its query's type; with TQueryData wider than
      // TData only a select can bridge the two.
      expect(
        () => QueriesObserver<Object, int>(client, [
          QueryObserverOptions<int>(queryKey: queryKey(), queryFn: (_) => 1),
        ]),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message',
            contains('requires select when data types differ'))),
      );
      client.clear();
    });

    testFakeAsync(
        'getOptimisticResult reports each query as a first build '
        'would see it', (time) async {
      final client = testClient();
      final cached = queryKey();
      client.setQueryData<int>(cached, 7);
      final observer = QueriesObserver<int, int>(client, [
        QueryObserverOptions<int>(queryKey: cached, queryFn: (_) => 8),
        QueryObserverOptions<int>(queryKey: queryKey(), queryFn: (_) => 9),
      ]);
      final optimistic = observer.getOptimisticResult();
      expect(optimistic, hasLength(2));
      expect(optimistic[0].dataOrNull, 7);
      expect(optimistic[1], isA<QueryPending<int>>());
      expect(optimistic[1].isFetching, isTrue,
          reason: 'a mount would fetch, and the first build says so');
      expect(() => optimistic.add(optimistic.first), throwsUnsupportedError);
      client.clear();
    });
  });

  group('AppFocusManager', () {
    test('refuses a negative refetchMinBackgroundDuration', () {
      expect(
          () => AppFocusManager(
              refetchMinBackgroundDuration: const Duration(seconds: -1)),
          throwsArgumentError);
    });

    test('an event source that reports no verdict counts as a focus event', () {
      final manager = AppFocusManager();
      final heard = <bool>[];
      final unsubscribe = manager.subscribe(heard.add);
      manager.setEventListener((setFocused) {
        setFocused(null);
        return () {};
      });
      expect(heard, [true]);
      unsubscribe();
    });
  });

  group('MutationCache', () {
    test('a removed mutation cannot be added again', () {
      final client = testClient();
      final mutation = client.mutationCache.build<int, int, void>(
        client,
        client.defaultMutationOptions(
            MutationOptions<int, int, void>(mutationFn: (v) => v)),
      );
      client.mutationCache.remove(mutation);
      expect(
          () => client.mutationCache.add(mutation), throwsA(isA<StateError>()));
      client.clear();
    });
  });

  group('messages and getters a user reads', () {
    testFakeAsync(
        'a query with no function fails with a message naming '
        'the key', (time) async {
      final client = testClient();
      final key = QueryKey(const ['no-fn']);
      Object? error;
      client
          .query(QueryOptions<int>(queryKey: key))
          .then<void>((_) {}, onError: (Object e) => error = e)
          .ignore();
      await time.flushMicrotasks();
      expect(error, isA<MissingQueryFunctionError>());
      expect(error.toString(),
          startsWith('No queryFn was provided for QueryKey(["no-fn"])'));
      expect(
          client.queryCache
              .find(filters: QueryFilters(queryKey: key))
              .toString(),
          'Query(QueryKey(["no-fn"]), QueryStatus.error)');
      client.clear();
    });

    testFakeAsync(
        'a mutation with no function fails with a message naming '
        'its key, and exposes its meta', (time) async {
      final client = testClient();
      final mutation = client.mutationCache.build<int, int, void>(
        client,
        client.defaultMutationOptions(MutationOptions<int, int, void>(
            mutationKey: QueryKey(const ['save']), meta: 'm')),
      );
      expect(mutation.meta, 'm');
      Object? error;
      mutation.execute(1).catchError((Object e) {
        error = e;
        return 0;
      }).ignore();
      await time.flushMicrotasks();
      expect(error, isA<MissingMutationFunctionError>());
      expect(error.toString(),
          startsWith('No mutationFn was provided for QueryKey(["save"])'));
      expect(const MissingMutationFunctionError(null).toString(),
          startsWith('No mutationFn was provided. '));
      expect(mutation.toString(),
          'Mutation(${mutation.mutationId}, MutationStatus.error)');
      client.clear();
    });

    test('a type error from a default names no key when there is none', () {
      expect(const QueryDataTypeError(null, int, String).toString(),
          startsWith('A default produced String where int was expected.'));
    });

    testFakeAsync(
        'MutationObserver exposes its resolved options, and the '
        "result's mutate runs the mutation", (time) async {
      final client = testClient();
      final observer = MutationObserver<int, int, void>(
          client, MutationOptions<int, int, void>(mutationFn: (v) async => v));
      expect(observer.options.retry, RetryPolicy.never,
          reason: 'resolved against the client defaults');
      final unsubscribe = observer.subscribe((_) {});
      observer.currentResult.mutate(4);
      await time.flushMicrotasks();
      expect(observer.currentResult.dataOrNull, 4);
      unsubscribe();
      client.clear();
    });

    testFakeAsyncGuarded(
        'an async per-call callback that fails reaches the '
        'zone, not the caller', (time, uncaught) async {
      final client = testClient();
      final observer = MutationObserver<int, int, void>(
          client, MutationOptions<int, int, void>(mutationFn: (v) async => v));
      // Per-call callbacks run for a subscribed observer only, as upstream's.
      final unsubscribe = observer.subscribe((_) {});
      final data = await observer.mutateAsync(1,
          callbacks: MutateCallbacks(onSuccess: (_, __, ___) async {
        throw StateError('callback');
      }));
      await time.flushMicrotasks();
      expect(data, 1);
      expect(uncaught, [isStateError]);
      unsubscribe();
      client.clear();
    });

    test('the status filter selects by status', () {
      final client = testClient();
      final done = queryKey();
      client.setQueryData<int>(done, 1);
      client.queryCache.build<int>(client,
          client.defaultQueryOptions(QueryOptions<int>(queryKey: queryKey())));
      expect(
          client.queryCache
              .findAll(filters: const QueryFilters(status: QueryStatus.success))
              .map((q) => q.queryKey),
          [done]);
      client.clear();
    });
  });

  group('QueryObserver edge results', () {
    testFakeAsync('a placeholder goes through the query\'s own sharing hook',
        (time) async {
      final client = testClient();
      final seen = <(int?, int)>[];
      int share(int? previous, int next) {
        seen.add((previous, next));
        return next;
      }

      final options = QueryObserverOptions<int>(
        queryKey: queryKey(),
        queryFn: (_) => sleep(ms(10)).then((_) => 1),
        placeholderData: const PlaceholderData.value(5),
        structuralSharing: share,
      );
      final observer = QueryObserver<int, int>(client, options);
      final result = observer.getOptimisticResult(options);
      expect(result.isPlaceholderData, isTrue);
      expect(result.dataOrNull, 5);
      expect(seen, contains((null, 5)));
      client.clear();
    });

    testFakeAsync(
        'an error state written without an error still reads as '
        'an error', (time) async {
      final client = testClient();
      final key = queryKey();
      final query = client.queryCache.build<int>(
          client, client.defaultQueryOptions(QueryOptions<int>(queryKey: key)));
      query.setState(const QueryState<int>(status: QueryStatus.error));
      final observer = QueryObserver<int, int>(
          client,
          QueryObserverOptions<int>(
              queryKey: key, queryFn: (_) => 1, enabled: Enabled.no));
      final result = observer.currentResult;
      expect(result, isA<QueryError<int>>());
      expect((result as QueryError<int>).error, isStateError);
      expect(result.stackTrace, StackTrace.empty);
      client.clear();
    });
  });

  group('structural sharing hashes the leaves it compares', () {
    test('typed data hashes as itself; equal InfiniteData alike', () {
      // A Uint8List is a List too; walked as one, it would hash as [1, 2].
      final bytes = Uint8List.fromList([1, 2]);
      expect(sharingBucketOf(bytes, 0), spreadHash(spreadHash(bytes.hashCode)));
      expect(sharingBucketOf(bytes, 0), isNot(sharingBucketOf([1, 2], 0)));
      expect(sharingBucketOf(InfiniteData(pages: [1], pageParams: [0]), 0),
          sharingBucketOf(InfiniteData(pages: [1], pageParams: [0]), 0));
    });

    test('a set of InfiniteData and typed data keeps the previous instance',
        () {
      final bytes = Uint8List.fromList([1, 2]);
      final previous = {
        InfiniteData(pages: [1], pageParams: [0]),
        bytes,
      };
      final next = {
        InfiniteData(pages: [1], pageParams: [0]),
        bytes,
      };
      expect(identical(replaceEqualDeep(previous, next), previous), isTrue);
    });
  });

  group('the retryer rejects when retries are cancelled mid-decision', () {
    Retryer<int> retryer({
      required RetryPolicy retry,
      RetryDelay retryDelay = const RetryDelay.fixed(Duration(seconds: 1)),
      void Function(int, Object, StackTrace)? onFail,
    }) =>
        Retryer<int>(
          fn: () async => throw StateError('attempt'),
          focusManager: AppFocusManager(),
          onlineManager: OnlineManager(),
          canRun: () => true,
          retry: retry,
          retryDelay: retryDelay,
          networkMode: NetworkMode.online,
          onFail: onFail,
        );

    testFakeAsync('by the retry policy itself', (time) async {
      late Retryer<int> subject;
      subject = retryer(retry: RetryPolicy.when((_, __, ___) {
        subject.cancelRetry();
        return true;
      }));
      Object? error;
      subject.start().catchError((Object e) {
        error = e;
        return 0;
      }).ignore();
      await time.flushMicrotasks();
      expect(error, isStateError);
      expect(subject.status, RetryerStatus.rejected);
    });

    testFakeAsync('by the retry delay', (time) async {
      late Retryer<int> subject;
      subject = retryer(
        retry: RetryPolicy.always,
        retryDelay: RetryDelay.dynamic((_, __) {
          subject.cancelRetry();
          return Duration.zero;
        }),
      );
      Object? error;
      subject.start().catchError((Object e) {
        error = e;
        return 0;
      }).ignore();
      await time.flushMicrotasks();
      expect(error, isStateError);
    });

    testFakeAsync('immediately, by onFail', (time) async {
      late Retryer<int> subject;
      var failures = 0;
      subject = retryer(
        retry: RetryPolicy.always,
        onFail: (count, _, __) {
          failures = count;
          subject.cancelRetry(immediately: true);
        },
      );
      Object? error;
      subject.start().catchError((Object e) {
        error = e;
        return 0;
      }).ignore();
      await time.flushMicrotasks();
      expect(error, isStateError);
      expect(failures, 1);
      expect(time.pendingTimers, 0, reason: 'no backoff timer left behind');
    });
  });

  testFakeAsyncGuarded('a resume that throws on reconnect reaches the zone',
      (time, uncaught) async {
    final client = QueryClient(
      mutationCache: _ThrowingResumeCache(),
      focusManager: AppFocusManager(),
      onlineManager: OnlineManager(),
      notifyManager: NotifyManager(),
    );
    client.mount();
    client.onlineManager.setOnline(false);
    client.onlineManager.setOnline(true);
    await time.flushMicrotasks();
    expect(uncaught, [isA<StateError>()]);
    client.unmount();
    client.clear();
  });
}

class _ThrowingResumeCache extends MutationCache {
  @override
  Future<void> resumePaused() async => throw StateError('resume');
}
