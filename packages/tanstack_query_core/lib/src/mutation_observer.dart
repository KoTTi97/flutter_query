/// Port of `query-core/src/mutationObserver.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'mutation.dart';
import 'mutation_options.dart';
import 'mutation_result.dart';
import 'query_client.dart';

typedef MutationObserverListener<TData, TVariables> = void Function(
    MutationResult<TData, TVariables> result);

/// Watches one mutation at a time and turns its state into a
/// [MutationResult].
class MutationObserver<TData, TVariables, TOnMutateResult>
    implements MutationObserverRef {
  MutationObserver(
    this._client,
    MutationOptions<TData, TVariables, TOnMutateResult> options,
  ) {
    _options = _client
        .defaultMutationOptions<TData, TVariables, TOnMutateResult>(options);
    _currentResult = _createResult(
      const MutationState<Never, Never, Never>().status,
      MutationState<TData, TVariables, TOnMutateResult>(),
    );
  }

  final QueryClient _client;

  // See the note in QueryObserver: Dart's variance rules stop an observer from
  // extending `Subscribable` with a listener type that mentions its own type
  // parameters.
  final List<MutationObserverListener<TData, TVariables>> listeners =
      <MutationObserverListener<TData, TVariables>>[];

  bool get hasListeners => listeners.isNotEmpty;

  void Function() subscribe(
      MutationObserverListener<TData, TVariables> listener) {
    listeners.add(listener);
    return () {
      listeners.remove(listener);
      if (!hasListeners) {
        _currentMutation?.removeObserver(this);
      }
    };
  }

  late DefaultedMutationOptions<TData, TVariables, TOnMutateResult> _options;
  DefaultedMutationOptions<TData, TVariables, TOnMutateResult> get options =>
      _options;

  Mutation<TData, TVariables, TOnMutateResult>? _currentMutation;
  late MutationResult<TData, TVariables> _currentResult;
  MutateCallbacks<TData, TVariables, TOnMutateResult>? _callCallbacks;

  MutationResult<TData, TVariables> get currentResult => _currentResult;

  void setOptions(
    MutationOptions<TData, TVariables, TOnMutateResult> options,
  ) {
    _options = _client
        .defaultMutationOptions<TData, TVariables, TOnMutateResult>(options);
    _currentMutation?.setOptions(_options);
  }

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

  /// Back to idle.
  void reset() {
    _currentMutation?.removeObserver(this);
    _currentMutation = null;
    _updateResult(MutationState<TData, TVariables, TOnMutateResult>());
  }

  @override
  void onMutationUpdate(MutationAction action) {
    final mutation = _currentMutation;
    if (mutation == null) {
      return;
    }
    _updateResult(mutation.state);
    _notifyCallCallbacks(action, mutation.state);
  }

  void _notifyCallCallbacks(
    MutationAction action,
    MutationState<TData, TVariables, TOnMutateResult> state,
  ) {
    final callbacks = _callCallbacks;
    if (callbacks == null || !state.hasVariables) {
      return;
    }
    final variables = state.variables as TVariables;

    switch (action) {
      case MutationSuccessAction(:final data):
        final typed = data as TData;
        callbacks.onSuccess?.call(typed, variables, state.onMutateResult);
        callbacks.onSettled?.call(
          typed,
          null,
          null,
          variables,
          state.onMutateResult,
        );
      case MutationErrorAction(:final error, :final stackTrace):
        callbacks.onError?.call(
          error,
          stackTrace,
          variables,
          state.onMutateResult,
        );
        callbacks.onSettled?.call(
          null,
          error,
          stackTrace,
          variables,
          state.onMutateResult,
        );
      default:
        break;
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

    _client.notifyManager.batch(() {
      for (final listener in List.of(listeners)) {
        listener(_currentResult);
      }
    });
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
