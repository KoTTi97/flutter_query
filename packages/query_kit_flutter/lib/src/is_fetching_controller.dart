/// Flutter's listenable adapter for the number of queries fetching. See
/// [IsFetchingController].
library;

import 'package:flutter/foundation.dart';
import 'package:query_kit/query_kit.dart';

import 'controller_lifetime.dart';
import 'notify_gate.dart';

/// How many queries matching the filters are fetching right now, as a
/// [ValueListenable] — the value behind a global loading indicator.
///
/// ```dart
/// final fetching = IsFetchingController(client);
///
/// ValueListenableBuilder<int>(
///   valueListenable: fetching,
///   builder: (context, count, _) => count > 0
///       ? const LinearProgressIndicator()
///       : const SizedBox.shrink(),
/// );
///
/// // Only the task queries:
/// final fetchingTasks = IsFetchingController(
///   client,
///   filters: QueryFilters(queryKey: tasksKey),
/// );
///
/// // When done:
/// fetching.dispose();
/// fetchingTasks.dispose();
/// ```
///
/// Subscribed to the query cache only while something listens, and it
/// notifies only when the count changes. A background refetch counts, so
/// the indicator also shows while stale data is refreshed.
///
/// `QueryClient.isFetching` is the same count as a one-off snapshot. The
/// mutation side's equivalent — how many mutations are running — is a
/// [MutationStateController] filtered on `MutationStatus.pending`, whose
/// list length is the count.
///
/// {@category Collections}
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
