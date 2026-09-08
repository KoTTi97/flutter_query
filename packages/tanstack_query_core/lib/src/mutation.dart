/// Port of `query-core/src/mutation.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

import 'mutation_options.dart';
import 'query_client.dart';
import 'query_key.dart';
import 'removable.dart';
import 'retryer.dart';

enum MutationStatus { idle, pending, success, error }

/// What a [Mutation] needs from an observer.
abstract interface class MutationObserverRef {
  void onMutationUpdate(MutationAction action);
}

/// What a [Mutation] needs from its cache.
abstract interface class MutationCacheRef {
  void onMutationStateUpdated(
    Mutation<Object?, Object?, Object?> mutation,
    MutationAction action,
  );
  void onMutationRemovalRequested(Mutation<Object?, Object?, Object?> mutation);
  void onMutationObserverAdded(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  );
  void onMutationObserverRemoved(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  );
  bool canRunMutation(Mutation<Object?, Object?, Object?> mutation);
  void onMutationSettled(Mutation<Object?, Object?, Object?> mutation);
  FutureOr<void> onMutationStarting(
    Mutation<Object?, Object?, Object?> mutation,
    Object? variables,
  );
  FutureOr<void> onMutationSuccess(
    Mutation<Object?, Object?, Object?> mutation,
    Object? data,
    Object? variables,
    Object? onMutateResult,
  );
  FutureOr<void> onMutationError(
    Mutation<Object?, Object?, Object?> mutation,
    Object error,
    StackTrace stackTrace,
    Object? variables,
    Object? onMutateResult,
  );
  FutureOr<void> onMutationSettledCallback(
    Mutation<Object?, Object?, Object?> mutation,
    Object? data,
    Object? error,
    StackTrace? stackTrace,
    Object? variables,
    Object? onMutateResult,
  );
}

@immutable
sealed class MutationAction {
  const MutationAction();
}

final class MutationPendingAction extends MutationAction {
  const MutationPendingAction({
    required this.variables,
    required this.onMutateResult,
    required this.isPaused,
  });
  final Object? variables;
  final Object? onMutateResult;
  final bool isPaused;
}

final class MutationSuccessAction extends MutationAction {
  const MutationSuccessAction(this.data);
  final Object? data;
}

final class MutationErrorAction extends MutationAction {
  const MutationErrorAction(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

final class MutationFailedAction extends MutationAction {
  const MutationFailedAction(this.failureCount, this.error, this.stackTrace);
  final int failureCount;
  final Object error;
  final StackTrace stackTrace;
}

final class MutationPauseAction extends MutationAction {
  const MutationPauseAction();
}

final class MutationContinueAction extends MutationAction {
  const MutationContinueAction();
}

final class MutationResetAction extends MutationAction {
  const MutationResetAction();
}

/// A mutation's state at one point in time.
@immutable
final class MutationState<TData, TVariables, TOnMutateResult> {
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

  final MutationStatus status;
  final bool hasData;
  final TData? data;
  final Object? error;
  final StackTrace? errorStackTrace;

  /// The variables of the run in flight or last finished — what optimistic UI
  /// reads while the mutation is pending.
  final TVariables? variables;
  final bool hasVariables;
  final TOnMutateResult? onMutateResult;

  final int failureCount;
  final Object? failureReason;
  final bool isPaused;
  final DateTime? submittedAt;

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
    bool clearError = false,
    bool clearFailureReason = false,
  }) =>
      MutationState<TData, TVariables, TOnMutateResult>(
        status: status ?? this.status,
        hasData: hasData ?? this.hasData,
        data: data ?? this.data,
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
}

/// One mutation: its options, its state, and one run of its mutation function.
class Mutation<TData, TVariables, TOnMutateResult> extends Removable {
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

  final QueryClient client;
  final MutationCacheRef _cache;
  final int mutationId;

  DefaultedMutationOptions<TData, TVariables, TOnMutateResult> _options;
  DefaultedMutationOptions<TData, TVariables, TOnMutateResult> get options =>
      _options;

  MutationState<TData, TVariables, TOnMutateResult> _state;
  MutationState<TData, TVariables, TOnMutateResult> get state => _state;

  final List<MutationObserverRef> observers = <MutationObserverRef>[];
  Retryer<TData>? _retryer;

  Object? get meta => _options.meta;

  @internal
  void setOptions(
    DefaultedMutationOptions<TData, TVariables, TOnMutateResult> options,
  ) {
    _options = options;
    updateGcTime(options.gcTime);
  }

  @internal
  void addObserver(MutationObserverRef observer) {
    if (!observers.contains(observer)) {
      observers.add(observer);
      clearGcTimeout();
      _cache.onMutationObserverAdded(
          this as Mutation<Object?, Object?, Object?>, observer);
    }
  }

  @internal
  void removeObserver(MutationObserverRef observer) {
    if (!observers.remove(observer)) {
      return;
    }
    _cache.onMutationObserverRemoved(
        this as Mutation<Object?, Object?, Object?>, observer);
    // Never removed on the spot: an unmounted widget must not cut a mutation's
    // callbacks short. The gc timer decides, and `optionalRemove` lets a
    // pending one keep going.
    scheduleGc();
  }

  @override
  void optionalRemove() {
    if (observers.isNotEmpty) {
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

  /// Releases a paused mutation, completing when it settles.
  ///
  /// A mutation restored from persistence is `pending` with no retryer at all;
  /// continuing it means running it, which is how an offline mutation survives
  /// a restart. A settled one has nothing to continue and must never run twice.
  Future<void> continueMutation() {
    final retryer = _retryer;
    if (retryer != null) {
      return retryer.continueFetch().then((_) {}).catchError((Object _) {});
    }
    if (_state.status == MutationStatus.pending && _state.hasVariables) {
      return execute(_state.variables as TVariables)
          .then((_) {})
          .catchError((Object _) {});
    }
    return Future<void>.value();
  }

  /// Cancels the pending collection.
  ///
  /// Called by the cache when this mutation is removed, so a removed mutation
  /// leaves no timer behind that would later ask to be removed again. Upstream
  /// does not do this — in a browser nobody notices a stray `setTimeout`, but
  /// Flutter's own widget tests assert that no timer outlives the tree.
  @override
  void destroy() => super.destroy();

  /// Runs [body], reporting anything it throws to the zone instead of letting
  /// it replace the error already on its way to the caller.
  static Future<void> _reportingFailures(FutureOr<void> Function() body) async {
    try {
      await body();
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  /// Back to idle.
  void reset() {
    _dispatch(const MutationResetAction());
  }

  /// Runs the mutation function once, with everything around it.
  Future<TData> execute(TVariables variables) async {
    final mutationFn = _options.mutationFn;
    if (mutationFn == null) {
      throw MissingMutationFunctionError(_options.mutationKey);
    }

    // The retryer exists before the first `await`, exactly as upstream builds
    // it: a mutation that pauses while its `onMutate` is still running must
    // still be resumable, and `continueMutation` has nothing to continue
    // without it.
    final retryer = Retryer<TData>(
      fn: () async => mutationFn(variables),
      focusManager: client.focusManager,
      onlineManager: client.onlineManager,
      canRun: () =>
          _cache.canRunMutation(this as Mutation<Object?, Object?, Object?>),
      retry: _options.retry,
      retryDelay: _options.retryDelay,
      networkMode: _options.networkMode,
      onFail: (failureCount, error, stackTrace) =>
          _dispatch(MutationFailedAction(failureCount, error, stackTrace)),
      onPause: () => _dispatch(const MutationPauseAction()),
      onContinue: () => _dispatch(const MutationContinueAction()),
    );
    _retryer = retryer;

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
        final starting = _cache.onMutationStarting(
          this as Mutation<Object?, Object?, Object?>,
          variables,
        );
        if (starting is Future<void>) {
          await starting;
        }

        final mutating = _options.onMutate?.call(variables);
        if (mutating is Future<TOnMutateResult>) {
          onMutateResult = await mutating;
        } else {
          onMutateResult = mutating as TOnMutateResult?;
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
      await _cache.onMutationSuccess(
        this as Mutation<Object?, Object?, Object?>,
        data,
        variables,
        onMutateResult,
      );
      await _options.onSuccess?.call(data, variables, onMutateResult);
      await _cache.onMutationSettledCallback(
        this as Mutation<Object?, Object?, Object?>,
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
          this as Mutation<Object?, Object?, Object?>,
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
          this as Mutation<Object?, Object?, Object?>,
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
      _cache.onMutationSettled(this as Mutation<Object?, Object?, Object?>);
      if (identical(_retryer, retryer)) {
        _retryer = null;
      }
      scheduleGc();
    }
  }

  void _dispatch(MutationAction action) {
    _state = _reduce(_state, action);

    client.notifyManager.batch(() {
      for (final observer in List<MutationObserverRef>.of(observers)) {
        observer.onMutationUpdate(action);
      }
      _cache.onMutationStateUpdated(
        this as Mutation<Object?, Object?, Object?>,
        action,
      );
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
            error: error,
            errorStackTrace: stackTrace,
            failureCount: state.failureCount + 1,
            failureReason: error,
            isPaused: false,
          ),
        MutationResetAction() =>
          MutationState<TData, TVariables, TOnMutateResult>(),
      };

  @override
  String toString() => 'Mutation($mutationId, ${_state.status})';
}

/// Thrown when a mutation runs without a `mutationFn`.
final class MissingMutationFunctionError implements Exception {
  const MissingMutationFunctionError(this.mutationKey);

  final QueryKey? mutationKey;

  @override
  String toString() => 'No mutationFn was provided'
      '${mutationKey == null ? '' : ' for $mutationKey'}. Pass one in the '
      'mutation options, or set a default with '
      'QueryClient.setMutationDefaults.';
}
