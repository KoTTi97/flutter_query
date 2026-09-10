/// Ported from `query-core/src/__tests__/notifyManager.test.tsx`
/// at upstream `50680b98c`. 6 of 7 cases; the type-level case is omitted
/// (see PORTING_NOTES.md).
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('notifyManager', () {
    testFakeAsync('should use default notifyFn', (time) async {
      final notifyManagerTest = NotifyManager();
      var callbackCalls = 0;
      notifyManagerTest.schedule(() => callbackCalls++);
      await time.flushMicrotasks();
      expect(callbackCalls, greaterThan(0));
    });

    testFakeAsync('should use default batchNotifyFn', (time) async {
      final notifyManagerTest = NotifyManager();
      var scheduleCalls = 0;
      var batchLevel2Calls = 0;
      var batchLevel1Calls = 0;

      void callbackSchedule() {
        scheduleCalls++;
        sleep(ms(20)).ignore();
      }

      void callbackBatchLevel2() {
        batchLevel2Calls++;
        notifyManagerTest.schedule(callbackSchedule);
      }

      void callbackBatchLevel1() {
        batchLevel1Calls++;
        notifyManagerTest.batch(callbackBatchLevel2);
      }

      notifyManagerTest.batch(callbackBatchLevel1);

      await time.flushMicrotasks();
      expect(batchLevel1Calls, 1);
      expect(batchLevel2Calls, 1);
      expect(scheduleCalls, 1);
    });

    testFakeAsync('should use a custom scheduler when configured',
        (time) async {
      var customCallbackCalls = 0;
      void customCallback(void Function() callback) {
        customCallbackCalls++;
        scheduleMicrotaskShim(callback);
      }

      final notifyManagerTest = NotifyManager();
      var notifyCalls = 0;
      notifyManagerTest.setScheduler(customCallback);
      notifyManagerTest.setNotifyFunction((callback) {
        notifyCalls++;
        callback();
      });

      notifyManagerTest.batch(() => notifyManagerTest.schedule(() {}));

      expect(customCallbackCalls, 1);

      await time.flushMicrotasks();
      expect(notifyCalls, 1);
    });

    testFakeAsync('should notify if error is thrown', (time) async {
      final notifyManagerTest = NotifyManager();
      var notifyCalls = 0;

      notifyManagerTest.setNotifyFunction((callback) {
        notifyCalls++;
        callback();
      });

      try {
        notifyManagerTest.batch(() {
          notifyManagerTest.schedule(() {});
          throw StateError('Foo');
        });
      } catch (_) {}

      await time.flushMicrotasks();

      expect(notifyCalls, 1);
    });

    testFakeAsync('should use custom batch notify function', (time) async {
      final notifyManagerTest = NotifyManager();
      var batchNotifyCalls = 0;
      var callback1Calls = 0;
      var callback2Calls = 0;

      notifyManagerTest.setBatchNotifyFunction((callback) {
        batchNotifyCalls++;
        callback();
      });

      notifyManagerTest.batch(() {
        notifyManagerTest.schedule(() => callback1Calls++);
        notifyManagerTest.schedule(() => callback2Calls++);
      });

      await time.flushMicrotasks();

      expect(batchNotifyCalls, greaterThan(0));
      expect(callback1Calls, greaterThan(0));
      expect(callback2Calls, greaterThan(0));
    });

    testFakeAsync('should batch calls correctly', (time) async {
      final notifyManagerTest = NotifyManager();
      final calls = <(int, String)>[];

      // Upstream's `batchCalls` is variadic; Dart has no variadics, so the
      // arguments travel as one record.
      final batchedFn = notifyManagerTest.batchCalls<(int, String)>(calls.add);

      batchedFn((1, 'test'));
      await time.flushMicrotasks();

      expect(calls, equals(<(int, String)>[(1, 'test')]));
    });
  });
}
