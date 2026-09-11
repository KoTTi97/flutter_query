/// Port of `query-core/src/mutation.ts` at upstream `50680b98c`.
library;

import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

import 'mutation_options.dart';
import 'option_values.dart';
import 'query_client.dart';
import 'query_key.dart';
import 'removable.dart';
import 'retryer.dart';

/// Where a mutation is in its life. Upstream's `MutationStatus`: `idle`
/// before the first run, `pending` while running (or paused), then `success`
/// or `error` until the next run or a reset.
enum MutationStatus {
  /// Never run, or reset since. No data, no error, no variables.
  idle,

  /// Running: `onMutate` and the mutation function are in flight, or the run
  /// is paused offline. `variables` is set.
  pending,

  /// The last run resolved; `data` holds what the mutation function returned.
  success,

  /// The last run failed for good; `error` holds why.
  error,
}

/// What a [Mutation] needs from an observer.
///
/// Exported because the cache's `MutationObserverAdded` and friends name
/// their observer through it; implementing it yourself is not supported —
/// `MutationObserver` is the one implementation, and the one member is
/// `@internal` there and here (ninth review, 2026-09-10, C21).
abstract interface class MutationObserverRef {
  /// The mutation's state changed by [action]. The observer recomputes its
  /// result and, for a success or error, runs the per-call callbacks.
  @internal
  void onMutationUpdate(MutationAction action);
}

/// What a [Mutation] needs from its cache.
abstract interface class MutationCacheRef {
  /// Told after every dispatch, with the [action] that produced [mutation]'s
  /// new state; the cache turns it into a `MutationUpdated` event.
  void onMutationStateUpdated(
    Mutation<Object?, Object?, Object?> mutation,
    MutationAction action,
  );

  /// Told when [mutation]'s collection timer fired with nothing observing it
  /// and the run settled; the cache removes it.
  void onMutationRemovalRequested(Mutation<Object?, Object?, Object?> mutation);

  /// Told when [observer] attached to [mutation]; the cache emits
  /// `MutationObserverAdded`.
  void onMutationObserverAdded(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  );

  /// Told when [observer] detached from [mutation]; the cache emits
  /// `MutationObserverRemoved`.
  void onMutationObserverRemoved(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  );

  /// Whether [mutation] may start or resume right now — `false` while another
  /// mutation in the same scope is pending. The retryer asks before every
  /// attempt.
  bool canRunMutation(Mutation<Object?, Object?, Object?> mutation);

  /// Told when [mutation]'s run has settled either way, so the cache can
  /// release the next paused mutation in the same scope.
  void onMutationSettled(Mutation<Object?, Object?, Object?> mutation);

  /// The cache-wide `onMutate` hook: runs before the mutation's own
  /// `onMutate`, with the [variables] the run was given.
  FutureOr<void> onMutationStarting(
    Mutation<Object?, Object?, Object?> mutation,
    Object? variables,
  );

  /// The cache-wide `onSuccess` hook: runs before the mutation's own
  /// `onSuccess`, with the [data], the [variables] and the [onMutateResult].
  FutureOr<void> onMutationSuccess(
    Mutation<Object?, Object?, Object?> mutation,
    Object? data,
    Object? variables,
    Object? onMutateResult,
  );

  /// The cache-wide `onError` hook: runs before the mutation's own `onError`,
  /// with the [error], the [variables] and the [onMutateResult].
  FutureOr<void> onMutationError(
    Mutation<Object?, Object?, Object?> mutation,
    Object error,
    StackTrace stackTrace,
    Object? variables,
    Object? onMutateResult,
  );

  /// The cache-wide `onSettled` hook: runs before the mutation's own
  /// `onSettled`, with whichever of [data] and [error] applies. Distinct from
  /// [onMutationSettled], which is the scope bookkeeping rather than a user
  /// callback.
  FutureOr<void> onMutationSettledCallback(
    Mutation<Object?, Object?, Object?> mutation,
    Object? data,
    Object? error,
    StackTrace? stackTrace,
    Object? variables,
    Object? onMutateResult,
  );
}

/// A state transition. Sealed, so the reducer is exhaustive.
///
/// Exported so that a cache listener can `switch` on the `action` a
/// `MutationUpdated` event carries — read-only from outside: only a
/// [Mutation] dispatches one.
@immutable
sealed class MutationAction {
  const MutationAction();
}

/// A run started. Replaces the whole state: status `pending`, the run's
/// [variables], a fresh `submittedAt`, and [isPaused] when the run cannot
/// start yet. Dispatched a second time once `onMutate` has produced a
/// result. Upstream's `pending` action.
final class MutationPendingAction extends MutationAction {
  /// Creates the action for a run of [variables].
  const MutationPendingAction({
    required this.variables,
    required this.onMutateResult,
    required this.isPaused,
  });

  /// What the mutation function is being called with.
  final Object? variables;

  /// What `onMutate` returned — `null` on the first dispatch, before it ran.
  final Object? onMutateResult;

  /// Whether the run is parked from the start: offline, backgrounded, or
  /// queued behind its scope.
  final bool isPaused;
}

/// The mutation function resolved and every success callback has run.
/// Status becomes `success` and the error and failure count are cleared.
/// Upstream's `success` action.
final class MutationSuccessAction extends MutationAction {
  /// Creates the action carrying [data].
  const MutationSuccessAction(this.data);

  /// What the mutation function returned.
  final Object? data;
}

/// The run failed for good and every error callback has run. Status becomes
/// `error`, the data is cleared, and the failure count is bumped one last
/// time. Upstream's `error` action.
final class MutationErrorAction extends MutationAction {
  /// Creates the action for the error that settled the run.
  const MutationErrorAction(this.error, this.stackTrace);

  /// What the run finally failed with.
  final Object error;

  /// Where it was thrown from.
  final StackTrace stackTrace;
}

/// One attempt failed and will be retried. Records the count and the reason;
/// status stays `pending`. Upstream's `failed` action.
final class MutationFailedAction extends MutationAction {
  /// Creates the action for the attempt that just failed.
  const MutationFailedAction(this.failureCount, this.error, this.stackTrace);

  /// How many attempts have failed so far in this run, including this one.
  final int failureCount;

  /// What the attempt threw.
  final Object error;

  /// Where it was thrown from.
  final StackTrace stackTrace;
}

/// The retryer suspended the run: offline, backgrounded, or blocked by its
/// scope. `isPaused` becomes true. Upstream's `pause` action.
final class MutationPauseAction extends MutationAction {
  /// Creates the action.
  const MutationPauseAction();
}

/// A paused run resumed — or a restored one was re-run. `isPaused` becomes
/// false. Upstream's `continue` action.
final class MutationContinueAction extends MutationAction {
  /// Creates the action.
  const MutationContinueAction();
}

/// A mutation's state at one point in time.
@immutable
final class MutationState<TData, TVariables, TOnMutateResult> {
  /// Creates a state; with no arguments, the idle state a fresh mutation
  /// starts in.
  const MutationState({
    this.status = MutationStatus.idle,
    this.hasData = false,
    this.data,
    this.error,
    this.errorStackTrace,
    this.variables,
    this.hasVariables = false,
    this.onMutateResult,
    this.failureCount = 0,
    this.failureReason,
    this.isPaused = false,
    this.submittedAt,
  });

  /// Where the mutation is in its life.
  final MutationStatus status;

  /// Whether [data] is authoritative. Travels with [data] so that a mutation
  /// whose function legitimately returned `null` still reads as having data.
  final bool hasData;

  /// What the last successful run returned; meaningful only while [hasData].
  final TData? data;

  /// Why the last run failed; `null` unless [status] is `error`.
  final Object? error;

  /// Where [error] was thrown from.
  final StackTrace? errorStackTrace;

  /// The variables of the run in flight or last finished — what optimistic UI
  /// reads while the mutation is pending.
  final TVariables? variables;

  /// Whether [variables] have been set by a run — a `null` variables value is
  /// a real value once this is true.
  final bool hasVariables;

  /// What `onMutate` returned for the run in flight or last finished; handed
  /// to the success, error and settled callbacks.
  final TOnMutateResult? onMutateResult;

  /// How many attempts of the current run have failed. Reset on success;
  /// bumped once more when the run settles in error.
  final int failureCount;

  /// What the last failed attempt threw, kept while retries continue.
  final Object? failureReason;

  /// Whether the run is parked, waiting for the network, the foreground, or
  /// its scope.
  final bool isPaused;

  /// When the current (or last) run was started.
  final DateTime? submittedAt;

  /// A copy with the given fields replaced. `null` leaves a field as it was;
  /// the `clear*` flags are how a field is set back to nothing.
  MutationState<TData, TVariables, TOnMutateResult> copyWith({
    MutationStatus? status,
    bool? hasData,
    TData? data,
    Object? error,
    StackTrace? errorStackTrace,
    TVariables? variables,
    bool? hasVariables,
    TOnMutateResult? onMutateResult,
    int? failureCount,
    Object? failureReason,
    bool? isPaused,
    DateTime? submittedAt,
    bool clearData = false,
    bool clearError = false,
    bool clearFailureReason = false,
  }) =>
      MutationState<TData, TVariables, TOnMutateResult>(
        status: status ?? this.status,
        hasData: clearData ? false : (hasData ?? this.hasData),
        // `data` and `hasData` travel together, as on `QueryState`: with
        // `hasData: true` the value is authoritative even when it is `null`.
        data: clearData ? null : (hasData == true ? data : (data ?? this.data)),
        error: clearError ? null : (error ?? this.error),
        errorStackTrace:
            clearError ? null : (errorStackTrace ?? this.errorStackTrace),
        variables: variables ?? this.variables,
        hasVariables: hasVariables ?? this.hasVariables,
        onMutateResult: onMutateResult ?? this.onMutateResult,
        failureCount: failureCount ?? this.failureCount,
        failureReason:
            clearFailureReason ? null : (failureReason ?? this.failureReason),
        isPaused: isPaused ?? this.isPaused,
        submittedAt: submittedAt ?? this.submittedAt,
      );

  // Value equality like `QueryState`'s: a persistence layer compares the
  // state it restored with the one it is about to write (fifth review,
  // 2026-09-09). `data` and `variables` by `==`, so typed models need their
  // own. `errorStackTrace` is left out, as `QueryState` leaves its traces
  // out: a stack trace never compares equal by value, so including it made
  // every rebuilt error state unequal to the one it copied (ninth review,
  // 2026-09-10, C23).
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MutationState<TData, TVariables, TOnMutateResult> &&
          other.status == status &&
          other.hasData == hasData &&
          other.data == data &&
          other.error == error &&
          other.variables == variables &&
          other.hasVariables == hasVariables &&
          other.onMutateResult == onMutateResult &&
          other.failureCount == failureCount &&
          other.failureReason == failureReason &&
          other.isPaused == isPaused &&
          other.submittedAt == submittedAt;

  @override
  int get hashCode => Object.hash(
        status,
        hasData,
        data,
        error,
        variables,
        hasVariables,
        onMutateResult,
        failureCount,
        failureReason,
        isPaused,
        submittedAt,
      );
}

/// One mutation: its options, its state, and one run of its mutation function.
class Mutation<TData, TVariables, TOnMutateResult> extends Removable {
  /// Creates a mutation for [options] with [mutationId], idle unless a
  /// restored [state] is given, and arms its collection timer straight away.
  /// Constructed by `MutationCache.build`; user code runs mutations through an
  /// observer.
  Mutation({
    required this.client,
    required MutationCacheRef cache,
    required this.mutationId,
    required DefaultedMutationOptions<TData, TVariables, TOnMutateResult>
        options,
    MutationState<TData, TVariables, TOnMutateResult>? state,
  })  : _cache = cache,
        _options = options,
        _state = state ?? MutationState<TData, TVariables, TOnMutateResult>() {
    updateGcTime(options.gcTime);
    scheduleGc();
  }

  /// The client this mutation belongs to: the source of its managers and its
  /// notify batching.
  final QueryClient client;
  final MutationCacheRef _cache;

  /// A number unique within the cache, in submission order. Upstream's
  /// `mutationId`; devtools use it to tell mutations apart.
  final int mutationId;

  DefaultedMutationOptions<TData, TVariables, TOnMutateResult> _options;

  /// The options in force, fully resolved. The mutation function and the retry
  /// settings are read from here per attempt, so an update during a run takes
  /// effect on the next one.
  DefaultedMutationOptions<TData, TVariables, TOnMutateResult> get options =>
      _options;

  MutationState<TData, TVariables, TOnMutateResult> _state;

  /// The current state. Replaced on every dispatch; observers compute their
  /// results from it.
  MutationState<TData, TVariables, TOnMutateResult> get state => _state;

  final List<MutationObserverRef> _observers = <MutationObserverRef>[];

  /// The observers attached right now, read-only; [addObserver] and
  /// [removeObserver] are the only way in and out.
  List<MutationObserverRef> get observers =>
      UnmodifiableListView<MutationObserverRef>(_observers);

  Retryer<TData>? _retryer;

  /// This mutation with its type arguments erased, the shape the cache
  /// speaks.
  Mutation<Object?, Object?, Object?> get _erased =>
      this as Mutation<Object?, Object?, Object?>;

  MutationScope? _runScope;
  bool _hasRunScope = false;

  /// The scope this mutation is queued and released under.
  ///
  /// Captured when [execute] starts and kept for the whole run: a
  /// `setOptions` that changes `scope` while the mutation is running does
  /// not move it. Adopting the new scope did — `onMutationSettled` then woke
  /// the next mutation in the *new* scope and left the one waiting in the
  /// old scope `pending` for good (fifth review, 2026-09-09). Before the
  /// first run, and for a restored mutation that has not been continued yet,
  /// it is the options' scope.
  @internal
  MutationScope? get schedulingScope =>
      _hasRunScope ? _runScope : _options.scope;

  /// The options' `meta`, as upstream exposes it on the mutation for cache
  /// listeners and devtools.
  Object? get meta => _options.meta;

  /// Replaces the options and folds their `gcTime` in. Called by an observer
  /// whose options changed while this mutation is still pending; not for user
  /// code.
  @internal
  void setOptions(
    DefaultedMutationOptions<TData, TVariables, TOnMutateResult> options,
  ) {
    _options = options;
    updateGcTime(options.gcTime);
  }

  /// Attaches [observer], cancelling the pending collection and emitting
  /// `MutationObserverAdded`. Attaching twice is a no-op. Called by the
  /// observer; not for user code.
  @internal
  void addObserver(MutationObserverRef observer) {
    if (!_observers.contains(observer)) {
      _observers.add(observer);
      clearGcTimeout();
      _cache.onMutationObserverAdded(_erased, observer);
    }
  }

  /// Detaches [observer], emits `MutationObserverRemoved` and arms the
  /// collection timer. The run is never cut short — a pending mutation keeps
  /// going, callbacks included, and is only collected once it settles. Called
  /// by the observer; not for user code.
  @internal
  void removeObserver(MutationObserverRef observer) {
    if (!_observers.remove(observer)) {
      return;
    }
    _cache.onMutationObserverRemoved(_erased, observer);
    // Never removed on the spot: an unmounted widget must not cut a mutation's
    // callbacks short. The gc timer decides, and `optionalRemove` lets a
    // pending one keep going.
    scheduleGc();
  }

  @override
  void optionalRemove() {
    if (_observers.isNotEmpty) {
      return;
    }
    if (_state.status == MutationStatus.pending) {
      // Still running: leave it alone. `execute` schedules the next collection
      // when it settles, which is why this does not re-arm the timer itself —
      // with `gcTime: Duration.zero` that would spin forever.
      return;
    }
    _cache.onMutationRemovalRequested(this);
  }

  /// Releases a paused mutation, completing when it settles — or rejecting
  /// with the error it settled on, as upstream's `continue()` does. The cache's
  /// `resumePaused` is the caller that swallows it; a direct caller who does
  /// not want the error `.ignore()`s the future.
  ///
  /// "Settles" is the run: the future is [execute]'s own, so the success (or
  /// error) and settled callbacks have run and the state has moved on when it
  /// completes — what `resumePausedMutations` promises, and what a mounted
  /// client's reconnect refetch relies on to run *after* an `onSuccess` cache
  /// write. It used to be the retryer's transport future, which completes
  /// before the first callback is called (ninth review, 2026-09-10, C10).
  ///
  /// A mutation restored from persistence is `pending` with no retryer at all;
  /// continuing it means running it, which is how an offline mutation survives
  /// a restart. It runs with the variables it was restored with — `null`
  /// included, when `null` is a `TVariables`: a `void`-variables mutation is
  /// naturally restored with `hasVariables: false`, and was never continued
  /// (ninth review, 2026-09-10, C12). Only a non-nullable `TVariables` with no
  /// variables at all is left alone — there is nothing to run it with, and
  /// `MutationCache.build(state:)` refuses such a state at the persistence
  /// door, so it reaches here only on a mutation built by hand and `add`ed. A
  /// settled one has nothing to continue and must never run twice.
  Future<void> continueMutation() {
    final retryer = _retryer;
    if (retryer != null) {
      // Release the pause; the run's own future says when it has settled.
      retryer.continueFetch().ignore();
      return _execution?.then<void>((_) {}) ?? Future<void>.value();
    }
    if (_state.status == MutationStatus.pending &&
        (_state.hasVariables || null is TVariables)) {
      return execute(_state.variables as TVariables).then((_) {});
    }
    return Future<void>.value();
  }

  // The future of the run in flight — `execute`'s, which settles after the
  // callbacks — for `continueMutation` to hand on. Set alongside `_retryer`
  // and cleared with it.
  Future<TData>? _execution;

  /// Whether the network lets [continueMutation] get anywhere right now — the
  /// rule the cache's `resumePaused` applies before awaiting a paused
  /// mutation.
  ///
  /// A run with a retryer continues under the retryer's network rule
  /// ([canContinue]: online unless `always`); a restored run, which has no
  /// retryer until it is executed, starts under the start rule ([canFetch]).
  /// The two differ for `offlineFirst`: it may begin offline but not retry
  /// offline. Gating on the start rule alone let `resumePaused` await an
  /// `offlineFirst` retry that nothing offline could release, and every focus
  /// refetch behind it. Only the network is asked: a pause for focus or for
  /// the scope's turn is released by the focus listener or the scope-mate's
  /// settling, so awaiting it is safe — and upstream's ordering, a mutation
  /// before the refetch that should reflect it, depends on the scope case
  /// being awaited (ninth review, 2026-09-10, C4).
  @internal
  bool get canResume => _retryer != null
      ? canContinue(_options.networkMode, client.onlineManager)
      : canFetch(_options.networkMode, client.onlineManager);

  /// Cancels the pending collection, and stops this mutation re-arming one.
  ///
  /// Called by the cache when the mutation is removed; user code removes a
  /// mutation through `MutationCache.remove`. Upstream leaves the timer
  /// running — in a browser nobody notices a stray `setTimeout`, but
  /// Flutter's own widget tests assert that no timer outlives the tree, and a
  /// removed mutation has nothing left to be collected from.
  @internal
  @override
  void destroy() {
    _removed = true;
    super.destroy();
    // A mutation the cache dropped has nothing left to retry for. Upstream
    // leaves the retryer running — `RetryPolicy.always` would keep hitting
    // the server after `clear()`, and its backoff timer would outlive the
    // cache. The in-flight attempt still settles; a backoff in progress is
    // cut short and the mutation fails with the error it last saw; a paused
    // one fails with a `CancelledError` on the spot. Failing means the error
    // callbacks run, a few microtasks after the removal — so a `clear()`
    // that drops an offline-paused optimistic mutation is followed by its
    // `onError` rollback, writing into the cache `clear()` just emptied
    // (ninth review, 2026-09-10, C11; see `QueryClient.clear`).
    _retryer?.cancelRetry(immediately: true);
  }

  bool _removed = false;

  @override
  void scheduleGc() {
    if (_removed) {
      return;
    }
    super.scheduleGc();
  }

  /// Runs [body], reporting anything it throws to the zone instead of letting
  /// it replace the error already on its way to the caller.
  static Future<void> _reportingFailures(FutureOr<void> Function() body) async {
    try {
      await body();
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  /// Runs the mutation function once, with everything around it. Completes
  /// after the callbacks have run and the settled state is dispatched.
  Future<TData> execute(TVariables variables) {
    // `_run` builds the retryer before its first `await`, so by the time it
    // hands its future back the run is already the current one.
    final run = _run(variables);
    _execution = run;
    return run;
  }

  Future<TData> _run(TVariables variables) async {
    // The scope is fixed for this run; see `schedulingScope`.
    _runScope = _options.scope;
    _hasRunScope = true;

    // The retryer exists before the first `await`, exactly as upstream builds
    // it: a mutation that pauses while its `onMutate` is still running must
    // still be resumable, and `continueMutation` has nothing to continue
    // without it.
    final retryer = Retryer<TData>(
      // Resolved per attempt, not once: `setOptions` on a running mutation
      // replaces the function, and a retry must call the replacement. A
      // missing function fails *inside* the attempt, so that it reaches the
      // error state and the callbacks like any other failure would.
      fn: () async {
        final mutationFn = _options.mutationFn;
        if (mutationFn == null) {
          throw MissingMutationFunctionError(_options.mutationKey);
        }
        return mutationFn(variables);
      },
      focusManager: client.focusManager,
      onlineManager: client.onlineManager,
      canRun: () => _cache.canRunMutation(_erased),
      // A missing function is a configuration error, and retrying it only
      // delays the message by the whole backoff — the same answer the query
      // side has given since the fourth review. Decided by what the options
      // hold now: a `setMutationDefaults` between attempts could supply one,
      // but a caller waiting 30 seconds to be told the function was never
      // there is the certain cost against that unlikely benefit (eighth
      // review, 2026-09-10).
      retry: _options.mutationFn == null ? RetryPolicy.never : _options.retry,
      retryDelay: _options.retryDelay,
      networkMode: _options.networkMode,
      onFail: (failureCount, error, stackTrace) =>
          _dispatch(MutationFailedAction(failureCount, error, stackTrace)),
      onPause: () => _dispatch(const MutationPauseAction()),
      onContinue: () => _dispatch(const MutationContinueAction()),
    );
    _retryer = retryer;
    // Removed from the cache before this run began — from inside the
    // `MutationAdded` event, say — `destroy` found no retryer to stop, and
    // the run it is about to make would otherwise retry with its full policy
    // or, paused offline, park for good. The same cancel `destroy` applies,
    // now that there is something to apply it to: one attempt at most, and a
    // pause rejects on the spot (ninth review, 2026-09-10, C5).
    if (_removed) {
      retryer.cancelRetry(immediately: true);
    }

    final isRestart = _state.status == MutationStatus.pending;
    TOnMutateResult? onMutateResult = _state.onMutateResult;

    try {
      if (isRestart) {
        // A restored mutation is `pending` and paused; running it again is what
        // unpauses it, and nothing else would clear the flag.
        _dispatch(const MutationContinueAction());
      } else {
        _dispatch(
          MutationPendingAction(
            variables: variables,
            onMutateResult: null,
            isPaused: !retryer.canStart(),
          ),
        );

        // Awaited only when there is something to await: with no cache-level
        // `onMutate`, the per-mutation one has to run synchronously, so that a
        // caller can read the optimistic state it wrote on the next line.
        final starting = _cache.onMutationStarting(_erased, variables);
        if (starting is Future<void>) {
          await starting;
        }

        final mutating = _options.onMutate?.call(variables);
        // `Future<TOnMutateResult?>`, not `Future<TOnMutateResult>`: the
        // callback's declared type is `FutureOr<TOnMutateResult?>`, and an
        // `async` callback that can return null produces the nullable future,
        // which the non-nullable check would let fall through to the cast.
        if (mutating is Future<TOnMutateResult?>) {
          onMutateResult = await mutating;
        } else {
          onMutateResult = mutating;
        }

        if (onMutateResult != _state.onMutateResult) {
          _dispatch(
            MutationPendingAction(
              variables: variables,
              onMutateResult: onMutateResult,
              isPaused: !retryer.canStart(),
            ),
          );
        }
      }

      final data = await retryer.start();

      // Cache hook then per-mutation hook, for each of success and settled —
      // interleaved exactly as upstream runs them, so a global handler can set
      // something up that the local one consumes.
      await _cache.onMutationSuccess(_erased, data, variables, onMutateResult);
      await _options.onSuccess?.call(data, variables, onMutateResult);
      await _cache.onMutationSettledCallback(
        _erased,
        data,
        null,
        null,
        variables,
        onMutateResult,
      );
      await _options.onSettled?.call(
        data,
        null,
        null,
        variables,
        onMutateResult,
      );

      _dispatch(MutationSuccessAction(data));
      return data;
    } catch (error, stackTrace) {
      // Each callback is isolated: one that throws reports its own failure to
      // the zone and is not allowed to replace the error the caller is waiting
      // for. Upstream does the same with `void Promise.reject(e)`.
      await _reportingFailures(
        () => _cache.onMutationError(
          _erased,
          error,
          stackTrace,
          variables,
          onMutateResult,
        ),
      );
      await _reportingFailures(
        () => _options.onError?.call(
          error,
          stackTrace,
          variables,
          onMutateResult,
        ),
      );
      await _reportingFailures(
        () => _cache.onMutationSettledCallback(
          _erased,
          null,
          error,
          stackTrace,
          variables,
          onMutateResult,
        ),
      );
      await _reportingFailures(
        () => _options.onSettled?.call(
          null,
          error,
          stackTrace,
          variables,
          onMutateResult,
        ),
      );
      _dispatch(MutationErrorAction(error, stackTrace));
      rethrow;
    } finally {
      _cache.onMutationSettled(_erased);
      if (identical(_retryer, retryer)) {
        _retryer = null;
        _execution = null;
      }
      // Only when nobody is watching: `optionalRemove` leaves a pending
      // mutation alone (re-arming there would spin on `gcTime: 0`), so a
      // mutation that settles unobserved has to arm its own collection. With
      // an observer attached, `removeObserver` arms it when that observer
      // leaves — and a timer standing while a widget is mounted is exactly
      // what Flutter's widget tests assert against (fourth review,
      // 2026-09-09).
      if (_observers.isEmpty) {
        scheduleGc();
      }
    }
  }

  void _dispatch(MutationAction action) {
    _state = _reduce(_state, action);

    client.notifyManager.batch(() {
      for (final observer in List<MutationObserverRef>.of(_observers)) {
        observer.onMutationUpdate(action);
      }
      _cache.onMutationStateUpdated(_erased, action);
    });
  }

  MutationState<TData, TVariables, TOnMutateResult> _reduce(
    MutationState<TData, TVariables, TOnMutateResult> state,
    MutationAction action,
  ) =>
      switch (action) {
        MutationFailedAction(:final failureCount, :final error) =>
          state.copyWith(
            failureCount: failureCount,
            failureReason: error,
          ),
        MutationPauseAction() => state.copyWith(isPaused: true),
        MutationContinueAction() => state.copyWith(isPaused: false),
        MutationPendingAction(
          :final variables,
          :final onMutateResult,
          :final isPaused,
        ) =>
          MutationState<TData, TVariables, TOnMutateResult>(
            status: MutationStatus.pending,
            variables: variables as TVariables?,
            hasVariables: true,
            onMutateResult: onMutateResult as TOnMutateResult?,
            isPaused: isPaused,
            submittedAt: clock.now(),
          ),
        MutationSuccessAction(:final data) => state.copyWith(
            status: MutationStatus.success,
            hasData: true,
            data: data as TData?,
            failureCount: 0,
            isPaused: false,
            clearError: true,
            clearFailureReason: true,
          ),
        MutationErrorAction(:final error, :final stackTrace) => state.copyWith(
            status: MutationStatus.error,
            // Upstream's `data: undefined`.
            clearData: true,
            error: error,
            errorStackTrace: stackTrace,
            failureCount: state.failureCount + 1,
            failureReason: error,
            isPaused: false,
          ),
      };

  @override
  String toString() => 'Mutation($mutationId, ${_state.status})';
}

/// Thrown when a mutation runs without a `mutationFn`.
final class MissingMutationFunctionError implements Exception {
  /// Creates the error for [mutationKey], which may be `null` for an unkeyed
  /// mutation.
  const MissingMutationFunctionError(this.mutationKey);

  /// The key of the mutation that had no function to run, if it had one.
  final QueryKey? mutationKey;

  @override
  String toString() => 'No mutationFn was provided'
      '${mutationKey == null ? '' : ' for $mutationKey'}. Pass one in the '
      'mutation options, or set a default with '
      'QueryClient.setMutationDefaults.';
}
