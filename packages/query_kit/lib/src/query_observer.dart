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
import 'structural_sharing.dart';
import 'timers.dart';

/// What a [QueryObserver.subscribe] listener receives: the new
/// [QueryResult], each time it changes.
typedef QueryObserverListener<TData> = void Function(QueryResult<TData> result);

/// Watches one query and turns its state into a [QueryResult].
///
/// Two type parameters, not upstream's five: what the cache holds
/// ([TQueryData]) and what the consumer sees after `select` ([TData]).
/// See https://github.com/KoTTi97/flutter_query/issues/7. Takes either
/// options shape — a `QueryObserverOptions<T>` makes a `QueryObserver<T, T>`,
/// a `QuerySelectOptions<TQueryData, TData>` a `QueryObserver<TQueryData,
/// TData>` — through their sealed base (ADR-0001).
class QueryObserver<TQueryData, TData> implements QueryObserverRef {
  /// Creates an observer for [options], resolved against the client's
  /// defaults, and builds — or joins — the query for its key. No fetch happens
  /// until the first [subscribe]; [currentResult] is readable at once.
  QueryObserver(
    this._client,
    QueryObserverOptionsBase<TQueryData, TData> options,
  ) {
    _checkDataType(options);
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
  final List<QueryObserverListener<TData>> _listeners =
      <QueryObserverListener<TData>>[];

  /// Whether anyone is subscribed — upstream's "mounted". Fetch-on-mount, the
  /// stale timer and the polling timer only run while this is true.
  bool get hasListeners => _listeners.isNotEmpty;

  /// Registers [listener] and returns the function that removes it again.
  ///
  /// Each handle removes its own registration, once: called twice it removes
  /// nothing more, as `Subscribable`'s handles already promised. Unguarded,
  /// a second call took another registration of the same listener with it
  /// and ran the last-listener teardown under a subscriber still present
  /// (ninth review, 2026-09-10, C6).
  void Function() subscribe(QueryObserverListener<TData> listener) {
    _listeners.add(listener);
    _onSubscribe();
    var removed = false;
    return () {
      if (removed) {
        return;
      }
      removed = true;
      _listeners.remove(listener);
      _onUnsubscribe();
    };
  }

  late DefaultedQueryObserverOptions<TQueryData, TData> _options;

  /// The options in force, fully resolved against the client's defaults.
  DefaultedQueryObserverOptions<TQueryData, TData> get options => _options;

  // Null only between construction and the first `_updateQuery`.
  Query<TQueryData>? _query;
  Query<TQueryData> get _currentQuery => _query!;
  late QueryState<TQueryData> _currentQueryInitialState;
  late QueryResult<TData> _currentResult;
  QueryResult<TData>? _previousResult;
  QueryState<TQueryData>? _currentResultState;
  DefaultedQueryObserverOptions<TQueryData, TData>? _currentResultOptions;

  Object? _selectError;
  StackTrace? _selectErrorStackTrace;
  // Captured when the selector throws, not per result: a standing select
  // error read at `clock.now()` on every `createResult` made two results
  // computed a millisecond apart unequal, and every `setOptions` a
  // notification — through the binding, a rebuild loop (fourth review,
  // 2026-09-09). Upstream reads `Date.now()` there too, but its render
  // tracking hides the churn; this port has no such filter.
  DateTime? _selectErrorUpdatedAt;
  TData Function(TQueryData data)? _selectFn;
  TData? _selectResult;
  bool _hasSelectResult = false;

  Query<TQueryData>? _lastQueryWithData;

  Timer? _staleTimer;
  Timer? _refetchTimer;
  Duration? _currentRefetchInterval;

  /// The most recently computed result.
  QueryResult<TData> get currentResult => _currentResult;

  /// The cache entry this observer is watching right now. Changes when
  /// [setOptions] is given a different key, or when the previous entry was
  /// collected while nobody was listening.
  Query<TQueryData> get currentQuery => _currentQuery;

  void _onSubscribe() {
    if (_listeners.length == 1) {
      // Re-resolve the query first. The one this observer last watched may
      // have been collected while nobody was listening, and a fresh entry
      // may already stand in its place; upstream only re-resolves on
      // `setOptions` and on a fetch, so an infinitely fresh query would
      // rejoin its dead predecessor. A binding that reuses a controller
      // across subscriptions hits exactly that.
      _updateQuery();
      _currentQuery.addObserver(this);

      if (_shouldFetchOnMount(_currentQuery, _options)) {
        executeFetch();
        // A fetch that joined one already running dispatched nothing, and
        // then nothing recomputed the result — while a binding reads
        // `currentResult` right after subscribing. Brought up to date only
        // when the dispatch did not already do it: every state change is a
        // new `QueryState`, and running `createResult` again would call a
        // placeholder callback one more time than upstream does (the ported
        // suite counts those calls).
        if (!identical(_currentResultState, _currentQuery.state)) {
          updateResult();
        }
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
    _listeners.clear();
    _clearStaleTimeout();
    _clearRefetchInterval();
    _currentQuery.removeObserver(this);
  }

  /// Replaces the options, switching queries if the key changed.
  ///
  /// Throws an [ArgumentError] before touching anything if the options have
  /// no `select` and [TQueryData] is not a [TData] — see [QueryObserver.new].
  void setOptions(QueryObserverOptionsBase<TQueryData, TData> options) {
    _checkDataType(options);
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

    // Compared once resolved, as upstream compares `resolveQueryValue`s: an
    // `Enabled.when` or `StaleTime.dynamic` built inline is a new closure on
    // every build, and comparing the wrappers would restart the timers — the
    // polling one included — on every rebuild, so a widget rebuilding faster
    // than its interval would never poll (third review, 2026-09-09).
    final queryChanged = !identical(_currentQuery, prevQuery);
    final enabledChanged = _options.enabled.resolve(_currentQuery) !=
        prevOptions.enabled.resolve(_currentQuery);

    if (mounted &&
        (queryChanged ||
            enabledChanged ||
            _options.staleTime.resolveFor(_currentQuery) !=
                prevOptions.staleTime.resolveFor(_currentQuery))) {
      _updateStaleTimeout();
    }

    final nextRefetchInterval = _computeRefetchInterval();

    if (mounted &&
        (queryChanged ||
            enabledChanged ||
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
    QueryObserverOptionsBase<TQueryData, TData> options,
  ) {
    _checkDataType(options);
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

  /// Defaults to false, as upstream's unset `cancelRefetch` does: only an
  /// explicit `refetch()` cancels a fetch that is already running.
  ///
  /// [meta] rides along into `QueryState.fetchMeta`; infinite queries put the
  /// page direction there.
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

  /// An observer with no `select` reports the query's data as its own, so
  /// every [TQueryData] must be a [TData]. Checked here, on the way in, and
  /// not only in `createResult`: there it was an `assert`, and the assertion
  /// fired inside `Query._dispatch` during the *fetch* — the `AssertionError`
  /// became the shared query's error state, this observer stayed pending, and
  /// a correctly typed observer on the same key saw the query in error (fifth
  /// review, 2026-09-09). A subtype test rather than exact equality, because
  /// `QueryObserver<int, num>` without a `select` is sound and
  /// `QueryObserver<int, String>` is not; on every platform the reified
  /// `List<TQueryData>` is a `List<TData>` exactly when that holds.
  static void _checkDataType<TQueryData, TData>(
    QueryObserverOptionsBase<TQueryData, TData> options,
  ) {
    if (options.select == null && <TQueryData>[] is! List<TData>) {
      throw ArgumentError.value(
        options,
        'options',
        'A QueryObserver<$TQueryData, $TData> with no select cannot report '
            '$TQueryData as $TData. Give it a select, or make the two types '
            'the same.',
      );
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

    final deadline = updatedAt.add(staleTime!);
    // Rounded up to the millisecond a `Timer` is armed in, and clamped to
    // what a web timer can take. Either way the timer can run before the
    // deadline — a microsecond remainder truncated, or a 30-day stale time
    // cut to 24.8 days — and the callback then finds the data still fresh.
    // It used to stop there, and `isStale` never flipped by timer; upstream
    // adds a millisecond for the truncation and has no clamp. The deadline is
    // the truth: still fresh means "arm again for what is left" (fifth
    // review, 2026-09-09).
    _staleTimer = Timer(
        clampTimerDuration(
            ceilToMilliseconds(deadline.difference(clock.now()))), () {
      if (_currentResult.isStale) {
        return;
      }
      if (_isStale(_currentQuery, _options)) {
        updateResult();
      } else {
        _updateStaleTimeout();
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

    _refetchTimer = Timer.periodic(clampTimerDuration(nextInterval), (_) {
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
          identical(placeholderData, prevResultOptions?.placeholderData) &&
          options.select == prevResultOptions?.select) {
        // Already selected on the previous pass, so `select` must not run
        // again over an already-selected value. Only while `select` is the
        // same one, though — upstream memoises on the placeholder alone and
        // keeps showing the old selection after the selector changed.
        outData = prevResult.dataOrNull;
        hasOutData = true;
        skipSelect = true;
        status = QueryStatus.success;
        isPlaceholderData = true;
      } else {
        final placeholder = placeholderData.provide(
          _lastQueryWithData?.state.data,
          _lastQueryWithData,
        );
        if (placeholder.hasData) {
          status = QueryStatus.success;
          isPlaceholderData = true;
          candidate = placeholder.data;
          hasCandidate = true;
        }
      }
    }

    if (!skipSelect) {
      final select = options.select;
      if (select != null && hasCandidate) {
        // The selector is compared with `==`, as the options compare it: an
        // instance-method tear-off is `==` to the next tear-off of the same
        // method but never `identical`, so an `identical` memo re-ran such a
        // `select` on every `setOptions` that changed nothing (ninth review,
        // 2026-09-10, C14). A closure is only ever `==` to itself.
        if (prevResult != null &&
            prevResultState != null &&
            prevResultState.hasData &&
            candidate == prevResultState.data &&
            select == _selectFn) {
          outData = _selectResult;
          hasOutData = _hasSelectResult;
        } else {
          try {
            _selectFn = select;
            // Shared against the last *reported* data, as upstream's
            // `replaceData(prevResult?.data, …)`: a selector that builds a
            // fresh but equal list must not count as a change.
            outData = replaceEqualDeep<TData>(
              prevResult?.dataOrNull,
              select(candidate as TQueryData),
            );
            _selectResult = outData;
            _hasSelectResult = true;
            hasOutData = true;
            _clearSelectError();
          } catch (selectError, selectStackTrace) {
            _selectError = selectError;
            _selectErrorStackTrace = selectStackTrace;
            _selectErrorUpdatedAt = clock.now();
          }
        }
      } else if (select == null && hasCandidate) {
        assert(
          candidate is TData,
          'A query observer with no select must have the same data type on '
          'both sides: $TQueryData cannot be reported as $TData.',
        );
        if (isPlaceholderData) {
          // A placeholder was never written to the cache, so it is shared
          // here — through the query's own hook, as upstream's
          // `replaceData(prevResult?.data, placeholderData, options)`.
          final sharing = options.structuralSharing;
          final previous = prevResult?.dataOrNull as TQueryData?;
          outData = (sharing == null
              ? replaceEqualDeep<TQueryData>(previous, candidate as TQueryData)
              : sharing(previous, candidate as TQueryData)) as TData;
        } else {
          // Cached data goes through as it is, as upstream's `data =
          // state.data`: the cache write already applied `structuralSharing`,
          // and re-sharing it against the last result here hid an opt-out
          // (`(_, next) => next`) from every reader — the showcase's
          // select-and-sharing screen found it (2026-09-09).
          outData = candidate as TData;
        }
        hasOutData = true;
        // The error belonged to a selector that is no longer there. Upstream
        // keeps reporting it until a *new* selection succeeds, which never
        // happens once `select` is gone.
        _clearSelectError();
      } else if (!hasCandidate) {
        // A select error belongs to data that is now gone.
        _clearSelectError();
      }
    }

    final selectError = _selectError;
    if (selectError != null) {
      error = selectError;
      errorStackTrace = _selectErrorStackTrace;
      errorUpdatedAt = _selectErrorUpdatedAt;
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

  void _clearSelectError() {
    _selectError = null;
    _selectErrorStackTrace = null;
    _selectErrorUpdatedAt = null;
  }

  /// Whether listeners hear about [next], given [previous] — the result they
  /// last heard about, `null` before the first. Here: the first result, and
  /// then every one that is not value-equal to the last. `updateResult` has
  /// already installed [next] as [currentResult] when this is asked, so a
  /// subclass can read what it derives from the result and the query;
  /// `InfiniteQueryObserver` adds its paging flags this way, which are not
  /// part of the result and used to change without a word (fifth review,
  /// 2026-09-09).
  @protected
  bool shouldNotify(QueryResult<TData>? previous, QueryResult<TData> next) =>
      previous == null || next != previous;

  /// Recomputes the result and notifies listeners if it changed — as
  /// [shouldNotify] decides.
  void updateResult() {
    final prevResult = _previousResult;
    final nextResult = createResult(_currentQuery, _options);

    _currentResultState = _currentQuery.state;
    _currentResultOptions = _options;

    if (_currentQuery.state.hasData) {
      _lastQueryWithData = _currentQuery;
    }

    _currentResult = nextResult;
    if (!shouldNotify(prevResult, nextResult)) {
      return;
    }

    _previousResult = nextResult;

    _client.notifyManager.batch(() {
      for (final listener in List.of(_listeners)) {
        // A listener's throw is the listener's problem, not the query's:
        // reaching `Query.fetch` it would be recorded as the fetch's error.
        // Reported to the zone, the way the mutation callbacks already are.
        try {
          listener(_currentResult);
        } catch (error, stackTrace) {
          Zone.current.handleUncaughtError(error, stackTrace);
        }
      }
      _client.queryCache.notifyObserverResultsUpdated(_currentQuery);
    });
  }

  void _updateQuery() {
    final query = _client.queryCache.build<TQueryData>(
      _client,
      _options.queryOptions,
    );

    final prevQuery = _query;
    if (identical(query, prevQuery)) {
      return;
    }

    _query = query;
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
