import 'dart:async';

import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Upstream has no dedicated retryer suite — its behavior is covered through
/// `query.test.tsx` and `mutation.test.tsx`. These tests exercise it directly
/// so the retry/pause/resume semantics are pinned before `Query` depends on
/// them (plan milestone M2).
void main() {
  setUp(() {
    focusManager.setFocused(null);
    onlineManager.setOnline(true);
  });

  group('Retryer', () {
    testFakeAsync('resolves with the value the function produced', (
      time,
    ) async {
      final retryer = Retryer<String>(
        fn: () async => 'data',
        canRun: () => true,
      );

      final result = retryer.start();
      await time.flushMicrotasks();

      expect(await result, 'data');
      expect(retryer.status, RetryerStatus.resolved);
    });

    testFakeAsync('every caller shares one future', (time) async {
      var calls = 0;
      final retryer = Retryer<String>(
        fn: () async {
          calls++;
          await sleep(const Duration(milliseconds: 10));
          return 'data';
        },
        canRun: () => true,
      );

      final first = retryer.start();
      final second = retryer.future;
      await time.advance(const Duration(milliseconds: 10));

      expect(await first, 'data');
      expect(await second, 'data');
      expect(calls, 1, reason: 'the function runs once for all awaiters');
    });

    testFakeAsync('retries three times by default, then rejects', (time) async {
      var attempts = 0;
      final retryer = Retryer<String>(
        fn: () async {
          attempts++;
          throw StateError('failed');
        },
        canRun: () => true,
        retryDelay: const RetryDelay.of(Duration(milliseconds: 10)),
      );

      final result = retryer.start();
      // 1 initial attempt + 3 retries.
      await time.advance(const Duration(milliseconds: 50));

      await expectLater(result, throwsStateError);
      expect(attempts, 4);
      expect(retryer.status, RetryerStatus.rejected);
    });

    testFakeAsync('succeeds on a retry after transient failures', (time) async {
      var attempts = 0;
      final retryer = Retryer<String>(
        fn: () async {
          attempts++;
          if (attempts < 3) {
            throw StateError('transient');
          }
          return 'data';
        },
        canRun: () => true,
        retryDelay: const RetryDelay.of(Duration(milliseconds: 10)),
      );

      final result = retryer.start();
      await time.advance(const Duration(milliseconds: 30));

      expect(await result, 'data');
      expect(attempts, 3);
    });

    testFakeAsync('reports each failure through onFail', (time) async {
      final failures = <int>[];
      final retryer = Retryer<String>(
        fn: () async => throw StateError('failed'),
        canRun: () => true,
        retry: const RetryOption.count(2),
        retryDelay: const RetryDelay.of(Duration(milliseconds: 10)),
        onFail: (failureCount, error, stackTrace) => failures.add(failureCount),
      );

      final result = retryer.start();
      await time.advance(const Duration(milliseconds: 30));
      await expectLater(result, throwsStateError);

      expect(failures, [1, 2]);
    });

    testFakeAsync('honours RetryOption.never', (time) async {
      var attempts = 0;
      final retryer = Retryer<String>(
        fn: () async {
          attempts++;
          throw StateError('failed');
        },
        canRun: () => true,
        retry: RetryOption.never,
      );

      final result = retryer.start();
      await time.flushMicrotasks();

      await expectLater(result, throwsStateError);
      expect(attempts, 1);
    });

    testFakeAsync('waits the configured delay between attempts', (time) async {
      var attempts = 0;
      final retryer = Retryer<String>(
        fn: () async {
          attempts++;
          throw StateError('failed');
        },
        canRun: () => true,
        retry: const RetryOption.count(1),
        retryDelay: const RetryDelay.of(Duration(milliseconds: 100)),
      );

      final result = retryer.start();
      await time.advance(const Duration(milliseconds: 50));
      expect(attempts, 1, reason: 'the retry is still waiting');

      await time.advance(const Duration(milliseconds: 50));
      expect(attempts, 2);
      await expectLater(result, throwsStateError);
    });

    group('cancellation', () {
      testFakeAsync('cancel rejects with a CancelledError', (time) async {
        final retryer = Retryer<String>(
          fn: () async {
            await sleep(const Duration(milliseconds: 100));
            return 'data';
          },
          canRun: () => true,
        );

        final result = retryer.start();
        retryer.cancel();

        await expectLater(result, throwsA(isA<CancelledError>()));
        expect(retryer.status, RetryerStatus.rejected);
      });

      testFakeAsync('cancel carries the revert and silent flags', (time) async {
        final retryer = Retryer<String>(
          fn: () async {
            await sleep(const Duration(milliseconds: 100));
            return 'data';
          },
          canRun: () => true,
        );

        CancelledError? reported;
        final result = retryer.start();
        retryer.cancel(revert: true, silent: true);

        await expectLater(
          result.catchError((Object e) {
            reported = e as CancelledError;
            return '';
          }),
          completes,
        );
        expect(reported?.revert, isTrue);
        expect(reported?.silent, isTrue);
      });

      testFakeAsync('onCancel fires once', (time) async {
        var cancels = 0;
        final retryer = Retryer<String>(
          fn: () async {
            await sleep(const Duration(milliseconds: 100));
            return 'data';
          },
          canRun: () => true,
          onCancel: (_) => cancels++,
        );

        unawaited(retryer.start());
        retryer.cancel();
        retryer.cancel();

        await time.flushMicrotasks();
        expect(cancels, 1);
      });

      testFakeAsync('cancelling a settled retryer does nothing', (time) async {
        final retryer = Retryer<String>(
          fn: () async => 'data',
          canRun: () => true,
        );

        final result = retryer.start();
        await time.flushMicrotasks();
        expect(await result, 'data');

        retryer.cancel();
        expect(
          retryer.status,
          RetryerStatus.resolved,
          reason: 'a resolved fetch cannot be cancelled after the fact',
        );
      });

      testFakeAsync('cancelRetry stops further attempts', (time) async {
        var attempts = 0;
        final retryer = Retryer<String>(
          fn: () async {
            attempts++;
            throw StateError('failed');
          },
          canRun: () => true,
          retry: RetryOption.forever,
          retryDelay: const RetryDelay.of(Duration(milliseconds: 10)),
        );

        final result = retryer.start();
        await time.advance(const Duration(milliseconds: 10));
        retryer.cancelRetry();
        await time.advance(const Duration(milliseconds: 50));

        await expectLater(result, throwsStateError);
        expect(
          attempts,
          lessThanOrEqualTo(3),
          reason: 'retrying stopped rather than continuing forever',
        );
      });
    });

    group('offline behaviour', () {
      testFakeAsync('pauses instead of starting while offline', (time) async {
        onlineManager.setOnline(false);
        var calls = 0;
        var paused = 0;

        final retryer = Retryer<String>(
          fn: () async {
            calls++;
            return 'data';
          },
          canRun: () => true,
          onPause: () => paused++,
        );

        final result = retryer.start();
        await time.flushMicrotasks();

        expect(calls, 0, reason: 'the fetch never started');
        expect(paused, 1);
        expect(retryer.status, RetryerStatus.pending);

        onlineManager.setOnline(true);
        await retryer.resume();
        await time.flushMicrotasks();

        expect(calls, 1);
        expect(await result, 'data');
      });

      testFakeAsync('resume reports continuation', (time) async {
        onlineManager.setOnline(false);
        var continued = 0;

        final retryer = Retryer<String>(
          fn: () async => 'data',
          canRun: () => true,
          onContinue: () => continued++,
        );

        unawaited(retryer.start());
        await time.flushMicrotasks();

        onlineManager.setOnline(true);
        await retryer.resume();
        await time.flushMicrotasks();

        expect(continued, 1);
      });

      testFakeAsync('stays paused while still offline', (time) async {
        onlineManager.setOnline(false);
        var calls = 0;

        final retryer = Retryer<String>(
          fn: () async {
            calls++;
            return 'data';
          },
          canRun: () => true,
        );

        unawaited(retryer.start());
        await time.flushMicrotasks();

        // A resume that arrives while conditions still forbid running must not
        // start the fetch.
        retryer.resume().ignore();
        await time.flushMicrotasks();
        expect(calls, 0);

        onlineManager.setOnline(true);
        retryer.resume().ignore();
        await time.flushMicrotasks();
        expect(calls, 1);
      });

      testFakeAsync('NetworkMode.always fetches while offline', (time) async {
        onlineManager.setOnline(false);
        var calls = 0;

        final retryer = Retryer<String>(
          fn: () async {
            calls++;
            return 'data';
          },
          canRun: () => true,
          networkMode: NetworkMode.always,
        );

        final result = retryer.start();
        await time.flushMicrotasks();

        expect(calls, 1);
        expect(await result, 'data');
      });

      testFakeAsync('canStart reflects connectivity and canRun', (time) async {
        final blocked = Retryer<String>(
          fn: () async => 'data',
          canRun: () => false,
        );
        expect(blocked.canStart(), isFalse);

        onlineManager.setOnline(false);
        final offline = Retryer<String>(
          fn: () async => 'data',
          canRun: () => true,
        );
        expect(offline.canStart(), isFalse);
        expect(canFetch(NetworkMode.always), isTrue);
        await time.flushMicrotasks();
      });
    });

    group('RetryDelay.exponential', () {
      test('doubles from one second', () {
        const delay = RetryDelay.exponential;
        final error = StateError('failed');
        expect(delay.delayFor(0, error), const Duration(seconds: 1));
        expect(delay.delayFor(1, error), const Duration(seconds: 2));
        expect(delay.delayFor(2, error), const Duration(seconds: 4));
      });

      test('caps at thirty seconds', () {
        const delay = RetryDelay.exponential;
        final error = StateError('failed');
        expect(delay.delayFor(10, error), const Duration(seconds: 30));
        expect(delay.delayFor(30, error), const Duration(seconds: 30));
      });
    });
  });
}
