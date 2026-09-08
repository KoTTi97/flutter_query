/// What a mutation observer reports.
///
/// Mirrors the query side's sealed result
/// (https://github.com/KoTTi97/flutter_query/issues/14) so the two halves of
/// the library feel like one.
library;

import 'package:meta/meta.dart';

import 'mutation.dart';

@immutable
sealed class MutationResult<TData, TVariables> {
  const MutationResult({
    required this.variables,
    required this.hasVariables,
    required this.failureCount,
    required this.failureReason,
    required this.isPaused,
    required this.submittedAt,
    required this.mutate,
    required this.mutateAsync,
    required this.reset,
  });

  /// The variables of the run in flight or last finished.
  final TVariables? variables;
  final bool hasVariables;

  final int failureCount;
  final Object? failureReason;
  final bool isPaused;
  final DateTime? submittedAt;

  /// Fire and forget: errors go to the callbacks and to this result.
  final void Function(TVariables variables) mutate;

  /// Completes with the data, or throws.
  final Future<TData> Function(TVariables variables) mutateAsync;

  final void Function() reset;

  MutationStatus get status => switch (this) {
        MutationIdle<TData, TVariables>() => MutationStatus.idle,
        MutationPending<TData, TVariables>() => MutationStatus.pending,
        MutationSuccess<TData, TVariables>() => MutationStatus.success,
        MutationError<TData, TVariables>() => MutationStatus.error,
      };

  bool get isIdle => this is MutationIdle<TData, TVariables>;
  bool get isPending => this is MutationPending<TData, TVariables>;
  bool get isSuccess => this is MutationSuccess<TData, TVariables>;
  bool get isError => this is MutationError<TData, TVariables>;

  TData? get dataOrNull => switch (this) {
        MutationSuccess<TData, TVariables>(:final data) => data,
        _ => null,
      };

  Object? get errorOrNull => switch (this) {
        MutationError<TData, TVariables>(:final error) => error,
        _ => null,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MutationResult<TData, TVariables> &&
          other.runtimeType == runtimeType &&
          other.variables == variables &&
          other.hasVariables == hasVariables &&
          other.failureCount == failureCount &&
          other.failureReason == failureReason &&
          other.isPaused == isPaused &&
          other.submittedAt == submittedAt &&
          other.dataOrNull == dataOrNull &&
          other.errorOrNull == errorOrNull;

  @override
  int get hashCode => Object.hash(
        runtimeType,
        variables,
        hasVariables,
        failureCount,
        failureReason,
        isPaused,
        submittedAt,
        dataOrNull,
        errorOrNull,
      );
}

/// Nothing has been submitted yet.
final class MutationIdle<TData, TVariables>
    extends MutationResult<TData, TVariables> {
  const MutationIdle({
    required super.variables,
    required super.hasVariables,
    required super.failureCount,
    required super.failureReason,
    required super.isPaused,
    required super.submittedAt,
    required super.mutate,
    required super.mutateAsync,
    required super.reset,
  });
}

/// In flight, or waiting for connectivity.
final class MutationPending<TData, TVariables>
    extends MutationResult<TData, TVariables> {
  const MutationPending({
    required super.variables,
    required super.hasVariables,
    required super.failureCount,
    required super.failureReason,
    required super.isPaused,
    required super.submittedAt,
    required super.mutate,
    required super.mutateAsync,
    required super.reset,
  });
}

final class MutationSuccess<TData, TVariables>
    extends MutationResult<TData, TVariables> {
  const MutationSuccess({
    required this.data,
    required super.variables,
    required super.hasVariables,
    required super.failureCount,
    required super.failureReason,
    required super.isPaused,
    required super.submittedAt,
    required super.mutate,
    required super.mutateAsync,
    required super.reset,
  });

  final TData data;
}

final class MutationError<TData, TVariables>
    extends MutationResult<TData, TVariables> {
  const MutationError({
    required this.error,
    required this.stackTrace,
    required super.variables,
    required super.hasVariables,
    required super.failureCount,
    required super.failureReason,
    required super.isPaused,
    required super.submittedAt,
    required super.mutate,
    required super.mutateAsync,
    required super.reset,
  });

  final Object error;
  final StackTrace stackTrace;
}
