import 'package:meta/meta.dart';

import 'option_values.dart';

/// A sentinel for "leave this field alone" in [QueryState.copyWith], so a
/// nullable field can be cleared as well as set.
const Object _unset = Object();

/// Everything the cache knows about one query.
///
/// [status] and [fetchStatus] are orthogonal on purpose: a query can hold
/// successful data *and* be fetching (a background refresh), which is what
/// makes stale-while-revalidate expressible.
///
/// [hasData] rather than a null check carries "is there data" because null may
/// be a legitimate cached value; upstream leans on JavaScript's separate
/// `undefined` for this.
@immutable
class QueryState<TQueryData> {
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
    this.isInvalidated = false,
    this.status = QueryStatus.pending,
    this.fetchStatus = FetchStatus.idle,
    this.fetchMeta,
  });

  final bool hasData;
  final TQueryData? data;
  final int dataUpdateCount;
  final DateTime? dataUpdatedAt;

  final Object? error;
  final StackTrace? errorStackTrace;
  final int errorUpdateCount;
  final DateTime? errorUpdatedAt;

  /// Failures within the *current* fetch, reset when a new one starts. A
  /// retrying query reports progress here without changing [status].
  final int fetchFailureCount;
  final Object? fetchFailureReason;
  final StackTrace? fetchFailureStackTrace;

  final bool isInvalidated;
  final QueryStatus status;
  final FetchStatus fetchStatus;
  final Object? fetchMeta;

  /// Whether anything has ever been fetched, successfully or not.
  bool get isFetched => dataUpdateCount + errorUpdateCount > 0;

  QueryState<TQueryData> copyWith({
    bool? hasData,
    Object? data = _unset,
    int? dataUpdateCount,
    Object? dataUpdatedAt = _unset,
    Object? error = _unset,
    Object? errorStackTrace = _unset,
    int? errorUpdateCount,
    Object? errorUpdatedAt = _unset,
    int? fetchFailureCount,
    Object? fetchFailureReason = _unset,
    Object? fetchFailureStackTrace = _unset,
    bool? isInvalidated,
    QueryStatus? status,
    FetchStatus? fetchStatus,
    Object? fetchMeta = _unset,
  }) {
    return QueryState<TQueryData>(
      hasData: hasData ?? this.hasData,
      data: identical(data, _unset) ? this.data : data as TQueryData?,
      dataUpdateCount: dataUpdateCount ?? this.dataUpdateCount,
      dataUpdatedAt: identical(dataUpdatedAt, _unset)
          ? this.dataUpdatedAt
          : dataUpdatedAt as DateTime?,
      error: identical(error, _unset) ? this.error : error,
      errorStackTrace: identical(errorStackTrace, _unset)
          ? this.errorStackTrace
          : errorStackTrace as StackTrace?,
      errorUpdateCount: errorUpdateCount ?? this.errorUpdateCount,
      errorUpdatedAt: identical(errorUpdatedAt, _unset)
          ? this.errorUpdatedAt
          : errorUpdatedAt as DateTime?,
      fetchFailureCount: fetchFailureCount ?? this.fetchFailureCount,
      fetchFailureReason: identical(fetchFailureReason, _unset)
          ? this.fetchFailureReason
          : fetchFailureReason,
      fetchFailureStackTrace: identical(fetchFailureStackTrace, _unset)
          ? this.fetchFailureStackTrace
          : fetchFailureStackTrace as StackTrace?,
      isInvalidated: isInvalidated ?? this.isInvalidated,
      status: status ?? this.status,
      fetchStatus: fetchStatus ?? this.fetchStatus,
      fetchMeta: identical(fetchMeta, _unset) ? this.fetchMeta : fetchMeta,
    );
  }

  @override
  String toString() => 'QueryState(status: $status, fetchStatus: $fetchStatus, '
      'hasData: $hasData, dataUpdateCount: $dataUpdateCount, '
      'errorUpdateCount: $errorUpdateCount, isInvalidated: $isInvalidated)';
}
