/// Port of `query-core/src/removable.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'option_values.dart';
import 'timers.dart';

/// Something the cache garbage-collects once nothing observes it.
///
/// The timer's duration is clamped to [maxTimerDuration]: Dart's [Timer] is
/// 64-bit on the VM but rides on `setTimeout` on the web, where a `gcTime`
/// over 24.8 days would fire after a millisecond (fourth review, 2026-09-09).
abstract class Removable {
  Timer? _gcTimer;

  GcTime? _gcTime;

  /// How long this may sit unused before it is collected. `null` until
  /// options are applied. Readable, as upstream has it — devtools and tests
  /// read the value that actually won — but only [updateGcTime] moves it,
  /// because the longest request has to keep winning.
  GcTime? get gcTime => _gcTime;

  /// Arms the collection timer for the current [gcTime], replacing any that is
  /// already running. Called when the last observer leaves; a [GcTime.never]
  /// arms nothing.
  @protected
  void scheduleGc() {
    clearGcTimeout();
    final gcTime = _gcTime;
    if (gcTime is GcTimeDuration) {
      _gcTimer = Timer(clampTimerDuration(gcTime.duration), optionalRemove);
    }
  }

  /// Folds [newGcTime] (or upstream's five-minute default when `null`) into
  /// [gcTime], keeping whichever of the old and new values is longer.
  @protected
  void updateGcTime(GcTime? newGcTime) {
    // The longest requested duration wins, exactly as upstream does when
    // several observers disagree.
    _gcTime = GcTime.longest(
        _gcTime,
        newGcTime ??
            const GcTime.duration(
              Duration(minutes: 5),
            ));
  }

  /// Cancels the collection timer without touching [gcTime]. Called whenever an
  /// observer attaches or a fetch starts, so a used entry is never collected.
  @protected
  void clearGcTimeout() {
    _gcTimer?.cancel();
    _gcTimer = null;
  }

  /// Cancels the pending collection, if any.
  @protected
  void destroy() => clearGcTimeout();

  /// Removes this from its cache if nothing is using it.
  @protected
  void optionalRemove();
}
