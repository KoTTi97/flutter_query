/// One cache entry — `Query` — with its state transitions and the types a
/// fetch is described by.
library;

import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

import 'cancel_token.dart';
import 'option_values.dart';
import 'query_client.dart';
import 'query_key.dart';
import 'query_options.dart';
import 'query_state.dart';
import 'removable.dart';
import 'retryer.dart';
import 'structural_sharing.dart';

/// What a [Query] needs from an observer, without knowing what an observer is.
///
/// Exported because the cache's `QueryObserverAdded` and friends name their
/// observer through it, so a cache listener can hold and compare one. That is
/// the whole public use: implementing it yourself is not supported, and
/// `QueryObserver` is the one implementation. Its members are the plumbing
/// between a query and its observer, `@internal` on the interface and on
/// `QueryObserver`'s overrides alike — calling one from outside the package
/// is an analyzer warning.
///
/// {@category Advanced}
abstract interface class QueryObserverRef {
  /// The query's state changed.
  @internal
  void onQueryUpdate();

  /// Whether this observer's `enabled` currently resolves to true.
  @internal
  bool get isEnabledForQuery;

  /// Whether this observer's own `staleTime` is [StaleTimeStatic].
  @internal
  bool get isStaticForQuery;

  /// Whether this observer's current result considers the data stale.
  @internal
  bool get currentResultIsStale;

  /// Whether this observer's `refetchOnWindowFocus` asks for a refetch when the
  /// app returns to the foreground, given the data it currently sees.
  @internal
  bool shouldFetchOnWindowFocus();

  /// Whether this observer's `refetchOnReconnect` asks for a refetch when the
  /// device comes back online, given the data it currently sees.
  @internal
  bool shouldFetchOnReconnect();

  /// Refetch without cancelling a fetch that is already running.
  @internal
  void refetchOnEvent();

  /// The options this observer contributes when the query itself has none.
  @internal
  DefaultedQueryOptions<Object?> get observerQueryOptions;
}

/// What a [Query] needs from its cache.
abstract interface class QueryCacheRef {
  /// Told after every dispatch, with the [action] that produced [query]'s new
  /// state; the cache turns it into a `QueryUpdated` event.
  void onQueryStateUpdated(Query<Object?> query, QueryAction action);

  /// Told when [query]'s collection timer fired with nothing observing it and
  /// no fetch running; the cache removes it.
  void onQueryRemovalRequested(Query<Object?> query);

  /// Told when a fetch of [query] resolved with [data]; the cache runs its
  /// `onSuccess` and `onSettled` hooks.
  void onQueryFetchSuccess(Query<Object?> query, Object? data);

  /// Told when a fetch of [query] rejected for good — retries exhausted, or a
  /// cancel that is neither silent nor reverting (`cancelQueries(revert:
  /// false)`); the cache runs its `onError` and `onSettled` hooks. A silent
  /// cancel and the default reverting one report nothing.
  void onQueryFetchError(
    Query<Object?> query,
    Object error,
    StackTrace stackTrace,
  );

  /// Told when [observer] attached to [query]; the cache turns it into a
  /// `QueryObserverAdded` event.
  void onQueryObserverAdded(Query<Object?> query, QueryObserverRef observer);

  /// Told when [observer] detached from [query]; the cache turns it into a
  /// `QueryObserverRemoved` event.
  void onQueryObserverRemoved(Query<Object?> query, QueryObserverRef observer);
}

/// Rewrites how a fetch runs.
///
/// Infinite queries use it to turn one fetch into a loop over pages; nothing
/// else does, and application code never sets one. TanStack Query calls this
/// a `QueryBehavior`.
///
/// {@category Advanced}
abstract interface class FetchBehavior<TQueryData> {
  /// Called once per fetch, before the retryer is built, to rewrite
  /// [FetchContext.fetchFn] — and read anything else the context carries — for
  /// [query].
  void onFetch(FetchContext<TQueryData> context, Query<TQueryData> query);
}

/// The mutable description of one fetch, handed to a [FetchBehavior], which
/// may replace [fetchFn] to change what the fetch does.
///
/// {@category Advanced}
class FetchContext<TQueryData> {
  /// Creates the description of one fetch. Built by [Query.fetch]; a behaviour
  /// receives one, it does not make one.
  @internal
  FetchContext({
    required this.client,
    required this.queryKey,
    required this.options,
    required this.state,
    required this.fetchOptions,
    required this.fetchFn,
    required QueryCancelToken signal,
    void Function()? onSignalRead,
  })  : _signal = signal,
        _onSignalRead = onSignalRead;

  /// The client the query belongs to, so a behaviour can reach its managers
  /// and caches.
  final QueryClient client;

  /// The key of the query being fetched.
  final QueryKey queryKey;

  /// The fully resolved options this fetch runs with.
  final DefaultedQueryOptions<TQueryData> options;

  /// The query's state as the fetch begins — what an infinite query reads its
  /// existing pages from.
  final QueryState<TQueryData> state;

  /// The per-fetch overrides passed to [Query.fetch], if any. An infinite query
  /// finds its page direction in [FetchOptions.meta].
  final FetchOptions? fetchOptions;

  /// Replaced by a behaviour to change what the fetch actually does.
  Future<TQueryData> Function() fetchFn;

  final QueryCancelToken _signal;
  final void Function()? _onSignalRead;
  bool _signalConsumed = false;

  /// The cancellation token for this fetch. Reading it counts as consuming the
  /// signal: the query then knows the transport can be stopped, and cancels
  /// the request rather than only the retry loop when its last observer
  /// leaves.
  ///
  /// Consumed once per context, as [QueryFunctionContext.signal] is.
  QueryCancelToken get signal {
    if (!_signalConsumed) {
      _signalConsumed = true;
      _onSignalRead?.call();
    }
    return _signal;
  }
}

/// Overrides for one call of [Query.fetch], leaving the query's options
/// untouched.
///
/// Application code rarely builds one. The client and the observers do:
/// `refetch`, `refetchQueries` and `invalidateQueries` from their
/// `cancelRefetch` parameter, `QueryClient.query` for its no-retry rule,
/// and an infinite query for its page direction. Reach for it when calling
/// [Query.fetch] directly on an entry found in the cache.
///
/// ```dart
/// final query = client.queryCache.find(
///   filters: QueryFilters(queryKey: QueryKey(['todos'])),
/// );
/// await query?.fetch(fetchOptions: const FetchOptions(cancelRefetch: true));
/// ```
///
/// {@category Advanced}
@immutable
final class FetchOptions {
  /// Creates the overrides; all are unset by default, which leaves the
  /// fetch as the query's options describe it.
  const FetchOptions({this.cancelRefetch, this.meta, this.retry});

  /// Cancel a fetch that is already running and start a new one — when the
  /// query already holds data. Without data the call joins the running fetch
  /// instead, so a first load is never restarted. Unset means `false`: join
  /// the running fetch.
  final bool? cancelRefetch;

  /// Carried into [QueryState.fetchMeta] for the length of the fetch;
  /// infinite queries put the page direction here. Unset by default.
  final Object? meta;

  /// A retry policy for *this fetch only*, in place of the options' `retry`.
  /// It is not written into the query's options, so later fetches and the
  /// observers' `retry` are untouched by it. Unset uses the options' policy.
  ///
  /// `QueryClient.query` uses it for its rule of no retries unless the
  /// caller asked: an imperative fetch fails fast, while a later
  /// `invalidateQueries` still refetches an observer's `RetryPolicy.times(3)`
  /// query with its three retries. (TanStack Query writes that rule into the
  /// shared query's options instead, where it outlives the call.)
  final RetryPolicy? retry;
}

/// One change to a query's state — what a `QueryUpdated` cache event says
/// happened.
///
/// A cache listener, a devtools panel or a persister can `switch` on the
/// `action` of a `QueryUpdated` event to tell a fetch starting from a retry,
/// a success or an invalidation. The class is sealed, so that `switch` is
/// exhaustive:
///
/// * [QueryFetchAction] — a fetch started.
/// * [QueryFailedAction] — one attempt failed and will be retried.
/// * [QuerySuccessAction] — data arrived, fetched or written by hand.
/// * [QueryErrorAction] — a fetch failed for good.
/// * [QueryPauseAction] / [QueryContinueAction] — a fetch paused, resumed.
/// * [QueryInvalidateAction] — the data was marked stale.
/// * [QuerySetStateAction] — the whole state was replaced.
///
/// Read-only from outside: only a [Query] dispatches one, and there is no
/// public way to hand one in.
///
/// {@category Advanced}
@immutable
sealed class QueryAction {
  /// Creates the action.
  const QueryAction();
}

/// A fetch started. Resets the failure count, records [meta], and moves
/// `fetchStatus` to fetching — or paused, when the network mode forbids
/// starting. TanStack Query calls this action `fetch`.
///
/// {@category Advanced}
final class QueryFetchAction extends QueryAction {
  /// Creates the action, with the fetch's [meta] if it has any.
  const QueryFetchAction({this.meta});

  /// What [FetchOptions.meta] carried in; becomes `QueryState.fetchMeta`.
  final Object? meta;
}

/// One attempt failed and will be retried. Records the count and the reason
/// without touching `status` or the data. TanStack Query calls this action
/// `failed`.
///
/// {@category Advanced}
final class QueryFailedAction extends QueryAction {
  /// Creates the action for the attempt that just failed.
  const QueryFailedAction(this.failureCount, this.error, this.stackTrace);

  /// How many attempts have failed so far in this fetch, including this one.
  final int failureCount;

  /// What the attempt threw.
  final Object error;

  /// Where it was thrown from.
  final StackTrace stackTrace;
}

/// Data arrived: from a fetch, or from a manual write through
/// `QueryClient.setQueryData`. Bumps `dataUpdateCount`, clears the error and
/// the invalidation, and — unless [manual] — ends the fetch. TanStack Query
/// calls this action `success`.
///
/// {@category Advanced}
final class QuerySuccessAction<TQueryData> extends QueryAction {
  /// Creates the action carrying [data].
  const QuerySuccessAction(this.data,
      {this.dataUpdatedAt, this.manual = false});

  /// The new data, already passed through structural sharing.
  final TQueryData data;

  /// When the data is to be dated, or `null` for "now".
  final DateTime? dataUpdatedAt;

  /// Whether the data was written by hand rather than fetched. A manual write
  /// leaves an in-flight fetch's status alone and becomes the state a later
  /// cancel-with-revert returns to.
  final bool manual;
}

/// A fetch failed for good: retries exhausted, or cancelled with neither
/// `silent` nor `revert` — a reverting cancel restores the earlier state
/// through [QuerySetStateAction] instead. Moves `status` to error, ends the
/// fetch and flags existing data as invalidated. TanStack Query calls this
/// action `error`.
///
/// {@category Advanced}
final class QueryErrorAction extends QueryAction {
  /// Creates the action for the error that settled the fetch.
  const QueryErrorAction(this.error, this.stackTrace);

  /// What the fetch finally failed with.
  final Object error;

  /// Where it was thrown from.
  final StackTrace stackTrace;
}

/// The fetch was suspended: the device is offline, or a retry is waiting
/// for the app to return to the foreground. `fetchStatus` becomes paused.
/// TanStack Query calls this action `pause`.
///
/// {@category Advanced}
final class QueryPauseAction extends QueryAction {
  /// Creates the action.
  const QueryPauseAction();
}

/// A paused fetch resumed; `fetchStatus` is fetching again. TanStack Query
/// calls this action `continue`.
///
/// {@category Advanced}
final class QueryContinueAction extends QueryAction {
  /// Creates the action.
  const QueryContinueAction();
}

/// The query was marked stale by `QueryClient.invalidateQueries`. Only
/// `isInvalidated` changes; whether a refetch follows is the caller's
/// decision. TanStack Query calls this action `invalidate`.
///
/// {@category Advanced}
final class QueryInvalidateAction extends QueryAction {
  /// Creates the action.
  const QueryInvalidateAction();
}

/// The whole state was replaced through [Query.setState] — a reset, a
/// revert after cancellation, or a persistence layer restoring. TanStack
/// Query calls this action `setState`.
///
/// {@category Advanced}
final class QuerySetStateAction<TQueryData> extends QueryAction {
  /// Creates the action carrying the replacement [state].
  const QuerySetStateAction(this.state);

  /// The state the query now holds, verbatim.
  final QueryState<TQueryData> state;
}

/// One cache entry: a key, its options, its state, and the fetch machinery.
///
/// Application code does not construct a `Query`; the `QueryCache` does,
/// the first time an observer or a fetch uses a key. You meet one when you
/// look at the cache from outside:
///
/// * `QueryCache.find` and `QueryCache.findAll`, or `QueryCache.queries`;
/// * the `query` of every `QueryCacheEvent` a cache listener receives, and
///   the `query` passed to the cache's `onSuccess`/`onError` hooks;
/// * the argument of a `QueryFilters.predicate`, and of callbacks such as
///   `StaleTime.dynamic` and `RefetchInterval.dynamic`.
///
/// What it offers:
///
/// * **Reading:** [queryKey], [state] (data, error, statuses, counters),
///   [options], [meta], [observersCount], [isStale], [isActive].
/// * **Acting:** [fetch], [invalidate], [cancel], [reset], [setState]. The
///   client's filtered methods (`invalidateQueries`, `cancelQueries`,
///   `resetQueries`, ...) call these for every matching query and are the
///   usual way in.
///
/// A query is removed from the cache after `gcTime` with no observers, or
/// through `QueryClient.removeQueries`; a removed instance never comes back,
/// and the next use of the key creates a fresh one.
///
/// It has one type parameter, the data type the cache stores — errors are
/// an `Object` with a `StackTrace`, and `select` belongs to the observer,
/// not the query.
///
/// {@category Queries}
class Query<TQueryData> extends Removable {
  /// Creates a cache entry for [queryKey] with [options], seeded from
  /// `initialData` or from a restored [state], and arms its collection timer
  /// straight away — a query nobody observes yet is collectable. Constructed by
  /// `QueryCache.build`; user code reaches a query through the cache.
  Query({
    required this.client,
    required QueryCacheRef cache,
    required this.queryKey,
    required DefaultedQueryOptions<TQueryData> options,
    QueryState<TQueryData>? state,
  })  : _cache = cache,
        _options = options {
    state?.validate();
    _initialState = _defaultState(options);
    _state = state ?? _initialState;
    updateGcTime(options.gcTime);
    scheduleGc();
  }

  /// The client this query belongs to: the source of its managers and its
  /// notify batching.
  final QueryClient client;
  final QueryCacheRef _cache;

  /// The key this query is stored under in the cache.
  final QueryKey queryKey;

  /// The data type this query holds, exactly.
  ///
  /// The cache compares this rather than asking `is Query<T>`: Dart generics
  /// are covariant, so a `Query<int>` *is a* `Query<int?>` and a `Query<num>`,
  /// and treating it as one would let options typed for the wider type reach
  /// it and fail later with a raw `TypeError`. One key, one exact type; a
  /// mismatch throws `QueryDataTypeError` at the call that asked.
  Type get dataType => TQueryData;

  DefaultedQueryOptions<TQueryData> _options;

  /// The options in force, fully resolved. They are the last options any
  /// observer or fetch handed in; `queryFn`, `retry`, `networkMode` and the
  /// like are read from here at fetch time.
  /// An imperative client fetch that omits retry preserves the entry's retry
  /// policy and uses its no-retry override only for that fetch.
  DefaultedQueryOptions<TQueryData> get options => _options;

  late QueryState<TQueryData> _state;

  /// The current state: data, error, status, fetch status and the counters.
  /// Replaced on every dispatch; observers compute their results from it.
  QueryState<TQueryData> get state => _state;

  late QueryState<TQueryData> _initialState;

  /// The state this query returns to on [reset]: pending with no data, or
  /// the `initialData` seed its options provided.
  QueryState<TQueryData> get resetState => _initialState;

  final List<QueryObserverRef> _observers = <QueryObserverRef>[];

  /// The observers attached right now, read-only; [addObserver] and
  /// [removeObserver] are the only way in and out.
  List<QueryObserverRef> get observers =>
      UnmodifiableListView<QueryObserverRef>(_observers);

  Retryer<TQueryData>? _retryer;

  /// The in-flight fetch as its callers see it: settled only once the data is
  /// in the cache and the cache hooks have run, or the error is in the state.
  /// Kept apart from the retryer's own future, which is the transport alone,
  /// so that every caller — the one that started the fetch and the ones that
  /// joined it — sees the same outcome, even when a `structuralSharing` hook
  /// throws after the transport succeeded.
  Completer<TQueryData>? _operation;
  QueryState<TQueryData>? _revertState;
  bool _signalConsumed = false;
  QueryCancelToken? _activeSignal;
  int _fetchGeneration = 0;

  /// The options' `meta`: free-form data attached to the query, for cache
  /// listeners, cache hooks and devtools to read.
  Object? get meta => _options.meta;

  /// The in-flight fetch, if there is one: the future every caller of [fetch]
  /// shares, settled once the cache has been written.
  Future<TQueryData>? get future => _operation?.future;

  /// How many observers are attached right now — zero for a query nothing
  /// on screen uses, which is what makes it collectable after `gcTime`.
  int get observersCount => _observers.length;

  /// Replaces the options and folds their `gcTime` in. Called by observers as
  /// they attach and by [fetch]; not for user code, which sets options through
  /// an observer or the client.
  @internal
  void setOptions(DefaultedQueryOptions<TQueryData> options) {
    // Late-arriving initialData still seeds a query that has never resolved.
    // The seed is user code (`InitialData.compute`), computed before anything
    // is written so that a throw leaves the query on the options it had.
    final defaultState = _state.hasData ? null : _defaultState(options);

    _options = options;
    updateGcTime(options.gcTime);

    // Only the success fields are written: a fetch already in flight keeps its
    // `fetchStatus`, and `dataUpdateCount` stays where it was, because seeding
    // is not fetching. An error held without data is cleared by the seed, and
    // an `InitialData.compute` is consulted on every call here until the
    // query holds data — both as upstream's `setOptions` does.
    if (defaultState != null) {
      if (_removed) return;
      if (!_state.hasData && defaultState.hasData) {
        setState(
          _state.copyWith(
            hasData: true,
            data: defaultState.data,
            dataUpdatedAt: defaultState.dataUpdatedAt ?? clock.now(),
            clearError: true,
            isInvalidated: false,
            status: QueryStatus.success,
          ),
        );
        _initialState = defaultState;
      }
    }
  }

  @override
  @protected
  void optionalRemove() {
    if (_observers.isEmpty && _state.fetchStatus == FetchStatus.idle) {
      _cache.onQueryRemovalRequested(this);
    }
  }

  /// Writes [newData] into the cache as if it had been fetched.
  @internal
  TQueryData setData(
    TQueryData newData, {
    DateTime? updatedAt,
    bool manual = false,
    bool Function()? canCommit,
  }) {
    final sharing = _options.structuralSharing;
    final previous = _state.hasData ? _state.data : null;
    final data = sharing == null
        ? replaceEqualDeep<TQueryData>(previous, newData)
        : sharing(previous, newData);

    // Sharing is user code and may reset/remove this entry or start another
    // fetch. A transport result commits only while its run still owns it.
    if (canCommit != null && !canCommit()) return data;

    _dispatch(
      QuerySuccessAction<TQueryData>(
        data,
        dataUpdatedAt: updatedAt,
        manual: manual,
      ),
    );

    return data;
  }

  /// Whether [value] is a [TQueryData], for a caller that holds a value but
  /// not this query's exact type — and, checking several entries before
  /// writing any, cannot write as it tests.
  ///
  /// `QueryClient.setQueryData` infers its type argument from the value, and a
  /// value infers narrowly — a `String` for a `String?` query, a sealed
  /// type's variant for the sealed type. The entry keeps its one exact type
  /// and takes any value that type can hold.
  @internal
  bool canHold(Object? value) => value is TQueryData;

  /// Replaces this query's state wholesale and notifies its observers and
  /// the cache's listeners, with a [QuerySetStateAction].
  ///
  /// This is how a persistence layer or a devtools panel writes into a query
  /// that already exists. Restoring an entry that does not exist yet goes
  /// through [QueryCache.build]'s `state:` instead. To change only the data,
  /// use `QueryClient.setQueryData`.
  ///
  /// A `success` state must carry data (`hasData: true`), or it is refused
  /// with an [ArgumentError] in every build mode: an observer built on a
  /// `success` with no data would cast `null` to the data type and throw
  /// somewhere that says nothing about where the state came from.
  ///
  /// Unlike [QueryCache.build], this installs [QueryState.fetchStatus] as
  /// given, because a fetch may really be running on a live query. A
  /// snapshot restored through here should therefore carry
  /// `FetchStatus.idle` itself. A `fetching` or `paused` status written with
  /// no fetch behind it stays: [QueryClient.isFetching] counts the entry, and
  /// garbage collection skips it, until a real fetch settles. TanStack Query
  /// behaves the same way.
  void setState(QueryState<TQueryData> state) {
    state.validate();
    _dispatch(QuerySetStateAction<TQueryData>(state));
  }

  /// Cancels the in-flight fetch, completing once it has settled. Does
  /// nothing when no fetch is running.
  ///
  /// The query function sees the cancellation through its
  /// `QueryFunctionContext.signal`; one that never reads the signal keeps
  /// running, but its result is dropped.
  ///
  /// With both flags `false`, the defaults, the fetch fails with a
  /// `CancelledError`: it becomes the query's error and runs the cache's
  /// `onError` hook. [revert] instead puts the state back to what it was
  /// before the fetch, and records no error. [silent] records no error and
  /// leaves the state alone — it is how a fetch that cancels a running one
  /// takes over its callers. When no new fetch follows a silent cancel, the
  /// fetch status goes back to `idle`, so nothing reports a fetch that is
  /// not happening. (TanStack Query leaves it `fetching` until the next
  /// fetch.)
  ///
  /// `QueryClient.cancelQueries` calls this, with `revert: true` by default,
  /// for every matching query.
  Future<void> cancel({bool revert = false, bool silent = false}) async {
    _fetchGeneration++;
    final cancelled = _retryer;
    final pending = cancelled?.future;
    cancelled?.cancel(revert: revert, silent: silent);
    if (pending == null) {
      return;
    }
    try {
      await pending;
    } catch (_) {
      // The error belongs to the query's state, not to whoever cancelled.
    }
    // Nothing replaced this fetch: `_retryer` is either cleared by its own
    // settle or still the one just cancelled. A successor is installed
    // synchronously by `fetch()`, before this await resumes, so a different
    // retryer here means the handoff happened and it owns the status.
    final successor = _retryer;
    final replaced = successor != null && !identical(successor, cancelled);
    if (silent &&
        !replaced &&
        !_removed &&
        _state.fetchStatus != FetchStatus.idle) {
      setState(_state.copyWith(fetchStatus: FetchStatus.idle));
    }
  }

  /// Cancels silently and stops the gc timer.
  ///
  /// The cache's to call, on removal and reset; user code removes a query
  /// through `QueryClient.removeQueries` or `QueryCache.remove`.
  @internal
  @override
  void destroy() {
    super.destroy();
    cancel(silent: true).ignore();
  }

  /// Called by the cache when this query is dropped for good.
  ///
  /// Beyond [destroy], it stops the query re-arming its own collection: the
  /// cancelled fetch's `finally` schedules one on its way out, and a query that
  /// is no longer in a cache has nothing left to be collected from — the timer
  /// would just outlive it.
  @internal
  void markRemoved() {
    _removed = true;
    destroy();
  }

  bool _removed = false;

  /// Whether the cache permanently removed this entry. Removed entries cannot
  /// be registered or fetched again; observers resolve a fresh cache entry.
  @internal
  bool get isRemoved => _removed;

  @override
  @protected
  void scheduleGc() {
    if (_removed) {
      return;
    }
    super.scheduleGc();
  }

  /// Back to the state this query was created with ([resetState]),
  /// cancelling any fetch in flight. Observers are notified of the reset
  /// state; nothing is refetched here. `QueryClient.resetQueries` calls this
  /// for every matching query and then refetches the active ones.
  void reset() {
    // Reset revokes write authority even when the transport already resolved
    // and cancel can no longer reject its retryer (for example inside sharing).
    _operation = null;
    _activeSignal = null;
    destroy();
    setState(_initialState);
    // `destroy` dropped the gc timer. Upstream never re-arms it, so a reset
    // query nobody observes stays in the cache for good; here it is collected
    // like any other idle entry.
    if (_observers.isEmpty) {
      scheduleGc();
    }
  }

  /// Whether any observer's `enabled` resolves to true — whether something
  /// is actively using this query. This is what `QueryTypeFilter.active`
  /// and `RefetchType.active` select.
  ///
  /// An `Enabled.when` predicate is user code and runs here; it may
  /// subscribe or unsubscribe observers without disturbing the check.
  bool isActive() => List<QueryObserverRef>.of(_observers)
      .any((observer) => observer.isEnabledForQuery);

  /// Whether the query will not fetch on its own.
  bool isDisabled() {
    if (observersCount > 0) {
      return !isActive();
    }
    // A query nobody observes is disabled until it has attempted a fetch,
    // and not a moment longer. `enabled` is deliberately *not* consulted
    // here, though upstream's arm reads
    // `options.queryFn === skipToken || !isFetched()`:
    //
    //  * Upstream's marker is `skipToken`, a static sentinel meaning "this
    //    query has no function". `enabled: false` never reaches this arm
    //    upstream — an unobserved, seeded, `enabled: false` query *is*
    //    refetched by `refetchType: 'all'`.
    //  * This package spells both with one value, `Enabled.no`, so consulting
    //    it here silences the far more common meaning: a dependent query
    //    (`enabled: userId != null`) that went disabled and then lost its
    //    widget would never be refetched from the cache side again, silently.
    //    `enabled` governs *automatic* fetching; `refetchQueries` is an
    //    explicit command.
    //  * And `enabled` is an observer option that merely survives on the
    //    query as the last writer's leftover. Resolving it with nobody
    //    attached runs an [Enabled.when] predicate — user code, over a scope
    //    its owner already tore down — on every bulk refetch, inside
    //    `notifyManager.batch`.
    return !isFetched();
  }

  /// Whether at least one fetch — or a manual write — has ever settled.
  bool isFetched() => _state.dataUpdateCount + _state.errorUpdateCount > 0;

  /// Whether any attached observer uses `StaleTime.static`, declaring this
  /// query permanently fresh: not even an invalidation makes it stale.
  ///
  /// A `StaleTime.dynamic` callback is user code and runs here, as
  /// `Enabled.when` does for [isActive].
  bool isStatic() =>
      observersCount > 0 &&
      List<QueryObserverRef>.of(_observers)
          .any((observer) => observer.isStaticForQuery);

  /// Whether the data should be refetched: any observer's result says so, or —
  /// with no observers — there is no data or it has been invalidated.
  ///
  /// This is the query's view, and it asks its observers rather than deciding:
  /// an observer answers with the `isStale` of the result it last built, which
  /// its own options computed from [isStaleByTime].
  bool isStale() {
    if (observersCount > 0) {
      return _observers.any((observer) => observer.currentResultIsStale);
    }
    return !_state.hasData || _state.isInvalidated;
  }

  /// Whether the data is older than [staleTime].
  ///
  /// Takes the [StaleTime] rather than a resolved [Duration] because the two
  /// "never stale by time" values are not the same thing: [StaleTime.static]
  /// outranks an invalidation, while [StaleTime.infinite] does not. Resolving
  /// first would collapse them, and an invalidated query would look fresh
  /// forever.
  bool isStaleByTime(StaleTime staleTime) {
    if (!_state.hasData) {
      return true;
    }
    // Resolved once: a dynamic stale time is user code.
    final resolved = staleTime.resolveFor(this);
    if (resolved is StaleTimeStatic) {
      return false;
    }
    if (_state.isInvalidated) {
      return true;
    }
    if (resolved is! StaleTimeDuration) {
      return false;
    }
    final updatedAt = _state.dataUpdatedAt;
    if (updatedAt == null) {
      return true;
    }
    return !clock.now().isBefore(updatedAt.add(resolved.duration));
  }

  /// Reacts to the app returning to the foreground: the first observer whose
  /// `refetchOnWindowFocus` asks for it refetches, and a paused fetch is given
  /// the chance to resume. Called by the cache's `onFocus`; not for user code.
  @internal
  void onFocus({bool refetchQueries = true}) {
    if (_removed) return;
    if (refetchQueries) {
      for (final observer in List<QueryObserverRef>.of(_observers)) {
        if (!_observers.contains(observer)) continue;
        var refetched = false;
        _runCacheHook(() {
          if (observer.shouldFetchOnWindowFocus()) {
            observer.refetchOnEvent();
            refetched = true;
          }
        });
        if (refetched) break;
      }
    }
    // Outside the guard on purpose: a short absence suppresses *new* fetches,
    // never the continuation of one that is already paused.
    _retryer?.continueFetch().ignore();
  }

  /// Reacts to the device coming back online: the first observer whose
  /// `refetchOnReconnect` asks for it refetches, and a paused fetch is given
  /// the chance to resume. Called by the cache's `onOnline`; not for user code.
  @internal
  void onOnline() {
    if (_removed) return;
    for (final observer in List<QueryObserverRef>.of(_observers)) {
      if (!_observers.contains(observer)) continue;
      var refetched = false;
      _runCacheHook(() {
        if (observer.shouldFetchOnReconnect()) {
          observer.refetchOnEvent();
          refetched = true;
        }
      });
      if (refetched) break;
    }
    _retryer?.continueFetch().ignore();
  }

  /// Attaches [observer], cancelling the pending collection and emitting
  /// `QueryObserverAdded`. Attaching twice is a no-op. Called by the observer's
  /// `subscribe`; not for user code.
  @internal
  void addObserver(QueryObserverRef observer) {
    if (!_observers.contains(observer)) {
      _observers.add(observer);
      clearGcTimeout();
      _cache.onQueryObserverAdded(this, observer);
    }
  }

  /// Detaches [observer] and emits `QueryObserverRemoved`. When it was the last
  /// one, an in-flight fetch is either cancelled and reverted (if the query
  /// function consumed the signal, or the fetch was still paused before any
  /// data) or left to finish with only its retries stopped, and the collection
  /// timer is armed. Called by the observer's unsubscribe; not for user code.
  @internal
  void removeObserver(QueryObserverRef observer) {
    if (!_observers.remove(observer)) {
      return;
    }

    if (_observers.isEmpty) {
      final retryer = _retryer;
      if (retryer != null) {
        // If the query function never read the cancellation token, the
        // transport cannot be stopped — so let the request finish and cache its
        // result, and only stop the retry loop.
        if (_signalConsumed ||
            (_state.fetchStatus == FetchStatus.paused &&
                _state.status == QueryStatus.pending)) {
          retryer.cancel(revert: true);
        } else {
          retryer.cancelRetry();
        }
      }
      scheduleGc();
    }

    _cache.onQueryObserverRemoved(this, observer);
  }

  /// Marks the data stale regardless of `staleTime`, dispatching
  /// [QueryInvalidateAction] unless it already is. Nothing is refetched
  /// here; `QueryClient.invalidateQueries` calls this and then refetches the
  /// queries its `refetchType` names.
  void invalidate() {
    if (!_state.isInvalidated) {
      _dispatch(const QueryInvalidateAction());
    }
  }

  /// Fetches this query now: runs its query function, with the retries and
  /// network rules of its options, and completes with the data.
  ///
  /// A fetch already in flight is joined rather than duplicated, unless
  /// [fetchOptions] asks for `cancelRefetch` on a query that holds data.
  /// [options], when given, replace the query's options first. Every caller
  /// gets the same future — it settles once the data has been written to the
  /// cache and the cache hooks have run, or once the error is in the state —
  /// whether it started the fetch or joined one already running. A query
  /// with no query function anywhere fails with [MissingQueryFunctionError];
  /// a removed query fails with a `CancelledError`.
  ///
  /// Application code usually fetches through `QueryClient.query`, an
  /// observer's `refetch`, or `QueryClient.refetchQueries`, which call this.
  ///
  /// The fetch is registered *before* it is announced to observers and cache
  /// listeners, so a listener that reacts to it (a `cancelQueries`, a
  /// `client.query` of the same key, a `clear()`) finds it to cancel or to
  /// join.
  Future<TQueryData> fetch({
    DefaultedQueryOptions<TQueryData>? options,
    FetchOptions? fetchOptions,
  }) {
    if (_removed) {
      return Future<TQueryData>.error(const CancelledError(silent: true));
    }
    if (_state.fetchStatus != FetchStatus.idle &&
        _retryer?.status != RetryerStatus.rejected) {
      if (_state.hasData && (fetchOptions?.cancelRefetch ?? false)) {
        // Deliberately not awaited, as upstream does not: the replacement
        // retryer has to be installed before the cancelled fetch's `catch`
        // runs, or that fetch has nothing to piggyback on and rejects.
        cancel(silent: true).ignore();
      } else {
        final retryer = _retryer;
        final operation = _operation;
        if (retryer != null && operation != null) {
          // Retries stopped by an unmount can continue.
          retryer.continueRetry();
          return operation.future;
        }
      }
    }

    final generation = ++_fetchGeneration;
    Future<TQueryData>? superseded() {
      if (_removed || generation != _fetchGeneration) {
        return _removed
            ? Future<TQueryData>.error(const CancelledError(silent: true))
            : _operation?.future ??
                Future<TQueryData>.error(const CancelledError(silent: true));
      }
      return null;
    }

    if (options != null) {
      setOptions(options);
    }
    final afterOptions = superseded();
    if (afterOptions != null) return afterOptions;

    // A query created by setQueryData or restored from persistence has no
    // query function of its own; borrow one from an observer. A behaviour
    // counts as one: an infinite query's options carry no `queryFn` — its
    // pages come from the behaviour — where upstream's carry the page
    // function as `queryFn`. Checking `queryFn` alone, a plain fetch of an
    // infinite key (`client.query` without a function, a select-only reader)
    // stripped the paging and failed with `MissingQueryFunctionError`, and so
    // did every option-less refetch after it.
    if (_options.queryFn == null && _options.behavior == null) {
      for (final observer in _observers) {
        final observerOptions = observer.observerQueryOptions;
        if (observerOptions.queryFn != null ||
            observerOptions.behavior != null) {
          setOptions(observerOptions as DefaultedQueryOptions<TQueryData>);
          break;
        }
      }
    }

    final afterBorrow = superseded();
    if (afterBorrow != null) return afterBorrow;

    final cancelToken = QueryCancelToken();
    _activeSignal = cancelToken;
    _signalConsumed = false;
    void signalRead() {
      if (identical(_activeSignal, cancelToken)) _signalConsumed = true;
    }

    Future<TQueryData> runQueryFn() async {
      final queryFn = _options.queryFn;
      if (queryFn == null) {
        throw MissingQueryFunctionError(queryKey);
      }
      final context = QueryFunctionContext(
        client: client,
        queryKey: queryKey,
        signal: cancelToken,
        meta: _options.meta,
        onSignalRead: signalRead,
      );
      // Reset per attempt, exactly where upstream resets it: a retry that
      // never touches the token is as uncancellable as a first try that
      // did not.
      if (identical(_activeSignal, cancelToken)) _signalConsumed = false;
      return queryFn(context);
    }

    final context = FetchContext<TQueryData>(
      client: client,
      queryKey: queryKey,
      options: _options,
      state: _state,
      fetchOptions: fetchOptions,
      fetchFn: runQueryFn,
      signal: cancelToken,
      onSignalRead: signalRead,
    );

    _options.behavior?.onFetch(context, this);
    final afterBehavior = superseded();
    if (afterBehavior != null) return afterBehavior;

    // Whether the attempt can only end in `MissingQueryFunctionError`: no
    // query function, and no behaviour that replaced the fetch with its own
    // (an infinite query has no `queryFn` either; its pages come from
    // `pageFn`). Decided here, where a query is known from a mutation, rather
    // than in the retryer.
    final missingQueryFn =
        _options.queryFn == null && identical(context.fetchFn, runQueryFn);

    // Kept in case this fetch has to be reverted.
    _revertState = _state;

    // The CancelledError this fetch's own `cancel` produced, recognised by
    // instance in `_settle`.
    CancelledError? ownCancel;

    // Constructing a retryer runs nothing; `start()` does, below.
    final retryer = Retryer<TQueryData>(
      fn: context.fetchFn,
      focusManager: client.focusManager,
      onlineManager: client.onlineManager,
      canRun: () => true,
      // A missing query function is a configuration error, and retrying it
      // only delays the message by the whole backoff. Upstream retries it
      // like any other failure; here the one attempt is the answer. A
      // per-fetch `retry` outranks the options'.
      retry: missingQueryFn
          ? RetryPolicy.never
          : fetchOptions?.retry ?? _options.retry,
      retryDelay: _options.retryDelay,
      networkMode: _options.networkMode,
      onFail: (failureCount, error, stackTrace) =>
          _dispatch(QueryFailedAction(failureCount, error, stackTrace)),
      onPause: () => _dispatch(const QueryPauseAction()),
      onContinue: () => _dispatch(const QueryContinueAction()),
      onCancel: (error) {
        ownCancel = error;
        if (error.revert) {
          final revertState = _revertState;
          if (revertState != null) {
            setState(revertState.copyWith(fetchStatus: FetchStatus.idle));
          }
        }
        cancelToken.cancel();
      },
    );
    final operation = Completer<TQueryData>();
    _retryer = retryer;
    _operation = operation;

    // Unconditional. Upstream skips the action when `fetchStatus !== 'idle'
    // && fetchMeta === meta`, and that never holds: a `null` fetchMeta is not
    // an unset `undefined`, and a page fetch builds a fresh meta object per
    // call. Comparing value-equal `FetchMore`s (or two `null`s) here skipped
    // it, so a refetch that cancelled a retrying fetch kept the old
    // `fetchFailureCount`.
    _dispatch(QueryFetchAction(meta: fetchOptions?.meta));

    _settle(retryer, operation, () => ownCancel).ignore();
    return operation.future;
  }

  /// Runs [retryer] to its end and completes [operation] with what the cache
  /// ended up holding: the data once written and the hooks run, or the
  /// error once dispatched.
  ///
  /// [ownCancel] is the [CancelledError] this fetch's own `cancel` produced,
  /// if any. Only that one takes the silent and reverting branches: they rely
  /// on `onCancel` having reverted the state, or on a successor or
  /// [cancel]'s idle fix owning the status. A `CancelledError` the query
  /// function threw itself — a query it awaited was cancelled, reset or
  /// removed — took them too, and nothing ever set the query `idle`: it sat
  /// `fetching` with nothing running, counted by `isFetching` and never
  /// collected. It is an ordinary failure now. Upstream tests
  /// `instanceof CancelledError` and hangs the same way.
  Future<void> _settle(
    Retryer<TQueryData> retryer,
    Completer<TQueryData> operation,
    CancelledError? Function() ownCancel,
  ) async {
    try {
      final data = await retryer.start();
      if (!identical(_operation, operation) || _removed) {
        operation.complete(data);
        return;
      }
      var committed = false;
      setData(data, canCommit: () {
        committed = identical(_operation, operation) && !_removed;
        return committed;
      });
      operation.complete(data);
      if (committed) {
        _runCacheHook(() => _cache.onQueryFetchSuccess(this, data));
      }
    } catch (error, stackTrace) {
      if (error is CancelledError && identical(error, ownCancel())) {
        if (error.silent) {
          // A silent cancel means a new fetch is starting: ride along with it.
          // When no new fetch replaced this one, `_operation` is still this
          // fetch's, so the caller sees the CancelledError — and no error is
          // dispatched into the query's state, which is what a silent cancel
          // means.
          final replacement = _operation;
          if (replacement != null && !identical(replacement, operation)) {
            operation.complete(replacement.future);
          } else {
            operation.completeError(error, stackTrace);
          }
          return;
        } else if (error.revert) {
          if (identical(_operation, operation) && _state.hasData) {
            operation.complete(_state.data as TQueryData);
          } else {
            operation.completeError(error, stackTrace);
          }
          return;
        }
      }
      final ownsState = identical(_operation, operation) && !_removed;
      if (ownsState) _dispatch(QueryErrorAction(error, stackTrace));
      operation.completeError(error, stackTrace);
      if (ownsState) {
        _runCacheHook(() => _cache.onQueryFetchError(this, error, stackTrace));
      }
    } finally {
      if (identical(_retryer, retryer)) {
        _retryer = null;
      }
      if (identical(_operation, operation)) {
        _operation = null;
        _activeSignal = null;
      }
      // Only when nobody is watching, the same rule as the mutation side: an
      // observer leaving arms the timer in `removeObserver`, and a timer
      // standing while a widget is mounted is what Flutter's widget tests
      // assert against.
      if (_observers.isEmpty) {
        scheduleGc();
      }
    }
  }

  /// Runs one of the cache's fetch hooks (`onSuccess`, `onError`,
  /// `onSettled`) after the operation has been completed, reporting a throw
  /// to the zone the way the cache's listeners and the observers' updates
  /// are. Run *before* completing and unprotected, a throwing hook left the
  /// operation open for good: `_settle` is nobody's future, so the exception
  /// vanished and every caller of the fetch — the `client.query` that started
  /// it, the ones deduplicated onto it, an `invalidateQueries` or
  /// `refetchQueries` awaiting it — waited forever. Upstream's `fetch` is the
  /// operation itself, so a throwing hook rejects it there; here the query's
  /// state is already what the hook was told about, and a telemetry hook's
  /// failure is not the fetch's.
  void _runCacheHook(void Function() hook) {
    try {
      hook();
    } catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }

  void _dispatch(QueryAction action) {
    _state = _reduce(_state, action);

    client.notifyManager.batch(() {
      // A stable copy: an observer may unsubscribe while being notified.
      for (final observer in List<QueryObserverRef>.of(_observers)) {
        // Isolated like the cache listeners: an observer recomputes its
        // result here, and that runs user code (`StaleTime.dynamic`,
        // `Enabled.when`, `PlaceholderData.compute`). One observer's throw
        // must neither become the shared fetch's error nor skip the observers
        // after it.
        try {
          observer.onQueryUpdate();
        } catch (error, stackTrace) {
          Zone.current.handleUncaughtError(error, stackTrace);
        }
      }
      _cache.onQueryStateUpdated(this, action);
    });
  }

  QueryState<TQueryData> _reduce(
    QueryState<TQueryData> state,
    QueryAction action,
  ) {
    switch (action) {
      case QueryFailedAction(
          :final failureCount,
          :final error,
          :final stackTrace
        ):
        return state.copyWith(
          fetchFailureCount: failureCount,
          fetchFailureReason: error,
          fetchFailureStackTrace: stackTrace,
        );

      case QueryPauseAction():
        return state.copyWith(fetchStatus: FetchStatus.paused);

      case QueryContinueAction():
        return state.copyWith(fetchStatus: FetchStatus.fetching);

      case QueryFetchAction(:final meta):
        final fetching = canFetch(_options.networkMode, client.onlineManager)
            ? FetchStatus.fetching
            : FetchStatus.paused;
        return state.copyWith(
          fetchFailureCount: 0,
          fetchStatus: fetching,
          fetchMeta: meta,
          clearFetchFailure: true,
          clearFetchMeta: meta == null,
          status: state.hasData ? null : QueryStatus.pending,
          clearError: !state.hasData,
        );

      case QuerySuccessAction<TQueryData>(
          :final data,
          :final dataUpdatedAt,
          :final manual,
        ):
        final newState = state.copyWith(
          hasData: true,
          data: data,
          dataUpdatedAt: dataUpdatedAt ?? clock.now(),
          dataUpdateCount: state.dataUpdateCount + 1,
          // A manual write is somebody's guess — an optimistic patch, mostly —
          // and says nothing about whether the source answers.
          consecutiveErrorCount: manual ? null : 0,
          isInvalidated: false,
          status: QueryStatus.success,
          clearError: true,
          fetchStatus: manual ? null : FetchStatus.idle,
          fetchFailureCount: manual ? null : 0,
          clearFetchFailure: !manual,
        );
        // After a real fetch there is nothing to revert to; a manual write
        // becomes the state a later cancellation reverts to.
        _revertState = manual ? newState : null;
        return newState;

      case QueryErrorAction(:final error, :final stackTrace):
        return state.copyWith(
          error: error,
          errorStackTrace: stackTrace,
          errorUpdateCount: state.errorUpdateCount + 1,
          // A cancelled fetch did not fail; nobody waited for its answer.
          consecutiveErrorCount:
              error is CancelledError ? null : state.consecutiveErrorCount + 1,
          errorUpdatedAt: clock.now(),
          fetchFailureCount: state.fetchFailureCount + 1,
          fetchFailureReason: error,
          fetchFailureStackTrace: stackTrace,
          fetchStatus: FetchStatus.idle,
          status: QueryStatus.error,
          // Existing data is flagged as invalidated after a background error.
          isInvalidated: true,
        );

      case QueryInvalidateAction():
        return state.copyWith(isInvalidated: true);

      case QuerySetStateAction<TQueryData>(:final state):
        return state;

      case QuerySuccessAction<Object?>() || QuerySetStateAction<Object?>():
        // A differently-typed action can never reach this query.
        return state;
    }
  }

  QueryState<TQueryData> _defaultState(
    DefaultedQueryOptions<TQueryData> options,
  ) {
    final seed = options.initialData?.seed();
    final hasData = seed?.hasData ?? false;

    return QueryState<TQueryData>(
      hasData: hasData,
      data: seed?.data,
      dataUpdatedAt: hasData
          ? (options.initialDataUpdatedAt ??
              options.initialDataUpdatedAtCompute?.call() ??
              clock.now())
          : null,
      status: hasData ? QueryStatus.success : QueryStatus.pending,
    );
  }

  @override
  String toString() => 'Query($queryKey, ${_state.status})';
}

/// Thrown when a query is fetched with no query function anywhere in its
/// options chain.
///
/// Never retried, whatever the `retry` policy says: the fetch settles in
/// error after its one attempt, so the message is seen at once rather than
/// after the full backoff.
///
/// Typical causes: a `QueryClient.query` whose options have no `queryFn`
/// and whose key has no default one, or a refetch of a key that only ever
/// had data written with `setQueryData` while no observer supplies a
/// function. Give the options a `queryFn`, or register one for the key with
/// `QueryClient.setQueryDefaults`.
///
/// {@category Errors}
final class MissingQueryFunctionError implements Exception {
  /// Creates the error for [queryKey].
  const MissingQueryFunctionError(this.queryKey);

  /// The key of the query that had no function to run.
  final QueryKey queryKey;

  @override
  String toString() =>
      'No queryFn was provided for $queryKey. Pass one in the query options, '
      'or set a default with QueryClient.setQueryDefaults.';
}
