/// Mutation options, the mutation function's context and the callback
/// typedefs.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'cancel_token.dart';
import 'option_values.dart';
// A cycle (query_client → here), which Dart allows; the context names the
// client.
import 'query_client.dart';
import 'query_key.dart';

/// Mutations sharing a scope run one at a time, in the order they started.
///
/// Use a scope when several writes to the same record must reach the server
/// in order — an offline queue replaying three edits concurrently could
/// reorder them. Set it through [MutationOptions.scope]:
///
/// ```dart
/// MutationOptions<Task, Task, void>(
///   mutationFn: (Task task) => api.saveTask(task),
///   // Every save of this task queues behind the one before it.
///   scope: MutationScope('task-$taskId'),
/// )
/// ```
///
/// **What waits for the scope is the mutation function, not `onMutate`:**
///
/// * `onMutate` — the cache-wide one and the mutation's own — runs when the
///   mutation is *submitted*, while an earlier mutation of the scope may
///   still be running. An optimistic patch, a snapshot for rolling it back,
///   a `cancelQueries` all happen then, not when the function's turn comes.
///   A snapshot taken there predates the writes still queued ahead of it,
///   so a rollback that restores it whole also undoes those; roll back only
///   what this mutation changed.
/// * The scope is held until the running mutation has *finished*, callbacks
///   included: the cache's and its options' `onSuccess`/`onError` and
///   `onSettled` run, and the next
///   mutation starts only once the future `onSettled` returned has
///   completed. An `onSettled` that returns an invalidation's future holds
///   the scope until that refetch is done; one that should not,
///   `.ignore()`s it.
///
/// While it waits, a queued mutation is `pending` with `isPaused` set. No
/// hook runs at the moment the scope admits a mutation; to undo an
/// optimistic update safely, roll back per item rather than restoring a
/// whole snapshot.
///
/// TanStack Query spells this `scope: { id }`, with the same order.
///
/// {@category Mutations}
@immutable
final class MutationScope {
  /// Creates the scope named [id]. Scopes with equal [id]s are the same
  /// scope, so two `MutationScope('task-1')` values queue together.
  const MutationScope(this.id);

  /// The scope's identity. Any value with value equality; a string naming
  /// the record being edited is the usual choice.
  final Object id;

  @override
  bool operator ==(Object other) => other is MutationScope && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MutationScope($id)';
}

/// The function a mutation runs: it performs the write for [variables] and
/// returns (or completes with) the server's answer, which becomes the
/// mutation's data. Throwing, or completing with an error, fails the
/// attempt. Set through [MutationOptions.mutationFn].
///
/// {@category Mutations}
typedef MutationFn<TData, TVariables> = FutureOr<TData> Function(
    TVariables variables);

/// What a [MutationFnWithContext] is told about the run it is part of.
///
/// [client], [meta] and [mutationKey] describe the mutation, as in TanStack
/// Query's `MutationFunctionContext`. This package adds two more:
///
/// * [onMutateResult] — after an optimistic patch the cache no longer says
///   what was there before; whatever `onMutate` kept does, and a function
///   that diffs "before" against "wanted" needs it.
/// * [signal] — cancelled by `Mutation.cancel`, so a transport that can abort
///   does. A function that ignores it runs on, and its result is discarded.
///
/// {@category Mutations}
@immutable
final class MutationFunctionContext<TOnMutateResult> {
  /// Built by the mutation for each run; not for callers.
  @internal
  const MutationFunctionContext({
    required this.client,
    required this.meta,
    required this.mutationKey,
    required this.onMutateResult,
    required this.signal,
  });

  /// The client the mutation belongs to — handy for reading or writing the
  /// query cache from inside the function.
  final QueryClient client;

  /// The mutation's [MutationOptions.meta], after the client's defaults
  /// were applied; `null` when none was set anywhere.
  final Object? meta;

  /// The mutation's [MutationOptions.mutationKey], or `null` for an unkeyed
  /// mutation.
  final QueryKey? mutationKey;

  /// What `onMutate` returned for this run — `null` when there is no
  /// `onMutate`, and for a restored mutation whatever was restored.
  final TOnMutateResult? onMutateResult;

  /// Cancelled by `cancel()` — on the mutation, its observer or a controller —
  /// and by nothing else. One token for the whole run: a cancelled mutation
  /// does not retry. Removing the mutation from the cache or disposing what
  /// watches it does **not** cancel it: an attempt in flight is left to
  /// settle, so there is nothing to abort.
  final QueryCancelToken signal;
}

/// A [MutationFn] that also receives the [MutationFunctionContext] of its
/// run. Set through [MutationOptions.mutationFnWithContext].
///
/// {@category Mutations}
typedef MutationFnWithContext<TData, TVariables, TOnMutateResult>
    = FutureOr<TData> Function(
  TVariables variables,
  MutationFunctionContext<TOnMutateResult> context,
);

/// The signature of [MutationOptions.onMutate]: runs before the mutation
/// function with its variables, and what it returns is the
/// `onMutateResult` the other callbacks receive — typically a snapshot to
/// roll an optimistic update back to. A returned future is awaited.
///
/// {@category Mutations}
typedef OnMutate<TVariables, TOnMutateResult> = FutureOr<TOnMutateResult?>
    Function(TVariables variables);

/// The signature of [MutationOptions.onSuccess] and
/// [MutateCallbacks.onSuccess]: the data, the variables, and what
/// `onMutate` returned.
///
/// {@category Mutations}
typedef OnMutationSuccess<TData, TVariables, TOnMutateResult> = FutureOr<void>
    Function(
  TData data,
  TVariables variables,
  TOnMutateResult? onMutateResult,
);

/// The signature of [MutationOptions.onError] and [MutateCallbacks.onError]:
/// the error and where it was thrown, the variables, and what `onMutate`
/// returned (`null` when `onMutate` itself threw or there is none).
///
/// {@category Mutations}
typedef OnMutationError<TVariables, TOnMutateResult> = FutureOr<void> Function(
  Object error,
  StackTrace stackTrace,
  TVariables variables,
  TOnMutateResult? onMutateResult,
);

/// The signature of [MutationOptions.onSettled] and
/// [MutateCallbacks.onSettled]: whichever of `data` and `error` applies (the
/// other is `null`), the error's stack trace, the variables, and what
/// `onMutate` returned.
///
/// {@category Mutations}
typedef OnMutationSettled<TData, TVariables, TOnMutateResult> = FutureOr<void>
    Function(
  TData? data,
  Object? error,
  StackTrace? stackTrace,
  TVariables variables,
  TOnMutateResult? onMutateResult,
);

/// Callbacks a caller can attach to a single `mutate` call, on top of the ones
/// in the options — for what only that call site cares about, such as
/// closing a dialog or showing a snack bar.
///
/// They run after the cache-wide hooks and the options' callbacks have run
/// and the result has settled, and only while the observer still has a
/// listener: a `mutate` whose widget has gone still updates the cache, but
/// does not call back into it. A returned future is not awaited, and a throw
/// is reported to the zone rather than failing the mutation.
///
/// ```dart
/// observer.mutate(
///   draft,
///   callbacks: MutateCallbacks(
///     onSuccess: (task, draft, _) => print('Saved ${task.id}'),
///     onError: (error, stackTrace, draft, _) => print('Failed: $error'),
///   ),
/// );
/// ```
///
/// {@category Mutations}
@immutable
final class MutateCallbacks<TData, TVariables, TOnMutateResult> {
  /// Creates the callbacks; any of the three may be left unset.
  const MutateCallbacks({this.onSuccess, this.onError, this.onSettled});

  /// Runs after the options' `onSuccess`, with the data, the variables, and
  /// what `onMutate` returned. Like the other two, it is skipped when the
  /// observer has stopped listening before the mutation settled. No default.
  final OnMutationSuccess<TData, TVariables, TOnMutateResult>? onSuccess;

  /// Runs after the options' `onError`, once retries are spent. No default.
  final OnMutationError<TVariables, TOnMutateResult>? onError;

  /// Runs after the options' `onSettled`, on success and error alike, with
  /// whichever of `data` and `error` applies. No default.
  final OnMutationSettled<TData, TVariables, TOnMutateResult>? onSettled;
}

/// Everything that describes a mutation: the write it performs, its
/// callbacks, and how it retries, pauses and queues.
///
/// Hand one to a `MutationObserver` (or the Flutter binding's mutation
/// helpers). The three type arguments are what the function returns
/// (`TData`), what it is called with (`TVariables`), and what [onMutate]
/// returns (`TOnMutateResult`) — the rollback handle an optimistic update
/// passes to [onError] and [onSettled]. A mutation with no optimistic step
/// has no such result; [simple] spells that out as `void` so the other two
/// types infer from [mutationFn].
///
/// An optimistic update: patch the cache in [onMutate], restore the
/// snapshot in [onError], and refetch the truth in [onSettled]:
///
/// ```dart
/// final todosKey = QueryKey(['todos']);
/// final addTodo = MutationOptions<Todo, Todo, List<Todo>>(
///   mutationFn: (Todo todo) => api.addTodo(todo),
///   onMutate: (Todo todo) async {
///     await client.cancelQueries(filters: QueryFilters(queryKey: todosKey));
///     final previous = client.getQueryData<List<Todo>>(todosKey) ?? [];
///     client.setQueryData<List<Todo>>(todosKey, [...previous, todo]);
///     return previous;
///   },
///   onError: (error, stackTrace, todo, previous) {
///     if (previous != null) client.setQueryData(todosKey, previous);
///   },
///   onSettled: (data, error, stackTrace, todo, previous) =>
///       client.invalidateQueries(filters: QueryFilters(queryKey: todosKey)),
/// );
/// ```
///
/// Every field is optional. An unset field takes the default registered for
/// the mutation's key with `QueryClient.setMutationDefaults`, then the
/// client's `DefaultOptions.mutations`, then the default each field states.
/// The callbacks have no client-level default.
///
/// The order the callbacks run in: the cache-wide `MutationCache.onMutate`,
/// then [onMutate]; after the function, `MutationCache.onSuccess` (or
/// `onError`), then [onSuccess] (or [onError]), then
/// `MutationCache.onSettled`, then [onSettled]. Each returned future is
/// awaited before the next one runs, and the mutation stays `pending` until
/// the last has completed. The per-call [MutateCallbacks] come after that.
///
/// No value equality, on purpose: options built inline are re-applied on
/// every build, and the observer compares the resolved values — so inline
/// callbacks are not a change by themselves.
///
/// {@category Mutations}
@immutable
final class MutationOptions<TData, TVariables, TOnMutateResult> {
  /// Creates the options. Every field is optional; an unset field takes the
  /// client's default when the mutation is built. Pass at most one of
  /// [mutationFn] and [mutationFnWithContext].
  const MutationOptions({
    this.mutationKey,
    this.mutationFn,
    this.mutationFnWithContext,
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
  }) : assert(
          mutationFn == null || mutationFnWithContext == null,
          'Pass mutationFn or mutationFnWithContext, not both.',
        );

  /// Options for a mutation without an [onMutate] step.
  ///
  /// The same parameters as the constructor, minus `onMutate`, on a
  /// `MutationOptions<TData, TVariables, void>` — so the two types that matter
  /// infer from [mutationFn], and nothing has to be written out:
  ///
  /// ```dart
  /// context.mutation(MutationOptions.simple(
  ///   mutationFn: (String name) => api.add(name),
  ///   onSuccess: (_, __, ___) =>
  ///       client.invalidateQueries(filters: QueryFilters(queryKey: tasksKey)),
  /// ));
  /// ```
  ///
  /// A static method rather than a typedef, because a typedef cannot fix one
  /// type argument of a class constructor and leave the others to inference.
  static MutationOptions<TData, TVariables, void> simple<TData, TVariables>({
    QueryKey? mutationKey,
    MutationFn<TData, TVariables>? mutationFn,
    MutationFnWithContext<TData, TVariables, void>? mutationFnWithContext,
    OnMutationSuccess<TData, TVariables, void>? onSuccess,
    OnMutationError<TVariables, void>? onError,
    OnMutationSettled<TData, TVariables, void>? onSettled,
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
        mutationFnWithContext: mutationFnWithContext,
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
  /// defaults registered with `QueryClient.setMutationDefaults`. No default:
  /// a mutation without a key simply cannot be addressed by one.
  final QueryKey? mutationKey;

  /// Runs the mutation. Left unset, the function registered for the key with
  /// `setMutationDefaults` (or in `DefaultOptions.mutations`) is used, and a
  /// mutation with none fails with `MissingMutationFunctionError` when it
  /// runs, without retrying.
  final MutationFn<TData, TVariables>? mutationFn;

  /// [mutationFn] with a second argument: the [MutationFunctionContext] of the
  /// run — the client, `meta`, the key, what [onMutate] returned, and a
  /// `signal` that `Mutation.cancel` cancels. Instead of [mutationFn], never
  /// beside it — both at once fails an assertion at the constructor in a
  /// debug build, and is an [ArgumentError] when the client resolves the
  /// options in a release build; when set it also wins over a function
  /// registered with `setMutationDefaults`, which has no context form. No
  /// default.
  ///
  /// A second field rather than a second parameter on [mutationFn]: Dart has
  /// no optional-arity function types, so that would make every
  /// `(variables) => …` and every tear-off a type error for the sake of the
  /// few functions that want the context. (TanStack Query passes the context
  /// as the function's second argument.)
  final MutationFnWithContext<TData, TVariables, TOnMutateResult>?
      mutationFnWithContext;

  /// Runs before the mutation function, when the mutation is submitted; its
  /// result is handed to [onSuccess], [onError] and [onSettled] so an
  /// optimistic update can be rolled back. A returned future is awaited
  /// before the function runs; a throw fails the mutation without running
  /// the function. No default.
  final OnMutate<TVariables, TOnMutateResult>? onMutate;

  /// Runs when the mutation function succeeds, after the cache-wide
  /// `MutationCache.onSuccess` and before the result reports success. A
  /// returned future is awaited. Throwing here turns the success into an
  /// error. No default.
  final OnMutationSuccess<TData, TVariables, TOnMutateResult>? onSuccess;

  /// Runs when the mutation fails for good, retries spent, after the
  /// cache-wide `MutationCache.onError`, with what [onMutate] returned so an
  /// optimistic update can be rolled back. A returned future is awaited; a
  /// throw is reported to the zone and does not replace the original error.
  /// No default.
  final OnMutationError<TVariables, TOnMutateResult>? onError;

  /// Runs after [onSuccess] or [onError] and the cache-wide
  /// `MutationCache.onSettled`, with whichever of `data` and `error`
  /// applies. A returned future is awaited, and the mutation stays `pending`
  /// until it completes — return an invalidation's future to report success
  /// only once the refetch is done. No default.
  final OnMutationSettled<TData, TVariables, TOnMutateResult>? onSettled;

  /// Whether a failed attempt is retried. Default [RetryPolicy.never]:
  /// mutations are rarely safe to repeat. (TanStack Query: `retry: 0`.)
  final RetryPolicy? retry;

  /// How long to wait between attempts. Default [RetryDelay.defaultValue]:
  /// one second, doubling per attempt, at most thirty seconds.
  final RetryDelay? retryDelay;

  /// How connectivity gates the run. Default [NetworkMode.online]: submitted
  /// offline, the mutation pauses, and a mounted client resumes it on
  /// reconnect.
  final NetworkMode? networkMode;

  /// How long a settled mutation stays in the cache once nothing observes
  /// it. Default [GcTime.defaultValue], five minutes.
  final GcTime? gcTime;

  /// Mutations in the same scope run one at a time — see [MutationScope],
  /// which says what waits (the function, not [onMutate]) and for how long
  /// (until the running one's [onSettled] has completed). No default:
  /// unscoped mutations run concurrently.
  ///
  /// Read when a run starts and fixed for that run: changing it through an
  /// observer's `setOptions` while the mutation is pending does not move the
  /// mutation to the new queue, nor release the old one early.
  final MutationScope? scope;

  /// Arbitrary data carried along for logging, devtools or the callbacks;
  /// readable as `Mutation.meta` and [MutationFunctionContext.meta]. No
  /// default.
  final Object? meta;
}

/// Mutation options with every default resolved. Only `QueryClient` produces
/// one, and `final` keeps it that way; read it from `Mutation.options` or
/// `MutationObserver.options` to see what a mutation actually runs with.
///
/// {@category Advanced}
@immutable
final class DefaultedMutationOptions<TData, TVariables, TOnMutateResult> {
  /// Built by `QueryClient.defaultMutationOptions`; not for callers.
  @internal
  const DefaultedMutationOptions({
    required this.mutationKey,
    required this.mutationFn,
    required this.mutationFnWithContext,
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

  /// [MutationOptions.mutationKey], as given; keys have no default.
  final QueryKey? mutationKey;

  /// [MutationOptions.mutationFn], with the key's registered default applied.
  /// Still nullable: the mutation fails only when it runs.
  final MutationFn<TData, TVariables>? mutationFn;

  /// [MutationOptions.mutationFnWithContext], carried through as given. When
  /// set, [mutationFn] is null.
  final MutationFnWithContext<TData, TVariables, TOnMutateResult>?
      mutationFnWithContext;

  /// [MutationOptions.onMutate], carried through as given.
  ///
  /// There is no client-level default for callbacks, so this is exactly
  /// what the options held — unlike `mutationFn`, `retry`, `retryDelay`,
  /// `networkMode`, `gcTime`, `scope` and `meta`, which do have one.
  final OnMutate<TVariables, TOnMutateResult>? onMutate;

  /// [MutationOptions.onSuccess], carried through as given.
  ///
  /// There is no client-level default for callbacks, so this is exactly
  /// what the options held — unlike `mutationFn`, `retry`, `retryDelay`,
  /// `networkMode`, `gcTime`, `scope` and `meta`, which do have one.
  final OnMutationSuccess<TData, TVariables, TOnMutateResult>? onSuccess;

  /// [MutationOptions.onError], carried through as given.
  ///
  /// There is no client-level default for callbacks, so this is exactly
  /// what the options held — unlike `mutationFn`, `retry`, `retryDelay`,
  /// `networkMode`, `gcTime`, `scope` and `meta`, which do have one.
  final OnMutationError<TVariables, TOnMutateResult>? onError;

  /// [MutationOptions.onSettled], carried through as given.
  ///
  /// There is no client-level default for callbacks, so this is exactly
  /// what the options held — unlike `mutationFn`, `retry`, `retryDelay`,
  /// `networkMode`, `gcTime`, `scope` and `meta`, which do have one.
  final OnMutationSettled<TData, TVariables, TOnMutateResult>? onSettled;

  /// [MutationOptions.retry], or the registered default, or
  /// [RetryPolicy.never].
  final RetryPolicy retry;

  /// [MutationOptions.retryDelay], or the registered default, or
  /// [RetryDelay.defaultValue].
  final RetryDelay retryDelay;

  /// [MutationOptions.networkMode], or the registered default, or
  /// [NetworkMode.online].
  final NetworkMode networkMode;

  /// [MutationOptions.gcTime], or the registered default, or
  /// [GcTime.defaultValue] (five minutes).
  final GcTime gcTime;

  /// [MutationOptions.scope], with the key's registered default applied.
  final MutationScope? scope;

  /// [MutationOptions.meta], with the key's registered default applied.
  final Object? meta;

  /// Field-by-field equality, functions compared by identity, which is what
  /// tells a rebuild that nothing actually changed.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DefaultedMutationOptions<TData, TVariables, TOnMutateResult> &&
          other.mutationKey == mutationKey &&
          other.mutationFn == mutationFn &&
          other.mutationFnWithContext == mutationFnWithContext &&
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
        mutationFnWithContext,
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
