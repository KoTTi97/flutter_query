/// Port of `query-core/src/__tests__/mutationObserver.test.tsx` at upstream
/// `50680b98c`. Omissions and adaptations: `test/PORTING_NOTES.md`.
library;

import 'package:tanstack_query_core/tanstack_query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('mutationObserver', () {
    late QueryClient queryClient;

    setUp(() {
      queryClient = testClient();
      queryClient.mount();
    });

    tearDown(() => queryClient.clear());

    testFakeAsync(
        'onUnsubscribe should not remove the current mutation observer if there '
        'is still a subscription', (time) async {
      final mutation = MutationObserver<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          mutationFn: (text) async {
            await sleep(ms(20));
            return text;
          },
        ),
      );

      var subscription1Calls = 0;
      var subscription2Calls = 0;

      final unsubscribe1 = mutation.subscribe((_) => subscription1Calls++);
      final unsubscribe2 = mutation.subscribe((_) => subscription2Calls++);

      mutation.mutate('input');

      unsubscribe1();

      expect(subscription1Calls, 1);
      expect(subscription2Calls, 1);

      await time.advance(ms(20));
      expect(subscription1Calls, 1);
      expect(subscription2Calls, 2);

      unsubscribe2();
    });

    testFakeAsync('unsubscribe should remove observer to trigger GC',
        (time) async {
      final mutation = MutationObserver<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          mutationFn: (text) async {
            await sleep(ms(5));
            return text;
          },
          gcTime: const GcTime.duration(Duration(milliseconds: 10)),
        ),
      );

      final unsubscribe = mutation.subscribe((_) {});

      mutation.mutate('input');

      await time.advance(ms(5));
      expect(queryClient.mutationCache.findAll(), hasLength(1));

      unsubscribe();

      await time.advance(ms(10));
      expect(queryClient.mutationCache.findAll(), isEmpty);
    });

    testFakeAsync(
        'resubscribing should reattach the observer to the in-flight mutation',
        (time) async {
      final mutation = MutationObserver<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          mutationFn: (text) async {
            await sleep(ms(20));
            return text;
          },
        ),
      );

      final unsubscribe = mutation.subscribe((_) {});

      mutation.mutate('input');

      unsubscribe();

      var calls = 0;
      mutation.subscribe((_) => calls++);

      await time.advance(ms(20));
      expect(mutation.currentResult.status, MutationStatus.success);
      expect(mutation.currentResult.dataOrNull, 'input');
      expect(calls, 1);
    });

    testFakeAsync(
        'resubscribing should pick up a mutation that settled while unsubscribed',
        (time) async {
      final mutation = MutationObserver<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          mutationFn: (text) async {
            await sleep(ms(20));
            return text;
          },
        ),
      );

      final unsubscribe = mutation.subscribe((_) {});

      mutation.mutate('input');

      unsubscribe();

      await time.advance(ms(20));
      mutation.subscribe((_) {});

      expect(mutation.currentResult.status, MutationStatus.success);
      expect(mutation.currentResult.dataOrNull, 'input');
    });

    testFakeAsync('reset should remove observer to trigger GC', (time) async {
      final mutation = MutationObserver<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          mutationFn: (text) async {
            await sleep(ms(5));
            return text;
          },
          gcTime: const GcTime.duration(Duration(milliseconds: 10)),
        ),
      );

      final unsubscribe = mutation.subscribe((_) {});

      mutation.mutate('input');

      await time.advance(ms(5));
      expect(queryClient.mutationCache.findAll(), hasLength(1));

      mutation.reset();

      await time.advance(ms(10));
      expect(queryClient.mutationCache.findAll(), isEmpty);

      unsubscribe();
    });

    testFakeAsync('changing mutation keys should reset the observer',
        (time) async {
      final key = queryKey();
      final mutation = MutationObserver<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          mutationKey: key.append(<Object?>['1']),
          mutationFn: (text) async {
            await sleep(ms(5));
            return text;
          },
        ),
      );

      final unsubscribe = mutation.subscribe((_) {});

      mutation.mutate('input');

      await time.advance(ms(5));
      expect(mutation.currentResult.status, MutationStatus.success);
      expect(mutation.currentResult.dataOrNull, 'input');

      mutation.setOptions(
        MutationOptions<String, String, void>(
          mutationKey: key.append(<Object?>['2']),
        ),
      );

      expect(mutation.currentResult.status, MutationStatus.idle);

      unsubscribe();
    });

    testFakeAsync(
        'changing mutation keys should not affect already existing mutations',
        (time) async {
      final key = queryKey();
      final observer = MutationObserver<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          mutationKey: key.append(<Object?>['1']),
          mutationFn: (text) async {
            await sleep(ms(5));
            return text;
          },
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      observer.mutate('input');

      await time.advance(ms(5));
      var existing = queryClient.mutationCache
          .find(MutationFilters(mutationKey: key.append(<Object?>['1'])))!;
      expect(existing.options.mutationKey, key.append(<Object?>['1']));
      expect(existing.state.status, MutationStatus.success);
      expect(existing.state.data, 'input');

      observer.setOptions(
        MutationOptions<String, String, void>(
          mutationKey: key.append(<Object?>['2']),
        ),
      );

      existing = queryClient.mutationCache
          .find(MutationFilters(mutationKey: key.append(<Object?>['1'])))!;
      expect(existing.options.mutationKey, key.append(<Object?>['1']));
      expect(existing.state.status, MutationStatus.success);
      expect(existing.state.data, 'input');

      unsubscribe();
    });

    testFakeAsync(
        'changing mutation meta should not affect successful mutations',
        (time) async {
      final observer = MutationObserver<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          meta: const <String, int>{'a': 1},
          mutationFn: (text) async {
            await sleep(ms(5));
            return text;
          },
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      observer.mutate('input');

      await time.advance(ms(5));
      var found = queryClient.mutationCache.find(const MutationFilters())!;
      expect(found.options.meta, const <String, int>{'a': 1});
      expect(found.state.status, MutationStatus.success);
      expect(found.state.data, 'input');

      observer.setOptions(
        const MutationOptions<String, String, void>(
          meta: <String, int>{'a': 2},
        ),
      );

      found = queryClient.mutationCache.find(const MutationFilters())!;
      expect(found.options.meta, const <String, int>{'a': 1});
      expect(found.state.status, MutationStatus.success);

      unsubscribe();
    });

    testFakeAsync(
        'mutation cache should have different meta when updated between mutations',
        (time) async {
      Future<String> mutationFn(String text) async {
        await sleep(ms(5));
        return text;
      }

      final observer = MutationObserver<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          meta: const <String, int>{'a': 1},
          mutationFn: mutationFn,
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      observer.mutate('input');
      await time.advance(ms(5));

      observer.setOptions(
        MutationOptions<String, String, void>(
          meta: const <String, int>{'a': 2},
          mutationFn: mutationFn,
        ),
      );

      observer.mutate('input');
      await time.advance(ms(5));

      final mutations = queryClient.mutationCache.findAll();
      expect(mutations[0].options.meta, const <String, int>{'a': 1});
      expect(mutations[0].state.status, MutationStatus.success);
      expect(mutations[0].state.data, 'input');
      expect(mutations[1].options.meta, const <String, int>{'a': 2});
      expect(mutations[1].state.status, MutationStatus.success);
      expect(mutations[1].state.data, 'input');

      unsubscribe();
    });

    testFakeAsync('changing mutation meta should not affect rejected mutations',
        (time) async {
      final observer = MutationObserver<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          meta: const <String, int>{'a': 1},
          mutationFn: (_) async {
            await sleep(ms(5));
            throw Exception('err');
          },
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      observer.mutate('input');

      await time.advance(ms(5));
      var found = queryClient.mutationCache.find(const MutationFilters())!;
      expect(found.options.meta, const <String, int>{'a': 1});
      expect(found.state.status, MutationStatus.error);

      observer.setOptions(
        const MutationOptions<String, String, void>(
          meta: <String, int>{'a': 2},
        ),
      );

      found = queryClient.mutationCache.find(const MutationFilters())!;
      expect(found.options.meta, const <String, int>{'a': 1});
      expect(found.state.status, MutationStatus.error);

      unsubscribe();
    });

    testFakeAsync('changing mutation meta should affect pending mutations',
        (time) async {
      final observer = MutationObserver<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          meta: const <String, int>{'a': 1},
          mutationFn: (text) async {
            await sleep(ms(20));
            return text;
          },
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      observer.mutate('input');
      await time.advance(ms(5));
      var found = queryClient.mutationCache.find(const MutationFilters())!;
      expect(found.options.meta, const <String, int>{'a': 1});
      expect(found.state.status, MutationStatus.pending);

      observer.setOptions(
        const MutationOptions<String, String, void>(
          meta: <String, int>{'a': 2},
        ),
      );

      found = queryClient.mutationCache.find(const MutationFilters())!;
      expect(found.options.meta, const <String, int>{'a': 2});
      expect(found.state.status, MutationStatus.pending);

      unsubscribe();
      await time.advance(ms(20));
    });

    testFakeAsync(
        'mutation callbacks should be called in correct order with correct '
        'arguments for success case', (time) async {
      final successes = <(String, String, Object?)>[];
      final settled = <(String?, Object?, String, Object?)>[];

      final observer = MutationObserver<String, String, Object?>(
        queryClient,
        MutationOptions<String, String, Object?>(
          mutationFn: (text) => Future<String>.value(text.toUpperCase()),
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      observer.mutate(
        'success',
        callbacks: MutateCallbacks<String, String, Object?>(
          onSuccess: (data, variables, onMutateResult) =>
              successes.add((data, variables, onMutateResult)),
          onSettled: (data, error, _, variables, onMutateResult) =>
              settled.add((data, error, variables, onMutateResult)),
        ),
      );

      await time.flushMicrotasks();

      expect(successes, [('SUCCESS', 'success', null)]);
      expect(settled, [('SUCCESS', null, 'success', null)]);

      unsubscribe();
    });

    testFakeAsync(
        'mutation callbacks should be called in correct order with correct '
        'arguments for error case', (time) async {
      final errors = <(Object, String, Object?)>[];
      final settled = <(String?, Object?, String, Object?)>[];

      final error = Exception('error');
      final observer = MutationObserver<String, String, Object?>(
        queryClient,
        MutationOptions<String, String, Object?>(
          mutationFn: (_) => Future<String>.error(error),
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      observer.mutate(
        'error',
        callbacks: MutateCallbacks<String, String, Object?>(
          onError: (error, _, variables, onMutateResult) =>
              errors.add((error, variables, onMutateResult)),
          onSettled: (data, error, _, variables, onMutateResult) =>
              settled.add((data, error, variables, onMutateResult)),
        ),
      );

      await time.flushMicrotasks();

      expect(errors, [(error, 'error', null)]);
      expect(settled, [(null, error, 'error', null)]);

      unsubscribe();
    });

    group('erroneous mutation callback', () {
      testFakeAsyncGuarded('onSuccess and onSettled is reported to the zone',
          (time, uncaught) async {
        final onSuccessError = Exception('onSuccess-error');
        final onSettledError = Exception('onSettled-error');
        var onSuccessCalls = 0;
        var onSettledCalls = 0;

        final observer = MutationObserver<String, String, void>(
          queryClient,
          MutationOptions<String, String, void>(
            mutationFn: (text) => Future<String>.value(text.toUpperCase()),
          ),
        );

        var notifications = 0;
        final unsubscribe = observer.subscribe((_) => notifications++);

        observer.mutate(
          'success',
          callbacks: MutateCallbacks<String, String, void>(
            onSuccess: (_, __, ___) {
              onSuccessCalls++;
              throw onSuccessError;
            },
            onSettled: (_, __, ___, ____, _____) {
              onSettledCalls++;
              throw onSettledError;
            },
          ),
        );

        await time.flushMicrotasks();

        expect(onSuccessCalls, 1);
        expect(onSettledCalls, 1);

        expect(uncaught, <Object>[onSuccessError, onSettledError]);

        expect(notifications, 2);

        unsubscribe();
      });

      testFakeAsyncGuarded('onError and onSettled is reported to the zone',
          (time, uncaught) async {
        final onErrorError = Exception('onError-error');
        final onSettledError = Exception('onSettled-error');
        var onErrorCalls = 0;
        var onSettledCalls = 0;

        final error = Exception('error');
        final observer = MutationObserver<String, String, void>(
          queryClient,
          MutationOptions<String, String, void>(
            mutationFn: (_) => Future<String>.error(error),
          ),
        );

        var notifications = 0;
        final unsubscribe = observer.subscribe((_) => notifications++);

        observer.mutate(
          'error',
          callbacks: MutateCallbacks<String, String, void>(
            onError: (_, __, ___, ____) {
              onErrorCalls++;
              throw onErrorError;
            },
            onSettled: (_, __, ___, ____, _____) {
              onSettledCalls++;
              throw onSettledError;
            },
          ),
        );

        await time.flushMicrotasks();

        expect(onErrorCalls, 1);
        expect(onSettledCalls, 1);

        expect(uncaught, <Object>[onErrorError, onSettledError]);

        expect(notifications, 2);

        unsubscribe();
      });
    });

    testFakeAsync(
        'should not notify cache when setOptions is called with same options',
        (time) async {
      Future<String> mutationFn(String text) => Future<String>.value(text);
      final observer = MutationObserver<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(mutationFn: mutationFn),
      );

      final unsubscribe = observer.subscribe((_) {});
      observer.mutate('input');
      await time.flushMicrotasks();

      final events = <MutationCacheEvent>[];
      final unsubscribeCache = queryClient.mutationCache.subscribe(events.add);

      // Call setOptions with the same options
      observer.setOptions(
        MutationOptions<String, String, void>(mutationFn: mutationFn),
      );

      expect(
        events.whereType<MutationObserverOptionsUpdated>(),
        isEmpty,
      );

      unsubscribeCache();
      unsubscribe();
    });
  });
}
