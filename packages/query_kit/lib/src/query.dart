/// Port of `query-core/src/query.ts` at upstream `50680b98c`.
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
/// is an analyzer warning (ninth review, 2026-09-10, C21).
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

  /// Told when a fetch of [query] rejected for good — retries exhausted or a
  /// non-silent cancel; the cache runs its `onError` and `onSettled` hooks.
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
/// Upstream's `QueryBehavior`. Infinite queries use it to turn one fetch into
/// a loop over pages; nothing else does, and users never set one
/// (https://github.com/KoTTi97/flutter_query/issues/16).
abstract interface class FetchBehavior<TQueryData> {
  /// Called once per fetch, before the retryer is built, to rewrite
  /// [FetchContext.fetchFn] — and read anything else the context carries — for
  /// [query].
  void onFetch(FetchContext<TQueryData> context, Query<TQueryData> query);
}

/// The mutable description of one fetch, handed to a [FetchBehavior].
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
  final FetchOptions<TQueryData>? fetchOptions;

  /// Replaced by a behaviour to change what the fetch actually does.
  Future<TQueryData> Function() fetchFn;

  final QueryCancelToken _signal;
  final void Function()? _onSignalRead;

  /// The cancellation token for this fetch. Reading it counts as consuming the
  /// signal, exactly as reading `signal` on upstream's context does: the query
  /// then knows the transport can be stopped, and cancels the request rather
  /// than only the retry loop when its last observer leaves.
  QueryCancelToken get signal {
    _onSignalRead?.call();
    return _signal;
  }
}

/// Per-fetch overrides.
///
/// Upstream's `initialPromise` is not here: it is the plumbing of
/// `experimental_prefetchInRender` and hydration, neither of which is ported.
@immutable
class FetchOptions<TQueryData> {
  /// Creates the overrides; all are unset by default.
  const FetchOptions({this.cancelRefetch, this.meta, this.retry});

  /// Cancel a fetch that is already running and start a new one.
  final bool? cancelRefetch;

  /// Carried into [QueryState.fetchMeta]; infinite queries put the page
  /// direction here.
  final Object? meta;

  /// A retry policy for *this fetch only*. It goes to the retryer and not
  /// into the query's options, so the observers' `retry` is untouched by it.
  /// `QueryClient.query` uses it for upstream's imperative rule — no retries
  /// unless the caller asked — which upstream writes into the shared query's
  /// options for good, so that the next `invalidateQueries` refetched an
  /// observer's `retry: times(3)` query with a single attempt (fifth review,
  /// 2026-09-09).
  final RetryPolicy? retry;
}

/// A state transition. Sealed, so the reducer is exhaustive.
///
/// Exported so that a cache listener can `switch` on the `action` a
/// `QueryUpdated` event carries — read-only from outside: only a [Query]
/// dispatches one, and there is no public way to hand one in.
@immutable
sealed class QueryAction {
  const QueryAction();
}

/// A fetch started. Resets the failure count, records [meta], and moves
/// `fetchStatus` to fetching — or paused, when the network mode forbids
/// starting. Upstream's `fetch` action.
final class QueryFetchAction extends QueryAction {
  /// Creates the action, with the fetch's [meta] if it has any.
  const QueryFetchAction({this.meta});

  /// What [FetchOptions.meta] carried in; becomes `QueryState.fetchMeta`.
  final Object? meta;
}

/// One attempt failed and will be retried. Records the count and the reason
/// without touching `status` or the data. Upstream's `failed` action.
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
/// the invalidation, and — unless [manual] — ends the fetch. Upstream's
/// `success` action.
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

/// A fetch failed for good: retries exhausted, or cancelled without `silent`.
/// Moves `status` to error, ends the fetch and flags existing data as
/// invalidated. Upstream's `error` action.
final class QueryErrorAction extends QueryAction {
  /// Creates the action for the error that settled the fetch.
  const QueryErrorAction(this.error, this.stackTrace);

  /// What the fetch finally failed with.
  final Object error;

  /// Where it was thrown from.
  final StackTrace stackTrace;
}

/// The retryer suspended the fetch: offline or backgrounded. `fetchStatus`
/// becomes paused. Upstream's `pause` action.
final class QueryPauseAction extends QueryAction {
  /// Creates the action.
  const QueryPauseAction();
}

/// A paused fetch resumed; `fetchStatus` is fetching again. Upstream's
/// `continue` action.
final class QueryContinueAction extends QueryAction {
  /// Creates the action.
  const QueryContinueAction();
}

/// The query was marked stale by `QueryClient.invalidateQueries`. Only
/// `isInvalidated` changes; whether a refetch follows is the caller's
/// decision. Upstream's `invalidate` action.
final class QueryInvalidateAction extends QueryAction {
  /// Creates the action.
  const QueryInvalidateAction();
}

/// The whole state was replaced through [Query.setState] — a reset, a
/// revert after cancellation, or a persistence layer restoring. Upstream's
/// `setState` action.
final class QuerySetStateAction<TQueryData> extends QueryAction {
  /// Creates the action carrying the replacement [state].
  const QuerySetStateAction(this.state);

  /// The state the query now holds, verbatim.
  final QueryState<TQueryData> state;
}

/// One cache entry: a key, its options, its state, and the fetch machinery.
///
/// One type parameter, not upstream's four: `TError` is gone (errors are
/// `Object` + `StackTrace`), the key is a value type, and the `select`
/// transform lives in the observer
/// (https://github.com/KoTTi97/flutter_query/issues/7).
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
  /// and an observer reading it that way then handed it
  /// `DefaultedQueryOptions<int?>`, which its `setOptions` refused with a raw
  /// `TypeError`. One key, one exact type (fourth review, 2026-09-09).
  Type get dataType => TQueryData;

  DefaultedQueryOptions<TQueryData> _options;

  /// The options in force, fully resolved. They are the last options any
  /// observer or fetch handed in; `queryFn`, `retry`, `networkMode` and the
  /// like are read from here at fetch time.
  DefaultedQueryOptions<TQueryData> get options => _options;

  late QueryState<TQueryData> _state;

  /// The current state: data, error, status, fetch status and the counters.
  /// Replaced on every dispatch; observers compute their results from it.
  QueryState<TQueryData> get state => _state;

  late QueryState<TQueryData> _initialState;

  /// The state this query returns to on [reset].
  QueryState<TQueryData> get resetState => _initialState;

  final List<QueryObserverRef> _observers = <QueryObserverRef>[];

  /// The observers attached right now, read-only; [addObserver] and
  /// [removeObserver] are the only way in and out.
  List<QueryObserverRef> get observers =>
      UnmodifiableListView<QueryObserverRef>(_observers);

  Retryer<TQueryData>? _retryer;

  /// The in-flight fetch as its callers see it: settled only once the data is
  /// in the cache and the cache hooks have run, or the error is in the state.
  /// Kept apart from the retryer's own future, which is the transport alone —
  /// a second caller that joined a running fetch used to get that one, and
  /// so saw `42` as a success while the first caller and the query ended in
  /// the error a throwing `structuralSharing` hook produced (fifth review,
  /// 2026-09-09).
  Completer<TQueryData>? _operation;
  QueryState<TQueryData>? _revertState;
  bool _signalConsumed = false;

  /// The options' `meta`, as upstream exposes it on the query for cache
  /// listeners and devtools.
  Object? get meta => _options.meta;

  /// The in-flight fetch, if there is one: the future every caller of [fetch]
  /// shares, settled once the cache has been written.
  Future<TQueryData>? get future => _operation?.future;

  /// How many observers are attached right now. Upstream's
  /// `getObserversCount`.
  int get observersCount => _observers.length;

  /// Replaces the options and folds their `gcTime` in. Called by observers as
  /// they attach and by [fetch]; not for user code, which sets options through
  /// an observer or the client.
  @internal
  void setOptions(DefaultedQueryOptions<TQueryData> options) {
    _options = options;
    updateGcTime(options.gcTime);

    // Late-arriving initialData still seeds a query that has never resolved.
    // Only the success fields are written: a fetch already in flight keeps its
    // `fetchStatus`, and `dataUpdateCount` stays where it was, because seeding
    // is not fetching.
    if (!_state.hasData) {
      final defaultState = _defaultState(options);
      if (defaultState.hasData) {
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
  }) {
    final sharing = _options.structuralSharing;
    final previous = _state.hasData ? _state.data : null;
    final data = sharing == null
        ? replaceEqualDeep<TQueryData>(previous, newData)
        : sharing(previous, newData);

    _dispatch(
      QuerySuccessAction<TQueryData>(
        data,
        dataUpdatedAt: updatedAt,
        manual: manual,
      ),
    );

    return data;
  }

  /// Replaces this query's state wholesale — the door persistence and devtools
  /// come through (https://github.com/KoTTi97/flutter_query/issues/17).
  ///
  /// A `success` state must carry data, the same invariant
  /// [QueryCache.build] checks on the other half of that door: a success
  /// state is by definition one that holds data, and an observer built on
  /// `success` with none casts `null` to the data type and throws — in its
  /// constructor, into whatever zone happened to be running, leaving a reader
  /// that never recovers. Rejected here in every build mode: an `assert`
  /// would let a release build accept the state and fail later somewhere that
  /// says nothing about where it came from (eighth review, 2026-09-10).
  void setState(QueryState<TQueryData> state) {
    if (state.status == QueryStatus.success && !state.hasData) {
      throw ArgumentError.value(
        state,
        'state',
        'A QueryState with status == success must have hasData == true. '
            'This is the persistence and devtools door; check what was '
            'restored for $queryKey',
      );
    }
    _dispatch(QuerySetStateAction<TQueryData>(state));
  }

  /// Cancels the in-flight fetch, completing once it has settled.
  ///
  /// [revert] puts the state back to what it was before the fetch. [silent]
  /// dispatches no error — it is how a cancel-refetch hands one fetch's
  /// callers to the next, and the successor's own `fetch` action is what ends
  /// the `fetching` status.
  ///
  /// When no successor turns up, this puts the fetch status back to `idle`
  /// itself. Upstream leaves it `fetching` with nothing running and no way
  /// out — reachable from one public call,
  /// `QueryClient.cancelQueries(silent: true)` — and a query wedged that way
  /// never loads again (eighth review, 2026-09-10). Not on a query the cache
  /// has dropped, though: its `destroy` cancels silently too, and the reset
  /// dispatched a `QueryUpdated` *after* the cache's `QueryRemoved`, handing
  /// an observer still attached a result from outside the cache (ninth
  /// review, 2026-09-10, C9). Upstream dispatches nothing after a silent
  /// cancel; a removed query dispatches nothing here either.
  Future<void> cancel({bool revert = false, bool silent = false}) async {
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

  @override
  void scheduleGc() {
    if (_removed) {
      return;
    }
    super.scheduleGc();
  }

  /// Back to the state this query was created with.
  void reset() {
    destroy();
    setState(_initialState);
    // `destroy` dropped the gc timer. Upstream never re-arms it, so a reset
    // query nobody observes stays in the cache for good; here it is collected
    // like any other idle entry.
    if (_observers.isEmpty) {
      scheduleGc();
    }
  }

  /// Whether any observer's `enabled` resolves to true.
  bool isActive() => _observers.any((observer) => observer.isEnabledForQuery);

  /// Whether the query will not fetch on its own.
  bool isDisabled() {
    if (observersCount > 0) {
      return !isActive();
    }
    // A query nobody observes is disabled until it has attempted a fetch.
    return !isFetched();
  }

  /// Whether at least one fetch — or a manual write — has ever settled.
  bool isFetched() => _state.dataUpdateCount + _state.errorUpdateCount > 0;

  /// Whether any observer declared this query permanently fresh.
  bool isStatic() =>
      observersCount > 0 &&
      _observers.any((observer) => observer.isStaticForQuery);

  /// Whether the data should be refetched: any observer's result says so, or —
  /// with no observers — there is no data or it has been invalidated.
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
    if (refetchQueries) {
      for (final observer in _observers) {
        if (observer.shouldFetchOnWindowFocus()) {
          observer.refetchOnEvent();
          break;
        }
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
    for (final observer in _observers) {
      if (observer.shouldFetchOnReconnect()) {
        observer.refetchOnEvent();
        break;
      }
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

  /// Marks the data stale, dispatching [QueryInvalidateAction] unless it
  /// already is. `QueryClient.invalidateQueries` calls this and then decides
  /// about the refetch.
  void invalidate() {
    if (!_state.isInvalidated) {
      _dispatch(const QueryInvalidateAction());
    }
  }

  /// Runs the query function, through the retryer and any behaviour.
  ///
  /// Every caller gets the same future — the one that settles once the data
  /// has been written to the cache and the cache hooks have run, or the
  /// error is in the state — whether it started the fetch or joined one
  /// already running. The retryer is installed *before* the fetch is
  /// announced, so a listener that reacts to the `fetch` action (a
  /// `cancelQueries` on `isFetching`, a `client.query` of the same key from
  /// a cache event, a `clear()`) finds something to cancel or to join;
  /// upstream announces first and installs after, and both of those ran the
  /// query function twice or not at all as asked (fifth review,
  /// 2026-09-09).
  Future<TQueryData> fetch({
    DefaultedQueryOptions<TQueryData>? options,
    FetchOptions<TQueryData>? fetchOptions,
  }) {
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

    if (options != null) {
      setOptions(options);
    }

    // A query created by setQueryData or restored from persistence has no
    // query function of its own; borrow one from an observer.
    if (_options.queryFn == null) {
      for (final observer in _observers) {
        final observerOptions = observer.observerQueryOptions;
        if (observerOptions.queryFn != null) {
          setOptions(observerOptions as DefaultedQueryOptions<TQueryData>);
          break;
        }
      }
    }

    final cancelToken = QueryCancelToken();
    _signalConsumed = false;

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
        onSignalRead: () => _signalConsumed = true,
      );
      // Reset per attempt, exactly where upstream resets it: a retry that
      // never touches the token is as uncancellable as a first try that
      // did not.
      _signalConsumed = false;
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
      onSignalRead: () => _signalConsumed = true,
    );

    _options.behavior?.onFetch(context, this);

    // Whether the attempt can only end in `MissingQueryFunctionError`: no
    // query function, and no behaviour that replaced the fetch with its own
    // (an infinite query has no `queryFn` either; its pages come from
    // `pageFn`). Decided here, where a query is known from a mutation, rather
    // than in the retryer.
    final missingQueryFn =
        _options.queryFn == null && identical(context.fetchFn, runQueryFn);

    // Kept in case this fetch has to be reverted.
    _revertState = _state;

    // Constructing a retryer runs nothing; `start()` does, below.
    final retryer = Retryer<TQueryData>(
      fn: context.fetchFn,
      focusManager: client.focusManager,
      onlineManager: client.onlineManager,
      canRun: () => true,
      // A missing query function is a configuration error, and retrying it
      // only delays the message by the whole backoff. Upstream retries it
      // like any other failure; here the one attempt is the answer (fourth
      // review, 2026-09-09). A per-fetch `retry` outranks the options'.
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
    // `fetchFailureCount` (fourth review, 2026-09-09).
    _dispatch(QueryFetchAction(meta: fetchOptions?.meta));

    _settle(retryer, operation).ignore();
    return operation.future;
  }

  /// Runs [retryer] to its end and completes [operation] with what the cache
  /// ended up holding: the data once written and the hooks run, or the
  /// error once dispatched.
  Future<void> _settle(
    Retryer<TQueryData> retryer,
    Completer<TQueryData> operation,
  ) async {
    try {
      final data = await retryer.start();
      setData(data);
      operation.complete(data);
      _runCacheHook(() => _cache.onQueryFetchSuccess(this, data));
    } catch (error, stackTrace) {
      if (error is CancelledError) {
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
          if (_state.hasData) {
            operation.complete(_state.data as TQueryData);
          } else {
            operation.completeError(error, stackTrace);
          }
          return;
        }
      }
      _dispatch(QueryErrorAction(error, stackTrace));
      operation.completeError(error, stackTrace);
      _runCacheHook(() => _cache.onQueryFetchError(this, error, stackTrace));
    } finally {
      if (identical(_retryer, retryer)) {
        _retryer = null;
      }
      if (identical(_operation, operation)) {
        _operation = null;
      }
      // Only when nobody is watching, the rule the mutation side settled on
      // in the fourth review: an observer leaving arms the timer in
      // `removeObserver`, and a timer standing while a widget is mounted is
      // what Flutter's widget tests assert against (fifth review,
      // 2026-09-09).
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
  /// failure is not the fetch's (ninth review, 2026-09-10, C3).
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
        // after it (fifth review, 2026-09-09).
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
