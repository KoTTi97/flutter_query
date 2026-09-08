import 'dart:async';

import 'package:meta/meta.dart';

import 'mutation.dart';
import 'mutation_cache.dart';
import 'mutation_options.dart';
import 'mutation_result.dart';
import 'mutation_state.dart';
import 'notify_manager.dart';

/// What a mutation observer needs from the client.
abstract interface class MutationObserverClient {
  MutationCache get mutationCache;

  DefaultedMutationOptions<TData, TVariables, TOnMutateResult>
  defaultMutationOptions<TData, TVariables, TOnMutateResult>(
    MutationOptions<TData, TVariables, TOnMutateResult> options,
  );
}

/// Callbacks attached to one `mutate` call rather than to the observer.
///
/// These fire only while something is subscribed, because they belong to the
/// call site — a screen that has gone away should not run its own
/// success handler. The options-level callbacks always run.
@immutable
class MutateCallbacks<TData, TVariables, TOnMutateResult> {
  const MutateCallbacks({this.onSuccess, this.onError, this.onSettled});

  final void Function(
    TData data,
    TVariables variables,
    TOnMutateResult? onMutateResult,
    MutationFunctionContext context,
  )?
  onSuccess;

  final void Function(
    Object error,
    StackTrace stackTrace,
    TVariables variables,
    TOnMutateResult? onMutateResult,
    MutationFunctionContext context,
  )?
  onError;

  final void Function(
    TData? data,
    Object? error,
    StackTrace? stackTrace,
    TVariables variables,
    TOnMutateResult? onMutateResult,
    MutationFunctionContext context,
  )?
  onSettled;
}

typedef MutationObserverListener<TData, TVariables, TOnMutateResult> =
    void Function(MutationResult<TData, TVariables, TOnMutateResult> result);

/// One use site's view of mutating.
///
/// It holds the options and the current [result], and builds a fresh
/// [Mutation] on every [mutate]. Nothing is shared between calls, which is
/// the whole difference from a query observer: two `mutate` calls are two
/// writes, never one deduplicated request.
///
/// As with [QueryObserver], it does not extend `Subscribable`: Dart forbids a
/// class type parameter in a contravariant position of a superinterface.
class MutationObserver<TData, TVariables, TOnMutateResult>
    implements MutationObserverRef {
  MutationObserver(
    this._client,
    MutationOptions<TData, TVariables, TOnMutateResult> options,
  ) {
    setOptions(options);
    _updateResult();
  }

  final MutationObserverClient _client;

  late DefaultedMutationOptions<TData, TVariables, TOnMutateResult> _options;
  DefaultedMutationOptions<TData, TVariables, TOnMutateResult>? _optionsOrNull;

  Mutation<TData, TVariables, TOnMutateResult>? _currentMutation;
  MutateCallbacks<TData, TVariables, TOnMutateResult>? _mutateCallbacks;

  late MutationResult<TData, TVariables, TOnMutateResult> _currentResult;

  final Set<MutationObserverListener<TData, TVariables, TOnMutateResult>>
  _listeners =
      <MutationObserverListener<TData, TVariables, TOnMutateResult>>{};

  DefaultedMutationOptions<TData, TVariables, TOnMutateResult> get options =>
      _options;

  /// The current result. Always valid, including before the first subscribe.
  MutationResult<TData, TVariables, TOnMutateResult> get result =>
      _currentResult;

  Mutation<TData, TVariables, TOnMutateResult>? get currentMutation =>
      _currentMutation;

  bool get hasListeners => _listeners.isNotEmpty;

  void Function() subscribe(
    MutationObserverListener<TData, TVariables, TOnMutateResult> listener,
  ) {
    _listeners.add(listener);
    if (_listeners.length == 1) {
      final mutation = _currentMutation;
      if (mutation != null) {
        mutation.addObserver(this);
        _updateResult();
      }
    }
    return () {
      _listeners.remove(listener);
      if (!hasListeners) {
        _currentMutation?.removeObserver(this);
      }
    };
  }

  void setOptions(MutationOptions<TData, TVariables, TOnMutateResult> options) {
    final prevOptions = _optionsOrNull;
    _options = _client.defaultMutationOptions(options);
    _optionsOrNull = _options;

    if (_options != prevOptions) {
      _client.mutationCache.notify(
        MutationObserverOptionsUpdated(_currentMutation, this),
      );
    }

    final previousKey = prevOptions?.mutationKey;
    final nextKey = _options.mutationKey;
    if (previousKey != null && nextKey != null && previousKey != nextKey) {
      // A different key means a different write; whatever the last one produced
      // no longer describes this observer.
      reset();
    } else if (_currentMutation?.state.status == MutationStatus.pending) {
      // A mutation already in flight picks up the new callbacks, so a rebuild
      // that changed them is honoured when the write lands.
      _currentMutation!.setOptions(_options);
    }
  }

  /// Runs the mutation. The returned future carries the mutation function's
  /// own result, and fails with whatever it failed with.
  Future<TData> mutate(
    TVariables variables, {
    MutateCallbacks<TData, TVariables, TOnMutateResult>? callbacks,
  }) {
    _mutateCallbacks = callbacks;

    _currentMutation?.removeObserver(this);
    final mutation = _client.mutationCache
        .build<TData, TVariables, TOnMutateResult>(_options);
    _currentMutation = mutation;
    mutation.addObserver(this);

    return mutation.execute(variables);
  }

  /// Forgets the last mutation and returns to idle.
  ///
  /// The observer detaches from the mutation because there is no way back to
  /// it — another [mutate] builds a new one.
  void reset() {
    _currentMutation?.removeObserver(this);
    _currentMutation = null;
    _updateResult();
    _notify(null);
  }

  @override
  void onMutationUpdate(MutationAction action) {
    _updateResult();
    _notify(action);
  }

  void _updateResult() {
    final state =
        _currentMutation?.state ??
        MutationState<TData, TVariables, TOnMutateResult>();

    _currentResult = switch (state.status) {
      MutationStatus.idle => MutationIdle<TData, TVariables, TOnMutateResult>(
        variables: state.variables,
        onMutateResult: state.onMutateResult,
        failureCount: state.failureCount,
        failureReason: state.failureReason,
        failureStackTrace: state.failureStackTrace,
        isPaused: state.isPaused,
        submittedAt: state.submittedAt,
      ),
      MutationStatus.pending =>
        MutationPending<TData, TVariables, TOnMutateResult>(
          variables: state.variables,
          onMutateResult: state.onMutateResult,
          failureCount: state.failureCount,
          failureReason: state.failureReason,
          failureStackTrace: state.failureStackTrace,
          isPaused: state.isPaused,
          submittedAt: state.submittedAt,
        ),
      MutationStatus.success =>
        MutationSuccess<TData, TVariables, TOnMutateResult>(
          data: state.data as TData,
          variables: state.variables,
          onMutateResult: state.onMutateResult,
          failureCount: state.failureCount,
          failureReason: state.failureReason,
          failureStackTrace: state.failureStackTrace,
          isPaused: state.isPaused,
          submittedAt: state.submittedAt,
        ),
      MutationStatus.error =>
        MutationError<TData, TVariables, TOnMutateResult>(
          error: state.error ?? const MissingMutationFunctionError(),
          stackTrace: state.errorStackTrace,
          variables: state.variables,
          onMutateResult: state.onMutateResult,
          failureCount: state.failureCount,
          failureReason: state.failureReason,
          failureStackTrace: state.failureStackTrace,
          isPaused: state.isPaused,
          submittedAt: state.submittedAt,
        ),
    };
  }

  void _notify(MutationAction? action) {
    notifyManager.batch(() {
      final callbacks = _mutateCallbacks;
      // The per-call callbacks run before the subscribers, so a listener
      // rebuilding on the new result sees whatever they did to the cache.
      if (callbacks != null && hasListeners) {
        final variables = _currentResult.variables as TVariables;
        final onMutateResult = _currentResult.onMutateResult;
        final context = _options.functionContext;

        if (action is MutationSuccessAction<TData>) {
          final data = action.data;
          _runIsolated(
            () => callbacks.onSuccess?.call(
              data,
              variables,
              onMutateResult,
              context,
            ),
          );
          _runIsolated(
            () => callbacks.onSettled?.call(
              data,
              null,
              null,
              variables,
              onMutateResult,
              context,
            ),
          );
        } else if (action is MutationErrorAction) {
          _runIsolated(
            () => callbacks.onError?.call(
              action.error,
              action.stackTrace,
              variables,
              onMutateResult,
              context,
            ),
          );
          _runIsolated(
            () => callbacks.onSettled?.call(
              null,
              action.error,
              action.stackTrace,
              variables,
              onMutateResult,
              context,
            ),
          );
        }
      }

      // Copy: a listener may unsubscribe while being notified.
      for (final listener in List.of(_listeners)) {
        listener(_currentResult);
      }
    });
  }

  /// Runs [body], handing any failure to the zone rather than letting it stop
  /// the callbacks that follow — the port of upstream's `void Promise.reject`.
  static void _runIsolated(void Function() body) {
    try {
      body();
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }
}
