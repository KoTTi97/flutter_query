import 'dart:async';

import 'option_values.dart';

/// Garbage-collection scheduling for cache entries.
///
/// The clock starts when an entry has no observers left, and is cleared when
/// one arrives. [gcTime] only ever grows: if two observers ask for different
/// lifetimes, the entry survives for the longer of them.
abstract class Removable {
  /// Unset until the first [updateGcTime], so the first value applies as given
  /// rather than being widened against a default.
  GcDuration? _gcTime;
  Timer? _gcTimer;

  static const Duration defaultGcTime = Duration(minutes: 5);

  GcDuration get gcTime => _gcTime ?? const GcDuration.of(defaultGcTime);

  /// Starts (or restarts) the collection timer.
  void scheduleGc() {
    clearGcTimeout();
    final gcTime = this.gcTime;
    if (gcTime is GcDurationValue) {
      _gcTimer = Timer(gcTime.duration, optionalRemove);
    }
  }

  /// Widens the collection time to cover [newGcTime]; null means "use the
  /// default". Only ever grows: an observer asking for a longer lifetime wins,
  /// and one asking for a shorter one cannot cut an entry short.
  void updateGcTime(GcDuration? newGcTime) {
    _gcTime = (_gcTime ?? const GcDuration.of(Duration.zero)).max(
      newGcTime ?? const GcDuration.of(defaultGcTime),
    );
  }

  void clearGcTimeout() {
    _gcTimer?.cancel();
    _gcTimer = null;
  }

  /// Called when the timer fires. Implementations decide whether the entry is
  /// really removable (it may have picked up observers or be mid-fetch).
  void optionalRemove();

  void destroy() {
    clearGcTimeout();
  }
}
