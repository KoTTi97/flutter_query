/// What a mutation observer reports.
///
/// Mirrors the query side's sealed result
/// (https://github.com/KoTTi97/flutter_query/issues/14) so the two halves of
/// the library feel like one.
library;

import 'package:meta/meta.dart';

import 'mutation.dart';

/// The result of observing one mutation — upstream's
/// `MutationObserverResult`, as a sealed hierarchy.
///
/// `switch` on it and the data or error is simply there:
///
/// ```dart
/// switch (result) {
///   MutationIdle() => SaveButton(onPressed: () => result.mutate(draft)),
///   MutationPending() => const SaveButton(onPressed: null),
///   MutationSuccess(:final data) => Text('Saved as ${data.id}'),
///   MutationError(:final error) => ErrorView(error, retry: result.reset),
/// }
/// ```
///
/// Every variant carries [mutate], [mutateAsync] and [reset], so a widget can
/// submit from any of them.
@immutable
sealed class MutationResult<TData, TVariables> {
  /// Built by the observer; each argument is the field of the same name.
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

  /// Whether [variables] means anything: false while idle, and the only way
  /// to tell a real `null` from none when `TVariables` is nullable.
  final bool hasVariables;

  /// Failed attempts within the current run — upstream's `failureCount`.
  /// Reset when a new run starts.
  final int failureCount;

  /// What the latest failed attempt threw — upstream's `failureReason`.
  /// `null` once an attempt succeeds or a new run starts.
  final Object? failureReason;

  /// Whether the run is waiting for the network — upstream's `isPaused`.
  /// Under [NetworkMode.online] a mutation submitted offline sits here until
  /// the device is back, when a mounted client resumes it through
  /// `resumePausedMutations`.
  final bool isPaused;

  /// When the current run was submitted — upstream's `submittedAt`. `null`
  /// while idle.
  final DateTime? submittedAt;

  /// Fire and forget: errors go to the callbacks and to this result.
  final void Function(TVariables variables) mutate;

  /// Completes with the data, or throws.
  final Future<TData> Function(TVariables variables) mutateAsync;

  /// Detaches from the mutation and goes back to [MutationIdle] — upstream's
  /// `reset`. The mutation itself keeps running and still fires its
  /// callbacks; only this observer stops reflecting it.
  final void Function() reset;

  /// Which variant this is, as an enum — upstream's `status`, for callers
  /// that store or compare it rather than pattern-match.
  MutationStatus get status => switch (this) {
        MutationIdle<TData, TVariables>() => MutationStatus.idle,
        MutationPending<TData, TVariables>() => MutationStatus.pending,
        MutationSuccess<TData, TVariables>() => MutationStatus.success,
        MutationError<TData, TVariables>() => MutationStatus.error,
      };

  /// Whether this is a [MutationIdle] — upstream's `isIdle`.
  bool get isIdle => this is MutationIdle<TData, TVariables>;

  /// Whether this is a [MutationPending] — upstream's `isPending`.
  bool get isPending => this is MutationPending<TData, TVariables>;

  /// Whether this is a [MutationSuccess] — upstream's `isSuccess`.
  bool get isSuccess => this is MutationSuccess<TData, TVariables>;

  /// Whether this is a [MutationError] — upstream's `isError`.
  bool get isError => this is MutationError<TData, TVariables>;

  /// The data this result carries, if any. Prefer pattern matching; this
  /// exists for the cases where a nullable read is genuinely what you want.
  TData? get dataOrNull => switch (this) {
        MutationSuccess<TData, TVariables>(:final data) => data,
        _ => null,
      };

  /// The error this result carries, if any.
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
  /// Built by the observer; each argument is the field of the same name.
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
  /// Built by the observer; each argument is the field of the same name.
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

/// The mutation function returned, and the success callbacks have run.
final class MutationSuccess<TData, TVariables>
    extends MutationResult<TData, TVariables> {
  /// Built by the observer; each argument is the field of the same name.
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

  /// What the mutation function returned.
  final TData data;
}

/// The run failed for good: retries, if any, are spent.
final class MutationError<TData, TVariables>
    extends MutationResult<TData, TVariables> {
  /// Built by the observer; each argument is the field of the same name.
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

  /// What the last attempt threw — or what a success callback threw, which
  /// counts the same.
  final Object error;

  /// Where [error] was thrown.
  final StackTrace stackTrace;
}
