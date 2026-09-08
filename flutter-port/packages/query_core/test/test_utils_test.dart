import 'dart:async';

import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Proves the harness itself before anything relies on it: virtual time must
/// advance, microtasks must interleave with timers, and errors must surface.
void main() {
  group('testFakeAsync harness', () {
    testFakeAsync('advances virtual time without real waiting', (time) async {
      final start = time.now;
      await time.advance(const Duration(seconds: 30));
      expect(time.now.difference(start), const Duration(seconds: 30));
    });

    testFakeAsync('resolves timers scheduled by the body', (time) async {
      var fired = false;
      unawaited(
        sleep(const Duration(milliseconds: 10)).then((_) {
          fired = true;
        }),
      );

      await time.advance(const Duration(milliseconds: 9));
      expect(fired, isFalse, reason: 'timer must not fire early');

      await time.advance(const Duration(milliseconds: 1));
      expect(fired, isTrue);
    });

    testFakeAsync('interleaves microtasks with timer firing', (time) async {
      // A chain where each step is scheduled only once the previous timer has
      // fired — this only completes if elapse() flushes microtasks as it goes,
      // which is the property the ported upstream tests depend on.
      final order = <String>[];
      unawaited(() async {
        await sleep(const Duration(milliseconds: 10));
        order.add('first');
        await sleep(const Duration(milliseconds: 10));
        order.add('second');
      }());

      await time.advance(const Duration(milliseconds: 20));
      expect(order, ['first', 'second']);
    });

    testFakeAsync('flushMicrotasks runs pending microtasks', (time) async {
      var ran = false;
      scheduleMicrotask(() => ran = true);
      expect(ran, isFalse);

      await time.flushMicrotasks();
      expect(ran, isTrue);
    });

    test('propagates failures out of the body', () {
      // A throw inside the body must surface, not be swallowed by the driver.
      expect(
        () => runFakeAsyncBody((time) async {
          await time.flushMicrotasks();
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
    });

    test('reports a body that can never complete', () {
      // The deadlock guard: awaiting a future virtual time cannot resolve.
      final completed = runFakeAsyncBody((time) async {
        await Completer<void>().future;
      });
      expect(completed, isFalse);
    });
  });

  group('test helpers', () {
    test('queryKey returns a fresh key each call', () {
      final first = queryKey();
      final second = queryKey();
      expect(first, isNot(second));
      expect(first, first);
    });

    test('mockOnline restores the previous state', () {
      expect(onlineManager.isOnline, isTrue);
      final inner = mockOnline(false, () => onlineManager.isOnline);
      expect(inner, isFalse);
      expect(onlineManager.isOnline, isTrue);
    });
  });
}
