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
  const MutationScope(this.id);
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
  const MutateCallbacks({this.onSuccess, this.onError, this.onSettled});

  final FutureOr<void> Function(
    TData data,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onSuccess;

  final FutureOr<void> Function(
    Object error,
    StackTrace stackTrace,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onError;

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

  final QueryKey? mutationKey;
  final MutationFn<TData, TVariables>? mutationFn;

  /// Runs before the mutation function; its result is handed to [onError] and
  /// [onSettled] so an optimistic update can be rolled back.
  final FutureOr<TOnMutateResult?> Function(TVariables variables)? onMutate;

  final FutureOr<void> Function(
    TData data,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onSuccess;

  final FutureOr<void> Function(
    Object error,
    StackTrace stackTrace,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onError;

  final FutureOr<void> Function(
    TData? data,
    Object? error,
    StackTrace? stackTrace,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onSettled;

  final RetryPolicy? retry;
  final RetryDelay? retryDelay;
  final NetworkMode? networkMode;
  final GcTime? gcTime;
  final MutationScope? scope;
  final Object? meta;
}

/// Mutation options with every default resolved. Only `QueryClient` produces
/// one, and `final` keeps it that way.
@immutable
final class DefaultedMutationOptions<TData, TVariables, TOnMutateResult> {
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

  final QueryKey? mutationKey;
  final MutationFn<TData, TVariables>? mutationFn;
  final FutureOr<TOnMutateResult?> Function(TVariables variables)? onMutate;
  final FutureOr<void> Function(
    TData data,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onSuccess;
  final FutureOr<void> Function(
    Object error,
    StackTrace stackTrace,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onError;
  final FutureOr<void> Function(
    TData? data,
    Object? error,
    StackTrace? stackTrace,
    TVariables variables,
    TOnMutateResult? onMutateResult,
  )? onSettled;
  final RetryPolicy retry;
  final RetryDelay retryDelay;
  final NetworkMode networkMode;
  final GcTime gcTime;
  final MutationScope? scope;
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
