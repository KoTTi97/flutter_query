import 'dart:async';

import 'package:meta/meta.dart';

import 'option_values.dart';
import 'query_key.dart';

/// Mutation keys have the same shape and matching rules as query keys, so they
/// are the same type.
typedef MutationKey = QueryKey;

/// What a mutation function receives besides its variables.
///
/// Upstream also passes the `QueryClient`; here the client is whatever the
/// call site closed over, which keeps `Mutation` free of a dependency on it.
@immutable
class MutationFunctionContext {
  const MutationFunctionContext({this.mutationKey, this.meta});

  final MutationKey? mutationKey;
  final Object? meta;
}

typedef MutationFn<TData, TVariables> =
    Future<TData> Function(TVariables variables, MutationFunctionContext context);

/// Runs before the mutation function, and returns whatever the later callbacks
/// need to undo an optimistic update.
typedef OnMutate<TVariables, TOnMutateResult> =
    FutureOr<TOnMutateResult?> Function(
      TVariables variables,
      MutationFunctionContext context,
    );

typedef OnMutationSuccess<TData, TVariables, TOnMutateResult> =
    FutureOr<void> Function(
      TData data,
      TVariables variables,
      TOnMutateResult? onMutateResult,
      MutationFunctionContext context,
    );

typedef OnMutationError<TVariables, TOnMutateResult> =
    FutureOr<void> Function(
      Object error,
      StackTrace stackTrace,
      TVariables variables,
      TOnMutateResult? onMutateResult,
      MutationFunctionContext context,
    );

typedef OnMutationSettled<TData, TVariables, TOnMutateResult> =
    FutureOr<void> Function(
      TData? data,
      Object? error,
      StackTrace? stackTrace,
      TVariables variables,
      TOnMutateResult? onMutateResult,
      MutationFunctionContext context,
    );

/// Thrown when a mutation runs with no mutation function to call.
class MissingMutationFunctionError implements Exception {
  const MissingMutationFunctionError();

  @override
  String toString() =>
      'MissingMutationFunctionError: no mutationFn. Pass one in the options, '
      'or register a default with setMutationDefaults.';
}

/// Everything a mutation needs.
///
/// Every field is nullable and null always means "not set", so merging
/// defaults is a plain `??` per field — the same rule as [QueryOptions].
@immutable
class MutationOptions<TData, TVariables, TOnMutateResult> {
  const MutationOptions({
    this.mutationKey,
    this.mutationFn,
    this.gcTime,
    this.retry,
    this.retryDelay,
    this.networkMode,
    this.scope,
    this.meta,
    this.onMutate,
    this.onSuccess,
    this.onError,
    this.onSettled,
  });

  final MutationKey? mutationKey;
  final MutationFn<TData, TVariables>? mutationFn;
  final GcDuration? gcTime;
  final RetryOption? retry;
  final RetryDelay? retryDelay;
  final NetworkMode? networkMode;

  /// Mutations sharing a scope run one at a time, in the order they started.
  ///
  /// Upstream wraps this in a `{ id }` object; a bare name says the same thing.
  final String? scope;

  final Object? meta;

  final OnMutate<TVariables, TOnMutateResult>? onMutate;
  final OnMutationSuccess<TData, TVariables, TOnMutateResult>? onSuccess;
  final OnMutationError<TVariables, TOnMutateResult>? onError;
  final OnMutationSettled<TData, TVariables, TOnMutateResult>? onSettled;
}

/// Defaults that apply to many mutations at once — the client-wide defaults and
/// anything registered with `setMutationDefaults`.
///
/// It is [MutationOptions] at its most general instantiation: one bag has to
/// cover mutations of different data and variable types, and every callback
/// there accepts `Object?` where a typed one accepts its own type — which is
/// exactly the direction function subtyping allows.
typedef MutationDefaults = MutationOptions<Object?, Object?, Object?>;

/// Mutation options with every default applied.
///
/// As with queries, "already defaulted" is a distinct type rather than a flag,
/// so nothing downstream can be handed half-resolved options.
@immutable
class DefaultedMutationOptions<TData, TVariables, TOnMutateResult> {
  const DefaultedMutationOptions({
    required this.gcTime,
    required this.retry,
    required this.retryDelay,
    required this.networkMode,
    this.mutationKey,
    this.mutationFn,
    this.scope,
    this.meta,
    this.onMutate,
    this.onSuccess,
    this.onError,
    this.onSettled,
  });

  final GcDuration gcTime;
  final RetryOption retry;
  final RetryDelay retryDelay;
  final NetworkMode networkMode;
  final MutationKey? mutationKey;
  final MutationFn<TData, TVariables>? mutationFn;
  final String? scope;
  final Object? meta;
  final OnMutate<TVariables, TOnMutateResult>? onMutate;
  final OnMutationSuccess<TData, TVariables, TOnMutateResult>? onSuccess;
  final OnMutationError<TVariables, TOnMutateResult>? onError;
  final OnMutationSettled<TData, TVariables, TOnMutateResult>? onSettled;

  MutationFunctionContext get functionContext =>
      MutationFunctionContext(mutationKey: mutationKey, meta: meta);

  /// Field-wise equality, the port of upstream's `shallowEqualObjects`. An
  /// observer uses it to tell a real options change from a rebuild that passed
  /// the same values in a fresh object.
  @override
  bool operator ==(Object other) =>
      other is DefaultedMutationOptions<TData, TVariables, TOnMutateResult> &&
      gcTime == other.gcTime &&
      retry == other.retry &&
      retryDelay == other.retryDelay &&
      networkMode == other.networkMode &&
      mutationKey == other.mutationKey &&
      mutationFn == other.mutationFn &&
      scope == other.scope &&
      meta == other.meta &&
      onMutate == other.onMutate &&
      onSuccess == other.onSuccess &&
      onError == other.onError &&
      onSettled == other.onSettled;

  @override
  int get hashCode => Object.hash(
    gcTime,
    retry,
    retryDelay,
    networkMode,
    mutationKey,
    mutationFn,
    scope,
    meta,
    onMutate,
    onSuccess,
    onError,
    onSettled,
  );
}

/// The library-wide mutation fallbacks.
abstract final class MutationOptionDefaults {
  static const GcDuration gcTime = GcDuration.of(Duration(minutes: 5));

  /// Mutations do not retry by default: a write that failed is the caller's to
  /// decide about, and retrying one is rarely safe without knowing more.
  static const RetryOption retry = RetryOption.never;

  static const RetryDelay retryDelay = RetryDelay.exponential;
  static const NetworkMode networkMode = NetworkMode.online;
}

/// Resolves [options] against [defaults].
///
/// [defaults] is expected to be pre-merged by the client: client-wide defaults
/// with every matching key default layered on in registration order.
DefaultedMutationOptions<TData, TVariables, TOnMutateResult>
resolveMutationOptions<TData, TVariables, TOnMutateResult>(
  MutationOptions<TData, TVariables, TOnMutateResult> options, {
  MutationDefaults defaults = const MutationDefaults(),
}) {
  final defaultMutationFn = defaults.mutationFn;
  final defaultOnMutate = defaults.onMutate;
  final defaultOnSuccess = defaults.onSuccess;
  final defaultOnError = defaults.onError;
  final defaultOnSettled = defaults.onSettled;

  return DefaultedMutationOptions<TData, TVariables, TOnMutateResult>(
    mutationKey: options.mutationKey ?? defaults.mutationKey,
    mutationFn:
        options.mutationFn ??
        (defaultMutationFn == null
            ? null
            : (variables, context) async =>
                  await defaultMutationFn(variables, context) as TData),
    gcTime: options.gcTime ?? defaults.gcTime ?? MutationOptionDefaults.gcTime,
    retry: options.retry ?? defaults.retry ?? MutationOptionDefaults.retry,
    retryDelay:
        options.retryDelay ??
        defaults.retryDelay ??
        MutationOptionDefaults.retryDelay,
    networkMode:
        options.networkMode ??
        defaults.networkMode ??
        MutationOptionDefaults.networkMode,
    scope: options.scope ?? defaults.scope,
    meta: options.meta ?? defaults.meta,
    onMutate:
        options.onMutate ??
        (defaultOnMutate == null
            ? null
            : (variables, context) async =>
                  await defaultOnMutate(variables, context)
                      as TOnMutateResult?),
    onSuccess: options.onSuccess ?? defaultOnSuccess,
    onError: options.onError ?? defaultOnError,
    onSettled: options.onSettled ?? defaultOnSettled,
  );
}
