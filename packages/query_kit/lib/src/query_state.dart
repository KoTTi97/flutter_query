/// The state a query holds — `QueryState` — and its two status enums.
library;

import 'package:meta/meta.dart';

/// What a query *holds*: nothing yet, data, or an error.
///
/// Independent of [FetchStatus], which is what the query is *doing*: a
/// query can hold data and be fetching a newer copy at the same time. A
/// `QueryResult` turns this enum into its sealed variants.
///
/// {@category Queries}
enum QueryStatus {
  /// Nothing has resolved: no data and no error. The state before the first
  /// fetch settles, unless `initialData` seeded the query.
  pending,

  /// The query holds data, fetched or seeded; [QueryState.data] is
  /// meaningful.
  success,

  /// The last fetch failed and its retries are spent; [QueryState.error] says
  /// why. Data from an earlier success is kept alongside.
  error,
}

/// What a query is doing right now: fetching, paused, or nothing.
///
/// Independent of [QueryStatus]: a query that holds data can be `fetching`
/// (a background refresh), and a pending one can be `idle` (disabled, or
/// not observed yet).
///
/// {@category Queries}
enum FetchStatus {
  /// A fetch is in flight.
  fetching,

  /// A fetch wants to run but cannot: the device is offline and the query's
  /// [NetworkMode] says to wait, or a retry is waiting for the app to return
  /// to the foreground.
  paused,

  /// Nothing is happening.
  idle,
}

/// Everything a query holds at one point in time: its data or error, its
/// [status] and [fetchStatus], and the counters and timestamps behind them.
///
/// Read it from `Query.state` — in a cache listener, a `QueryFilters`
/// predicate, or a `RefetchInterval.dynamic` or `StaleTime.dynamic`
/// callback. Widgets usually read a `QueryResult` instead, which an observer
/// derives from this state.
///
/// The class is flat and immutable rather than sealed: [status] and
/// [fetchStatus] vary independently, and the counters survive every
/// transition, so one class with all fields fits better than a variant per
/// combination. The sealed view is `QueryResult`.
///
/// [hasData] says whether [data] is meaningful. `hasData == false` means
/// nothing has ever resolved; `hasData == true` with a `null` [data] means
/// the query resolved to `null` on purpose, which a query with a nullable
/// data type can do.
///
/// It is publicly constructible so that a persistence layer can restore a
/// saved entry: hand a state to `QueryCache.build` for a new entry, or to
/// `Query.setState` for an existing one. A `success` state must have
/// [hasData] set, or it is rejected with an [ArgumentError].
///
/// {@category Queries}
@immutable
final class QueryState<TQueryData> {
  /// Validates a state before a query, cache build or state replacement accepts
  /// it. Presence flags must agree with both success and the payload's type.
  ///
  /// A `success` state must have [hasData], whatever `TQueryData` is — `void`
  /// and nullable types included. To restore a query that resolved to
  /// nothing, write `hasData: true` with `data: null`. A query's data is read
  /// through `select` into an observer's own data type, which may be
  /// non-nullable: a data-less success skips the selector, and `null` cast to
  /// a `String` selection would throw in the observer's constructor, so such
  /// a state is refused even for a nullable `TQueryData`. The mutation twin
  /// keeps the looser rule, because nothing projects a mutation's data into
  /// another type; see `MutationState.validate`.
  @internal
  void validate() {
    if ((status == QueryStatus.success && !hasData) ||
        (hasData && data is! TQueryData)) {
      throw ArgumentError.value(this, 'state',
          'A successful QueryState must hold data compatible with $TQueryData.');
    }
  }

  /// The initial state unless told otherwise: pending, idle, no data, every
  /// counter at zero. Each argument is the field of the same name.
  const QueryState({
    this.hasData = false,
    this.data,
    this.dataUpdateCount = 0,
    this.dataUpdatedAt,
    this.error,
    this.errorStackTrace,
    this.errorUpdateCount = 0,
    this.consecutiveErrorCount = 0,
    this.errorUpdatedAt,
    this.fetchFailureCount = 0,
    this.fetchFailureReason,
    this.fetchFailureStackTrace,
    this.fetchMeta,
    this.isInvalidated = false,
    this.status = QueryStatus.pending,
    this.fetchStatus = FetchStatus.idle,
  });

  /// Whether [data] is meaningful: true once the query has resolved to data
  /// (fetched, seeded or written by hand), even when that data is `null`.
  /// False before anything has resolved; stays true through a later error.
  /// Defaults to `false`.
  final bool hasData;

  /// The cached data. Meaningful only while [hasData] is true.
  final TQueryData? data;

  /// How many times data has been written, by fetches and `setQueryData`
  /// alike. Defaults to zero.
  final int dataUpdateCount;

  /// When [data] was last written, which is what `staleTime` counts from.
  /// `null` until the first write.
  final DateTime? dataUpdatedAt;

  /// Why the last fetch failed, if it did. Cleared by the next success; a
  /// query that has data keeps it alongside the error.
  final Object? error;

  /// The stack trace of the fetch that failed with [error]; `null` whenever
  /// [error] is.
  final StackTrace? errorStackTrace;

  /// How many times the query has ended in an error over its whole life. It
  /// never goes down; [consecutiveErrorCount] counts failures in a row.
  final int errorUpdateCount;

  /// How many fetches in a row have ended in an error: one more with every
  /// failed fetch — its retries exhausted — and back to zero with the next
  /// data that is *fetched*. A manual write (`setQueryData`, an optimistic
  /// patch) leaves it alone, and so does a cancelled fetch: neither says
  /// anything about whether the source answers.
  ///
  /// It counts whole fetches, where [fetchFailureCount] counts the attempts
  /// inside one fetch and starts over with every new fetch, and
  /// [errorUpdateCount] never goes down at all. So "stop polling after five
  /// failed fetches in a row" reads this count:
  ///
  /// ```dart
  /// refetchInterval: RefetchInterval.dynamic((query) =>
  ///     query.state.consecutiveErrorCount >= 5
  ///         ? null
  ///         : const Duration(seconds: 30)),
  /// ```
  ///
  /// Every observer's result carries it too, as
  /// `QueryResult.consecutiveErrorCount`. TanStack Query has no such field.
  final int consecutiveErrorCount;

  /// When the query last ended in an error. Not cleared with [error], so
  /// "last failed at" survives the refetch that follows.
  final DateTime? errorUpdatedAt;

  /// Failed attempts inside the *current* fetch, reset when a new one starts.
  /// A query retrying in the background reports progress here without
  /// changing [status].
  final int fetchFailureCount;

  /// What the latest failed attempt of the current fetch threw; `null` once
  /// an attempt succeeds or a new fetch starts.
  final Object? fetchFailureReason;

  /// The stack trace of the attempt that threw [fetchFailureReason]; `null`
  /// whenever [fetchFailureReason] is.
  final StackTrace? fetchFailureStackTrace;

  /// Whatever the fetch behaviour attached to this fetch (infinite queries use
  /// it to carry the page direction).
  final Object? fetchMeta;

  /// Whether `invalidateQueries` has marked the data stale regardless of
  /// `staleTime`. Reset by the next successful fetch.
  final bool isInvalidated;

  /// What the query holds: pending, success or error. Defaults to
  /// [QueryStatus.pending].
  final QueryStatus status;

  /// What the query is doing: fetching, paused or idle. Defaults to
  /// [FetchStatus.idle].
  final FetchStatus fetchStatus;

  /// Whether anything has ever been fetched, successfully or not.
  bool get isFetched => dataUpdateCount + errorUpdateCount > 0;

  /// This state with the given fields replaced.
  ///
  /// Pass [hasData] whenever you pass [data]: the two are one unit, and only
  /// [hasData] can tell "set it to null" from "leave it alone".
  QueryState<TQueryData> copyWith({
    bool? hasData,
    TQueryData? data,
    int? dataUpdateCount,
    DateTime? dataUpdatedAt,
    Object? error,
    StackTrace? errorStackTrace,
    int? errorUpdateCount,
    int? consecutiveErrorCount,
    DateTime? errorUpdatedAt,
    int? fetchFailureCount,
    Object? fetchFailureReason,
    StackTrace? fetchFailureStackTrace,
    Object? fetchMeta,
    bool? isInvalidated,
    QueryStatus? status,
    FetchStatus? fetchStatus,
    bool clearData = false,
    bool clearError = false,
    bool clearFetchFailure = false,
    bool clearFetchMeta = false,
  }) {
    return QueryState<TQueryData>(
      hasData: hasData ?? (clearData ? false : this.hasData),
      // `data` and `hasData` travel together: passing `hasData: true` makes
      // `data` authoritative, including when it is `null`. Without that rule a
      // query whose data type is nullable could never resolve *to* null — the
      // `??` would read a legitimate value as "not passed" and keep the
      // previous one.
      data: clearData ? null : (hasData == true ? data : (data ?? this.data)),
      dataUpdateCount: dataUpdateCount ?? this.dataUpdateCount,
      dataUpdatedAt: dataUpdatedAt ?? this.dataUpdatedAt,
      error: clearError ? null : (error ?? this.error),
      errorStackTrace:
          clearError ? null : (errorStackTrace ?? this.errorStackTrace),
      errorUpdateCount: errorUpdateCount ?? this.errorUpdateCount,
      consecutiveErrorCount:
          consecutiveErrorCount ?? this.consecutiveErrorCount,
      // Not cleared with the error: upstream's `fetchState` and `successState`
      // null `error` and leave `errorUpdatedAt` standing, so "last failed at"
      // survives the refetch that follows.
      errorUpdatedAt: errorUpdatedAt ?? this.errorUpdatedAt,
      fetchFailureCount:
          fetchFailureCount ?? (clearFetchFailure ? 0 : this.fetchFailureCount),
      fetchFailureReason: clearFetchFailure
          ? null
          : (fetchFailureReason ?? this.fetchFailureReason),
      fetchFailureStackTrace: clearFetchFailure
          ? null
          : (fetchFailureStackTrace ?? this.fetchFailureStackTrace),
      fetchMeta: clearFetchMeta ? null : (fetchMeta ?? this.fetchMeta),
      isInvalidated: isInvalidated ?? this.isInvalidated,
      status: status ?? this.status,
      fetchStatus: fetchStatus ?? this.fetchStatus,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryState<TQueryData> &&
          other.hasData == hasData &&
          other.data == data &&
          other.dataUpdateCount == dataUpdateCount &&
          other.dataUpdatedAt == dataUpdatedAt &&
          other.error == error &&
          other.errorUpdateCount == errorUpdateCount &&
          other.consecutiveErrorCount == consecutiveErrorCount &&
          other.errorUpdatedAt == errorUpdatedAt &&
          other.fetchFailureCount == fetchFailureCount &&
          other.fetchFailureReason == fetchFailureReason &&
          other.fetchMeta == fetchMeta &&
          other.isInvalidated == isInvalidated &&
          other.status == status &&
          other.fetchStatus == fetchStatus;

  @override
  int get hashCode => Object.hash(
        hasData,
        data,
        dataUpdateCount,
        dataUpdatedAt,
        error,
        errorUpdateCount,
        consecutiveErrorCount,
        errorUpdatedAt,
        fetchFailureCount,
        fetchFailureReason,
        fetchMeta,
        isInvalidated,
        status,
        fetchStatus,
      );

  @override
  String toString() =>
      'QueryState($status/$fetchStatus, hasData: $hasData, data: $data, '
      'error: $error, invalidated: $isInvalidated)';
}
