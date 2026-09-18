/// Flutter's listenable adapter for the number of queries fetching.
library;

import 'package:flutter/foundation.dart';
import 'package:query_kit/query_kit.dart';

import 'controller_lifetime.dart';
import 'notify_gate.dart';

/// How many queries matching the filters are fetching right now — upstream's
/// `useIsFetching`, the value behind a global loading indicator. Subscribed
/// to the query cache only while something listens, and it notifies only
/// when the count changes (final review, 2026-09-18, B-1).
///
/// `QueryClient.isFetching` is the same count as a snapshot; the mutation
/// side's twin is a `MutationStateController` filtered on
/// `MutationStatus.pending`.
class IsFetchingController extends ChangeNotifier
    implements ValueListenable<int> {
  /// Creates a count over [client]'s query cache, narrowed by [filters].
  IsFetchingController(
    this.client, {
    this.filters = const QueryFilters(),
  });

  /// The client whose queries are counted.
  final QueryClient client;

  /// Which queries are counted — all of them by default. Fixed for the
  /// controller's life: another set of filters is another controller.
  final QueryFilters filters;

  late final ControllerLifetime<int> _life = ControllerLifetime<int>(
    gate: NotifyGate<int>.byValue(),
    read: () => value,
    subscribe: (deliver) => client.queryCache.subscribe(
      (_) => client.notifyManager.schedule(deliver),
    ),
    hasListeners: () => hasListeners,
    notify: notifyListeners,
  );

  @override
  int get value => client.isFetching(filters: filters);

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
    super.dispose();
  }
}
