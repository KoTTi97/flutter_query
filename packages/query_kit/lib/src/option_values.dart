/// The sealed value types that replace upstream's union-typed options.
///
/// Dart has no union types, so each of `staleTime: number | 'static' | fn`,
/// `enabled: boolean | fn`, `retry: boolean | number | fn` and friends becomes
/// a `const`-constructible sealed class. `null` is reserved to mean "not
/// configured" on every option field, which is why "off" is a *value* here
/// ([RefetchInterval.off], [RetryPolicy.never]) and never a null.
/// See https://github.com/KoTTi97/flutter_query/issues/10.
library;

import 'package:meta/meta.dart';

import 'query.dart';

/// How long fetched data stays fresh.
@immutable
sealed class StaleTime {
  const StaleTime();

  /// Fresh for [duration] after it was fetched.
  const factory StaleTime.duration(Duration duration) = StaleTimeDuration;

  /// Stale the moment it arrives — upstream's `staleTime: 0`, the default.
  static const StaleTime zero = StaleTimeDuration(Duration.zero);

  /// Never stale and, while an observer holds it, never refetched by any
  /// trigger — upstream's `staleTime: 'static'`. Even an explicit
  /// `refetchQueries` skips it; only an explicit `refetchInterval` and a
  /// `refetch()` still fetch. It is an observer's option: an entry nobody
  /// observes (one fetched by `QueryClient.query`, say) is an ordinary entry
  /// to `refetchQueries` and `invalidateQueries`, as upstream's `isStatic`
  /// reads the observers too (DC-05, 2026-09-12).
  static const StaleTime static = StaleTimeStatic();

  /// Never stale by time, but still refetched when asked — upstream's
  /// `staleTime: Infinity`, which Dart has no `Duration` for.
  static const StaleTime infinite = StaleTimeInfinite();

  /// Computed per query, from its current state.
  ///
  /// Asked every time staleness is decided, which is several times per
  /// operation — four times for a single subscribe-and-fetch as this is
  /// written, and no number worth relying on. Keep [compute] cheap and free
  /// of side effects; it is a question about the query, not a place to do
  /// work (eighth review, 2026-09-10).
  const factory StaleTime.dynamic(
      StaleTime Function(Query<Object?> query) compute) = StaleTimeDynamic;

  /// This with any [StaleTime.dynamic] layer peeled off for [query], so the
  /// result is one of [StaleTimeDuration], [StaleTimeStatic] or
  /// [StaleTimeInfinite].
  ///
  /// Callers that need more than one fact about a stale time resolve *once*
  /// and then ask the result — a dynamic stale time is user code, and calling
  /// it twice per decision would be visible to whoever wrote it.
  StaleTime resolveFor(Query<Object?> query) => switch (this) {
        StaleTimeDynamic(:final compute) => compute(query).resolveFor(query),
        _ => this,
      };

  /// Resolves this to a plain duration for [query]. `null` means "never stale
  /// by time", which both [StaleTime.static] and [StaleTime.infinite] are.
  Duration? resolve(Query<Object?> query) => switch (resolveFor(query)) {
        StaleTimeDuration(:final duration) => duration,
        _ => null,
      };

  /// Whether this resolves to [StaleTime.static] for [query] — the one thing
  /// that separates it from [StaleTime.infinite]: a static query is skipped by
  /// `refetchQueries` and by every refetch trigger, and outranks an
  /// invalidation.
  bool isStaticFor(Query<Object?> query) =>
      resolveFor(query) is StaleTimeStatic;
}

/// The [StaleTime.duration] variant: fresh for [duration] after the fetch that
/// produced the data, stale from then on.
final class StaleTimeDuration extends StaleTime {
  /// Fresh for [duration].
  const StaleTimeDuration(this.duration);

  /// How long the data counts as fresh, measured from `dataUpdatedAt`.
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is StaleTimeDuration && other.duration == duration;
  @override
  int get hashCode => duration.hashCode;
  @override
  String toString() => 'StaleTime.duration($duration)';
}

/// The [StaleTime.static] variant: never stale, and — while an observer with
/// this option holds the query — never refetched by a trigger either: not on
/// mount, focus, reconnect, invalidation or `refetchQueries`. With no
/// observer, `refetchQueries` and `invalidateQueries` refetch it like any
/// other entry. Two things still fetch it: a `refetch()` on the observer
/// itself, and an explicit `refetchInterval`, which polls a static query
/// exactly as it polls any other — an interval is a request, not a trigger,
/// and upstream (`50680b98c`) polls too; only `refetchQueries` filters
/// static out. (This dartdoc used to list "interval" among the refetches
/// static prevents; the behaviour never did — fifth review, 2026-09-09.)
final class StaleTimeStatic extends StaleTime {
  /// The one instance is [StaleTime.static]; a `const StaleTimeStatic()` is
  /// the same value.
  const StaleTimeStatic();
  @override
  bool operator ==(Object other) => other is StaleTimeStatic;
  @override
  int get hashCode => (StaleTimeStatic).hashCode;
  @override
  String toString() => 'StaleTime.static';
}

/// The [StaleTime.infinite] variant: never stale by time, so nothing refetches
/// it on its own, but an invalidation or an explicit refetch still does —
/// which is what separates it from [StaleTimeStatic].
final class StaleTimeInfinite extends StaleTime {
  /// The one instance is [StaleTime.infinite]; a `const StaleTimeInfinite()`
  /// is the same value.
  const StaleTimeInfinite();
  @override
  bool operator ==(Object other) => other is StaleTimeInfinite;
  @override
  int get hashCode => (StaleTimeInfinite).hashCode;
  @override
  String toString() => 'StaleTime.infinite';
}

/// The [StaleTime.dynamic] variant: a stale time computed from the query each
/// time staleness is checked — upstream's `staleTime: (query) => …`.
final class StaleTimeDynamic extends StaleTime {
  /// Computes the stale time with [compute].
  const StaleTimeDynamic(this.compute);

  /// Given the query, the stale time to apply. May itself return another
  /// [StaleTime.dynamic]; [StaleTime.resolveFor] unwraps until it reaches a
  /// plain value.
  final StaleTime Function(Query<Object?> query) compute;

  @override
  bool operator ==(Object other) =>
      other is StaleTimeDynamic && other.compute == compute;
  @override
  int get hashCode => compute.hashCode;
  @override
  String toString() => 'StaleTime.dynamic($compute)';
}

/// How long unused data stays in the cache.
@immutable
sealed class GcTime {
  const GcTime();

  /// Removed from the cache [duration] after the last observer leaves —
  /// upstream's `gcTime: ms`.
  const factory GcTime.duration(Duration duration) = GcTimeDuration;

  /// Never collected.
  static const GcTime never = GcTimeNever();

  /// Upstream's default: five minutes.
  static const GcTime defaultValue = GcTimeDuration(Duration(minutes: 5));

  /// The longer of [a] and [b], with [GcTime.never] winning outright. Upstream
  /// applies the same rule when several observers ask for different times.
  static GcTime? longest(GcTime? a, GcTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    if (a is GcTimeNever || b is GcTimeNever) return GcTime.never;
    final durationA = (a as GcTimeDuration).duration;
    final durationB = (b as GcTimeDuration).duration;
    return durationA >= durationB ? a : b;
  }
}

/// The [GcTime.duration] variant: collected [duration] after the query lost
/// its last observer.
final class GcTimeDuration extends GcTime {
  /// Collected after [duration] unobserved.
  const GcTimeDuration(this.duration);

  /// How long an unobserved query stays cached.
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is GcTimeDuration && other.duration == duration;
  @override
  int get hashCode => duration.hashCode;
  @override
  String toString() => 'GcTime.duration($duration)';
}

/// The [GcTime.never] variant: an unobserved query stays cached until it is
/// removed by hand — upstream's `gcTime: Infinity`.
final class GcTimeNever extends GcTime {
  /// The one instance is [GcTime.never]; a `const GcTimeNever()` is the same
  /// value.
  const GcTimeNever();
  @override
  bool operator ==(Object other) => other is GcTimeNever;
  @override
  int get hashCode => (GcTimeNever).hashCode;
  @override
  String toString() => 'GcTime.never';
}

/// Whether a query may run at all.
@immutable
sealed class Enabled {
  const Enabled();

  /// The query fetches on its own: on mount, on every refetch trigger, and
  /// when invalidated. The default.
  static const Enabled yes = EnabledYes();

  /// The query never fetches on its own — upstream's `enabled: false`. It
  /// still serves cached data, and a `refetch()` still works.
  ///
  /// It is also this port's only spelling of upstream's `skipToken`
  /// (https://github.com/KoTTi97/flutter_query/issues/17), and `enabled:
  /// false` is the meaning that wins wherever upstream keeps the two apart.
  /// The one place that matters is [Query.isDisabled] with no observer
  /// attached: a cached query whose last observer left disabled is still
  /// refetched by `refetchQueries`/`invalidateQueries(refetchType: all)`,
  /// where upstream's `skipToken` would be skipped (pre-release review,
  /// 2026-09-12, F2).
  static const Enabled no = EnabledNo();

  /// Decided per query, each time it matters — upstream's
  /// `enabled: (query) => boolean`. A predicate that reads the query's state
  /// can, for instance, keep a query enabled only until it first succeeds.
  ///
  /// "Each time it matters" is often: seven calls for a single
  /// subscribe-and-fetch as this is written, and not a number to depend on.
  /// [predicate] must be cheap and free of side effects — it answers a
  /// question about the query, and anything else it does happens an
  /// unpredictable number of times (eighth review, 2026-09-10).
  const factory Enabled.when(bool Function(Query<Object?> query) predicate) =
      EnabledWhen;

  /// Whether [query] may fetch on its own right now.
  bool resolve(Query<Object?> query) => switch (this) {
        EnabledYes() => true,
        EnabledNo() => false,
        EnabledWhen(:final predicate) => predicate(query),
      };
}

/// The [Enabled.yes] variant.
final class EnabledYes extends Enabled {
  /// The one instance is [Enabled.yes]; a `const EnabledYes()` is the same
  /// value.
  const EnabledYes();
  @override
  bool operator ==(Object other) => other is EnabledYes;
  @override
  int get hashCode => (EnabledYes).hashCode;
  @override
  String toString() => 'Enabled.yes';
}

/// The [Enabled.no] variant.
final class EnabledNo extends Enabled {
  /// The one instance is [Enabled.no]; a `const EnabledNo()` is the same
  /// value.
  const EnabledNo();
  @override
  bool operator ==(Object other) => other is EnabledNo;
  @override
  int get hashCode => (EnabledNo).hashCode;
  @override
  String toString() => 'Enabled.no';
}

/// The [Enabled.when] variant.
final class EnabledWhen extends Enabled {
  /// Enabled while [predicate] says so.
  const EnabledWhen(this.predicate);

  /// Given the query, whether it may fetch on its own right now.
  final bool Function(Query<Object?> query) predicate;
  @override
  bool operator ==(Object other) =>
      other is EnabledWhen && other.predicate == predicate;
  @override
  int get hashCode => predicate.hashCode;
  @override
  String toString() => 'Enabled.when($predicate)';
}

/// Whether a failed attempt is retried.
@immutable
sealed class RetryPolicy {
  const RetryPolicy();

  /// Never retry: the first failure is the error — upstream's `retry: false`,
  /// and the default for mutations.
  static const RetryPolicy never = RetryNever();

  /// Retry forever — upstream's `retry: true`.
  static const RetryPolicy always = RetryAlways();

  /// Retry until [count] failures have happened — upstream's `retry: 3`, and
  /// `RetryPolicy.times(3)` is the default for queries: three retries after
  /// the first failure.
  const factory RetryPolicy.times(int count) = RetryTimes;

  /// Decided per failure — upstream's `retry: (failureCount, error) => …`.
  /// `failureCount` is how many attempts had already failed before the one
  /// being decided, so it is `0` on the first decision.
  const factory RetryPolicy.when(
    bool Function(int failureCount, Object error, StackTrace stackTrace)
        predicate,
  ) = RetryWhen;

  /// Whether to try again after an attempt threw [error], given that
  /// [failureCount] attempts had failed before it.
  bool shouldRetry(int failureCount, Object error, StackTrace stackTrace) =>
      switch (this) {
        RetryNever() => false,
        RetryAlways() => true,
        RetryTimes(:final count) => failureCount < count,
        RetryWhen(:final predicate) =>
          predicate(failureCount, error, stackTrace),
      };
}

/// The [RetryPolicy.never] variant.
final class RetryNever extends RetryPolicy {
  /// The one instance is [RetryPolicy.never]; a `const RetryNever()` is the
  /// same value.
  const RetryNever();
  @override
  bool operator ==(Object other) => other is RetryNever;
  @override
  int get hashCode => (RetryNever).hashCode;
  @override
  String toString() => 'RetryPolicy.never';
}

/// The [RetryPolicy.always] variant.
final class RetryAlways extends RetryPolicy {
  /// The one instance is [RetryPolicy.always]; a `const RetryAlways()` is the
  /// same value.
  const RetryAlways();
  @override
  bool operator ==(Object other) => other is RetryAlways;
  @override
  int get hashCode => (RetryAlways).hashCode;
  @override
  String toString() => 'RetryPolicy.always';
}

/// The [RetryPolicy.times] variant.
final class RetryTimes extends RetryPolicy {
  /// Retries until [count] attempts have failed.
  const RetryTimes(this.count);

  /// How many failures are tolerated before the fetch is an error. `0`
  /// behaves like [RetryPolicy.never] — the two are distinct values of a
  /// sealed type, so they are not `==`.
  final int count;
  @override
  bool operator ==(Object other) => other is RetryTimes && other.count == count;
  @override
  int get hashCode => count.hashCode;
  @override
  String toString() => 'RetryPolicy.times($count)';
}

/// The [RetryPolicy.when] variant.
final class RetryWhen extends RetryPolicy {
  /// Retries while [predicate] says so.
  const RetryWhen(this.predicate);

  /// Given how many attempts had failed before this one and what it threw,
  /// whether to try again.
  final bool Function(int failureCount, Object error, StackTrace stackTrace)
      predicate;
  @override
  bool operator ==(Object other) =>
      other is RetryWhen && other.predicate == predicate;
  @override
  int get hashCode => predicate.hashCode;
  @override
  String toString() => 'RetryPolicy.when($predicate)';
}

/// How long to wait before the next attempt.
@immutable
sealed class RetryDelay {
  const RetryDelay();

  /// The same wait before every retry — upstream's `retryDelay: ms`.
  const factory RetryDelay.fixed(Duration delay) = RetryDelayFixed;

  /// Upstream's default: `min(1000 * 2^attempt, 30s)`.
  static const RetryDelay defaultValue = RetryDelayExponential();

  /// Doubles from [base] on every failure and never exceeds [maximum]. With
  /// no arguments this is [defaultValue]: one second, two, four, … capped at
  /// thirty.
  const factory RetryDelay.exponential({
    Duration base,
    Duration maximum,
  }) = RetryDelayExponential;

  /// Computed per failure — upstream's `retryDelay: (attempt, error) => ms`.
  /// `failureCount` is how many attempts had failed before the one that just
  /// did, so it is `0` before the first retry. Named like
  /// [StaleTime.dynamic] and [RefetchInterval.dynamic], the other values
  /// computed on demand.
  const factory RetryDelay.dynamic(
    Duration Function(int failureCount, Object error) compute,
  ) = RetryDelayDynamic;

  /// The wait before the next attempt, after an attempt threw [error] with
  /// [failureCount] failures before it.
  Duration resolve(int failureCount, Object error) => switch (this) {
        RetryDelayFixed(:final delay) => delay,
        RetryDelayExponential(:final base, :final maximum) =>
          _exponential(base, maximum, failureCount),
        RetryDelayDynamic(:final compute) => compute(failureCount, error),
      };

  /// `min(base * 2^failureCount, maximum)`, without ever computing the
  /// power. `1 << failureCount` overflows a 64-bit int at 63 and a JavaScript
  /// int at 32, and the overflowed product clamped to *zero*, which turned a
  /// long-running `RetryPolicy.always` into a tight loop of instant retries.
  static Duration _exponential(Duration base, Duration maximum, int count) {
    final cap = maximum.inMicroseconds;
    var delay = base.inMicroseconds.clamp(0, cap);
    for (var i = 0; i < count && delay < cap; i++) {
      delay = (delay * 2).clamp(0, cap);
    }
    return Duration(microseconds: delay);
  }
}

/// The [RetryDelay.fixed] variant.
final class RetryDelayFixed extends RetryDelay {
  /// Waits [delay] before every retry.
  const RetryDelayFixed(this.delay);

  /// The wait between attempts.
  final Duration delay;
  @override
  bool operator ==(Object other) =>
      other is RetryDelayFixed && other.delay == delay;
  @override
  int get hashCode => delay.hashCode;
  @override
  String toString() => 'RetryDelay.fixed($delay)';
}

/// The [RetryDelay.exponential] variant: `min(base * 2^failureCount, maximum)`.
final class RetryDelayExponential extends RetryDelay {
  /// Defaults to upstream's numbers: one second, doubling, capped at thirty.
  const RetryDelayExponential({
    this.base = const Duration(seconds: 1),
    this.maximum = const Duration(seconds: 30),
  });

  /// The wait before the first retry; each failure doubles it. One second by
  /// default.
  final Duration base;

  /// The wait never exceeds this. Thirty seconds by default.
  final Duration maximum;
  @override
  bool operator ==(Object other) =>
      other is RetryDelayExponential &&
      other.base == base &&
      other.maximum == maximum;
  @override
  int get hashCode => Object.hash(base, maximum);
  @override
  String toString() => 'RetryDelay.exponential(base: $base, maximum: $maximum)';
}

/// The [RetryDelay.dynamic] variant.
final class RetryDelayDynamic extends RetryDelay {
  /// Computes every wait with [compute].
  const RetryDelayDynamic(this.compute);

  /// Given how many attempts had failed before the latest one and what it
  /// threw, how long to wait before trying again.
  final Duration Function(int failureCount, Object error) compute;
  @override
  bool operator ==(Object other) =>
      other is RetryDelayDynamic && other.compute == compute;
  @override
  int get hashCode => compute.hashCode;
  @override
  String toString() => 'RetryDelay.dynamic($compute)';
}

/// Whether an event (mount, focus, reconnect) triggers a refetch.
///
/// [ifStale] is upstream's `true`, which never said which of the two
/// behaviours it meant.
@immutable
sealed class RefetchOn {
  const RefetchOn();

  /// The event never triggers a refetch — upstream's `false`.
  static const RefetchOn never = RefetchOnNever();

  /// The event triggers a refetch only when the data is stale — upstream's
  /// `true`, and the default for mount, focus and reconnect.
  static const RefetchOn ifStale = RefetchOnIfStale();

  /// The event always triggers a refetch, fresh data or not — upstream's
  /// `'always'`.
  static const RefetchOn always = RefetchOnAlways();

  /// Decided per query when the event fires — upstream's
  /// `(query) => boolean | 'always'`.
  const factory RefetchOn.when(
    RefetchOn Function(Query<Object?> query) compute,
  ) = RefetchOnWhen;

  /// This with any [RefetchOn.when] layer peeled off for [query], so the
  /// result is [never], [ifStale] or [always].
  RefetchOn resolve(Query<Object?> query) => switch (this) {
        RefetchOnWhen(:final compute) => compute(query).resolve(query),
        _ => this,
      };
}

/// The [RefetchOn.never] variant.
final class RefetchOnNever extends RefetchOn {
  /// The one instance is [RefetchOn.never]; a `const RefetchOnNever()` is the
  /// same value.
  const RefetchOnNever();
  @override
  bool operator ==(Object other) => other is RefetchOnNever;
  @override
  int get hashCode => (RefetchOnNever).hashCode;
  @override
  String toString() => 'RefetchOn.never';
}

/// The [RefetchOn.ifStale] variant.
final class RefetchOnIfStale extends RefetchOn {
  /// The one instance is [RefetchOn.ifStale]; a `const RefetchOnIfStale()` is
  /// the same value.
  const RefetchOnIfStale();
  @override
  bool operator ==(Object other) => other is RefetchOnIfStale;
  @override
  int get hashCode => (RefetchOnIfStale).hashCode;
  @override
  String toString() => 'RefetchOn.ifStale';
}

/// The [RefetchOn.always] variant.
final class RefetchOnAlways extends RefetchOn {
  /// The one instance is [RefetchOn.always]; a `const RefetchOnAlways()` is
  /// the same value.
  const RefetchOnAlways();
  @override
  bool operator ==(Object other) => other is RefetchOnAlways;
  @override
  int get hashCode => (RefetchOnAlways).hashCode;
  @override
  String toString() => 'RefetchOn.always';
}

/// The [RefetchOn.when] variant.
final class RefetchOnWhen extends RefetchOn {
  /// Decides with [compute] each time the event fires.
  const RefetchOnWhen(this.compute);

  /// Given the query, whether the event should refetch it. May itself return
  /// another [RefetchOn.when]; [RefetchOn.resolve] unwraps until it reaches a
  /// plain value.
  final RefetchOn Function(Query<Object?> query) compute;
  @override
  bool operator ==(Object other) =>
      other is RefetchOnWhen && other.compute == compute;
  @override
  int get hashCode => compute.hashCode;
  @override
  String toString() => 'RefetchOn.when($compute)';
}

/// Polling.
@immutable
sealed class RefetchInterval {
  const RefetchInterval();

  /// No polling — upstream's `refetchInterval: false`, and the default.
  static const RefetchInterval off = RefetchIntervalOff();

  /// Refetches every [interval] for as long as an observer is subscribed —
  /// upstream's `refetchInterval: ms`.
  const factory RefetchInterval.every(Duration interval) = RefetchIntervalEvery;

  /// Computed from the query each time the observer re-arms its timer —
  /// upstream's `refetchInterval: (query) => ms | false`. Returning `null`
  /// stops polling, which is how a poll can end once the data says it is
  /// done.
  const factory RefetchInterval.dynamic(
    Duration? Function(Query<Object?> query) compute,
  ) = RefetchIntervalDynamic;

  /// The interval to poll [query] at; `null` means "do not poll".
  Duration? resolve(Query<Object?> query) => switch (this) {
        RefetchIntervalOff() => null,
        RefetchIntervalEvery(:final interval) => interval,
        RefetchIntervalDynamic(:final compute) => compute(query),
      };
}

/// The [RefetchInterval.off] variant.
final class RefetchIntervalOff extends RefetchInterval {
  /// The one instance is [RefetchInterval.off]; a `const RefetchIntervalOff()`
  /// is the same value.
  const RefetchIntervalOff();
  @override
  bool operator ==(Object other) => other is RefetchIntervalOff;
  @override
  int get hashCode => (RefetchIntervalOff).hashCode;
  @override
  String toString() => 'RefetchInterval.off';
}

/// The [RefetchInterval.every] variant.
final class RefetchIntervalEvery extends RefetchInterval {
  /// Polls every [interval].
  const RefetchIntervalEvery(this.interval);

  /// The time between one refetch starting and the next.
  final Duration interval;
  @override
  bool operator ==(Object other) =>
      other is RefetchIntervalEvery && other.interval == interval;
  @override
  int get hashCode => interval.hashCode;
  @override
  String toString() => 'RefetchInterval.every($interval)';
}

/// The [RefetchInterval.dynamic] variant.
final class RefetchIntervalDynamic extends RefetchInterval {
  /// Computes the interval with [compute].
  const RefetchIntervalDynamic(this.compute);

  /// Given the query, how often to poll it, or `null` to stop.
  final Duration? Function(Query<Object?> query) compute;
  @override
  bool operator ==(Object other) =>
      other is RefetchIntervalDynamic && other.compute == compute;
  @override
  int get hashCode => compute.hashCode;
  @override
  String toString() => 'RefetchInterval.dynamic($compute)';
}

/// How connectivity gates fetching. A closed set of constants, so a plain enum
/// rather than a sealed class.
enum NetworkMode {
  /// Only fetch while online; otherwise pause.
  online,

  /// Always fetch, connectivity be damned.
  always,

  /// Try once even when offline, then pause.
  offlineFirst,
}
