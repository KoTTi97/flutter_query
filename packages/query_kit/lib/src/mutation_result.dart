/// What a mutation observer reports, as a sealed result mirroring the query
/// side's.
library;

import 'package:meta/meta.dart';

import 'mutation.dart';
import 'mutation_options.dart';

/// The result of observing one mutation: what a `MutationObserver` reports
/// and what the Flutter binding's mutation helpers hand a widget.
///
/// Sealed, with one variant per [MutationStatus]:
///
/// * [MutationIdle] — nothing submitted yet, or [reset] since.
/// * [MutationPending] — a run is in flight, or paused ([isPaused]) waiting
///   for the network, the foreground, or its `MutationScope`.
/// * [MutationSuccess] — the last run succeeded; carries its `data`.
/// * [MutationError] — the last run failed for good; carries its `error`.
///
/// `switch` on it and the data or error is simply there:
///
/// ```dart
/// return switch (result) {
///   MutationIdle() => SaveButton(onPressed: () => result.mutate(draft)),
///   MutationPending() => const SaveButton(onPressed: null),
///   MutationSuccess(:final data) => Text('Saved as ${data.id}'),
///   MutationError(:final error) => ErrorView(error, retry: result.reset),
/// };
/// ```
///
/// Every variant carries [mutate], [mutateAsync] and [reset], so a widget can
/// submit from any of them. (TanStack Query: `MutationObserverResult`.)
///
/// {@category Mutations}
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

  /// How many attempts of the current run have failed so far. Reset when a
  /// new run starts.
  final int failureCount;

  /// What the latest failed attempt threw, kept while retries continue.
  /// `null` once an attempt succeeds or a new run starts.
  final Object? failureReason;

  /// Whether the run is parked rather than running. Three things park it:
  /// the network (under `NetworkMode.online` a mutation submitted offline
  /// sits here until the device is back, when a mounted client resumes it
  /// through `resumePausedMutations`), focus (a retry waits for the app to
  /// return to the foreground), and its `MutationScope` — a mutation queued
  /// behind another in its scope is `pending` with `isPaused` until its
  /// turn. Show "waiting" rather than "saving" while it is set.
  final bool isPaused;

  /// When the current run was submitted. `null` while idle.
  final DateTime? submittedAt;

  /// Starts a new run with the given variables and returns at once: errors
  /// go to the callbacks and to the next result, never to the caller.
  ///
  /// It takes only the variables, so it can be passed around as a plain
  /// callback. To attach per-call [MutateCallbacks], call
  /// `MutationObserver.mutate(variables, callbacks: ...)` instead — or the
  /// Flutter binding's `MutationController.mutate`.
  final void Function(TVariables variables) mutate;

  /// Starts a new run with the given variables and completes with its data,
  /// or throws its error, once the run's callbacks have run.
  final Future<TData> Function(TVariables variables) mutateAsync;

  /// Detaches from the mutation and goes back to [MutationIdle] — to clear
  /// an error message, say. The mutation itself keeps running and still
  /// fires its callbacks; only this observer stops reflecting it.
  final void Function() reset;

  /// Which variant this is, as a [MutationStatus] — for callers that store
  /// or compare it rather than pattern-match.
  MutationStatus get status => switch (this) {
        MutationIdle<TData, TVariables>() => MutationStatus.idle,
        MutationPending<TData, TVariables>() => MutationStatus.pending,
        MutationSuccess<TData, TVariables>() => MutationStatus.success,
        MutationError<TData, TVariables>() => MutationStatus.error,
      };

  /// Whether this is a [MutationIdle]: nothing has been submitted since the
  /// observer was created or reset.
  bool get isIdle => this is MutationIdle<TData, TVariables>;

  /// Whether this is a [MutationPending]: a run is in flight or paused.
  /// Handy for disabling a submit button.
  bool get isPending => this is MutationPending<TData, TVariables>;

  /// Whether this is a [MutationSuccess]: the last run succeeded, and
  /// [dataOrNull] holds what it returned.
  bool get isSuccess => this is MutationSuccess<TData, TVariables>;

  /// Whether this is a [MutationError]: the last run failed for good, and
  /// [errorOrNull] holds why.
  bool get isError => this is MutationError<TData, TVariables>;

  /// The data this result carries, if any. Prefer pattern matching; this
  /// exists for the cases where a nullable read is genuinely what you want.
  TData? get dataOrNull => switch (this) {
        MutationSuccess<TData, TVariables>(:final data) => data,
        _ => null,
      };

  /// The error this result carries — set only on a [MutationError], `null`
  /// on every other variant.
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

  /// The variant, then the variables once a run has set them, the data or
  /// the error, and `paused` while the run waits — `MutationSuccess<int,
  /// String>(variables: draft, data: 1)`.
  @override
  String toString() {
    final parts = <String?>[
      if (hasVariables) 'variables: $variables',
      switch (this) {
        MutationSuccess<TData, TVariables>(:final data) => 'data: $data',
        MutationError<TData, TVariables>(:final error) => 'error: $error',
        MutationIdle<TData, TVariables>() ||
        MutationPending<TData, TVariables>() =>
          null,
      },
      if (isPaused) 'paused',
    ].nonNulls;
    return '$runtimeType(${parts.join(', ')})';
  }
}

/// Nothing has been submitted yet, or the observer was reset since: no
/// variables, no data, no error. Call `mutate` to start a run.
///
/// {@category Mutations}
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

/// A run has been submitted and has not settled yet: `onMutate`, the
/// mutation function or the settling callbacks are running, or the run is
/// paused ([isPaused]) waiting for the network, the foreground or its
/// `MutationScope`. `variables` holds what it was called with — what an
/// optimistic UI shows meanwhile.
///
/// {@category Mutations}
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

/// The mutation function returned, and the success callbacks have run;
/// [data] holds what it returned.
///
/// {@category Mutations}
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

  /// What the mutation function returned — typically the server's copy of
  /// what was written.
  final TData data;
}

/// The run failed for good: retries, if any, are spent, and the error
/// callbacks have run. [error] holds why; a cancelled run fails with a
/// `CancelledError`.
///
/// {@category Mutations}
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
