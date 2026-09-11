/// Port of `query-core/src/mutationCache.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'filters.dart';
import 'mutation.dart';
import 'mutation_options.dart';
import 'query_client.dart';
import 'subscribable.dart';

/// Something happened to a mutation in the cache. The mutation-side twin of
/// `QueryCacheEvent`, delivered to [MutationCache.subscribe] listeners.
@immutable
sealed class MutationCacheEvent {
  /// Creates an event about [mutation].
  const MutationCacheEvent(this.mutation);

  /// The mutation the event is about, with its type arguments erased — a cache
  /// listener sees every mutation there is.
  final Mutation<Object?, Object?, Object?> mutation;
}

/// A mutation was created and appended to the cache, which happens the moment
/// `mutate` is called (or an observer is built with a restored state).
/// Upstream's `added` event.
final class MutationAdded extends MutationCacheEvent {
  /// Creates the event for [mutation].
  const MutationAdded(super.mutation);
}

/// A mutation left the cache: garbage-collected after its last observer
/// left, or removed through [MutationCache.remove] or [MutationCache.clear].
/// Upstream's `removed` event.
final class MutationRemoved extends MutationCacheEvent {
  /// Creates the event for [mutation].
  const MutationRemoved(super.mutation);
}

/// A mutation's state changed. Emitted for every dispatched [MutationAction]
/// — pending, success, error, pause, continue and the rest. Upstream's
/// `updated` event.
final class MutationUpdated extends MutationCacheEvent {
  /// Creates the event for [mutation], carrying the [action] that changed it.
  const MutationUpdated(super.mutation, this.action);

  /// The transition that produced the mutation's new state. Sealed, so a
  /// listener can `switch` over it exhaustively.
  final MutationAction action;
}

/// An observer subscribed to the mutation, which also cancels its pending
/// collection. Upstream's `observerAdded` event.
final class MutationObserverAdded extends MutationCacheEvent {
  /// Creates the event for [mutation] and the [observer] that attached.
  const MutationObserverAdded(super.mutation, this.observer);

  /// The observer that attached. Read-only from outside: an identity to hold
  /// and compare, not something to drive.
  final MutationObserverRef observer;
}

/// An observer unsubscribed from the mutation; when it was the last one, the
/// collection timer has been armed by the time this fires. Upstream's
/// `observerRemoved` event.
final class MutationObserverRemoved extends MutationCacheEvent {
  /// Creates the event for [mutation] and the [observer] that detached.
  const MutationObserverRemoved(super.mutation, this.observer);

  /// The observer that detached. Read-only from outside.
  final MutationObserverRef observer;
}

/// An observer's options were replaced while it stayed attached to the same
/// mutation — a rebuild that changed a callback or `retry`, say. Upstream's
/// `observerOptionsUpdated` event.
final class MutationObserverOptionsUpdated extends MutationCacheEvent {
  /// Creates the event for [mutation] and the [observer] whose options changed.
  const MutationObserverOptionsUpdated(super.mutation, this.observer);

  /// The observer whose options changed. Read-only from outside.
  final MutationObserverRef observer;
}

/// Every mutation, in submission order.
class MutationCache
    extends Subscribable<void Function(MutationCacheEvent event)>
    implements MutationCacheRef {
  /// Creates an empty cache. All four hooks are optional and cache-wide; a
  /// [QueryClient] constructs one of these when none is passed to it.
  MutationCache({this.onMutate, this.onSuccess, this.onError, this.onSettled});

  /// Cache-wide hooks. They run *before* the per-mutation callbacks, which is
  /// what lets a global handler set something up that a local one consumes.
  final FutureOr<void> Function(
    Object? variables,
    Mutation<Object?, Object?, Object?> mutation,
  )? onMutate;

  /// Runs after any mutation succeeds, before the mutation's own `onSuccess`,
  /// with the data, the variables, and whatever the `onMutate` hook returned.
  /// Upstream's `MutationCacheConfig.onSuccess`.
  final FutureOr<void> Function(
    Object? data,
    Object? variables,
    Object? onMutateResult,
    Mutation<Object?, Object?, Object?> mutation,
  )? onSuccess;

  /// Runs after any mutation fails for good, before the mutation's own
  /// `onError`, with the error, the variables, and the `onMutate` result.
  /// Upstream's `MutationCacheConfig.onError`.
  final FutureOr<void> Function(
    Object error,
    StackTrace stackTrace,
    Object? variables,
    Object? onMutateResult,
    Mutation<Object?, Object?, Object?> mutation,
  )? onError;

  /// Runs after any mutation settles, success or failure, before the
  /// mutation's own `onSettled`, with whichever of data and error applies.
  /// Upstream's `MutationCacheConfig.onSettled`.
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

  /// Every mutation in the cache, in submission order, as a copy: safe to
  /// iterate while removing. Upstream's `getAll`.
  List<Mutation<Object?, Object?, Object?>> get mutations =>
      List<Mutation<Object?, Object?, Object?>>.of(_mutations);

  /// Creates a mutation for [options], assigns it the next id, adds it to the
  /// cache and returns it. Unlike a query, every call creates a new entry —
  /// mutations are never shared by key. [state] is the door a persistence
  /// layer restores an offline mutation through.
  ///
  /// A `pending` state must carry the variables to run with (`hasVariables`),
  /// unless `null` is a `TVariables` and therefore a value of its own —
  /// `continueMutation` has nothing to call the function with otherwise, so
  /// the mutation would sit in the cache forever and
  /// `resumePausedMutations` would report success having run nothing. One
  /// without is refused with an [ArgumentError] in every build mode, as
  /// `QueryCache.build` refuses a data-less `success` state (ninth review,
  /// 2026-09-10, C8 and C12; the twin closed with the same door).
  Mutation<TData, TVariables, TOnMutateResult>
      build<TData, TVariables, TOnMutateResult>(
    QueryClient client,
    DefaultedMutationOptions<TData, TVariables, TOnMutateResult> options, {
    MutationState<TData, TVariables, TOnMutateResult>? state,
  }) {
    if (state != null &&
        state.status == MutationStatus.pending &&
        !state.hasVariables &&
        null is! TVariables) {
      throw ArgumentError.value(
        state,
        'state',
        'A MutationState restored through MutationCache.build with status == '
            'pending must have hasVariables == true when TVariables '
            '($TVariables) is not nullable: continuing it means running the '
            'mutation function, and there is nothing to run it with. This is '
            'the persistence door; check what was persisted',
      );
    }
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

  /// Emits [MutationObserverOptionsUpdated]. Called by the observer's
  /// `setOptions` when it stays on the same mutation; not for user code.
  @internal
  void notifyObserverOptionsUpdated(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  ) =>
      notify(MutationObserverOptionsUpdated(mutation, observer));

  /// Appends [mutation] to the cache and emits [MutationAdded]. [build] is the
  /// usual way in; this is upstream's `add`, for a mutation constructed by
  /// hand.
  void add(Mutation<Object?, Object?, Object?> mutation) {
    _mutations.add(mutation);
    notify(MutationAdded(mutation));
  }

  /// Takes [mutation] out of the cache, stopping its collection timer, and
  /// emits [MutationRemoved]. A running mutation is not cancelled — its
  /// retryer finishes on its own, as upstream's does. Upstream's `remove`.
  void remove(Mutation<Object?, Object?, Object?> mutation) {
    if (_mutations.remove(mutation)) {
      mutation.destroy();
    }
    // Notified even when it was not in the cache: a caller that asked for a
    // removal gets told the removal happened, exactly once, either way.
    notify(MutationRemoved(mutation));
  }

  /// Removes every mutation, one [MutationRemoved] each. `QueryClient.clear`
  /// calls this together with the query cache's.
  void clear() {
    for (final mutation in mutations) {
      remove(mutation);
    }
  }

  /// Every mutation matching [filters], in submission order — all of them
  /// when the filters are empty. Partial key matching by default, as
  /// upstream's `findAll`. Iterates a copy, as `QueryCache` does: a predicate
  /// may remove the mutation it is shown.
  List<Mutation<Object?, Object?, Object?>> findAll({
    MutationFilters filters = const MutationFilters(),
  }) =>
      mutations.where(filters.matches).toList();

  /// The first matching mutation. An unset `exact` means an exact match
  /// here, as upstream's `find` defaults `{ exact: true, ...filters }`.
  Mutation<Object?, Object?, Object?>? find(
      {required MutationFilters filters}) {
    for (final mutation in mutations) {
      if (filters.matches(mutation, exactByDefault: true)) {
        return mutation;
      }
    }
    return null;
  }

  /// Each listener is isolated, as observer listeners are: a throw is
  /// reported to the zone and the rest still run. Unisolated, a devtools or
  /// logging subscriber that threw on a `failed` action blew up the retryer's
  /// loop and left the mutation pending forever.
  void notify(MutationCacheEvent event) {
    for (final listener in List.of(listeners)) {
      try {
        listener(event);
      } catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }
    }
  }

  /// Releases every paused mutation that can run right now.
  ///
  /// All of them are continued together, as upstream does: what serialises
  /// mutations is [canRunMutation]'s scope rule, not the order they are
  /// resumed in. Resuming them one after another would make every paused
  /// mutation wait for the slowest one before it.
  ///
  /// A mutation the network would not let go on is left alone — it would
  /// only park on the same wait, and the returned future would not complete
  /// until the network came back. The gate is per mutation and it is the
  /// retryer's own network rule for continuing ([Mutation.canResume]): an
  /// `always` mutation paused for focus or its scope is resumed offline, an
  /// `online` one is not, and neither is an `offlineFirst` one paused
  /// mid-retry, which may begin offline but cannot retry offline. A pause for
  /// focus or for the scope's turn is awaited, as upstream awaits it: its own
  /// event releases it. Upstream gates the whole call on
  /// `onlineManager.isOnline()` in `QueryClient.resumePausedMutations`
  /// instead (fifth review, 2026-09-09; the gate was the *start* rule until
  /// the ninth review, 2026-09-10, C4). Completes when the resumed runs have
  /// settled — callbacks run, states moved on — since `continueMutation`
  /// hands on the run's own future (ninth review, 2026-09-10, C10).
  Future<void> resumePaused() async {
    final paused = _mutations
        .where((mutation) => mutation.state.isPaused && mutation.canResume)
        .toList();
    await Future.wait<void>(
      // Errors belong to each mutation's state, not to whoever resumed it —
      // upstream's `mutation.continue().catch(noop)`.
      paused.map(
        (mutation) => mutation.continueMutation().catchError((Object _) {}),
      ),
    );
  }

  /// The scope a mutation is serialised under, or null for an unscoped one.
  ///
  /// Unscoped mutations are never serialised — not even against themselves —
  /// so they get no synthetic scope. Falling back to the mutation's own id
  /// would put it in the same namespace as user-chosen scope ids, and
  /// `MutationScope(3)` would then queue behind whichever unscoped mutation
  /// happened to be the third one created.
  ///
  /// Read off the mutation's *run* rather than its options: a `setOptions`
  /// during a run does not move the mutation between queues (see
  /// [Mutation.schedulingScope]).
  Object? _scopeOf(Mutation<Object?, Object?, Object?> mutation) =>
      mutation.schedulingScope?.id;

  @override
  @internal
  bool canRunMutation(Mutation<Object?, Object?, Object?> mutation) {
    final scope = _scopeOf(mutation);
    if (scope == null) {
      return true;
    }
    // Upstream's rule exactly: a scoped mutation may run when no mutation in
    // its scope is pending, or when it is itself the *first* pending one (the
    // continue case). Stopping at the mutation's own position let one built
    // earlier start while one built later was already running.
    for (final other in _mutations) {
      if (_scopeOf(other) == scope &&
          other.state.status == MutationStatus.pending) {
        return identical(other, mutation);
      }
    }
    return true;
  }

  @override
  @internal
  void onMutationSettled(Mutation<Object?, Object?, Object?> mutation) {
    final scope = _scopeOf(mutation);
    if (scope == null) {
      return;
    }
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
  @internal
  void onMutationStateUpdated(
    Mutation<Object?, Object?, Object?> mutation,
    MutationAction action,
  ) =>
      notify(MutationUpdated(mutation, action));

  @override
  @internal
  void onMutationObserverAdded(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  ) =>
      notify(MutationObserverAdded(mutation, observer));

  @override
  @internal
  void onMutationObserverRemoved(
    Mutation<Object?, Object?, Object?> mutation,
    MutationObserverRef observer,
  ) =>
      notify(MutationObserverRemoved(mutation, observer));

  @override
  @internal
  void onMutationRemovalRequested(
    Mutation<Object?, Object?, Object?> mutation,
  ) =>
      remove(mutation);

  @override
  @internal
  FutureOr<void> onMutationStarting(
    Mutation<Object?, Object?, Object?> mutation,
    Object? variables,
  ) =>
      onMutate?.call(variables, mutation);

  @override
  @internal
  FutureOr<void> onMutationSuccess(
    Mutation<Object?, Object?, Object?> mutation,
    Object? data,
    Object? variables,
    Object? onMutateResult,
  ) async {
    await onSuccess?.call(data, variables, onMutateResult, mutation);
  }

  @override
  @internal
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
  @internal
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
