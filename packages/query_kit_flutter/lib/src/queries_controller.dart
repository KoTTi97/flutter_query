/// Flutter adapter for a changing list of queries. See [QueriesController].
library;

import 'package:flutter/foundation.dart';
import 'package:query_kit/query_kit.dart';

import 'controller_lifetime.dart';
import 'notify_gate.dart';

/// A list of queries that may change length or order, as a
/// [ValueListenable] of their results in the same order.
///
/// The controller underneath [QueriesBuilder], for the same collection in a
/// view model or anywhere else outside a widget:
///
/// ```dart
/// final tasks = QueriesController(client, [
///   for (final id in ids) taskQuery(id),
/// ]);
///
/// ValueListenableBuilder<List<QueryResult<Task>>>(
///   valueListenable: tasks,
///   builder: (context, results, _) => Text(
///     '${results.where((r) => r.dataOrNull?.done ?? false).length} done',
///   ),
/// );
///
/// // The list changed — observers are reused by key and occurrence:
/// tasks.setQueries([for (final id in newIds) taskQuery(id)]);
///
/// // When done — it destroys every observer:
/// tasks.dispose();
/// ```
///
/// Subscribed to its queries only while something listens, which is when
/// the enabled ones fetch if they need to. Before the first listener,
/// [value] is the optimistic list the widget styles show on a first build.
/// Listeners are told only when a result changed, compared element by
/// element.
///
/// {@category Collections}
class QueriesController<TQueryData, TData> extends ChangeNotifier
    implements ValueListenable<List<QueryResult<TData>>> {
  /// Creates the collection over [queries] on [client]. Nothing fetches
  /// until the first listener arrives; then every enabled query that needs
  /// to does.
  QueriesController(
      this.client, List<QueryObserverOptionsBase<TQueryData, TData>> queries)
      : _observer = QueriesObserver<TQueryData, TData>(client, queries);

  /// The client all queries in this collection use.
  final QueryClient client;
  final QueriesObserver<TQueryData, TData> _observer;

  /// Subscribed while listened to, and never told twice about the same
  /// results — see [ControllerLifetime]. Refetch targets are compared too:
  /// replacing or reordering equal results must update listeners' actions.
  late final ControllerLifetime<List<(QueryResult<TData>, QueryRefetch<TData>)>>
      _life =
      ControllerLifetime<List<(QueryResult<TData>, QueryRefetch<TData>)>>(
    gate: NotifyGate.elementWise<(QueryResult<TData>, QueryRefetch<TData>)>(),
    read: () => [for (final result in value) (result, result.refetch)],
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

  /// Replaces the query list, reusing existing observers by key occurrence —
  /// reordering starts no requests, and a new key fetches like any new
  /// query.
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
