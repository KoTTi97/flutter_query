/// Port of `query-core/src/__tests__/mutation.test.tsx` at upstream
/// `50680b98c`. Omissions and adaptations: `test/PORTING_NOTES.md`.
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('mutation', () {
    late QueryClient queryClient;

    setUp(() {
      queryClient = testClient();
      queryClient.mount();
    });

    tearDown(() => queryClient.clear());

    testFakeAsync('mutate should accept null values', (time) async {
      Object? variables = 'unset';

      final mutation = MutationObserver<Object?, Object?, void>(
        queryClient,
        MutationOptions<Object?, Object?, void>(
          mutationFn: (vars) {
            variables = vars;
            return Future<Object?>.value(vars);
          },
        ),
      );

      mutation.mutate(null);
      await time.flushMicrotasks();

      expect(variables, isNull);
    });

    testFakeAsync('setMutationDefaults should be able to set defaults',
        (time) async {
      final key = queryKey();
      final seen = <Object?>[];

      queryClient.setMutationDefaults(
        key,
        MutationDefaults(mutationFn: (vars) {
          seen.add(vars);
          return Future<Object?>.value(null);
        }),
      );

      executeMutation<Object?, String, void>(
        queryClient,
        MutationOptions<Object?, String, void>(mutationKey: key),
        'vars',
      ).ignore();

      await time.flushMicrotasks();
      expect(seen, <Object?>['vars']);
    });

    testFakeAsync('mutation should set correct success states', (time) async {
      final mutation = MutationObserver<String, String, String>(
        queryClient,
        MutationOptions<String, String, String>(
          mutationFn: (text) async {
            await sleep(ms(10));
            return text;
          },
          onMutate: (text) => text,
        ),
      );

      final idle = mutation.currentResult;
      expect(idle.status, MutationStatus.idle);
      expect(idle.isIdle, isTrue);
      expect(idle.dataOrNull, isNull);
      expect(idle.errorOrNull, isNull);
      expect(idle.failureCount, 0);
      expect(idle.failureReason, isNull);
      expect(idle.isPaused, isFalse);
      expect(idle.hasVariables, isFalse);
      expect(idle.submittedAt, isNull);

      final states = <MutationResult<String, String>>[];

      mutation.subscribe(states.add);

      mutation.mutate('todo');

      await time.flushMicrotasks();

      expect(states[0].status, MutationStatus.pending);
      expect(states[0].isPending, isTrue);
      expect(states[0].dataOrNull, isNull);
      expect(states[0].variables, 'todo');
      expect(states[0].submittedAt, isNotNull);

      await time.advance(ms(10));

      final last = states.last;
      expect(last.status, MutationStatus.success);
      expect(last.dataOrNull, 'todo');
      expect(last.errorOrNull, isNull);
      expect(last.failureCount, 0);
      expect(last.variables, 'todo');
    });

    testFakeAsync('mutation should set correct error states', (time) async {
      final error = Exception('err');
      final mutation = MutationObserver<String, String, String>(
        queryClient,
        MutationOptions<String, String, String>(
          mutationFn: (_) async {
            await sleep(ms(20));
            throw error;
          },
          onMutate: (text) => text,
          retry: const RetryTimes(1),
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 10)),
        ),
      );

      final states = <MutationResult<String, String>>[];

      mutation.subscribe(states.add);

      mutation.mutate('todo');

      await time.flushMicrotasks();

      expect(states[0].status, MutationStatus.pending);
      expect(states[0].variables, 'todo');
      expect(states[0].failureCount, 0);

      await time.advance(ms(20));

      final retrying = states.last;
      expect(retrying.status, MutationStatus.pending);
      expect(retrying.failureCount, 1);
      expect(retrying.failureReason, same(error));

      await time.advance(ms(30));

      final failed = states.last;
      expect(failed.status, MutationStatus.error);
      expect(failed.errorOrNull, same(error));
      expect(failed.failureCount, 2);
      expect(failed.failureReason, same(error));
      expect(failed.variables, 'todo');
    });

    testFakeAsync('should be able to restore a mutation', (time) async {
      final key = queryKey();

      var onMutateCalls = 0;
      var onSuccessCalls = 0;
      var onSettledCalls = 0;

      final options = MutationOptions<String, String, String>(
        mutationKey: key,
        mutationFn: (text) async {
          await sleep(ms(10));
          return text;
        },
        onMutate: (variables) {
          onMutateCalls++;
          return variables;
        },
        onSuccess: (_, __, ___) => onSuccessCalls++,
        onSettled: (_, __, ___, ____, _____) => onSettledCalls++,
      );

      final mutation = queryClient.mutationCache.build<String, String, String>(
        queryClient,
        queryClient.defaultMutationOptions<String, String, String>(options),
        state: MutationState<String, String, String>(
          onMutateResult: 'todo',
          failureCount: 1,
          failureReason: 'err',
          isPaused: true,
          status: MutationStatus.pending,
          variables: 'todo',
          hasVariables: true,
          submittedAt: DateTime.fromMillisecondsSinceEpoch(1),
        ),
      );

      expect(mutation.state.isPaused, isTrue);
      expect(mutation.state.status, MutationStatus.pending);
      expect(mutation.state.variables, 'todo');

      queryClient.resumePausedMutations().ignore();

      // check that the mutation is correctly resumed
      expect(mutation.state.isPaused, isFalse);
      expect(mutation.state.status, MutationStatus.pending);

      await time.advance(ms(10));

      expect(mutation.state.data, 'todo');
      expect(mutation.state.status, MutationStatus.success);
      expect(mutation.state.failureCount, 0);
      expect(mutation.state.failureReason, isNull);
      expect(
          mutation.state.submittedAt, DateTime.fromMillisecondsSinceEpoch(1));

      expect(onMutateCalls, 0);
      expect(onSuccessCalls, 1);
      expect(onSettledCalls, 1);
    });

    testFakeAsync('addObserver should not add an existing observer',
        (time) async {
      final mutationCache = queryClient.mutationCache;
      final observer = MutationObserver<void, void, void>(
        queryClient,
        const MutationOptions<void, void, void>(),
      );
      final currentMutation = mutationCache.build<void, void, void>(
        queryClient,
        queryClient.defaultMutationOptions<void, void, void>(
          const MutationOptions<void, void, void>(),
        ),
      );

      final events = <MutationCacheEvent>[];

      final unsubscribe = mutationCache.subscribe(events.add);

      currentMutation.addObserver(observer);
      currentMutation.addObserver(observer);

      expect(events, hasLength(1));
      expect(events.single, isA<MutationObserverAdded>());

      unsubscribe();
    });

    testFakeAsync('mutate should throw an error if no mutationFn found',
        (time) async {
      final mutation = MutationObserver<String, void, void>(
        queryClient,
        const MutationOptions<String, void, void>(retry: RetryPolicy.never),
      );

      await expectLater(
        mutation.mutateAsync(null),
        throwsA(isA<MissingMutationFunctionError>()),
      );
    });

    testFakeAsync(
        'mutate update the mutation state even without an active subscription 1',
        (time) async {
      var onSuccessCalls = 0;
      var onSettledCalls = 0;

      final mutation = MutationObserver<String, void, void>(
        queryClient,
        MutationOptions<String, void, void>(
          mutationFn: (_) => Future<String>.value('update'),
        ),
      );

      mutation.mutate(
        null,
        callbacks: MutateCallbacks<String, void, void>(
          onSuccess: (_, __, ___) => onSuccessCalls++,
          onSettled: (_, __, ___, ____, _____) => onSettledCalls++,
        ),
      );

      await time.flushMicrotasks();
      expect(mutation.currentResult.dataOrNull, 'update');
      expect(onSuccessCalls, 0);
      expect(onSettledCalls, 0);
    });

    testFakeAsync(
        'mutate update the mutation state even without an active subscription 2',
        (time) async {
      var onSuccessCalls = 0;
      var onSettledCalls = 0;

      final mutation = MutationObserver<String, void, void>(
        queryClient,
        MutationOptions<String, void, void>(
          mutationFn: (_) => Future<String>.value('update'),
        ),
      );

      mutation.mutate(
        null,
        callbacks: MutateCallbacks<String, void, void>(
          onSuccess: (_, __, ___) => onSuccessCalls++,
          onSettled: (_, __, ___, ____, _____) => onSettledCalls++,
        ),
      );

      await time.flushMicrotasks();
      expect(mutation.currentResult.dataOrNull, 'update');
      expect(onSuccessCalls, 0);
      expect(onSettledCalls, 0);
    });

    testFakeAsync('mutation callbacks should see updated options',
        (time) async {
      final seen = <int>[];

      final mutation = MutationObserver<String, void, void>(
        queryClient,
        MutationOptions<String, void, void>(
          mutationFn: (_) async {
            await sleep(ms(100));
            return 'update';
          },
          onSuccess: (_, __, ___) => seen.add(1),
        ),
      );

      mutation.mutate(null);

      mutation.setOptions(
        MutationOptions<String, void, void>(
          mutationFn: (_) async {
            await sleep(ms(100));
            return 'update';
          },
          onSuccess: (_, __, ___) => seen.add(2),
        ),
      );

      await time.advance(ms(100));
      expect(seen, <int>[2]);
    });

    group('scoped mutations', () {
      testFakeAsync('mutations in the same scope should run in serial',
          (time) async {
        final key1 = queryKey();
        final key2 = queryKey();

        final results = <String>[];

        executeMutation<String, String, void>(
          queryClient,
          MutationOptions<String, String, void>(
            mutationKey: key1,
            scope: const MutationScope('scope'),
            mutationFn: (_) async {
              results.add('start-A');
              await sleep(ms(10));
              results.add('finish-A');
              return 'a';
            },
          ),
          'vars1',
        ).ignore();

        var state = queryClient.mutationCache
            .find(filters: MutationFilters(mutationKey: key1))!
            .state;
        expect(state.status, MutationStatus.pending);
        expect(state.isPaused, isFalse);

        executeMutation<String, String, void>(
          queryClient,
          MutationOptions<String, String, void>(
            mutationKey: key2,
            scope: const MutationScope('scope'),
            mutationFn: (_) async {
              results.add('start-B');
              await sleep(ms(10));
              results.add('finish-B');
              return 'b';
            },
          ),
          'vars2',
        ).ignore();

        state = queryClient.mutationCache
            .find(filters: MutationFilters(mutationKey: key2))!
            .state;
        expect(state.status, MutationStatus.pending);
        expect(state.isPaused, isTrue);

        await time.advance(ms(20));

        expect(results, <String>['start-A', 'finish-A', 'start-B', 'finish-B']);
      });
    });

    testFakeAsync('mutations without scope should run in parallel',
        (time) async {
      final key1 = queryKey();
      final key2 = queryKey();

      final results = <String>[];

      executeMutation<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          mutationKey: key1,
          mutationFn: (_) async {
            results.add('start-A');
            await sleep(ms(10));
            results.add('finish-A');
            return 'a';
          },
        ),
        'vars1',
      ).ignore();

      executeMutation<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          mutationKey: key2,
          mutationFn: (_) async {
            results.add('start-B');
            await sleep(ms(10));
            results.add('finish-B');
            return 'b';
          },
        ),
        'vars2',
      ).ignore();

      await time.advance(ms(10));

      expect(results, <String>['start-A', 'start-B', 'finish-A', 'finish-B']);
    });

    testFakeAsync('each scope should run in parallel, serial within scope',
        (time) async {
      final results = <String>[];

      Future<String> step(String name, String value) async {
        results.add('start-$name');
        await sleep(ms(10));
        results.add('finish-$name');
        return value;
      }

      executeMutation<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          scope: const MutationScope('1'),
          mutationFn: (_) => step('A1', 'a'),
        ),
        'vars1',
      ).ignore();

      executeMutation<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          scope: const MutationScope('1'),
          mutationFn: (_) => step('B1', 'b'),
        ),
        'vars2',
      ).ignore();

      executeMutation<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          scope: const MutationScope('2'),
          mutationFn: (_) => step('A2', 'a'),
        ),
        'vars1',
      ).ignore();

      executeMutation<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          scope: const MutationScope('2'),
          mutationFn: (_) => step('B2', 'b'),
        ),
        'vars2',
      ).ignore();

      await time.advance(ms(20));

      expect(results, <String>[
        'start-A1',
        'start-A2',
        'finish-A1',
        'start-B1',
        'finish-A2',
        'start-B2',
        'finish-B1',
        'finish-B2',
      ]);
    });

    testFakeAsync(
        'should not remove mutation when one observer is removed but another '
        'still exists', (time) async {
      final observer1 = MutationObserver<String, void, void>(
        queryClient,
        MutationOptions<String, void, void>(
          gcTime: const GcTime.duration(Duration(milliseconds: 10)),
          mutationFn: (_) async {
            await sleep(ms(10));
            return 'data';
          },
        ),
      );
      final unsubscribe1 = observer1.subscribe((_) {});

      observer1.mutate(null);
      await time.advance(ms(10));

      expect(queryClient.mutationCache.mutations, hasLength(1));

      final mutation = queryClient.mutationCache.mutations.first;
      final observer2 = MutationObserver<String, void, void>(
        queryClient,
        MutationOptions<String, void, void>(
          gcTime: const GcTime.duration(Duration(milliseconds: 10)),
          mutationFn: (_) async {
            await sleep(ms(10));
            return 'data';
          },
        ),
      );
      mutation.addObserver(observer2);

      unsubscribe1();

      await time.advance(ms(10));

      expect(queryClient.mutationCache.mutations, hasLength(1));
    });

    testFakeAsync('should release the retryer once a mutation settles',
        (time) async {
      final observer = MutationObserver<String, String, void>(
        queryClient,
        MutationOptions<String, String, void>(
          mutationFn: (text) async {
            await sleep(ms(10));
            return text;
          },
        ),
      );

      observer.mutate('data');
      await time.advance(ms(10));

      final mutation = queryClient.mutationCache.mutations.first;
      expect(mutation.state.status, MutationStatus.success);

      // continueMutation is the only reader of the retryer outside execute():
      // a retained one would hand back its own settled future here.
      await mutation.continueMutation();
      expect(mutation.state.status, MutationStatus.success);
    });

    testFakeAsync(
        'should release the retryer of a mutation that settled with an error',
        (time) async {
      final observer = MutationObserver<String, void, void>(
        queryClient,
        MutationOptions<String, void, void>(
          mutationFn: (_) async {
            await sleep(ms(10));
            throw Exception('oops');
          },
        ),
      );

      observer.mutate(null);
      await time.advance(ms(10));

      final mutation = queryClient.mutationCache.mutations.first;
      expect(mutation.state.status, MutationStatus.error);

      // a retained retryer would hand back its rejected future here
      await mutation.continueMutation();
      expect(mutation.state.status, MutationStatus.error);
    });

    testFakeAsync(
        'should not re-execute a settled mutation when it is continued',
        (time) async {
      var calls = 0;
      final observer = MutationObserver<String, void, void>(
        queryClient,
        MutationOptions<String, void, void>(
          mutationFn: (_) async {
            calls++;
            await sleep(ms(10));
            return 'data';
          },
        ),
      );

      observer.mutate(null);
      await time.advance(ms(10));

      final mutation = queryClient.mutationCache.mutations.first;
      expect(mutation.state.status, MutationStatus.success);
      expect(calls, 1);

      await mutation.continueMutation();
      await time.advance(ms(10));

      expect(calls, 1);
      expect(mutation.state.status, MutationStatus.success);
    });

    testFakeAsync(
        'should still continue a restored paused mutation that has no retryer',
        (time) async {
      var calls = 0;
      // a mutation restored from a persisted pending state has no retryer yet
      final mutation = queryClient.mutationCache.build<String, void, void>(
        queryClient,
        queryClient.defaultMutationOptions<String, void, void>(
          MutationOptions<String, void, void>(
            mutationFn: (_) async {
              calls++;
              await sleep(ms(10));
              return 'data';
            },
          ),
        ),
        state: MutationState<String, void, void>(
          isPaused: true,
          status: MutationStatus.pending,
          hasVariables: true,
          submittedAt: time.now,
        ),
      );

      final continued = mutation.continueMutation();
      await time.advance(ms(10));
      await continued;

      expect(calls, 1);
      expect(mutation.state.status, MutationStatus.success);
    });

    group('callback return types', () {
      testFakeAsync('should handle all sync callback patterns', (time) async {
        final key = queryKey();
        final results = <String>[];

        executeMutation<String, String, Map<String, String>>(
          queryClient,
          MutationOptions<String, String, Map<String, String>>(
            mutationKey: key,
            mutationFn: (_) => Future<String>.value('success'),
            onMutate: (_) {
              results.add('onMutate-sync');
              return <String, String>{'backup': 'data'};
            },
            onSuccess: (_, __, ___) {
              results.add('onSuccess-implicit-void');
            },
            onError: (_, __, ___, ____) {
              results.add('onError-explicit-void');
            },
            onSettled: (_, __, ___, ____, _____) {
              results.add('onSettled-return-value');
            },
          ),
          'vars',
        ).ignore();

        await time.flushMicrotasks();

        expect(results, <String>[
          'onMutate-sync',
          'onSuccess-implicit-void',
          'onSettled-return-value',
        ]);
      });

      testFakeAsync('should handle all async callback patterns', (time) async {
        final key = queryKey();
        final results = <String>[];

        executeMutation<String, String, Map<String, String>>(
          queryClient,
          MutationOptions<String, String, Map<String, String>>(
            mutationKey: key,
            mutationFn: (_) => Future<String>.value('success'),
            onMutate: (_) async {
              results.add('onMutate-async');
              await sleep(ms(10));
              return <String, String>{'backup': 'async-data'};
            },
            onSuccess: (_, __, ___) async {
              results.add('onSuccess-async-start');
              await sleep(ms(20));
              results.add('onSuccess-async-end');
            },
            onSettled: (_, __, ___, ____, _____) {
              results.add('onSettled-promise');
              // upstream returns a `Promise<string>` here to show it is
              // ignored; a `FutureOr<void>` callback cannot.
            },
          ),
          'vars',
        ).ignore();

        await time.advance(ms(30));

        expect(results, <String>[
          'onMutate-async',
          'onSuccess-async-start',
          'onSuccess-async-end',
          'onSettled-promise',
        ]);
      });

      testFakeAsync('should handle Future.wait() patterns', (time) async {
        final key = queryKey();
        final results = <String>[];

        executeMutation<String, String, void>(
          queryClient,
          MutationOptions<String, String, void>(
            mutationKey: key,
            mutationFn: (_) => Future<String>.value('success'),
            onSuccess: (_, __, ___) async {
              results.add('onSuccess-start');
              await Future.wait<void>(<Future<void>>[
                sleep(ms(20)).then((_) {
                  results.add('invalidate-queries');
                }),
                sleep(ms(10)).then((_) {
                  results.add('track-analytics');
                }),
              ]);
            },
            onSettled: (_, __, ___, ____, _____) async {
              results.add('onSettled-start');
              await Future.wait<void>(<Future<void>>[
                sleep(ms(10)).then((_) {
                  results.add('cleanup-1');
                }),
                Future<void>.error('error').catchError((Object _) {
                  results.add('cleanup-2-failed');
                }),
              ]);
            },
          ),
          'vars',
        ).ignore();

        await time.advance(ms(30));

        expect(results, <String>[
          'onSuccess-start',
          'track-analytics',
          'invalidate-queries',
          'onSettled-start',
          'cleanup-2-failed',
          'cleanup-1',
        ]);
      });

      testFakeAsync(
          'should handle mixed sync/async patterns and return value isolation',
          (time) async {
        final key = queryKey();
        final results = <String>[];

        final mutationFuture =
            executeMutation<String, String, Map<String, String>>(
          queryClient,
          MutationOptions<String, String, Map<String, String>>(
            mutationKey: key,
            mutationFn: (_) => Future<String>.value('actual-result'),
            onMutate: (_) {
              results.add('sync-onMutate');
              return <String, String>{'rollback': 'data'};
            },
            onSuccess: (_, __, ___) async {
              results.add('async-onSuccess');
              await sleep(ms(10));
              // upstream returns a value here to show it is ignored; a
              // `FutureOr<void>` callback cannot, so the type system says it.
            },
            onError: (_, __, ___, ____) {
              results.add('sync-onError');
            },
            onSettled: (_, __, ___, ____, onMutateResult) {
              results.add('settled-onMutateResult-'
                  '${onMutateResult?['rollback']}');
            },
          ),
          'vars',
        );

        await time.advance(ms(10));

        // the mutation returns its own result, not a callback's
        expect(await mutationFuture, 'actual-result');
        expect(results, <String>[
          'sync-onMutate',
          'async-onSuccess',
          'settled-onMutateResult-data',
        ]);
      });

      testFakeAsync('should handle error cases with all callback patterns',
          (time) async {
        final key = queryKey();
        final results = <String>[];

        final mutationError = Exception('mutation-error');
        Object? caught;
        executeMutation<String, String, Map<String, String>>(
          queryClient,
          MutationOptions<String, String, Map<String, String>>(
            mutationKey: key,
            mutationFn: (_) => Future<String>.error(mutationError),
            onMutate: (_) {
              results.add('onMutate');
              return <String, String>{'backup': 'error-data'};
            },
            onSuccess: (_, __, ___) {
              results.add('onSuccess-should-not-run');
            },
            onError: (_, __, ___, ____) async {
              results.add('onError-async');
              await sleep(ms(10));
              await Future.wait<void>(<Future<void>>[
                sleep(ms(10)).then((_) {
                  results.add('error-cleanup-1');
                }),
                sleep(ms(20)).then((_) {
                  results.add('error-cleanup-2');
                }),
              ]);
            },
            onSettled: (_, __, ___, ____, onMutateResult) {
              results.add('settled-error-${onMutateResult?['backup']}');
            },
          ),
          'vars',
        ).then<void>(
          (_) {},
          onError: (Object error) {
            caught = error;
          },
        ).ignore();

        await time.advance(ms(30));

        expect(results, <String>[
          'onMutate',
          'onError-async',
          'error-cleanup-1',
          'error-cleanup-2',
          'settled-error-error-data',
        ]);

        expect(caught, same(mutationError));
      });
    });

    group('erroneous mutation callback', () {
      testFakeAsync('error by global onSuccess triggers onError callback',
          (time) async {
        final mutationError = Exception('mutation-error');

        final results = <String>[];
        final client = testClient(
          mutationCache: MutationCache(
            onSuccess: (_, __, ___, ____) => throw mutationError,
          ),
        )..mount();

        final key = queryKey();

        Object? caught;
        executeMutation<String, String, Map<String, String>>(
          client,
          MutationOptions<String, String, Map<String, String>>(
            mutationKey: key,
            mutationFn: (_) => Future<String>.value('success'),
            onMutate: (_) async {
              results.add('onMutate-async');
              await sleep(ms(10));
              return <String, String>{'backup': 'async-data'};
            },
            onSuccess: (_, __, ___) async {
              results.add('onSuccess-async-start');
              await sleep(ms(10));
              throw mutationError;
            },
            onError: (_, __, ___, ____) async {
              results.add('onError-async-start');
              await sleep(ms(10));
              results.add('onError-async-end');
            },
            onSettled: (_, __, ___, ____, _____) {
              results.add('onSettled-promise');
            },
          ),
          'vars',
        ).then<void>(
          (_) {},
          onError: (Object error) {
            caught = error;
          },
        ).ignore();

        await time.advance(ms(30));

        expect(results, <String>[
          'onMutate-async',
          'onError-async-start',
          'onError-async-end',
          'onSettled-promise',
        ]);

        expect(caught, same(mutationError));
      });

      testFakeAsync('error by mutations onSuccess triggers onError callback',
          (time) async {
        final key = queryKey();
        final results = <String>[];

        final mutationError = Exception('mutation-error');

        Object? caught;
        executeMutation<String, String, Map<String, String>>(
          queryClient,
          MutationOptions<String, String, Map<String, String>>(
            mutationKey: key,
            mutationFn: (_) => Future<String>.value('success'),
            onMutate: (_) async {
              results.add('onMutate-async');
              await sleep(ms(10));
              return <String, String>{'backup': 'async-data'};
            },
            onSuccess: (_, __, ___) async {
              results.add('onSuccess-async-start');
              await sleep(ms(10));
              throw mutationError;
            },
            onError: (_, __, ___, ____) async {
              results.add('onError-async-start');
              await sleep(ms(10));
              results.add('onError-async-end');
            },
            onSettled: (_, __, ___, ____, _____) {
              results.add('onSettled-promise');
            },
          ),
          'vars',
        ).then<void>(
          (_) {},
          onError: (Object error) {
            caught = error;
          },
        ).ignore();

        await time.advance(ms(30));

        expect(results, <String>[
          'onMutate-async',
          'onSuccess-async-start',
          'onError-async-start',
          'onError-async-end',
          'onSettled-promise',
        ]);

        expect(caught, same(mutationError));
      });

      testFakeAsyncGuarded(
          'error by global onSettled triggers onError callback, calling global '
          'onSettled callback twice', (time, uncaught) async {
        final mutationError = Exception('mutation-error');
        final results = <String>[];

        final client = testClient(
          mutationCache: MutationCache(
            onSettled: (_, __, ___, ____, _____, ______) async {
              results.add('global-onSettled');
              await sleep(ms(10));
              throw mutationError;
            },
          ),
        )..mount();

        final key = queryKey();

        Object? caught;
        executeMutation<String, String, Map<String, String>>(
          client,
          MutationOptions<String, String, Map<String, String>>(
            mutationKey: key,
            mutationFn: (_) => Future<String>.value('success'),
            onMutate: (_) async {
              results.add('onMutate-async');
              await sleep(ms(10));
              return <String, String>{'backup': 'async-data'};
            },
            onSuccess: (_, __, ___) async {
              results.add('onSuccess-async-start');
              await sleep(ms(10));
              results.add('onSuccess-async-end');
            },
            onError: (_, __, ___, ____) async {
              results.add('onError-async-start');
              await sleep(ms(10));
              results.add('onError-async-end');
            },
            onSettled: (_, __, ___, ____, _____) {
              results.add('local-onSettled');
            },
          ),
          'vars',
        ).then<void>(
          (_) {},
          onError: (Object error) {
            caught = error;
          },
        ).ignore();

        await time.advance(ms(60));

        expect(results, <String>[
          'onMutate-async',
          'onSuccess-async-start',
          'onSuccess-async-end',
          'global-onSettled',
          'onError-async-start',
          'onError-async-end',
          'global-onSettled',
          'local-onSettled',
        ]);

        // the second failure of the global onSettled has nobody to go to
        expect(uncaught, <Object>[mutationError]);
        expect(caught, same(mutationError));
      });

      testFakeAsyncGuarded(
          'error by mutations onSettled triggers onError callback, calling both '
          'onSettled callbacks twice', (time, uncaught) async {
        final key = queryKey();
        final results = <String>[];

        final mutationError = Exception('mutation-error');

        Object? caught;
        executeMutation<String, String, Map<String, String>>(
          queryClient,
          MutationOptions<String, String, Map<String, String>>(
            mutationKey: key,
            mutationFn: (_) => Future<String>.value('success'),
            onMutate: (_) async {
              results.add('onMutate-async');
              await sleep(ms(10));
              return <String, String>{'backup': 'async-data'};
            },
            onSuccess: (_, __, ___) async {
              results.add('onSuccess-async-start');
              await sleep(ms(10));
              results.add('onSuccess-async-end');
            },
            onError: (_, __, ___, ____) async {
              results.add('onError-async-start');
              await sleep(ms(10));
              results.add('onError-async-end');
            },
            onSettled: (_, __, ___, ____, _____) async {
              results.add('onSettled-async-promise');
              await sleep(ms(10));
              throw mutationError;
            },
          ),
          'vars',
        ).then<void>(
          (_) {},
          onError: (Object error) {
            caught = error;
          },
        ).ignore();

        await time.advance(ms(60));

        expect(results, <String>[
          'onMutate-async',
          'onSuccess-async-start',
          'onSuccess-async-end',
          'onSettled-async-promise',
          'onError-async-start',
          'onError-async-end',
          'onSettled-async-promise',
        ]);

        expect(uncaught, <Object>[mutationError]);
        expect(caught, same(mutationError));
      });

      testFakeAsyncGuarded(
          'errors by onError and consecutive onSettled callbacks are reported '
          'to the zone', (time, uncaught) async {
        final globalErrorError = Exception('global-error-error');
        final globalSettledError = Exception('global-settled-error');

        final client = testClient(
          mutationCache: MutationCache(
            onError: (_, __, ___, ____, _____) => throw globalErrorError,
            onSettled: (_, __, ___, ____, _____, ______) =>
                throw globalSettledError,
          ),
        )..mount();

        final key = queryKey();
        final results = <String>[];

        final mutationError = Exception('mutation-error');
        final errorError = Exception('error-error');
        final settledError = Exception('settled-error');

        Object? caught;
        executeMutation<String, String, Map<String, String>>(
          client,
          MutationOptions<String, String, Map<String, String>>(
            mutationKey: key,
            mutationFn: (_) => Future<String>.value('success'),
            onMutate: (_) async {
              results.add('onMutate-async');
              await sleep(ms(10));
              throw mutationError;
            },
            onSuccess: (_, __, ___) {
              results.add('onSuccess-async-start');
            },
            onError: (_, __, ___, ____) async {
              results.add('onError-async-start');
              await sleep(ms(10));
              throw errorError;
            },
            onSettled: (_, __, ___, ____, _____) async {
              results.add('onSettled-promise');
              await sleep(ms(10));
              throw settledError;
            },
          ),
          'vars',
        ).then<void>(
          (_) {},
          onError: (Object error) {
            caught = error;
          },
        ).ignore();

        await time.advance(ms(30));

        expect(results, <String>[
          'onMutate-async',
          'onError-async-start',
          'onSettled-promise',
        ]);

        expect(caught, same(mutationError));

        expect(uncaught, <Object>[
          globalErrorError,
          errorError,
          globalSettledError,
          settledError,
        ]);
      });
    });
  });
}
