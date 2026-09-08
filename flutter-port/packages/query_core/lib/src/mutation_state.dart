import 'package:meta/meta.dart';

/// A sentinel for "leave this field alone" in [MutationState.copyWith], so a
/// nullable field can be cleared as well as set.
const Object _unset = Object();

/// Where a mutation is in its life.
///
/// Unlike a query there is no separate fetch status: a mutation runs once, so
/// "is it running" and "what does it hold" are the same axis. [isPaused] is the
/// one extra bit, for a mutation waiting on connectivity.
enum MutationStatus { idle, pending, success, error }

/// Everything the cache knows about one mutation.
@immutable
class MutationState<TData, TVariables, TOnMutateResult> {
  const MutationState({
    this.onMutateResult,
    this.hasData = false,
    this.data,
    this.error,
    this.errorStackTrace,
    this.failureCount = 0,
    this.failureReason,
    this.failureStackTrace,
    this.isPaused = false,
    this.status = MutationStatus.idle,
    this.variables,
    this.submittedAt,
  });

  /// Whatever `onMutate` returned — the rollback material for `onError`.
  ///
  /// Upstream calls this `context`; renamed here because `context` means
  /// something else entirely in Flutter.
  final TOnMutateResult? onMutateResult;

  final bool hasData;
  final TData? data;

  final Object? error;
  final StackTrace? errorStackTrace;

  /// Failures within the current attempt, reset when the mutation restarts.
  final int failureCount;
  final Object? failureReason;
  final StackTrace? failureStackTrace;

  /// Whether the mutation is waiting for connectivity rather than running.
  final bool isPaused;

  final MutationStatus status;

  /// What the mutation was called with. Null until it is submitted.
  final TVariables? variables;

  /// When the mutation was submitted. Null while idle.
  final DateTime? submittedAt;

  MutationState<TData, TVariables, TOnMutateResult> copyWith({
    Object? onMutateResult = _unset,
    bool? hasData,
    Object? data = _unset,
    Object? error = _unset,
    Object? errorStackTrace = _unset,
    int? failureCount,
    Object? failureReason = _unset,
    Object? failureStackTrace = _unset,
    bool? isPaused,
    MutationStatus? status,
    Object? variables = _unset,
    Object? submittedAt = _unset,
  }) {
    return MutationState<TData, TVariables, TOnMutateResult>(
      onMutateResult: identical(onMutateResult, _unset)
          ? this.onMutateResult
          : onMutateResult as TOnMutateResult?,
      hasData: hasData ?? this.hasData,
      data: identical(data, _unset) ? this.data : data as TData?,
      error: identical(error, _unset) ? this.error : error,
      errorStackTrace: identical(errorStackTrace, _unset)
          ? this.errorStackTrace
          : errorStackTrace as StackTrace?,
      failureCount: failureCount ?? this.failureCount,
      failureReason: identical(failureReason, _unset)
          ? this.failureReason
          : failureReason,
      failureStackTrace: identical(failureStackTrace, _unset)
          ? this.failureStackTrace
          : failureStackTrace as StackTrace?,
      isPaused: isPaused ?? this.isPaused,
      status: status ?? this.status,
      variables: identical(variables, _unset)
          ? this.variables
          : variables as TVariables?,
      submittedAt: identical(submittedAt, _unset)
          ? this.submittedAt
          : submittedAt as DateTime?,
    );
  }

  @override
  String toString() =>
      'MutationState(status: $status, isPaused: $isPaused, '
      'hasData: $hasData, failureCount: $failureCount)';
}
