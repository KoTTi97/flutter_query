/// Homogeneous adaptation of upstream `queriesObserver.ts` at `50680b98c`.
library;

import 'dart:collection';

import 'listener_registry.dart';
import 'query_client.dart';
import 'query_key.dart';
import 'query_observer.dart';
import 'query_options.dart';
import 'query_result.dart';

/// Watches a dynamic, ordered list of independently settling queries.
///
/// Keys identify cache entries; repeated occurrences each own an observer,
/// allowing distinct selections and options over the same cached data.
class QueriesObserver<TQueryData, TData> {
  /// Builds the queries without fetching until the first subscription.
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

  /// Whether this collection has active subscribers.
  bool get hasListeners => _listeners.hasListeners;

  /// The latest result for each query, in input order.
  List<QueryResult<TData>> get currentResult => _result;

  /// Results as if these queries were subscribed, for a Flutter first build.
  List<QueryResult<TData>> getOptimisticResult() => List.unmodifiable([
        for (var i = 0; i < _observers.length; i++)
          _observers[i].getOptimisticResult(_queries[i]),
      ]);

  /// The underlying observers, in input order. The returned list is read-only;
  /// their lifetime belongs to this collection.
  List<QueryObserver<TQueryData, TData>> get observers =>
      List.unmodifiable(_observers);

  /// Registers a listener and starts each enabled query independently.
  void Function() subscribe(void Function(List<QueryResult<TData>>) listener) {
    final remove = _listeners.add(listener, onRemoved: () {
      if (!hasListeners) _detach();
    });
    if (_listeners.length == 1) {
      for (final observer in List.of(_observers)) {
        _subscribeObserver(observer);
      }
      _collect();
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

  /// Reuses observers by key and occurrence, preserving result order. New
  /// queries subscribe immediately when this collection is being observed.
  void setQueries(List<QueryObserverOptionsBase<TQueryData, TData>> queries) {
    final nextQueries =
        List<QueryObserverOptionsBase<TQueryData, TData>>.of(queries);
    final available = <QueryKey, Queue<QueryObserver<TQueryData, TData>>>{};
    for (final observer in _observers) {
      available.putIfAbsent(observer.options.queryKey, Queue.new).add(observer);
    }
    final next = <QueryObserver<TQueryData, TData>>[];
    final created = <QueryObserver<TQueryData, TData>>[];
    // Resolve types/defaults before changing existing subscriptions.
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
    } catch (_) {
      for (final observer in created) {
        observer.destroy();
      }
      rethrow;
    }
    _updating++;
    try {
      for (final observer in _observers) {
        if (!next.contains(observer)) {
          _subscriptions.remove(observer)?.call();
          observer.destroy();
        }
      }
      _queries = nextQueries;
      _observers = next;
      for (var i = 0; i < next.length; i++) {
        next[i].setOptions(nextQueries[i]);
      }
      if (hasListeners) {
        for (final observer in List.of(next)) {
          _subscribeObserver(observer);
        }
      }
    } finally {
      _updating--;
    }
    _collect();
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

  /// Releases listeners and every underlying observer.
  void destroy() {
    _resultRevision++;
    _listeners.clear();
    _detach();
    for (final observer in _observers) {
      observer.destroy();
    }
  }
}
