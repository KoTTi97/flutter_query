/// The sealed value types behind the union-typed options: [StaleTime],
/// [GcTime], [Enabled], [RetryPolicy], [RetryDelay], [RefetchOn],
/// [RefetchInterval] and [NetworkMode]. The user-facing rules are on each
/// type's own doc.
library;

import 'package:meta/meta.dart';

import 'query.dart';

/// How long fetched data counts as fresh — the `staleTime` option.
///
/// Fresh data is served from the cache without a fetch; stale data is still
/// served, but a refetch trigger (a new observer mounting, the app regaining
/// focus, the network coming back, an invalidation) fetches it again.
///
/// Like every option value in this package, a stale time is a `const`
/// sealed value rather than a number or a magic string. Dart has no union
/// types, so each option that TanStack Query types as `number | 'static' |
/// function` is a small sealed family here. An option field left `null`
/// means "not configured" and takes the client's default; "off" is always
/// a value of its own ([StaleTime.zero], [RetryPolicy.never],
/// [RefetchInterval.off]), never a `null`.
///
/// **Default:** [StaleTime.zero] — data is stale the moment it arrives.
///
/// The variants:
///
/// ```dart
/// staleTime: StaleTime.zero                                // the default
/// staleTime: const StaleTime.duration(Duration(minutes: 5)) // fresh 5 min
/// staleTime: StaleTime.infinite  // never stale by time; invalidation works
/// staleTime: StaleTime.static    // never stale, never refetched by triggers
/// staleTime: StaleTime.dynamic(
///   (query) => query.state.data == null
///       ? StaleTime.zero
///       : const StaleTime.duration(Duration(minutes: 1)),
/// )
/// ```
///
/// A switch over a resolved value covers [StaleTimeDuration],
/// [StaleTimeStatic], [StaleTimeInfinite] and [StaleTimeDynamic].
///
/// {@category Option values}
@immutable
sealed class StaleTime {
  const StaleTime();

  /// Fresh for [duration] after the fetch that produced the data
  /// (TanStack Query: `staleTime: ms`).
  const factory StaleTime.duration(Duration duration) = StaleTimeDuration;

  /// Stale the moment it arrives — the default (TanStack Query:
  /// `staleTime: 0`).
  static const StaleTime zero = StaleTimeDuration(Duration.zero);

  /// Never stale and, while an observer holds the query, never refetched by
  /// any trigger (TanStack Query: `staleTime: 'static'`).
  ///
  /// Even an explicit `refetchQueries` skips it; only an explicit
  /// `refetchInterval` and a `refetch()` on the observer still fetch. It is
  /// an observer's option: an entry nobody observes (one fetched by
  /// `QueryClient.query`, say) is an ordinary entry to `refetchQueries` and
  /// `invalidateQueries`, because whether a query is static is read from
  /// its observers.
  static const StaleTime static = StaleTimeStatic();

  /// Never stale by time, but still refetched when asked — by an
  /// invalidation or an explicit refetch (TanStack Query:
  /// `staleTime: Infinity`, which has no `Duration` equivalent).
  static const StaleTime infinite = StaleTimeInfinite();

  /// Computed per query, from its current state (TanStack Query:
  /// `staleTime: (query) => …`).
  ///
  /// Asked every time staleness is decided, which is several times per
  /// operation, and not a number worth relying on. Keep [compute] cheap and
  /// free of side effects; it is a question about the query, not a place to
  /// do work.
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
///
/// {@category Option values}
final class StaleTimeDuration extends StaleTime {
  /// Fresh for [duration]; prefer spelling it `StaleTime.duration(…)`.
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
/// mount, focus, reconnect, invalidation or `refetchQueries`.
///
/// With no observer, `refetchQueries` and `invalidateQueries` refetch it like
/// any other entry. Two things still fetch it: a `refetch()` on the observer
/// itself, and an explicit `refetchInterval`, which polls a static query
/// exactly as it polls any other — an interval is a request, not a trigger,
/// and TanStack Query polls it too. Only `refetchQueries` filters static
/// queries out.
///
/// {@category Option values}
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
///
/// {@category Option values}
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
/// time staleness is checked.
///
/// {@category Option values}
final class StaleTimeDynamic extends StaleTime {
  /// Computes the stale time with [compute]; prefer spelling it
  /// `StaleTime.dynamic(…)`.
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

/// How long a query nobody observes stays in the cache — the `gcTime`
/// option (the name is TanStack Query's: "garbage-collection time").
///
/// When a query's last observer leaves, a timer of this length starts; if no
/// observer comes back before it fires, the query and its data are removed
/// from the cache. The same option on a mutation governs how long a settled
/// mutation stays in the mutation cache. When several observers of one query
/// ask for different times, the longest wins ([GcTime.longest]).
///
/// **Default:** [GcTime.defaultValue], five minutes.
///
/// ```dart
/// gcTime: GcTime.defaultValue                               // 5 minutes
/// gcTime: const GcTime.duration(Duration(seconds: 30))
/// gcTime: const GcTime.duration(Duration.zero)  // drop as soon as unused
/// gcTime: GcTime.never          // keep until removed or the client clears
/// ```
///
/// {@category Option values}
@immutable
sealed class GcTime {
  const GcTime();

  /// Removed from the cache [duration] after the last observer leaves
  /// (TanStack Query: `gcTime: ms`).
  const factory GcTime.duration(Duration duration) = GcTimeDuration;

  /// Never collected: stays until removed by hand or the client is cleared
  /// (TanStack Query: `gcTime: Infinity`).
  static const GcTime never = GcTimeNever();

  /// The default: five minutes, the same as TanStack Query's.
  static const GcTime defaultValue = GcTimeDuration(Duration(minutes: 5));

  /// The longer of [a] and [b], with [GcTime.never] winning outright; a
  /// `null` (unset) loses to anything. This is how several observers asking
  /// for different times are reconciled, as in TanStack Query.
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
///
/// {@category Option values}
final class GcTimeDuration extends GcTime {
  /// Collected after [duration] unobserved; prefer spelling it
  /// `GcTime.duration(…)`.
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
/// removed by hand or the client is cleared.
///
/// {@category Option values}
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

/// Whether a query may fetch on its own — the `enabled` option.
///
/// A disabled query never fetches by itself: not when an observer mounts,
/// not on focus, reconnect, polling or invalidation. It still serves
/// whatever the cache holds, and an explicit `refetch()` on its observer
/// still fetches. Use it for dependent queries (wait until an id is known)
/// or to pause a query.
///
/// **Default:** [Enabled.yes].
///
/// ```dart
/// enabled: Enabled.yes                     // the default
/// enabled: Enabled.no                      // only an explicit refetch
/// enabled: userId == null ? Enabled.no : Enabled.yes   // dependent query
/// enabled: Enabled.when((query) => query.state.data == null) // until loaded
/// ```
///
/// {@category Option values}
@immutable
sealed class Enabled {
  const Enabled();

  /// The query fetches on its own: on mount, on every refetch trigger, and
  /// when invalidated. The default.
  static const Enabled yes = EnabledYes();

  /// The query never fetches on its own (TanStack Query: `enabled: false`).
  /// It still serves cached data, and a `refetch()` still works.
  ///
  /// This is also the spelling of TanStack Query's `skipToken`, which this
  /// package does not have separately; where TanStack Query treats the two
  /// differently, `enabled: false` is the behaviour you get. The one place
  /// that shows is [Query.isDisabled] with no observer attached: a cached
  /// query whose last observer left while disabled is still refetched by
  /// `refetchQueries` and by `invalidateQueries(refetchType: all)`, where a
  /// `skipToken` query would be skipped.
  static const Enabled no = EnabledNo();

  /// Decided per query, each time it matters (TanStack Query:
  /// `enabled: (query) => boolean`). A predicate that reads the query's
  /// state can, for instance, keep a query enabled only until it first
  /// succeeds.
  ///
  /// "Each time it matters" is often — several calls for a single
  /// subscribe-and-fetch, and not a number to depend on. [predicate] must
  /// be cheap and free of side effects: it answers a question about the
  /// query, and anything else it does happens an unpredictable number of
  /// times.
  const factory Enabled.when(bool Function(Query<Object?> query) predicate) =
      EnabledWhen;

  /// Whether [query] may fetch on its own right now.
  bool resolve(Query<Object?> query) => switch (this) {
        EnabledYes() => true,
        EnabledNo() => false,
        EnabledWhen(:final predicate) => predicate(query),
      };
}

/// The [Enabled.yes] variant: the query fetches on its own.
///
/// {@category Option values}
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

/// The [Enabled.no] variant: the query never fetches on its own, but serves
/// cached data and honours an explicit refetch.
///
/// {@category Option values}
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

/// The [Enabled.when] variant: enabled while [predicate] returns `true` for
/// the query.
///
/// {@category Option values}
final class EnabledWhen extends Enabled {
  /// Enabled while [predicate] says so; prefer spelling it
  /// `Enabled.when(…)`.
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

/// Whether a failed attempt is tried again — the `retry` option.
///
/// A query or mutation function that throws is retried according to this
/// policy, with [RetryDelay] deciding the wait in between. While retrying,
/// the result stays pending (or keeps its old data) and reports the failure
/// so far through `failureCount` and `failureReason`; only when the policy
/// gives up does the result become an error.
///
/// **Default:** [RetryPolicy.times] `(3)` for queries — three retries after
/// the first failure, four attempts in all — and [RetryPolicy.never] for
/// mutations.
///
/// ```dart
/// retry: RetryPolicy.never          // fail on the first error
/// retry: const RetryPolicy.times(5) // up to five retries
/// retry: RetryPolicy.always         // retry until it succeeds
/// retry: RetryPolicy.when(
///   (failureCount, error, stackTrace) =>
///       error is! NotFoundException && failureCount < 3,
/// )
/// ```
///
/// {@category Option values}
@immutable
sealed class RetryPolicy {
  const RetryPolicy();

  /// Never retry: the first failure is the error — the default for
  /// mutations (TanStack Query: `retry: false`).
  static const RetryPolicy never = RetryNever();

  /// Retry until an attempt succeeds, however often it fails (TanStack
  /// Query: `retry: true`).
  static const RetryPolicy always = RetryAlways();

  /// Retry until [count] failures have happened; `RetryPolicy.times(3)` is
  /// the default for queries: three retries after the first failure
  /// (TanStack Query: `retry: 3`).
  const factory RetryPolicy.times(int count) = RetryTimes;

  /// Decided per failure (TanStack Query: `retry: (failureCount, error) =>
  /// …`). `failureCount` is how many attempts had already failed before the
  /// one being decided, so it is `0` on the first decision.
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

/// The [RetryPolicy.never] variant: the first failure is final.
///
/// {@category Option values}
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

/// The [RetryPolicy.always] variant: retries until an attempt succeeds.
///
/// {@category Option values}
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

/// The [RetryPolicy.times] variant: retries until [count] attempts have
/// failed.
///
/// {@category Option values}
final class RetryTimes extends RetryPolicy {
  /// Retries until [count] attempts have failed; prefer spelling it
  /// `RetryPolicy.times(…)`.
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

/// The [RetryPolicy.when] variant: retries while [predicate] returns `true`.
///
/// {@category Option values}
final class RetryWhen extends RetryPolicy {
  /// Retries while [predicate] says so; prefer spelling it
  /// `RetryPolicy.when(…)`.
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

/// How long to wait before the next attempt after a failure — the
/// `retryDelay` option. Only consulted when [RetryPolicy] decided to retry.
///
/// **Default:** [RetryDelay.defaultValue]: one second, then two, four, …,
/// never more than thirty seconds (the same numbers as TanStack Query).
///
/// ```dart
/// retryDelay: RetryDelay.defaultValue            // 1s, 2s, 4s, … max 30s
/// retryDelay: const RetryDelay.fixed(Duration(seconds: 2))
/// retryDelay: const RetryDelay.exponential(
///   base: Duration(milliseconds: 200),
///   maximum: Duration(seconds: 5),
/// )
/// retryDelay: RetryDelay.dynamic(
///   (failureCount, error) => error is RateLimited
///       ? error.retryAfter
///       : const Duration(seconds: 1),
/// )
/// ```
///
/// {@category Option values}
@immutable
sealed class RetryDelay {
  const RetryDelay();

  /// The same wait before every retry (TanStack Query: `retryDelay: ms`).
  const factory RetryDelay.fixed(Duration delay) = RetryDelayFixed;

  /// The default: `min(1s * 2^failureCount, 30s)` — one second, two, four,
  /// … capped at thirty.
  static const RetryDelay defaultValue = RetryDelayExponential();

  /// Doubles from [base] on every failure and never exceeds [maximum]. With
  /// no arguments this is [defaultValue]: one second, two, four, … capped at
  /// thirty.
  const factory RetryDelay.exponential({
    Duration base,
    Duration maximum,
  }) = RetryDelayExponential;

  /// Computed per failure (TanStack Query: `retryDelay: (attempt, error) =>
  /// ms`). `failureCount` is how many attempts had failed before the one
  /// that just did, so it is `0` before the first retry. Named like
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

/// The [RetryDelay.fixed] variant: the same wait before every retry.
///
/// {@category Option values}
final class RetryDelayFixed extends RetryDelay {
  /// Waits [delay] before every retry; prefer spelling it
  /// `RetryDelay.fixed(…)`.
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

/// The [RetryDelay.exponential] variant: `min(base * 2^failureCount,
/// maximum)`.
///
/// {@category Option values}
final class RetryDelayExponential extends RetryDelay {
  /// One second, doubling, capped at thirty unless [base] or [maximum] say
  /// otherwise.
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

/// The [RetryDelay.dynamic] variant: every wait computed by a function of the
/// failure count and the error.
///
/// {@category Option values}
final class RetryDelayDynamic extends RetryDelay {
  /// Computes every wait with [compute]; prefer spelling it
  /// `RetryDelay.dynamic(…)`.
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

/// Whether an event refetches an observed query — the value of the
/// `refetchOnMount`, `refetchOnWindowFocus` and `refetchOnReconnect`
/// options.
///
/// The events are: an observer subscribing (mount), the app regaining focus
/// ([AppFocusManager]-driven), and the network coming back
/// ([OnlineManager]-driven). A disabled query is never refetched by any of
/// them.
///
/// **Default:** [RefetchOn.ifStale] for all three — except
/// `refetchOnReconnect` on a query whose `networkMode` is
/// [NetworkMode.always], which defaults to [RefetchOn.never] since such a
/// query never waited for the network in the first place.
///
/// TanStack Query spells this `true | false | 'always' | (query) => …`;
/// [ifStale] is its `true`, named for what it does.
///
/// ```dart
/// refetchOnWindowFocus: RefetchOn.never
/// refetchOnMount: RefetchOn.always   // even if the data is fresh
/// refetchOnReconnect: RefetchOn.ifStale  // the default
/// refetchOnWindowFocus: RefetchOn.when(
///   (query) => query.state.error != null ? RefetchOn.always : RefetchOn.never,
/// )
/// ```
///
/// {@category Option values}
@immutable
sealed class RefetchOn {
  const RefetchOn();

  /// The event never triggers a refetch (TanStack Query: `false`).
  static const RefetchOn never = RefetchOnNever();

  /// The event triggers a refetch only when the data is stale — the default
  /// for mount, focus and reconnect (TanStack Query: `true`).
  static const RefetchOn ifStale = RefetchOnIfStale();

  /// The event always triggers a refetch, fresh data or not (TanStack
  /// Query: `'always'`).
  static const RefetchOn always = RefetchOnAlways();

  /// Decided per query when the event fires (TanStack Query:
  /// `(query) => boolean | 'always'`).
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

/// The [RefetchOn.never] variant: the event never refetches.
///
/// {@category Option values}
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

/// The [RefetchOn.ifStale] variant: the event refetches stale data only.
///
/// {@category Option values}
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

/// The [RefetchOn.always] variant: the event refetches, fresh data or not.
///
/// {@category Option values}
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

/// The [RefetchOn.when] variant: the answer is computed per query each time
/// the event fires.
///
/// {@category Option values}
final class RefetchOnWhen extends RefetchOn {
  /// Decides with [compute] each time the event fires; prefer spelling it
  /// `RefetchOn.when(…)`.
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

/// Polling — the `refetchInterval` option.
///
/// While at least one observer with an interval is subscribed, the query is
/// refetched on that interval, whether its data is stale or not. Polling
/// pauses while the app is in the background unless
/// `refetchIntervalInBackground` is set, and stops when the last polling
/// observer unsubscribes. An interval polls even a [StaleTime.static] query.
///
/// **Default:** [RefetchInterval.off].
///
/// ```dart
/// refetchInterval: RefetchInterval.off     // the default
/// refetchInterval: const RefetchInterval.every(Duration(seconds: 10))
/// // Poll a job until it is done, then stop:
/// refetchInterval: RefetchInterval.dynamic(
///   (query) => query.state.data == 'done' ? null : const Duration(seconds: 2),
/// )
/// ```
///
/// {@category Option values}
@immutable
sealed class RefetchInterval {
  const RefetchInterval();

  /// No polling — the default (TanStack Query: `refetchInterval: false`).
  static const RefetchInterval off = RefetchIntervalOff();

  /// Refetches every [interval] for as long as an observer is subscribed
  /// (TanStack Query: `refetchInterval: ms`).
  const factory RefetchInterval.every(Duration interval) = RefetchIntervalEvery;

  /// Computed from the query each time the observer re-arms its timer
  /// (TanStack Query: `refetchInterval: (query) => ms | false`). Returning
  /// `null` stops polling, which is how a poll can end once the data says it
  /// is done.
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

/// The [RefetchInterval.off] variant: no polling.
///
/// {@category Option values}
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

/// The [RefetchInterval.every] variant: polls at a fixed interval.
///
/// {@category Option values}
final class RefetchIntervalEvery extends RefetchInterval {
  /// Polls every [interval]; prefer spelling it `RefetchInterval.every(…)`.
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

/// The [RefetchInterval.dynamic] variant: the interval is computed from the
/// query each time the timer is re-armed, and `null` stops polling.
///
/// {@category Option values}
final class RefetchIntervalDynamic extends RefetchInterval {
  /// Computes the interval with [compute]; prefer spelling it
  /// `RefetchInterval.dynamic(…)`.
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

/// How connectivity gates fetching — the `networkMode` option, for queries
/// and mutations alike. Connectivity comes from the client's
/// [OnlineManager].
///
/// **Default:** [NetworkMode.online].
///
/// A closed set of constants, so a plain enum rather than a sealed class:
///
/// ```dart
/// networkMode: NetworkMode.online        // the default
/// networkMode: NetworkMode.always        // e.g. a local database
/// networkMode: NetworkMode.offlineFirst  // e.g. a service-worker cache
/// ```
///
/// {@category Option values}
enum NetworkMode {
  /// Only fetch while online. Offline, a fetch does not start: the query
  /// stays pending (or keeps its data) with `fetchStatus` paused, and
  /// continues when the network comes back. Retries pause the same way.
  online,

  /// Ignore connectivity entirely: always fetch, never pause for the
  /// network. For work that does not need one, such as reading a local
  /// store.
  always,

  /// Try the first attempt even when offline, then pause any retry until
  /// the network comes back. For a query function that may be answered by
  /// a cache of its own.
  offlineFirst,
}
