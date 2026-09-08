/// Port of `query-core/src/mutationCache.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'filters.dart';
import 'mutation.dart';
import 'mutation_options.dart';
import 'query_client.dart';
import 'subscribable.dart';

@immutable
sealed class MutationCacheEvent {
  const MutationCacheEvent(this.mutation);
  final Mutation<Object?, Object?, Object?> mutation;
}

final class MutationAdded extends MutationCacheEvent {
  const MutationAdded(super.mutation);
}

final class MutationRemoved extends MutationCacheEvent {
  const MutationRemoved(super.mutation);
}

final class MutationUpdated extends MutationCacheEvent {
  const MutationUpdated(super.mutation, this.action);
  final MutationAction action;
}

final class MutationObserverAdded extends MutationCacheEvent {
  const MutationObserverAdded(super.mutation, this.observer);
  final MutationObserverRef observer;
}

final class MutationObserverRemoved extends MutationCacheEvent {
  const MutationObserverRemoved(super.mutation, this.observer);
  final MutationObserverRef observer;
}

final class MutationObserverOptionsUpdated extends MutationCacheEvent {
  const MutationObserverOptionsUpdated(super.mutation, this.observer);
  final MutationObserverRef observer;
}

/// Every mutation, in submission order.
class MutationCache
    extends Subscribable<void Function(MutationCacheEvent event)>
    implements MutationCacheRef {
  MutationCache({this.onMutate, this.onSuccess, this.onError, this.onSettled});

  /// Cache-wide hooks. They run *before* the per-mutation callbacks, which is
  /// what lets a global handler set something up that a local one consumes.
  final FutureOr<void> Function(
    Object? variables,
    Mutation<Object?, Object?, Object?> mutation,
  )? onMutate;
  final FutureOr<void> Function(
    Object? data,
    Object? variables,
    Object? onMutateResult,
    Mutation<Object?, Object?, Object?> mutation,
  )? onSuccess;
  final FutureOr<void> Function(
    Object error,
    StackTrace stackTrace,
    Object? variables,
    Object? onMutateResult,
    Mutation<Object?, Object?, Object?> mutation,
  )? onError;
  final FutureOr<void> Function(
    Object? data,
    Object? error,
    StackTrace? stackTrace,
    Object? variables,
    Object? onMutateResult,
    Mutation<Object?, Object?, Object?> mutation,
  )? onSettled;

  final List<Mutation<Object?, Object?, Object?>> _mutations =
      <Mutation<Object?, Object?, Object?>>[];
  int _nextMutationId = 1;

  List<Mutation<Object?, Object?, Object?>> get mutations =>
      List<Mutation<Object?, Object?, Object?>>.of(_mutations);

  Mutation<TData, TVariables, TOnMutateResult>
      build<TData, TVariables, TOnMutateResult>(
    QueryClient client,
    DefaultedMutationOptions<TData, TVariables, TOnMutateResult> options, {
    MutationState<TData, TVariables, TOnMutateResult>? state,
  }) {
    final mutation = Mutation<TData, TVariables, TOnMutateResult>(
      client: client,
      cache: this,
      mutationId: _nextMutationId++,
      options: options,
      state: state,
    );
    add(mutation);
    return mutation;
  }

  @internal
  void notifyObserverOptionsUpdated(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  ) =>
      notify(MutationObserverOptionsUpdated(mutation, observer));

  void add(Mutation<Object?, Object?, Object?> mutation) {
    _mutations.add(mutation);
    notify(MutationAdded(mutation));
  }

  void remove(Mutation<Object?, Object?, Object?> mutation) {
    _mutations.remove(mutation);
    // Notified even when it was not in the cache: a caller that asked for a
    // removal gets told the removal happened, exactly once, either way.
    notify(MutationRemoved(mutation));
  }

  void clear() {
    for (final mutation in mutations) {
      remove(mutation);
    }
  }

  List<Mutation<Object?, Object?, Object?>> findAll([
    MutationFilters filters = const MutationFilters(),
  ]) =>
      _mutations.where(filters.matches).toList();

  Mutation<Object?, Object?, Object?>? find(MutationFilters filters) {
    for (final mutation in _mutations) {
      if (filters.matches(mutation)) {
        return mutation;
      }
    }
    return null;
  }

  void notify(MutationCacheEvent event) {
    for (final listener in List.of(listeners)) {
      listener(event);
    }
  }

  /// Replays paused mutations in submission order.
  /// Releases every paused mutation at once.
  ///
  /// All of them are continued together, as upstream does: what serialises
  /// mutations is [canRunMutation]'s scope rule, not the order they are
  /// resumed in. Resuming them one after another would make every paused
  /// mutation wait for the slowest one before it.
  Future<void> resumePaused() async {
    final paused =
        _mutations.where((mutation) => mutation.state.isPaused).toList();
    await Future.wait<void>(
      // Errors belong to each mutation's state, not to whoever resumed it;
      // `continueMutation` already swallows them.
      paused.map((mutation) => mutation.continueMutation()),
    );
  }

  /// The scope a mutation is serialised under: its own scope, or its identity.
  Object _scopeOf(Mutation<Object?, Object?, Object?> mutation) =>
      mutation.options.scope?.id ?? mutation.mutationId;

  @override
  bool canRunMutation(Mutation<Object?, Object?, Object?> mutation) {
    final scope = _scopeOf(mutation);
    for (final other in _mutations) {
      if (identical(other, mutation)) {
        return true;
      }
      if (_scopeOf(other) == scope &&
          other.state.status == MutationStatus.pending) {
        // An earlier mutation in the same scope is still running.
        return false;
      }
    }
    return true;
  }

  @override
  void onMutationSettled(Mutation<Object?, Object?, Object?> mutation) {
    final scope = _scopeOf(mutation);
    for (final other in _mutations) {
      if (!identical(other, mutation) &&
          _scopeOf(other) == scope &&
          other.state.isPaused) {
        other.continueMutation().ignore();
        break;
      }
    }
  }

  @override
  void onMutationStateUpdated(
    Mutation<Object?, Object?, Object?> mutation,
    MutationAction action,
  ) =>
      notify(MutationUpdated(mutation, action));

  @override
  void onMutationObserverAdded(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  ) =>
      notify(MutationObserverAdded(mutation, observer));

  @override
  void onMutationObserverRemoved(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  ) =>
      notify(MutationObserverRemoved(mutation, observer));

  @override
  void onMutationRemovalRequested(
    Mutation<Object?, Object?, Object?> mutation,
  ) =>
      remove(mutation);

  @override
  FutureOr<void> onMutationStarting(
    Mutation<Object?, Object?, Object?> mutation,
    Object? variables,
  ) =>
      onMutate?.call(variables, mutation);

  @override
  FutureOr<void> onMutationSuccess(
    Mutation<Object?, Object?, Object?> mutation,
    Object? data,
    Object? variables,
    Object? onMutateResult,
  ) async {
    await onSuccess?.call(data, variables, onMutateResult, mutation);
  }

  @override
  FutureOr<void> onMutationSettledCallback(
    Mutation<Object?, Object?, Object?> mutation,
    Object? data,
    Object? error,
    StackTrace? stackTrace,
    Object? variables,
    Object? onMutateResult,
  ) async {
    await onSettled?.call(
      data,
      error,
      stackTrace,
      variables,
      onMutateResult,
      mutation,
    );
  }

  @override
  FutureOr<void> onMutationError(
    Mutation<Object?, Object?, Object?> mutation,
    Object error,
    StackTrace stackTrace,
    Object? variables,
    Object? onMutateResult,
  ) async {
    await onError?.call(error, stackTrace, variables, onMutateResult, mutation);
  }
}
