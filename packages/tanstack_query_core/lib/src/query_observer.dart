/// Port of `query-core/src/queryObserver.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

import 'option_values.dart';
import 'query.dart';
import 'query_client.dart';
import 'query_options.dart';
import 'query_result.dart';
import 'query_state.dart';
import 'retryer.dart';

typedef QueryObserverListener<TData> = void Function(QueryResult<TData> result);

/// Watches one query and turns its state into a [QueryResult].
///
/// Two type parameters, not upstream's five: what the cache holds
/// ([TQueryData]) and what the consumer sees after `select` ([TData]).
/// See https://github.com/KoTTi97/flutter_query/issues/7.
class QueryObserver<TQueryData, TData> implements QueryObserverRef {
  QueryObserver(
    this._client,
    QueryObserverOptions<TQueryData, TData> options,
  ) {
    _options = _client.defaultQueryObserverOptions<TQueryData, TData>(options);
    _updateQuery();
    // The query takes the observer's options even when it already existed:
    // this is how a late `initialData` seeds a query created by a bare
    // prefetch, and how `gcTime` grows to the longest anyone asked for.
    _currentQuery.setOptions(_options.queryOptions);
    updateResult();
  }

  final QueryClient _client;

  /// The client this observer reads through. Infinite observers need it to
  /// re-default their options.
  @protected
  QueryClient get client => _client;

  // Observers manage their own listeners instead of extending `Subscribable`:
  // Dart has no declaration-site variance, and `Subscribable<void
  // Function(QueryResult<TData>)>` puts TData in a contravariant position of a
  // superinterface, which the language forbids. Composition costs a dozen
  // lines and keeps the listener type exact.
  final List<QueryObserverListener<TData>> listeners =
      <QueryObserverListener<TData>>[];

  bool get hasListeners => listeners.isNotEmpty;

  /// Registers [listener] and returns the function that removes it again.
  void Function() subscribe(QueryObserverListener<TData> listener) {
    listeners.add(listener);
    _onSubscribe();
    return () {
      listeners.remove(listener);
      _onUnsubscribe();
    };
  }

  late DefaultedQueryObserverOptions<TQueryData, TData> _options;
  DefaultedQueryObserverOptions<TQueryData, TData> get options => _options;

  late Query<TQueryData> _currentQuery;
  late QueryState<TQueryData> _currentQueryInitialState;
  late QueryResult<TData> _currentResult;
  QueryResult<TData>? _previousResult;
  QueryState<TQueryData>? _currentResultState;
  DefaultedQueryObserverOptions<TQueryData, TData>? _currentResultOptions;

  Object? _selectError;
  StackTrace? _selectErrorStackTrace;
  TData Function(TQueryData data)? _selectFn;
  TData? _selectResult;
  bool _hasSelectResult = false;

  Query<TQueryData>? _lastQueryWithData;

  Timer? _staleTimer;
  Timer? _refetchTimer;
  Duration? _currentRefetchInterval;

  /// The most recently computed result.
  QueryResult<TData> get currentResult => _currentResult;

  Query<TQueryData> get currentQuery => _currentQuery;

  void _onSubscribe() {
    if (listeners.length == 1) {
      _currentQuery.addObserver(this);

      if (_shouldFetchOnMount(_currentQuery, _options)) {
        executeFetch();
      } else {
        updateResult();
      }

      _updateTimers();
    }
  }

  void _onUnsubscribe() {
    if (!hasListeners) {
      destroy();
    }
  }

  /// Stops observing: clears listeners and timers and leaves the query, which
  /// starts its `gcTime` clock.
  void destroy() {
    listeners.clear();
    _clearStaleTimeout();
    _clearRefetchInterval();
    _currentQuery.removeObserver(this);
  }

  /// Replaces the options, switching queries if the key changed.
  void setOptions(QueryObserverOptions<TQueryData, TData> options) {
    final prevOptions = _options;
    final prevQuery = _currentQuery;

    _options = _client.defaultQueryObserverOptions<TQueryData, TData>(options);

    _updateQuery();
    _currentQuery.setOptions(_options.queryOptions);

    if (_options != prevOptions) {
      _client.queryCache.notifyObserverOptionsUpdated(_currentQuery, this);
    }

    final mounted = hasListeners;

    if (mounted &&
        _shouldFetchOptionally(
            _currentQuery, prevQuery, _options, prevOptions)) {
      executeFetch();
    }

    updateResult();

    if (mounted &&
        (!identical(_currentQuery, prevQuery) ||
            _options.enabled != prevOptions.enabled ||
            _options.staleTime != prevOptions.staleTime)) {
      _updateStaleTimeout();
    }

    final nextRefetchInterval = _computeRefetchInterval();

    if (mounted &&
        (!identical(_currentQuery, prevQuery) ||
            _options.enabled != prevOptions.enabled ||
            nextRefetchInterval != _currentRefetchInterval)) {
      _updateRefetchInterval(nextRefetchInterval);
    }
  }

  /// The result these options would produce right now, building the query if
  /// it does not exist yet.
  ///
  /// This is the adapter contract's synchronous read: a widget's first build
  /// shows `isLoading` rather than a stale idle state
  /// (https://github.com/KoTTi97/flutter_query/issues/15).
  QueryResult<TData> getOptimisticResult(
    QueryObserverOptions<TQueryData, TData> options,
  ) {
    final defaulted = _client.defaultQueryObserverOptions<TQueryData, TData>(
      options,
    );
    final query =
        _client.queryCache.build<TQueryData>(_client, defaulted.queryOptions);
    final result = createResult(query, defaulted, optimistic: true);

    if (result != _currentResult) {
      _currentResult = result;
      _currentResultOptions = _options;
      _currentResultState = _currentQuery.state;
    }
    return result;
  }

  /// Refetches, completing with the result the refetch produced.
  Future<QueryResult<TData>> refetch({bool cancelRefetch = true}) async {
    await executeFetch(cancelRefetch: cancelRefetch);
    updateResult();
    return _currentResult;
  }

  // Defaults to false, as upstream's unset `cancelRefetch` does: only an
  // explicit `refetch()` cancels a fetch that is already running.
  //
  // [meta] rides along into `QueryState.fetchMeta`; infinite queries put the
  // page direction there.
  @protected
  Future<void> executeFetch({bool cancelRefetch = false, Object? meta}) async {
    _updateQuery();
    try {
      await _currentQuery.fetch(
        options: _options.queryOptions,
        fetchOptions: FetchOptions<TQueryData>(
          cancelRefetch: cancelRefetch,
          meta: meta,
        ),
      );
    } catch (_) {
      // The error is in the query's state; an observer never rethrows it.
    }
  }

  // ---------------------------------------------------------------- timers

  bool _shouldScheduleTimer(Duration? timeout) =>
      _options.enabled.resolve(_currentQuery) &&
      timeout != null &&
      timeout > Duration.zero;

  void _updateStaleTimeout() {
    _clearStaleTimeout();
    final staleTime = _options.staleTime.resolve(_currentQuery);

    if (_currentResult.isStale || !_shouldScheduleTimer(staleTime)) {
      return;
    }

    final updatedAt = _currentResult.dataUpdatedAt;
    if (updatedAt == null) {
      return;
    }

    final elapsed = clock.now().difference(updatedAt);
    final remaining = staleTime! - elapsed;
    // Upstream adds a millisecond because its timer can fire just before the
    // deadline; Dart's virtual and real timers do not, so the deadline is used
    // as is.
    _staleTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      if (!_currentResult.isStale) {
        updateResult();
      }
    });
  }

  Duration? _computeRefetchInterval() =>
      _options.refetchInterval.resolve(_currentQuery);

  void _updateRefetchInterval(Duration? nextInterval) {
    _clearRefetchInterval();
    _currentRefetchInterval = nextInterval;

    if (nextInterval == null ||
        nextInterval <= Duration.zero ||
        !_shouldScheduleTimer(nextInterval)) {
      return;
    }

    _refetchTimer = Timer.periodic(nextInterval, (_) {
      if (_options.refetchIntervalInBackground ||
          _client.focusManager.isFocused()) {
        executeFetch().ignore();
      }
    });
  }

  void _updateTimers() {
    _updateStaleTimeout();
    _updateRefetchInterval(_computeRefetchInterval());
  }

  void _clearStaleTimeout() {
    _staleTimer?.cancel();
    _staleTimer = null;
  }

  void _clearRefetchInterval() {
    _refetchTimer?.cancel();
    _refetchTimer = null;
  }

  // ---------------------------------------------------------------- result

  /// Turns a query's state into the result an observer reports.
  ///
  /// `@protected` rather than private so `InfiniteQueryObserver` can extend it
  /// (https://github.com/KoTTi97/flutter_query/issues/16).
  @protected
  QueryResult<TData> createResult(
    Query<TQueryData> query,
    DefaultedQueryObserverOptions<TQueryData, TData> options, {
    bool optimistic = false,
  }) {
    final prevResult = _previousResult;
    final prevResultOptions = _currentResultOptions;
    final prevResultState = _currentResultState;
    final queryChanged = !identical(query, _currentQuery);
    final queryInitialState =
        queryChanged ? query.state : _currentQueryInitialState;

    var state = query.state;

    if (optimistic) {
      final mounted = hasListeners;
      final fetchOnMount = !mounted && _shouldFetchOnMount(query, options);
      final fetchOptionally = mounted &&
          _shouldFetchOptionally(query, _currentQuery, options, _options);

      if (fetchOnMount || fetchOptionally) {
        final fetchable = canFetch(options.networkMode, _client.onlineManager);
        state = state.copyWith(
          fetchStatus: fetchable ? FetchStatus.fetching : FetchStatus.paused,
          fetchFailureCount: 0,
          clearFetchFailure: true,
          status: state.hasData ? null : QueryStatus.pending,
          clearError: !state.hasData,
        );
      }
    }

    var status = state.status;
    var error = state.error;
    var errorStackTrace = state.errorStackTrace;
    var errorUpdatedAt = state.errorUpdatedAt;
    var isPlaceholderData = false;
    var skipSelect = false;

    // What `select` will be given: the query's data, or the placeholder that
    // stands in for it. Upstream runs placeholder data through `select` too,
    // by leaving it in the same variable rather than selecting it early.
    TQueryData? candidate = state.hasData ? state.data : null;
    var hasCandidate = state.hasData;

    TData? outData;
    var hasOutData = false;

    // Placeholder data, only while nothing real has resolved.
    final placeholderData = options.placeholderData;
    if (placeholderData != null &&
        !hasCandidate &&
        status == QueryStatus.pending) {
      if (prevResult != null &&
          prevResult.isPlaceholderData &&
          identical(placeholderData, prevResultOptions?.placeholderData)) {
        // Already selected on the previous pass, so `select` must not run
        // again over an already-selected value.
        outData = prevResult.dataOrNull;
        hasOutData = true;
        skipSelect = true;
        status = QueryStatus.success;
        isPlaceholderData = true;
      } else {
        final placeholder = placeholderData.resolve(
          _lastQueryWithData?.state.data,
          _lastQueryWithData,
        );
        if (placeholder != null) {
          status = QueryStatus.success;
          isPlaceholderData = true;
          candidate = placeholder;
          hasCandidate = true;
        }
      }
    }

    if (!skipSelect) {
      final select = options.select;
      if (select != null && hasCandidate) {
        if (prevResult != null &&
            prevResultState != null &&
            prevResultState.hasData &&
            candidate == prevResultState.data &&
            identical(select, _selectFn)) {
          outData = _selectResult;
          hasOutData = _hasSelectResult;
        } else {
          try {
            _selectFn = select;
            outData = select(candidate as TQueryData);
            _selectResult = outData;
            _hasSelectResult = true;
            hasOutData = true;
            _selectError = null;
            _selectErrorStackTrace = null;
          } catch (selectError, selectStackTrace) {
            _selectError = selectError;
            _selectErrorStackTrace = selectStackTrace;
          }
        }
      } else if (select == null && hasCandidate) {
        assert(
          candidate is TData,
          'A query observer with no select must have the same data type on '
          'both sides: $TQueryData cannot be reported as $TData.',
        );
        outData = candidate as TData;
        hasOutData = true;
      } else if (!hasCandidate) {
        // A select error belongs to data that is now gone.
        _selectError = null;
        _selectErrorStackTrace = null;
      }
    }

    final selectError = _selectError;
    if (selectError != null) {
      error = selectError;
      errorStackTrace = _selectErrorStackTrace;
      errorUpdatedAt = clock.now();
      status = QueryStatus.error;
      isPlaceholderData = false;
      // The last value `select` produced stays on screen behind the error,
      // which is what makes a failing selector as survivable as a failing
      // fetch.
      outData = _selectResult;
      hasOutData = _hasSelectResult;
    }

    final isFetchedAfterMount =
        state.dataUpdateCount > queryInitialState.dataUpdateCount ||
            state.errorUpdateCount > queryInitialState.errorUpdateCount;

    QueryResult<TData> build() {
      switch (status) {
        case QueryStatus.error:
          return QueryError<TData>(
            error: error ?? StateError('query is in an error state'),
            stackTrace: errorStackTrace ?? StackTrace.empty,
            staleData: outData,
            hasStaleData: hasOutData,
            fetchStatus: state.fetchStatus,
            dataUpdatedAt: state.dataUpdatedAt,
            errorUpdatedAt: errorUpdatedAt,
            failureCount: state.fetchFailureCount,
            failureReason: state.fetchFailureReason,
            failureStackTrace: state.fetchFailureStackTrace,
            errorUpdateCount: state.errorUpdateCount,
            isStale: _isStale(query, options),
            isEnabled: options.enabled.resolve(query),
            isFetched: query.isFetched(),
            isFetchedAfterMount: isFetchedAfterMount,
            isPlaceholderData: isPlaceholderData,
            refetch: refetch,
          );
        case QueryStatus.success:
          return QuerySuccess<TData>(
            data: outData as TData,
            fetchStatus: state.fetchStatus,
            dataUpdatedAt: state.dataUpdatedAt,
            errorUpdatedAt: errorUpdatedAt,
            failureCount: state.fetchFailureCount,
            failureReason: state.fetchFailureReason,
            failureStackTrace: state.fetchFailureStackTrace,
            errorUpdateCount: state.errorUpdateCount,
            isStale: _isStale(query, options),
            isEnabled: options.enabled.resolve(query),
            isFetched: query.isFetched(),
            isFetchedAfterMount: isFetchedAfterMount,
            isPlaceholderData: isPlaceholderData,
            refetch: refetch,
          );
        case QueryStatus.pending:
          return QueryPending<TData>(
            fetchStatus: state.fetchStatus,
            dataUpdatedAt: state.dataUpdatedAt,
            errorUpdatedAt: errorUpdatedAt,
            failureCount: state.fetchFailureCount,
            failureReason: state.fetchFailureReason,
            failureStackTrace: state.fetchFailureStackTrace,
            errorUpdateCount: state.errorUpdateCount,
            isStale: _isStale(query, options),
            isEnabled: options.enabled.resolve(query),
            isFetched: query.isFetched(),
            isFetchedAfterMount: isFetchedAfterMount,
            isPlaceholderData: isPlaceholderData,
            refetch: refetch,
          );
      }
    }

    return build();
  }

  /// Recomputes the result and notifies listeners if it changed.
  void updateResult() {
    final prevResult = _previousResult;
    final nextResult = createResult(_currentQuery, _options);

    _currentResultState = _currentQuery.state;
    _currentResultOptions = _options;

    if (_currentQuery.state.hasData) {
      _lastQueryWithData = _currentQuery;
    }

    if (prevResult != null && nextResult == prevResult) {
      _currentResult = nextResult;
      return;
    }

    _currentResult = nextResult;
    _previousResult = nextResult;

    _client.notifyManager.batch(() {
      for (final listener in List.of(listeners)) {
        listener(_currentResult);
      }
      _client.queryCache.notifyObserverResultsUpdated(_currentQuery);
    });
  }

  void _updateQuery() {
    final query = _client.queryCache.build<TQueryData>(
      _client,
      _options.queryOptions,
    );

    Query<TQueryData>? prevQuery;
    var hadQuery = false;
    try {
      prevQuery = _currentQuery;
      hadQuery = true;
    } on Error {
      // First call: there is no current query yet.
    }

    if (hadQuery && identical(query, prevQuery)) {
      return;
    }

    _currentQuery = query;
    _currentQueryInitialState = query.state;

    if (hasListeners) {
      prevQuery?.removeObserver(this);
      query.addObserver(this);
    }
  }

  // -------------------------------------------------- QueryObserverRef

  @override
  void onQueryUpdate() {
    updateResult();
    if (hasListeners) {
      _updateTimers();
    }
  }

  @override
  bool get isEnabledForQuery => _options.enabled.resolve(_currentQuery);

  @override
  bool get isStaticForQuery => _options.staleTime.isStaticFor(_currentQuery);

  @override
  bool get currentResultIsStale => _currentResult.isStale;

  @override
  bool shouldFetchOnWindowFocus() =>
      _shouldFetchOn(_currentQuery, _options, _options.refetchOnWindowFocus);

  @override
  bool shouldFetchOnReconnect() =>
      _shouldFetchOn(_currentQuery, _options, _options.refetchOnReconnect);

  @override
  void refetchOnEvent() => executeFetch(cancelRefetch: false).ignore();

  @override
  DefaultedQueryOptions<Object?> get observerQueryOptions =>
      _options.queryOptions;
}

bool _shouldLoadOnMount(
  Query<Object?> query,
  DefaultedQueryObserverOptions<Object?, Object?> options,
) =>
    options.enabled.resolve(query) &&
    !query.state.hasData &&
    !(query.state.status == QueryStatus.error && !options.retryOnMount);

bool _shouldFetchOnMount(
  Query<Object?> query,
  DefaultedQueryObserverOptions<Object?, Object?> options,
) =>
    _shouldLoadOnMount(query, options) ||
    (query.state.hasData &&
        _shouldFetchOn(query, options, options.refetchOnMount));

bool _shouldFetchOn(
  Query<Object?> query,
  DefaultedQueryObserverOptions<Object?, Object?> options,
  RefetchOn field,
) {
  if (options.enabled.resolve(query) && !options.staleTime.isStaticFor(query)) {
    final value = field.resolve(query);
    return value is RefetchOnAlways ||
        (value is! RefetchOnNever && _isStale(query, options));
  }
  return false;
}

bool _shouldFetchOptionally(
  Query<Object?> query,
  Query<Object?> prevQuery,
  DefaultedQueryObserverOptions<Object?, Object?> options,
  DefaultedQueryObserverOptions<Object?, Object?> prevOptions,
) =>
    (!identical(query, prevQuery) || !prevOptions.enabled.resolve(query)) &&
    _isStale(query, options);

bool _isStale(
  Query<Object?> query,
  DefaultedQueryObserverOptions<Object?, Object?> options,
) =>
    options.enabled.resolve(query) && query.isStaleByTime(options.staleTime);
