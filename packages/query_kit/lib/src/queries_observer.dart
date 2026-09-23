/// [QueriesObserver]: a list of queries observed together.
library;

import 'dart:collection';

import 'listener_registry.dart';
import 'query_client.dart';
import 'query_key.dart';
import 'query_observer.dart';
import 'query_options.dart';
import 'query_result.dart';

/// Watches a list of queries at once and reports their results as one
/// list, in the order the queries were given.
///
/// Use it when the number of queries is only known at run time — one query
/// per id in a list, say. Each query is fetched, cached and settles on its
/// own, exactly as with a [QueryObserver] per query (which is what this
/// holds, one per entry); the listener receives the whole list of
/// [QueryResult]s whenever any of them changes. All queries share one data
/// type [TQueryData] and one reported type [TData]; for a fixed handful of
/// queries of different types, observe them separately and combine the
/// results with `combine` on a record of results.
///
/// The lifecycle mirrors [QueryObserver]'s:
///
/// - **Construct** with a client and a list of options. The queries are
///   built or joined, but nothing is fetched yet.
/// - **[subscribe]** a listener. The first listener subscribes every
///   member, which fetches each one that is due.
/// - **[setQueries]** replaces the list — members whose key is still there
///   are kept (and handed their new options), new keys get a new member,
///   and members whose key is gone are dropped.
/// - **Stop**: removing the last listener unsubscribes every member;
///   [destroy] also releases the members themselves.
///
/// ```dart
/// final observer = QueriesObserver(client, [
///   for (final id in taskIds)
///     QueryObserverOptions<Task>(
///       queryKey: QueryKey(['tasks', id]),
///       queryFn: (_) => api.task(id),
///     ),
/// ]);
/// final unsubscribe = observer.subscribe((results) {
///   final loaded = results.whereType<QuerySuccess<Task>>().length;
///   print('$loaded of ${results.length} tasks loaded');
/// });
/// // When the ids change: observer.setQueries([...]).
/// // When done:
/// unsubscribe();
/// ```
///
/// The same key may appear more than once; each occurrence gets its own
/// member, so two entries can apply different `select`s or options to the
/// same cached data.
///
/// {@category Observers}
class QueriesObserver<TQueryData, TData> {
  /// Creates the members for [queries] — building or joining each query —
  /// without fetching until the first [subscribe].
  ///
  /// Throws an [ArgumentError] if an entry has no `select` and a
  /// [TQueryData] is not a [TData].
  QueriesObserver(
      this._client, List<QueryObserverOptionsBase<TQueryData, TData>> queries) {
    setQueries(queries);
  }

  final QueryClient _client;
  List<QueryObserverOptionsBase<TQueryData, TData>> _queries = [];
  List<QueryObserver<TQueryData, TData>> _observers = [];
  final Map<QueryObserver<TQueryData, TData>, void Function()> _subscriptions =
      Map.identity();
  final Set<QueryObserver<TQueryData, TData>> _subscribing = Set.identity();
  final ListenerRegistry<void Function(List<QueryResult<TData>>)> _listeners =
      ListenerRegistry<void Function(List<QueryResult<TData>>)>();
  List<QueryResult<TData>> _result = List.unmodifiable(<QueryResult<TData>>[]);
  int _updating = 0;
  int _resultRevision = 0;

  /// Whether anyone is subscribed. While this is false, the members are not
  /// subscribed to their queries and nothing is fetched on their behalf.
  bool get hasListeners => _listeners.hasListeners;

  /// The latest result for each query, in the order of the list last
  /// given to the constructor or [setQueries]. Read-only; a new list
  /// replaces it whenever any member's result changes.
  List<QueryResult<TData>> get currentResult => _result;

  /// Each member's [QueryObserver.getOptimisticResult] for its current
  /// options: the results as they will look once subscribed, a fetch about
  /// to start included — the right read for a UI's first build, before the
  /// subscription exists. Fetches nothing.
  List<QueryResult<TData>> getOptimisticResult() => List.unmodifiable([
        for (var i = 0; i < _observers.length; i++)
          _observers[i].getOptimisticResult(_queries[i]),
      ]);

  /// The underlying observers, in input order. The returned list is read-only;
  /// their lifetime belongs to this collection.
  List<QueryObserver<TQueryData, TData>> get observers =>
      List.unmodifiable(_observers);

  /// Registers [listener] and returns the function that removes it again.
  ///
  /// The listener receives the whole list of results each time any member's
  /// result changes. The first listener subscribes every member, which
  /// fetches each query that is enabled and due, independently of the
  /// others; removing the last one unsubscribes them all again. Each
  /// returned function removes its own registration, once.
  ///
  /// A member whose dynamic option (an `Enabled.when`, a `StaleTime.dynamic`,
  /// ...) throws on its first subscribe throws out of here too, and — as
  /// [QueryObserver.subscribe] does for itself — leaves nothing behind: the
  /// members subscribed before it are unsubscribed again and the listener is
  /// removed.
  void Function() subscribe(void Function(List<QueryResult<TData>>) listener) {
    final remove = _listeners.add(listener, onRemoved: () {
      if (!hasListeners) _detach();
    });
    if (_listeners.length == 1) {
      try {
        for (final observer in List.of(_observers)) {
          _subscribeObserver(observer);
        }
        _collect();
      } catch (_) {
        remove();
        rethrow;
      }
    }
    return remove;
  }

  void _subscribeObserver(QueryObserver<TQueryData, TData> observer) {
    if (!hasListeners ||
        !_observers.contains(observer) ||
        _subscriptions.containsKey(observer) ||
        !_subscribing.add(observer)) {
      return;
    }
    try {
      // The first notification can synchronously call setQueries. Guard the
      // subscription before its unsubscribe handle has become available.
      final unsubscribe = observer.subscribe((_) {
        if (_updating == 0 && _observers.contains(observer)) _collect();
      });
      if (hasListeners && _observers.contains(observer)) {
        _subscriptions[observer] = unsubscribe;
      } else {
        unsubscribe();
      }
    } finally {
      _subscribing.remove(observer);
    }
  }

  /// Replaces the list of queries.
  ///
  /// Members are matched by key and occurrence: the first entry with a key
  /// reuses the first existing member with that key, the second the second,
  /// and so on, and each reused member is handed its entry's new options
  /// (see [QueryObserver.setOptions]). Entries with no match get a new
  /// member, which is subscribed right away if anyone is listening; members
  /// left without an entry are unsubscribed and destroyed. Results follow
  /// the new order, and listeners hear about the new list if it changed.
  ///
  /// If building or updating a member throws — a type mismatch, a throwing
  /// `InitialData.compute` — the list is left as it was: new members are
  /// destroyed and no member is removed, though members before the failing
  /// one keep the options they were just given.
  void setQueries(List<QueryObserverOptionsBase<TQueryData, TData>> queries) {
    final nextQueries =
        List<QueryObserverOptionsBase<TQueryData, TData>>.of(queries);
    final available = <QueryKey, Queue<QueryObserver<TQueryData, TData>>>{};
    for (final observer in _observers) {
      available.putIfAbsent(observer.options.queryKey, Queue.new).add(observer);
    }
    final next = <QueryObserver<TQueryData, TData>>[];
    final created = <QueryObserver<TQueryData, TData>>[];
    _updating++;
    try {
      // Everything that can throw — types, defaults, a new member's
      // construction and every member's `setOptions`, which runs user code
      // (`InitialData.compute`) — before the collection changes, as
      // upstream applies the options before it swaps `#observers`. Applied
      // after the swap, a throw left removed members destroyed, new members
      // never subscribed and `currentResult` a different length from
      // `observers`. Members before the
      // throwing one keep their new options, as upstream's do.
      try {
        for (final options in nextQueries) {
          if (options.select == null && <TQueryData>[] is! List<TData>) {
            throw ArgumentError(
                'QueriesObserver requires select when data types differ.');
          }
          _client.defaultQueryObserverOptions(options);
          final matches = available[options.queryKey];
          if (matches != null && matches.isNotEmpty) {
            next.add(matches.removeFirst());
          } else {
            final observer = QueryObserver<TQueryData, TData>(_client, options);
            created.add(observer);
            next.add(observer);
          }
        }
        for (var i = 0; i < next.length; i++) {
          next[i].setOptions(nextQueries[i]);
        }
      } catch (_) {
        for (final observer in created) {
          observer.destroy();
        }
        rethrow;
      }
      for (final observer in _observers) {
        if (!next.contains(observer)) {
          _subscriptions.remove(observer)?.call();
          observer.destroy();
        }
      }
      _queries = nextQueries;
      _observers = next;
      if (hasListeners) {
        for (final observer in List.of(next)) {
          _subscribeObserver(observer);
        }
      }
    } finally {
      _updating--;
      // On the throw path too: the members before the throwing one took
      // their new options with their notifications held back by `_updating`,
      // and skipping this left `currentResult` behind theirs and the
      // listeners untold.
      _collect();
    }
  }

  void _collect() {
    final next = <QueryResult<TData>>[
      for (var i = 0; i < _observers.length; i++) _observers[i].currentResult,
    ];
    if (next.length == _result.length &&
        Iterable<int>.generate(next.length).every((i) =>
            next[i] == _result[i] && next[i].refetch == _result[i].refetch)) {
      return;
    }
    _result = List.unmodifiable(next);
    final result = _result;
    final revision = ++_resultRevision;
    _listeners.notify((listener) {
      if (revision == _resultRevision) listener(result);
    });
  }

  void _detach() {
    final subscriptions = List.of(_subscriptions.values);
    _subscriptions.clear();
    for (final unsubscribe in subscriptions) {
      unsubscribe();
    }
  }

  /// Stops observing for good: removes every listener, unsubscribes every
  /// member and destroys it, so each query starts its `gcTime` clock once
  /// nothing else observes it.
  void destroy() {
    _resultRevision++;
    _listeners.clear();
    _detach();
    for (final observer in _observers) {
      observer.destroy();
    }
  }
}
