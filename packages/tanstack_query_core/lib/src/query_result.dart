/// What an observer reports. Ports `QueryObserverResult` from
/// `query-core/src/types.ts` at upstream `50680b98c`, as a sealed hierarchy
/// rather than a bag of booleans
/// (https://github.com/KoTTi97/flutter_query/issues/12).
library;

import 'package:meta/meta.dart';

import 'query_state.dart';

/// Refetches the query behind a result.
///
/// Errors surface in the returned result rather than as a thrown exception, so
/// a widget callback can await it without a try/catch.
typedef QueryRefetch<TData> = Future<QueryResult<TData>> Function(
    {bool cancelRefetch});

/// The result of observing one query.
///
/// `switch` on it and the data is simply there — no `result.data!`:
///
/// ```dart
/// switch (result) {
///   QueryPending() => const CircularProgressIndicator(),
///   QuerySuccess(:final data) => SensorList(sensors: data),
///   QueryError(:final error, :final staleData) => staleData != null
///       ? SensorList(sensors: staleData, banner: 'Offline')
///       : ErrorView(error),
/// }
/// ```
///
/// [fetchStatus] is orthogonal to which variant this is: a [QuerySuccess] that
/// is refetching in the background is the ordinary stale-while-revalidate case.
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
    required this.isPlaceholderData,
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

  /// How many times this query has ended in an error over its whole life.
  final int errorUpdateCount;

  final bool isStale;

  /// Whether this observer's options currently allow the query to run.
  final bool isEnabled;

  /// Whether anything has ever been fetched, successfully or not.
  final bool isFetched;

  /// Whether a fetch has completed since this observer was created.
  final bool isFetchedAfterMount;

  /// Whether the data shown is `placeholderData` rather than cached data.
  final bool isPlaceholderData;

  final QueryRefetch<TData> refetch;

  QueryStatus get status => switch (this) {
        QueryPending<TData>() => QueryStatus.pending,
        QuerySuccess<TData>() => QueryStatus.success,
        QueryError<TData>() => QueryStatus.error,
      };

  bool get isPending => this is QueryPending<TData>;
  bool get isSuccess => this is QuerySuccess<TData>;
  bool get isError => this is QueryError<TData>;

  bool get isFetching => fetchStatus == FetchStatus.fetching;
  bool get isPaused => fetchStatus == FetchStatus.paused;

  /// The first load: pending *and* fetching.
  bool get isLoading => isPending && isFetching;

  /// A fetch over data that is already there.
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

  /// The error this result carries, if any.
  Object? get errorOrNull => switch (this) {
        QueryError<TData>(:final error) => error,
        _ => null,
      };

  @override
  int get hashCode => Object.hash(_identity, dataOrNull, errorOrNull);
}

/// Nothing has resolved yet.
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
    required super.isPlaceholderData,
    required super.refetch,
  });

  @override
  String toString() => 'QueryPending(fetchStatus: $fetchStatus)';
}

/// The query holds data — fetched, seeded, or a placeholder.
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
    required super.isPlaceholderData,
    required super.refetch,
  });

  final TData data;

  @override
  String toString() => 'QuerySuccess($data, fetchStatus: $fetchStatus, '
      'placeholder: $isPlaceholderData)';
}

/// The last attempt failed.
///
/// [staleData] is what upstream's error reducer deliberately keeps: a failed
/// background refetch over content that is already on screen must not blank it.
final class QueryError<TData> extends QueryResult<TData> {
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
    required super.isStale,
    required super.isEnabled,
    required super.isFetched,
    required super.isFetchedAfterMount,
    required super.isPlaceholderData,
    required super.refetch,
  });

  final Object error;
  final StackTrace stackTrace;

  /// The last good data, if there is any.
  final TData? staleData;

  /// Whether [staleData] means anything — a query whose data type is nullable
  /// can hold a null that is real data.
  final bool hasStaleData;

  /// The first load failed and there is nothing to show.
  bool get isLoadingError => !hasStaleData;

  /// A refetch failed over data that is still on screen.
  bool get isRefetchError => hasStaleData;

  @override
  String toString() => 'QueryError($error, hasStaleData: $hasStaleData, '
      'fetchStatus: $fetchStatus)';
}
