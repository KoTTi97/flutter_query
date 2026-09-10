/// Flutter's listenable adapter for cache-wide mutation selection.
library;

import 'package:flutter/foundation.dart';
import 'package:tanstack_query_core/tanstack_query_core.dart';

/// Selected mutation values, subscribed only while something listens.
class MutationStateController<TSelected> extends ChangeNotifier
    implements ValueListenable<List<TSelected>> {
  /// Creates a selection over [client]'s mutation cache.
  MutationStateController(
    this.client, {
    MutationFilters filters = const MutationFilters(),
    required MutationStateSelect<TSelected> select,
  }) : _observer = MutationStateObserver<TSelected>(client,
            filters: filters, select: select);

  /// The client whose mutations are selected.
  final QueryClient client;
  final MutationStateObserver<TSelected> _observer;
  void Function()? _unsubscribe;
  bool _disposed = false;

  @override
  List<TSelected> get value => _observer.currentResult;

  /// Replaces the filters and/or selector, keeping the same client.
  void setOptions({
    MutationFilters? filters,
    MutationStateSelect<TSelected>? select,
  }) =>
      _observer.setOptions(filters: filters, select: select);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    if (_unsubscribe != null || _disposed) return;
    _unsubscribe = _observer.subscribe((_) {
      client.notifyManager.schedule(() {
        if (!_disposed && hasListeners) notifyListeners();
      });
    });
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
