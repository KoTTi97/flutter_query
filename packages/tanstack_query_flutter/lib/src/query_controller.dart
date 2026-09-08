/// Listenable wrappers around the core's observers.
///
/// This is the binding's foundation: a `QueryObserver` already has a current
/// value and a `subscribe`, which is precisely what Flutter calls a
/// [ValueListenable]. Saying so once makes every other integration free —
/// `ValueListenableBuilder`, `ListenableBuilder`, `Listenable.merge`, and any
/// signal or state-management package that can read a listenable
/// (https://github.com/KoTTi97/flutter_query/issues/21).
library;

import 'package:flutter/foundation.dart';
import 'package:tanstack_query_core/tanstack_query_core.dart';

/// One query, as a [ValueListenable].
///
/// ```dart
/// final sensor = QueryController<Sensor>(client, sensorQuery(id));
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
    QueryClient client,
    QueryObserverOptions<TQueryData, TData> options,
  ) : _observer = QueryObserver<TQueryData, TData>(client, options);

  /// The common case: no `select`, so the query's data type is what you get.
  static QueryController<TData, TData> of<TData>(
    QueryClient client,
    QueryObserverOptions<TData, TData> options,
  ) =>
      QueryController<TData, TData>(client, options);

  final QueryObserver<TQueryData, TData> _observer;
  void Function()? _unsubscribe;
  bool _disposed = false;

  /// The observer underneath, for the operations the controller does not
  /// mirror (`refetch`, `currentQuery`).
  QueryObserver<TQueryData, TData> get observer => _observer;

  @override
  QueryResult<TData> get value => _observer.currentResult;

  /// Replaces the options — a changed key switches the observed query without
  /// recreating anything (https://github.com/KoTTi97/flutter_query/issues/22).
  ///
  /// Deliberately does not notify: the observer notifies by itself when the
  /// *result* changes, and notifying here would rebuild the widget that just
  /// called this from its own `build`.
  void setOptions(QueryObserverOptions<TQueryData, TData> options) =>
      _observer.setOptions(options);

  /// Refetches, completing with the result the refetch produced.
  Future<QueryResult<TData>> refetch({bool cancelRefetch = true}) =>
      _observer.refetch(cancelRefetch: cancelRefetch);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _unsubscribe ??= _observer.subscribe((_) => notifyListeners());
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

/// One mutation, as a [ValueListenable].
class MutationController<TData, TVariables, TOnMutateResult>
    extends ChangeNotifier
    implements ValueListenable<MutationResult<TData, TVariables>> {
  MutationController(
    QueryClient client,
    MutationOptions<TData, TVariables, TOnMutateResult> options,
  ) : _observer = MutationObserver<TData, TVariables, TOnMutateResult>(
          client,
          options,
        );

  final MutationObserver<TData, TVariables, TOnMutateResult> _observer;
  void Function()? _unsubscribe;
  bool _disposed = false;

  MutationObserver<TData, TVariables, TOnMutateResult> get observer =>
      _observer;

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
    _unsubscribe ??= _observer.subscribe((_) => notifyListeners());
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
    if (_disposed) {
      return;
    }
    _disposed = true;
    _unsubscribe?.call();
    _unsubscribe = null;
    super.dispose();
  }
}
