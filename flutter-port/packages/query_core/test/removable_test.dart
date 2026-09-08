import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

class _TestRemovable extends Removable {
  int removeCalls = 0;

  @override
  void optionalRemove() => removeCalls++;
}

/// Covers the garbage-collection scheduling upstream exercises through
/// `query.test.tsx`'s gc cases — pulled out here because it is its own base
/// class in the port.
void main() {
  group('Removable', () {
    testFakeAsync('removes after the gc time elapses', (time) async {
      final removable = _TestRemovable()
        ..updateGcTime(const GcDuration.of(Duration(minutes: 1)));
      removable.scheduleGc();

      await time.advance(const Duration(seconds: 59));
      expect(removable.removeCalls, 0);

      await time.advance(const Duration(seconds: 1));
      expect(removable.removeCalls, 1);
    });

    testFakeAsync('clearing the timeout cancels removal', (time) async {
      final removable = _TestRemovable()
        ..updateGcTime(const GcDuration.of(Duration(minutes: 1)))
        ..scheduleGc();

      removable.clearGcTimeout();
      await time.advance(const Duration(minutes: 5));
      expect(removable.removeCalls, 0);
    });

    testFakeAsync('rescheduling restarts the clock', (time) async {
      final removable = _TestRemovable()
        ..updateGcTime(const GcDuration.of(Duration(minutes: 1)))
        ..scheduleGc();

      await time.advance(const Duration(seconds: 50));
      removable.scheduleGc();

      await time.advance(const Duration(seconds: 50));
      expect(removable.removeCalls, 0, reason: 'the clock restarted');

      await time.advance(const Duration(seconds: 10));
      expect(removable.removeCalls, 1);
    });

    testFakeAsync('never collects with GcDuration.never', (time) async {
      final removable = _TestRemovable()
        ..updateGcTime(GcDuration.never)
        ..scheduleGc();

      await time.advance(const Duration(days: 1));
      expect(removable.removeCalls, 0);
    });

    // Upstream: "should use the longest garbage collection time it has seen".
    group('updateGcTime keeps the longest lifetime seen', () {
      test('grows to the longer value', () {
        final removable = _TestRemovable()
          ..updateGcTime(GcDuration.of(const Duration(minutes: 1)))
          ..updateGcTime(GcDuration.of(const Duration(minutes: 10)));

        expect(removable.gcTime, GcDuration.of(const Duration(minutes: 10)));
      });

      test('ignores a shorter value', () {
        final removable = _TestRemovable()
          ..updateGcTime(GcDuration.of(const Duration(minutes: 10)))
          ..updateGcTime(GcDuration.of(const Duration(minutes: 1)));

        expect(removable.gcTime, GcDuration.of(const Duration(minutes: 10)));
      });

      test('never wins over any duration', () {
        final removable = _TestRemovable()
          ..updateGcTime(GcDuration.of(const Duration(minutes: 1)))
          ..updateGcTime(GcDuration.never);

        expect(removable.gcTime, GcDuration.never);

        removable.updateGcTime(GcDuration.of(const Duration(minutes: 10)));
        expect(removable.gcTime, GcDuration.never);
      });

      test('null falls back to the five-minute default', () {
        final removable = _TestRemovable()..updateGcTime(null);
        expect(removable.gcTime, GcDuration.of(Removable.defaultGcTime));
      });
    });
  });
}
