/// The sealed result an observer reports for one query: `QueryResult` and
/// its three variants.
library;

import 'package:meta/meta.dart';

import 'query_state.dart';

/// Refetches the query behind a result.
///
/// Errors surface in the returned result rather than as a thrown exception, so
/// a widget callback can await it without a try/catch. See
/// [QueryResult.refetch] for what `cancelRefetch` does.
///
/// {@category Results}
typedef QueryRefetch<TData> = Future<QueryResult<TData>> Function(
    {bool cancelRefetch});

/// The result of observing one query: what it holds, and what it is doing.
///
/// Every observer — a `QueryObserver`, and each widget or controller of the
/// Flutter binding — hands out one of these, and a new one whenever something
/// it reports changes. Results are immutable values with `==`, so an
/// unchanged result compares equal to the previous one.
///
/// **What the query holds** is the variant. The class is sealed, with exactly
/// three subclasses, so a `switch` over it is exhaustive and each arm gets
/// the fields that exist in that state — no `result.data!`:
///
/// * [QueryPending] — nothing has resolved yet: no data, no error.
/// * [QuerySuccess] — [QuerySuccess.data] is there: fetched, seeded with
///   `initialData`, written with `setQueryData`, or a placeholder.
/// * [QueryError] — the last fetch failed for good. [QueryError.error] says
///   why, and [QueryError.staleData] keeps the data from an earlier success,
///   if there was one, so a failed refresh does not blank the screen.
///
/// **What the query is doing** is separate from the variant: [fetchStatus]
/// and the flags derived from it — [isFetching], [isPaused], [isLoading],
/// [isRefetching]. A [QuerySuccess] with [isFetching] true is the ordinary
/// background refresh: the old data stays on screen while the new data
/// loads. The retry progress of the fetch in flight is in [failureCount] and
/// [failureReason], again without changing the variant.
///
/// ```dart
/// String describe(QueryResult<List<Task>> result) => switch (result) {
///       QueryPending() => 'Loading',
///       QuerySuccess(:final data) when result.isFetching =>
///         '${data.length} tasks (refreshing)',
///       QuerySuccess(:final data) => '${data.length} tasks',
///       QueryError(:final error, :final staleData?) =>
///         '${staleData.length} tasks (refresh failed: $error)',
///       QueryError(:final error) => 'Failed: $error',
///     };
/// ```
///
/// For code that stores or compares the state rather than matching on it
/// there are [status], [isPending], [isSuccess] and [isError], and
/// [dataOrNull] and [errorOrNull] for a plain nullable read.
///
/// TanStack Query reports the same information as one object with a
/// `status` string and a set of booleans; the sealed variants replace that.
///
/// {@category Results}
@immutable
sealed class QueryResult<TData> {
  /// Built by the observer; each argument is the field of the same name.
  const QueryResult({
    required this.fetchStatus,
    required this.dataUpdatedAt,
    required this.errorUpdatedAt,
    required this.failureCount,
    required this.failureReason,
    required this.failureStackTrace,
    required this.errorUpdateCount,
    required this.consecutiveErrorCount,
    required this.isStale,
    required this.isEnabled,
    required this.isFetched,
    required this.isFetchedAfterMount,
    required this.isPlaceholderData,
    required this.refetch,
  });

  /// What the query is doing right now, independent of what it holds.
  final FetchStatus fetchStatus;

  /// When the data was last written, by a fetch or by hand — what
  /// `staleTime` counts from. `null` until something has been.
  final DateTime? dataUpdatedAt;

  /// When the query last ended in an error. `null` until it has; not cleared
  /// by a later success, so "last failed at" stays readable.
  final DateTime? errorUpdatedAt;

  /// Failures within the *current* fetch. A query retrying in the background
  /// reports progress here while still showing its last good data.
  final int failureCount;

  /// What the latest failed attempt of the current fetch threw, while it may
  /// still be retried. `null` between fetches and once an attempt succeeds.
  final Object? failureReason;

  /// The stack trace of the attempt that threw [failureReason]; `null`
  /// whenever [failureReason] is.
  final StackTrace? failureStackTrace;

  /// How many times this query has ended in an error over its whole life. It
  /// never goes down; see [consecutiveErrorCount] for failures in a row.
  final int errorUpdateCount;

  /// Fetches in a row that ended in an error — the query's
  /// [QueryState.consecutiveErrorCount], here so the widget that renders a
  /// result can read it too. A successful fetch sets it back to zero; a
  /// manual write (`setQueryData`, an optimistic patch) does not, although
  /// it turns an error into a [QuerySuccess]. So a "gave up after five
  /// failures" is read here, not from the variant: after such a write the
  /// result is a success while polling that stopped on this count stays
  /// stopped.
  final int consecutiveErrorCount;

  /// Whether the data is older than this observer's `staleTime`, or has been
  /// invalidated. A query with no data is stale; a disabled query never is,
  /// since nothing would refetch it. Stale data is still shown; it is only
  /// refetched at the next trigger (a new observer, focus, reconnect).
  final bool isStale;

  /// Whether this observer's `enabled` option currently allows the query to
  /// fetch on its own. [refetch] runs even when this is false.
  final bool isEnabled;

  /// Whether anything has ever been fetched, successfully or not.
  final bool isFetched;

  /// Whether a fetch has completed since this observer was created, as
  /// opposed to data that was already in the cache when it attached.
  final bool isFetchedAfterMount;

  /// Whether [QuerySuccess.data] is the observer's `placeholderData` rather
  /// than data from the cache. A placeholder is shown while the real fetch
  /// runs and is never written to the cache.
  final bool isPlaceholderData;

  /// Refetches this query regardless of `enabled` and `staleTime`, and
  /// completes with the result that follows. With `cancelRefetch: true`, the
  /// default, a fetch already in flight is cancelled and started over — once
  /// the query holds data; a first load is joined, not restarted. With
  /// `false` the in-flight one is awaited instead.
  final QueryRefetch<TData> refetch;

  /// Which variant this is, as an enum, for callers that store or compare it
  /// rather than pattern-match.
  QueryStatus get status => switch (this) {
        QueryPending<TData>() => QueryStatus.pending,
        QuerySuccess<TData>() => QueryStatus.success,
        QueryError<TData>() => QueryStatus.error,
      };

  /// Whether this is a [QueryPending]: nothing has resolved yet. True during
  /// the first load, and also for a disabled query that has never fetched.
  bool get isPending => this is QueryPending<TData>;

  /// Whether this is a [QuerySuccess]: the query holds data, whether or not
  /// a refresh is running.
  bool get isSuccess => this is QuerySuccess<TData>;

  /// Whether this is a [QueryError]: the last fetch failed after its
  /// retries. Earlier data may still be in [QueryError.staleData].
  bool get isError => this is QueryError<TData>;

  /// Whether a fetch is in flight, first load and refetch alike, whatever
  /// the variant.
  bool get isFetching => fetchStatus == FetchStatus.fetching;

  /// Whether a fetch wants to run but is waiting: for the network, as the
  /// query's `networkMode` asks, or for the app to return to the foreground
  /// before its next retry.
  bool get isPaused => fetchStatus == FetchStatus.paused;

  /// Whether this is the first load: pending *and* fetching. False for a
  /// pending query that is not fetching, such as a disabled one — the case
  /// where a spinner would spin forever.
  bool get isLoading => isPending && isFetching;

  /// Whether a fetch is running over a result that is not pending — a
  /// background refresh of data already shown, or a retry after an error.
  bool get isRefetching => isFetching && !isPending;

  /// The data this result carries, if any. Prefer pattern matching; this exists
  /// for the cases where a nullable read is genuinely what you want.
  TData? get dataOrNull => switch (this) {
        QuerySuccess<TData>(:final data) => data,
        QueryError<TData>(:final staleData) => staleData,
        QueryPending<TData>() => null,
      };

  @protected
  Object? get _identity => (
        fetchStatus,
        dataUpdatedAt,
        errorUpdatedAt,
        failureCount,
        failureReason,
        errorUpdateCount,
        consecutiveErrorCount,
        isStale,
        isEnabled,
        isFetched,
        isFetchedAfterMount,
        isPlaceholderData,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryResult<TData> &&
          other.runtimeType == runtimeType &&
          other._identity == _identity &&
          other.dataOrNull == dataOrNull &&
          other.errorOrNull == errorOrNull;

  /// The error this result carries: [QueryError.error] for a [QueryError],
  /// `null` for the other variants.
  Object? get errorOrNull => switch (this) {
        QueryError<TData>(:final error) => error,
        _ => null,
      };

  @override
  int get hashCode => Object.hash(_identity, dataOrNull, errorOrNull);
}

/// The query has nothing to show yet: no fetch has succeeded or failed, and
/// no data was seeded.
///
/// Usually the first load is running ([isLoading]); a disabled query that
/// has never fetched is pending too, with [fetchStatus] `idle`.
///
/// {@category Results}
final class QueryPending<TData> extends QueryResult<TData> {
  /// Built by the observer; each argument is the field of the same name.
  const QueryPending({
    required super.fetchStatus,
    required super.dataUpdatedAt,
    required super.errorUpdatedAt,
    required super.failureCount,
    required super.failureReason,
    required super.failureStackTrace,
    required super.errorUpdateCount,
    required super.consecutiveErrorCount,
    required super.isStale,
    required super.isEnabled,
    required super.isFetched,
    required super.isFetchedAfterMount,
    required super.isPlaceholderData,
    required super.refetch,
  });

  @override
  String toString() => 'QueryPending(fetchStatus: $fetchStatus)';
}

/// The query holds data — fetched, seeded, written by hand, or a
/// placeholder — in [data].
///
/// A success can be fetching at the same time: that is a background
/// refresh, and [isRefetching] is true while it runs.
///
/// {@category Results}
final class QuerySuccess<TData> extends QueryResult<TData> {
  /// Built by the observer; each argument is the field of the same name.
  const QuerySuccess({
    required this.data,
    required super.fetchStatus,
    required super.dataUpdatedAt,
    required super.errorUpdatedAt,
    required super.failureCount,
    required super.failureReason,
    required super.failureStackTrace,
    required super.errorUpdateCount,
    required super.consecutiveErrorCount,
    required super.isStale,
    required super.isEnabled,
    required super.isFetched,
    required super.isFetchedAfterMount,
    required super.isPlaceholderData,
    required super.refetch,
  });

  /// The data — fetched, seeded, or a placeholder when [isPlaceholderData]
  /// is true — after `select`, when the observer has one.
  final TData data;

  @override
  String toString() => 'QuerySuccess($data, fetchStatus: $fetchStatus, '
      'placeholder: $isPlaceholderData)';
}

/// The last fetch failed after its retries, with [error].
///
/// Data from an earlier success is kept in [staleData] (with [hasStaleData]
/// true), because a failed background refresh over content that is already
/// on screen must not blank it. [isLoadingError] and [isRefetchError] tell
/// the two cases apart.
///
/// {@category Results}
final class QueryError<TData> extends QueryResult<TData> {
  /// Built by the observer; each argument is the field of the same name.
  const QueryError({
    required this.error,
    required this.stackTrace,
    required this.staleData,
    required this.hasStaleData,
    required super.fetchStatus,
    required super.dataUpdatedAt,
    required super.errorUpdatedAt,
    required super.failureCount,
    required super.failureReason,
    required super.failureStackTrace,
    required super.errorUpdateCount,
    required super.consecutiveErrorCount,
    required super.isStale,
    required super.isEnabled,
    required super.isFetched,
    required super.isFetchedAfterMount,
    required super.isPlaceholderData,
    required super.refetch,
  });

  /// What the last attempt of the failed fetch threw. A cancelled fetch that
  /// was not reverted fails with a `CancelledError`.
  final Object error;

  /// Where [error] was thrown.
  final StackTrace stackTrace;

  /// The data from the last successful fetch or write, kept through the
  /// error; `null` when there was none. Use [hasStaleData] to tell that from
  /// data that is itself `null`.
  final TData? staleData;

  /// Whether [staleData] means anything — a query whose data type is nullable
  /// can hold a null that is real data.
  final bool hasStaleData;

  /// The first load failed and there is nothing to show.
  bool get isLoadingError => !hasStaleData;

  /// A refetch failed over data that is still on screen.
  bool get isRefetchError => hasStaleData;

  // The base compares `staleData` through `dataOrNull`; `hasStaleData` is
  // what tells a real `null` from no data, so it is part of the identity too.
  @override
  bool operator ==(Object other) =>
      super == other &&
      other is QueryError<TData> &&
      other.hasStaleData == hasStaleData;

  @override
  int get hashCode => Object.hash(super.hashCode, hasStaleData);

  @override
  String toString() => 'QueryError($error, hasStaleData: $hasStaleData, '
      'fetchStatus: $fetchStatus)';
}
