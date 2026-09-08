/// Port of `query-core/src/queryObserver.ts` at upstream `50680b98c`.
library;

import 'dart:async';

import 'package:clock/clock.dart';

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
    updateResult();
  }

  final QueryClient _client;

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
        _executeFetch();
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

    final mounted = hasListeners;

    if (mounted &&
        _shouldFetchOptionally(
            _currentQuery, prevQuery, _options, prevOptions)) {
      _executeFetch();
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
    final result = _createResult(query, defaulted, optimistic: true);

    if (result != _currentResult) {
      _currentResult = result;
      _currentResultOptions = _options;
      _currentResultState = _currentQuery.state;
    }
    return result;
  }

  /// Refetches, completing with the result the refetch produced.
  Future<QueryResult<TData>> refetch({bool cancelRefetch = true}) async {
    await _executeFetch(cancelRefetch: cancelRefetch);
    updateResult();
    return _currentResult;
  }

  Future<void> _executeFetch({bool cancelRefetch = true}) async {
    _updateQuery();
    try {
      await _currentQuery.fetch(
        options: _options.queryOptions,
        fetchOptions: FetchOptions<TQueryData>(cancelRefetch: cancelRefetch),
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
        _executeFetch().ignore();
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

  QueryResult<TData> _createResult(
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

    final queryData = state.data;
    final hasQueryData = state.hasData;

    TData? outData;
    var hasOutData = false;

    // Placeholder data, only while nothing real has resolved.
    final placeholderData = options.placeholderData;
    if (placeholderData != null &&
        !hasQueryData &&
        status == QueryStatus.pending) {
      if (prevResult != null &&
          prevResult.isPlaceholderData &&
          identical(placeholderData, prevResultOptions?.placeholderData)) {
        // Already selected on the previous pass.
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
          final select = options.select;
          if (select != null) {
            try {
              outData = select(placeholder);
              hasOutData = true;
            } catch (selectError, selectStackTrace) {
              _selectError = selectError;
              _selectErrorStackTrace = selectStackTrace;
            }
          } else {
            outData = placeholder as TData;
            hasOutData = true;
          }
          skipSelect = true;
        }
      }
    }

    if (!skipSelect) {
      final select = options.select;
      if (select != null && hasQueryData) {
        if (prevResult != null &&
            prevResultState != null &&
            prevResultState.hasData &&
            queryData == prevResultState.data &&
            identical(select, _selectFn)) {
          outData = _selectResult;
          hasOutData = true;
        } else {
          try {
            _selectFn = select;
            outData = select(queryData as TQueryData);
            _selectResult = outData;
            hasOutData = true;
            _selectError = null;
            _selectErrorStackTrace = null;
          } catch (selectError, selectStackTrace) {
            _selectError = selectError;
            _selectErrorStackTrace = selectStackTrace;
          }
        }
      } else if (select == null && hasQueryData) {
        assert(
          queryData is TData,
          'A query observer with no select must have the same data type on '
          'both sides: $TQueryData cannot be reported as $TData.',
        );
        outData = queryData as TData;
        hasOutData = true;
      } else if (!hasQueryData) {
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
    final nextResult = _createResult(_currentQuery, _options);

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
  bool get isStaticForQuery => _options.staleTime is StaleTimeStatic;

  @override
  bool get currentResultIsStale => _currentResult.isStale;

  @override
  bool shouldFetchOnWindowFocus() =>
      _shouldFetchOn(_currentQuery, _options, _options.refetchOnWindowFocus);

  @override
  bool shouldFetchOnReconnect() =>
      _shouldFetchOn(_currentQuery, _options, _options.refetchOnReconnect);

  @override
  void refetchOnEvent() => _executeFetch(cancelRefetch: false).ignore();

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
  if (options.enabled.resolve(query) && options.staleTime is! StaleTimeStatic) {
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
    options.enabled.resolve(query) &&
    query.isStaleByTime(options.staleTime.resolve(query));
