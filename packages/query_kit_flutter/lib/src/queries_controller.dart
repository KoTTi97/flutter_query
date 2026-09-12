/// Flutter adapter for a changing list of queries.
library;

import 'package:flutter/foundation.dart';
import 'package:query_kit/query_kit.dart';

import 'controller_lifetime.dart';
import 'notify_gate.dart';

/// An ordered query-result list, observed only while listeners are attached.
class QueriesController<TQueryData, TData> extends ChangeNotifier
    implements ValueListenable<List<QueryResult<TData>>> {
  /// Creates the collection. Enabled queries start with the first listener.
  QueriesController(
      this.client, List<QueryObserverOptionsBase<TQueryData, TData>> queries)
      : _observer = QueriesObserver<TQueryData, TData>(client, queries);

  /// The client all queries in this collection use.
  final QueryClient client;
  final QueriesObserver<TQueryData, TData> _observer;

  /// Subscribed while listened to, and never told twice about the same
  /// results — see [ControllerLifetime]. The gate is element-wise, because
  /// [value] is a `List` — identity, not value, equality — while the
  /// `QueryResult`s in it carry `==`.
  late final ControllerLifetime<List<QueryResult<TData>>> _life =
      ControllerLifetime<List<QueryResult<TData>>>(
    gate: NotifyGate.elementWise<QueryResult<TData>>(),
    read: () => value,
    subscribe: (deliver) => _observer.subscribe(
      (_) => client.notifyManager.schedule(deliver),
    ),
    hasListeners: () => hasListeners,
    notify: notifyListeners,
  );

  @override
  List<QueryResult<TData>> get value =>
      !_observer.hasListeners && !_life.isDisposed
          ? _observer.getOptimisticResult()
          : _observer.currentResult;

  /// The collection's core observer, including its underlying observers.
  QueriesObserver<TQueryData, TData> get observer => _observer;

  /// Replaces the query list, reusing existing observers by key occurrence.
  void setQueries(List<QueryObserverOptionsBase<TQueryData, TData>> queries) =>
      _observer.setQueries(queries);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _life.listenerAdded();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _life.listenerRemoved();
  }

  @override
  void dispose() {
    if (!_life.dispose()) return;
    _observer.destroy();
    super.dispose();
  }
}
