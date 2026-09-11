/// Regressions from the fifth review (two external reviews of `98443be`,
/// 2026-09-09) that concern the *lifecycle* of a fetch or a mutation run:
/// when the retryer exists, which future a caller holds, when a paused run is
/// released, how a bulk operation picks and re-picks its queries.
///
/// A file of its own rather than more cases in `port_specifics_test.dart`:
/// that file is the observer, structural-sharing and option-value side of the
/// same review, and the two were worked in parallel with a strict file split.
/// Both are port-only tests, so neither maps to an upstream file
/// (https://github.com/KoTTi97/flutter_query/issues/18). Cases are named by
/// the finding: `D` for review A, `F` for review B, `N` for the nits.
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('D7 / F03 — clear() during an async onMutate', () {
    testFakeAsync('an offline mutation settles instead of pausing forever',
        (time) async {
      final client = testClient()..mount();
      client.onlineManager.setOnline(false);
      final preparation = Completer<void>();
      final calls = <String>[];
      final observer = MutationObserver<int, int, void>(
        client,
        MutationOptions(
          onMutate: (_) => preparation.future,
          mutationFn: (v) {
            calls.add('mutationFn');
            return v;
          },
          onError: (error, _, __, ___) async => calls.add('onError'),
          onSettled: (_, error, __, ___, ____) async => calls.add('onSettled'),
        ),
      );
      Object? settledWith;
      unawaited(observer.mutateAsync(1).then<void>((_) => settledWith = 'data',
          onError: (Object error) => settledWith = error));
      client.clear();
      preparation.complete();
      await time.flushMicrotasks();
      client.onlineManager.setOnline(true);
      await time.advance(const Duration(days: 1));
      expect(settledWith, isA<CancelledError>());
      expect(calls, ['onError', 'onSettled']);
      expect(observer.currentResult.status, MutationStatus.error);
      observer.destroy();
      client.unmount();
      client.clear();
    });

    testFakeAsync('the same through an async cache-level onMutate',
        (time) async {
      final preparation = Completer<void>();
      final client = testClient(
        mutationCache: MutationCache(onMutate: (_, __) => preparation.future),
      )..mount();
      client.onlineManager.setOnline(false);
      var ran = 0;
      final observer = MutationObserver<int, int, void>(
        client,
        MutationOptions(mutationFn: (v) => ++ran),
      );
      Object? settledWith;
      unawaited(observer.mutateAsync(1).then<void>((_) => settledWith = 'data',
          onError: (Object error) => settledWith = error));
      client.clear();
      preparation.complete();
      await time.flushMicrotasks();
      client.onlineManager.setOnline(true);
      await time.advance(const Duration(days: 1));
      expect(settledWith, isA<CancelledError>());
      expect(ran, 0);
      observer.destroy();
      client.unmount();
      client.clear();
    });

    testFakeAsync('a mutation removed while queued behind its scope settles',
        (time) async {
      final client = testClient();
      final first = Completer<int>();
      final preparation = Completer<void>();
      final scope = const MutationScope('record');
      final running = MutationObserver<int, int, void>(
        client,
        MutationOptions(scope: scope, mutationFn: (_) => first.future),
      );
      final queued = MutationObserver<int, int, void>(
        client,
        MutationOptions(
          mutationKey: QueryKey(<Object?>['queued']),
          scope: scope,
          onMutate: (_) => preparation.future,
          mutationFn: (v) => v,
        ),
      );
      running.mutate(1);
      Object? settledWith;
      unawaited(queued.mutateAsync(2).then<void>((_) => settledWith = 'data',
          onError: (Object error) => settledWith = error));
      await time.flushMicrotasks();
      final mutation = client.mutationCache.find(
        filters: MutationFilters(mutationKey: QueryKey(<Object?>['queued'])),
      )!;
      client.mutationCache.remove(mutation);
      preparation.complete();
      await time.flushMicrotasks();
      // The scope is still busy: the removed mutation cannot start, and
      // nothing in the cache will ever release it.
      expect(settledWith, isA<CancelledError>());
      first.complete(1);
      await time.flushMicrotasks();
      expect(running.currentResult.status, MutationStatus.success);
      running.destroy();
      queued.destroy();
      client.clear();
    });
  });

  group('F04 / D19 — the retryer exists before the fetch is announced', () {
    testFakeAsync(
        'cancelQueries from the fetching notification stops the request',
        (time) async {
      final client = testClient();
      var calls = 0;
      final observer = client.observe<int, int>(QueryObserverOptions(
        queryKey: queryKey(),
        queryFn: (_) => ++calls,
      ));
      final unsubscribe = observer.subscribe((result) {
        if (result.isFetching) client.cancelQueries().ignore();
      });
      await time.flushMicrotasks();
      expect(calls, 0);
      expect(observer.currentResult.fetchStatus, FetchStatus.idle);
      unsubscribe();
      client.clear();
    });

    testFakeAsync('a re-entrant client.query joins the fetch just announced',
        (time) async {
      final client = testClient();
      var calls = 0;
      var joined = false;
      final responses = <Completer<int>>[];
      final options = QueryOptions<int>(
        queryKey: queryKey(),
        queryFn: (_) {
          calls++;
          final response = Completer<int>();
          responses.add(response);
          return response.future;
        },
      );
      client.queryCache.subscribe((event) {
        if (event is QueryUpdated &&
            event.action is QueryFetchAction &&
            !joined) {
          joined = true;
          client.query(options).ignore();
        }
      });
      final first = client.query(options);
      for (final response in responses) {
        response.complete(1);
      }
      expect(await first, 1);
      expect(calls, 1);
      client.clear();
    });

    testFakeAsync('clear() from a fetch listener: nothing runs afterwards',
        (time) async {
      final client = testClient();
      var calls = 0;
      client.queryCache.subscribe((event) {
        if (event is QueryUpdated && event.action is QueryFetchAction) {
          client.clear();
        }
      });
      final fetch = client.query<int>(QueryOptions(
        queryKey: queryKey(),
        queryFn: (_) => ++calls,
      ));
      await expectLater(fetch, throwsA(isA<CancelledError>()));
      expect(calls, 0);
      expect(client.queryCache.queries, isEmpty);
      client.clear();
    });

    testFakeAsync('unsubscribing from the fetching notification: one request',
        (time) async {
      final client = testClient();
      var calls = 0;
      final key = queryKey();
      final observer = client.observe<int, int>(QueryObserverOptions(
        queryKey: key,
        queryFn: (_) async {
          calls++;
          await sleep(ms(10));
          return calls;
        },
      ));
      // The first notification arrives synchronously, from inside
      // `subscribe`, so leaving is done through the observer itself.
      observer.subscribe((result) {
        if (result.isFetching) observer.destroy();
      });
      await time.advance(ms(10));
      // The function never read the signal, so the request finished and its
      // result is in the cache; nothing ran twice.
      expect(calls, 1);
      expect(client.getQueryData<int>(key), 1);
      client.clear();
    });

    testFakeAsync('refetch from the fetching notification: one request',
        (time) async {
      final client = testClient();
      var calls = 0;
      var refetched = false;
      final observer = client.observe<int, int>(QueryObserverOptions(
        queryKey: queryKey(),
        queryFn: (_) async {
          calls++;
          await sleep(ms(10));
          return calls;
        },
      ));
      final unsubscribe = observer.subscribe((result) {
        if (result.isFetching && !refetched) {
          refetched = true;
          observer.refetch().ignore();
        }
      });
      await time.advance(ms(10));
      expect(calls, 1);
      expect(observer.currentResult.dataOrNull, 1);
      unsubscribe();
      client.clear();
    });
  });

  group('F05 — every caller of a deduplicated fetch shares one outcome', () {
    testFakeAsync('a throwing structuralSharing hook fails both callers',
        (time) async {
      final client = testClient();
      final key = queryKey();
      final response = Completer<int>();
      final options = QueryOptions<int>(
        queryKey: key,
        queryFn: (_) => response.future,
        structuralSharing: (_, __) => throw StateError('sharing failed'),
      );
      final first = client.query(options);
      final second = client.query(options);
      response.complete(42);
      await expectLater(first, throwsStateError);
      await expectLater(second, throwsStateError);
      expect(client.getQueryState<int>(key)!.status, QueryStatus.error);
      client.clear();
    });

    testFakeAsync('the joining caller sees the cache written when it completes',
        (time) async {
      final client = testClient();
      final key = queryKey();
      final response = Completer<int>();
      var settledHook = false;
      final client2 = testClient(
        queryCache: QueryCache(onSettled: (_, __, ___, ____) {
          settledHook = true;
        }),
      );
      final options = QueryOptions<int>(
        queryKey: key,
        queryFn: (_) => response.future,
      );
      client2.query(options).ignore();
      final second = client2.query(options);
      response.complete(7);
      expect(await second, 7);
      expect(client2.getQueryData<int>(key), 7);
      expect(settledHook, isTrue);
      client.clear();
      client2.clear();
    });

    testFakeAsync('a cancel-refetch still hands the first caller to the second',
        (time) async {
      final client = testClient();
      final key = queryKey();
      var calls = 0;
      final observer = client.observe<int, int>(QueryObserverOptions(
        queryKey: key,
        queryFn: (_) async {
          final call = ++calls;
          await sleep(ms(10));
          return call;
        },
      ));
      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      client.setQueryData(key, 0);
      final first = observer.currentQuery.fetch();
      final second = observer.refetch();
      await time.advance(ms(20));
      expect(await first, 2);
      expect((await second).dataOrNull, 2);
      unsubscribe();
      client.clear();
    });
  });

  group('F06 — a scope change on a running mutation', () {
    testFakeAsync('does not strand the queue in the old scope', (time) async {
      final client = testClient();
      final response = Completer<int>();
      final a = MutationObserver<int, int, void>(
        client,
        MutationOptions(
          scope: const MutationScope('A'),
          mutationFn: (_) => response.future,
        ),
      );
      final b = MutationObserver<int, int, void>(
        client,
        MutationOptions(scope: const MutationScope('A'), mutationFn: (v) => v),
      );
      a.mutate(1);
      b.mutate(2);
      await time.flushMicrotasks();
      expect(b.currentResult.isPaused, isTrue);
      a.setOptions(MutationOptions(
        scope: const MutationScope('B'),
        mutationFn: (_) => response.future,
      ));
      response.complete(1);
      await time.flushMicrotasks();
      expect(a.currentResult.status, MutationStatus.success);
      expect(b.currentResult.status, MutationStatus.success);
      a.destroy();
      b.destroy();
      client.clear();
    });

    testFakeAsync('to unscoped: the old scope is still released', (time) async {
      final client = testClient();
      final response = Completer<int>();
      final a = MutationObserver<int, int, void>(
        client,
        MutationOptions(
          scope: const MutationScope('A'),
          mutationFn: (_) => response.future,
        ),
      );
      final b = MutationObserver<int, int, void>(
        client,
        MutationOptions(scope: const MutationScope('A'), mutationFn: (v) => v),
      );
      a.mutate(1);
      b.mutate(2);
      await time.flushMicrotasks();
      a.setOptions(MutationOptions(mutationFn: (_) => response.future));
      response.complete(1);
      await time.flushMicrotasks();
      expect(b.currentResult.status, MutationStatus.success);
      a.destroy();
      b.destroy();
      client.clear();
    });

    testFakeAsync('from unscoped: a later mutation in that scope is not queued',
        (time) async {
      final client = testClient();
      final response = Completer<int>();
      final a = MutationObserver<int, int, void>(
        client,
        MutationOptions(mutationFn: (_) => response.future),
      );
      a.mutate(1);
      await time.flushMicrotasks();
      a.setOptions(MutationOptions(
        scope: const MutationScope('A'),
        mutationFn: (_) => response.future,
      ));
      final b = MutationObserver<int, int, void>(
        client,
        MutationOptions(scope: const MutationScope('A'), mutationFn: (v) => v),
      );
      b.mutate(2);
      await time.flushMicrotasks();
      // `a` runs under the scope it started with — none — so `b` is not
      // behind it.
      expect(b.currentResult.status, MutationStatus.success);
      expect(a.currentResult.status, MutationStatus.pending);
      response.complete(1);
      await time.flushMicrotasks();
      a.destroy();
      b.destroy();
      client.clear();
    });
  });

  group('D5 — resumePausedMutations is gated per mutation', () {
    testFakeAsync(
        'an always-mode mutation paused in the background resumes on refocus '
        'while offline', (time) async {
      final client = testClient()..mount();
      client.onlineManager.setOnline(false);
      client.focusManager.setFocused(false);
      var attempts = 0;
      final observer = MutationObserver<int, int, void>(
        client,
        MutationOptions(
          networkMode: NetworkMode.always,
          retry: const RetryTimes(3),
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 10)),
          mutationFn: (v) async {
            attempts++;
            if (attempts == 1) throw StateError('first');
            return v;
          },
        ),
      );
      observer.mutate(1);
      await time.advance(ms(20));
      expect(attempts, 1);
      expect(observer.currentResult.isPaused, isTrue);
      client.focusManager.setFocused(true);
      await time.advance(ms(20));
      expect(attempts, 2);
      expect(observer.currentResult.status, MutationStatus.success);
      observer.destroy();
      client.unmount();
      client.clear();
    });

    testFakeAsync('an online-mode mutation is still left alone while offline',
        (time) async {
      final client = testClient();
      client.onlineManager.setOnline(false);
      var attempts = 0;
      final observer = MutationObserver<int, int, void>(
        client,
        MutationOptions(mutationFn: (v) => ++attempts),
      );
      observer.mutate(1);
      await time.flushMicrotasks();
      expect(observer.currentResult.isPaused, isTrue);
      // Completes at once rather than waiting for a network that is not
      // coming back inside this call.
      await client.resumePausedMutations();
      expect(attempts, 0);
      expect(observer.currentResult.isPaused, isTrue);
      client.onlineManager.setOnline(true);
      await client.resumePausedMutations();
      expect(attempts, 1);
      observer.destroy();
      client.clear();
    });
  });

  group('D6 — client.query does not write its retry rule into the query', () {
    testFakeAsync("an observer's retry policy survives a client.query",
        (time) async {
      final client = testClient();
      final key = queryKey();
      var attempts = 0;
      FutureOr<int> flaky(QueryFunctionContext _) {
        attempts++;
        if (attempts % 4 != 0) throw StateError('attempt $attempts');
        return attempts;
      }

      final observer = client.observe<int, int>(QueryObserverOptions(
        queryKey: key,
        queryFn: flaky,
        retry: const RetryTimes(3),
        retryDelay: const RetryDelay.fixed(Duration(milliseconds: 1)),
      ));
      final unsubscribe = observer.subscribe((_) {});
      await time.advance(ms(50));
      expect(attempts, 4);

      // The imperative call makes its one attempt (the fifth, which fails)
      // and its options land on the shared query — all but the retry rule.
      await expectLater(
        client.query<int>(QueryOptions(queryKey: key, queryFn: flaky)),
        throwsStateError,
      );
      expect(attempts, 5);
      expect(observer.currentQuery.options.retry, const RetryTimes(3));

      // The call's *other* resolved options did land — last options win, as
      // upstream — so the refetch backs off with the default delay now.
      client.invalidateQueries(filters: QueryFilters(queryKey: key)).ignore();
      await time.advance(const Duration(seconds: 10));
      expect(attempts, 8);
      expect(observer.currentResult.dataOrNull, 8);
      unsubscribe();
      client.clear();
    });

    testFakeAsync('client.query itself still makes one attempt by default',
        (time) async {
      final client = testClient();
      var attempts = 0;
      final fetch = client.query<int>(QueryOptions(
        queryKey: queryKey(),
        queryFn: (_) => throw StateError('attempt ${++attempts}'),
      ));
      await expectLater(fetch, throwsStateError);
      await time.advance(const Duration(seconds: 30));
      expect(attempts, 1);
      client.clear();
    });
  });

  group('D8 / F07 — invalidateQueries freezes its match set', () {
    testFakeAsync('a stale: false filter still refetches what it invalidated',
        (time) async {
      final client = testClient();
      var calls = 0;
      final observer = client.observe<int, int>(QueryObserverOptions(
        queryKey: queryKey(),
        queryFn: (_) => ++calls,
        staleTime: StaleTime.infinite,
      ));
      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      await client.invalidateQueries(
        filters: const QueryFilters(stale: false),
      );
      expect(calls, 2);
      unsubscribe();
      client.clear();
    });

    testFakeAsync('so does a predicate over isInvalidated', (time) async {
      final client = testClient();
      var calls = 0;
      final observer = client.observe<int, int>(QueryObserverOptions(
        queryKey: queryKey(),
        queryFn: (_) => ++calls,
        staleTime: StaleTime.infinite,
      ));
      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      await client.invalidateQueries(
        filters: QueryFilters(predicate: (query) => !query.state.isInvalidated),
      );
      expect(calls, 2);
      unsubscribe();
      client.clear();
    });
  });

  group('D9 / F11 — MutationCache.findAll and find iterate a copy', () {
    test('a predicate may remove the mutation it is shown', () {
      final client = testClient();
      for (var i = 0; i < 2; i++) {
        client.mutationCache.build<int, int, void>(
          client,
          client.defaultMutationOptions(
            MutationOptions<int, int, void>(mutationFn: (v) => v),
          ),
        );
      }
      final all = client.mutationCache.findAll(
        filters: MutationFilters(predicate: (mutation) {
          client.mutationCache.remove(mutation);
          return true;
        }),
      );
      expect(all, hasLength(2));
      expect(client.mutationCache.mutations, isEmpty);

      client.mutationCache.build<int, int, void>(
        client,
        client.defaultMutationOptions(
          MutationOptions<int, int, void>(mutationFn: (v) => v),
        ),
      );
      final found = client.mutationCache.find(
        filters: MutationFilters(predicate: (mutation) {
          client.mutationCache.remove(mutation);
          return true;
        }),
      );
      expect(found, isNotNull);
      expect(client.mutationCache.mutations, isEmpty);
      client.clear();
    });
  });

  group('D16 — cancelQueries batches', () {
    testFakeAsync('every revert lands in one scheduler round', (time) async {
      final client = testClient();
      var rounds = 0;
      client.notifyManager.setScheduler((callback) {
        rounds++;
        scheduleMicrotask(callback);
      });
      final reverted = <QueryKey>[];
      client.queryCache.subscribe(client.notifyManager.batchCalls((event) {
        if (event is QueryUpdated && event.action is QuerySetStateAction) {
          reverted.add(event.query.queryKey);
        }
      }));
      final gate = Completer<int>();
      final keys = [queryKey(), queryKey()];
      for (final key in keys) {
        client.setQueryData(key, 0);
        client
            .query<int>(
                QueryOptions(queryKey: key, queryFn: (_) => gate.future))
            .ignore();
      }
      await time.flushMicrotasks();
      rounds = 0;
      await client.cancelQueries();
      // The batch's one flush is a scheduled round; let it run.
      await time.flushMicrotasks();
      expect(reverted, keys);
      expect(rounds, 1);
      client.clear();
    });
  });

  group('N2 — QueryClient.observeInfinite', () {
    testFakeAsync('is the observer twin of infiniteQuery', (time) async {
      final client = testClient();
      final observer = client.observeInfinite<int, int, InfiniteData<int, int>>(
        InfiniteQueryObserverOptions(
          queryKey: queryKey(),
          pageFn: (context) => context.pageParam,
          initialPageParam: 0,
          getNextPageParam: (_, __, param, ___) => param + 1,
        ),
      );
      expect(observer, isA<InfiniteQueryObserver<int, int, Object?>>());
      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      await observer.fetchNextPage();
      expect(observer.currentResult.dataOrNull?.pages, [0, 1]);
      unsubscribe();
      client.clear();
    });
  });

  group('N3 — no gc timer while a query is observed', () {
    testFakeAsync('a fetch with a subscribed observer arms nothing',
        (time) async {
      final client = testClient();
      final observer = client.observe<int, int>(QueryObserverOptions(
        queryKey: queryKey(),
        queryFn: (_) => 1,
        staleTime: StaleTime.infinite,
      ));
      final unsubscribe = observer.subscribe((_) {});
      await time.flushMicrotasks();
      expect(observer.currentResult.dataOrNull, 1);
      expect(time.pendingTimers, 0);
      unsubscribe();
      // The observer leaving is what arms it.
      expect(time.pendingTimers, 1);
      client.clear();
      expect(time.pendingTimers, 0);
    });
  });

  group('N7 — MutationState has value equality', () {
    test('equal fields compare equal, a differing one does not', () {
      final now = DateTime(2026, 9, 9);
      MutationState<int, String, void> state({int data = 1}) =>
          MutationState<int, String, void>(
            status: MutationStatus.success,
            hasData: true,
            data: data,
            variables: 'v',
            hasVariables: true,
            submittedAt: now,
          );
      final a = state();
      final b = state();
      expect(identical(a, b), isFalse);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(state(data: 2))));
      expect(a, isNot(equals(a.copyWith(isPaused: true))));
    });
  });

  group('D3 — a throwing per-observer computation', () {
    testFakeAsyncGuarded(
        'is reported to the zone and does not become the shared fetch error',
        (time, uncaught) async {
      final client = testClient();
      final key = queryKey();
      var calls = 0;
      final good = client.observe<int, int>(
          QueryObserverOptions(queryKey: key, queryFn: (_) async => 1));
      final bad = client.observe<int, int>(QueryObserverOptions(
        queryKey: key,
        queryFn: (_) async => 1,
        // Fine at construction; throws from the fetch's own dispatch onward.
        staleTime: StaleTime.dynamic(
            (_) => ++calls > 1 ? throw StateError('stale') : StaleTime.zero),
      ));
      good.subscribe((_) {});
      bad.subscribe((_) {});
      await time.flushMicrotasks();
      final state = client.getQueryState<int>(key)!;
      expect(state.status, QueryStatus.success);
      expect(good.currentResult, isA<QuerySuccess<int>>());
      expect(uncaught.whereType<StateError>().map((e) => e.message),
          contains('stale'));
      good.destroy();
      bad.destroy();
      client.clear();
    });
  });

  group(
      'C4 / F3 / P3 (R4) — resumePausedMutations gates on the continuation '
      'rule', () {
    // The gate was the *start* rule (`canFetch`), so an `offlineFirst`
    // mutation paused mid-retry offline was awaited by every
    // `resumePausedMutations` — the one `mount()` runs before each focus
    // refetch included — and nothing offline could release it.
    testFakeAsync(
        'F3 / P3a (R4) resumePausedMutations completes while offline when '
        'the only paused mutation is an offlineFirst retry that needs the '
        'network', (time) async {
      final client = testClient();
      client.onlineManager.setOnline(false);
      var attempts = 0;
      final observer = MutationObserver<int, int, void>(
        client,
        MutationOptions(
          mutationFn: (v) {
            attempts++;
            if (attempts == 1) throw StateError('offline');
            return v;
          },
          networkMode: NetworkMode.offlineFirst,
          retry: const RetryPolicy.times(1),
          retryDelay: const RetryDelay.fixed(Duration.zero),
        ),
      );
      observer.mutate(1);
      await time.advance(Duration.zero);
      expect(attempts, 1, reason: 'offlineFirst makes its first attempt');
      expect(observer.currentResult.isPaused, isTrue);
      var completed = false;
      unawaited(client.resumePausedMutations().then((_) => completed = true));
      await time.advance(const Duration(days: 1));
      expect(completed, isTrue,
          reason: 'nothing can be continued offline; the call must not wait '
              'for the network');
      expect(attempts, 1);
      // The network's return is what releases it, through mount()'s
      // listener or a direct call.
      client.onlineManager.setOnline(true);
      await client.resumePausedMutations();
      await time.flushMicrotasks();
      expect(attempts, 2);
      expect(observer.currentResult.status, MutationStatus.success);
      observer.destroy();
      client.clear();
    });

    testFakeAsync(
        'F3 / P3b (R4) an offlineFirst mutation paused offline does not '
        'suppress the focus refetch of an independent networkMode.always '
        'query', (time) async {
      final client = testClient()..mount();
      client.onlineManager.setOnline(false);
      var reads = 0;
      final query = client.observe<int, int>(QueryObserverOptions(
        queryKey: queryKey(),
        queryFn: (_) => ++reads,
        networkMode: NetworkMode.always,
      ));
      final unsubscribe = query.subscribe((_) {});
      await time.flushMicrotasks();
      expect(reads, 1);
      // Control: with no paused mutation the focus refetch runs offline.
      client.focusManager.setFocused(false);
      client.focusManager.setFocused(true);
      await time.flushMicrotasks();
      expect(reads, 2);
      final mutation = MutationObserver<int, int, void>(
        client,
        MutationOptions(
          mutationFn: (_) => throw StateError('offline'),
          networkMode: NetworkMode.offlineFirst,
          retry: const RetryPolicy.times(1),
          retryDelay: const RetryDelay.fixed(Duration.zero),
        ),
      );
      mutation.mutate(1);
      await time.advance(Duration.zero);
      expect(mutation.currentResult.isPaused, isTrue);
      client.focusManager.setFocused(false);
      client.focusManager.setFocused(true);
      await time.advance(const Duration(days: 1));
      expect(reads, 3, reason: 'the always query can run offline');
      unsubscribe();
      mutation.destroy();
      client.onlineManager.setOnline(true);
      await time.flushMicrotasks();
      client.unmount();
      client.clear();
    });
  });

  group('C10 / P2 (R3) — continueMutation hands on the run, not the transport',
      () {
    // `resumePausedMutations` promised the settled state but returned the
    // retryer's future, which completes before the first callback runs; a
    // mounted client's reconnect refetch overtook the `onSuccess` cache
    // write it was meant to reflect.
    testFakeAsync(
        'P2a (R3) resumePausedMutations completes after the synchronous '
        'callbacks ran and the state settled', (time) async {
      final client = testClient();
      client.onlineManager.setOnline(false);
      final log = <String>[];
      final observer = MutationObserver<int, int, void>(
        client,
        MutationOptions(
          mutationFn: (value) => value,
          onSuccess: (_, __, ___) => log.add('onSuccess'),
          onSettled: (_, __, ___, ____, _____) => log.add('onSettled'),
        ),
      );
      observer.mutate(42);
      await time.flushMicrotasks();
      expect(observer.currentResult.isPaused, isTrue);
      client.onlineManager.setOnline(true);
      await client.resumePausedMutations();
      expect(log, ['onSuccess', 'onSettled'],
          reason: 'callbacks not yet run when resumePausedMutations '
              'completed');
      expect(observer.currentResult.status, MutationStatus.success,
          reason: 'state not settled when resumePausedMutations completed');
      observer.destroy();
      client.clear();
    });

    testFakeAsync(
        'P2b (R3) a mounted client refetches on reconnect after the resumed '
        'mutation\'s onSuccess wrote to the cache', (time) async {
      final client = testClient()..mount();
      final key = queryKey();
      final log = <String>[];
      client.setQueryData<int>(key, 0);
      final query = QueryObserver<int, int>(
        client,
        QueryObserverOptions(
          queryKey: key,
          queryFn: (_) {
            log.add('refetch');
            return 1;
          },
        ),
      );
      final unsubscribe = query.subscribe((_) {});
      await time.flushMicrotasks();
      log.clear();
      client.onlineManager.setOnline(false);
      final observer = MutationObserver<int, int, void>(
        client,
        MutationOptions(
          mutationFn: (value) => value,
          onSuccess: (_, __, ___) {
            log.add('onSuccess');
            client.setQueryData<int>(key, 99);
          },
        ),
      );
      observer.mutate(42);
      await time.flushMicrotasks();
      expect(observer.currentResult.isPaused, isTrue);
      client.onlineManager.setOnline(true);
      await time.flushMicrotasks();
      expect(log, ['onSuccess', 'refetch'],
          reason: 'the reconnect refetch must follow the cache write');
      unsubscribe();
      query.destroy();
      observer.destroy();
      client.unmount();
      client.clear();
    });

    testFakeAsync(
        'R3 resuming mutations awaits an async onSuccess and the settled '
        'state', (time) async {
      final client = testClient();
      client.onlineManager.setOnline(false);
      final hook = Completer<void>();
      final observer = MutationObserver<int, int, void>(
        client,
        MutationOptions(
            mutationFn: (value) => value,
            onSuccess: (_, __, ___) => hook.future),
      );
      observer.mutate(42);
      await time.flushMicrotasks();
      expect(observer.currentResult.isPaused, isTrue);
      client.onlineManager.setOnline(true);
      var resumed = false;
      unawaited(client.resumePausedMutations().then((_) => resumed = true));
      await time.flushMicrotasks();
      expect(observer.currentResult.status, MutationStatus.pending);
      expect(resumed, isFalse,
          reason: 'onSuccess is still running and the state is pending');
      hook.complete();
      await time.flushMicrotasks();
      expect(resumed, isTrue);
      expect(observer.currentResult.status, MutationStatus.success);
      observer.destroy();
      client.clear();
    });
  });

  group(
      'C12 / P7 — a restored pending mutation runs with the variables it '
      'was restored with', () {
    // `continueMutation` required `hasVariables`, which a `void`-variables
    // mutation is naturally restored without; `resumePausedMutations`
    // reported success and nothing ran.
    testFakeAsync(
        'P7 a restored pending mutation with hasVariables false and void '
        'variables is continued', (time) async {
      final client = testClient();
      var calls = 0;
      final mutation = client.mutationCache.build<String, void, void>(
        client,
        client.defaultMutationOptions<String, void, void>(
          MutationOptions<String, void, void>(mutationFn: (_) => 'x${++calls}'),
        ),
        state: MutationState<String, void, void>(
          isPaused: true,
          status: MutationStatus.pending,
          submittedAt: time.now,
        ),
      );
      await client.resumePausedMutations();
      await time.flushMicrotasks();
      expect(calls, 1, reason: 'upstream executes regardless of variables');
      expect(mutation.state.status, MutationStatus.success);
      expect(mutation.state.data, 'x1');
      client.clear();
    });

    testFakeAsync(
        'P7 a restored pending mutation with non-nullable variables and none '
        'restored is left alone', (time) async {
      final client = testClient();
      var calls = 0;
      final mutation = client.mutationCache.build<String, int, void>(
        client,
        client.defaultMutationOptions<String, int, void>(
          MutationOptions<String, int, void>(mutationFn: (_) => 'x${++calls}'),
        ),
        state: MutationState<String, int, void>(
          isPaused: true,
          status: MutationStatus.pending,
          submittedAt: time.now,
        ),
      );
      await client.resumePausedMutations();
      await time.flushMicrotasks();
      expect(calls, 0, reason: 'there is nothing to run it with');
      expect(mutation.state.status, MutationStatus.pending);
      client.clear();
    });
  });

  group('C11 / P6 — clear() and the rollback of a dropped paused mutation', () {
    // A paused mutation `clear()` drops fails with a `CancelledError` (the
    // rule since the third review, pinned by C-M3 and D7), so its `onError`
    // runs a few microtasks later — and the canonical optimistic rollback
    // `setQueryData(key, previous)` re-creates the query in the cache
    // `clear()` just emptied, gc timer included. Decided as the behaviour:
    // `clear()` empties, it does not seal, and a write after it is a write.
    // The teardown that must leave nothing pending lets the callbacks run
    // and clears again; the binding's `tearDownQueryClient` does.
    testFakeAsync(
        'P6 the onError rollback re-creates the query after clear(); a second '
        'clear once the callbacks ran leaves nothing pending', (time) async {
      final client = testClient();
      final key = queryKey();
      client.setQueryData<int>(key, 1);
      client.onlineManager.setOnline(false);
      final calls = <String>[];
      final observer = MutationObserver<int, int, int>(
        client,
        MutationOptions(
          mutationFn: (v) => v,
          onMutate: (_) {
            final previous = client.getQueryData<int>(key)!;
            client.setQueryData<int>(key, 2);
            return previous;
          },
          onError: (error, _, __, previous) {
            calls.add(error.runtimeType.toString());
            client.setQueryData<int>(key, previous!);
          },
        ),
      );
      observer.mutate(2);
      await time.flushMicrotasks();
      expect(observer.currentResult.isPaused, isTrue);
      expect(client.getQueryData<int>(key), 2);
      observer.destroy();
      client.clear();
      expect(client.queryCache.queries, isEmpty);
      expect(time.pendingTimers, 0, reason: 'right after clear()');
      await time.flushMicrotasks();
      // The rollback ran, with the cancellation as its error, and wrote.
      expect(calls, ['CancelledError']);
      expect(client.getQueryData<int>(key), 1);
      expect(client.queryCache.queries, hasLength(1));
      expect(time.pendingTimers, 1, reason: 'the re-created query\'s gc');
      client.clear();
      await time.flushMicrotasks();
      expect(client.queryCache.queries, isEmpty);
      expect(time.pendingTimers, 0);
    });
  });
}
