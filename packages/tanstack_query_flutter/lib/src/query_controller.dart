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
import 'package:tanstack_query_core/tanstack_query_core.dart';

/// One query, as a [ValueListenable].
///
/// ```dart
/// final sensor = QueryController.of<Sensor>(client, sensorQuery(id));
/// // …
/// sensor.dispose();
/// ```
///
/// The controller subscribes to its observer only while something is listening
/// to *it*, so a controller nobody watches costs nothing but the observer's own
/// cache entry.
class QueryController<TQueryData, TData> extends ChangeNotifier
    implements ValueListenable<QueryResult<TData>> {
  QueryController(
    this.client,
    QueryObserverOptions<TQueryData, TData> options,
  )   : _observer = QueryObserver<TQueryData, TData>(client, options),
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
      : _observer = observer,
        _options = null;

  /// The common case: no `select`, so the query's data type is what you get.
  static QueryController<TData, TData> of<TData>(
    QueryClient client,
    QueryObserverOptions<TData, TData> options,
  ) =>
      QueryController<TData, TData>(client, options);

  /// The client the observer runs on.
  final QueryClient client;

  final QueryObserver<TQueryData, TData> _observer;
  QueryObserverOptions<TQueryData, TData>? _options;
  void Function()? _unsubscribe;
  bool _disposed = false;

  /// The observer underneath, for the operations the controller does not
  /// mirror (`refetch`, `currentQuery`).
  QueryObserver<TQueryData, TData> get observer => _observer;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

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
  void setOptions(QueryObserverOptions<TQueryData, TData> options) {
    _options = options;
    _observer.setOptions(options);
  }

  /// Refetches, completing with the result the refetch produced.
  Future<QueryResult<TData>> refetch({bool cancelRefetch = true}) =>
      _observer.refetch(cancelRefetch: cancelRefetch);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_unsubscribe != null || _disposed) {
      return;
    }
    final unsubscribe = _observer.subscribe(
      client.notifyManager.batchCalls<QueryResult<TData>>((_) => _notify()),
    );
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
/// final feed = InfiniteQueryController<List<Post>, int, InfiniteData<List<Post>, int>>(
///   client,
///   feedQuery(),
/// );
/// // …
/// if (feed.hasNextPage) feed.fetchNextPage();
/// ```
class InfiniteQueryController<TPageData, TPageParam, TData>
    extends QueryController<InfiniteData<TPageData, TPageParam>, TData> {
  InfiniteQueryController(
    QueryClient client,
    InfiniteQueryObserverOptions<TPageData, TPageParam, TData> options,
  )   : _infiniteOptions = options,
        super.observing(
          client,
          InfiniteQueryObserver<TPageData, TPageParam, TData>(client, options),
        );

  InfiniteQueryObserverOptions<TPageData, TPageParam, TData> _infiniteOptions;

  /// The observer underneath, typed.
  InfiniteQueryObserver<TPageData, TPageParam, TData> get infiniteObserver =>
      observer as InfiniteQueryObserver<TPageData, TPageParam, TData>;

  @override
  QueryResult<TData> get optimisticValue =>
      infiniteObserver.getOptimisticInfiniteResult(_infiniteOptions);

  /// Replaces the options, paging half included. See
  /// [QueryController.setOptions] on why this does not notify.
  void setInfiniteOptions(
    InfiniteQueryObserverOptions<TPageData, TPageParam, TData> options,
  ) {
    _infiniteOptions = options;
    infiniteObserver.setInfiniteOptions(options);
  }

  /// Not for infinite queries: the plain observer options carry no paging
  /// half, so applying them here would silently drop it. Throws in every
  /// build mode, where an `assert` would have made it a silent no-op in
  /// release.
  @override
  void setOptions(
    QueryObserverOptions<InfiniteData<TPageData, TPageParam>, TData> options,
  ) {
    throw UnsupportedError(
      'Use setInfiniteOptions on an InfiniteQueryController; plain observer '
      'options have no paging half.',
    );
  }

  bool get hasNextPage => infiniteObserver.hasNextPage;
  bool get hasPreviousPage => infiniteObserver.hasPreviousPage;
  bool get isFetchingNextPage => infiniteObserver.isFetchingNextPage;
  bool get isFetchingPreviousPage => infiniteObserver.isFetchingPreviousPage;
  bool get isFetchNextPageError => infiniteObserver.isFetchNextPageError;
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
  void mutate(
    TVariables variables, {
    MutateCallbacks<TData, TVariables, TOnMutateResult>? callbacks,
  }) =>
      _observer.mutate(variables, callbacks: callbacks);

  /// Completes with the data, or throws.
  Future<TData> mutateAsync(
    TVariables variables, {
    MutateCallbacks<TData, TVariables, TOnMutateResult>? callbacks,
  }) =>
      _observer.mutateAsync(variables, callbacks: callbacks);

  /// Back to idle, detaching from the mutation being observed.
  void reset() => _observer.reset();

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_unsubscribe != null || _disposed) {
      return;
    }
    final unsubscribe = _observer.subscribe(
      client.notifyManager
          .batchCalls<MutationResult<TData, TVariables>>((_) => _notify()),
    );
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
