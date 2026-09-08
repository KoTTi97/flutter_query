/// Port of `query-core/src/query.ts` at upstream `50680b98c`.
library;

import 'dart:async';

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

/// What a [Query] needs from an observer, without knowing what an observer is.
abstract interface class QueryObserverRef {
  /// The query's state changed.
  void onQueryUpdate();

  /// Whether this observer's `enabled` currently resolves to true.
  bool get isEnabledForQuery;

  /// Whether this observer's own `staleTime` is [StaleTimeStatic].
  bool get isStaticForQuery;

  /// Whether this observer's current result considers the data stale.
  bool get currentResultIsStale;

  bool shouldFetchOnWindowFocus();

  bool shouldFetchOnReconnect();

  /// Refetch without cancelling a fetch that is already running.
  void refetchOnEvent();

  /// The options this observer contributes when the query itself has none.
  DefaultedQueryOptions<Object?> get observerQueryOptions;
}

/// What a [Query] needs from its cache.
abstract interface class QueryCacheRef {
  void onQueryStateUpdated(Query<Object?> query, QueryAction action);
  void onQueryRemovalRequested(Query<Object?> query);
  void onQueryFetchSuccess(Query<Object?> query, Object? data);
  void onQueryFetchError(
    Query<Object?> query,
    Object error,
    StackTrace stackTrace,
  );
}

/// Rewrites how a fetch runs.
///
/// Upstream's `QueryBehavior`. Infinite queries use it to turn one fetch into
/// a loop over pages; nothing else does, and users never set one
/// (https://github.com/KoTTi97/flutter_query/issues/16).
abstract interface class FetchBehavior<TQueryData> {
  void onFetch(FetchContext<TQueryData> context, Query<TQueryData> query);
}

/// The mutable description of one fetch, handed to a [FetchBehavior].
class FetchContext<TQueryData> {
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

  final QueryClient client;
  final QueryKey queryKey;
  final DefaultedQueryOptions<TQueryData> options;
  final QueryState<TQueryData> state;
  final FetchOptions<TQueryData>? fetchOptions;

  /// Replaced by a behaviour to change what the fetch actually does.
  Future<TQueryData> Function() fetchFn;

  final QueryCancelToken _signal;
  final void Function()? _onSignalRead;
  bool _signalConsumed = false;

  QueryCancelToken get signal {
    _signalConsumed = true;
    _onSignalRead?.call();
    return _signal;
  }

  @internal
  bool get signalConsumed => _signalConsumed;
}

/// Per-fetch overrides.
@immutable
class FetchOptions<TQueryData> {
  const FetchOptions({this.cancelRefetch, this.meta, this.initialFuture});

  /// Cancel a fetch that is already running and start a new one.
  final bool? cancelRefetch;

  /// Carried into [QueryState.fetchMeta]; infinite queries put the page
  /// direction here.
  final Object? meta;

  /// A fetch that has already been started elsewhere.
  final Future<TQueryData>? initialFuture;
}

/// A state transition. Sealed, so the reducer is exhaustive.
@immutable
sealed class QueryAction {
  const QueryAction();
}

final class QueryFetchAction extends QueryAction {
  const QueryFetchAction({this.meta});
  final Object? meta;
}

final class QueryFailedAction extends QueryAction {
  const QueryFailedAction(this.failureCount, this.error, this.stackTrace);
  final int failureCount;
  final Object error;
  final StackTrace stackTrace;
}

final class QuerySuccessAction<TQueryData> extends QueryAction {
  const QuerySuccessAction(this.data,
      {this.dataUpdatedAt, this.manual = false});
  final TQueryData data;
  final DateTime? dataUpdatedAt;
  final bool manual;
}

final class QueryErrorAction extends QueryAction {
  const QueryErrorAction(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

final class QueryPauseAction extends QueryAction {
  const QueryPauseAction();
}

final class QueryContinueAction extends QueryAction {
  const QueryContinueAction();
}

final class QueryInvalidateAction extends QueryAction {
  const QueryInvalidateAction();
}

final class QuerySetStateAction<TQueryData> extends QueryAction {
  const QuerySetStateAction(this.state);
  final QueryState<TQueryData> state;
}

/// One cache entry: a key, its options, its state, and the fetch machinery.
///
/// One type parameter, not upstream's four: `TError` is gone (errors are
/// `Object` + `StackTrace`), the key is a value type, and the `select`
/// transform lives in the observer
/// (https://github.com/KoTTi97/flutter_query/issues/7).
class Query<TQueryData> extends Removable {
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

  final QueryClient client;
  final QueryCacheRef _cache;
  final QueryKey queryKey;

  DefaultedQueryOptions<TQueryData> _options;
  DefaultedQueryOptions<TQueryData> get options => _options;

  late QueryState<TQueryData> _state;
  QueryState<TQueryData> get state => _state;

  late QueryState<TQueryData> _initialState;

  /// The state this query returns to on [reset].
  QueryState<TQueryData> get resetState => _initialState;

  final List<QueryObserverRef> observers = <QueryObserverRef>[];

  Retryer<TQueryData>? _retryer;
  QueryState<TQueryData>? _revertState;
  bool _signalConsumed = false;

  Object? get meta => _options.meta;

  /// The in-flight fetch, if there is one.
  Future<TQueryData>? get future => _retryer?.future;

  int get observersCount => observers.length;

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
    if (observers.isEmpty && _state.fetchStatus == FetchStatus.idle) {
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
    final data = sharing == null
        ? newData
        : sharing(_state.hasData ? _state.data : null, newData);

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
  void setState(QueryState<TQueryData> state) =>
      _dispatch(QuerySetStateAction<TQueryData>(state));

  /// Cancels the in-flight fetch, completing once it has settled.
  Future<void> cancel({bool revert = false, bool silent = false}) async {
    final pending = _retryer?.future;
    _retryer?.cancel(revert: revert, silent: silent);
    if (pending == null) {
      return;
    }
    try {
      await pending;
    } catch (_) {
      // The error belongs to the query's state, not to whoever cancelled.
    }
  }

  /// Cancels silently and stops the gc timer.
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
  }

  /// Whether any observer's `enabled` resolves to true.
  bool isActive() => observers.any((observer) => observer.isEnabledForQuery);

  /// Whether the query will not fetch on its own.
  bool isDisabled() {
    if (observersCount > 0) {
      return !isActive();
    }
    // A query nobody observes is disabled until it has attempted a fetch.
    return !isFetched();
  }

  bool isFetched() => _state.dataUpdateCount + _state.errorUpdateCount > 0;

  /// Whether any observer declared this query permanently fresh.
  bool isStatic() =>
      observersCount > 0 &&
      observers.any((observer) => observer.isStaticForQuery);

  bool isStale() {
    if (observersCount > 0) {
      return observers.any((observer) => observer.currentResultIsStale);
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

  @internal
  void onFocus() {
    for (final observer in observers) {
      if (observer.shouldFetchOnWindowFocus()) {
        observer.refetchOnEvent();
        break;
      }
    }
    _retryer?.continueFetch().ignore();
  }

  @internal
  void onOnline() {
    for (final observer in observers) {
      if (observer.shouldFetchOnReconnect()) {
        observer.refetchOnEvent();
        break;
      }
    }
    _retryer?.continueFetch().ignore();
  }

  @internal
  void addObserver(QueryObserverRef observer) {
    if (!observers.contains(observer)) {
      observers.add(observer);
      clearGcTimeout();
      client.queryCache.notifyObserverAdded(this, observer);
    }
  }

  @internal
  void removeObserver(QueryObserverRef observer) {
    if (!observers.remove(observer)) {
      return;
    }

    if (observers.isEmpty) {
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

    client.queryCache.notifyObserverRemoved(this, observer);
  }

  void invalidate() {
    if (!_state.isInvalidated) {
      _dispatch(const QueryInvalidateAction());
    }
  }

  /// Runs the query function, through the retryer and any behaviour.
  Future<TQueryData> fetch({
    DefaultedQueryOptions<TQueryData>? options,
    FetchOptions<TQueryData>? fetchOptions,
  }) async {
    if (_state.fetchStatus != FetchStatus.idle &&
        _retryer?.status != RetryerStatus.rejected) {
      if (_state.hasData && (fetchOptions?.cancelRefetch ?? false)) {
        // Deliberately not awaited, as upstream does not: the replacement
        // retryer has to be installed before the cancelled fetch's `catch`
        // runs, or that fetch has nothing to piggyback on and rejects.
        cancel(silent: true).ignore();
      } else {
        final retryer = _retryer;
        if (retryer != null) {
          // Retries stopped by an unmount can continue.
          retryer.continueRetry();
          return retryer.future;
        }
      }
    }

    if (options != null) {
      setOptions(options);
    }

    // A query created by setQueryData or restored from persistence has no
    // query function of its own; borrow one from an observer.
    if (_options.queryFn == null) {
      for (final observer in observers) {
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

    // Kept in case this fetch has to be reverted.
    _revertState = _state;

    if (_state.fetchStatus == FetchStatus.idle ||
        _state.fetchMeta != fetchOptions?.meta) {
      _dispatch(QueryFetchAction(meta: fetchOptions?.meta));
    }

    final retryer = Retryer<TQueryData>(
      fn: context.fetchFn,
      initialFuture: fetchOptions?.initialFuture,
      focusManager: client.focusManager,
      onlineManager: client.onlineManager,
      canRun: () => true,
      retry: _options.retry,
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
    _retryer = retryer;

    try {
      final data = await retryer.start();
      setData(data);
      _cache.onQueryFetchSuccess(this, data);
      return data;
    } catch (error, stackTrace) {
      if (error is CancelledError) {
        if (error.silent) {
          // A silent cancel means a new fetch is starting: ride along with it.
          // When no new fetch replaced this one, `_retryer` is still this
          // rejected retryer, so the caller sees the CancelledError — and no
          // error is dispatched into the query's state, which is what a silent
          // cancel means.
          final replacement = _retryer;
          if (replacement != null) {
            return replacement.future;
          }
        } else if (error.revert) {
          if (!_state.hasData) {
            rethrow;
          }
          return _state.data as TQueryData;
        }
      }
      _dispatch(QueryErrorAction(error, stackTrace));
      _cache.onQueryFetchError(this, error, stackTrace);
      rethrow;
    } finally {
      if (identical(_retryer, retryer)) {
        _retryer = null;
      }
      scheduleGc();
    }
  }

  void _dispatch(QueryAction action) {
    _state = _reduce(_state, action);

    client.notifyManager.batch(() {
      // A stable copy: an observer may unsubscribe while being notified.
      for (final observer in List<QueryObserverRef>.of(observers)) {
        observer.onQueryUpdate();
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
    final initialData = options.initialData?.resolve();
    final hasData = options.initialData != null && initialData != null;

    return QueryState<TQueryData>(
      hasData: hasData,
      data: initialData,
      dataUpdatedAt:
          hasData ? (options.initialDataUpdatedAt ?? clock.now()) : null,
      status: hasData ? QueryStatus.success : QueryStatus.pending,
    );
  }

  @override
  String toString() => 'Query($queryKey, ${_state.status})';
}

/// Thrown when a query is fetched with no query function anywhere in its
/// options chain.
final class MissingQueryFunctionError implements Exception {
  const MissingQueryFunctionError(this.queryKey);

  final QueryKey queryKey;

  @override
  String toString() =>
      'No queryFn was provided for $queryKey. Pass one in the query options, '
      'or set a default with QueryClient.setQueryDefaults.';
}
