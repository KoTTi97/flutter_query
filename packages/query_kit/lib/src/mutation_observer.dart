/// Port of `query-core/src/mutationObserver.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'mutation.dart';
import 'mutation_options.dart';
import 'mutation_result.dart';
import 'query_client.dart';

/// What a [MutationObserver.subscribe] listener receives: the new
/// [MutationResult], each time it changes.
typedef MutationObserverListener<TData, TVariables> = void Function(
    MutationResult<TData, TVariables> result);

/// Watches one mutation at a time and turns its state into a
/// [MutationResult].
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
  // parameters.
  final List<MutationObserverListener<TData, TVariables>> _listeners =
      <MutationObserverListener<TData, TVariables>>[];

  /// Whether anyone is subscribed. Per-call callbacks only run while this is
  /// true — a `mutate` from a widget that has since gone must not call back
  /// into it.
  bool get hasListeners => _listeners.isNotEmpty;

  /// Registers [listener] and returns the function that removes it again. The
  /// first listener re-attaches the observer to the mutation it was watching
  /// and brings the result up to date; the last one leaving detaches it, which
  /// starts the mutation's `gcTime` clock.
  void Function() subscribe(
      MutationObserverListener<TData, TVariables> listener) {
    _listeners.add(listener);
    if (_listeners.length == 1) {
      // Re-attaching after an unsubscribe: the mutation may have moved on, or
      // even settled, while nobody was watching.
      final mutation = _currentMutation;
      if (mutation != null) {
        mutation.addObserver(this);
        _updateResult(mutation.state);
      }
    }
    return () {
      _listeners.remove(listener);
      if (!hasListeners) {
        _currentMutation?.removeObserver(this);
      }
    };
  }

  late DefaultedMutationOptions<TData, TVariables, TOnMutateResult> _options;

  /// The options in force, fully resolved against the client's defaults.
  DefaultedMutationOptions<TData, TVariables, TOnMutateResult> get options =>
      _options;

  Mutation<TData, TVariables, TOnMutateResult>? _currentMutation;
  late MutationResult<TData, TVariables> _currentResult;
  MutateCallbacks<TData, TVariables, TOnMutateResult>? _callCallbacks;

  /// The most recently computed result — idle until the first `mutate`, then
  /// whatever the observed mutation's state maps to.
  MutationResult<TData, TVariables> get currentResult => _currentResult;

  /// Replaces the options, resolving them against the client's defaults. A
  /// changed `mutationKey` means a different mutation, so the observer
  /// [reset]s; otherwise a mutation still in flight takes the new options and
  /// a settled one keeps the ones it ran with.
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

  /// Fire and forget. Errors reach the callbacks and the result, never the
  /// zone — an unawaited failing future would otherwise fail the enclosing
  /// test file.
  void mutate(
    TVariables variables, {
    MutateCallbacks<TData, TVariables, TOnMutateResult>? callbacks,
  }) {
    mutateAsync(variables, callbacks: callbacks).ignore();
  }

  /// Completes with the data, or throws.
  Future<TData> mutateAsync(
    TVariables variables, {
    MutateCallbacks<TData, TVariables, TOnMutateResult>? callbacks,
  }) {
    _callCallbacks = callbacks;

    _currentMutation?.removeObserver(this);
    final mutation = _client.mutationCache
        .build<TData, TVariables, TOnMutateResult>(_client, _options);
    _currentMutation = mutation;
    mutation.addObserver(this);

    return mutation.execute(variables);
  }

  /// Detaches from the mutation being observed and goes back to idle.
  ///
  /// The mutation itself keeps running and still fires its own callbacks; this
  /// observer just stops reflecting it, and the next `mutate` builds a new one.
  void reset() {
    _currentMutation?.removeObserver(this);
    _currentMutation = null;
    _updateResult(MutationState<TData, TVariables, TOnMutateResult>());
  }

  /// Stops observing for good: drops every listener and leaves the mutation,
  /// which starts its `gcTime` clock.
  ///
  /// Upstream has no counterpart — a React observer is simply forgotten — but
  /// a binding that owns the observer's lifetime needs a way to say so, or a
  /// mutation that ran without listeners keeps an observer nobody will ever
  /// remove and can never be collected.
  void destroy() {
    _listeners.clear();
    _currentMutation?.removeObserver(this);
    _currentMutation = null;
  }

  @override
  void onMutationUpdate(MutationAction action) {
    final mutation = _currentMutation;
    if (mutation == null) {
      return;
    }
    final state = mutation.state;
    final next = _createResult(state.status, state);
    final changed = next != _currentResult;
    _currentResult = next;

    // Per-call callbacks first, then the listeners — upstream's order, and it
    // matters: a listener may start the next mutation from inside its
    // notification, which replaces `_callCallbacks`. Running the callbacks
    // afterwards would hand this mutation's result to the *next* call's
    // `onSuccess`.
    _client.notifyManager.batch(() {
      _notifyCallCallbacks(action, state);
      if (changed) {
        _notifyListeners();
      }
    });
  }

  /// Each listener is isolated, as the query observer's are: a throw is
  /// reported to the zone, and the rest still run. Unisolated, a listener
  /// throwing on a `failed` action escaped into the retryer's loop, and one
  /// throwing on `success` turned the success into the error path.
  void _notifyListeners() {
    for (final listener in List.of(_listeners)) {
      try {
        listener(_currentResult);
      } catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }
    }
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
  /// with it: the failure goes to the zone, as upstream re-throws it into a
  /// fresh execution context.
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
