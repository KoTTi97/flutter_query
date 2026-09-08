import 'package:meta/meta.dart';

import 'option_values.dart';

/// Refetches the query behind a result. Errors surface in the returned result
/// rather than as a thrown exception, so a widget callback can await it without
/// a try/catch.
typedef QueryRefetch<TData> = Future<QueryResult<TData>> Function(
    {bool cancelRefetch});

/// What an observer exposes to whoever is watching it.
///
/// Upstream returns one flat object with a `status` string plus a dozen
/// `isX` booleans, leaving `data` and `error` optional in every combination.
/// Here the three terminal states are separate types (D7), so having data is a
/// property of the type rather than something to re-check at each use site:
/// pattern-match the result and the data is simply there.
///
/// The orthogonal axis stays on the base class. [fetchStatus] is independent of
/// which variant this is — a [QuerySuccess] that is refetching in the
/// background is the normal stale-while-revalidate case.
@immutable
sealed class QueryResult<TData> {
  const QueryResult({
    required this.fetchStatus,
    required this.dataUpdatedAt,
    required this.errorUpdatedAt,
    required this.failureCount,
    required this.failureReason,
    required this.failureStackTrace,
    required this.errorUpdateCount,
    required this.isStale,
    required this.isEnabled,
    required this.isFetched,
    required this.isFetchedAfterMount,
    required this.refetch,
  });

  /// What the query is doing right now, independent of what it holds.
  final FetchStatus fetchStatus;

  final DateTime? dataUpdatedAt;
  final DateTime? errorUpdatedAt;

  /// Failures within the *current* fetch. A query retrying in the background
  /// reports progress here while still showing its last good data.
  final int failureCount;
  final Object? failureReason;
  final StackTrace? failureStackTrace;

  /// How many times this query has ended in an error, over its whole life.
  final int errorUpdateCount;

  final bool isStale;

  /// Whether this observer's options currently allow the query to run.
  final bool isEnabled;

  /// Whether anything has ever been fetched, successfully or not.
  final bool isFetched;

  /// Whether a fetch has completed since this observer started watching —
  /// false for data that was already in the cache.
  final bool isFetchedAfterMount;

  final QueryRefetch<TData> refetch;

  QueryStatus get status;

  /// The data if there is any, including data left over from before an error.
  TData? get dataOrNull;

  Object? get errorOrNull;

  bool get isPending => status == QueryStatus.pending;
  bool get isSuccess => status == QueryStatus.success;
  bool get isError => status == QueryStatus.error;

  bool get isFetching => fetchStatus == FetchStatus.fetching;

  /// Whether the fetch is waiting for connectivity or focus rather than
  /// running. Paused is not failed: it continues on its own.
  bool get isPaused => fetchStatus == FetchStatus.paused;

  /// The first load, with nothing to show yet — the spinner case, as opposed
  /// to [isFetching], which is also true during a background refresh.
  bool get isLoading => isPending && isFetching;

  /// A fetch over data that is already on screen.
  bool get isRefetching => isFetching && !isPending;

  /// Field-wise equality drives rebuild suppression (D5), so the [refetch]
  /// member is deliberately excluded: it is a fresh closure on every result and
  /// would make every result unequal to the last.
  bool _baseEquals(QueryResult<TData> other) =>
      fetchStatus == other.fetchStatus &&
      dataUpdatedAt == other.dataUpdatedAt &&
      errorUpdatedAt == other.errorUpdatedAt &&
      failureCount == other.failureCount &&
      failureReason == other.failureReason &&
      errorUpdateCount == other.errorUpdateCount &&
      isStale == other.isStale &&
      isEnabled == other.isEnabled &&
      isFetched == other.isFetched &&
      isFetchedAfterMount == other.isFetchedAfterMount;

  int get _baseHash => Object.hash(
        fetchStatus,
        dataUpdatedAt,
        errorUpdatedAt,
        failureCount,
        failureReason,
        errorUpdateCount,
        isStale,
        isEnabled,
        isFetched,
        isFetchedAfterMount,
      );
}

/// No data and no error yet. [QueryResult.isLoading] separates the first load
/// from a query that is merely disabled or waiting.
final class QueryPending<TData> extends QueryResult<TData> {
  const QueryPending({
    required super.fetchStatus,
    required super.dataUpdatedAt,
    required super.errorUpdatedAt,
    required super.failureCount,
    required super.failureReason,
    required super.failureStackTrace,
    required super.errorUpdateCount,
    required super.isStale,
    required super.isEnabled,
    required super.isFetched,
    required super.isFetchedAfterMount,
    required super.refetch,
  });

  @override
  QueryStatus get status => QueryStatus.pending;

  @override
  TData? get dataOrNull => null;

  @override
  Object? get errorOrNull => null;

  @override
  bool operator ==(Object other) =>
      other is QueryPending<TData> && _baseEquals(other);

  @override
  int get hashCode => Object.hash(QueryPending, _baseHash);

  @override
  String toString() => 'QueryPending(fetchStatus: $fetchStatus)';
}

/// Data is available. It stays available across background refetches, which is
/// what makes stale-while-revalidate work without a nullable read.
final class QuerySuccess<TData> extends QueryResult<TData> {
  const QuerySuccess({
    required this.data,
    required super.fetchStatus,
    required super.dataUpdatedAt,
    required super.errorUpdatedAt,
    required super.failureCount,
    required super.failureReason,
    required super.failureStackTrace,
    required super.errorUpdateCount,
    required super.isStale,
    required super.isEnabled,
    required super.isFetched,
    required super.isFetchedAfterMount,
    required super.refetch,
  });

  final TData data;

  @override
  QueryStatus get status => QueryStatus.success;

  @override
  TData? get dataOrNull => data;

  @override
  Object? get errorOrNull => null;

  @override
  bool operator ==(Object other) =>
      other is QuerySuccess<TData> && data == other.data && _baseEquals(other);

  @override
  int get hashCode => Object.hash(QuerySuccess, data, _baseHash);

  @override
  String toString() => 'QuerySuccess(data: $data, fetchStatus: $fetchStatus, '
      'isStale: $isStale)';
}

/// The query failed.
///
/// It may still carry [staleData]: a refetch that fails leaves the previous
/// data in the cache, and dropping it from the UI would be a worse answer than
/// showing it alongside the error.
final class QueryError<TData> extends QueryResult<TData> {
  const QueryError({
    required this.error,
    required this.stackTrace,
    required this.hasStaleData,
    required this.staleData,
    required super.fetchStatus,
    required super.dataUpdatedAt,
    required super.errorUpdatedAt,
    required super.failureCount,
    required super.failureReason,
    required super.failureStackTrace,
    required super.errorUpdateCount,
    required super.isStale,
    required super.isEnabled,
    required super.isFetched,
    required super.isFetchedAfterMount,
    required super.refetch,
  });

  final Object error;
  final StackTrace? stackTrace;

  /// Whether [staleData] holds a value — a separate flag because null can be a
  /// legitimate cached value.
  final bool hasStaleData;

  /// The last data this query held, if any.
  final TData? staleData;

  /// The query has never succeeded — nothing to show but the error.
  bool get isLoadingError => !hasStaleData;

  /// A refresh over existing data failed. [staleData] is still worth showing.
  bool get isRefetchError => hasStaleData;

  @override
  QueryStatus get status => QueryStatus.error;

  @override
  TData? get dataOrNull => staleData;

  @override
  Object? get errorOrNull => error;

  @override
  bool operator ==(Object other) =>
      other is QueryError<TData> &&
      error == other.error &&
      hasStaleData == other.hasStaleData &&
      staleData == other.staleData &&
      _baseEquals(other);

  @override
  int get hashCode =>
      Object.hash(QueryError, error, hasStaleData, staleData, _baseHash);

  @override
  String toString() => 'QueryError(error: $error, hasStaleData: $hasStaleData, '
      'fetchStatus: $fetchStatus)';
}
