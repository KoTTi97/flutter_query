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

  /// Never stale and never refetched in the background — upstream's
  /// `staleTime: 'static'`. Even an explicit `refetchQueries` skips it.
  static const StaleTime static = StaleTimeStatic();

  /// Never stale by time, but still refetched when asked — upstream's
  /// `staleTime: Infinity`, which Dart has no `Duration` for.
  static const StaleTime infinite = StaleTimeInfinite();

  /// Computed per query, from its current state.
  const factory StaleTime.dynamic(
      StaleTime Function(Query<Object?> query) compute) = StaleTimeDynamic;

  /// Resolves this to a plain duration for [query]. `null` means "never
  /// stale".
  Duration? resolve(Query<Object?> query) => switch (this) {
        StaleTimeDuration(:final duration) => duration,
        StaleTimeStatic() => null,
        StaleTimeInfinite() => null,
        StaleTimeDynamic(:final compute) => compute(query).resolve(query),
      };

  /// Whether this resolves to [StaleTime.static] for [query] — the one thing
  /// that separates it from [StaleTime.infinite]: a static query is skipped by
  /// `refetchQueries` and by every refetch trigger.
  bool isStaticFor(Query<Object?> query) => switch (this) {
        StaleTimeStatic() => true,
        StaleTimeDynamic(:final compute) => compute(query).isStaticFor(query),
        _ => false,
      };
}

final class StaleTimeDuration extends StaleTime {
  const StaleTimeDuration(this.duration);
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is StaleTimeDuration && other.duration == duration;
  @override
  int get hashCode => duration.hashCode;
}

final class StaleTimeStatic extends StaleTime {
  const StaleTimeStatic();
  @override
  bool operator ==(Object other) => other is StaleTimeStatic;
  @override
  int get hashCode => (StaleTimeStatic).hashCode;
}

final class StaleTimeInfinite extends StaleTime {
  const StaleTimeInfinite();
  @override
  bool operator ==(Object other) => other is StaleTimeInfinite;
  @override
  int get hashCode => (StaleTimeInfinite).hashCode;
}

final class StaleTimeDynamic extends StaleTime {
  const StaleTimeDynamic(this.compute);
  final StaleTime Function(Query<Object?> query) compute;

  @override
  bool operator ==(Object other) =>
      other is StaleTimeDynamic && other.compute == compute;
  @override
  int get hashCode => compute.hashCode;
}

/// How long unused data stays in the cache.
@immutable
sealed class GcTime {
  const GcTime();

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

final class GcTimeDuration extends GcTime {
  const GcTimeDuration(this.duration);
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is GcTimeDuration && other.duration == duration;
  @override
  int get hashCode => duration.hashCode;
}

final class GcTimeNever extends GcTime {
  const GcTimeNever();
  @override
  bool operator ==(Object other) => other is GcTimeNever;
  @override
  int get hashCode => (GcTimeNever).hashCode;
}

/// Whether a query may run at all.
@immutable
sealed class Enabled {
  const Enabled();

  static const Enabled yes = EnabledYes();
  static const Enabled no = EnabledNo();

  const factory Enabled.when(bool Function(Query<Object?> query) predicate) =
      EnabledWhen;

  bool resolve(Query<Object?> query) => switch (this) {
        EnabledYes() => true,
        EnabledNo() => false,
        EnabledWhen(:final predicate) => predicate(query),
      };
}

final class EnabledYes extends Enabled {
  const EnabledYes();
  @override
  bool operator ==(Object other) => other is EnabledYes;
  @override
  int get hashCode => (EnabledYes).hashCode;
}

final class EnabledNo extends Enabled {
  const EnabledNo();
  @override
  bool operator ==(Object other) => other is EnabledNo;
  @override
  int get hashCode => (EnabledNo).hashCode;
}

final class EnabledWhen extends Enabled {
  const EnabledWhen(this.predicate);
  final bool Function(Query<Object?> query) predicate;
  @override
  bool operator ==(Object other) =>
      other is EnabledWhen && other.predicate == predicate;
  @override
  int get hashCode => predicate.hashCode;
}

/// Whether a failed attempt is retried.
@immutable
sealed class RetryPolicy {
  const RetryPolicy();

  static const RetryPolicy never = RetryNever();

  /// RetryPolicy forever.
  static const RetryPolicy always = RetryAlways();

  /// RetryPolicy until [count] failures have happened — upstream's `retry: 3`.
  const factory RetryPolicy.times(int count) = RetryTimes;

  const factory RetryPolicy.when(
    bool Function(int failureCount, Object error, StackTrace stackTrace)
        predicate,
  ) = RetryWhen;

  bool shouldRetry(int failureCount, Object error, StackTrace stackTrace) =>
      switch (this) {
        RetryNever() => false,
        RetryAlways() => true,
        RetryTimes(:final count) => failureCount < count,
        RetryWhen(:final predicate) =>
          predicate(failureCount, error, stackTrace),
      };
}

final class RetryNever extends RetryPolicy {
  const RetryNever();
  @override
  bool operator ==(Object other) => other is RetryNever;
  @override
  int get hashCode => (RetryNever).hashCode;
}

final class RetryAlways extends RetryPolicy {
  const RetryAlways();
  @override
  bool operator ==(Object other) => other is RetryAlways;
  @override
  int get hashCode => (RetryAlways).hashCode;
}

final class RetryTimes extends RetryPolicy {
  const RetryTimes(this.count);
  final int count;
  @override
  bool operator ==(Object other) => other is RetryTimes && other.count == count;
  @override
  int get hashCode => count.hashCode;
}

final class RetryWhen extends RetryPolicy {
  const RetryWhen(this.predicate);
  final bool Function(int failureCount, Object error, StackTrace stackTrace)
      predicate;
  @override
  bool operator ==(Object other) =>
      other is RetryWhen && other.predicate == predicate;
  @override
  int get hashCode => predicate.hashCode;
}

/// How long to wait before the next attempt.
@immutable
sealed class RetryDelay {
  const RetryDelay();

  const factory RetryDelay.fixed(Duration delay) = RetryDelayFixed;

  /// Upstream's default: `min(1000 * 2^attempt, 30s)`.
  static const RetryDelay defaultValue = RetryDelayExponential();

  const factory RetryDelay.exponential({
    Duration base,
    Duration maximum,
  }) = RetryDelayExponential;

  const factory RetryDelay.custom(
    Duration Function(int failureCount, Object error) compute,
  ) = RetryDelayCustom;

  Duration resolve(int failureCount, Object error) => switch (this) {
        RetryDelayFixed(:final delay) => delay,
        RetryDelayExponential(:final base, :final maximum) => Duration(
            microseconds: (base.inMicroseconds * (1 << failureCount)).clamp(
              0,
              maximum.inMicroseconds,
            ),
          ),
        RetryDelayCustom(:final compute) => compute(failureCount, error),
      };
}

final class RetryDelayFixed extends RetryDelay {
  const RetryDelayFixed(this.delay);
  final Duration delay;
  @override
  bool operator ==(Object other) =>
      other is RetryDelayFixed && other.delay == delay;
  @override
  int get hashCode => delay.hashCode;
}

final class RetryDelayExponential extends RetryDelay {
  const RetryDelayExponential({
    this.base = const Duration(seconds: 1),
    this.maximum = const Duration(seconds: 30),
  });
  final Duration base;
  final Duration maximum;
  @override
  bool operator ==(Object other) =>
      other is RetryDelayExponential &&
      other.base == base &&
      other.maximum == maximum;
  @override
  int get hashCode => Object.hash(base, maximum);
}

final class RetryDelayCustom extends RetryDelay {
  const RetryDelayCustom(this.compute);
  final Duration Function(int failureCount, Object error) compute;
  @override
  bool operator ==(Object other) =>
      other is RetryDelayCustom && other.compute == compute;
  @override
  int get hashCode => compute.hashCode;
}

/// Whether an event (mount, focus, reconnect) triggers a refetch.
///
/// [ifStale] is upstream's `true`, which never said which of the two
/// behaviours it meant.
@immutable
sealed class RefetchOn {
  const RefetchOn();

  static const RefetchOn never = RefetchOnNever();
  static const RefetchOn ifStale = RefetchOnIfStale();
  static const RefetchOn always = RefetchOnAlways();

  const factory RefetchOn.when(
    RefetchOn Function(Query<Object?> query) compute,
  ) = RefetchOnWhen;

  RefetchOn resolve(Query<Object?> query) => switch (this) {
        RefetchOnWhen(:final compute) => compute(query).resolve(query),
        _ => this,
      };
}

final class RefetchOnNever extends RefetchOn {
  const RefetchOnNever();
  @override
  bool operator ==(Object other) => other is RefetchOnNever;
  @override
  int get hashCode => (RefetchOnNever).hashCode;
}

final class RefetchOnIfStale extends RefetchOn {
  const RefetchOnIfStale();
  @override
  bool operator ==(Object other) => other is RefetchOnIfStale;
  @override
  int get hashCode => (RefetchOnIfStale).hashCode;
}

final class RefetchOnAlways extends RefetchOn {
  const RefetchOnAlways();
  @override
  bool operator ==(Object other) => other is RefetchOnAlways;
  @override
  int get hashCode => (RefetchOnAlways).hashCode;
}

final class RefetchOnWhen extends RefetchOn {
  const RefetchOnWhen(this.compute);
  final RefetchOn Function(Query<Object?> query) compute;
  @override
  bool operator ==(Object other) =>
      other is RefetchOnWhen && other.compute == compute;
  @override
  int get hashCode => compute.hashCode;
}

/// Polling.
@immutable
sealed class RefetchInterval {
  const RefetchInterval();

  static const RefetchInterval off = RefetchIntervalOff();

  const factory RefetchInterval.every(Duration interval) = RefetchIntervalEvery;

  const factory RefetchInterval.dynamic(
    Duration? Function(Query<Object?> query) compute,
  ) = RefetchIntervalDynamic;

  /// `null` means "do not poll".
  Duration? resolve(Query<Object?> query) => switch (this) {
        RefetchIntervalOff() => null,
        RefetchIntervalEvery(:final interval) => interval,
        RefetchIntervalDynamic(:final compute) => compute(query),
      };
}

final class RefetchIntervalOff extends RefetchInterval {
  const RefetchIntervalOff();
  @override
  bool operator ==(Object other) => other is RefetchIntervalOff;
  @override
  int get hashCode => (RefetchIntervalOff).hashCode;
}

final class RefetchIntervalEvery extends RefetchInterval {
  const RefetchIntervalEvery(this.interval);
  final Duration interval;
  @override
  bool operator ==(Object other) =>
      other is RefetchIntervalEvery && other.interval == interval;
  @override
  int get hashCode => interval.hashCode;
}

final class RefetchIntervalDynamic extends RefetchInterval {
  const RefetchIntervalDynamic(this.compute);
  final Duration? Function(Query<Object?> query) compute;
  @override
  bool operator ==(Object other) =>
      other is RefetchIntervalDynamic && other.compute == compute;
  @override
  int get hashCode => compute.hashCode;
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
