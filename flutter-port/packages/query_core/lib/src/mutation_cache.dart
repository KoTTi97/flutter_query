import 'dart:async';

import 'package:collection/collection.dart';

import 'filters.dart';
import 'mutation.dart';
import 'mutation_options.dart';
import 'mutation_state.dart';
import 'notify_manager.dart';
import 'subscribable.dart';

/// Something that happened to a mutation in the cache.
sealed class MutationCacheEvent {
  const MutationCacheEvent(this.mutation);

  /// The mutation involved. Null only for [MutationObserverOptionsUpdated],
  /// where the observer may not have run a mutation yet.
  final Mutation<Object?, Object?, Object?>? mutation;
}

class MutationAdded extends MutationCacheEvent {
  const MutationAdded(super.mutation);
}

class MutationRemoved extends MutationCacheEvent {
  const MutationRemoved(super.mutation);
}

class MutationUpdated extends MutationCacheEvent {
  const MutationUpdated(super.mutation, this.action);
  final MutationAction action;
}

class MutationObserverAdded extends MutationCacheEvent {
  const MutationObserverAdded(super.mutation, this.observer);
  final MutationObserverRef observer;
}

class MutationObserverRemoved extends MutationCacheEvent {
  const MutationObserverRemoved(super.mutation, this.observer);
  final MutationObserverRef observer;
}

class MutationObserverOptionsUpdated extends MutationCacheEvent {
  const MutationObserverOptionsUpdated(super.mutation, this.observer);
  final MutationObserverRef observer;
}

/// Holds every mutation, and serialises the ones that share a scope.
///
/// Unlike [QueryCache] this is a set, not a map: mutations are never
/// deduplicated, so there is no key to store them under. What the cache does
/// arbitrate is *ordering* — two writes to the same resource should not race.
class MutationCache extends Subscribable<void Function(MutationCacheEvent event)>
    implements MutationHost {
  MutationCache({this.onMutate, this.onSuccess, this.onError, this.onSettled});

  /// Cache-wide callbacks, awaited immediately before each mutation's own
  /// callback of the same name. Useful for global error reporting, or for
  /// invalidation that should happen after every write.
  final FutureOr<void> Function(
    Object? variables,
    Mutation<Object?, Object?, Object?> mutation,
    MutationFunctionContext context,
  )?
  onMutate;

  final FutureOr<void> Function(
    Object? data,
    Object? variables,
    Object? onMutateResult,
    Mutation<Object?, Object?, Object?> mutation,
    MutationFunctionContext context,
  )?
  onSuccess;

  final FutureOr<void> Function(
    Object error,
    StackTrace stackTrace,
    Object? variables,
    Object? onMutateResult,
    Mutation<Object?, Object?, Object?> mutation,
    MutationFunctionContext context,
  )?
  onError;

  final FutureOr<void> Function(
    Object? data,
    Object? error,
    StackTrace? stackTrace,
    Object? variables,
    Object? onMutateResult,
    Mutation<Object?, Object?, Object?> mutation,
    MutationFunctionContext context,
  )?
  onSettled;

  final Set<Mutation<Object?, Object?, Object?>> _mutations =
      <Mutation<Object?, Object?, Object?>>{};

  final Map<String, List<Mutation<Object?, Object?, Object?>>> _scopes =
      <String, List<Mutation<Object?, Object?, Object?>>>{};

  int _mutationId = 0;

  /// Creates a mutation and adds it. Always a new one — mutations are never
  /// reused.
  Mutation<TData, TVariables, TOnMutateResult>
  build<TData, TVariables, TOnMutateResult>(
    DefaultedMutationOptions<TData, TVariables, TOnMutateResult> options, {
    MutationState<TData, TVariables, TOnMutateResult>? state,
  }) {
    final mutation = Mutation<TData, TVariables, TOnMutateResult>(
      mutationId: ++_mutationId,
      host: this,
      options: options,
      state: state,
    );
    add(mutation);
    return mutation;
  }

  void add(Mutation<Object?, Object?, Object?> mutation) {
    _mutations.add(mutation);
    final scope = mutation.scope;
    if (scope != null) {
      _scopes.putIfAbsent(scope, () => []).add(mutation);
    }
    notify(MutationAdded(mutation));
  }

  void remove(Mutation<Object?, Object?, Object?> mutation) {
    if (_mutations.remove(mutation)) {
      final scope = mutation.scope;
      if (scope != null) {
        final scoped = _scopes[scope];
        if (scoped != null) {
          scoped.remove(mutation);
          if (scoped.isEmpty) {
            _scopes.remove(scope);
          }
        }
      }
    }

    // The removal is notified even when the mutation was not in the cache.
    // Upstream flags this as a question of desired semantics rather than a
    // bug, and its tests pin the current behaviour.
    notify(MutationRemoved(mutation));
  }

  void clear() {
    notifyManager.batch(() {
      for (final mutation in mutations) {
        notify(MutationRemoved(mutation));
      }
      _mutations.clear();
      _scopes.clear();
    });
  }

  List<Mutation<Object?, Object?, Object?>> get mutations =>
      List.of(_mutations);

  List<Mutation<Object?, Object?, Object?>> findAll([
    MutationFilters filters = const MutationFilters(),
  ]) {
    final all = mutations;
    return filters.isEmpty ? all : all.where(filters.matches).toList();
  }

  /// The first mutation matching [mutationKey].
  ///
  /// Matches the whole key unless [filters] says otherwise — upstream's `find`
  /// defaults to `exact: true` where `findAll` does not.
  Mutation<Object?, Object?, Object?>? find(
    MutationKey mutationKey, {
    MutationFilters? filters,
  }) {
    final resolved = (filters ?? const MutationFilters(exact: true)).copyWith(
      mutationKey: mutationKey,
    );
    return mutations.firstWhereOrNull(resolved.matches);
  }

  void notify(MutationCacheEvent event) {
    notifyManager.batch(() {
      for (final listener in List.of(listeners)) {
        listener(event);
      }
    });
  }

  /// Resumes every paused mutation.
  ///
  /// Scope gating re-serialises them: they all resume, but the ones sharing a
  /// scope pause again immediately behind whichever one goes first.
  Future<void> resumePausedMutations() {
    final paused = mutations.where((m) => m.state.isPaused).toList();

    return notifyManager.batch(
      () => Future.wait(
        paused.map(
          (mutation) => mutation.resume().then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          ),
        ),
      ),
    ).then((_) {});
  }

  // --- MutationHost ---------------------------------------------------------

  @override
  bool canRun(Mutation<Object?, Object?, Object?> mutation) {
    final scope = mutation.scope;
    if (scope == null) {
      // An unscoped mutation never queues behind anything.
      return true;
    }
    final firstPending = _scopes[scope]?.firstWhereOrNull(
      (m) => m.state.status == MutationStatus.pending,
    );
    // It may run if nothing in its scope is pending (starting), or if it is
    // itself the one at the front (continuing).
    return firstPending == null || identical(firstPending, mutation);
  }

  @override
  Future<void> runNext(Mutation<Object?, Object?, Object?> mutation) async {
    final scope = mutation.scope;
    if (scope == null) {
      return;
    }
    final next = _scopes[scope]?.firstWhereOrNull(
      (m) => !identical(m, mutation) && m.state.isPaused,
    );
    await next?.resume();
  }

  @override
  void onMutationRemovalRequested(
    Mutation<Object?, Object?, Object?> mutation,
  ) => remove(mutation);

  @override
  void onMutationUpdated(
    Mutation<Object?, Object?, Object?> mutation,
    MutationAction action,
  ) => notify(MutationUpdated(mutation, action));

  @override
  void onMutationObserverAdded(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  ) => notify(MutationObserverAdded(mutation, observer));

  @override
  void onMutationObserverRemoved(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  ) => notify(MutationObserverRemoved(mutation, observer));

  @override
  Future<void> onMutationMutate(
    Mutation<Object?, Object?, Object?> mutation,
    Object? variables,
    MutationFunctionContext context,
  ) async => onMutate?.call(variables, mutation, context);

  @override
  Future<void> onMutationSuccess(
    Mutation<Object?, Object?, Object?> mutation,
    Object? data,
    Object? variables,
    Object? onMutateResult,
    MutationFunctionContext context,
  ) async =>
      onSuccess?.call(data, variables, onMutateResult, mutation, context);

  @override
  Future<void> onMutationError(
    Mutation<Object?, Object?, Object?> mutation,
    Object error,
    StackTrace stackTrace,
    Object? variables,
    Object? onMutateResult,
    MutationFunctionContext context,
  ) async => onError?.call(
    error,
    stackTrace,
    variables,
    onMutateResult,
    mutation,
    context,
  );

  @override
  Future<void> onMutationSettled(
    Mutation<Object?, Object?, Object?> mutation,
    Object? data,
    Object? error,
    StackTrace? stackTrace,
    Object? variables,
    Object? onMutateResult,
    MutationFunctionContext context,
  ) async => onSettled?.call(
    data,
    error,
    stackTrace,
    variables,
    onMutateResult,
    mutation,
    context,
  );
}
