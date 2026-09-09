/// Ported from `query-core/src/__tests__/removable.test.tsx`
/// at upstream `50680b98c`. 11 of 12 cases; the server case is omitted, and
/// the assertions move from spying on `timeoutManager`'s provider to observing
/// the effect under virtual time (see PORTING_NOTES.md).
library;

// The unit under test is internal plumbing the package does not export.
import 'package:tanstack_query_core/src/removable.dart';
import 'package:tanstack_query_core/tanstack_query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

class RemovableTest extends Removable {
  int optionalRemoveCalls = 0;

  // Expose the protected members so they can be exercised directly.
  void callScheduleGc() => scheduleGc();

  void callUpdateGcTime(GcTime? newGcTime) => updateGcTime(newGcTime);

  void callClearGcTimeout() => clearGcTimeout();

  void callDestroy() => destroy();

  GcTime? get currentGcTime => gcTime;

  @override
  void optionalRemove() => optionalRemoveCalls++;
}

void main() {
  group('Removable', () {
    group('updateGcTime', () {
      test(
        'should default to 5 minutes when no gcTime is provided on the client',
        () {
          final removable = RemovableTest();

          removable.callUpdateGcTime(null);

          expect(
            removable.currentGcTime,
            equals(const GcTime.duration(Duration(minutes: 5))),
          );
        },
      );

      test(
        'should use the provided gcTime when it is larger than the default',
        () {
          final removable = RemovableTest();

          removable
              .callUpdateGcTime(const GcTime.duration(Duration(minutes: 10)));

          expect(
            removable.currentGcTime,
            equals(const GcTime.duration(Duration(minutes: 10))),
          );
        },
      );

      test(
        'should use an explicit gcTime even when it is smaller than the default',
        () {
          final removable = RemovableTest();

          removable
              .callUpdateGcTime(const GcTime.duration(Duration(seconds: 1)));

          expect(
            removable.currentGcTime,
            equals(const GcTime.duration(Duration(seconds: 1))),
          );
        },
      );

      test('should never decrease an already larger gcTime', () {
        final removable = RemovableTest();

        removable
            .callUpdateGcTime(const GcTime.duration(Duration(minutes: 10)));
        removable.callUpdateGcTime(const GcTime.duration(Duration(seconds: 1)));

        expect(
          removable.currentGcTime,
          equals(const GcTime.duration(Duration(minutes: 10))),
        );
      });
    });

    group('scheduleGc', () {
      testFakeAsync('should schedule optionalRemove after a valid gcTime', (
        time,
      ) async {
        final removable = RemovableTest();
        removable.callUpdateGcTime(const GcTime.duration(Duration(seconds: 1)));

        removable.callScheduleGc();

        await time.advance(ms(999));
        expect(removable.optionalRemoveCalls, 0);

        await time.advance(ms(1));
        expect(removable.optionalRemoveCalls, 1);
      });

      testFakeAsync('should not schedule when gcTime is not a valid timeout', (
        time,
      ) async {
        final removable = RemovableTest();
        removable.callUpdateGcTime(GcTime.never);

        removable.callScheduleGc();

        expect(time.pendingTimers, 0);
        await time.advance(const Duration(days: 1));
        expect(removable.optionalRemoveCalls, 0);
      });

      testFakeAsync(
        'should clear a previously scheduled timeout before scheduling a new one',
        (time) async {
          final removable = RemovableTest();
          removable
              .callUpdateGcTime(const GcTime.duration(Duration(seconds: 1)));

          removable.callScheduleGc();
          await time.advance(ms(500));
          removable.callScheduleGc();

          expect(time.pendingTimers, 1);

          // The first timer would have fired here had it survived.
          await time.advance(ms(500));
          expect(removable.optionalRemoveCalls, 0);

          await time.advance(ms(500));
          expect(removable.optionalRemoveCalls, 1);
        },
      );
    });

    group('clearGcTimeout', () {
      testFakeAsync('should clear a scheduled timeout', (time) async {
        final removable = RemovableTest();
        removable.callUpdateGcTime(const GcTime.duration(Duration(seconds: 1)));
        removable.callScheduleGc();

        removable.callClearGcTimeout();

        expect(time.pendingTimers, 0);
        await time.advance(const Duration(seconds: 2));
        expect(removable.optionalRemoveCalls, 0);
      });

      testFakeAsync('should do nothing when no timeout is scheduled', (
        time,
      ) async {
        final removable = RemovableTest();

        removable.callClearGcTimeout();

        expect(time.pendingTimers, 0);
      });

      testFakeAsync('should not clear the same timeout twice', (time) async {
        final removable = RemovableTest();
        removable.callUpdateGcTime(const GcTime.duration(Duration(seconds: 1)));
        removable.callScheduleGc();

        removable.callClearGcTimeout();
        removable.callClearGcTimeout();

        expect(time.pendingTimers, 0);
      });
    });

    group('destroy', () {
      testFakeAsync('should clear the scheduled gc timeout', (time) async {
        final removable = RemovableTest();
        removable.callUpdateGcTime(const GcTime.duration(Duration(seconds: 1)));
        removable.callScheduleGc();

        removable.callDestroy();

        expect(time.pendingTimers, 0);
        await time.advance(const Duration(seconds: 2));
        expect(removable.optionalRemoveCalls, 0);
      });
    });
  });
}
