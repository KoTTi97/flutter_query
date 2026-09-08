/// Port of `query-core/src/removable.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'option_values.dart';

/// Something the cache garbage-collects once nothing observes it.
///
/// Upstream clamps `gcTime` to `setTimeout`'s 32-bit limit; Dart's [Timer]
/// takes a 64-bit [Duration], so the clamp is not ported
/// (https://github.com/KoTTi97/flutter_query/issues/9).
abstract class Removable {
  Timer? _gcTimer;

  /// How long this may sit unused before it is collected. `null` until
  /// options are applied.
  @protected
  GcTime? gcTime;

  @protected
  void scheduleGc() {
    clearGcTimeout();
    final gcTime = this.gcTime;
    if (gcTime is GcTimeDuration) {
      _gcTimer = Timer(gcTime.duration, optionalRemove);
    }
  }

  @protected
  void updateGcTime(GcTime? newGcTime) {
    // The longest requested duration wins, exactly as upstream does when
    // several observers disagree.
    gcTime = GcTime.longest(
        gcTime,
        newGcTime ??
            const GcTime.duration(
              Duration(minutes: 5),
            ));
  }

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
