/// The mutation cache and its events.
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
///
/// Sealed, so a listener can `switch` over the variants exhaustively.
///
/// {@category Advanced}
@immutable
sealed class MutationCacheEvent {
  /// Creates an event about [mutation].
  const MutationCacheEvent(this.mutation);

  /// The mutation the event is about, with its type arguments erased — a cache
  /// listener sees every mutation there is.
  final Mutation<Object?, Object?, Object?> mutation;
}

/// A mutation was created and appended to the cache, which happens the moment
/// `mutate` is called (or a restored mutation is built into the cache).
/// TanStack Query calls this the `added` event.
///
/// {@category Advanced}
final class MutationAdded extends MutationCacheEvent {
  /// Creates the event announcing that [mutation] joined the cache.
  const MutationAdded(super.mutation);
}

/// A mutation left the cache: garbage-collected after its last observer
/// left, or removed through [MutationCache.remove] or [MutationCache.clear].
/// TanStack Query calls this the `removed` event.
///
/// {@category Advanced}
final class MutationRemoved extends MutationCacheEvent {
  /// Creates the event announcing that [mutation] left the cache.
  const MutationRemoved(super.mutation);
}

/// A mutation's state changed. Emitted for every dispatched [MutationAction]
/// — pending, success, error, pause, continue and the rest. TanStack Query
/// calls this the `updated` event.
///
/// {@category Advanced}
final class MutationUpdated extends MutationCacheEvent {
  /// Creates the event for [mutation], carrying the [action] that changed it.
  const MutationUpdated(super.mutation, this.action);

  /// The transition that produced the mutation's new state. Sealed, so a
  /// listener can `switch` over it exhaustively.
  final MutationAction action;
}

/// An observer subscribed to the mutation, which also cancels its pending
/// collection. TanStack Query calls this the `observerAdded` event.
///
/// {@category Advanced}
final class MutationObserverAdded extends MutationCacheEvent {
  /// Creates the event announcing that [observer] attached to [mutation].
  const MutationObserverAdded(super.mutation, this.observer);

  /// The observer that attached. Read-only from outside: an identity to hold
  /// and compare, not something to drive.
  final MutationObserverRef observer;
}

/// An observer unsubscribed from the mutation; when it was the last one, the
/// collection timer has been armed by the time this fires. TanStack Query
/// calls this the `observerRemoved` event.
///
/// {@category Advanced}
final class MutationObserverRemoved extends MutationCacheEvent {
  /// Creates the event announcing that [observer] detached from [mutation].
  const MutationObserverRemoved(super.mutation, this.observer);

  /// The observer that detached. Read-only from outside: an identity to hold
  /// and compare, not something to drive.
  final MutationObserverRef observer;
}

/// An observer's options were replaced while it stayed attached to the same
/// mutation — a rebuild that changed a callback or `retry`, say. TanStack
/// Query calls this the `observerOptionsUpdated` event.
///
/// {@category Advanced}
final class MutationObserverOptionsUpdated extends MutationCacheEvent {
  /// Creates the event for [mutation] and the [observer] whose options changed.
  const MutationObserverOptionsUpdated(super.mutation, this.observer);

  /// The observer whose options changed. Read-only from outside.
  final MutationObserverRef observer;
}

/// Every mutation the client has run, in submission order.
///
/// Each `QueryClient` owns one, reachable as `client.mutationCache`. Unlike
/// queries, mutations are never shared: every `mutate` call adds a new
/// [Mutation], which stays here while it runs and for its `gcTime` (five
/// minutes by default) after the last observer leaves.
///
/// Most apps touch it in two ways:
///
/// * **Cache-wide callbacks.** [onMutate], [onSuccess], [onError] and
///   [onSettled], passed to the constructor, run for every mutation — the
///   place for a global error toast or for logging. Each runs *before* the
///   mutation's own `MutationOptions` callback of the same name, and each
///   returned future is awaited before the next callback starts; the
///   mutation stays `pending` until all of them are done. The per-call
///   `MutateCallbacks` passed to `mutate` run last, after the result has
///   settled.
/// * **Inspection.** [findAll] and [find] select mutations by
///   `MutationFilters`, [mutations] lists them all, and [subscribe] reports
///   every [MutationCacheEvent] — for devtools, logging or persistence.
///
/// ```dart
/// final client = QueryClient(
///   mutationCache: MutationCache(
///     onError: (error, stackTrace, variables, onMutateResult, mutation) {
///       showToast('Could not save: $error');
///     },
///     onSuccess: (data, variables, onMutateResult, mutation) {
///       log('Mutation ${mutation.mutationId} succeeded');
///     },
///   ),
/// );
/// ```
///
/// {@category Caches}
class MutationCache
    extends Subscribable<void Function(MutationCacheEvent event)>
    implements MutationCacheRef {
  /// Creates an empty cache. All four hooks are optional and cache-wide; a
  /// [QueryClient] constructs one of these when none is passed to it.
  ///
  /// The hooks are final: a hook whose behaviour has to change closes over
  /// something its owner can swap, and [subscribe] is how to watch a cache
  /// without handling anything for it.
  MutationCache({this.onMutate, this.onSuccess, this.onError, this.onSettled});

  /// Runs when any mutation is submitted, before the mutation's own
  /// `onMutate`, with the variables and the mutation. A returned future is
  /// awaited before the mutation's `onMutate` runs; what it returns is
  /// ignored. A throw fails the mutation without running its function. No
  /// default.
  ///
  /// All four hooks run *before* the per-mutation callbacks, which is what
  /// lets a global handler set something up that a local one consumes.
  final FutureOr<void> Function(
    Object? variables,
    Mutation<Object?, Object?, Object?> mutation,
  )? onMutate;

  /// Runs after any mutation succeeds, before the mutation's own `onSuccess`,
  /// with the data, the variables, what the mutation's `onMutate` returned,
  /// and the mutation. A returned future is awaited. A throw turns the
  /// success into an error, as a throwing `onSuccess` does. No default.
  final FutureOr<void> Function(
    Object? data,
    Object? variables,
    Object? onMutateResult,
    Mutation<Object?, Object?, Object?> mutation,
  )? onSuccess;

  /// Runs after any mutation fails for good, before the mutation's own
  /// `onError`, with the error and its stack trace, the variables, what the
  /// mutation's `onMutate` returned, and the mutation. A returned future is
  /// awaited; a throw is reported to the zone and the remaining callbacks
  /// still run. No default.
  final FutureOr<void> Function(
    Object error,
    StackTrace stackTrace,
    Object? variables,
    Object? onMutateResult,
    Mutation<Object?, Object?, Object?> mutation,
  )? onError;

  /// Runs after any mutation settles, success or failure, before the
  /// mutation's own `onSettled`, with whichever of data and error applies,
  /// the variables, what the mutation's `onMutate` returned, and the
  /// mutation. A returned future is awaited. No default.
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
  final Map<Object, Mutation<Object?, Object?, Object?>> _scopeOwners = {};

  /// Mutations [remove] took out of the cache while they were the first
  /// `pending` entry of an unclaimed scope *and* had a run still to settle —
  /// a restored head cancelled and then removed. Out of the cache,
  /// [onMutationSettled] can no longer see where in line such a run stood,
  /// so what it was is written down while it still can be.
  final Set<Mutation<Object?, Object?, Object?>> _removedRunningHeads =
      Set<Mutation<Object?, Object?, Object?>>.identity();

  /// Every mutation in the cache, in submission order, as a copy: safe to
  /// iterate while removing. (TanStack Query: `getAll()`.)
  List<Mutation<Object?, Object?, Object?>> get mutations =>
      List<Mutation<Object?, Object?, Object?>>.of(_mutations);

  /// Creates a mutation for [options], assigns it the next id, adds it to the
  /// cache and returns it. Unlike a query, every call creates a new entry —
  /// mutations are never shared by key. [state] is the door a persistence
  /// layer restores an offline mutation through.
  ///
  /// Usually called by `MutationObserver.mutate`; call it yourself to restore
  /// a mutation from persistence, and `QueryClient.resumePausedMutations`
  /// then runs it.
  ///
  /// A restored state is validated. A `pending` state must carry the
  /// variables to run with (`hasVariables`), unless `null` is a `TVariables`
  /// and therefore a value of its own — otherwise there is nothing to call
  /// the function with, and the mutation would sit in the cache forever. A
  /// `success` state must carry data unless `null` is a `TData`. Either
  /// violation throws an [ArgumentError] in every build mode.
  ///
  /// A restored `pending` state is normalised to `isPaused: true`. A
  /// mutation that was in flight when the process died is not in flight in
  /// this one; paused, `resumePausedMutations` continues it, where an
  /// un-paused entry would block every later mutation in its scope — and
  /// the client's reconnect and focus refetches, which wait for resumed
  /// mutations — for good.
  Mutation<TData, TVariables, TOnMutateResult>
      build<TData, TVariables, TOnMutateResult>(
    QueryClient client,
    DefaultedMutationOptions<TData, TVariables, TOnMutateResult> options, {
    MutationState<TData, TVariables, TOnMutateResult>? state,
  }) {
    state?.validate();
    final mutation = Mutation<TData, TVariables, TOnMutateResult>(
      client: client,
      cache: this,
      mutationId: _nextMutationId++,
      options: options,
      state: state != null &&
              state.status == MutationStatus.pending &&
              !state.isPaused
          ? state.copyWith(isPaused: true)
          : state,
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
  /// usual way in; this is for a mutation constructed by hand.
  ///
  /// Adding the same instance twice is a no-op. An instance previously
  /// removed from the cache is terminal and throws [StateError].
  void add(Mutation<Object?, Object?, Object?> mutation) {
    if (_mutations.contains(mutation)) return;
    if (mutation.isRemoved) {
      throw StateError('A removed Mutation cannot be added again.');
    }
    _mutations.add(mutation);
    notify(MutationAdded(mutation));
  }

  /// Takes [mutation] out of the cache, stopping its collection timer, and
  /// emits [MutationRemoved].
  ///
  /// A running mutation is told to stop retrying. The attempt in flight
  /// still settles, but a backoff is cut short and the mutation fails with
  /// its last error — or with a `CancelledError` when it was paused — and
  /// its error callbacks run a few microtasks after the removal. (TanStack
  /// Query lets a removed mutation keep retrying.)
  ///
  /// Removing a restored mutation at the head of a [MutationScope], one that
  /// never ran, lets the next one in that scope run, as its settling would
  /// have. That hand-over happens one microtask after the removal, so a loop
  /// removing several mutations never starts one of them mid-removal.
  void remove(Mutation<Object?, Object?, Object?> mutation) {
    // The scope is captured *here*, not re-derived in the microtask: a
    // `setOptions` between the removal and the release moves the entry's
    // scheduling scope, and the release then looked for waiters of a queue
    // this entry was never blocking, leaving the one it was blocking paused
    // for good.
    final releasedScope =
        _isUnstartedScopeHead(mutation) ? _scopeOf(mutation) : null;
    if (mutation.isRunning && _isUnclaimedScopeHead(mutation)) {
      // Its run's `finally` releases the scope, and by then the entry is
      // gone from the line it headed.
      _removedRunningHeads.add(mutation);
    }
    if (_mutations.remove(mutation)) {
      mutation.destroy();
      if (releasedScope != null) {
        scheduleMicrotask(() => _releaseScope(releasedScope, mutation));
      }
    }
    // Notified even when it was not in the cache: a caller that asked for a
    // removal gets told the removal happened, exactly once, either way.
    notify(MutationRemoved(mutation));
  }

  /// Whether [mutation] is the first `pending` entry of its scope and has no
  /// run of its own — a restored head, whose removal is what releases the
  /// scope. A running head releases it from its own `finally`.
  bool _isUnstartedScopeHead(Mutation<Object?, Object?, Object?> mutation) =>
      !mutation.isRunning && _isUnclaimedScopeHead(mutation);

  /// Whether [mutation] is the first `pending` entry of its scope while
  /// nobody has claimed that scope — the one a release on its behalf would
  /// rightly hand on from.
  bool _isUnclaimedScopeHead(Mutation<Object?, Object?, Object?> mutation) {
    final scope = _scopeOf(mutation);
    if (scope == null ||
        _scopeOwners.containsKey(scope) ||
        mutation.state.status != MutationStatus.pending) {
      return false;
    }
    for (final other in _mutations) {
      if (_scopeOf(other) == scope &&
          other.state.status == MutationStatus.pending) {
        return identical(other, mutation);
      }
    }
    return false;
  }

  /// Removes every mutation, one [MutationRemoved] each. `QueryClient.clear`
  /// calls this together with the query cache's.
  ///
  /// Running mutations stop retrying, as with [remove], and `clear()` never
  /// starts a mutation that was queued in a [MutationScope]. The events are
  /// emitted after every entry is gone, so a listener sees the cache in its
  /// final state and a `clear()` it re-enters finds nothing left to
  /// remove.
  void clear() {
    final removed = mutations;
    _mutations.clear();
    _removedRunningHeads.clear();
    for (final mutation in removed) {
      mutation.destroy();
    }
    for (final mutation in removed) {
      notify(MutationRemoved(mutation));
    }
  }

  /// Every mutation matching [filters], in submission order — all of them
  /// when the filters are empty. A `mutationKey` filter matches as a prefix
  /// unless `exact` is set. Iterates a copy: a predicate may remove the
  /// mutation it is shown.
  ///
  /// ```dart
  /// final pendingSaves = client.mutationCache.findAll(
  ///   filters: MutationFilters(
  ///     mutationKey: QueryKey(['todos']),
  ///     status: MutationStatus.pending,
  ///   ),
  /// );
  /// ```
  List<Mutation<Object?, Object?, Object?>> findAll({
    MutationFilters filters = const MutationFilters(),
  }) =>
      mutations.where(filters.matches).toList();

  /// The first matching mutation in submission order, or `null`. Unlike
  /// [findAll], an unset `exact` means an exact key match here.
  Mutation<Object?, Object?, Object?>? find(
      {required MutationFilters filters}) {
    for (final mutation in mutations) {
      if (filters.matches(mutation, exactByDefault: true)) {
        return mutation;
      }
    }
    return null;
  }

  /// Delivers [event] to every [subscribe] listener. Called by the cache
  /// itself; rarely useful from outside.
  ///
  /// Each listener is isolated: a throw is reported to the zone and the rest
  /// still run, so a failing logging subscriber cannot break a mutation.
  void notify(MutationCacheEvent event) =>
      notifyListeners((listener) => listener(event));

  /// Releases every paused mutation that can run right now.
  /// `QueryClient.resumePausedMutations` calls this, and a mounted client
  /// does on reconnect and on focus.
  ///
  /// All of them are continued together; mutations in one [MutationScope]
  /// still run one at a time, in order. Completes when the resumed runs have
  /// settled — callbacks run, states moved on. Errors stay with each
  /// mutation's state and callbacks; this future does not throw them.
  ///
  /// A mutation the network would not let go on is left alone, so the
  /// returned future never waits for the network to come back: an `online`
  /// mutation is not resumed offline, nor is an `offlineFirst` one paused
  /// mid-retry, while an `always` mutation is. A mutation waiting for focus
  /// or for its scope's turn is resumed and awaited — unless the mutation
  /// holding its scope cannot go on either; it then runs when that one
  /// settles, as any queued mutation does. (TanStack Query instead resumes
  /// nothing while offline.)
  Future<void> resumePaused() async {
    final paused = _mutations
        .where(
          (mutation) =>
              mutation.state.isPaused &&
              mutation.canResume &&
              _scopeCanMove(mutation),
        )
        .toList();
    await Future.wait<void>(
      // Errors belong to each mutation's state, not to whoever resumed it.
      paused.map(
        (mutation) => mutation.continueMutation().catchError((Object _) {}),
      ),
    );
  }

  /// Whether the mutation holding [mutation]'s scope — its owner, or the
  /// first pending mutation in it when nobody owns it yet — can get on under
  /// the network as it is. Always true for an unscoped mutation and for the
  /// holder itself. Reads the owners and never claims: see [canRunMutation].
  bool _scopeCanMove(Mutation<Object?, Object?, Object?> mutation) {
    final scope = _scopeOf(mutation);
    if (scope == null) {
      return true;
    }
    var holder = _scopeOwners[scope];
    if (holder == null) {
      for (final other in _mutations) {
        if (_scopeOf(other) == scope &&
            other.state.status == MutationStatus.pending) {
          holder = other;
          break;
        }
      }
    }
    return holder == null || identical(holder, mutation) || holder.canResume;
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

  /// Answers whether [mutation] may run now, and **claims** the scope for it
  /// when the answer is yes: the owner is recorded here and released only by
  /// [onMutationSettled]. So only a run that will settle may ask — the
  /// retryer before an attempt, and `Mutation`'s own pending dispatches,
  /// which the run's `finally` balances. A "could it run?" probe from
  /// anywhere else would take the scope and never give it back.
  @override
  @internal
  bool canRunMutation(Mutation<Object?, Object?, Object?> mutation) {
    final scope = _scopeOf(mutation);
    if (scope == null) {
      return true;
    }
    final owner = _scopeOwners[scope];
    if (owner != null) return identical(owner, mutation);
    // Preserve restored/pending queue order, but reserve the owner before a
    // pending notification can reenter. Cache insertion order alone can let
    // an earlier idle entry overtake a transport that already started.
    for (final other in _mutations) {
      if (_scopeOf(other) == scope &&
          other.state.status == MutationStatus.pending) {
        if (!identical(other, mutation)) return false;
        break;
      }
    }
    _scopeOwners[scope] = mutation;
    return true;
  }

  @override
  @internal
  void onMutationSettled(Mutation<Object?, Object?, Object?> mutation) {
    final scope = _scopeOf(mutation);
    if (scope == null) {
      return;
    }
    // A run that settles without the scope ever having been claimed — a
    // restored mutation cancelled before it could start — holds it only when
    // it was first in line. Behind an earlier pending mate it held nothing,
    // and handing the scope on would start that mate although nobody resumed
    // it; the mate hands on itself when it settles.
    //
    // Where it stood is read off the cache, so an entry already removed from
    // it is judged by what [remove] wrote down: a head removed mid-run still
    // hands on, as `cancel` alone and `remove` alone do.
    final removedHead = _removedRunningHeads.remove(mutation);
    if (!_scopeOwners.containsKey(scope) && !removedHead) {
      if (!_mutations.any((other) => identical(other, mutation))) return;
      for (final other in _mutations) {
        if (identical(other, mutation)) break;
        if (_scopeOf(other) == scope &&
            other.state.status == MutationStatus.pending) {
          return;
        }
      }
    }
    _releaseScope(scope, mutation);
  }

  /// Hands [scope] to its next waiter, now that [settled] no longer holds it.
  ///
  /// Takes the scope rather than reading it off [settled]: the deferred
  /// release in [remove] runs a microtask after the entry left the cache, and
  /// by then the entry's own scope can have moved.
  void _releaseScope(
    Object scope,
    Mutation<Object?, Object?, Object?> settled,
  ) {
    if (identical(_scopeOwners[scope], settled)) _scopeOwners.remove(scope);
    if (_scopeOwners.containsKey(scope)) return;
    for (final other in _mutations) {
      if (!identical(other, settled) &&
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
