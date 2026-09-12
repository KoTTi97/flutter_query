/// Flutter's listenable adapter for cache-wide mutation selection.
library;

import 'package:flutter/foundation.dart';
import 'package:query_kit/query_kit.dart';

import 'controller_lifetime.dart';
import 'notify_gate.dart';

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

  /// Subscribed while listened to, and never told twice about the same
  /// selection — see [ControllerLifetime]. The gate is element-wise, because
  /// the value is a list — though the selection is structurally shared, so an
  /// unchanged one is usually the *same* list.
  ///
  /// This controller is the one that had neither the reentrancy guard nor the
  /// drop-the-handle check; sharing the lifetime is what gave it both, and
  /// nothing in its behaviour moved, because a `MutationStateObserver` has no
  /// first notification to re-enter from (C15, and see the notes' C50 row).
  late final ControllerLifetime<List<TSelected>> _life =
      ControllerLifetime<List<TSelected>>(
    gate: NotifyGate.elementWise<TSelected>(),
    read: () => value,
    subscribe: (deliver) => _observer.subscribe(
      (_) => client.notifyManager.schedule(deliver),
    ),
    hasListeners: () => hasListeners,
    notify: notifyListeners,
  );

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
