/// Ported from `query-core/src/__tests__/retryer.test.tsx`
/// at upstream `50680b98c`. 13 of 13 cases.
library;

import 'dart:async';

import 'package:tanstack_query_core/tanstack_query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('createRetryer', () {
    late AppFocusManager focusManager;
    late OnlineManager onlineManager;

    setUp(() {
      // Upstream resets the module-level managers here; ours are per-test
      // instances (https://github.com/KoTTi97/flutter_query/issues/19).
      focusManager = AppFocusManager();
      onlineManager = OnlineManager();
    });

    Retryer<T> createRetryer<T>({
      required Future<T> Function() fn,
      Future<T>? initialFuture,
      RetryPolicy retry = RetryPolicy.never,
      RetryDelay retryDelay = RetryDelay.defaultValue,
      NetworkMode networkMode = NetworkMode.online,
      bool Function()? canRun,
      void Function(int failureCount, Object error, StackTrace stackTrace)?
          onFail,
      void Function()? onPause,
      void Function()? onContinue,
      void Function(CancelledError error)? onCancel,
    }) =>
        Retryer<T>(
          fn: fn,
          initialFuture: initialFuture,
          focusManager: focusManager,
          onlineManager: onlineManager,
          canRun: canRun ?? () => true,
          retry: retry,
          retryDelay: retryDelay,
          networkMode: networkMode,
          onFail: onFail,
          onPause: onPause,
          onContinue: onContinue,
          onCancel: onCancel,
        );

    testFakeAsync(
      'should resolve with the result of fn and set status to resolved',
      (time) async {
        var calls = 0;
        final retryer = createRetryer<String>(
          fn: () async {
            calls++;
            return 'success';
          },
        );

        final future = retryer.start();
        await time.flushMicrotasks();

        expect(await future, 'success');
        expect(retryer.status, RetryerStatus.resolved);
        expect(calls, 1);
      },
    );

    testFakeAsync(
      'should reject after exhausting the retry limit and report each failure',
      (time) async {
        final error = StateError('failed');
        var calls = 0;
        final failures = <(int, Object)>[];

        final retryer = createRetryer<String>(
          fn: () async {
            calls++;
            throw error;
          },
          retry: const RetryPolicy.times(2),
          onFail: (failureCount, error, _) =>
              failures.add((failureCount, error)),
        );

        final future = retryer.start();
        await time.advance(ms(10000));

        await expectLater(future, throwsA(same(error)));
        expect(calls, 3);
        expect(failures, equals(<(int, Object)>[(1, error), (2, error)]));
        expect(retryer.status, RetryerStatus.rejected);
      },
    );

    testFakeAsync(
      'should retry a synchronous throw and resolve once fn succeeds',
      (time) async {
        var calls = 0;
        final retryer = createRetryer<String>(
          fn: () {
            calls++;
            if (calls == 1) {
              throw StateError('sync throw');
            }
            return Future<String>.value('success');
          },
          retry: const RetryPolicy.times(1),
        );

        final future = retryer.start();
        await time.advance(ms(5000));

        expect(await future, 'success');
        expect(calls, 2);
      },
    );

    testFakeAsync(
      'should use the default exponential backoff capped at 30 seconds',
      (time) async {
        // Upstream reads the delays off a `setTimeout` spy; the delays are a
        // pure function here, so they are asserted directly and the loop is
        // then run to prove the same schedule drives it.
        final delays = <Duration>[
          for (var failureCount = 0; failureCount < 6; failureCount++)
            RetryDelay.defaultValue.resolve(failureCount, StateError('failed')),
        ];
        expect(
          delays,
          equals(<Duration>[
            ms(1000),
            ms(2000),
            ms(4000),
            ms(8000),
            ms(16000),
            ms(30000),
          ]),
        );

        var calls = 0;
        final retryer = createRetryer<String>(
          fn: () async {
            calls++;
            if (calls < 7) {
              throw StateError('failed');
            }
            return 'success';
          },
          retry: RetryPolicy.always,
        );

        final future = retryer.start();
        await time.advance(ms(100000));

        expect(await future, 'success');
        expect(calls, 7);
      },
    );

    testFakeAsync(
      'should reject with a CancelledError carrying the cancel options and '
      'call onCancel',
      (time) async {
        CancelledError? cancelled;
        final retryer = createRetryer<String>(
          fn: () => Completer<String>().future,
          onCancel: (error) => cancelled = error,
        );

        final future = retryer.start();
        retryer.cancel(revert: true, silent: true);

        Object? caught;
        try {
          await future;
        } catch (error) {
          caught = error;
        }

        expect(caught, isA<CancelledError>());
        expect((caught! as CancelledError).revert, isTrue);
        expect((caught as CancelledError).silent, isTrue);
        expect(cancelled, same(caught));
        expect(retryer.status, RetryerStatus.rejected);
      },
    );

    testFakeAsync('should ignore cancel after the retryer resolved', (
      time,
    ) async {
      var cancelCalls = 0;
      final retryer = createRetryer<String>(
        fn: () async => 'success',
        onCancel: (_) => cancelCalls++,
      );

      final future = retryer.start();
      await time.flushMicrotasks();
      retryer.cancel();

      expect(await future, 'success');
      expect(retryer.status, RetryerStatus.resolved);
      expect(cancelCalls, 0);
    });

    testFakeAsync(
      'should reject the pending retry instead of re-running when cancelRetry '
      'was called',
      (time) async {
        final error = StateError('failed');
        var calls = 0;
        final retryer = createRetryer<String>(
          fn: () async {
            calls++;
            throw error;
          },
          retry: const RetryPolicy.times(1),
        );

        final future = retryer.start();
        await time.flushMicrotasks();
        expect(calls, 1);

        retryer.cancelRetry();
        await time.advance(ms(5000));

        await expectLater(future, throwsA(same(error)));
        expect(calls, 1);
        expect(retryer.status, RetryerStatus.rejected);
      },
    );

    testFakeAsync(
        'should resume retrying after continueRetry reverts cancelRetry', (
      time,
    ) async {
      var calls = 0;
      final retryer = createRetryer<String>(
        fn: () async {
          calls++;
          if (calls == 1) {
            throw StateError('failed');
          }
          return 'success';
        },
        retry: const RetryPolicy.times(1),
      );

      final future = retryer.start();
      await time.flushMicrotasks();
      retryer.cancelRetry();
      retryer.continueRetry();
      await time.advance(ms(5000));

      expect(await future, 'success');
      expect(calls, 2);
    });

    testFakeAsync(
      'should pause when offline during a retry and continue when back online',
      (time) async {
        var calls = 0;
        var pauseCalls = 0;
        var continueCalls = 0;

        final retryer = createRetryer<String>(
          fn: () async {
            calls++;
            if (calls == 1) {
              throw StateError('failed');
            }
            return 'success';
          },
          retry: const RetryPolicy.times(1),
          onPause: () => pauseCalls++,
          onContinue: () => continueCalls++,
        );

        final future = retryer.start();
        onlineManager.setOnline(false);
        await time.advance(ms(5000));

        expect(pauseCalls, 1);
        expect(calls, 1);
        expect(retryer.status, RetryerStatus.pending);

        onlineManager.setOnline(true);
        retryer.continueFetch().ignore();
        await time.flushMicrotasks();

        expect(continueCalls, 1);
        expect(await future, 'success');
        expect(calls, 2);
      },
    );

    testFakeAsync('should run even when offline with networkMode "always"', (
      time,
    ) async {
      onlineManager.setOnline(false);
      var calls = 0;
      final retryer = createRetryer<String>(
        fn: () async {
          calls++;
          return 'success';
        },
        networkMode: NetworkMode.always,
      );

      final future = retryer.start();
      await time.flushMicrotasks();

      expect(await future, 'success');
      expect(calls, 1);
    });

    testFakeAsync(
      'should start offline with networkMode "offlineFirst" but pause when the '
      'retry stays offline',
      (time) async {
        onlineManager.setOnline(false);
        var calls = 0;
        var pauseCalls = 0;

        final retryer = createRetryer<String>(
          fn: () async {
            calls++;
            if (calls == 1) {
              throw StateError('failed');
            }
            return 'success';
          },
          retry: const RetryPolicy.times(1),
          onPause: () => pauseCalls++,
          networkMode: NetworkMode.offlineFirst,
        );

        retryer.start().ignore();
        await time.advance(ms(5000));

        expect(calls, 1);
        expect(pauseCalls, 1);
        expect(retryer.status, RetryerStatus.pending);
      },
    );

    test('should reflect network availability in canFetch and canStart', () {
      onlineManager.setOnline(false);

      expect(canFetch(NetworkMode.online, onlineManager), isFalse);
      expect(canFetch(NetworkMode.offlineFirst, onlineManager), isTrue);

      final onlineRetryer = createRetryer<String>(
        fn: () async => '',
      );
      expect(onlineRetryer.canStart(), isFalse);

      final offlineFirstRetryer = createRetryer<String>(
        fn: () async => '',
        networkMode: NetworkMode.offlineFirst,
      );
      expect(offlineFirstRetryer.canStart(), isTrue);

      onlineManager.setOnline(true);
      expect(onlineRetryer.canStart(), isTrue);
    });

    testFakeAsync(
      'should reuse the initialPromise on the first run and call fn only on '
      'retries',
      (time) async {
        var calls = 0;
        // `.ignore()` because the retryer is the only listener and it attaches
        // one microtask later (https://github.com/KoTTi97/flutter_query/issues/9).
        final initial = Future<String>.microtask(
          () => throw StateError('initial failed'),
        )..ignore();

        final retryer = createRetryer<String>(
          fn: () async {
            calls++;
            return 'from fn';
          },
          initialFuture: initial,
          retry: const RetryPolicy.times(1),
        );

        final future = retryer.start();
        await time.advance(ms(5000));

        expect(await future, 'from fn');
        expect(calls, 1);
      },
    );
  });
}
