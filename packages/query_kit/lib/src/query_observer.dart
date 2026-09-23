/// [QueryObserver]: one query's state turned into results for listeners.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

import 'listener_registry.dart';
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
///
/// {@category Observers}
typedef QueryObserverListener<TData> = void Function(QueryResult<TData> result);

/// Watches one query in a [QueryClient]'s cache and reports its state to
/// listeners as a [QueryResult].
///
/// An observer is what a screen, a widget or a service holds to *use* a
/// query. It finds or creates the cache entry for its options' key, fetches
/// when its options say so — on the first subscribe if there is no data or
/// the data is stale, on focus and reconnect, on a polling interval — and
/// recomputes a [QueryResult] each time the query changes, telling its
/// listeners whenever that result differs from the last one. Several
/// observers of the same key share one query and one fetch. The Flutter
/// binding's widgets and controllers are built on observers; pure Dart code
/// uses one directly.
///
/// The lifecycle:
///
/// - **Construct** with a client and options. This resolves the options
///   against the client's defaults and joins or creates the query, but does
///   not fetch. [currentResult] is readable at once.
/// - **[subscribe]** a listener. The first listener attaches the observer to
///   the query, starts a fetch if one is due, and arms the stale and polling
///   timers. `subscribe` returns the function that removes the listener.
/// - **Use** it: read [currentResult], call [refetch], or hand it new
///   options with [setOptions] — a new key moves it to another query.
/// - **Stop**: when the last listener is removed the observer detaches from
///   the query ([destroy] runs), which starts the query's `gcTime` clock.
///   Subscribing again attaches it again.
///
/// The two type parameters: [TQueryData] is what the query function returns
/// and the cache holds, and [TData] is what listeners see — the same type
/// when there is no `select`, the `select`'s return type when there is one.
/// Both are inferred from the options: a `QueryObserverOptions<T>` makes a
/// `QueryObserver<T, T>`, a `QuerySelectOptions<TQueryData, TData>` a
/// `QueryObserver<TQueryData, TData>`.
///
/// ```dart
/// final client = QueryClient();
/// final observer = QueryObserver(
///   client,
///   QueryObserverOptions<List<Task>>(
///     queryKey: QueryKey(['tasks']),
///     queryFn: (_) => api.tasks(),
///   ),
/// );
/// final unsubscribe = observer.subscribe((result) {
///   switch (result) {
///     case QueryPending():
///       print('Loading…');
///     case QuerySuccess(:final data):
///       print('${data.length} tasks');
///     case QueryError(:final error):
///       print('Failed: $error');
///   }
/// });
/// // Later, when the tasks are no longer needed:
/// unsubscribe();
/// ```
///
/// TanStack Query's `QueryObserver` has five type parameters; this one
/// keeps the two a Dart caller actually names.
///
/// {@category Observers}
class QueryObserver<TQueryData, TData> implements QueryObserverRef {
  /// Creates an observer for [options], resolved against the client's
  /// defaults, and builds — or joins — the query for its key. No fetch happens
  /// until the first [subscribe]; [currentResult] is readable at once.
  ///
  /// Throws an [ArgumentError] if the options have no `select` and a
  /// [TQueryData] is not a [TData]: without a projection the observer reports
  /// the cached data as it is, so the two types must agree.
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
    _lastSeenEnabled = _currentResult.isEnabled;
  }

  final QueryClient _client;

  /// The client this observer reads through. Infinite observers need it to
  /// re-default their options.
  @protected
  QueryClient get client => _client;

  // Observers hold a `ListenerRegistry` instead of extending `Subscribable`:
  // Dart has no declaration-site variance, and `Subscribable<void
  // Function(QueryResult<TData>)>` puts TData in a contravariant position of a
  // superinterface, which the language forbids. A field has no such rule, so
  // composition keeps the listener type exact — and the registry is the same
  // one `Subscribable` itself holds.
  final ListenerRegistry<QueryObserverListener<TData>> _listeners =
      ListenerRegistry<QueryObserverListener<TData>>();

  /// Whether anyone is subscribed (TanStack Query calls this "mounted").
  /// Fetch-on-mount, the stale timer and the polling timer only run while
  /// this is true.
  bool get hasListeners => _listeners.hasListeners;

  /// Registers [listener] and returns the function that removes it again.
  ///
  /// The listener is called with each new [QueryResult] from then on —
  /// including the ones a fetch started by this subscribe produces — but not
  /// with the result that was current before; read that from
  /// [currentResult]. A listener that throws has its error reported to the
  /// current zone; the other listeners still run. The first listener
  /// attaches the observer to its query, fetches if the options say
  /// a fetch is due (no data yet, or stale data and `refetchOnMount`), and
  /// arms the stale and polling timers. Removing the last listener detaches
  /// the observer again, as [destroy] does.
  ///
  /// Each returned function removes its own registration, and only once:
  /// calling it again does nothing, even if the same listener was added
  /// twice.
  ///
  /// The first subscribe runs user code — an `Enabled.when`, a
  /// `StaleTime.dynamic`, a `RefetchOn.when`, a `RefetchInterval.dynamic`, a
  /// `PlaceholderData.compute` — and a throw there propagates to the caller.
  /// It leaves nothing behind: the listener is removed and the observer
  /// detached again before the error leaves, as if the subscribe had never
  /// happened. (TanStack Query keeps the listener registered in that case.)
  void Function() subscribe(QueryObserverListener<TData> listener) {
    final remove = _listeners.add(listener, onRemoved: _onUnsubscribe);
    try {
      _onSubscribe();
    } catch (_) {
      // The handle is the rollback: for a last listener it runs `destroy`,
      // which detaches from the query and clears any timer already armed.
      remove();
      rethrow;
    }
    return remove;
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
  // notification — through the binding, a rebuild loop. Upstream reads `Date.now()` there too, but its render
  // tracking hides the churn; this package has no such filter.
  DateTime? _selectErrorUpdatedAt;
  TData Function(TQueryData data)? _selectFn;
  TData? _selectResult;
  bool _hasSelectResult = false;
  TQueryData? _selectInput;
  bool _hasSelectInput = false;
  // The query the memoised selection was last reported for. A retained
  // `_selectResult` is what a throwing `select` shows as `staleData`, and
  // that is only stale data of *this* query if this query once reported it:
  // after a key change the previous key's selection was labelled the new
  // key's `isRefetchError`. Upstream keeps `#selectResult`
  // across `#updateQuery` and has the same leak.
  Query<TQueryData>? _selectQuery;
  int _resultRevision = 0;
  int _lifetime = 0;
  _SelectionSnapshot<TQueryData, TData>? _previewSelection;

  _SelectionSnapshot<TQueryData, TData> _captureSelection() => (
        error: _selectError,
        stackTrace: _selectErrorStackTrace,
        updatedAt: _selectErrorUpdatedAt,
        select: _selectFn,
        result: _selectResult,
        hasResult: _hasSelectResult,
        input: _selectInput,
        hasInput: _hasSelectInput,
        query: _selectQuery,
      );

  void _restoreSelection(_SelectionSnapshot<TQueryData, TData> snapshot) {
    _selectError = snapshot.error;
    _selectErrorStackTrace = snapshot.stackTrace;
    _selectErrorUpdatedAt = snapshot.updatedAt;
    _selectFn = snapshot.select;
    _selectResult = snapshot.result;
    _hasSelectResult = snapshot.hasResult;
    _selectInput = snapshot.input;
    _hasSelectInput = snapshot.hasInput;
    _selectQuery = snapshot.query;
  }

  Query<TQueryData>? _lastQueryWithData;

  Timer? _staleTimer;
  Timer? _refetchTimer;
  Duration? _currentRefetchInterval;
  // The resolved stale time the stale timer was last armed for — the
  // `_currentRefetchInterval` of the stale timer.
  StaleTime? _armedStaleTime;

  // What `enabled` came to when this observer last committed options or
  // subscribed: [setOptions]' and the preview's "was it enabled?". Not the
  // last result's `isEnabled`, which a query update or a preview recomputes
  // against the new world.
  late bool _lastSeenEnabled;

  /// The result as of now — the last one computed, which is also the last
  /// one listeners were told about unless [getOptimisticResult] has replaced
  /// it since.
  ///
  /// Readable right after construction, before any subscribe; it is then
  /// the query's state as the options see it (typically [QueryPending] for a
  /// query that has never been fetched). Read it after [subscribe] to get the
  /// value the listener will not be called with.
  QueryResult<TData> get currentResult => _currentResult;

  /// The cache entry this observer is watching right now. Changes when
  /// [setOptions] is given a different key, or when the previous entry was
  /// collected while nobody was listening.
  Query<TQueryData> get currentQuery => _currentQuery;

  void _onSubscribe() {
    if (_listeners.length == 1) {
      final lifetime = _lifetime;
      // Re-resolve the query first. The one this observer last watched may
      // have been collected while nobody was listening, and a fresh entry
      // may already stand in its place; upstream only re-resolves on
      // `setOptions` and on a fetch, so an infinitely fresh query would
      // rejoin its dead predecessor. A binding that reuses a controller
      // across subscriptions hits exactly that.
      _updateQuery();
      if (!hasListeners || lifetime != _lifetime) return;
      _currentQuery.addObserver(this);
      if (!hasListeners || lifetime != _lifetime) return;

      final fetchOnMount = _options.shouldFetchOnMount(_currentQuery);
      if (!hasListeners || lifetime != _lifetime) return;
      if (fetchOnMount) {
        // `shouldFetchOnMount` is false for a disabled observer.
        _lastSeenEnabled = true;
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
        _lastSeenEnabled = _currentResult.isEnabled;
      }

      if (hasListeners && lifetime == _lifetime) _updateTimers();
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
    _lifetime++;
    _resultRevision++;
    _listeners.clear();
    _clearStaleTimeout();
    _clearRefetchInterval();
    _currentQuery.removeObserver(this);
  }

  /// Replaces the options, switching queries if the key changed.
  ///
  /// Call it whenever the inputs to the options change — a new id in the
  /// key, a flipped `enabled`. Handing it options equal to the current ones
  /// is cheap and notifies nobody. While subscribed, it fetches when the
  /// observer moved to a query whose data is stale or missing, or when
  /// `enabled` went from false to true over stale data, and it re-arms the
  /// stale and polling timers when what they depend on changed. Listeners
  /// hear about the new result if it differs from the last.
  ///
  /// `enabled` is compared with what it came to the last time this observer
  /// applied options, not with the previous options evaluated again now, so
  /// an `Enabled.when` over state outside the cache takes effect on the next
  /// `setOptions` after that state changed.
  ///
  /// Throws an [ArgumentError] before touching anything if the options have
  /// no `select` and [TQueryData] is not a [TData] — see [QueryObserver.new].
  /// A throwing `InitialData.compute` for the new query propagates, and the
  /// observer stays on the options and the query it had.
  void setOptions(QueryObserverOptionsBase<TQueryData, TData> options) {
    _checkDataType(options);
    final prevOptions = _options;
    final prevQuery = _currentQuery;
    // What `enabled` came to the last time this observer committed options,
    // not what the previous options come to *now*. Upstream resolves old and
    // new at the same instant, so a predicate over state outside the cache —
    // "a write is in flight", a connection flag — never reads as changed:
    // both sides see the same world, and polling paused that way never
    // resumed. Against what the observer last saw,
    // handing it its options again — which every rebuild does — is a
    // re-evaluation. A dedicated field, not the last result's `isEnabled`:
    // a preview and every query update recompute that result with the *new*
    // world, and either one between the flip and the rebuild swallowed the
    // fetch.
    final wasEnabled = _lastSeenEnabled;

    final nextOptions =
        _client.defaultQueryObserverOptions<TQueryData, TData>(options);
    // Resolve the candidate before committing options, so a rejected key/type
    // transition leaves the previous observer usable.
    final nextQuery =
        _client.queryCache.build<TQueryData>(_client, nextOptions.queryOptions);
    // `InitialData.compute` is user code, and an existing query with no data
    // runs it here. Its throw is the caller's — and it comes before
    // the switch, so the observer is still on the options and the query it
    // had, and the previous query's fetch still has its observer: switching
    // first detached it, which cancelled and reverted that fetch before the
    // rollback could re-attach.
    //
    // The options, though, are committed before the seed, as upstream
    // assigns `this.options` before `setOptions`: with the key unchanged the
    // seed's update reaches this observer, and it has to compute its result
    // with the new `select`, not run the old one and notify with that.
    // Only `_options` is rolled back on a throw — nothing has
    // switched yet.
    _options = nextOptions;
    try {
      nextQuery.setOptions(nextOptions.queryOptions);
    } catch (_) {
      _options = prevOptions;
      rethrow;
    }
    _updateQuery(nextQuery);

    if (_options != prevOptions) {
      _client.queryCache.notifyObserverOptionsUpdated(_currentQuery, this);
    }

    final mounted = hasListeners;

    if (mounted &&
        _options.shouldFetchOptionally(_currentQuery, prevQuery, prevOptions,
            wasEnabled: wasEnabled)) {
      executeFetch();
    }

    updateResult();
    _lastSeenEnabled = _currentResult.isEnabled;

    // Compared once resolved, as upstream compares `resolveQueryValue`s: an
    // `Enabled.when` or `StaleTime.dynamic` built inline is a new closure on
    // every build, and comparing the wrappers would restart the timers — the
    // polling one included — on every rebuild, so a widget rebuilding faster
    // than its interval would never poll.
    final queryChanged = !identical(_currentQuery, prevQuery);
    final enabledChanged = queryChanged
        ? _options.enabled.resolve(_currentQuery) !=
            prevOptions.enabled.resolve(_currentQuery)
        : _options.enabled.resolve(_currentQuery) != wasEnabled;

    // The stale time, like the interval below, is compared with the one the
    // timer was last armed for, not with the previous options resolved now:
    // a `StaleTime.dynamic` over outside state reads the same world on both
    // sides and never differed, so a stale time shortened by outside state
    // was never armed and `isStale` stayed false.
    if (mounted &&
        (queryChanged ||
            enabledChanged ||
            _options.staleTime.resolveFor(_currentQuery) != _armedStaleTime)) {
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
  /// The result already accounts for the fetch that subscribing (or
  /// [setOptions], if subscribed) is about to start: it reports
  /// `isFetching` — or `isLoading` for a query with no data — rather than an
  /// idle state that the next frame would contradict. That is what makes it
  /// the right read for a UI's first build, before the subscription exists.
  /// It fetches nothing and does not apply the options; it does become
  /// [currentResult] until the next real update.
  QueryResult<TData> getOptimisticResult(
    QueryObserverOptionsBase<TQueryData, TData> options,
  ) {
    _checkDataType(options);
    final defaulted = _client.defaultQueryObserverOptions<TQueryData, TData>(
      options,
    );
    final query =
        _client.queryCache.build<TQueryData>(_client, defaulted.queryOptions);
    final committedSelection = _captureSelection();
    final previewSelection = _previewSelection;
    if (previewSelection != null) _restoreSelection(previewSelection);
    final QueryResult<TData> result;
    try {
      result = createResult(query, defaulted, optimistic: true);
    } finally {
      _previewSelection = _captureSelection();
      _restoreSelection(committedSelection);
    }

    if (result != _currentResult) {
      _currentResult = result;
      // The previous committed result retains its own state/options. Selection
      // memoization separately records the input used by this preview.
    }
    return result;
  }

  /// Fetches the query again, whether or not its data is stale, and
  /// completes with the [currentResult] after the fetch settled.
  ///
  /// With [cancelRefetch] `true` (the default), a fetch that is already
  /// running for a query that has data is cancelled and replaced by this
  /// one; with `false`, this call joins the running fetch instead. A query
  /// with no data always joins. The returned future never completes with an
  /// error: a failed fetch completes with a [QueryError] result. The
  /// query's `enabled` is not consulted — an explicit refetch runs on a
  /// disabled query too.
  Future<QueryResult<TData>> refetch({bool cancelRefetch = true}) async {
    await executeFetch(cancelRefetch: cancelRefetch);
    updateResult();
    return _currentResult;
  }

  /// Runs the query's fetch with this observer's options; the error, if
  /// any, lands in the query's state and is never rethrown.
  ///
  /// [cancelRefetch] defaults to false: only an explicit [refetch] cancels
  /// a fetch that is already running.
  ///
  /// [meta] rides along into `QueryState.fetchMeta`; infinite queries put the
  /// page direction there.
  @protected
  Future<void> executeFetch({bool cancelRefetch = false, Object? meta}) async {
    _updateQuery();
    try {
      await _currentQuery.fetch(
        options: _options.queryOptions,
        fetchOptions: FetchOptions(
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
  /// a correctly typed observer on the same key saw the query in error. A
  /// subtype test rather than exact equality, because
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
      timeout > Duration.zero &&
      hasListeners;

  void _updateStaleTimeout() {
    _clearStaleTimeout();
    final resolved = _options.staleTime.resolveFor(_currentQuery);
    _armedStaleTime = resolved;
    final staleTime = resolved is StaleTimeDuration ? resolved.duration : null;

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
    // the truth: still fresh means "arm again for what is left".
    _staleTimer = Timer(
        clampTimerDuration(
            ceilToMilliseconds(deadline.difference(clock.now()))), () {
      if (_currentResult.isStale) {
        return;
      }
      if (_options.isStaleFor(_currentQuery)) {
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
      if (!hasListeners) return;
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

  /// Turns [query]'s state into the result this observer reports under
  /// [options]: applies placeholder data while the query has none, runs
  /// `select` (memoised on its input and the selector), turns a throwing
  /// `select` into a [QueryError] that keeps the last selected value as its
  /// stale data, and fills in the derived flags such as `isStale`.
  ///
  /// With [optimistic], the state is first adjusted for the fetch that a
  /// subscribe or [setOptions] is about to start — see
  /// [getOptimisticResult].
  ///
  /// Only for subclasses: `InfiniteQueryObserver` extends this observer.
  /// Callers read [currentResult] instead.
  @protected
  QueryResult<TData> createResult(
    Query<TQueryData> query,
    DefaultedQueryObserverOptions<TQueryData, TData> options, {
    bool optimistic = false,
  }) {
    final prevResult = _previousResult;
    final prevResultOptions = _currentResultOptions;
    final queryChanged = !identical(query, _currentQuery);
    final queryInitialState =
        queryChanged ? query.state : _currentQueryInitialState;

    var state = query.state;

    if (optimistic) {
      final mounted = hasListeners;
      final fetchOnMount = !mounted && options.shouldFetchOnMount(query);
      // The same "was it enabled?" [setOptions] is about to ask, so the
      // preview shows the fetch the commit starts.
      final fetchOptionally = mounted &&
          options.shouldFetchOptionally(query, _currentQuery, _options,
              wasEnabled: _lastSeenEnabled);

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
        // `select` on every `setOptions` that changed nothing. A closure is only ever `==` to itself.
        if (_hasSelectInput &&
            candidate == _selectInput &&
            select == _selectFn) {
          outData = _selectResult;
          hasOutData = _hasSelectResult;
          // Equal input through the same selector is this query's selection
          // too, whichever query first produced it — unless the input is a
          // placeholder, which is no query's data: a selection of it stands
          // behind nobody's select error.
          _selectQuery = isPlaceholderData ? null : query;
        } else {
          if (!identical(query, _selectQuery)) {
            // The last selection belongs to another query. It must not stand
            // behind this query's select error as its stale data.
            _selectResult = null;
            _hasSelectResult = false;
            _selectQuery = query;
          }
          try {
            _selectFn = select;
            _selectInput = candidate;
            _hasSelectInput = true;
            // Shared against the last *reported* data, as upstream's
            // `replaceData(prevResult?.data, …)`: a selector that builds a
            // fresh but equal list must not count as a change.
            //
            // `replaceData` routes the `structuralSharing` option, so an
            // opt-out governs the selected value too. Upstream calls the hook
            // itself on the selected values; here it is typed for the query's
            // data (`StructuralSharing<TQueryData>`) and cannot be handed a
            // `TData`. So only the recognised opt-out steps back from the
            // selection — a hook that shares in its own way leaves the
            // selection at the default walk, rather than paying for an
            // opt-out it never asked for.
            final selected = select(candidate as TQueryData);
            outData = isNoStructuralSharing(options.structuralSharing)
                ? selected
                : replaceEqualDeep<TData>(prevResult?.dataOrNull, selected);
            _selectResult = outData;
            _hasSelectResult = true;
            hasOutData = true;
            // A selection of a placeholder belongs to no query: the
            // next pass over this query's real data starts without stale
            // data, as a failed first fetch does.
            if (isPlaceholderData) _selectQuery = null;
            _clearSelectError();
          } catch (selectError, selectStackTrace) {
            _selectError = selectError;
            _selectErrorStackTrace = selectStackTrace;
            _selectErrorUpdatedAt = clock.now();
          }
        }
      } else if (select == null && hasCandidate) {
        _hasSelectInput = false;
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
          final previousOutput = prevResult?.dataOrNull;
          final previous =
              prevResultOptions?.select == null && previousOutput is TQueryData
                  ? previousOutput
                  : null;
          outData = (sharing == null
              ? replaceEqualDeep<TQueryData>(previous, candidate as TQueryData)
              : sharing(previous, candidate as TQueryData)) as TData;
        } else {
          // Cached data goes through as it is, as upstream's `data =
          // state.data`: the cache write already applied `structuralSharing`,
          // and re-sharing it against the last result here hid an opt-out
          // (`(_, next) => next`) from every reader.
          outData = candidate as TData;
        }
        hasOutData = true;
        // The error belonged to a selector that is no longer there. Upstream
        // keeps reporting it until a *new* selection succeeds, which never
        // happens once `select` is gone.
        _clearSelectError();
      } else if (!hasCandidate) {
        _hasSelectInput = false;
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
            consecutiveErrorCount: state.consecutiveErrorCount,
            isStale: options.isStaleFor(query),
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
            consecutiveErrorCount: state.consecutiveErrorCount,
            isStale: options.isStaleFor(query),
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
            consecutiveErrorCount: state.consecutiveErrorCount,
            isStale: options.isStaleFor(query),
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
  /// then every one that is not value-equal to the last.
  ///
  /// A hook for subclasses that report state beside the result. [updateResult]
  /// has already installed [next] as [currentResult] when this is asked, so
  /// an override can compare whatever it derives from the result and the
  /// query; `InfiniteQueryObserver` adds its paging flags (`hasNextPage`,
  /// `isFetchingNextPage`, ...) this way, so a listener hears when one of
  /// them changes even if the result itself did not.
  @protected
  bool shouldNotify(QueryResult<TData>? previous, QueryResult<TData> next) =>
      previous == null || next != previous;

  /// Recomputes the result from the query's current state and notifies
  /// listeners if it changed — as [shouldNotify] decides.
  ///
  /// The observer calls this itself whenever the query changes, after its
  /// own fetches and when its stale timer fires; a caller rarely needs to.
  void updateResult() {
    final prevResult = _previousResult;
    final nextResult = createResult(_currentQuery, _options);

    _currentResultState = _currentQuery.state;
    _currentResultOptions = _options;

    if (_currentQuery.state.hasData) {
      _lastQueryWithData = _currentQuery;
    }

    _currentResult = nextResult;
    _previousResult = nextResult;
    if (!shouldNotify(prevResult, nextResult)) {
      return;
    }

    final revision = ++_resultRevision;

    _client.notifyManager.batch(() {
      // A listener's throw is the listener's problem, not the query's:
      // reaching `Query.fetch` it would be recorded as the fetch's error.
      // Reported to the zone, the way the mutation callbacks already are —
      // and a listener an earlier one unsubscribed is not called at all
      // ([ListenerRegistry.notify]).
      _listeners.notify((listener) {
        if (revision == _resultRevision) listener(nextResult);
      });
      if (revision == _resultRevision) {
        _client.queryCache.notifyObserverResultsUpdated(_currentQuery);
      }
    });
  }

  void _updateQuery([Query<TQueryData>? resolved]) {
    final query = resolved ??
        _client.queryCache.build<TQueryData>(
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
      final lifetime = _lifetime;
      prevQuery?.removeObserver(this);
      if (hasListeners && lifetime == _lifetime && identical(_query, query)) {
        query.addObserver(this);
      }
    }
  }

  // -------------------------------------------------- QueryObserverRef

  @override
  @internal
  void onQueryUpdate() {
    updateResult();
    if (hasListeners) {
      _updateTimers();
    }
  }

  @override
  @internal
  bool get isEnabledForQuery => _options.enabled.resolve(_currentQuery);

  @override
  @internal
  bool get isStaticForQuery => _options.staleTime.isStaticFor(_currentQuery);

  @override
  @internal
  bool get currentResultIsStale => _currentResult.isStale;

  @override
  @internal
  bool shouldFetchOnWindowFocus() =>
      _options.shouldFetchOnWindowFocus(_currentQuery);

  @override
  @internal
  bool shouldFetchOnReconnect() =>
      _options.shouldFetchOnReconnect(_currentQuery);

  @override
  @internal
  void refetchOnEvent() => executeFetch(cancelRefetch: false).ignore();

  @override
  @internal
  DefaultedQueryOptions<Object?> get observerQueryOptions =>
      _options.queryOptions;
}

typedef _SelectionSnapshot<TInput, TOutput> = ({
  Object? error,
  StackTrace? stackTrace,
  DateTime? updatedAt,
  TOutput Function(TInput)? select,
  TOutput? result,
  bool hasResult,
  TInput? input,
  bool hasInput,
  Query<TInput>? query,
});

/// The refetch rules, as questions asked of one observer's options about one
/// query. The rules belong to the *options*: the query supplies the state,
/// the options supply `enabled`, `staleTime` and the three `refetchOn*`
/// fields, and every one of them reads `options.<rule>(query)`.
///
/// **Four similar names, four different questions** — a round trip between
/// query and observer that terminates because the third step reads a field:
///
/// 1. [Query.isStale] — the *query's* view: does any observer call its own
///    result stale, or, with nothing observing, is there no data / has it been
///    invalidated;
/// 2. `QueryObserver.currentResultIsStale` — one observer's **cached** answer,
///    the `isStale` of the result it last built;
/// 3. [isStaleFor] — the **rule** that produced that field: enabled, and stale
///    by time;
/// 4. [Query.isStaleByTime] — the time half of the rule, which is where
///    `StaleTime.static` outranks an invalidation and `StaleTime.infinite`
///    does not.
extension _RefetchRules on DefaultedQueryObserverOptions<Object?, Object?> {
  /// Enabled, and older than this observer's `staleTime`. Step 3 above.
  bool isStaleFor(Query<Object?> query) =>
      enabled.resolve(query) && query.isStaleByTime(staleTime);

  /// Nothing to show yet: enabled, no data, and not an error a
  /// `retryOnMount: false` says to leave alone.
  bool shouldLoadOnMount(Query<Object?> query) =>
      enabled.resolve(query) &&
      !query.state.hasData &&
      !(query.state.status == QueryStatus.error && !retryOnMount);

  /// A first subscribe either loads or refreshes what is already there.
  bool shouldFetchOnMount(Query<Object?> query) =>
      shouldLoadOnMount(query) ||
      (query.state.hasData && shouldFetchOn(query, refetchOnMount));

  /// The shared body of the three `refetchOn*` fields: `always` refetches
  /// whatever the state, `never` refetches nothing, and anything else asks
  /// [isStaleFor]. A static `staleTime` opts out of all three.
  bool shouldFetchOn(Query<Object?> query, RefetchOn field) {
    if (enabled.resolve(query) && !staleTime.isStaticFor(query)) {
      final value = field.resolve(query);
      return value is RefetchOnAlways ||
          (value is! RefetchOnNever && isStaleFor(query));
    }
    return false;
  }

  /// The app returned to the foreground.
  bool shouldFetchOnWindowFocus(Query<Object?> query) =>
      shouldFetchOn(query, refetchOnWindowFocus);

  /// The device came back online.
  bool shouldFetchOnReconnect(Query<Object?> query) =>
      shouldFetchOn(query, refetchOnReconnect);

  /// `setOptions` moved to another query, or re-enabled this one, and what it
  /// landed on is stale. (TanStack Query: `shouldFetchOptionally`.)
  bool shouldFetchOptionally(
    Query<Object?> query,
    Query<Object?> prevQuery,
    DefaultedQueryObserverOptions<Object?, Object?> prevOptions, {
    bool? wasEnabled,
  }) =>
      (!identical(query, prevQuery) ||
          !(wasEnabled ?? prevOptions.enabled.resolve(query))) &&
      isStaleFor(query);
}
