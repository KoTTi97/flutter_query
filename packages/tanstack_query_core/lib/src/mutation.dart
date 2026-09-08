/// Port of `query-core/src/mutation.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

import 'mutation_options.dart';
import 'option_values.dart';
import 'query_client.dart';
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
    }
  }

  @internal
  void removeObserver(MutationObserverRef observer) {
    observers.remove(observer);
    if (observers.isEmpty) {
      if (_state.status == MutationStatus.pending) {
        scheduleGc();
      } else {
        _cache.onMutationRemovalRequested(this);
      }
    }
  }

  @override
  void optionalRemove() {
    if (observers.isEmpty && _state.status != MutationStatus.pending) {
      _cache.onMutationRemovalRequested(this);
    }
  }

  /// Releases a paused mutation.
  Future<TData>? continueMutation() => _retryer?.continueFetch();

  /// Back to idle.
  void reset() {
    _dispatch(const MutationResetAction());
  }

  /// Runs the mutation function once, with everything around it.
  Future<TData> execute(TVariables variables) async {
    final mutationFn = _options.mutationFn;
    if (mutationFn == null) {
      throw StateError('No mutationFn was provided for this mutation');
    }

    final isRestart = _state.status == MutationStatus.pending;
    TOnMutateResult? onMutateResult = _state.onMutateResult;

    if (!isRestart) {
      _dispatch(
        MutationPendingAction(
          variables: variables,
          onMutateResult: null,
          isPaused: !_canFetch(),
        ),
      );

      await _cache.onMutationStarting(
        this as Mutation<Object?, Object?, Object?>,
        variables,
      );

      onMutateResult = await _options.onMutate?.call(variables);

      if (onMutateResult != _state.onMutateResult) {
        _dispatch(
          MutationPendingAction(
            variables: variables,
            onMutateResult: onMutateResult,
            isPaused: !_canFetch(),
          ),
        );
      }
    }

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

    try {
      final data = await retryer.start();

      await _cache.onMutationSuccess(
        this as Mutation<Object?, Object?, Object?>,
        data,
        variables,
        onMutateResult,
      );
      await _options.onSuccess?.call(data, variables, onMutateResult);
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
      try {
        await _cache.onMutationError(
          this as Mutation<Object?, Object?, Object?>,
          error,
          stackTrace,
          variables,
          onMutateResult,
        );
        await _options.onError?.call(
          error,
          stackTrace,
          variables,
          onMutateResult,
        );
        await _options.onSettled?.call(
          null,
          error,
          stackTrace,
          variables,
          onMutateResult,
        );
      } finally {
        _dispatch(MutationErrorAction(error, stackTrace));
      }
      rethrow;
    } finally {
      _cache.onMutationSettled(this as Mutation<Object?, Object?, Object?>);
      if (identical(_retryer, retryer)) {
        _retryer = null;
      }
      scheduleGc();
    }
  }

  bool _canFetch() =>
      _options.networkMode != NetworkMode.online ||
      client.onlineManager.isOnline();

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
