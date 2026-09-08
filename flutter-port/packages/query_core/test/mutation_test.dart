import 'dart:async';

import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Port of `query/packages/query-core/src/__tests__/mutation.test.tsx`.
void main() {
  late QueryClient queryClient;

  setUp(() {
    queryClient = QueryClient();
    queryClient.mount();
  });

  tearDown(() {
    queryClient.clear();
    queryClient.unmount();
    onlineManager.setOnline(true);
  });

  testFakeAsync('mutate should accept null values', (time) async {
    Object? seen = 'not called';

    final mutation = MutationObserver<Object?, Object?, Object?>(
      queryClient,
      MutationOptions<Object?, Object?, Object?>(
        mutationFn: (variables, _) async {
          seen = variables;
          return variables;
        },
      ),
    );

    unawaited(mutation.mutate(null));
    await time.advance(Duration.zero);

    expect(seen, isNull);
  });

  testFakeAsync('setMutationDefaults should be able to set defaults', (
    time,
  ) async {
    final key = queryKey();
    var calls = 0;
    Object? seenVariables;
    MutationFunctionContext? seenContext;

    queryClient.setMutationDefaults(
      key,
      MutationDefaults(
        mutationFn: (variables, context) async {
          calls++;
          seenVariables = variables;
          seenContext = context;
          return null;
        },
      ),
    );

    executeMutation(
      queryClient,
      MutationOptions<Object?, String, Object?>(mutationKey: key),
      'vars',
    ).ignore();

    await time.advance(Duration.zero);
    expect(calls, 1);
    expect(seenVariables, 'vars');
    expect(seenContext!.mutationKey, key);
    expect(seenContext!.meta, isNull);
  });

  testFakeAsync('mutation should set correct success states', (time) async {
    final mutation = MutationObserver<String, String, String>(
      queryClient,
      MutationOptions<String, String, String>(
        mutationFn: (text, _) => sleep(ms(10)).then((_) => text),
        onMutate: (text, _) => text,
      ),
    );

    expect(mutation.result, isA<MutationIdle<String, String, String>>());
    expect(mutation.result.dataOrNull, isNull);
    expect(mutation.result.errorOrNull, isNull);
    expect(mutation.result.failureCount, 0);
    expect(mutation.result.failureReason, isNull);
    expect(mutation.result.isPaused, isFalse);
    expect(mutation.result.variables, isNull);
    expect(mutation.result.onMutateResult, isNull);
    expect(mutation.result.submittedAt, isNull);

    final states = <MutationResult<String, String, String>>[];
    mutation.subscribe(states.add);

    unawaited(mutation.mutate('todo'));

    await time.advance(Duration.zero);

    expect(states[0], isA<MutationPending<String, String, String>>());
    expect(states[0].onMutateResult, isNull);
    expect(states[0].dataOrNull, isNull);
    expect(states[0].errorOrNull, isNull);
    expect(states[0].failureCount, 0);
    expect(states[0].isPaused, isFalse);
    expect(states[0].variables, 'todo');
    expect(states[0].submittedAt, isNotNull);

    await time.advance(Duration.zero);

    expect(states[1], isA<MutationPending<String, String, String>>());
    expect(states[1].onMutateResult, 'todo');
    expect(states[1].dataOrNull, isNull);
    expect(states[1].variables, 'todo');

    await time.advance(ms(10));

    expect(states[2], isA<MutationSuccess<String, String, String>>());
    expect(states[2].onMutateResult, 'todo');
    expect(states[2].dataOrNull, 'todo');
    expect(states[2].errorOrNull, isNull);
    expect(states[2].failureCount, 0);
    expect(states[2].isPaused, isFalse);
    expect(states[2].variables, 'todo');
  });

  testFakeAsync('mutation should set correct error states', (time) async {
    final error = StateError('err');

    final mutation = MutationObserver<String, String, String>(
      queryClient,
      MutationOptions<String, String, String>(
        mutationFn: (_, _) =>
            sleep(ms(20)).then((_) => Future<String>.error(error)),
        onMutate: (text, _) => text,
        retry: const RetryOption.count(1),
        retryDelay: const RetryDelay.of(Duration(milliseconds: 10)),
      ),
    );

    final states = <MutationResult<String, String, String>>[];
    mutation.subscribe(states.add);

    mutation.mutate('todo').ignore();

    await time.advance(Duration.zero);

    expect(states[0], isA<MutationPending<String, String, String>>());
    expect(states[0].onMutateResult, isNull);
    expect(states[0].failureCount, 0);
    expect(states[0].variables, 'todo');

    await time.advance(Duration.zero);

    expect(states[1], isA<MutationPending<String, String, String>>());
    expect(states[1].onMutateResult, 'todo');

    await time.advance(ms(20));

    expect(
      states[2],
      isA<MutationPending<String, String, String>>(),
      reason: 'still pending while it retries',
    );
    expect(states[2].failureCount, 1);
    expect(states[2].failureReason, same(error));

    await time.advance(ms(30));

    expect(states[3], isA<MutationError<String, String, String>>());
    expect(states[3].errorOrNull, same(error));
    expect(states[3].failureCount, 2);
    expect(states[3].failureReason, same(error));
    expect(states[3].isPaused, isFalse);
    expect(states[3].variables, 'todo');
    expect(states[3].onMutateResult, 'todo');
  });

  testFakeAsync('should be able to restore a mutation', (time) async {
    final key = queryKey();
    var onMutateCalls = 0;
    var onSuccessCalls = 0;
    var onSettledCalls = 0;

    queryClient.setMutationDefaults(
      key,
      MutationDefaults(
        mutationFn: (variables, _) =>
            sleep(ms(10)).then((_) => variables as String),
        onMutate: (_, _) {
          onMutateCalls++;
          return null;
        },
        onSuccess: (_, _, _, _) => onSuccessCalls++,
        onSettled: (_, _, _, _, _, _) => onSettledCalls++,
      ),
    );

    final submittedAt = DateTime.fromMillisecondsSinceEpoch(1, isUtc: true);
    final mutation = queryClient.mutationCache.build<String, String, String>(
      queryClient.defaultMutationOptions(
        MutationOptions<String, String, String>(mutationKey: key),
      ),
      state: MutationState<String, String, String>(
        onMutateResult: 'todo',
        failureCount: 1,
        failureReason: 'err',
        isPaused: true,
        status: MutationStatus.pending,
        variables: 'todo',
        submittedAt: submittedAt,
      ),
    );

    expect(mutation.state.isPaused, isTrue);
    expect(mutation.state.status, MutationStatus.pending);

    unawaited(queryClient.resumePausedMutations());

    // Resuming unpauses it synchronously.
    expect(mutation.state.isPaused, isFalse);
    expect(mutation.state.status, MutationStatus.pending);
    expect(mutation.state.failureCount, 1);

    await time.advance(ms(10));

    expect(mutation.state.data, 'todo');
    expect(mutation.state.status, MutationStatus.success);
    expect(mutation.state.failureCount, 0);
    expect(mutation.state.failureReason, isNull);
    expect(
      mutation.state.submittedAt,
      submittedAt,
      reason: 'a restored mutation keeps when it was originally submitted',
    );

    expect(onMutateCalls, 0, reason: 'onMutate already ran before the restore');
    expect(onSuccessCalls, 1);
    expect(onSettledCalls, 1);
  });

  test('addObserver should not add an existing observer', () {
    final mutationCache = queryClient.mutationCache;
    final observer = MutationObserver<Object?, Object?, Object?>(
      queryClient,
      const MutationOptions<Object?, Object?, Object?>(),
    );
    final mutation = mutationCache.build<Object?, Object?, Object?>(
      queryClient.defaultMutationOptions(
        const MutationOptions<Object?, Object?, Object?>(),
      ),
    );

    final events = <MutationCacheEvent>[];
    final unsubscribe = mutationCache.subscribe(events.add);

    mutation.addObserver(observer);
    mutation.addObserver(observer);

    expect(events, hasLength(1));
    expect(events.single, isA<MutationObserverAdded>());

    unsubscribe();
  });

  testFakeAsync('mutate should throw an error if no mutationFn found', (
    time,
  ) async {
    final mutation = MutationObserver<Object?, Object?, Object?>(
      queryClient,
      const MutationOptions<Object?, Object?, Object?>(
        retry: RetryOption.never,
      ),
    );

    await expectLater(
      mutation.mutate(null),
      throwsA(isA<MissingMutationFunctionError>()),
    );
  });

  testFakeAsync(
    'mutate updates the mutation state even without an active subscription',
    (time) async {
      var successCalls = 0;
      var settledCalls = 0;

      final mutation = MutationObserver<String, Object?, Object?>(
        queryClient,
        MutationOptions<String, Object?, Object?>(
          mutationFn: (_, _) async => 'update',
        ),
      );

      unawaited(
        mutation.mutate(
          null,
          callbacks: MutateCallbacks<String, Object?, Object?>(
            onSuccess: (_, _, _, _) => successCalls++,
            onSettled: (_, _, _, _, _, _) => settledCalls++,
          ),
        ),
      );

      await time.advance(Duration.zero);

      expect(mutation.result.dataOrNull, 'update');
      expect(
        successCalls,
        0,
        reason: 'per-call callbacks belong to a live use site',
      );
      expect(settledCalls, 0);
    },
  );

  testFakeAsync('mutation callbacks should see updated options', (time) async {
    final seen = <int>[];

    final mutation = MutationObserver<String, Object?, Object?>(
      queryClient,
      MutationOptions<String, Object?, Object?>(
        mutationFn: (_, _) => sleep(ms(100)).then((_) => 'update'),
        onSuccess: (_, _, _, _) => seen.add(1),
      ),
    );

    mutation.mutate(null).ignore();

    mutation.setOptions(
      MutationOptions<String, Object?, Object?>(
        mutationFn: (_, _) => sleep(ms(100)).then((_) => 'update'),
        onSuccess: (_, _, _, _) => seen.add(2),
      ),
    );

    await time.advance(ms(100));

    expect(seen, [2]);
  });

  group('scoped mutations', () {
    testFakeAsync('mutations in the same scope should run in serial', (
      time,
    ) async {
      final key1 = queryKey();
      final key2 = queryKey();
      final results = <String>[];

      executeMutation(
        queryClient,
        MutationOptions<String, String, Object?>(
          mutationKey: key1,
          scope: 'scope',
          mutationFn: (_, _) async {
            results.add('start-A');
            await sleep(ms(10));
            results.add('finish-A');
            return 'a';
          },
        ),
        'vars1',
      ).ignore();

      final first = queryClient.mutationCache.find(key1)!;
      expect(first.state.status, MutationStatus.pending);
      expect(first.state.isPaused, isFalse);

      executeMutation(
        queryClient,
        MutationOptions<String, String, Object?>(
          mutationKey: key2,
          scope: 'scope',
          mutationFn: (_, _) async {
            results.add('start-B');
            await sleep(ms(10));
            results.add('finish-B');
            return 'b';
          },
        ),
        'vars2',
      ).ignore();

      final second = queryClient.mutationCache.find(key2)!;
      expect(second.state.status, MutationStatus.pending);
      expect(second.state.isPaused, isTrue);

      await time.advance(ms(20));

      expect(results, ['start-A', 'finish-A', 'start-B', 'finish-B']);
    });
  });

  testFakeAsync('mutations without scope should run in parallel', (time) async {
    final key1 = queryKey();
    final key2 = queryKey();
    final results = <String>[];

    executeMutation(
      queryClient,
      MutationOptions<String, String, Object?>(
        mutationKey: key1,
        mutationFn: (_, _) async {
          results.add('start-A');
          await sleep(ms(10));
          results.add('finish-A');
          return 'a';
        },
      ),
      'vars1',
    ).ignore();

    executeMutation(
      queryClient,
      MutationOptions<String, String, Object?>(
        mutationKey: key2,
        mutationFn: (_, _) async {
          results.add('start-B');
          await sleep(ms(10));
          results.add('finish-B');
          return 'b';
        },
      ),
      'vars2',
    ).ignore();

    await time.advance(ms(10));

    expect(results, ['start-A', 'start-B', 'finish-A', 'finish-B']);
  });

  testFakeAsync('each scope should run in parallel, serial within scope', (
    time,
  ) async {
    final results = <String>[];

    Future<String> run(String scope, String label, String value) =>
        executeMutation(
          queryClient,
          MutationOptions<String, String, Object?>(
            scope: scope,
            mutationFn: (_, _) async {
              results.add('start-$label');
              await sleep(ms(10));
              results.add('finish-$label');
              return value;
            },
          ),
          'vars',
        );

    unawaited(run('1', 'A1', 'a'));
    unawaited(run('1', 'B1', 'b'));
    unawaited(run('2', 'A2', 'a'));
    unawaited(run('2', 'B2', 'b'));

    await time.advance(ms(20));

    expect(results, [
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

  group('callback return types', () {
    testFakeAsync('should handle all sync callback patterns', (time) async {
      final key = queryKey();
      final results = <String>[];

      executeMutation(
        queryClient,
        MutationOptions<String, String, Map<String, String>>(
          mutationKey: key,
          mutationFn: (_, _) async => 'success',
          onMutate: (_, _) {
            results.add('onMutate-sync');
            return {'backup': 'data'};
          },
          onSuccess: (_, _, _, _) => results.add('onSuccess-implicit-void'),
          onError: (_, _, _, _, _) => results.add('onError-explicit-void'),
          onSettled: (_, _, _, _, _, _) =>
              results.add('onSettled-return-value'),
        ),
        'vars',
      ).ignore();

      await time.advance(Duration.zero);

      expect(results, [
        'onMutate-sync',
        'onSuccess-implicit-void',
        'onSettled-return-value',
      ]);
    });

    testFakeAsync('should handle all async callback patterns', (time) async {
      final key = queryKey();
      final results = <String>[];

      executeMutation(
        queryClient,
        MutationOptions<String, String, Map<String, String>>(
          mutationKey: key,
          mutationFn: (_, _) async => 'success',
          onMutate: (_, _) async {
            results.add('onMutate-async');
            await sleep(ms(10));
            return {'backup': 'async-data'};
          },
          onSuccess: (_, _, _, _) async {
            results.add('onSuccess-async-start');
            await sleep(ms(20));
            results.add('onSuccess-async-end');
          },
          onSettled: (_, _, _, _, _, _) async {
            results.add('onSettled-promise');
            await Future<String>.value('also-ignored');
          },
        ),
        'vars',
      ).ignore();

      await time.advance(ms(30));

      expect(results, [
        'onMutate-async',
        'onSuccess-async-start',
        'onSuccess-async-end',
        'onSettled-promise',
      ]);
    });

    testFakeAsync('should handle concurrent work inside callbacks', (
      time,
    ) async {
      final key = queryKey();
      final results = <String>[];

      executeMutation(
        queryClient,
        MutationOptions<String, String, Object?>(
          mutationKey: key,
          mutationFn: (_, _) async => 'success',
          onSuccess: (_, _, _, _) async {
            results.add('onSuccess-start');
            await Future.wait([
              sleep(ms(20)).then((_) {
                results.add('invalidate-queries');
              }),
              sleep(ms(10)).then((_) {
                results.add('track-analytics');
              }),
            ]);
          },
          onSettled: (_, _, _, _, _, _) async {
            results.add('onSettled-start');
            await Future.wait([
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

      expect(results, [
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

        final mutationFuture = executeMutation(
          queryClient,
          MutationOptions<String, String, Map<String, String>>(
            mutationKey: key,
            mutationFn: (_, _) async => 'actual-result',
            onMutate: (_, _) {
              results.add('sync-onMutate');
              return {'rollback': 'data'};
            },
            onSuccess: (_, _, _, _) async {
              results.add('async-onSuccess');
              await sleep(ms(10));
            },
            onError: (_, _, _, _, _) => results.add('sync-onError'),
            onSettled: (_, _, _, _, onMutateResult, _) {
              results.add(
                'settled-onMutateResult-${onMutateResult?['rollback']}',
              );
              return;
            },
          ),
          'vars',
        );

        await time.advance(ms(10));

        expect(await mutationFuture, 'actual-result');
        expect(results, [
          'sync-onMutate',
          'async-onSuccess',
          'settled-onMutateResult-data',
        ]);
      },
    );

    testFakeAsync('should handle error cases with all callback patterns', (
      time,
    ) async {
      final key = queryKey();
      final results = <String>[];
      final mutationError = StateError('mutation-error');
      Object? seenError;

      executeMutation(
        queryClient,
        MutationOptions<String, String, Map<String, String>>(
          mutationKey: key,
          mutationFn: (_, _) => Future<String>.error(mutationError),
          onMutate: (_, _) {
            results.add('onMutate');
            return {'backup': 'error-data'};
          },
          onSuccess: (_, _, _, _) => results.add('onSuccess-should-not-run'),
          onError: (_, _, _, _, _) async {
            results.add('onError-async');
            await sleep(ms(10));
            await Future.wait([
              sleep(ms(10)).then((_) {
                results.add('error-cleanup-1');
              }),
              sleep(ms(20)).then((_) {
                results.add('error-cleanup-2');
              }),
            ]);
          },
          onSettled: (_, _, _, _, onMutateResult, _) {
            results.add('settled-error-${onMutateResult?['backup']}');
          },
        ),
        'vars',
      ).catchError((Object error) {
        seenError = error;
        return '';
      }).ignore();

      await time.advance(ms(30));

      expect(results, [
        'onMutate',
        'onError-async',
        'error-cleanup-1',
        'error-cleanup-2',
        'settled-error-error-data',
      ]);
      expect(seenError, same(mutationError));
    });
  });

  group('erroneous mutation callback', () {
    testFakeAsync('error by global onSuccess triggers onError callback', (
      time,
    ) async {
      final mutationError = StateError('mutation-error');
      final results = <String>[];

      final testClient = QueryClient(
        mutationCache: MutationCache(
          onSuccess: (_, _, _, _, _) => throw mutationError,
        ),
      )..mount();

      Object? seenError;
      executeMutation(
        testClient,
        MutationOptions<String, String, Map<String, String>>(
          mutationKey: queryKey(),
          mutationFn: (_, _) async => 'success',
          onMutate: (_, _) async {
            results.add('onMutate-async');
            await sleep(ms(10));
            return {'backup': 'async-data'};
          },
          onSuccess: (_, _, _, _) async {
            results.add('onSuccess-async-start');
            await sleep(ms(10));
            throw mutationError;
          },
          onError: (_, _, _, _, _) async {
            results.add('onError-async-start');
            await sleep(ms(10));
            results.add('onError-async-end');
          },
          onSettled: (_, _, _, _, _, _) {
            results.add('onSettled-promise');
          },
        ),
        'vars',
      ).catchError((Object error) {
        seenError = error;
        return '';
      }).ignore();

      await time.advance(ms(30));

      expect(results, [
        'onMutate-async',
        'onError-async-start',
        'onError-async-end',
        'onSettled-promise',
      ]);
      expect(seenError, same(mutationError));

      testClient.unmount();
    });

    testFakeAsync('error by the mutation onSuccess triggers onError callback', (
      time,
    ) async {
      final results = <String>[];
      final mutationError = StateError('mutation-error');
      Object? seenError;

      executeMutation(
        queryClient,
        MutationOptions<String, String, Map<String, String>>(
          mutationKey: queryKey(),
          mutationFn: (_, _) async => 'success',
          onMutate: (_, _) async {
            results.add('onMutate-async');
            await sleep(ms(10));
            return {'backup': 'async-data'};
          },
          onSuccess: (_, _, _, _) async {
            results.add('onSuccess-async-start');
            await sleep(ms(10));
            throw mutationError;
          },
          onError: (_, _, _, _, _) async {
            results.add('onError-async-start');
            await sleep(ms(10));
            results.add('onError-async-end');
          },
          onSettled: (_, _, _, _, _, _) {
            results.add('onSettled-promise');
          },
        ),
        'vars',
      ).catchError((Object error) {
        seenError = error;
        return '';
      }).ignore();

      await time.advance(ms(30));

      expect(results, [
        'onMutate-async',
        'onSuccess-async-start',
        'onError-async-start',
        'onError-async-end',
        'onSettled-promise',
      ]);
      expect(seenError, same(mutationError));
    });

    testFakeAsyncGuarded(
      'error by global onSettled triggers onError, calling global onSettled '
      'twice',
      (time, uncaught) async {
        final results = <String>[];
        final mutationError = StateError('mutation-error');

        final testClient = QueryClient(
          mutationCache: MutationCache(
            onSettled: (_, _, _, _, _, _, _) async {
              results.add('global-onSettled');
              await sleep(ms(10));
              throw mutationError;
            },
          ),
        )..mount();

        Object? seenError;
        executeMutation(
          testClient,
          MutationOptions<String, String, Map<String, String>>(
            mutationKey: queryKey(),
            mutationFn: (_, _) async => 'success',
            onMutate: (_, _) async {
              results.add('onMutate-async');
              await sleep(ms(10));
              return {'backup': 'async-data'};
            },
            onSuccess: (_, _, _, _) async {
              results.add('onSuccess-async-start');
              await sleep(ms(10));
              results.add('onSuccess-async-end');
            },
            onError: (_, _, _, _, _) async {
              results.add('onError-async-start');
              await sleep(ms(10));
              results.add('onError-async-end');
            },
            onSettled: (_, _, _, _, _, _) {
              results.add('local-onSettled');
              return null;
            },
          ),
          'vars',
        ).catchError((Object error) {
          seenError = error;
          return '';
        }).ignore();

        await time.advance(ms(50));

        expect(results, [
          'onMutate-async',
          'onSuccess-async-start',
          'onSuccess-async-end',
          'global-onSettled',
          'onError-async-start',
          'onError-async-end',
          'global-onSettled',
          'local-onSettled',
        ]);

        expect(uncaught, [same(mutationError)]);
        expect(seenError, same(mutationError));

        testClient.unmount();
      },
    );

    testFakeAsyncGuarded(
      'error by the mutation onSettled triggers onError, calling both onSettled '
      'callbacks twice',
      (time, uncaught) async {
        final results = <String>[];
        final mutationError = StateError('mutation-error');
        Object? seenError;

        executeMutation(
          queryClient,
          MutationOptions<String, String, Map<String, String>>(
            mutationKey: queryKey(),
            mutationFn: (_, _) async => 'success',
            onMutate: (_, _) async {
              results.add('onMutate-async');
              await sleep(ms(10));
              return {'backup': 'async-data'};
            },
            onSuccess: (_, _, _, _) async {
              results.add('onSuccess-async-start');
              await sleep(ms(10));
              results.add('onSuccess-async-end');
            },
            onError: (_, _, _, _, _) async {
              results.add('onError-async-start');
              await sleep(ms(10));
              results.add('onError-async-end');
            },
            onSettled: (_, _, _, _, _, _) async {
              results.add('onSettled-async-promise');
              await sleep(ms(10));
              throw mutationError;
            },
          ),
          'vars',
        ).catchError((Object error) {
          seenError = error;
          return '';
        }).ignore();

        await time.advance(ms(50));

        expect(results, [
          'onMutate-async',
          'onSuccess-async-start',
          'onSuccess-async-end',
          'onSettled-async-promise',
          'onError-async-start',
          'onError-async-end',
          'onSettled-async-promise',
        ]);

        expect(uncaught, [same(mutationError)]);
        expect(seenError, same(mutationError));
      },
    );

    testFakeAsyncGuarded(
      'errors thrown by onError and the onSettled after it are reported to the '
      'zone rather than replacing the failure the caller sees',
      (time, uncaught) async {
        final globalErrorError = StateError('global-error-error');
        final globalSettledError = StateError('global-settled-error');
        final mutationError = StateError('mutation-error');
        final errorError = StateError('error-error');
        final settledError = StateError('settled-error');

        final results = <String>[];

        final testClient = QueryClient(
          mutationCache: MutationCache(
            onError: (_, _, _, _, _, _) => throw globalErrorError,
            onSettled: (_, _, _, _, _, _, _) => throw globalSettledError,
          ),
        )..mount();

        Object? seenError;
        executeMutation(
          testClient,
          MutationOptions<String, String, Map<String, String>>(
            mutationKey: queryKey(),
            mutationFn: (_, _) async => 'success',
            onMutate: (_, _) async {
              results.add('onMutate-async');
              await sleep(ms(10));
              throw mutationError;
            },
            onSuccess: (_, _, _, _) => results.add('onSuccess-should-not-run'),
            onError: (_, _, _, _, _) async {
              results.add('onError-async-start');
              await sleep(ms(10));
              throw errorError;
            },
            onSettled: (_, _, _, _, _, _) async {
              results.add('onSettled-promise');
              await sleep(ms(10));
              throw settledError;
            },
          ),
          'vars',
        ).catchError((Object error) {
          seenError = error;
          return '';
        }).ignore();

        await time.advance(ms(30));

        expect(results, [
          'onMutate-async',
          'onError-async-start',
          'onSettled-promise',
        ]);

        expect(seenError, same(mutationError));
        expect(uncaught, [
          same(globalErrorError),
          same(errorError),
          same(globalSettledError),
          same(settledError),
        ]);

        testClient.unmount();
      },
    );
  });

  testFakeAsync(
    'should not remove mutation when one observer is removed but another still '
    'exists',
    (time) async {
      final observer1 = MutationObserver<String, Object?, Object?>(
        queryClient,
        MutationOptions<String, Object?, Object?>(
          gcTime: const GcDuration.of(Duration(milliseconds: 10)),
          mutationFn: (_, _) => sleep(ms(10)).then((_) => 'data'),
        ),
      );
      final unsubscribe1 = observer1.subscribe((_) {});

      unawaited(observer1.mutate(null));
      await time.advance(ms(10));

      expect(queryClient.mutationCache.mutations, hasLength(1));

      final mutation = queryClient.mutationCache.mutations.first;
      final observer2 = MutationObserver<String, Object?, Object?>(
        queryClient,
        MutationOptions<String, Object?, Object?>(
          gcTime: const GcDuration.of(Duration(milliseconds: 10)),
          mutationFn: (_, _) => sleep(ms(10)).then((_) => 'data'),
        ),
      );
      mutation.addObserver(observer2);

      unsubscribe1();

      await time.advance(ms(10));

      expect(queryClient.mutationCache.mutations, hasLength(1));
    },
  );

  testFakeAsync('should release the retryer once a mutation settles', (
    time,
  ) async {
    final observer = MutationObserver<String, String, Object?>(
      queryClient,
      MutationOptions<String, String, Object?>(
        mutationFn: (text, _) => sleep(ms(10)).then((_) => text),
      ),
    );

    unawaited(observer.mutate('data'));
    await time.advance(ms(10));

    final mutation = queryClient.mutationCache.mutations.first;
    expect(mutation.state.status, MutationStatus.success);

    // A retained retryer would hand back the future it closed over; a released
    // one leaves nothing to continue.
    await expectLater(mutation.resume(), completion(isNull));
  });

  testFakeAsync(
    'should release the retryer of a mutation that settled with an error',
    (time) async {
      final observer = MutationObserver<String, Object?, Object?>(
        queryClient,
        MutationOptions<String, Object?, Object?>(
          mutationFn: (_, _) => sleep(
            ms(10),
          ).then((_) => Future<String>.error(StateError('oops'))),
        ),
      );

      observer.mutate(null).ignore();
      await time.advance(ms(10));

      final mutation = queryClient.mutationCache.mutations.first;
      expect(mutation.state.status, MutationStatus.error);

      await expectLater(mutation.resume(), completion(isNull));
    },
  );

  testFakeAsync('should not re-execute a settled mutation when it is resumed', (
    time,
  ) async {
    var calls = 0;
    final observer = MutationObserver<String, Object?, Object?>(
      queryClient,
      MutationOptions<String, Object?, Object?>(
        mutationFn: (_, _) {
          calls++;
          return sleep(ms(10)).then((_) => 'data');
        },
      ),
    );

    unawaited(observer.mutate(null));
    await time.advance(ms(10));

    final mutation = queryClient.mutationCache.mutations.first;
    expect(mutation.state.status, MutationStatus.success);
    expect(calls, 1);

    await mutation.resume();
    await time.advance(ms(10));

    expect(calls, 1);
    expect(mutation.state.status, MutationStatus.success);
  });

  testFakeAsync(
    'should still resume a restored paused mutation that has no retryer',
    (time) async {
      var calls = 0;

      final mutation = queryClient.mutationCache
          .build<String, Object?, Object?>(
            queryClient.defaultMutationOptions(
              MutationOptions<String, Object?, Object?>(
                mutationFn: (_, _) {
                  calls++;
                  return sleep(ms(10)).then((_) => 'data');
                },
              ),
            ),
            state: MutationState<String, Object?, Object?>(
              isPaused: true,
              status: MutationStatus.pending,
              submittedAt: DateTime.utc(2020),
            ),
          );

      final resumed = mutation.resume();
      await time.advance(ms(10));
      await resumed;

      expect(calls, 1);
      expect(mutation.state.status, MutationStatus.success);
    },
  );
}
