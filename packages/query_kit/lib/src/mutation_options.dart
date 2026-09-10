/// Mutation options. Ports the mutation half of `query-core/src/types.ts` at
/// upstream `50680b98c` (https://github.com/KoTTi97/flutter_query/issues/14).
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'option_values.dart';
import 'query_key.dart';

/// Mutations sharing a scope run one at a time, in the order they started.
///
/// The reason it ships: replaying three edits to the same record concurrently
/// reorders them, which is exactly what an offline queue must not do.
@immutable
final class MutationScope {
  /// Scopes with equal [id]s are the same scope.
  const MutationScope(this.id);

  /// The scope's identity — upstream's `scope: { id }`. Any value with value
  /// equality; a string naming the record being edited is the usual choice.
  final Object id;

  @override
  bool operator ==(Object other) => other is MutationScope && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MutationScope($id)';
}

/// What a mutation runs.
typedef MutationFn<TData, TVariables> = FutureOr<TData> Function(
    TVariables variables);

/// Callbacks a caller can attach to a single `mutate` call, on top of the ones
/// in the options.
@immutable
class MutateCallbacks<TData, TVariables, TOnMutateResult> {
  /// Any of the three may be left unset.
  const MutateCallbacks({this.onSuccess, this.onError, this.onSettled});

  /// Runs after the options' `onSuccess`, with the data, the variables, and
  /// what `onMutate` returned. Like the other two, it is skipped when the
  /// observer has stopped listening before the mutation settled — upstream's
  /// per-call `onSuccess`.
  final FutureOr<void> Function(
    TData data,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onSuccess;

  /// Runs after the options' `onError`, once retries are spent — upstream's
  /// per-call `onError`.
  final FutureOr<void> Function(
    Object error,
    StackTrace stackTrace,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onError;

  /// Runs after the options' `onSettled`, on success and error alike, with
  /// whichever of `data` and `error` applies — upstream's per-call
  /// `onSettled`.
  final FutureOr<void> Function(
    TData? data,
    Object? error,
    StackTrace? stackTrace,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onSettled;
}

/// Everything that describes a mutation.
///
/// `TOnMutateResult` is upstream's renamed `TContext`: what [onMutate] returns
/// and [onError]/[onSettled] receive — the rollback handle for an optimistic
/// update. The rename matters more in Flutter, where `BuildContext` owns the
/// word. A mutation with no optimistic step has no such result; [simple]
/// spells that out as `void` so the other two types infer from [mutationFn].
///
/// No value equality, on purpose: options built inline are re-applied on
/// every build, and the observer compares the resolved values — so inline
/// callbacks are not a change by themselves.
@immutable
class MutationOptions<TData, TVariables, TOnMutateResult> {
  /// Every field is optional; an unset field takes the client's default when
  /// the mutation is built.
  const MutationOptions({
    this.mutationKey,
    this.mutationFn,
    this.onMutate,
    this.onSuccess,
    this.onError,
    this.onSettled,
    this.retry,
    this.retryDelay,
    this.networkMode,
    this.gcTime,
    this.scope,
    this.meta,
  });

  /// Options for a mutation without an [onMutate] step.
  ///
  /// The same parameters as the constructor, minus `onMutate`, on a
  /// `MutationOptions<TData, TVariables, void>` — so the two types that matter
  /// infer from [mutationFn], and nothing has to be written out:
  ///
  /// ```dart
  /// context.mutation(MutationOptions.simple(
  ///   mutationFn: (String name) => api.add(name),
  ///   onSuccess: (_, __, ___) => client.invalidateQueries(…),
  /// ));
  /// ```
  ///
  /// A static method rather than a typedef, because a typedef cannot fix one
  /// type argument of a class constructor and leave the others to inference.
  static MutationOptions<TData, TVariables, void> simple<TData, TVariables>({
    QueryKey? mutationKey,
    MutationFn<TData, TVariables>? mutationFn,
    FutureOr<void> Function(
      TData data,
      TVariables variables,
      void onMutateResult,
    )? onSuccess,
    FutureOr<void> Function(
      Object error,
      StackTrace stackTrace,
      TVariables variables,
      void onMutateResult,
    )? onError,
    FutureOr<void> Function(
      TData? data,
      Object? error,
      StackTrace? stackTrace,
      TVariables variables,
      void onMutateResult,
    )? onSettled,
    RetryPolicy? retry,
    RetryDelay? retryDelay,
    NetworkMode? networkMode,
    GcTime? gcTime,
    MutationScope? scope,
    Object? meta,
  }) =>
      MutationOptions<TData, TVariables, void>(
        mutationKey: mutationKey,
        mutationFn: mutationFn,
        onSuccess: onSuccess,
        onError: onError,
        onSettled: onSettled,
        retry: retry,
        retryDelay: retryDelay,
        networkMode: networkMode,
        gcTime: gcTime,
        scope: scope,
        meta: meta,
      );

  /// Groups mutations for the cache's filters, for `isMutating`, and for the
  /// defaults registered with `QueryClient.setMutationDefaults`. Optional: a
  /// mutation without a key simply cannot be addressed by one.
  final QueryKey? mutationKey;

  /// Runs the mutation. Left unset, the function registered for the key with
  /// `setMutationDefaults` is used, and a mutation with none fails with
  /// `MissingMutationFunctionError`.
  final MutationFn<TData, TVariables>? mutationFn;

  /// Runs before the mutation function; its result is handed to [onError] and
  /// [onSettled] so an optimistic update can be rolled back.
  final FutureOr<TOnMutateResult?> Function(TVariables variables)? onMutate;

  /// Runs when the mutation function succeeds, before the result reports
  /// success. Throwing here turns the success into an error, as upstream
  /// does.
  final FutureOr<void> Function(
    TData data,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onSuccess;

  /// Runs when the mutation fails for good, retries spent, with what
  /// [onMutate] returned so an optimistic update can be rolled back.
  final FutureOr<void> Function(
    Object error,
    StackTrace stackTrace,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onError;

  /// Runs after [onSuccess] or [onError], with whichever of `data` and
  /// `error` applies.
  final FutureOr<void> Function(
    TData? data,
    Object? error,
    StackTrace? stackTrace,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onSettled;

  /// Whether a failed attempt is retried. Default [RetryPolicy.never] —
  /// upstream's `retry: 0` for mutations, which are rarely safe to repeat.
  final RetryPolicy? retry;

  /// How long to wait between attempts. Default [RetryDelay.defaultValue].
  final RetryDelay? retryDelay;

  /// How connectivity gates the run. Default [NetworkMode.online]: submitted
  /// offline, the mutation pauses, and a mounted client resumes it on
  /// reconnect.
  final NetworkMode? networkMode;

  /// How long a settled mutation stays in the cache once nothing observes
  /// it. Default [GcTime.defaultValue], five minutes.
  final GcTime? gcTime;

  /// Mutations in the same scope run one at a time — see [MutationScope].
  /// Unset, mutations run concurrently.
  ///
  /// Read when a run starts and fixed for that run: changing it through an
  /// observer's `setOptions` while the mutation is pending does not move the
  /// mutation to the new queue, nor release the old one early.
  final MutationScope? scope;

  /// Arbitrary data carried along for logging, devtools or the callbacks.
  final Object? meta;
}

/// Mutation options with every default resolved. Only `QueryClient` produces
/// one, and `final` keeps it that way.
@immutable
final class DefaultedMutationOptions<TData, TVariables, TOnMutateResult> {
  /// Built by `QueryClient.defaultMutationOptions`; not for callers.
  @internal
  const DefaultedMutationOptions({
    required this.mutationKey,
    required this.mutationFn,
    required this.onMutate,
    required this.onSuccess,
    required this.onError,
    required this.onSettled,
    required this.retry,
    required this.retryDelay,
    required this.networkMode,
    required this.gcTime,
    required this.scope,
    required this.meta,
  });

  /// [MutationOptions.mutationKey]; there is no default.
  final QueryKey? mutationKey;

  /// [MutationOptions.mutationFn], with the key's registered default applied.
  /// Still nullable: the mutation fails only when it runs.
  final MutationFn<TData, TVariables>? mutationFn;

  /// [MutationOptions.onMutate], carried through as given.
  ///
  /// `MutationDefaults` carries no callbacks, so there is no per-key default
  /// to merge in — unlike `mutationFn`, `retry`, `retryDelay`,
  /// `networkMode`, `gcTime`, `scope` and `meta`, which do have one (eighth
  /// review, 2026-09-10).
  final FutureOr<TOnMutateResult?> Function(TVariables variables)? onMutate;

  /// [MutationOptions.onSuccess], carried through as given.
  ///
  /// `MutationDefaults` carries no callbacks, so there is no per-key default
  /// to merge in — unlike `mutationFn`, `retry`, `retryDelay`,
  /// `networkMode`, `gcTime`, `scope` and `meta`, which do have one (eighth
  /// review, 2026-09-10).
  final FutureOr<void> Function(
    TData data,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onSuccess;

  /// [MutationOptions.onError], carried through as given.
  ///
  /// `MutationDefaults` carries no callbacks, so there is no per-key default
  /// to merge in — unlike `mutationFn`, `retry`, `retryDelay`,
  /// `networkMode`, `gcTime`, `scope` and `meta`, which do have one (eighth
  /// review, 2026-09-10).
  final FutureOr<void> Function(
    Object error,
    StackTrace stackTrace,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onError;

  /// [MutationOptions.onSettled], carried through as given.
  ///
  /// `MutationDefaults` carries no callbacks, so there is no per-key default
  /// to merge in — unlike `mutationFn`, `retry`, `retryDelay`,
  /// `networkMode`, `gcTime`, `scope` and `meta`, which do have one (eighth
  /// review, 2026-09-10).
  final FutureOr<void> Function(
    TData? data,
    Object? error,
    StackTrace? stackTrace,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onSettled;

  /// [MutationOptions.retry], with the default applied.
  final RetryPolicy retry;

  /// [MutationOptions.retryDelay], with the default applied.
  final RetryDelay retryDelay;

  /// [MutationOptions.networkMode], with the default applied.
  final NetworkMode networkMode;

  /// [MutationOptions.gcTime], with the default applied.
  final GcTime gcTime;

  /// [MutationOptions.scope], with the key's registered default applied.
  final MutationScope? scope;

  /// [MutationOptions.meta], with the key's registered default applied.
  final Object? meta;

  /// Field-by-field equality, functions compared by identity — upstream's
  /// `shallowEqualObjects` over defaulted options, which is what tells a
  /// rebuild that nothing actually changed.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DefaultedMutationOptions<TData, TVariables, TOnMutateResult> &&
          other.mutationKey == mutationKey &&
          other.mutationFn == mutationFn &&
          other.onMutate == onMutate &&
          other.onSuccess == onSuccess &&
          other.onError == onError &&
          other.onSettled == onSettled &&
          other.retry == retry &&
          other.retryDelay == retryDelay &&
          other.networkMode == networkMode &&
          other.gcTime == gcTime &&
          other.scope == scope &&
          other.meta == meta;

  @override
  int get hashCode => Object.hash(
        mutationKey,
        mutationFn,
        onMutate,
        onSuccess,
        onError,
        onSettled,
        retry,
        retryDelay,
        networkMode,
        gcTime,
        scope,
        meta,
      );
}
