/// The mutation observer: runs mutations and reports their results.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'listener_registry.dart';
import 'mutation.dart';
import 'mutation_options.dart';
import 'mutation_result.dart';
import 'query_client.dart';

/// What a [MutationObserver.subscribe] listener receives: the new
/// [MutationResult], each time it changes.
///
/// {@category Observers}
typedef MutationObserverListener<TData, TVariables> = void Function(
    MutationResult<TData, TVariables> result);

/// Runs mutations and reports the latest one's state as a [MutationResult].
///
/// This is the pure-Dart entry point for writes; the Flutter binding wraps
/// one for its widgets. The lifecycle:
///
/// * **Create** it with the client and the [MutationOptions]. It starts
///   idle; nothing runs yet.
/// * **Subscribe** to hear each new result; [currentResult] holds the
///   latest one at any time.
/// * **[mutate]** (fire and forget) or **[mutateAsync]** (a future of the
///   data) starts a run with the given variables, optionally with
///   per-call [MutateCallbacks]. Each call builds a new mutation in the
///   cache, and the observer follows the newest one.
/// * **[reset]** goes back to idle, **[cancel]** fails the run in flight,
///   and [setOptions] swaps the options (a rebuild's new callbacks, say).
/// * **Unsubscribe** and **[destroy]** when done. A mutation already running
///   finishes on its own and is collected after its `gcTime`.
///
/// ```dart
/// final observer = MutationObserver<Todo, String, void>(
///   client,
///   MutationOptions(
///     mutationFn: (String title) => api.addTodo(title),
///     onSuccess: (todo, title, _) => client.invalidateQueries(
///         filters: QueryFilters(queryKey: QueryKey(['todos']))),
///   ),
/// );
/// final unsubscribe = observer.subscribe((result) => print(result.status));
/// observer.mutate('Buy milk');
/// // Later:
/// unsubscribe();
/// observer.destroy();
/// ```
///
/// {@category Observers}
class MutationObserver<TData, TVariables, TOnMutateResult>
    implements MutationObserverRef {
  /// Creates an idle observer for [options], resolved against the client's
  /// defaults. Nothing runs until [mutate] or [mutateAsync] is called.
  MutationObserver(
    this._client,
    MutationOptions<TData, TVariables, TOnMutateResult> options,
  ) {
    setOptions(options);
    _currentResult = _createResult(
      const MutationState<Never, Never, Never>().status,
      MutationState<TData, TVariables, TOnMutateResult>(),
    );
  }

  final QueryClient _client;

  // See the note in QueryObserver: Dart's variance rules stop an observer from
  // extending `Subscribable` with a listener type that mentions its own type
  // parameters, so it holds the same registry as a field instead.
  final ListenerRegistry<MutationObserverListener<TData, TVariables>>
      _listeners =
      ListenerRegistry<MutationObserverListener<TData, TVariables>>();

  /// Whether anyone is subscribed. Per-call callbacks only run while this is
  /// true — a `mutate` from a widget that has since gone must not call back
  /// into it.
  bool get hasListeners => _listeners.hasListeners;

  /// Registers [listener] and returns the function that removes it again. The
  /// first listener re-attaches the observer to the mutation it was watching
  /// and brings the result up to date; the last one leaving detaches it, which
  /// starts the mutation's `gcTime` clock.
  void Function() subscribe(
      MutationObserverListener<TData, TVariables> listener) {
    // Once only, as the query observer's handles — see [ListenerRegistry].
    final remove = _listeners.add(listener, onRemoved: () {
      if (!hasListeners) {
        _currentMutation?.removeObserver(this);
      }
    });
    if (_listeners.length == 1) {
      // Re-attaching after an unsubscribe: the mutation may have moved on, or
      // even settled, while nobody was watching.
      final mutation = _currentMutation;
      if (mutation != null) {
        final invocation = _invocation;
        mutation.addObserver(this);
        if (invocation == _invocation &&
            identical(_currentMutation, mutation) &&
            hasListeners) {
          _updateResult(mutation.state);
        }
      }
    }
    return remove;
  }

  late DefaultedMutationOptions<TData, TVariables, TOnMutateResult> _options;

  /// The options in force, fully resolved against the client's defaults.
  DefaultedMutationOptions<TData, TVariables, TOnMutateResult> get options =>
      _options;

  Mutation<TData, TVariables, TOnMutateResult>? _currentMutation;
  late MutationResult<TData, TVariables> _currentResult;
  MutateCallbacks<TData, TVariables, TOnMutateResult>? _callCallbacks;
  int _invocation = 0;
  int _resultRevision = 0;

  /// The most recently computed result — idle until the first `mutate`, then
  /// whatever the observed mutation's state maps to.
  MutationResult<TData, TVariables> get currentResult => _currentResult;

  /// Replaces the options, resolving them against the client's defaults. A
  /// changed `mutationKey` means a different mutation, so the observer
  /// [reset]s; otherwise a mutation still in flight takes the new options and
  /// a settled one keeps the ones it ran with.
  ///
  /// What an in-flight run takes: its callbacks, `meta` and `gcTime`, and a
  /// retry calls the new mutation function. Its `retry`, `retryDelay`,
  /// `networkMode` and `scope` were fixed when it started and stay so.
  void setOptions(
    MutationOptions<TData, TVariables, TOnMutateResult> options,
  ) {
    final prevOptions = _hasOptions ? _options : null;
    _options = _client
        .defaultMutationOptions<TData, TVariables, TOnMutateResult>(options);
    _hasOptions = true;

    // Upstream reports this event with `mutation: undefined` when the observer
    // has never run one; an event about no mutation is not actionable, so it is
    // simply not sent.
    final observed = _currentMutation;
    if (observed != null && _options != prevOptions) {
      _client.mutationCache.notifyObserverOptionsUpdated(
        observed as Mutation<Object?, Object?, Object?>,
        this,
      );
    }

    final previousKey = prevOptions?.mutationKey;
    final nextKey = _options.mutationKey;
    if (previousKey != null && nextKey != null && previousKey != nextKey) {
      // A different key means a different mutation: there is no way back to the
      // old one, so the observer starts over.
      reset();
    } else if (_currentMutation?.state.status == MutationStatus.pending) {
      // Only a mutation still in flight takes new options; a settled one keeps
      // the ones it ran with, which is what its recorded `meta` means.
      _currentMutation?.setOptions(_options);
    }
  }

  bool _hasOptions = false;

  void _mutate(TVariables variables) => mutate(variables);

  /// Starts a run with [variables] and returns at once. Errors reach the
  /// callbacks and the result, never the zone — an unawaited failing future
  /// would otherwise surface as an uncaught error. [callbacks] are the
  /// per-call callbacks for this run only.
  ///
  /// `onMutate` runs now, even for a mutation that then waits its turn in a
  /// `MutationScope`; only the mutation function waits. The result stays
  /// `pending` until the cache's and the options' callbacks have run and
  /// `onSettled`'s future has completed — see `MutationScope`; [callbacks]
  /// run after that.
  void mutate(
    TVariables variables, {
    MutateCallbacks<TData, TVariables, TOnMutateResult>? callbacks,
  }) {
    mutateAsync(variables, callbacks: callbacks).ignore();
  }

  /// Starts a run with [variables] and completes with the data, or throws
  /// the error — after the callbacks have run, as [mutate]'s result
  /// settles. The same order applies: `onMutate` at submission, the function
  /// in its scope's turn. Use it when the caller must await the write;
  /// otherwise prefer [mutate].
  Future<TData> mutateAsync(
    TVariables variables, {
    MutateCallbacks<TData, TVariables, TOnMutateResult>? callbacks,
  }) {
    final invocation = ++_invocation;
    final options = _options;
    final previous = _currentMutation;
    _currentMutation = null;
    _callCallbacks = null;
    previous?.removeObserver(this);
    final mutation = _client.mutationCache
        .build<TData, TVariables, TOnMutateResult>(_client, options);
    if (invocation == _invocation) {
      _currentMutation = mutation;
      _callCallbacks = callbacks;
      mutation.addObserver(this);
      if (invocation != _invocation) mutation.removeObserver(this);
    }

    return mutation.execute(variables);
  }

  /// Cancels the run this observer is showing — see [Mutation.cancel]: it
  /// fails with a `CancelledError`, its error callbacks run, and this observer
  /// shows that. Earlier runs this observer has moved on from are not touched,
  /// and with nothing running this does nothing.
  void cancel() => _currentMutation?.cancel();

  /// Detaches from the mutation being observed and goes back to idle.
  ///
  /// The mutation itself keeps running and still fires its own callbacks; this
  /// observer just stops reflecting it, and the next `mutate` builds a new one.
  void reset() {
    final invocation = ++_invocation;
    final previous = _currentMutation;
    _currentMutation = null;
    _callCallbacks = null;
    previous?.removeObserver(this);
    if (invocation == _invocation) {
      _updateResult(MutationState<TData, TVariables, TOnMutateResult>());
    }
  }

  /// Stops observing for good: drops every listener and leaves the mutation,
  /// which starts its `gcTime` clock. Call it when whatever owns the
  /// observer goes away; without it, a mutation that ran without listeners
  /// keeps an observer nobody will ever remove and can never be collected.
  /// (TanStack Query has no counterpart; a JavaScript observer is simply
  /// forgotten.)
  void destroy() {
    _invocation++;
    _resultRevision++;
    _listeners.clear();
    final previous = _currentMutation;
    _currentMutation = null;
    _callCallbacks = null;
    previous?.removeObserver(this);
  }

  @override
  @internal
  void onMutationUpdate(MutationAction action) {
    final mutation = _currentMutation;
    if (mutation == null) {
      return;
    }
    final state = mutation.state;
    final next = _createResult(state.status, state);
    final changed = next != _currentResult;
    _currentResult = next;
    final revision = ++_resultRevision;

    // Per-call callbacks first, then the listeners — upstream's order, and it
    // matters: a listener may start the next mutation from inside its
    // notification, which replaces `_callCallbacks`. Running the callbacks
    // afterwards would hand this mutation's result to the *next* call's
    // `onSuccess`.
    _client.notifyManager.batch(() {
      _notifyCallCallbacks(action, state);
      if (changed && revision == _resultRevision) {
        _notifyListeners();
      }
    });
  }

  /// Each listener is isolated, as the query observer's are: a throw is
  /// reported to the zone, and the rest still run. Unisolated, a listener
  /// throwing on a `failed` action escaped into the retryer's loop, and one
  /// throwing on `success` turned the success into the error path.
  void _notifyListeners() {
    final revision = _resultRevision;
    final result = _currentResult;
    _listeners.notify((listener) {
      if (revision == _resultRevision) listener(result);
    });
  }

  void _notifyCallCallbacks(
    MutationAction action,
    MutationState<TData, TVariables, TOnMutateResult> state,
  ) {
    final callbacks = _callCallbacks;
    // Per-call callbacks belong to a live subscription: a `mutate` whose widget
    // is already gone must still update the cache, but must not call back into
    // it. Upstream gates them on `hasListeners()` for the same reason.
    if (callbacks == null || !hasListeners || !state.hasVariables) {
      return;
    }
    final variables = state.variables as TVariables;

    switch (action) {
      case MutationSuccessAction(:final data):
        final typed = data as TData;
        _reporting(() =>
            callbacks.onSuccess?.call(typed, variables, state.onMutateResult));
        _reporting(
          () => callbacks.onSettled?.call(
            typed,
            null,
            null,
            variables,
            state.onMutateResult,
          ),
        );
      case MutationErrorAction(:final error, :final stackTrace):
        _reporting(
          () => callbacks.onError?.call(
            error,
            stackTrace,
            variables,
            state.onMutateResult,
          ),
        );
        _reporting(
          () => callbacks.onSettled?.call(
            null,
            error,
            stackTrace,
            variables,
            state.onMutateResult,
          ),
        );
      default:
        break;
    }
  }

  /// A per-call callback that throws must not take the caller's future down
  /// with it: the failure goes to the zone instead.
  static void _reporting(FutureOr<void> Function() body) {
    try {
      final result = body();
      if (result is Future<void>) {
        result.catchError(Zone.current.handleUncaughtError);
      }
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  void _updateResult(
    MutationState<TData, TVariables, TOnMutateResult> state,
  ) {
    final next = _createResult(state.status, state);
    if (next == _currentResult) {
      return;
    }
    _currentResult = next;
    _resultRevision++;

    _client.notifyManager.batch(_notifyListeners);
  }

  MutationResult<TData, TVariables> _createResult(
    MutationStatus status,
    MutationState<TData, TVariables, TOnMutateResult> state,
  ) {
    switch (status) {
      case MutationStatus.idle:
        return MutationIdle<TData, TVariables>(
          variables: state.variables,
          hasVariables: state.hasVariables,
          failureCount: state.failureCount,
          failureReason: state.failureReason,
          isPaused: state.isPaused,
          submittedAt: state.submittedAt,
          mutate: _mutate,
          mutateAsync: mutateAsync,
          reset: reset,
        );
      case MutationStatus.pending:
        return MutationPending<TData, TVariables>(
          variables: state.variables,
          hasVariables: state.hasVariables,
          failureCount: state.failureCount,
          failureReason: state.failureReason,
          isPaused: state.isPaused,
          submittedAt: state.submittedAt,
          mutate: _mutate,
          mutateAsync: mutateAsync,
          reset: reset,
        );
      case MutationStatus.success:
        return MutationSuccess<TData, TVariables>(
          data: state.data as TData,
          variables: state.variables,
          hasVariables: state.hasVariables,
          failureCount: state.failureCount,
          failureReason: state.failureReason,
          isPaused: state.isPaused,
          submittedAt: state.submittedAt,
          mutate: _mutate,
          mutateAsync: mutateAsync,
          reset: reset,
        );
      case MutationStatus.error:
        return MutationError<TData, TVariables>(
          error: state.error ?? StateError('mutation is in an error state'),
          stackTrace: state.errorStackTrace ?? StackTrace.empty,
          variables: state.variables,
          hasVariables: state.hasVariables,
          failureCount: state.failureCount,
          failureReason: state.failureReason,
          isPaused: state.isPaused,
          submittedAt: state.submittedAt,
          mutate: _mutate,
          mutateAsync: mutateAsync,
          reset: reset,
        );
    }
  }
}
