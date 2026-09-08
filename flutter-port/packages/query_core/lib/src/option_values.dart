import 'package:meta/meta.dart';

/// How fetching behaves with respect to connectivity.
enum NetworkMode {
  /// Only fetch while online; otherwise pause. The default.
  online,

  /// Always fetch, connectivity notwithstanding.
  always,

  /// Try once even when offline, then pause on failure.
  offlineFirst,
}

/// Whether a query has data, failed, or has neither yet.
enum QueryStatus { pending, success, error }

/// What a query is doing right now — orthogonal to [QueryStatus].
enum FetchStatus { fetching, paused, idle }

/// How long fetched data counts as fresh.
///
/// Upstream overloads a number with the magic string `'static'` and `Infinity`;
/// here each meaning is its own variant.
@immutable
sealed class StaleDuration {
  const StaleDuration();

  /// Immediately stale. The default.
  static const StaleDuration zero = StaleDurationValue(Duration.zero);

  /// Fresh for [duration].
  const factory StaleDuration.of(Duration duration) = StaleDurationValue;

  /// Never becomes stale on its own, but still refetches on invalidation.
  static const StaleDuration infinity = StaleDurationInfinity._();

  /// Never stale and never refetched in the background — not even on
  /// invalidation, focus or reconnect.
  static const StaleDuration static_ = StaleDurationStatic._();

  /// Computed per query, re-evaluated whenever staleness is checked.
  const factory StaleDuration.resolve(
    StaleDuration Function(Object query) compute,
  ) = StaleDurationResolver;

  /// Collapses a [StaleDuration.resolve] against [query]; other variants
  /// return themselves.
  StaleDuration resolveWith(Object query) => this;
}

final class StaleDurationValue extends StaleDuration {
  const StaleDurationValue(this.duration);

  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is StaleDurationValue && other.duration == duration;

  @override
  int get hashCode => duration.hashCode;
}

final class StaleDurationInfinity extends StaleDuration {
  const StaleDurationInfinity._();
}

final class StaleDurationStatic extends StaleDuration {
  const StaleDurationStatic._();
}

final class StaleDurationResolver extends StaleDuration {
  const StaleDurationResolver(this.compute);

  final StaleDuration Function(Object query) compute;

  @override
  StaleDuration resolveWith(Object query) => compute(query).resolveWith(query);
}

/// How long an unused cache entry is kept before collection.
@immutable
sealed class GcDuration {
  const GcDuration();

  /// Collect [duration] after the last observer leaves.
  const factory GcDuration.of(Duration duration) = GcDurationValue;

  /// Never collect. Replaces upstream's `Infinity`.
  static const GcDuration never = GcDurationNever._();

  /// The longer of the two — garbage-collection time only ever grows, so a
  /// second observer asking for a longer lifetime wins (upstream behavior).
  GcDuration max(GcDuration other) {
    if (this is GcDurationNever || other is GcDurationNever) {
      return never;
    }
    final a = (this as GcDurationValue).duration;
    final b = (other as GcDurationValue).duration;
    return GcDuration.of(a >= b ? a : b);
  }
}

final class GcDurationValue extends GcDuration {
  const GcDurationValue(this.duration);

  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is GcDurationValue && other.duration == duration;

  @override
  int get hashCode => duration.hashCode;
}

final class GcDurationNever extends GcDuration {
  const GcDurationNever._();
}

/// Whether a query may run. Replaces upstream's `skipToken`: a query that
/// should not run is simply not enabled.
@immutable
sealed class Enabled {
  const Enabled._();

  const factory Enabled(bool value) = EnabledValue;

  static const Enabled on = EnabledValue(true);
  static const Enabled off = EnabledValue(false);

  /// Computed per query, re-evaluated on each check.
  const factory Enabled.resolve(bool Function(Object query) compute) =
      EnabledResolver;

  bool resolveWith(Object query);
}

final class EnabledValue extends Enabled {
  const EnabledValue(this.value) : super._();

  final bool value;

  @override
  bool resolveWith(Object query) => value;

  @override
  bool operator ==(Object other) =>
      other is EnabledValue && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class EnabledResolver extends Enabled {
  const EnabledResolver(this.compute) : super._();

  final bool Function(Object query) compute;

  @override
  bool resolveWith(Object query) => compute(query);
}

/// Whether a failed fetch is retried, and how often.
@immutable
sealed class RetryOption {
  const RetryOption();

  /// No retries. The default for mutations.
  static const RetryOption never = RetryCount(0);

  /// Retry until it succeeds.
  static const RetryOption forever = RetryForever._();

  /// Retry up to [count] times. The default for queries is three.
  const factory RetryOption.count(int count) = RetryCount;

  /// Decide per failure.
  const factory RetryOption.when(
    bool Function(int failureCount, Object error) shouldRetry,
  ) = RetryWhen;

  bool shouldRetry(int failureCount, Object error);
}

final class RetryCount extends RetryOption {
  const RetryCount(this.count);

  final int count;

  @override
  bool shouldRetry(int failureCount, Object error) => failureCount < count;

  @override
  bool operator ==(Object other) => other is RetryCount && other.count == count;

  @override
  int get hashCode => count.hashCode;
}

final class RetryForever extends RetryOption {
  const RetryForever._();

  @override
  bool shouldRetry(int failureCount, Object error) => true;
}

final class RetryWhen extends RetryOption {
  const RetryWhen(this._shouldRetry);

  final bool Function(int failureCount, Object error) _shouldRetry;

  @override
  bool shouldRetry(int failureCount, Object error) =>
      _shouldRetry(failureCount, error);
}

/// How long to wait before the next retry.
@immutable
sealed class RetryDelay {
  const RetryDelay();

  const factory RetryDelay.of(Duration duration) = RetryDelayValue;

  const factory RetryDelay.compute(
    Duration Function(int failureCount, Object error) compute,
  ) = RetryDelayComputed;

  /// Doubling backoff from 1s, capped at 30s — upstream's default.
  static const RetryDelay exponential = RetryDelayExponential._();

  Duration delayFor(int failureCount, Object error);
}

final class RetryDelayValue extends RetryDelay {
  const RetryDelayValue(this.duration);

  final Duration duration;

  @override
  Duration delayFor(int failureCount, Object error) => duration;

  @override
  bool operator ==(Object other) =>
      other is RetryDelayValue && other.duration == duration;

  @override
  int get hashCode => duration.hashCode;
}

final class RetryDelayComputed extends RetryDelay {
  const RetryDelayComputed(this.compute);

  final Duration Function(int failureCount, Object error) compute;

  @override
  Duration delayFor(int failureCount, Object error) =>
      compute(failureCount, error);
}

final class RetryDelayExponential extends RetryDelay {
  const RetryDelayExponential._();

  static const Duration _cap = Duration(seconds: 30);

  @override
  Duration delayFor(int failureCount, Object error) {
    final millis = 1000 * (1 << failureCount.clamp(0, 30));
    final delay = Duration(milliseconds: millis);
    return delay > _cap ? _cap : delay;
  }
}

/// Whether to refetch on a given trigger (mount, app focus, reconnect).
@immutable
sealed class RefetchOn {
  const RefetchOn();

  /// Never refetch on this trigger.
  static const RefetchOn never = RefetchOnNever._();

  /// Refetch only when the data is stale. The default.
  static const RefetchOn ifStale = RefetchOnIfStale._();

  /// Refetch every time, stale or not.
  static const RefetchOn always = RefetchOnAlways._();

  /// Decide per query.
  const factory RefetchOn.resolve(RefetchOn Function(Object query) compute) =
      RefetchOnResolver;

  RefetchOn resolveWith(Object query) => this;
}

final class RefetchOnNever extends RefetchOn {
  const RefetchOnNever._();
}

final class RefetchOnIfStale extends RefetchOn {
  const RefetchOnIfStale._();
}

final class RefetchOnAlways extends RefetchOn {
  const RefetchOnAlways._();
}

final class RefetchOnResolver extends RefetchOn {
  const RefetchOnResolver(this.compute);

  final RefetchOn Function(Object query) compute;

  @override
  RefetchOn resolveWith(Object query) => compute(query).resolveWith(query);
}

/// Polling interval.
@immutable
sealed class RefetchInterval {
  const RefetchInterval();

  /// No polling. The default.
  static const RefetchInterval off = RefetchIntervalOff._();

  /// Poll every [duration].
  const factory RefetchInterval.every(Duration duration) = RefetchIntervalValue;

  /// Poll on a schedule computed from the query — returning null stops it.
  /// This is how a confirmation loop runs only while a write is outstanding.
  const factory RefetchInterval.resolve(
    Duration? Function(Object query) compute,
  ) = RefetchIntervalResolver;

  Duration? resolveWith(Object query);
}

final class RefetchIntervalOff extends RefetchInterval {
  const RefetchIntervalOff._();

  @override
  Duration? resolveWith(Object query) => null;
}

final class RefetchIntervalValue extends RefetchInterval {
  const RefetchIntervalValue(this.duration);

  final Duration duration;

  @override
  Duration? resolveWith(Object query) => duration;

  @override
  bool operator ==(Object other) =>
      other is RefetchIntervalValue && other.duration == duration;

  @override
  int get hashCode => duration.hashCode;
}

final class RefetchIntervalResolver extends RefetchInterval {
  const RefetchIntervalResolver(this.compute);

  final Duration? Function(Object query) compute;

  @override
  Duration? resolveWith(Object query) => compute(query);
}
