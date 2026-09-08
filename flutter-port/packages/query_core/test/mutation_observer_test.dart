import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Port of `query/packages/query-core/src/__tests__/mutationObserver.test.tsx`.
void main() {
  late QueryClient queryClient;

  setUp(() {
    queryClient = QueryClient();
    queryClient.mount();
  });

  tearDown(() {
    queryClient.clear();
    queryClient.unmount();
  });

  MutationOptions<String, String, Object?> upper({
    Duration delay = const Duration(milliseconds: 5),
    MutationKey? mutationKey,
    Object? meta,
    GcDuration? gcTime,
  }) =>
      MutationOptions<String, String, Object?>(
        mutationKey: mutationKey,
        meta: meta,
        gcTime: gcTime,
        mutationFn: (text, _) => sleep(delay).then((_) => text),
      );

  testFakeAsync(
    'onUnsubscribe should not remove the current mutation observer if there is '
    'still a subscription',
    (time) async {
      final mutation = MutationObserver<String, String, Object?>(
        queryClient,
        upper(delay: ms(20)),
      );

      var handler1 = 0;
      var handler2 = 0;

      final unsubscribe1 = mutation.subscribe((_) => handler1++);
      final unsubscribe2 = mutation.subscribe((_) => handler2++);

      mutation.mutate('input').ignore();

      unsubscribe1();

      expect(handler1, 1);
      expect(handler2, 1);

      await time.advance(ms(20));
      expect(handler1, 1);
      expect(handler2, 2);

      unsubscribe2();
    },
  );

  testFakeAsync('unsubscribe should remove the observer to trigger GC', (
    time,
  ) async {
    final mutation = MutationObserver<String, String, Object?>(
      queryClient,
      upper(gcTime: const GcDuration.of(Duration(milliseconds: 10))),
    );

    final unsubscribe = mutation.subscribe((_) {});

    mutation.mutate('input').ignore();

    await time.advance(ms(5));
    expect(queryClient.mutationCache.findAll(), hasLength(1));

    unsubscribe();

    await time.advance(ms(10));
    expect(queryClient.mutationCache.findAll(), isEmpty);
  });

  testFakeAsync(
    'resubscribing should reattach the observer to the in-flight mutation',
    (time) async {
      final mutation = MutationObserver<String, String, Object?>(
        queryClient,
        upper(delay: ms(20)),
      );

      final unsubscribe = mutation.subscribe((_) {});

      mutation.mutate('input').ignore();

      unsubscribe();

      var notifications = 0;
      mutation.subscribe((_) => notifications++);

      await time.advance(ms(20));

      expect(mutation.result, isA<MutationSuccess<String, String, Object?>>());
      expect(mutation.result.dataOrNull, 'input');
      expect(notifications, 1);
    },
  );

  testFakeAsync(
    'resubscribing should pick up a mutation that settled while unsubscribed',
    (time) async {
      final mutation = MutationObserver<String, String, Object?>(
        queryClient,
        upper(delay: ms(20)),
      );

      final unsubscribe = mutation.subscribe((_) {});

      mutation.mutate('input').ignore();

      unsubscribe();

      await time.advance(ms(20));
      mutation.subscribe((_) {});

      expect(mutation.result, isA<MutationSuccess<String, String, Object?>>());
      expect(mutation.result.dataOrNull, 'input');
    },
  );

  testFakeAsync('reset should remove the observer to trigger GC', (time) async {
    final mutation = MutationObserver<String, String, Object?>(
      queryClient,
      upper(gcTime: const GcDuration.of(Duration(milliseconds: 10))),
    );

    final unsubscribe = mutation.subscribe((_) {});

    mutation.mutate('input').ignore();

    await time.advance(ms(5));
    expect(queryClient.mutationCache.findAll(), hasLength(1));

    mutation.reset();

    await time.advance(ms(10));
    expect(queryClient.mutationCache.findAll(), isEmpty);

    unsubscribe();
  });

  testFakeAsync('changing mutation keys should reset the observer', (
    time,
  ) async {
    final key = queryKey();
    final mutation = MutationObserver<String, String, Object?>(
      queryClient,
      upper(mutationKey: QueryKey([...key.parts, '1'])),
    );

    final unsubscribe = mutation.subscribe((_) {});

    mutation.mutate('input').ignore();

    await time.advance(ms(5));
    expect(mutation.result, isA<MutationSuccess<String, String, Object?>>());
    expect(mutation.result.dataOrNull, 'input');

    mutation.setOptions(
      MutationOptions<String, String, Object?>(
        mutationKey: QueryKey([...key.parts, '2']),
      ),
    );

    expect(mutation.result, isA<MutationIdle<String, String, Object?>>());

    unsubscribe();
  });

  testFakeAsync(
    'changing mutation keys should not affect already existing mutations',
    (time) async {
      final key = queryKey();
      final first = QueryKey([...key.parts, '1']);

      final observer = MutationObserver<String, String, Object?>(
        queryClient,
        upper(mutationKey: first),
      );

      final unsubscribe = observer.subscribe((_) {});

      observer.mutate('input').ignore();

      await time.advance(ms(5));
      final mutation = queryClient.mutationCache.find(first)!;
      expect(mutation.options.mutationKey, first);
      expect(mutation.state.status, MutationStatus.success);
      expect(mutation.state.data, 'input');

      observer.setOptions(
        MutationOptions<String, String, Object?>(
          mutationKey: QueryKey([...key.parts, '2']),
        ),
      );

      final unchanged = queryClient.mutationCache.find(first)!;
      expect(unchanged.options.mutationKey, first);
      expect(unchanged.state.status, MutationStatus.success);
      expect(unchanged.state.data, 'input');

      unsubscribe();
    },
  );

  testFakeAsync(
    'changing mutation meta should not affect successful mutations',
    (time) async {
      final observer = MutationObserver<String, String, Object?>(
        queryClient,
        upper(meta: const {'a': 1}),
      );

      final unsubscribe = observer.subscribe((_) {});

      observer.mutate('input').ignore();

      await time.advance(ms(5));
      var mutation = queryClient.mutationCache.mutations.first;
      expect(mutation.options.meta, const {'a': 1});
      expect(mutation.state.status, MutationStatus.success);

      observer.setOptions(
        const MutationOptions<String, String, Object?>(meta: {'a': 2}),
      );

      mutation = queryClient.mutationCache.mutations.first;
      expect(mutation.options.meta, const {'a': 1});
      expect(mutation.state.status, MutationStatus.success);

      unsubscribe();
    },
  );

  testFakeAsync(
    'mutation cache should have different meta when updated between mutations',
    (time) async {
      Future<String> mutationFn(String text, MutationFunctionContext _) =>
          sleep(ms(5)).then((_) => text);

      final observer = MutationObserver<String, String, Object?>(
        queryClient,
        MutationOptions<String, String, Object?>(
          meta: const {'a': 1},
          mutationFn: mutationFn,
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      observer.mutate('input').ignore();
      await time.advance(ms(5));

      observer.setOptions(
        MutationOptions<String, String, Object?>(
          meta: const {'a': 2},
          mutationFn: mutationFn,
        ),
      );

      observer.mutate('input').ignore();
      await time.advance(ms(5));

      final mutations = queryClient.mutationCache.findAll();
      expect(mutations[0].options.meta, const {'a': 1});
      expect(mutations[0].state.status, MutationStatus.success);
      expect(mutations[0].state.data, 'input');
      expect(mutations[1].options.meta, const {'a': 2});
      expect(mutations[1].state.status, MutationStatus.success);
      expect(mutations[1].state.data, 'input');

      unsubscribe();
    },
  );

  testFakeAsync('changing mutation meta should not affect rejected mutations', (
    time,
  ) async {
    final observer = MutationObserver<String, String, Object?>(
      queryClient,
      MutationOptions<String, String, Object?>(
        meta: const {'a': 1},
        mutationFn: (_, _) =>
            sleep(ms(5)).then((_) => Future<String>.error(StateError('err'))),
      ),
    );

    final unsubscribe = observer.subscribe((_) {});

    observer.mutate('input').ignore();

    await time.advance(ms(5));
    var mutation = queryClient.mutationCache.mutations.first;
    expect(mutation.options.meta, const {'a': 1});
    expect(mutation.state.status, MutationStatus.error);

    observer.setOptions(
      const MutationOptions<String, String, Object?>(meta: {'a': 2}),
    );

    mutation = queryClient.mutationCache.mutations.first;
    expect(mutation.options.meta, const {'a': 1});
    expect(mutation.state.status, MutationStatus.error);

    unsubscribe();
  });

  testFakeAsync('changing mutation meta should affect pending mutations', (
    time,
  ) async {
    final observer = MutationObserver<String, String, Object?>(
      queryClient,
      upper(delay: ms(20), meta: const {'a': 1}),
    );

    final unsubscribe = observer.subscribe((_) {});

    observer.mutate('input').ignore();
    await time.advance(ms(5));

    var mutation = queryClient.mutationCache.mutations.first;
    expect(mutation.options.meta, const {'a': 1});
    expect(mutation.state.status, MutationStatus.pending);

    observer.setOptions(
      const MutationOptions<String, String, Object?>(meta: {'a': 2}),
    );

    mutation = queryClient.mutationCache.mutations.first;
    expect(mutation.options.meta, const {'a': 2});
    expect(mutation.state.status, MutationStatus.pending);

    unsubscribe();
    await time.advance(ms(20));
  });

  testFakeAsync(
    'mutation callbacks should be called with the right arguments on success',
    (time) async {
      final successCalls = <List<Object?>>[];
      final settledCalls = <List<Object?>>[];

      final observer = MutationObserver<String, String, Object?>(
        queryClient,
        MutationOptions<String, String, Object?>(
          mutationFn: (text, _) async => text.toUpperCase(),
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      observer
          .mutate(
            'success',
            callbacks: MutateCallbacks<String, String, Object?>(
              onSuccess: (data, variables, onMutateResult, context) =>
                  successCalls.add([data, variables, onMutateResult, context]),
              onSettled: (data, error, _, variables, onMutateResult, context) =>
                  settledCalls.add([
                data,
                error,
                variables,
                onMutateResult,
                context,
              ]),
            ),
          )
          .ignore();

      await time.advance(Duration.zero);

      expect(successCalls, hasLength(1));
      expect(successCalls.single[0], 'SUCCESS');
      expect(successCalls.single[1], 'success');
      expect(successCalls.single[2], isNull);
      expect(
        (successCalls.single[3]! as MutationFunctionContext).mutationKey,
        isNull,
      );

      expect(settledCalls, hasLength(1));
      expect(settledCalls.single[0], 'SUCCESS');
      expect(settledCalls.single[1], isNull);
      expect(settledCalls.single[2], 'success');
      expect(settledCalls.single[3], isNull);

      unsubscribe();
    },
  );

  testFakeAsync(
    'mutation callbacks should be called with the right arguments on error',
    (time) async {
      final errorCalls = <List<Object?>>[];
      final settledCalls = <List<Object?>>[];
      final error = StateError('error');

      final observer = MutationObserver<String, String, Object?>(
        queryClient,
        MutationOptions<String, String, Object?>(
          mutationFn: (_, _) => Future<String>.error(error),
        ),
      );

      final unsubscribe = observer.subscribe((_) {});

      observer
          .mutate(
            'error',
            callbacks: MutateCallbacks<String, String, Object?>(
              onError: (error, _, variables, onMutateResult, context) =>
                  errorCalls.add([error, variables, onMutateResult, context]),
              onSettled: (data, error, _, variables, onMutateResult, context) =>
                  settledCalls.add([
                data,
                error,
                variables,
                onMutateResult,
                context,
              ]),
            ),
          )
          .ignore();

      await time.advance(Duration.zero);

      expect(errorCalls, hasLength(1));
      expect(errorCalls.single[0], same(error));
      expect(errorCalls.single[1], 'error');
      expect(errorCalls.single[2], isNull);

      expect(settledCalls, hasLength(1));
      expect(settledCalls.single[0], isNull);
      expect(settledCalls.single[1], same(error));
      expect(settledCalls.single[2], 'error');
      expect(settledCalls.single[3], isNull);

      unsubscribe();
    },
  );

  group('erroneous mutation callback', () {
    testFakeAsyncGuarded(
      'a throwing onSuccess and onSettled are reported to the zone',
      (time, uncaught) async {
        final onSuccessError = StateError('onSuccess-error');
        final onSettledError = StateError('onSettled-error');
        var successCalls = 0;
        var settledCalls = 0;
        var notifications = 0;

        final observer = MutationObserver<String, String, Object?>(
          queryClient,
          MutationOptions<String, String, Object?>(
            mutationFn: (text, _) async => text.toUpperCase(),
          ),
        );

        final unsubscribe = observer.subscribe((_) => notifications++);

        observer
            .mutate(
              'success',
              callbacks: MutateCallbacks<String, String, Object?>(
                onSuccess: (_, _, _, _) {
                  successCalls++;
                  throw onSuccessError;
                },
                onSettled: (_, _, _, _, _, _) {
                  settledCalls++;
                  throw onSettledError;
                },
              ),
            )
            .ignore();

        await time.advance(Duration.zero);

        expect(successCalls, 1);
        expect(settledCalls, 1);
        expect(uncaught, [same(onSuccessError), same(onSettledError)]);
        expect(notifications, 2);

        unsubscribe();
      },
    );

    testFakeAsyncGuarded(
      'a throwing onError and onSettled are reported to the zone',
      (time, uncaught) async {
        final onErrorError = StateError('onError-error');
        final onSettledError = StateError('onSettled-error');
        final error = StateError('error');
        var errorCalls = 0;
        var settledCalls = 0;
        var notifications = 0;

        final observer = MutationObserver<String, String, Object?>(
          queryClient,
          MutationOptions<String, String, Object?>(
            mutationFn: (_, _) => Future<String>.error(error),
          ),
        );

        final unsubscribe = observer.subscribe((_) => notifications++);

        observer
            .mutate(
              'error',
              callbacks: MutateCallbacks<String, String, Object?>(
                onError: (_, _, _, _, _) {
                  errorCalls++;
                  throw onErrorError;
                },
                onSettled: (_, _, _, _, _, _) {
                  settledCalls++;
                  throw onSettledError;
                },
              ),
            )
            .ignore();

        await time.advance(Duration.zero);

        expect(errorCalls, 1);
        expect(settledCalls, 1);
        expect(uncaught, [same(onErrorError), same(onSettledError)]);
        expect(notifications, 2);

        unsubscribe();
      },
    );
  });

  test(
      'should not notify the cache when setOptions is called with the same '
      'options', () {
    final observer = MutationObserver<String, String, Object?>(
      queryClient,
      MutationOptions<String, String, Object?>(
        mutationFn: (text, _) async => text,
      ),
    );

    final unsubscribe = observer.subscribe((_) {});

    final events = <MutationCacheEvent>[];
    final unsubscribeCache = queryClient.mutationCache.subscribe(events.add);

    observer.setOptions(
      MutationOptions<String, String, Object?>(
        mutationFn: observer.options.mutationFn,
      ),
    );

    expect(events.whereType<MutationObserverOptionsUpdated>(), isEmpty);

    unsubscribeCache();
    unsubscribe();
  });
}
