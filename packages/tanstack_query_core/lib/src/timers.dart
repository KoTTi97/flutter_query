/// The two timer facts the core has to know about: the longest delay a
/// timer takes, and the millisecond it is rounded to.
///
/// Every delay the core arms — a `gcTime`, a stale timer, a refetch interval,
/// a retry backoff — goes through [clampTimerDuration]. Port-only: upstream at
/// `50680b98c` has no clamp (its `isValidTimeout` only rejects `Infinity`),
/// and neither did this port until the fourth review (2026-09-09) ran a
/// 30-day `Timer` under dart2js and watched it fire first. The stale timer
/// also goes through [ceilToMilliseconds]; see there for why only it does.
library;

/// The longest delay a timer can be given on every platform Dart runs on.
///
/// The VM's [Timer] takes a 64-bit [Duration]. dart2js and dart2wasm hand the
/// milliseconds to `setTimeout` / `setInterval`, and browsers (and Node) treat
/// anything above 2^31 − 1 as an overflow and fire after **1 ms** — so a
/// `GcTime.duration(Duration(days: 30))` collected its query a millisecond
/// after the last observer left, and a 30-day `RefetchInterval.every` polled
/// every millisecond.
const Duration maxTimerDuration = Duration(milliseconds: 0x7FFFFFFF);

/// [duration], no longer than [maxTimerDuration] (about 24.8 days).
///
/// A clamp rather than "never": a 30-day gc that runs on day 24.8 is
/// harmless, while a 30-day gc that never runs would change what the option
/// means.
Duration clampTimerDuration(Duration duration) =>
    duration > maxTimerDuration ? maxTimerDuration : duration;

/// [duration] rounded *up* to whole milliseconds, and never less than one.
///
/// Every `Timer` is armed in whole milliseconds: the VM takes
/// `duration.inMilliseconds` (and adds one, on a clock that is itself floored
/// to the millisecond, so its guarantee is "not before `trunc(d)`", not "not
/// before `d`"); dart2js and dart2wasm hand `inMilliseconds` to `setTimeout`
/// with no extra millisecond at all. A deadline 29.6 ms away armed for 29 ms
/// can run before it. Upstream's `#updateStaleTimeout` adds a millisecond for
/// the same reason. The stale timer, which must not fire *before* its
/// deadline, rounds up here; the gc timer, a refetch interval and a retry
/// backoff may run a fraction of a millisecond early without anyone noticing,
/// and take their durations as they are (fifth review, 2026-09-09).
Duration ceilToMilliseconds(Duration duration) {
  final micros = duration.inMicroseconds;
  if (micros <= 0) {
    return const Duration(milliseconds: 1);
  }
  return Duration(
    milliseconds: (micros + Duration.microsecondsPerMillisecond - 1) ~/
        Duration.microsecondsPerMillisecond,
  );
}
