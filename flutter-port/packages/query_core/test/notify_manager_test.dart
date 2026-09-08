import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Adapted from upstream `notifyManager.test.tsx`. Upstream schedules through
/// `setTimeout(0)` and exposes setNotifyFunction/setBatchNotifyFunction; here
/// delivery is coalesced into a microtask and `deferFlush` is the single seam
/// (D8), so the scheduling-hook tests are replaced by deferFlush tests.
void main() {
  late NotifyManager manager;

  setUp(() => manager = NotifyManager());

  group('NotifyManager', () {
    testFakeAsync('defers notifications to a microtask', (time) async {
      final calls = <String>[];
      manager.schedule(() => calls.add('first'));

      expect(calls, isEmpty, reason: 'delivery must not be synchronous');

      await time.flushMicrotasks();
      expect(calls, ['first']);
    });

    testFakeAsync('batches all callbacks scheduled in one transaction', (
      time,
    ) async {
      final calls = <String>[];

      manager.batch(() {
        manager.schedule(() => calls.add('a'));
        manager.schedule(() => calls.add('b'));
        expect(calls, isEmpty, reason: 'nothing fires inside the batch');
      });

      await time.flushMicrotasks();
      expect(calls, ['a', 'b']);
    });

    testFakeAsync('nested batches flush once, with the outermost', (
      time,
    ) async {
      final calls = <String>[];

      manager.batch(() {
        manager.schedule(() => calls.add('outer'));
        manager.batch(() {
          manager.schedule(() => calls.add('inner'));
        });
        expect(calls, isEmpty, reason: 'the inner batch must not flush');
      });

      await time.flushMicrotasks();
      expect(calls, ['outer', 'inner']);
    });

    testFakeAsync('returns the value the batched function produced', (
      time,
    ) async {
      expect(manager.batch(() => 42), 42);
      await time.flushMicrotasks();
    });

    testFakeAsync('flushes even when the batched function throws', (
      time,
    ) async {
      final calls = <String>[];

      expect(
        () => manager.batch(() {
          manager.schedule(() => calls.add('scheduled'));
          throw StateError('boom');
        }),
        throwsStateError,
      );

      await time.flushMicrotasks();
      expect(
          calls,
          [
            'scheduled',
          ],
          reason: 'a throwing transaction must not strand the queue');
    });

    testFakeAsync('drains callbacks scheduled from within a flush', (
      time,
    ) async {
      final calls = <String>[];

      manager.schedule(() {
        calls.add('first');
        // A listener reacting to a notification by triggering another one.
        manager.schedule(() => calls.add('second'));
      });

      await time.flushMicrotasks();
      expect(
          calls,
          [
            'first',
            'second',
          ],
          reason: 're-entrant schedules join the same flush');
    });

    testFakeAsync('deferFlush is the scheduling seam', (time) async {
      final calls = <String>[];
      var deferred = 0;
      void Function()? held;

      manager.deferFlush = (flush) {
        deferred++;
        held = flush;
      };

      manager.schedule(() => calls.add('a'));
      await time.flushMicrotasks();

      expect(deferred, 1);
      expect(calls, isEmpty, reason: 'the custom scheduler holds the flush');

      held!();
      expect(calls, ['a']);
    });
  });
}
