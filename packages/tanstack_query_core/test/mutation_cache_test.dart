/// Port of `query-core/src/__tests__/mutationCache.test.tsx` at upstream
/// `50680b98c`. Omissions and adaptations: `test/PORTING_NOTES.md`.
library;

import 'package:tanstack_query_core/tanstack_query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('mutationCache', () {
    group('MutationCacheConfig error callbacks', () {
      testFakeAsync('should call onError and onSettled when a mutation errors',
          (time) async {
        final key = queryKey();
        final errors = <(Object, Object?, Object?)>[];
        final successes = <Object?>[];
        final settled = <(Object?, Object?, Object?, Object?)>[];
        final testCache = MutationCache(
          onError: (error, _, variables, onMutateResult, __) =>
              errors.add((error, variables, onMutateResult)),
          onSuccess: (data, _, __, ___) => successes.add(data),
          onSettled: (data, error, _, variables, onMutateResult, __) =>
              settled.add((data, error, variables, onMutateResult)),
        );
        final client = testClient(mutationCache: testCache);

        final error = Exception('error');
        executeMutation<Object?, String, String>(
          client,
          MutationOptions<Object?, String, String>(
            mutationKey: key,
            mutationFn: (_) async {
              await sleep(ms(10));
              throw error;
            },
            onMutate: (_) => 'result',
          ),
          'vars',
        ).ignore();
        await time.advance(ms(10));

        expect(errors, [(error, 'vars', 'result')]);
        expect(successes, isEmpty);
        expect(settled, [(null, error, 'vars', 'result')]);
      });

      testFakeAsync('should be awaited', (time) async {
        final key = queryKey();
        final states = <int>[];
        final testCache = MutationCache(
          onError: (_, __, ___, ____, _____) async {
            await sleep(ms(10));
            states
              ..add(1)
              ..add(2);
          },
          onSettled: (_, __, ___, ____, _____, ______) async {
            await sleep(ms(10));
            states
              ..add(5)
              ..add(6);
          },
        );
        final client = testClient(mutationCache: testCache);

        executeMutation<Object?, String, void>(
          client,
          MutationOptions<Object?, String, void>(
            mutationKey: key,
            mutationFn: (_) async {
              await sleep(ms(10));
              throw Exception('error');
            },
            onError: (_, __, ___, ____) async {
              await sleep(ms(10));
              states
                ..add(3)
                ..add(4);
            },
            onSettled: (_, __, ___, ____, _____) async {
              await sleep(ms(10));
              states
                ..add(7)
                ..add(8);
            },
          ),
          'vars',
        ).ignore();
        await time.advance(ms(50));

        expect(states, <int>[1, 2, 3, 4, 5, 6, 7, 8]);
      });
    });

    group('MutationCacheConfig success callbacks', () {
      testFakeAsync(
          'should call onSuccess and onSettled when a mutation is successful',
          (time) async {
        final key = queryKey();
        final errors = <Object>[];
        final successes = <(Object?, Object?, Object?)>[];
        final settled = <(Object?, Object?, Object?, Object?)>[];
        final testCache = MutationCache(
          onError: (error, _, __, ___, ____) => errors.add(error),
          onSuccess: (data, variables, onMutateResult, _) =>
              successes.add((data, variables, onMutateResult)),
          onSettled: (data, error, _, variables, onMutateResult, __) =>
              settled.add((data, error, variables, onMutateResult)),
        );
        final client = testClient(mutationCache: testCache);

        executeMutation<Map<String, int>, String, String>(
          client,
          MutationOptions<Map<String, int>, String, String>(
            mutationKey: key,
            mutationFn: (_) async {
              await sleep(ms(10));
              return <String, int>{'data': 5};
            },
            onMutate: (_) => 'result',
          ),
          'vars',
        ).ignore();
        await time.advance(ms(10));

        expect(successes, hasLength(1));
        expect(successes.single.$1, equals(<String, int>{'data': 5}));
        expect(successes.single.$2, 'vars');
        expect(successes.single.$3, 'result');
        expect(errors, isEmpty);
        expect(settled, hasLength(1));
        expect(settled.single.$1, equals(<String, int>{'data': 5}));
        expect(settled.single.$2, isNull);
        expect(settled.single.$3, 'vars');
        expect(settled.single.$4, 'result');
      });

      testFakeAsync('should be awaited', (time) async {
        final key = queryKey();
        final states = <int>[];
        final testCache = MutationCache(
          onSuccess: (_, __, ___, ____) async {
            await sleep(ms(10));
            states
              ..add(1)
              ..add(2);
          },
          onSettled: (_, __, ___, ____, _____, ______) async {
            await sleep(ms(10));
            states
              ..add(5)
              ..add(6);
          },
        );
        final client = testClient(mutationCache: testCache);

        executeMutation<Map<String, int>, String, void>(
          client,
          MutationOptions<Map<String, int>, String, void>(
            mutationKey: key,
            mutationFn: (_) async {
              await sleep(ms(10));
              return <String, int>{'data': 5};
            },
            onSuccess: (_, __, ___) async {
              await sleep(ms(10));
              states
                ..add(3)
                ..add(4);
            },
            onSettled: (_, __, ___, ____, _____) async {
              await sleep(ms(10));
              states
                ..add(7)
                ..add(8);
            },
          ),
          'vars',
        ).ignore();
        await time.advance(ms(50));

        expect(states, <int>[1, 2, 3, 4, 5, 6, 7, 8]);
      });
    });

    group('MutationCacheConfig.onMutate', () {
      testFakeAsync('should be called before a mutation executes',
          (time) async {
        final key = queryKey();
        final seen = <(Object?, Mutation<Object?, Object?, Object?>)>[];
        final testCache = MutationCache(
          onMutate: (variables, mutation) => seen.add((variables, mutation)),
        );
        final client = testClient(mutationCache: testCache);

        executeMutation<Map<String, int>, String, String>(
          client,
          MutationOptions<Map<String, int>, String, String>(
            mutationKey: key,
            mutationFn: (_) async {
              await sleep(ms(10));
              return <String, int>{'data': 5};
            },
            onMutate: (_) => 'result',
          ),
          'vars',
        ).ignore();

        final mutation = testCache.mutations.first;

        expect(seen, hasLength(1));
        expect(seen.single.$1, 'vars');
        expect(seen.single.$2, same(mutation));
      });

      testFakeAsync('should be awaited', (time) async {
        final key = queryKey();
        final states = <int>[];
        final testCache = MutationCache(
          onMutate: (_, __) async {
            await sleep(ms(10));
            states
              ..add(1)
              ..add(2);
          },
        );
        final client = testClient(mutationCache: testCache);

        executeMutation<Map<String, int>, String, void>(
          client,
          MutationOptions<Map<String, int>, String, void>(
            mutationKey: key,
            mutationFn: (_) async {
              await sleep(ms(10));
              return <String, int>{'data': 5};
            },
            onMutate: (_) async {
              await sleep(ms(10));
              states
                ..add(3)
                ..add(4);
            },
          ),
          'vars',
        ).ignore();
        await time.advance(ms(20));

        expect(states, <int>[1, 2, 3, 4]);
      });

      testFakeAsync(
          'options.onMutate should run synchronously when '
          'mutationCache.config.onMutate is not defined', (time) async {
        final key = queryKey();
        final states = <String>[];

        // No onMutate in the cache config
        final testCache = MutationCache();
        final client = testClient(mutationCache: testCache);

        executeMutation<Map<String, int>, String, String>(
          client,
          MutationOptions<Map<String, int>, String, String>(
            mutationKey: key,
            mutationFn: (_) async {
              await sleep(ms(10));
              return <String, int>{'data': 5};
            },
            onMutate: (_) {
              states.add('onMutate');
              return 'context';
            },
          ),
          'vars',
        ).ignore();

        expect(states, <String>['onMutate']);
      });
    });

    group('find', () {
      testFakeAsync('should filter correctly', (time) async {
        final testCache = MutationCache();
        final client = testClient(mutationCache: testCache);
        final key = QueryKey(<Object?>['mutation', 'vars']);

        executeMutation<void, String, void>(
          client,
          MutationOptions<void, String, void>(
            mutationKey: key,
            mutationFn: (_) => sleep(ms(10)),
          ),
          'vars',
        ).ignore();

        final mutation = testCache.mutations.first;

        expect(testCache.find(filters: MutationFilters(mutationKey: key)),
            same(mutation));
        expect(
          testCache.find(
              filters: MutationFilters(
            mutationKey: QueryKey(<Object?>['mutation']),
            exact: false,
          )),
          same(mutation),
        );
        expect(
          testCache.find(
              filters: MutationFilters(
            mutationKey: QueryKey(<Object?>['unknown']),
          )),
          isNull,
        );
        expect(
          testCache.find(
              filters: MutationFilters(
            predicate: (m) => m.options.mutationKey?.parts.first == 'mutation',
          )),
          same(mutation),
        );
      });
    });

    group('findAll', () {
      testFakeAsync('should filter correctly', (time) async {
        final testCache = MutationCache();
        final client = testClient(mutationCache: testCache);

        for (final (key, variables) in <(QueryKey, int)>[
          (QueryKey(<Object?>['a', 1]), 1),
          (QueryKey(<Object?>['a', 2]), 2),
          (QueryKey(<Object?>['b']), 3),
        ]) {
          executeMutation<void, int, void>(
            client,
            MutationOptions<void, int, void>(
              mutationKey: key,
              mutationFn: (_) => sleep(ms(10)),
            ),
            variables,
          ).ignore();
        }

        final mutation1 = testCache.mutations[0];
        final mutation2 = testCache.mutations[1];

        expect(
          testCache.findAll(
              filters: MutationFilters(mutationKey: QueryKey(<Object?>['a']))),
          hasLength(2),
        );
        expect(
          testCache.find(
              filters:
                  MutationFilters(mutationKey: QueryKey(<Object?>['a', 1]))),
          same(mutation1),
        );
        expect(
          testCache.findAll(
              filters: MutationFilters(
            predicate: (m) => m.options.mutationKey?.parts.last == 2,
          )),
          [same(mutation2)],
        );
        expect(
          testCache.findAll(
              filters:
                  MutationFilters(mutationKey: QueryKey(<Object?>['unknown']))),
          isEmpty,
        );
      });
    });

    group('garbage collection', () {
      testFakeAsync('should remove unused mutations after gcTime has elapsed',
          (time) async {
        final testCache = MutationCache();
        final client = testClient(mutationCache: testCache);
        var successes = 0;

        executeMutation<void, int, void>(
          client,
          MutationOptions<void, int, void>(
            mutationKey: QueryKey(<Object?>['a', 1]),
            gcTime: const GcTime.duration(Duration(milliseconds: 10)),
            mutationFn: (_) => sleep(ms(10)),
            onSuccess: (_, __, ___) => successes++,
          ),
          1,
        ).ignore();
        await time.advance(ms(10));

        expect(testCache.mutations, hasLength(1));

        await time.advance(ms(10));
        expect(testCache.mutations, isEmpty);
        expect(successes, 1);
      });

      testFakeAsync('should not remove mutations if there are active observers',
          (time) async {
        final client = testClient();
        final observer = MutationObserver<int, int, void>(
          client,
          MutationOptions<int, int, void>(
            gcTime: const GcTime.duration(Duration(milliseconds: 10)),
            mutationFn: (input) async {
              await sleep(ms(10));
              return input;
            },
          ),
        );
        final unsubscribe = observer.subscribe((_) {});

        expect(client.mutationCache.mutations, isEmpty);

        observer.mutate(1);

        expect(client.mutationCache.mutations, hasLength(1));

        await time.advance(ms(10));
        expect(client.mutationCache.mutations, hasLength(1));

        unsubscribe();

        expect(client.mutationCache.mutations, hasLength(1));

        await time.advance(ms(10));
        expect(client.mutationCache.mutations, isEmpty);
      });

      testFakeAsync(
          'should be garbage collected later when unsubscribed and mutation is '
          'pending', (time) async {
        final client = testClient();
        var successes = 0;
        final observer = MutationObserver<String, int, void>(
          client,
          MutationOptions<String, int, void>(
            gcTime: const GcTime.duration(Duration(milliseconds: 10)),
            mutationFn: (_) async {
              await sleep(ms(10));
              return 'data';
            },
            onSuccess: (_, __, ___) => successes++,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});

        observer.mutate(1);

        unsubscribe();

        expect(client.mutationCache.mutations, hasLength(1));

        await time.advance(ms(10));
        // unsubscribing should not remove it even though gcTime has elapsed,
        // because the mutation is still pending
        expect(client.mutationCache.mutations, hasLength(1));

        await time.advance(ms(10));
        // removed after an additional gcTime wait
        expect(client.mutationCache.mutations, isEmpty);
        expect(successes, 1);
      });

      testFakeAsync(
          'should call callbacks even with gcTime 0 and mutation still pending',
          (time) async {
        final client = testClient();
        var successes = 0;
        final observer = MutationObserver<String, int, void>(
          client,
          MutationOptions<String, int, void>(
            gcTime: const GcTime.duration(Duration.zero),
            mutationFn: (_) async {
              await sleep(ms(10));
              return 'data';
            },
            onSuccess: (_, __, ___) => successes++,
          ),
        );
        final unsubscribe = observer.subscribe((_) {});

        observer.mutate(1);

        unsubscribe();

        await time.advance(ms(10));
        expect(client.mutationCache.mutations, isEmpty);
        expect(successes, 1);
      });
    });

    group('remove', () {
      testFakeAsync(
          'should remove only the target mutation from scope when multiple '
          'scoped mutations exist', (time) async {
        final testCache = MutationCache();
        final client = testClient(mutationCache: testCache);

        final mutation1 = testCache.build<String, void, void>(
          client,
          client.defaultMutationOptions<String, void, void>(
            MutationOptions<String, void, void>(
              scope: const MutationScope('scope1'),
              mutationFn: (_) => Future<String>.value('data1'),
            ),
          ),
        );
        testCache.build<String, void, void>(
          client,
          client.defaultMutationOptions<String, void, void>(
            MutationOptions<String, void, void>(
              scope: const MutationScope('scope1'),
              mutationFn: (_) => Future<String>.value('data2'),
            ),
          ),
        );

        expect(testCache.mutations, hasLength(2));

        testCache.remove(mutation1);

        expect(testCache.mutations, hasLength(1));
        expect(testCache.mutations.single, isNot(same(mutation1)));
      });

      testFakeAsync(
          'should delete scope when removing the only mutation in that scope',
          (time) async {
        final testCache = MutationCache();
        final client = testClient(mutationCache: testCache);

        final mutation = testCache.build<String, void, void>(
          client,
          client.defaultMutationOptions<String, void, void>(
            MutationOptions<String, void, void>(
              scope: const MutationScope('scope1'),
              mutationFn: (_) => Future<String>.value('data'),
            ),
          ),
        );

        expect(testCache.mutations, hasLength(1));

        testCache.remove(mutation);

        expect(testCache.mutations, isEmpty);
      });

      testFakeAsync(
          'should still notify removal when removing a mutation that does not '
          'exist in the cache', (time) async {
        final testCache = MutationCache();
        final client = testClient(mutationCache: testCache);

        final mutation = testCache.build<String, void, void>(
          client,
          client.defaultMutationOptions<String, void, void>(
            MutationOptions<String, void, void>(
              mutationFn: (_) => Future<String>.value('data'),
            ),
          ),
        );

        expect(testCache.mutations, hasLength(1));
        testCache.remove(mutation);
        expect(testCache.mutations, isEmpty);

        // Remove again — the mutation is already gone from the cache
        final events = <MutationCacheEvent>[];
        final unsubscribe = testCache.subscribe(events.add);
        testCache.remove(mutation);

        expect(testCache.mutations, isEmpty);
        expect(events, hasLength(1));
        expect(events.single, isA<MutationRemoved>());
        expect(events.single.mutation, same(mutation));

        unsubscribe();
      });
    });
  });
}
