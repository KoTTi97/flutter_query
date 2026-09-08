import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Port of `query/packages/query-core/src/__tests__/mutationCache.test.tsx`.
///
/// The upstream assertions on the mutation-function context also check a
/// `client` field; the port's context carries only the key and meta, because
/// the client is whatever the call site closed over.
void main() {
  group('MutationCacheConfig error callbacks', () {
    testFakeAsync('should call onError and onSettled when a mutation errors', (
      time,
    ) async {
      final key = queryKey();
      final error = StateError('error');

      final errorCalls = <List<Object?>>[];
      final successCalls = <List<Object?>>[];
      final settledCalls = <List<Object?>>[];

      final testCache = MutationCache(
        onError: (error, _, variables, onMutateResult, mutation, context) =>
            errorCalls.add([
              error,
              variables,
              onMutateResult,
              mutation,
              context,
            ]),
        onSuccess: (data, variables, onMutateResult, mutation, context) =>
            successCalls.add([
              data,
              variables,
              onMutateResult,
              mutation,
              context,
            ]),
        onSettled:
            (data, error, _, variables, onMutateResult, mutation, context) =>
                settledCalls.add([
                  data,
                  error,
                  variables,
                  onMutateResult,
                  mutation,
                  context,
                ]),
      );
      final testClient = QueryClient(mutationCache: testCache);

      executeMutation(
        testClient,
        MutationOptions<String, String, String>(
          mutationKey: key,
          mutationFn: (_, _) =>
              sleep(ms(10)).then((_) => Future<String>.error(error)),
          onMutate: (_, _) => 'result',
        ),
        'vars',
      ).ignore();
      await time.advance(ms(10));

      final mutation = testCache.mutations.first;

      expect(errorCalls, hasLength(1));
      expect(errorCalls.single[0], same(error));
      expect(errorCalls.single[1], 'vars');
      expect(errorCalls.single[2], 'result');
      expect(errorCalls.single[3], same(mutation));
      expect(
        (errorCalls.single[4]! as MutationFunctionContext).mutationKey,
        key,
      );

      expect(successCalls, isEmpty);

      expect(settledCalls, hasLength(1));
      expect(settledCalls.single[0], isNull);
      expect(settledCalls.single[1], same(error));
      expect(settledCalls.single[2], 'vars');
      expect(settledCalls.single[3], 'result');
      expect(settledCalls.single[4], same(mutation));
    });

    testFakeAsync('error callbacks should be awaited', (time) async {
      final key = queryKey();
      final states = <int>[];

      final testCache = MutationCache(
        onError: (_, _, _, _, _, _) =>
            sleep(ms(10)).then((_) => states.addAll([1, 2])),
        onSettled: (_, _, _, _, _, _, _) =>
            sleep(ms(10)).then((_) => states.addAll([5, 6])),
      );
      final testClient = QueryClient(mutationCache: testCache);

      executeMutation(
        testClient,
        MutationOptions<String, String, Object?>(
          mutationKey: key,
          mutationFn: (_, _) =>
              sleep(ms(10)).then((_) => Future<String>.error(StateError('e'))),
          onError: (_, _, _, _, _) =>
              sleep(ms(10)).then((_) => states.addAll([3, 4])),
          onSettled: (_, _, _, _, _, _) =>
              sleep(ms(10)).then((_) => states.addAll([7, 8])),
        ),
        'vars',
      ).ignore();
      await time.advance(ms(50));

      expect(states, [1, 2, 3, 4, 5, 6, 7, 8]);
    });
  });

  group('MutationCacheConfig success callbacks', () {
    testFakeAsync(
      'should call onSuccess and onSettled when a mutation is successful',
      (time) async {
        final key = queryKey();

        final errorCalls = <List<Object?>>[];
        final successCalls = <List<Object?>>[];
        final settledCalls = <List<Object?>>[];

        final testCache = MutationCache(
          onError: (error, _, variables, onMutateResult, mutation, context) =>
              errorCalls.add([error, variables, onMutateResult]),
          onSuccess: (data, variables, onMutateResult, mutation, context) =>
              successCalls.add([
                data,
                variables,
                onMutateResult,
                mutation,
                context,
              ]),
          onSettled:
              (data, error, _, variables, onMutateResult, mutation, context) =>
                  settledCalls.add([
                    data,
                    error,
                    variables,
                    onMutateResult,
                    mutation,
                  ]),
        );
        final testClient = QueryClient(mutationCache: testCache);

        executeMutation(
          testClient,
          MutationOptions<int, String, String>(
            mutationKey: key,
            mutationFn: (_, _) => sleep(ms(10)).then((_) => 5),
            onMutate: (_, _) => 'result',
          ),
          'vars',
        ).ignore();
        await time.advance(ms(10));

        final mutation = testCache.mutations.first;

        expect(successCalls, hasLength(1));
        expect(successCalls.single[0], 5);
        expect(successCalls.single[1], 'vars');
        expect(successCalls.single[2], 'result');
        expect(successCalls.single[3], same(mutation));
        expect(
          (successCalls.single[4]! as MutationFunctionContext).mutationKey,
          key,
        );

        expect(errorCalls, isEmpty);

        expect(settledCalls, hasLength(1));
        expect(settledCalls.single[0], 5);
        expect(settledCalls.single[1], isNull);
        expect(settledCalls.single[2], 'vars');
        expect(settledCalls.single[3], 'result');
        expect(settledCalls.single[4], same(mutation));
      },
    );

    testFakeAsync('success callbacks should be awaited', (time) async {
      final key = queryKey();
      final states = <int>[];

      final testCache = MutationCache(
        onSuccess: (_, _, _, _, _) =>
            sleep(ms(10)).then((_) => states.addAll([1, 2])),
        onSettled: (_, _, _, _, _, _, _) =>
            sleep(ms(10)).then((_) => states.addAll([5, 6])),
      );
      final testClient = QueryClient(mutationCache: testCache);

      executeMutation(
        testClient,
        MutationOptions<int, String, Object?>(
          mutationKey: key,
          mutationFn: (_, _) => sleep(ms(10)).then((_) => 5),
          onSuccess: (_, _, _, _) =>
              sleep(ms(10)).then((_) => states.addAll([3, 4])),
          onSettled: (_, _, _, _, _, _) =>
              sleep(ms(10)).then((_) => states.addAll([7, 8])),
        ),
        'vars',
      ).ignore();
      await time.advance(ms(50));

      expect(states, [1, 2, 3, 4, 5, 6, 7, 8]);
    });
  });

  group('MutationCache.onMutate', () {
    testFakeAsync('should be called before a mutation executes', (time) async {
      final key = queryKey();
      final calls = <List<Object?>>[];

      final testCache = MutationCache(
        onMutate: (variables, mutation, context) =>
            calls.add([variables, mutation, context]),
      );
      final testClient = QueryClient(mutationCache: testCache);

      executeMutation(
        testClient,
        MutationOptions<int, String, String>(
          mutationKey: key,
          mutationFn: (_, _) => sleep(ms(10)).then((_) => 5),
          onMutate: (_, _) => 'result',
        ),
        'vars',
      ).ignore();

      final mutation = testCache.mutations.first;

      expect(calls, hasLength(1));
      expect(calls.single[0], 'vars');
      expect(calls.single[1], same(mutation));
      expect((calls.single[2]! as MutationFunctionContext).mutationKey, key);

      await time.advance(ms(10));
    });

    testFakeAsync('onMutate should be awaited', (time) async {
      final key = queryKey();
      final states = <int>[];

      final testCache = MutationCache(
        onMutate: (_, _, _) => sleep(ms(10)).then((_) => states.addAll([1, 2])),
      );
      final testClient = QueryClient(mutationCache: testCache);

      executeMutation(
        testClient,
        MutationOptions<int, String, Object?>(
          mutationKey: key,
          mutationFn: (_, _) => sleep(ms(10)).then((_) => 5),
          onMutate: (_, _) => sleep(
            ms(10),
          ).then((_) => states.addAll([3, 4])).then((_) => null),
        ),
        'vars',
      ).ignore();
      await time.advance(ms(20));

      expect(states, [1, 2, 3, 4]);
    });

    testFakeAsync(
      'options.onMutate should run synchronously when the cache has no onMutate',
      (time) async {
        final key = queryKey();
        final states = <String>[];

        final testCache = MutationCache();
        final testClient = QueryClient(mutationCache: testCache);

        executeMutation(
          testClient,
          MutationOptions<int, String, String>(
            mutationKey: key,
            mutationFn: (_, _) => sleep(ms(10)).then((_) => 5),
            onMutate: (_, _) {
              states.add('onMutate');
              return 'context';
            },
          ),
          'vars',
        ).ignore();

        expect(states, ['onMutate']);

        await time.advance(ms(10));
      },
    );
  });

  group('find', () {
    testFakeAsync('should filter correctly', (time) async {
      final testCache = MutationCache();
      final testClient = QueryClient(mutationCache: testCache);
      const key = QueryKey(['mutation', 'vars']);

      executeMutation(
        testClient,
        MutationOptions<Object?, String, Object?>(
          mutationKey: key,
          mutationFn: (_, _) => sleep(ms(10)).then((_) => null),
        ),
        'vars',
      ).ignore();

      final mutation = testCache.mutations.first;

      expect(testCache.find(key), same(mutation));
      expect(
        testCache.find(
          const QueryKey(['mutation']),
          filters: const MutationFilters(),
        ),
        same(mutation),
      );
      expect(testCache.find(const QueryKey(['unknown'])), isNull);
      expect(
        testCache.findAll(
          MutationFilters(
            predicate: (m) => m.options.mutationKey?.parts.first == 'mutation',
          ),
        ),
        [mutation],
      );

      await time.advance(ms(10));
    });
  });

  group('findAll', () {
    testFakeAsync('should filter correctly', (time) async {
      final testCache = MutationCache();
      final testClient = QueryClient(mutationCache: testCache);

      void run(QueryKey key, int variables) {
        executeMutation(
          testClient,
          MutationOptions<Object?, int, Object?>(
            mutationKey: key,
            mutationFn: (_, _) => sleep(ms(10)).then((_) => null),
          ),
          variables,
        ).ignore();
      }

      run(const QueryKey(['a', 1]), 1);
      run(const QueryKey(['a', 2]), 2);
      run(const QueryKey(['b']), 3);

      final mutation1 = testCache.mutations[0];
      final mutation2 = testCache.mutations[1];

      expect(
        testCache.findAll(const MutationFilters(mutationKey: QueryKey(['a']))),
        hasLength(2),
      );
      expect(testCache.find(const QueryKey(['a', 1])), same(mutation1));
      expect(
        testCache.findAll(
          MutationFilters(
            predicate: (m) {
              final parts = m.options.mutationKey?.parts ?? const [];
              return parts.length > 1 && parts[1] == 2;
            },
          ),
        ),
        [mutation2],
      );
      expect(
        testCache.findAll(
          const MutationFilters(mutationKey: QueryKey(['unknown'])),
        ),
        isEmpty,
      );

      await time.advance(ms(10));
    });
  });

  group('garbage collection', () {
    testFakeAsync('should remove unused mutations after gcTime has elapsed', (
      time,
    ) async {
      final testCache = MutationCache();
      final testClient = QueryClient(mutationCache: testCache);
      var successCalls = 0;

      executeMutation(
        testClient,
        MutationOptions<Object?, int, Object?>(
          mutationKey: const QueryKey(['a', 1]),
          gcTime: const GcDuration.of(Duration(milliseconds: 10)),
          mutationFn: (_, _) => sleep(ms(10)).then((_) => null),
          onSuccess: (_, _, _, _) => successCalls++,
        ),
        1,
      ).ignore();
      await time.advance(ms(10));

      expect(testCache.mutations, hasLength(1));

      await time.advance(ms(10));
      expect(testCache.mutations, isEmpty);
      expect(successCalls, 1);
    });

    testFakeAsync('should not remove mutations if there are active observers', (
      time,
    ) async {
      final queryClient = QueryClient();
      final observer = MutationObserver<int, int, Object?>(
        queryClient,
        MutationOptions<int, int, Object?>(
          gcTime: const GcDuration.of(Duration(milliseconds: 10)),
          mutationFn: (input, _) => sleep(ms(10)).then((_) => input),
        ),
      );
      final unsubscribe = observer.subscribe((_) {});

      expect(queryClient.mutationCache.mutations, isEmpty);

      observer.mutate(1).ignore();

      expect(queryClient.mutationCache.mutations, hasLength(1));

      await time.advance(ms(10));
      expect(queryClient.mutationCache.mutations, hasLength(1));

      unsubscribe();

      expect(queryClient.mutationCache.mutations, hasLength(1));

      await time.advance(ms(10));
      expect(queryClient.mutationCache.mutations, isEmpty);
    });

    testFakeAsync(
      'should be garbage collected later when unsubscribed and the mutation is '
      'pending',
      (time) async {
        final queryClient = QueryClient();
        var successCalls = 0;

        final observer = MutationObserver<String, int, Object?>(
          queryClient,
          MutationOptions<String, int, Object?>(
            gcTime: const GcDuration.of(Duration(milliseconds: 10)),
            mutationFn: (_, _) => sleep(ms(10)).then((_) => 'data'),
            onSuccess: (_, _, _, _) => successCalls++,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});

        observer.mutate(1).ignore();
        unsubscribe();

        expect(queryClient.mutationCache.mutations, hasLength(1));

        await time.advance(ms(10));
        // Not removed even though the gc time elapsed: it is still pending.
        expect(queryClient.mutationCache.mutations, hasLength(1));

        await time.advance(ms(10));
        expect(queryClient.mutationCache.mutations, isEmpty);
        expect(successCalls, 1);
      },
    );

    testFakeAsync(
      'should call callbacks even with gcTime 0 and the mutation still pending',
      (time) async {
        final queryClient = QueryClient();
        var successCalls = 0;

        final observer = MutationObserver<String, int, Object?>(
          queryClient,
          MutationOptions<String, int, Object?>(
            gcTime: const GcDuration.of(Duration.zero),
            mutationFn: (_, _) => sleep(ms(10)).then((_) => 'data'),
            onSuccess: (_, _, _, _) => successCalls++,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});

        observer.mutate(1).ignore();
        unsubscribe();

        await time.advance(ms(10));
        expect(queryClient.mutationCache.mutations, isEmpty);
        expect(successCalls, 1);
      },
    );
  });

  group('remove', () {
    test(
      'should remove only the target mutation from a scope holding several',
      () {
        final testCache = MutationCache();
        final testClient = QueryClient(mutationCache: testCache);

        MutationOptions<String, Object?, Object?> scoped(String data) =>
            MutationOptions<String, Object?, Object?>(
              scope: 'scope1',
              mutationFn: (_, _) async => data,
            );

        final mutation1 = testCache.build<String, Object?, Object?>(
          testClient.defaultMutationOptions(scoped('data1')),
        );
        final mutation2 = testCache.build<String, Object?, Object?>(
          testClient.defaultMutationOptions(scoped('data2')),
        );

        expect(testCache.mutations, hasLength(2));

        testCache.remove(mutation1);

        expect(testCache.mutations, [same(mutation2)]);
      },
    );

    test('should delete the scope when removing its only mutation', () {
      final testCache = MutationCache();
      final testClient = QueryClient(mutationCache: testCache);

      final mutation = testCache.build<String, Object?, Object?>(
        testClient.defaultMutationOptions(
          MutationOptions<String, Object?, Object?>(
            scope: 'scope1',
            mutationFn: (_, _) async => 'data',
          ),
        ),
      );

      expect(testCache.mutations, hasLength(1));

      testCache.remove(mutation);

      expect(testCache.mutations, isEmpty);
    });

    test(
      'should still notify removal when removing a mutation that is not in the '
      'cache',
      () {
        final testCache = MutationCache();
        final testClient = QueryClient(mutationCache: testCache);

        final mutation = testCache.build<String, Object?, Object?>(
          testClient.defaultMutationOptions(
            MutationOptions<String, Object?, Object?>(
              mutationFn: (_, _) async => 'data',
            ),
          ),
        );

        expect(testCache.mutations, hasLength(1));
        testCache.remove(mutation);
        expect(testCache.mutations, isEmpty);

        // Remove again — it is already gone.
        final events = <MutationCacheEvent>[];
        final unsubscribe = testCache.subscribe(events.add);
        testCache.remove(mutation);

        expect(testCache.mutations, isEmpty);
        expect(events, hasLength(1));
        expect(events.single, isA<MutationRemoved>());
        expect(events.single.mutation, same(mutation));

        unsubscribe();
      },
    );
  });
}
