import 'dart:async';

import 'package:clock/clock.dart';

import 'focus_manager.dart';
import 'notify_manager.dart';
import 'option_values.dart';
import 'query.dart';
import 'query_cache.dart';
import 'query_options.dart';
import 'query_result.dart';
import 'query_state.dart';

/// What an observer needs from the client.
///
/// Declared here rather than imported so `QueryObserver` does not depend on
/// `QueryClient`, which depends on it — the same cycle-breaking move as
/// [QueryHost].
abstract interface class ObserverClient {
  QueryCache get queryCache;

  DefaultedQueryObserverOptions<TQueryData, TData>
      defaultQueryOptions<TQueryData, TData>(
          QueryObserverOptions<TQueryData, TData> options);
}

/// Holds a selected value so "no value" and "a null value" stay distinct.
class _Box<T> {
  const _Box(this.value);
  final T value;
}

typedef QueryObserverListener<TData> = void Function(QueryResult<TData> result);

/// One watcher of one query: it owns the options, the derived [QueryResult],
/// and the timers that keep that result honest.
///
/// A [Query] is shared by everyone using its key; an observer is per use site.
/// That is where `select`, `staleTime` and the refetch triggers live, because
/// two widgets can watch the same cache entry with different answers to each.
///
/// The observer is synchronously authoritative: the constructor computes
/// [result], so it is valid before anyone subscribes. A Flutter binding can
/// therefore build its first frame from `observer.result` without a
/// null-check or an intermediate "no result yet" state.
///
/// It does not extend [Subscribable] as upstream does, because Dart forbids a
/// class type parameter in a contravariant position of a superinterface —
/// `TData` appears in the listener's argument type. The subscription contract
/// is the same.
class QueryObserver<TQueryData, TData> implements QueryObserverRef {
  QueryObserver(this._client, QueryObserverOptions<TQueryData, TData> options) {
    setOptions(options);
  }

  final ObserverClient _client;

  late DefaultedQueryObserverOptions<TQueryData, TData> _options;
  DefaultedQueryObserverOptions<TQueryData, TData>? _optionsOrNull;

  late Query<TQueryData> _currentQuery;
  Query<TQueryData>? _currentQueryOrNull;

  /// The query's state when this observer started watching it — the baseline
  /// for [QueryResult.isFetchedAfterMount].
  late QueryState<TQueryData> _currentQueryInitialState;

  late QueryResult<TData> _currentResult;
  QueryResult<TData>? _currentResultOrNull;

  /// The query state the current result was derived from, used to tell whether
  /// the select result can be reused.
  QueryState<TQueryData>? _currentResultState;

  Object? _selectError;
  StackTrace? _selectErrorStackTrace;
  TData Function(TQueryData data)? _selectFn;
  _Box<TData>? _selectResult;

  Timer? _staleTimer;
  Timer? _refetchTimer;
  Duration? _currentRefetchInterval;

  DefaultedQueryObserverOptions<TQueryData, TData> get options => _options;

  Query<TQueryData> get currentQuery => _currentQuery;

  /// The current result. Always valid, including before the first subscribe.
  QueryResult<TData> get result => _currentResult;

  final Set<QueryObserverListener<TData>> _listeners =
      <QueryObserverListener<TData>>{};

  bool get hasListeners => _listeners.isNotEmpty;

  /// Registers [listener] and returns the function that removes it.
  ///
  /// The first subscriber is what mounts the observer on its query: that is
  /// when the query stops being a collection candidate and when a
  /// fetch-on-mount happens.
  void Function() subscribe(QueryObserverListener<TData> listener) {
    _listeners.add(listener);
    _onSubscribe();
    return () {
      _listeners.remove(listener);
      _onUnsubscribe();
    };
  }

  void _onSubscribe() {
    if (_listeners.length != 1) {
      return;
    }
    _currentQuery.addObserver(this);

    if (_shouldFetchOnMount(_currentQuery, _options)) {
      _executeFetch().ignore();
    } else {
      updateResult();
    }

    _updateTimers();
  }

  void _onUnsubscribe() {
    if (!hasListeners) {
      destroy();
    }
  }

  /// Detaches from the query and stops every timer. The query's collection
  /// clock starts here, when its last observer leaves (D11).
  void destroy() {
    _listeners.clear();
    _clearStaleTimeout();
    _clearRefetchInterval();
    _currentQuery.removeObserver(this);
  }

  void setOptions(QueryObserverOptions<TQueryData, TData> options) {
    final prevOptions = _optionsOrNull;
    final prevQuery = _currentQueryOrNull;

    _options = _client.defaultQueryOptions(options);
    _optionsOrNull = _options;

    _updateQuery();
    _currentQuery.setOptions(_options);

    if (prevOptions != null && _options != prevOptions) {
      _client.queryCache.notify(
        QueryObserverOptionsUpdated(_currentQuery, this),
      );
    }

    // Only a mounted observer acts on an options change; an unmounted one just
    // records it, and `onSubscribe` does the work when someone starts watching.
    final mounted = hasListeners;

    if (mounted &&
        prevQuery != null &&
        prevOptions != null &&
        _shouldFetchOptionally(
          _currentQuery,
          prevQuery,
          _options,
          prevOptions,
        )) {
      _executeFetch().ignore();
    }

    updateResult();

    if (mounted &&
        prevOptions != null &&
        (!identical(_currentQuery, prevQuery) ||
            _options.enabled.resolveWith(_currentQuery) !=
                prevOptions.enabled.resolveWith(_currentQuery) ||
            _options.staleTime.resolveWith(_currentQuery) !=
                prevOptions.staleTime.resolveWith(_currentQuery))) {
      _updateStaleTimeout();
    }

    final nextRefetchInterval = _computeRefetchInterval();

    if (mounted &&
        prevOptions != null &&
        (!identical(_currentQuery, prevQuery) ||
            _options.enabled.resolveWith(_currentQuery) !=
                prevOptions.enabled.resolveWith(_currentQuery) ||
            nextRefetchInterval != _currentRefetchInterval)) {
      _updateRefetchInterval(nextRefetchInterval);
    }
  }

  /// Refetches, replacing any fetch already running.
  ///
  /// The returned result carries a failure as [QueryError] instead of throwing:
  /// a refetch that fails is a state the UI renders, not an exception the call
  /// site has to catch.
  Future<QueryResult<TData>> refetch({bool cancelRefetch = true}) async {
    await _executeFetch(cancelRefetch: cancelRefetch);
    updateResult();
    return _currentResult;
  }

  Future<void> _executeFetch({bool cancelRefetch = false}) {
    // The query may have been removed from the cache since the last look.
    _updateQuery();

    return _currentQuery
        .fetch(options: _options, cancelRefetch: cancelRefetch)
        .then<void>((_) {}, onError: (Object _, StackTrace _) {});
  }

  void _updateQuery() {
    final query = _client.queryCache.build<TQueryData>(_options);
    if (identical(query, _currentQueryOrNull)) {
      return;
    }

    final prevQuery = _currentQueryOrNull;
    _currentQuery = query;
    _currentQueryOrNull = query;
    _currentQueryInitialState = query.state;

    if (hasListeners) {
      prevQuery?.removeObserver(this);
      query.addObserver(this);
    }
  }

  // --- Timers ---------------------------------------------------------------

  void _updateTimers() {
    _updateStaleTimeout();
    _updateRefetchInterval(_computeRefetchInterval());
  }

  void _updateStaleTimeout() {
    _clearStaleTimeout();

    final staleTime = _options.staleTime.resolveWith(_currentQuery);
    // Already stale, or never becomes stale on a clock: nothing to wait for.
    if (_currentResult.isStale || staleTime is! StaleDurationValue) {
      return;
    }

    final updatedAt = _currentResult.dataUpdatedAt;
    final remaining = updatedAt == null
        ? Duration.zero
        : updatedAt.add(staleTime.duration).difference(clock.now());

    // Upstream adds a millisecond because the timer sometimes fires just before
    // the staleness boundary, which would leave the result fresh and the timer
    // spent.
    final timeout = (remaining.isNegative ? Duration.zero : remaining) +
        const Duration(milliseconds: 1);

    _staleTimer = Timer(timeout, () {
      if (!_currentResult.isStale) {
        updateResult();
      }
    });
  }

  Duration? _computeRefetchInterval() =>
      _options.refetchInterval.resolveWith(_currentQuery);

  void _updateRefetchInterval(Duration? next) {
    _clearRefetchInterval();
    _currentRefetchInterval = next;

    if (!_options.enabled.resolveWith(_currentQuery) ||
        next == null ||
        next <= Duration.zero) {
      return;
    }

    _refetchTimer = Timer.periodic(next, (_) {
      // A poll normally stops while the app is backgrounded; a query that has
      // asked to keep polling there says so explicitly.
      if (_options.refetchIntervalInBackground || focusManager.isFocused) {
        _executeFetch().ignore();
      }
    });
  }

  void _clearStaleTimeout() {
    _staleTimer?.cancel();
    _staleTimer = null;
  }

  void _clearRefetchInterval() {
    _refetchTimer?.cancel();
    _refetchTimer = null;
  }

  // --- Result ---------------------------------------------------------------

  /// Recomputes the result and notifies listeners if it changed.
  void updateResult() {
    final prevResult = _currentResultOrNull;
    final nextResult = _createResult(_currentQuery, _options);

    _currentResultState = _currentQuery.state;

    // Field-wise equality is the whole rebuild-suppression story (D5): a poll
    // that returns identical data must not repaint anything.
    if (prevResult != null && nextResult == prevResult) {
      return;
    }

    _currentResult = nextResult;
    _currentResultOrNull = nextResult;

    _notify();
  }

  void _notify() {
    notifyManager.batch(() {
      // Copy: a listener may unsubscribe while being notified.
      for (final listener in List.of(_listeners)) {
        listener(_currentResult);
      }
      _client.queryCache.notify(QueryObserverResultsUpdated(_currentQuery));
    });
  }

  QueryResult<TData> _createResult(
    Query<TQueryData> query,
    DefaultedQueryObserverOptions<TQueryData, TData> options,
  ) {
    final prevResultState = _currentResultState;
    final queryInitialState = identical(query, _currentQueryOrNull)
        ? _currentQueryInitialState
        : query.state;

    final state = query.state;
    var status = state.status;
    var error = state.error;
    var errorStackTrace = state.errorStackTrace;
    var errorUpdatedAt = state.errorUpdatedAt;

    final selected = _select(state, prevResultState, options);

    // A select that threw turns a successful query into a failed one for this
    // observer only — the cache entry itself is fine, and another observer
    // selecting differently still sees success.
    final selectError = _selectError;
    if (selectError != null) {
      error = selectError;
      errorStackTrace = _selectErrorStackTrace;
      errorUpdatedAt = clock.now();
      status = QueryStatus.error;
    }

    final isFetchedAfterMount =
        state.dataUpdateCount > queryInitialState.dataUpdateCount ||
            state.errorUpdateCount > queryInitialState.errorUpdateCount;

    if (status == QueryStatus.error && error != null) {
      return QueryError<TData>(
        error: error,
        stackTrace: errorStackTrace,
        hasStaleData: selected != null,
        staleData: selected?.value,
        fetchStatus: state.fetchStatus,
        dataUpdatedAt: state.dataUpdatedAt,
        errorUpdatedAt: errorUpdatedAt,
        failureCount: state.fetchFailureCount,
        failureReason: state.fetchFailureReason,
        failureStackTrace: state.fetchFailureStackTrace,
        errorUpdateCount: state.errorUpdateCount,
        isStale: _isStale(query, options),
        isEnabled: options.enabled.resolveWith(query),
        isFetched: query.isFetched(),
        isFetchedAfterMount: isFetchedAfterMount,
        refetch: refetch,
      );
    }

    if (status == QueryStatus.success && selected != null) {
      return QuerySuccess<TData>(
        data: selected.value,
        fetchStatus: state.fetchStatus,
        dataUpdatedAt: state.dataUpdatedAt,
        errorUpdatedAt: errorUpdatedAt,
        failureCount: state.fetchFailureCount,
        failureReason: state.fetchFailureReason,
        failureStackTrace: state.fetchFailureStackTrace,
        errorUpdateCount: state.errorUpdateCount,
        isStale: _isStale(query, options),
        isEnabled: options.enabled.resolveWith(query),
        isFetched: query.isFetched(),
        isFetchedAfterMount: isFetchedAfterMount,
        refetch: refetch,
      );
    }

    return QueryPending<TData>(
      fetchStatus: state.fetchStatus,
      dataUpdatedAt: state.dataUpdatedAt,
      errorUpdatedAt: errorUpdatedAt,
      failureCount: state.fetchFailureCount,
      failureReason: state.fetchFailureReason,
      failureStackTrace: state.fetchFailureStackTrace,
      errorUpdateCount: state.errorUpdateCount,
      isStale: _isStale(query, options),
      isEnabled: options.enabled.resolveWith(query),
      isFetched: query.isFetched(),
      isFetchedAfterMount: isFetchedAfterMount,
      refetch: refetch,
    );
  }

  /// Applies `select`, reusing the previous result when the inputs have not
  /// changed.
  ///
  /// The memoization matters for rebuild suppression: a select returning a
  /// fresh object every call would make every result unequal to the last, so a
  /// background refetch of unchanged data would still repaint.
  _Box<TData>? _select(
    QueryState<TQueryData> state,
    QueryState<TQueryData>? prevResultState,
    DefaultedQueryObserverOptions<TQueryData, TData> options,
  ) {
    if (!state.hasData) {
      // The stored error belongs to data that is now gone (a reset, or a
      // switch to another key); it must not leak into this result.
      _selectError = null;
      _selectErrorStackTrace = null;
      return null;
    }

    final raw = state.data as TQueryData;
    final select = options.select;

    if (select == null) {
      // Without a select the observer exposes what the cache holds, so the two
      // type parameters are the same type. They can only differ if a caller
      // named a TData with no select to produce it, which fails loudly here.
      return _Box<TData>(raw as TData);
    }

    final memoized = _selectResult;
    if (memoized != null &&
        prevResultState != null &&
        prevResultState.hasData &&
        identical(raw, prevResultState.data) &&
        identical(select, _selectFn)) {
      return memoized;
    }

    try {
      _selectFn = select;
      final next = _Box<TData>(select(raw));
      _selectResult = next;
      _selectError = null;
      _selectErrorStackTrace = null;
      return next;
    } catch (error, stackTrace) {
      _selectError = error;
      _selectErrorStackTrace = stackTrace;
      // Keep whatever was selected last, so the error can be shown next to it.
      return _selectResult;
    }
  }

  // --- QueryObserverRef -----------------------------------------------------

  @override
  Enabled get enabledOption => _options.enabled;

  @override
  StaleDuration get staleTimeOption => _options.staleTime;

  @override
  DefaultedQueryOptions<Object?> get queryOptions => _options;

  @override
  bool get isResultStale => _currentResult.isStale;

  @override
  void onQueryUpdate() {
    updateResult();
    if (hasListeners) {
      _updateTimers();
    }
  }

  @override
  bool shouldFetchOnAppFocus() =>
      _shouldFetchOn(_currentQuery, _options, _options.refetchOnAppFocus);

  @override
  bool shouldFetchOnReconnect() =>
      _shouldFetchOn(_currentQuery, _options, _options.refetchOnReconnect);

  @override
  void refetchQuietly() {
    // cancelRefetch: false — a focus or reconnect must not restart a fetch
    // that is already in flight.
    refetch(cancelRefetch: false).ignore();
  }
}

/// Whether a query with nothing to show should load when first observed.
bool _shouldLoadOnMount<TQueryData, TData>(
  Query<TQueryData> query,
  DefaultedQueryObserverOptions<TQueryData, TData> options,
) {
  return options.enabled.resolveWith(query) &&
      !query.state.hasData &&
      // A query that already failed does not retry on mount unless asked to,
      // so a failing endpoint is not re-hit by every new widget.
      !(query.state.status == QueryStatus.error &&
          !options.retryOnMount.resolveWith(query));
}

bool _shouldFetchOnMount<TQueryData, TData>(
  Query<TQueryData> query,
  DefaultedQueryObserverOptions<TQueryData, TData> options,
) {
  return _shouldLoadOnMount(query, options) ||
      (query.state.hasData &&
          _shouldFetchOn(query, options, options.refetchOnMount));
}

/// The shared rule behind the three refetch triggers (mount, focus, reconnect).
bool _shouldFetchOn<TQueryData, TData>(
  Query<TQueryData> query,
  DefaultedQueryObserverOptions<TQueryData, TData> options,
  RefetchOn field,
) {
  if (!options.enabled.resolveWith(query) ||
      options.staleTime.resolveWith(query) is StaleDurationStatic) {
    return false;
  }
  final value = field.resolveWith(query);
  return value is RefetchOnAlways ||
      (value is! RefetchOnNever && _isStale(query, options));
}

/// Whether an options change should trigger a fetch on an already-mounted
/// observer — a new key, or one that was disabled and just became enabled.
bool _shouldFetchOptionally<TQueryData, TData>(
  Query<TQueryData> query,
  Query<TQueryData> prevQuery,
  DefaultedQueryObserverOptions<TQueryData, TData> options,
  DefaultedQueryObserverOptions<TQueryData, TData> prevOptions,
) {
  return (!identical(query, prevQuery) ||
          !prevOptions.enabled.resolveWith(query)) &&
      _isStale(query, options);
}

bool _isStale<TQueryData, TData>(
  Query<TQueryData> query,
  DefaultedQueryObserverOptions<TQueryData, TData> options,
) {
  // A disabled query is never stale: staleness is a reason to refetch, and a
  // disabled query will not.
  return options.enabled.resolveWith(query) &&
      query.isStaleByTime(options.staleTime);
}
