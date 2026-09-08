import 'dart:async';

import 'package:clock/clock.dart';

import 'cancel_token.dart';
import 'notify_manager.dart';
import 'option_values.dart';
import 'query_key.dart';
import 'query_options.dart';
import 'query_state.dart';
import 'removable.dart';
import 'retryer.dart';

/// What [Query] needs from an observer, without depending on the observer
/// implementation itself.
abstract interface class QueryObserverRef {
  /// This observer's resolved options, used for the enabled/staleTime checks
  /// a query makes across all of its observers.
  Enabled get enabledOption;
  StaleDuration get staleTimeOption;

  /// This observer's resolved cache-level options.
  ///
  /// A query with no query function of its own adopts these wholesale — the
  /// case for an entry created by `setQueryData` and observed afterwards.
  DefaultedQueryOptions<Object?> get queryOptions;

  /// Whether this observer currently considers its result stale.
  bool get isResultStale;

  /// Called after every state change, inside the notify batch.
  void onQueryUpdate();

  bool shouldFetchOnAppFocus();
  bool shouldFetchOnReconnect();

  /// Refetch without surfacing errors — used by focus/reconnect triggers.
  void refetchQuietly();
}

/// What a [Query] reports to its cache when something changes.
sealed class QueryAction {
  const QueryAction();
}

class QueryFetchAction extends QueryAction {
  const QueryFetchAction({this.meta});
  final Object? meta;
}

class QueryFailedAction extends QueryAction {
  const QueryFailedAction(this.failureCount, this.error, this.stackTrace);
  final int failureCount;
  final Object error;
  final StackTrace stackTrace;
}

class QuerySuccessAction<TQueryData> extends QueryAction {
  const QuerySuccessAction(
    this.data, {
    this.dataUpdatedAt,
    this.manual = false,
  });
  final TQueryData data;
  final DateTime? dataUpdatedAt;
  final bool manual;
}

class QueryErrorAction extends QueryAction {
  const QueryErrorAction(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

class QueryPauseAction extends QueryAction {
  const QueryPauseAction();
}

class QueryContinueAction extends QueryAction {
  const QueryContinueAction();
}

class QueryInvalidateAction extends QueryAction {
  const QueryInvalidateAction();
}

class QuerySetStateAction<TQueryData> extends QueryAction {
  const QuerySetStateAction(this.state);
  final QueryState<TQueryData> state;
}

/// Receives a query's changes. Implemented by `QueryCache`; declared here so
/// [Query] does not depend on the cache.
abstract interface class QueryHost {
  void onQueryUpdated(Query<Object?> query, QueryAction action);

  /// Cache-wide fetch callbacks. Reported by the fetch itself rather than by
  /// the resulting state change, so a manual `setQueryData` write does not look
  /// like a request that succeeded.
  void onQueryFetchSuccess(Query<Object?> query, Object? data);
  void onQueryFetchError(
    Query<Object?> query,
    Object error,
    StackTrace stackTrace,
  );

  void onQueryRemovalRequested(Query<Object?> query);
  void onQueryObserverAdded(Query<Object?> query, QueryObserverRef observer);
  void onQueryObserverRemoved(Query<Object?> query, QueryObserverRef observer);
}

/// One cache entry: the data, the state machine that maintains it, and the
/// fetch orchestration behind it.
class Query<TQueryData> extends Removable {
  Query({
    required this.queryKey,
    required QueryHost host,
    required DefaultedQueryOptions<TQueryData> options,
    QueryState<TQueryData>? initialState,
  }) : _host = host,
       _options = options {
    _initialState = initialState ?? _defaultState(options);
    _state = _initialState;
    updateGcTime(options.gcTime);
    scheduleGc();
  }

  final QueryKey queryKey;
  final QueryHost _host;

  DefaultedQueryOptions<TQueryData> _options;
  late QueryState<TQueryData> _initialState;
  late QueryState<TQueryData> _state;

  QueryState<TQueryData>? _revertState;
  Retryer<TQueryData>? _retryer;
  bool _cancelTokenConsumed = false;

  final List<QueryObserverRef> observers = <QueryObserverRef>[];

  QueryState<TQueryData> get state => _state;
  DefaultedQueryOptions<TQueryData> get options => _options;
  Object? get meta => _options.meta;

  /// The in-flight fetch, if any. Every observer of a fetching query awaits
  /// this same future — that is what deduplicates concurrent requests.
  Future<TQueryData>? get future => _retryer?.future;

  /// The state a [reset] returns to.
  QueryState<TQueryData> get resetState => _initialState;

  void setOptions(DefaultedQueryOptions<TQueryData> options) {
    _options = options;
    updateGcTime(options.gcTime);

    // A query created without data (by setQueryData, or by an observer that
    // had none) picks up initial data the moment options supplying it arrive.
    //
    // Only the data-bearing fields change: a fetch already in flight keeps its
    // fetchStatus, and dataUpdateCount stays put because seeding is not a
    // fetch. Upstream expresses this by merging a partial state; here the merge
    // is spelled out.
    if (!_state.hasData) {
      final defaults = _defaultState(options);
      if (defaults.hasData) {
        setState(
          _state.copyWith(
            hasData: true,
            data: defaults.data,
            dataUpdatedAt: defaults.dataUpdatedAt,
            error: null,
            errorStackTrace: null,
            isInvalidated: false,
            status: QueryStatus.success,
          ),
        );
        _initialState = defaults;
      }
    }
  }

  /// Writes [data] into the cache.
  ///
  /// [manual] marks a write that did not come from a fetch, which keeps the
  /// current fetch status intact and snapshots the new state as the revert
  /// target — so a cancellation after an optimistic write returns here.
  TQueryData setData(
    TQueryData data, {
    DateTime? updatedAt,
    bool manual = false,
  }) {
    final sharing = _options.structuralSharing;
    final next = sharing == null ? data : sharing(_state.data, data);

    _dispatch(
      QuerySuccessAction<TQueryData>(
        next,
        dataUpdatedAt: updatedAt,
        manual: manual,
      ),
    );
    return next;
  }

  void setState(QueryState<TQueryData> state) =>
      _dispatch(QuerySetStateAction<TQueryData>(state));

  /// Cancels an in-flight fetch. Resolves once it has settled.
  Future<void> cancel({bool revert = false, bool silent = false}) {
    final retryer = _retryer;
    final future = retryer?.future;
    retryer?.cancel(revert: revert, silent: silent);
    if (future == null) {
      return Future<void>.value();
    }
    // Swallow the outcome: the caller wants to know the fetch is over, not
    // how it ended.
    return future.then<void>((_) {}, onError: (Object _) {});
  }

  @override
  void destroy() {
    super.destroy();
    cancel(silent: true).ignore();
  }

  /// Returns to the initial state and drops any in-flight fetch.
  void reset() {
    destroy();
    setState(resetState);
  }

  void invalidate() {
    if (!_state.isInvalidated) {
      _dispatch(const QueryInvalidateAction());
    }
  }

  /// Whether any observer wants this query to run.
  bool isActive() =>
      observers.any((observer) => observer.enabledOption.resolveWith(this));

  bool isDisabled() {
    if (observers.isNotEmpty) {
      return !isActive();
    }
    // With no observers, a query is disabled if it can never run (no query
    // function — the port's stand-in for upstream's skipToken) or if it has
    // never even attempted a fetch. One that has fetched is merely idle.
    return _options.queryFn == null || !isFetched();
  }

  bool isFetched() => _state.isFetched;

  /// Whether any observer has pinned this query as never-refetching.
  bool isStatic() => observers.any(
    (observer) =>
        observer.staleTimeOption.resolveWith(this) is StaleDurationStatic,
  );

  bool isStale() {
    // Observers know best: their staleness accounts for enabled and staleTime.
    if (observers.isNotEmpty) {
      return observers.any((observer) => observer.isResultStale);
    }
    return !_state.hasData || _state.isInvalidated;
  }

  bool isStaleByTime([StaleDuration staleTime = StaleDuration.zero]) {
    if (!_state.hasData) {
      return true;
    }
    final resolved = staleTime.resolveWith(this);
    if (resolved is StaleDurationStatic) {
      return false;
    }
    if (_state.isInvalidated) {
      return true;
    }
    if (resolved is StaleDurationInfinity) {
      return false;
    }
    final updatedAt = _state.dataUpdatedAt;
    if (updatedAt == null) {
      return true;
    }
    final duration = (resolved as StaleDurationValue).duration;
    return !clock.now().isBefore(updatedAt.add(duration));
  }

  void onFocus() {
    for (final observer in List.of(observers)) {
      if (observer.shouldFetchOnAppFocus()) {
        observer.refetchQuietly();
        break;
      }
    }
    _retryer?.resume().ignore();
  }

  void onOnline() {
    for (final observer in List.of(observers)) {
      if (observer.shouldFetchOnReconnect()) {
        observer.refetchQuietly();
        break;
      }
    }
    _retryer?.resume().ignore();
  }

  void addObserver(QueryObserverRef observer) {
    if (observers.contains(observer)) {
      return;
    }
    observers.add(observer);
    // An observed query is in use, so stop the collection clock.
    clearGcTimeout();
    _host.onQueryObserverAdded(this, observer);
  }

  void removeObserver(QueryObserverRef observer) {
    if (!observers.remove(observer)) {
      return;
    }

    if (observers.isEmpty) {
      final retryer = _retryer;
      if (retryer != null) {
        // If the fetch can really be aborted, abort it and undo the optimistic
        // fetching state. If it cannot, let it finish so its result is still
        // cached — just stop retrying.
        if (_cancelTokenConsumed || _isInitialPausedFetch()) {
          retryer.cancel(revert: true);
        } else {
          retryer.cancelRetry();
        }
      }
      scheduleGc();
    }

    _host.onQueryObserverRemoved(this, observer);
  }

  int get observersCount => observers.length;

  bool _isInitialPausedFetch() =>
      _state.fetchStatus == FetchStatus.paused &&
      _state.status == QueryStatus.pending;

  @override
  void optionalRemove() {
    if (observers.isEmpty && _state.fetchStatus == FetchStatus.idle) {
      _host.onQueryRemovalRequested(this);
    }
  }

  /// Fetches, or joins the fetch already running.
  ///
  /// [cancelRefetch] replaces an in-flight fetch with a fresh one; without it,
  /// a second caller simply awaits the first fetch's future.
  Future<TQueryData> fetch({
    DefaultedQueryOptions<TQueryData>? options,
    bool cancelRefetch = false,
    Object? fetchMeta,
  }) async {
    final existing = _retryer;
    if (_state.fetchStatus != FetchStatus.idle &&
        existing?.status != RetryerStatus.rejected) {
      if (_state.hasData && cancelRefetch) {
        // Silent, because the replacement fetch starting below is what the
        // caller will await.
        //
        // Deliberately not awaited: the cancelled fetch's own `catch` runs on a
        // microtask and reads `_retryer` to find the fetch it should piggyback
        // on. Suspending here would let it run before the replacement is
        // installed, and it would adopt the very retryer that just failed.
        cancel(silent: true).ignore();
      } else if (existing != null) {
        // A retry cancelled by an unmount can pick up again here.
        existing.continueRetry();
        return existing.future;
      }
    }

    if (options != null) {
      setOptions(options);
    }

    // An entry created by setQueryData (or hydration) has no query function of
    // its own. It takes the options of the first observer that has one, rather
    // than only borrowing the function: everything else on those options — meta,
    // retry, network mode — describes the same request.
    if (_options.queryFn == null) {
      for (final observer in observers) {
        final candidate = observer.queryOptions;
        if (candidate.queryFn != null) {
          setOptions(candidate as DefaultedQueryOptions<TQueryData>);
          break;
        }
      }
    }

    final queryFn = _resolveQueryFn();
    final cancelToken = QueryCancelToken();
    _cancelTokenConsumed = false;

    final context = QueryFunctionContext(
      queryKey: queryKey,
      cancelToken: cancelToken,
      meta: _options.meta,
      onTokenConsumed: () => _cancelTokenConsumed = true,
    );

    // Snapshot before the fetch, so a reverting cancellation can restore it.
    _revertState = _state;

    if (_state.fetchStatus == FetchStatus.idle ||
        !identical(_state.fetchMeta, fetchMeta)) {
      _dispatch(QueryFetchAction(meta: fetchMeta));
    }

    final retryer = Retryer<TQueryData>(
      fn: () => queryFn(context),
      canRun: () => true,
      networkMode: _options.networkMode,
      retry: _options.retry,
      retryDelay: _options.retryDelay,
      onCancel: (error) {
        if (error.revert) {
          final revertState = _revertState;
          if (revertState != null) {
            setState(revertState.copyWith(fetchStatus: FetchStatus.idle));
          }
        }
        cancelToken.cancel(error);
      },
      onFail: (failureCount, error, stackTrace) =>
          _dispatch(QueryFailedAction(failureCount, error, stackTrace)),
      onPause: () => _dispatch(const QueryPauseAction()),
      onContinue: () => _dispatch(const QueryContinueAction()),
    );
    _retryer = retryer;

    try {
      final data = await retryer.start();
      setData(data);
      _host.onQueryFetchSuccess(this, data);
      return data;
    } catch (error, stackTrace) {
      if (error is CancelledError) {
        if (error.silent) {
          // A silent cancellation means a replacement fetch is starting, so
          // hand back whatever the current retryer produces. Notably this does
          // *not* record an error: nothing failed, the fetch was superseded.
          final current = _retryer;
          if (current != null) {
            return current.future;
          }
        }
        if (error.revert) {
          // The reverted state is the answer, unless there was nothing to
          // revert to.
          if (_state.hasData) {
            return _state.data as TQueryData;
          }
          rethrow;
        }
      }

      _dispatch(QueryErrorAction(error, stackTrace));
      _host.onQueryFetchError(this, error, stackTrace);
      rethrow;
    } finally {
      // Holding the settled retryer would pin its raw result for the query's
      // lifetime.
      if (identical(_retryer, retryer)) {
        _retryer = null;
      }
      scheduleGc();
    }
  }

  QueryFn<TQueryData> _resolveQueryFn() {
    final own = _options.queryFn;
    if (own != null) {
      return own;
    }
    final key = queryKey;
    return (_) => Future<TQueryData>.error(MissingQueryFunctionError(key));
  }

  void _dispatch(QueryAction action) {
    _state = _reduce(_state, action);

    notifyManager.batch(() {
      // Copy: an observer may unsubscribe while being notified.
      for (final observer in List.of(observers)) {
        observer.onQueryUpdate();
      }
      _host.onQueryUpdated(this, action);
    });
  }

  QueryState<TQueryData> _reduce(
    QueryState<TQueryData> state,
    QueryAction action,
  ) {
    switch (action) {
      case QueryFailedAction():
        return state.copyWith(
          fetchFailureCount: action.failureCount,
          fetchFailureReason: action.error,
          fetchFailureStackTrace: action.stackTrace,
        );

      case QueryPauseAction():
        return state.copyWith(fetchStatus: FetchStatus.paused);

      case QueryContinueAction():
        return state.copyWith(fetchStatus: FetchStatus.fetching);

      case QueryFetchAction():
        final fetching = state.copyWith(
          fetchFailureCount: 0,
          fetchFailureReason: null,
          fetchFailureStackTrace: null,
          fetchStatus: canFetch(_options.networkMode)
              ? FetchStatus.fetching
              : FetchStatus.paused,
          fetchMeta: action.meta,
        );
        // Data already on screen keeps its status through a background fetch;
        // only a query with nothing to show returns to a clean pending state.
        return state.hasData
            ? fetching
            : fetching.copyWith(
                error: null,
                errorStackTrace: null,
                status: QueryStatus.pending,
              );

      case QuerySuccessAction<TQueryData>():
        final next = state.copyWith(
          hasData: true,
          data: action.data,
          dataUpdateCount: state.dataUpdateCount + 1,
          dataUpdatedAt: action.dataUpdatedAt ?? clock.now(),
          error: null,
          errorStackTrace: null,
          isInvalidated: false,
          status: QueryStatus.success,
          fetchStatus: action.manual ? state.fetchStatus : FetchStatus.idle,
          fetchFailureCount: action.manual ? state.fetchFailureCount : 0,
          fetchFailureReason: action.manual ? state.fetchFailureReason : null,
        );
        // A successful fetch has nothing to revert to; a manual write becomes
        // the new revert target so a later cancellation returns here.
        _revertState = action.manual ? next : null;
        return next;

      case QueryErrorAction():
        return state.copyWith(
          error: action.error,
          errorStackTrace: action.stackTrace,
          errorUpdateCount: state.errorUpdateCount + 1,
          errorUpdatedAt: clock.now(),
          fetchFailureCount: state.fetchFailureCount + 1,
          fetchFailureReason: action.error,
          fetchFailureStackTrace: action.stackTrace,
          fetchStatus: FetchStatus.idle,
          status: QueryStatus.error,
          // Data that survived a failed refresh is stale by definition.
          isInvalidated: true,
        );

      case QueryInvalidateAction():
        return state.copyWith(isInvalidated: true);

      case QuerySetStateAction<TQueryData>():
        return action.state;

      // Actions carrying a different data type cannot apply here.
      case QuerySuccessAction<Object?>():
      case QuerySetStateAction<Object?>():
        return state;
    }
  }
}

QueryState<TQueryData> _defaultState<TQueryData>(
  DefaultedQueryOptions<TQueryData> options,
) {
  final initialData = options.initialData?.call();
  final hasData = initialData != null;

  return QueryState<TQueryData>(
    hasData: hasData,
    data: initialData,
    dataUpdatedAt: hasData
        ? (options.initialDataUpdatedAt?.call() ?? clock.now())
        : null,
    status: hasData ? QueryStatus.success : QueryStatus.pending,
  );
}
