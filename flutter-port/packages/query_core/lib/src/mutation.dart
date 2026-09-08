import 'dart:async';

import 'package:clock/clock.dart';

import 'mutation_options.dart';
import 'mutation_state.dart';
import 'notify_manager.dart';
import 'removable.dart';
import 'retryer.dart';

/// What [Mutation] needs from an observer, without depending on the observer
/// implementation itself.
abstract interface class MutationObserverRef {
  /// Called after every state change, inside the notify batch.
  void onMutationUpdate(MutationAction action);
}

/// What a [Mutation] reports when something changes.
sealed class MutationAction {
  const MutationAction();
}

class MutationFailedAction extends MutationAction {
  const MutationFailedAction(this.failureCount, this.error, this.stackTrace);
  final int failureCount;
  final Object error;
  final StackTrace stackTrace;
}

class MutationPendingAction<TVariables, TOnMutateResult>
    extends MutationAction {
  const MutationPendingAction({
    required this.isPaused,
    required this.variables,
    this.onMutateResult,
  });
  final bool isPaused;
  final TVariables variables;
  final TOnMutateResult? onMutateResult;
}

class MutationSuccessAction<TData> extends MutationAction {
  const MutationSuccessAction(this.data);
  final TData data;
}

class MutationErrorAction extends MutationAction {
  const MutationErrorAction(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

class MutationPauseAction extends MutationAction {
  const MutationPauseAction();
}

class MutationContinueAction extends MutationAction {
  const MutationContinueAction();
}

/// Receives a mutation's changes and arbitrates between mutations. Implemented
/// by `MutationCache`; declared here so [Mutation] does not depend on it.
abstract interface class MutationHost {
  /// Whether [mutation] may start now — false while another mutation in the
  /// same scope is still running.
  bool canRun(Mutation<Object?, Object?, Object?> mutation);

  /// Resumes the next paused mutation in [mutation]'s scope, if any.
  Future<void> runNext(Mutation<Object?, Object?, Object?> mutation);

  void onMutationRemovalRequested(Mutation<Object?, Object?, Object?> mutation);
  void onMutationUpdated(
    Mutation<Object?, Object?, Object?> mutation,
    MutationAction action,
  );
  void onMutationObserverAdded(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  );
  void onMutationObserverRemoved(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  );

  /// Cache-wide lifecycle callbacks, awaited immediately before the mutation's
  /// own callback of the same name.
  ///
  /// [onMutationMutate] returns `FutureOr` on purpose: with no cache-level
  /// callback registered there is nothing to await, and the mutation's own
  /// `onMutate` has to still run in the same turn as `mutate()` — an optimistic
  /// update that waits a microtask is an update the screen flickers through.
  FutureOr<void> onMutationMutate(
    Mutation<Object?, Object?, Object?> mutation,
    Object? variables,
    MutationFunctionContext context,
  );
  Future<void> onMutationSuccess(
    Mutation<Object?, Object?, Object?> mutation,
    Object? data,
    Object? variables,
    Object? onMutateResult,
    MutationFunctionContext context,
  );
  Future<void> onMutationError(
    Mutation<Object?, Object?, Object?> mutation,
    Object error,
    StackTrace stackTrace,
    Object? variables,
    Object? onMutateResult,
    MutationFunctionContext context,
  );
  Future<void> onMutationSettled(
    Mutation<Object?, Object?, Object?> mutation,
    Object? data,
    Object? error,
    StackTrace? stackTrace,
    Object? variables,
    Object? onMutateResult,
    MutationFunctionContext context,
  );
}

/// One write, from submission to outcome.
///
/// Unlike a [Query], a mutation is never shared or deduplicated: every
/// `mutate()` builds a new one. That is why its identity is a counter rather
/// than a key, and why the cache holds a set rather than a map.
class Mutation<TData, TVariables, TOnMutateResult> extends Removable {
  Mutation({
    required this.mutationId,
    required MutationHost host,
    required DefaultedMutationOptions<TData, TVariables, TOnMutateResult>
    options,
    MutationState<TData, TVariables, TOnMutateResult>? state,
  }) : _host = host,
       _options = options,
       _state = state ?? MutationState<TData, TVariables, TOnMutateResult>() {
    updateGcTime(options.gcTime);
    scheduleGc();
  }

  final int mutationId;
  final MutationHost _host;

  DefaultedMutationOptions<TData, TVariables, TOnMutateResult> _options;
  MutationState<TData, TVariables, TOnMutateResult> _state;
  Retryer<TData>? _retryer;

  final List<MutationObserverRef> _observers = <MutationObserverRef>[];

  MutationState<TData, TVariables, TOnMutateResult> get state => _state;
  DefaultedMutationOptions<TData, TVariables, TOnMutateResult> get options =>
      _options;
  Object? get meta => _options.meta;
  String? get scope => _options.scope;

  int get observersCount => _observers.length;

  void setOptions(
    DefaultedMutationOptions<TData, TVariables, TOnMutateResult> options,
  ) {
    _options = options;
    updateGcTime(options.gcTime);
  }

  void addObserver(MutationObserverRef observer) {
    if (_observers.contains(observer)) {
      return;
    }
    _observers.add(observer);
    // An observed mutation is in use, so stop the collection clock.
    clearGcTimeout();
    _host.onMutationObserverAdded(this, observer);
  }

  void removeObserver(MutationObserverRef observer) {
    _observers.remove(observer);
    scheduleGc();
    _host.onMutationObserverRemoved(this, observer);
  }

  @override
  void optionalRemove() {
    if (_observers.isNotEmpty) {
      return;
    }
    if (_state.status == MutationStatus.pending) {
      // A mutation still in flight outlives its observers: the write should
      // land even if the screen that started it is gone.
      //
      // Upstream re-arms the same timer here and polls until the mutation
      // settles. That relies on the browser clamping `setTimeout(0)` to a few
      // milliseconds; Dart does not clamp `Timer(Duration.zero)`, so polling
      // would spin the event loop. The collection clock restarts when the
      // mutation settles instead — see the end of [execute] — which reaches
      // the same outcome without the busy loop.
      return;
    }
    _host.onMutationRemovalRequested(this);
  }

  /// Continues a paused mutation. Upstream calls this `continue`, which Dart
  /// reserves.
  Future<Object?> resume() {
    final retryer = _retryer;
    if (retryer != null) {
      return retryer.resume();
    }
    // No retryer means the mutation was restored from a persisted pending
    // state, so it has to start for real. A settled one must not run again.
    if (_state.status == MutationStatus.pending) {
      return execute(_state.variables as TVariables);
    }
    return Future<Object?>.value();
  }

  /// Runs the mutation and every callback around it.
  ///
  /// The callback order is load-bearing: cache-wide callback, then this
  /// mutation's own, for each of mutate/success/error/settled. A throw from any
  /// callback in the success path moves execution to the error path, which is
  /// what makes "the write succeeded but the follow-up invalidation failed"
  /// surface as a failed mutation rather than a silent one.
  Future<TData> execute(TVariables variables) async {
    void onContinue() => _dispatch(const MutationContinueAction());

    final functionContext = _options.functionContext;

    final retryer = Retryer<TData>(
      fn: () {
        final mutationFn = _options.mutationFn;
        if (mutationFn == null) {
          return Future<TData>.error(const MissingMutationFunctionError());
        }
        return mutationFn(variables, functionContext);
      },
      canRun: () => _host.canRun(this),
      networkMode: _options.networkMode,
      retry: _options.retry,
      retryDelay: _options.retryDelay,
      onFail: (failureCount, error, stackTrace) =>
          _dispatch(MutationFailedAction(failureCount, error, stackTrace)),
      onPause: () => _dispatch(const MutationPauseAction()),
      onContinue: onContinue,
    );
    _retryer = retryer;

    // Already pending means this was restored from a persisted state: it has
    // been through onMutate once already and must not run it again.
    final restored = _state.status == MutationStatus.pending;
    final isPaused = !retryer.canStart();

    try {
      if (restored) {
        onContinue();
      } else {
        _dispatch(
          MutationPendingAction<TVariables, TOnMutateResult>(
            isPaused: isPaused,
            variables: variables,
          ),
        );
        final cacheOnMutate = _host.onMutationMutate(
          this,
          variables,
          functionContext,
        );
        if (cacheOnMutate is Future<void>) {
          await cacheOnMutate;
        }

        final onMutateResult = await _options.onMutate?.call(
          variables,
          functionContext,
        );
        if (!identical(onMutateResult, _state.onMutateResult)) {
          _dispatch(
            MutationPendingAction<TVariables, TOnMutateResult>(
              isPaused: isPaused,
              variables: variables,
              onMutateResult: onMutateResult,
            ),
          );
        }
      }

      final data = await retryer.start();

      await _host.onMutationSuccess(
        this,
        data,
        variables,
        _state.onMutateResult,
        functionContext,
      );
      await _options.onSuccess?.call(
        data,
        variables,
        _state.onMutateResult,
        functionContext,
      );
      await _host.onMutationSettled(
        this,
        data,
        null,
        null,
        _state.variables,
        _state.onMutateResult,
        functionContext,
      );
      await _options.onSettled?.call(
        data,
        null,
        null,
        variables,
        _state.onMutateResult,
        functionContext,
      );

      _dispatch(MutationSuccessAction<TData>(data));
      return data;
    } catch (error, stackTrace) {
      // Each of these is isolated: a failing error handler must not stop the
      // remaining ones, and must not replace the error the caller sees. The
      // failure is handed to the zone instead, which is where Dart reports an
      // error nobody is waiting for.
      await _runIsolated(
        () => _host.onMutationError(
          this,
          error,
          stackTrace,
          variables,
          _state.onMutateResult,
          functionContext,
        ),
      );
      await _runIsolated(
        () => _options.onError?.call(
          error,
          stackTrace,
          variables,
          _state.onMutateResult,
          functionContext,
        ),
      );
      await _runIsolated(
        () => _host.onMutationSettled(
          this,
          null,
          error,
          stackTrace,
          _state.variables,
          _state.onMutateResult,
          functionContext,
        ),
      );
      await _runIsolated(
        () => _options.onSettled?.call(
          null,
          error,
          stackTrace,
          variables,
          _state.onMutateResult,
          functionContext,
        ),
      );

      _dispatch(MutationErrorAction(error, stackTrace));
      rethrow;
    } finally {
      // Holding the settled retryer would pin this mutation's result,
      // variables and context for as long as the cache keeps it.
      if (identical(_retryer, retryer)) {
        _retryer = null;
      }
      // Now that it has settled, an unobserved mutation is a collection
      // candidate again.
      scheduleGc();

      // Ignored, not awaited: the resumed mutation reports to whoever is
      // holding its own future, and this one has already finished.
      _host.runNext(this).ignore();
    }
  }

  static Future<void> _runIsolated(FutureOr<void> Function() body) async {
    try {
      await body();
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  void _dispatch(MutationAction action) {
    _state = _reduce(_state, action);

    notifyManager.batch(() {
      // Copy: an observer may detach while being notified.
      for (final observer in List.of(_observers)) {
        observer.onMutationUpdate(action);
      }
      _host.onMutationUpdated(this, action);
    });
  }

  MutationState<TData, TVariables, TOnMutateResult> _reduce(
    MutationState<TData, TVariables, TOnMutateResult> state,
    MutationAction action,
  ) {
    switch (action) {
      case MutationFailedAction():
        return state.copyWith(
          failureCount: action.failureCount,
          failureReason: action.error,
          failureStackTrace: action.stackTrace,
        );

      case MutationPauseAction():
        return state.copyWith(isPaused: true);

      case MutationContinueAction():
        return state.copyWith(isPaused: false);

      case MutationPendingAction<TVariables, TOnMutateResult>():
        return state.copyWith(
          onMutateResult: action.onMutateResult,
          hasData: false,
          data: null,
          failureCount: 0,
          failureReason: null,
          failureStackTrace: null,
          error: null,
          errorStackTrace: null,
          isPaused: action.isPaused,
          status: MutationStatus.pending,
          variables: action.variables,
          submittedAt: clock.now(),
        );

      case MutationSuccessAction<TData>():
        return state.copyWith(
          hasData: true,
          data: action.data,
          failureCount: 0,
          failureReason: null,
          failureStackTrace: null,
          error: null,
          errorStackTrace: null,
          status: MutationStatus.success,
          isPaused: false,
        );

      case MutationErrorAction():
        return state.copyWith(
          hasData: false,
          data: null,
          error: action.error,
          errorStackTrace: action.stackTrace,
          failureCount: state.failureCount + 1,
          failureReason: action.error,
          failureStackTrace: action.stackTrace,
          isPaused: false,
          status: MutationStatus.error,
        );

      // Actions carrying different type arguments cannot apply here.
      case MutationPendingAction<Object?, Object?>():
      case MutationSuccessAction<Object?>():
        return state;
    }
  }
}
