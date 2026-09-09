/// The one timer limit the core has to know about.
///
/// Every delay the core arms — a `gcTime`, a stale timer, a refetch interval,
/// a retry backoff — goes through [clampTimerDuration]. Port-only: upstream at
/// `50680b98c` has no clamp (its `isValidTimeout` only rejects `Infinity`),
/// and neither did this port until the fourth review (2026-09-09) ran a
/// 30-day `Timer` under dart2js and watched it fire first.
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
