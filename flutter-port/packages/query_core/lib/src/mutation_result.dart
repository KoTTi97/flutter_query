import 'package:meta/meta.dart';

import 'mutation_state.dart';

/// What a mutation observer exposes to whoever is watching it.
///
/// Same shape as [QueryResult] and for the same reason (D7): the terminal
/// states are separate types, so having data — or an error — is a property of
/// the type rather than something to re-check at each use site.
///
/// [variables] and [onMutateResult] stay on the base class because they are
/// what a retry button and a rollback need, and both matter most in the error
/// case.
@immutable
sealed class MutationResult<TData, TVariables, TOnMutateResult> {
  const MutationResult({
    required this.variables,
    required this.onMutateResult,
    required this.failureCount,
    required this.failureReason,
    required this.failureStackTrace,
    required this.isPaused,
    required this.submittedAt,
  });

  /// What the mutation was called with. Null until it is submitted.
  final TVariables? variables;

  /// Whatever `onMutate` returned — the material an undo needs.
  final TOnMutateResult? onMutateResult;

  final int failureCount;
  final Object? failureReason;
  final StackTrace? failureStackTrace;

  /// Whether the mutation is waiting for connectivity rather than running.
  final bool isPaused;

  final DateTime? submittedAt;

  MutationStatus get status;

  bool get isIdle => status == MutationStatus.idle;
  bool get isPending => status == MutationStatus.pending;
  bool get isSuccess => status == MutationStatus.success;
  bool get isError => status == MutationStatus.error;

  TData? get dataOrNull;
  Object? get errorOrNull;

  bool _baseEquals(MutationResult<TData, TVariables, TOnMutateResult> other) =>
      variables == other.variables &&
      onMutateResult == other.onMutateResult &&
      failureCount == other.failureCount &&
      failureReason == other.failureReason &&
      isPaused == other.isPaused &&
      submittedAt == other.submittedAt;

  int get _baseHash => Object.hash(
        variables,
        onMutateResult,
        failureCount,
        failureReason,
        isPaused,
        submittedAt,
      );
}

/// Nothing has been submitted yet.
final class MutationIdle<TData, TVariables, TOnMutateResult>
    extends MutationResult<TData, TVariables, TOnMutateResult> {
  const MutationIdle({
    required super.variables,
    required super.onMutateResult,
    required super.failureCount,
    required super.failureReason,
    required super.failureStackTrace,
    required super.isPaused,
    required super.submittedAt,
  });

  @override
  MutationStatus get status => MutationStatus.idle;

  @override
  TData? get dataOrNull => null;

  @override
  Object? get errorOrNull => null;

  @override
  bool operator ==(Object other) =>
      other is MutationIdle<TData, TVariables, TOnMutateResult> &&
      _baseEquals(other);

  @override
  int get hashCode => Object.hash(MutationIdle, _baseHash);

  @override
  String toString() => 'MutationIdle()';
}

/// Submitted and still running — or paused, waiting for connectivity.
final class MutationPending<TData, TVariables, TOnMutateResult>
    extends MutationResult<TData, TVariables, TOnMutateResult> {
  const MutationPending({
    required super.variables,
    required super.onMutateResult,
    required super.failureCount,
    required super.failureReason,
    required super.failureStackTrace,
    required super.isPaused,
    required super.submittedAt,
  });

  @override
  MutationStatus get status => MutationStatus.pending;

  @override
  TData? get dataOrNull => null;

  @override
  Object? get errorOrNull => null;

  @override
  bool operator ==(Object other) =>
      other is MutationPending<TData, TVariables, TOnMutateResult> &&
      _baseEquals(other);

  @override
  int get hashCode => Object.hash(MutationPending, _baseHash);

  @override
  String toString() =>
      'MutationPending(variables: $variables, isPaused: $isPaused)';
}

/// The mutation completed and returned [data].
final class MutationSuccess<TData, TVariables, TOnMutateResult>
    extends MutationResult<TData, TVariables, TOnMutateResult> {
  const MutationSuccess({
    required this.data,
    required super.variables,
    required super.onMutateResult,
    required super.failureCount,
    required super.failureReason,
    required super.failureStackTrace,
    required super.isPaused,
    required super.submittedAt,
  });

  final TData data;

  @override
  MutationStatus get status => MutationStatus.success;

  @override
  TData? get dataOrNull => data;

  @override
  Object? get errorOrNull => null;

  @override
  bool operator ==(Object other) =>
      other is MutationSuccess<TData, TVariables, TOnMutateResult> &&
      data == other.data &&
      _baseEquals(other);

  @override
  int get hashCode => Object.hash(MutationSuccess, data, _baseHash);

  @override
  String toString() => 'MutationSuccess(data: $data)';
}

/// The mutation failed. [MutationResult.onMutateResult] is what an undo needs.
final class MutationError<TData, TVariables, TOnMutateResult>
    extends MutationResult<TData, TVariables, TOnMutateResult> {
  const MutationError({
    required this.error,
    required this.stackTrace,
    required super.variables,
    required super.onMutateResult,
    required super.failureCount,
    required super.failureReason,
    required super.failureStackTrace,
    required super.isPaused,
    required super.submittedAt,
  });

  final Object error;
  final StackTrace? stackTrace;

  @override
  MutationStatus get status => MutationStatus.error;

  @override
  TData? get dataOrNull => null;

  @override
  Object? get errorOrNull => error;

  @override
  bool operator ==(Object other) =>
      other is MutationError<TData, TVariables, TOnMutateResult> &&
      error == other.error &&
      _baseEquals(other);

  @override
  int get hashCode => Object.hash(MutationError, error, _baseHash);

  @override
  String toString() => 'MutationError(error: $error, variables: $variables)';
}
