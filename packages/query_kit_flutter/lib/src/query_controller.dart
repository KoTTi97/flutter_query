/// Listenable wrappers around the core's observers.
///
/// This is the binding's foundation: a `QueryObserver` already has a current
/// value and a `subscribe`, which is precisely what Flutter calls a
/// [ValueListenable]. Saying so once makes every other integration free —
/// `ValueListenableBuilder`, `ListenableBuilder`, `Listenable.merge`, and any
/// signal or state-management package that can read a listenable
/// (https://github.com/KoTTi97/flutter_query/issues/21).
///
/// Notifications are delivered through the client's `NotifyManager`, never
/// straight from the observer. That is what puts them on the scheduler the
/// `QueryClientProvider` installs: a result that changes while a build is in
/// flight is reported after the frame, not in the middle of it.
library;

import 'package:flutter/foundation.dart';
import 'package:query_kit/query_kit.dart';

/// A controller whose readers have to compare more than its `value`.
///
/// A `QueryResult` is the whole of what a plain query shows, so every reading
/// style skips a notification carrying the result it already built. An
/// infinite query keeps its paging state on the controller instead — a fetch
/// that switches direction leaves the result untouched — and that comparison
/// would swallow a change the widget is showing. A controller says here what
/// "everything its readers can see" means for it (third review, 2026-09-10).
abstract interface class ObservedState {
  /// The whole observable state, as one value with value equality.
  Object? get observedState;
}

/// [ObservedState.observedState] where [controller] has one, its `value`
/// otherwise.
Object? observedStateOf(ValueListenable<Object?> controller) =>
    controller is ObservedState
        ? (controller as ObservedState).observedState
        : controller.value;

/// One query, as a [ValueListenable].
///
/// ```dart
/// final task = QueryController.create<Task>(client, taskQuery(id));
/// // …
/// task.dispose();
/// ```
///
/// The controller subscribes to its observer only while something is listening
/// to *it*, so a controller nobody watches costs nothing but the observer's own
/// cache entry.
class QueryController<TQueryData, TData> extends ChangeNotifier
    implements ValueListenable<QueryResult<TData>>, ObservedState {
  /// Creates the observer for [options] on [client]. Nothing is fetched until
  /// the first listener arrives — until then [value] is the optimistic result.
  /// Call [dispose] when done; it destroys the observer.
  QueryController(
    this.client,
    QueryObserverOptionsBase<TQueryData, TData> options,
  )   : assert(
          _debugDataTypeIsAnchored<TData>(),
          'QueryController<$TQueryData, $TData>: the data type is a top type '
          '($TData) — give the options a queryFn whose return type names it, '
          'or an explicit type argument (QueryController.create<Task>(…), '
          'QueryBuilder<Task>(…)).',
        ),
        _observer = QueryObserver<TQueryData, TData>(client, options),
        _options = options;

  /// Wraps an observer built elsewhere — how [InfiniteQueryController] brings
  /// its own. The controller owns it from here on and destroys it on
  /// [dispose].
  ///
  /// A controller built this way holds no options of its own, so its [value]
  /// before the first listener is the observer's current result rather than
  /// the optimistic one — unless the subclass overrides [optimisticValue], as
  /// [InfiniteQueryController] does.
  QueryController.observing(
      this.client, QueryObserver<TQueryData, TData> observer)
      : assert(
          _debugDataTypeIsAnchored<TData>(),
          'QueryController<$TQueryData, $TData>: the data type is a top type '
          '($TData) — give the observer an explicit type argument.',
        ),
        _observer = observer,
        _options = null;

  /// The common case: no `select`, so the query's data type is what you get,
  /// and one type argument names it — from `queryFn`'s return type, or
  /// written out as `QueryController.create<Task>(…)` (ADR-0001).
  ///
  /// A static method rather than a named constructor because it drops a type
  /// parameter, which a constructor cannot. It *creates* a controller — and
  /// hands you something to [dispose] — so it deliberately does not use the
  /// name `of`: in Flutter that means "find the one already there", and a
  /// call in `build` that leaked an observer and its timers on every rebuild
  /// would be the reader's reasonable mistake, not theirs to debug (sixth
  /// review, 2026-09-10). In this package `of` belongs to
  /// [QueryClientProvider.of] alone.
  static QueryController<TData, TData> create<TData>(
    QueryClient client,
    QueryObserverOptions<TData> options,
  ) =>
      QueryController<TData, TData>(client, options);

  /// The client the observer runs on.
  final QueryClient client;

  final QueryObserver<TQueryData, TData> _observer;
  QueryObserverOptionsBase<TQueryData, TData>? _options;
  void Function()? _unsubscribe;
  bool _disposed = false;

  /// Set while the first subscription is being made, so a listener added from
  /// inside that subscription's own notification does not make a second one.
  bool _subscribing = false;

  /// The observer underneath, for the operations the controller does not
  /// mirror (`refetch`, `currentQuery`).
  QueryObserver<TQueryData, TData> get observer => _observer;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  /// A plain query shows its result and nothing else.
  @override
  Object? get observedState => value;

  /// The current result.
  ///
  /// While nobody listens this is the *optimistic* result — what the observer
  /// would report the moment a listener arrived: `fetching` for a query that
  /// will fetch on subscribe, not the `idle` the observer holds until then.
  /// That is the read upstream's `useBaseQuery` does on every render, and it
  /// is what makes a controller read before it is listened to agree with what
  /// every widget style shows on its first build. Once subscribed, the value
  /// is the observer's own, kept current by its notifications.
  @override
  QueryResult<TData> get value => _unsubscribe == null && !_disposed
      ? optimisticValue
      : _observer.currentResult;

  /// The result the observer would report on subscribing right now. Reported
  /// by [value] while nobody listens; see there.
  @protected
  QueryResult<TData> get optimisticValue {
    final options = _options;
    return options == null
        ? _observer.currentResult
        : _observer.getOptimisticResult(options);
  }

  /// Replaces the options — a changed key switches the observed query without
  /// recreating anything (https://github.com/KoTTi97/flutter_query/issues/22).
  ///
  /// Deliberately does not notify: the observer notifies by itself when the
  /// *result* changes, and notifying here would rebuild the widget that just
  /// called this from its own `build`.
  void setOptions(QueryObserverOptionsBase<TQueryData, TData> options) {
    _options = options;
    _observer.setOptions(options);
  }

  /// Refetches, completing with the result the refetch produced.
  Future<QueryResult<TData>> refetch({bool cancelRefetch = true}) =>
      _observer.refetch(cancelRefetch: cancelRefetch);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // `_subscribing` closes the window `_unsubscribe` alone leaves open: the
    // subscribe below can notify synchronously, a listener called there may
    // add another one, and that nested call would still see no handle and
    // subscribe a second time — one of the two handles then overwritten and
    // lost, leaving an observer attached for good (third review,
    // 2026-09-10).
    if (_unsubscribe != null || _disposed || _subscribing) {
      return;
    }
    _subscribing = true;
    final void Function() unsubscribe;
    try {
      unsubscribe = _observer.subscribe(
        client.notifyManager.batchCalls<QueryResult<TData>>((_) => _notify()),
      );
    } finally {
      _subscribing = false;
    }
    // Subscribing can notify on the spot, and a listener may leave inside its
    // first notification. The handle is only kept while someone still wants
    // it; otherwise the observer would stay attached with nobody to tell.
    if (!hasListeners || _disposed) {
      unsubscribe();
    } else {
      _unsubscribe = unsubscribe;
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _unsubscribe?.call();
      _unsubscribe = null;
    }
  }

  /// Delivered through the notify manager, so it can land after the frame
  /// that was building — or after the controller went away.
  void _notify() {
    if (!_disposed && hasListeners) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _unsubscribe?.call();
    _unsubscribe = null;
    _observer.destroy();
    super.dispose();
  }
}

/// One infinite query, as a [ValueListenable], with the paging operations the
/// sealed result does not carry
/// (https://github.com/KoTTi97/flutter_query/issues/16).
///
/// ```dart
/// final feed = InfiniteQueryController(client, feedQuery());
/// // …
/// if (feed.hasNextPage) feed.fetchNextPage();
/// ```
///
/// No type arguments at the call site: either options shape carries all
/// three, and inference reads them off it — `InfiniteQueryObserverOptions<List<Post>, int>`
/// makes an `InfiniteQueryController<List<Post>, int, InfiniteData<List<Post>, int>>`
/// (ADR-0001).
class InfiniteQueryController<TPageData, TPageParam, TData>
    extends QueryController<InfiniteData<TPageData, TPageParam>, TData> {
  /// Creates an [InfiniteQueryObserver] for [options] on [client], with the
  /// same contract as [QueryController.new]: nothing is fetched until the
  /// first listener, and [dispose] destroys the observer.
  InfiniteQueryController(
    QueryClient client,
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options,
  )   : assert(
          _debugDataTypeIsAnchored<TData>(),
          'InfiniteQueryController<$TPageData, $TPageParam, $TData>: the data '
          'type is a top type ($TData) — a plain infinite query never is, so '
          'give the select a return type that names it, or explicit type '
          'arguments (InfiniteQuerySelectOptions<List<Post>, int, '
          'List<Post>>(…)).',
        ),
        _infiniteOptions = options,
        super.observing(
          client,
          InfiniteQueryObserver<TPageData, TPageParam, TData>(client, options),
        );

  /// The typed options last applied, or `null` once [setOptions] applied
  /// untyped ones; then the base class's copy is the current one.
  InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData>?
      _infiniteOptions;

  /// The observer underneath, typed.
  InfiniteQueryObserver<TPageData, TPageParam, TData> get infiniteObserver =>
      observer as InfiniteQueryObserver<TPageData, TPageParam, TData>;

  @override
  QueryResult<TData> get optimisticValue {
    final options = _infiniteOptions;
    return options == null
        ? super.optimisticValue
        : infiniteObserver.getOptimisticInfiniteResult(options);
  }

  /// The result *and* the paging flags a builder can show. Two fetches in
  /// opposite directions leave the result equal, so without the flags the
  /// reading styles would filter the change out.
  @override
  Object? get observedState => (
        value,
        infiniteObserver.isFetchingNextPage,
        infiniteObserver.isFetchingPreviousPage,
        infiniteObserver.isFetchNextPageError,
        infiniteObserver.isFetchPreviousPageError,
        infiniteObserver.hasNextPage,
        infiniteObserver.hasPreviousPage,
      );

  /// Replaces the options, paging half included. See
  /// [QueryController.setOptions] on why this does not notify.
  void setInfiniteOptions(
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options,
  ) {
    _infiniteOptions = options;
    _options = null;
    infiniteObserver.setInfiniteOptions(options);
  }

  /// Accepts any options that carry the paging behaviour — what
  /// [setInfiniteOptions] and the core's own conversions produce — and
  /// forwards them to the observer, exactly as
  /// `InfiniteQueryObserver.setOptions` does. Plain observer options have no
  /// paging half; applying them would silently drop it, so they are refused
  /// with an [UnsupportedError] in every build mode (an `assert` would have
  /// made that a silent no-op in release). Nothing is kept when the observer
  /// refuses.
  @override
  void setOptions(
    QueryObserverOptionsBase<InfiniteData<TPageData, TPageParam>, TData>
        options,
  ) {
    infiniteObserver.setOptions(options);
    _infiniteOptions = null;
    _options = options;
  }

  /// Whether [fetchNextPage] has a page to fetch: the options'
  /// `getNextPageParam`, given the pages held, returns a param. False before
  /// the first page is in, and false — not an error — once the paging function
  /// says there is no more.
  bool get hasNextPage => infiniteObserver.hasNextPage;

  /// Whether [fetchPreviousPage] has a page to fetch: the options'
  /// `getPreviousPageParam` returns a param for the pages held. Always false
  /// when the options have none.
  bool get hasPreviousPage => infiniteObserver.hasPreviousPage;

  /// Whether the fetch in flight is a [fetchNextPage] — the result's
  /// `isFetching`, narrowed to the forward direction, so a refetch of the
  /// pages already held ([isRefetching]) does not count.
  bool get isFetchingNextPage => infiniteObserver.isFetchingNextPage;

  /// The backwards twin of [isFetchingNextPage]: the fetch in flight is a
  /// [fetchPreviousPage].
  bool get isFetchingPreviousPage => infiniteObserver.isFetchingPreviousPage;

  /// Whether the result's error came from a [fetchNextPage] — the result's
  /// `isError`, narrowed to the forward direction. The pages already held are
  /// still there; a failed refetch of *those* is [isRefetchError] instead.
  bool get isFetchNextPageError => infiniteObserver.isFetchNextPageError;

  /// The backwards twin of [isFetchNextPageError]: the error came from a
  /// [fetchPreviousPage].
  bool get isFetchPreviousPageError =>
      infiniteObserver.isFetchPreviousPageError;

  /// Whether the pages already held are being refetched, as opposed to a page
  /// being added — the result's own `isRefetching` is true for both.
  bool get isRefetching => infiniteObserver.isRefetching;

  /// Whether a refetch of the held pages failed, as opposed to a page fetch.
  bool get isRefetchError => infiniteObserver.isRefetchError;

  /// Fetches the page after the ones already held.
  Future<QueryResult<TData>> fetchNextPage({bool cancelRefetch = true}) =>
      infiniteObserver.fetchNextPage(cancelRefetch: cancelRefetch);

  /// Fetches the page before the ones already held.
  Future<QueryResult<TData>> fetchPreviousPage({bool cancelRefetch = true}) =>
      infiniteObserver.fetchPreviousPage(cancelRefetch: cancelRefetch);
}

/// One mutation, as a [ValueListenable].
class MutationController<TData, TVariables, TOnMutateResult>
    extends ChangeNotifier
    implements ValueListenable<MutationResult<TData, TVariables>> {
  /// Creates a [MutationObserver] with [options] on [client]. Idle until
  /// [mutate] or [mutateAsync] starts a run; [dispose] detaches it from
  /// whatever mutation it ran, so that mutation can be collected.
  MutationController(
    this.client,
    MutationOptions<TData, TVariables, TOnMutateResult> options,
  ) : _observer = MutationObserver<TData, TVariables, TOnMutateResult>(
          client,
          options,
        );

  /// The client the observer runs on.
  final QueryClient client;

  final MutationObserver<TData, TVariables, TOnMutateResult> _observer;
  void Function()? _unsubscribe;
  bool _disposed = false;

  /// See [QueryController] on the same field: one subscription, even when a
  /// listener added from inside the first notification races it.
  bool _subscribing = false;

  /// The observer underneath, for what the controller does not mirror — the
  /// defaulted `options` it runs with, for one.
  MutationObserver<TData, TVariables, TOnMutateResult> get observer =>
      _observer;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  @override
  MutationResult<TData, TVariables> get value => _observer.currentResult;

  /// See [QueryController.setOptions] on why this does not notify.
  void setOptions(
    MutationOptions<TData, TVariables, TOnMutateResult> options,
  ) =>
      _observer.setOptions(options);

  /// Fire and forget: the result lands in [value], errors never reach the
  /// caller.
  ///
  /// Still runs after [dispose] — see [mutateAsync].
  void mutate(
    TVariables variables, {
    MutateCallbacks<TData, TVariables, TOnMutateResult>? callbacks,
  }) =>
      mutateAsync(variables, callbacks: callbacks).ignore();

  /// Completes with the data, or throws.
  ///
  /// Called after [dispose] — a tap handler that awaited a dialog and whose
  /// widget is gone by the time it gets here — the mutation still runs, with
  /// its options' callbacks, and is collected after its `gcTime` like any
  /// mutation nobody watches. Nothing lands in [value], and the per-call
  /// [callbacks] are dropped, as they are for any run whose controller has no
  /// listener. Upstream re-attaches the forgotten observer, so the mutation
  /// stays in the cache for good; a disposed controller here does not come
  /// back (ninth review, 2026-09-10, C18). Hold the controller above the
  /// widget when the result is wanted after the widget is gone.
  Future<TData> mutateAsync(
    TVariables variables, {
    MutateCallbacks<TData, TVariables, TOnMutateResult>? callbacks,
  }) {
    if (_disposed) {
      return client.mutationCache
          .build<TData, TVariables, TOnMutateResult>(client, _observer.options)
          .execute(variables);
    }
    return _observer.mutateAsync(variables, callbacks: callbacks);
  }

  /// Back to idle, detaching from the mutation being observed.
  void reset() => _observer.reset();

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // Reentrancy, exactly as in [QueryController.addListener]; see there.
    if (_unsubscribe != null || _disposed || _subscribing) {
      return;
    }
    _subscribing = true;
    final void Function() unsubscribe;
    try {
      unsubscribe = _observer.subscribe(
        client.notifyManager
            .batchCalls<MutationResult<TData, TVariables>>((_) => _notify()),
      );
    } finally {
      _subscribing = false;
    }
    if (!hasListeners || _disposed) {
      unsubscribe();
    } else {
      _unsubscribe = unsubscribe;
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _unsubscribe?.call();
      _unsubscribe = null;
    }
  }

  void _notify() {
    if (!_disposed && hasListeners) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _unsubscribe?.call();
    _unsubscribe = null;
    // Detach whether or not anyone ever listened: `mutateAsync` attaches the
    // observer to its mutation regardless, and a mutation with an observer
    // left behind is never collected.
    _observer.destroy();
    super.dispose();
  }
}

/// Whether [TData] is a real type rather than a top type — `dynamic`,
/// `Object?` or `void` — which is what a plain options literal written inline
/// with neither a `queryFn` nor a type argument leaves an observer with. A
/// `List<Object?>` is a `List<TData>` exactly for the top types, so the test
/// survives the question whether such a slot is inferred as `dynamic` or
/// `Object?`. The controllers assert it: a debug backstop for the one
/// residue the options shapes cannot remove (ADR-0001), compiled out of
/// release.
bool _debugDataTypeIsAnchored<TData>() => <Object?>[] is! List<TData>;
