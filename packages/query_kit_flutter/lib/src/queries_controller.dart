/// Flutter adapter for a changing list of queries.
library;

import 'package:flutter/foundation.dart';
import 'package:query_kit/query_kit.dart';

/// An ordered query-result list, observed only while listeners are attached.
class QueriesController<TQueryData, TData> extends ChangeNotifier
    implements ValueListenable<List<QueryResult<TData>>> {
  /// Creates the collection. Enabled queries start with the first listener.
  QueriesController(
      this.client, List<QueryObserverOptions<TQueryData, TData>> queries)
      : _observer = QueriesObserver<TQueryData, TData>(client, queries);

  /// The client all queries in this collection use.
  final QueryClient client;
  final QueriesObserver<TQueryData, TData> _observer;
  void Function()? _unsubscribe;
  bool _disposed = false;
  bool _subscribing = false;

  @override
  List<QueryResult<TData>> get value => !_observer.hasListeners && !_disposed
      ? _observer.getOptimisticResult()
      : _observer.currentResult;

  /// The collection's core observer, including its underlying observers.
  QueriesObserver<TQueryData, TData> get observer => _observer;

  /// Replaces the query list, reusing existing observers by key occurrence.
  void setQueries(List<QueryObserverOptions<TQueryData, TData>> queries) =>
      _observer.setQueries(queries);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_unsubscribe != null || _disposed || _subscribing) return;
    _subscribing = true;
    try {
      final unsubscribe = _observer.subscribe((_) {
        client.notifyManager.schedule(() {
          if (!_disposed && hasListeners) notifyListeners();
        });
      });
      if (_disposed || !hasListeners) {
        unsubscribe();
      } else {
        _unsubscribe = unsubscribe;
      }
    } finally {
      _subscribing = false;
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

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _unsubscribe?.call();
    _unsubscribe = null;
    _observer.destroy();
    super.dispose();
  }
}
