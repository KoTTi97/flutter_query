/// Port of the state half of `query-core/src/query.ts` at upstream `50680b98c`.
library;

import 'package:meta/meta.dart';

/// What a query *holds*. Orthogonal to [FetchStatus], which is what it is
/// *doing* — the pair is upstream's central design and is ported unchanged.
enum QueryStatus { pending, success, error }

/// What a query is doing right now.
enum FetchStatus {
  /// A fetch is in flight.
  fetching,

  /// A fetch wants to run but cannot: the device is offline and the query's
  /// [NetworkMode] says to wait.
  paused,

  /// Nothing is happening.
  idle,
}

/// A query's state at one point in time.
///
/// Flat and immutable rather than sealed: `status` and `fetchStatus` are
/// orthogonal, and the counters survive transitions, so sealing here would
/// either flatten a nine-way product or duplicate the counters into every
/// variant. The sealing happens one layer up, in `QueryResult`, where users
/// live. See https://github.com/KoTTi97/flutter_query/issues/12.
///
/// [hasData] is the port's answer to upstream's two nulls: `hasData == false`
/// is upstream's `undefined` (nothing has ever resolved), while
/// `hasData == true` with a null [data] is upstream's `null` (a query that
/// legitimately resolved to nothing). See
/// https://github.com/KoTTi97/flutter_query/issues/7.
///
/// Publicly constructible on purpose: handing a state to `QueryCache.build` is
/// the entire hook a persistence layer needs
/// (https://github.com/KoTTi97/flutter_query/issues/17).
@immutable
final class QueryState<TQueryData> {
  const QueryState({
    this.hasData = false,
    this.data,
    this.dataUpdateCount = 0,
    this.dataUpdatedAt,
    this.error,
    this.errorStackTrace,
    this.errorUpdateCount = 0,
    this.errorUpdatedAt,
    this.fetchFailureCount = 0,
    this.fetchFailureReason,
    this.fetchFailureStackTrace,
    this.fetchMeta,
    this.isInvalidated = false,
    this.status = QueryStatus.pending,
    this.fetchStatus = FetchStatus.idle,
  });

  /// Whether [data] means anything. See the class doc.
  final bool hasData;
  final TQueryData? data;
  final int dataUpdateCount;
  final DateTime? dataUpdatedAt;

  final Object? error;
  final StackTrace? errorStackTrace;
  final int errorUpdateCount;
  final DateTime? errorUpdatedAt;

  /// Failures inside the *current* fetch, reset when a new one starts. A query
  /// retrying in the background reports progress here without changing
  /// [status].
  final int fetchFailureCount;
  final Object? fetchFailureReason;
  final StackTrace? fetchFailureStackTrace;

  /// Whatever the fetch behaviour attached to this fetch (infinite queries use
  /// it to carry the page direction).
  final Object? fetchMeta;

  final bool isInvalidated;
  final QueryStatus status;
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
      errorUpdatedAt:
          clearError ? null : (errorUpdatedAt ?? this.errorUpdatedAt),
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
