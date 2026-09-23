/// Flutter's listenable adapter for cache-wide mutation selection. See
/// [MutationStateController].
library;

import 'package:flutter/foundation.dart';
import 'package:query_kit/query_kit.dart';

import 'controller_lifetime.dart';
import 'notify_gate.dart';

/// A value selected from every mutation in the cache that matches the
/// filters, as a [ValueListenable] of a list — one entry per mutation, in
/// the order they were added.
///
/// What it is for: showing mutations from somewhere other than where they
/// were started — a "saving…" badge in the app bar, a pending row in a list
/// for a write started on another screen, a count of writes in flight. It is
/// also the mutation side's answer to [IsFetchingController]: a controller
/// filtered on `MutationStatus.pending` counts the mutations running.
///
/// ```dart
/// final saving = MutationStateController<int>(
///   client,
///   filters: const MutationFilters(status: MutationStatus.pending),
///   select: (mutation) => 1,
/// );
///
/// ValueListenableBuilder<List<int>>(
///   valueListenable: saving,
///   builder: (context, pending, _) => pending.isEmpty
///       ? const SizedBox()
///       : Text('Saving ${pending.length}…'),
/// );
///
/// // When done:
/// saving.dispose();
/// ```
///
/// Subscribed to the mutation cache only while something listens, and
/// listeners are told only when the selection changed element by element.
/// [select] runs over every matching mutation on every cache change, so keep
/// it cheap. Use [MutationStateController.typed] to select from mutations of
/// one type, with their variables and data typed.
///
/// {@category Collections}
class MutationStateController<TSelected> extends ChangeNotifier
    implements ValueListenable<List<TSelected>> {
  /// Creates a selection over [client]'s mutation cache.
  MutationStateController(
    QueryClient client, {
    MutationFilters filters = const MutationFilters(),
    required MutationStateSelect<TSelected> select,
  }) : this._(
          client,
          MutationStateObserver<TSelected>(client,
              filters: filters, select: select),
        );

  MutationStateController._(this.client, this._observer);

  /// A selection over the mutations of one type, [select] receiving them
  /// typed — see `MutationStateObserver.typed`. The types usually come from
  /// [select]'s parameter, and a type left as `Object?` matches anything.
  ///
  /// ```dart
  /// final pendingRenames = MutationStateController.typed(
  ///   client,
  ///   filters: const MutationFilters(status: MutationStatus.pending),
  ///   // The parameter's type is the filter: every mutation whose variables
  ///   // are a String, and `variables` needs no cast.
  ///   select: (Mutation<Object?, String, Object?> mutation) =>
  ///       mutation.state.variables!,
  /// );
  /// ```
  ///
  /// The type test stays through a later [setOptions], whatever filters and
  /// select it passes.
  static MutationStateController<TSelected>
      typed<TData, TVariables, TOnMutateResult, TSelected>(
    QueryClient client, {
    MutationFilters filters = const MutationFilters(),
    required TypedMutationStateSelect<TData, TVariables, TOnMutateResult,
            TSelected>
        select,
  }) =>
          MutationStateController<TSelected>._(
            client,
            MutationStateObserver.typed<TData, TVariables, TOnMutateResult,
                TSelected>(client, filters: filters, select: select),
          );

  /// The client whose mutations are selected.
  final QueryClient client;
  final MutationStateObserver<TSelected> _observer;

  /// Subscribed while listened to, and never told twice about the same
  /// selection — see [ControllerLifetime]. The gate is element-wise, because
  /// the value is a list — though the selection is structurally shared, so an
  /// unchanged one is usually the *same* list. A `MutationStateObserver` has
  /// no first notification to re-enter from, so the lifetime's reentrancy
  /// guard never fires here; it is shared for the drop-the-handle check.
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

  /// Replaces the filters and/or selector, keeping the same client. Either
  /// left `null` stays as it was. The selection is recomputed at once, and
  /// listeners are told when it changed.
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
