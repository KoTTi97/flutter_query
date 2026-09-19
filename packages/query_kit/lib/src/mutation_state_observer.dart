/// Cache-wide mutation selection, analogous to upstream's `useMutationState`.
library;

import 'filters.dart';
import 'listener_registry.dart';
import 'mutation.dart';
import 'query_client.dart';
import 'structural_sharing.dart';

/// Selects a value from each matching mutation, including concurrent runs
/// sharing one key. Mutation data is erased because filters span data types.
typedef MutationStateSelect<TSelected> = TSelected Function(
    Mutation<Object?, Object?, Object?> mutation);

/// [MutationStateSelect] over mutations of one type: what
/// [MutationStateObserver.typed] takes.
typedef TypedMutationStateSelect<TData, TVariables, TOnMutateResult, TSelected>
    = TSelected Function(Mutation<TData, TVariables, TOnMutateResult> mutation);

/// [filters] narrowed to the mutations that *are* a
/// `Mutation<TData, TVariables, TOnMutateResult>`, and [select] adapted to
/// the erased signature — the two halves of a typed selection, for the
/// binding's controller to share. A type argument left as `Object?` matches
/// anything, so `<Object?, SensorIntent, Object?>` is "every mutation whose
/// variables are a `SensorIntent`".
(MutationFilters, MutationStateSelect<TSelected>)
    typedMutationSelection<TData, TVariables, TOnMutateResult, TSelected>(
  MutationFilters filters,
  TypedMutationStateSelect<TData, TVariables, TOnMutateResult, TSelected>
      select,
) {
  final predicate = filters.predicate;
  return (
    MutationFilters(
      mutationKey: filters.mutationKey,
      exact: filters.exact,
      status: filters.status,
      predicate: (mutation) =>
          mutation is Mutation<TData, TVariables, TOnMutateResult> &&
          (predicate == null || predicate(mutation)),
    ),
    (mutation) =>
        select(mutation as Mutation<TData, TVariables, TOnMutateResult>),
  );
}

/// Observes selected mutation values in cache insertion order.
///
/// Subscribes to the cache only while it has listeners. Selection uses
/// structural sharing, so equivalent lists and maps do not notify again.
class MutationStateObserver<TSelected> {
  /// Creates a selection, readable immediately through [currentResult].
  MutationStateObserver(
    this._client, {
    MutationFilters filters = const MutationFilters(),
    required MutationStateSelect<TSelected> select,
  })  : _filters = filters,
        _select = select {
    _update(notify: false);
  }

  /// A selection over the mutations of one type, [select] receiving them
  /// typed — no cast to get at `state.variables`. Port-only
  /// (https://github.com/KoTTi97/flutter_query/issues/85); upstream's
  /// `useMutationState` select is untyped too.
  ///
  /// The types usually come from [select]'s parameter:
  ///
  /// ```dart
  /// MutationStateObserver.typed(
  ///   client,
  ///   filters: const MutationFilters(status: MutationStatus.pending),
  ///   select: (Mutation<Object?, SensorIntent, Object?> mutation) =>
  ///       mutation.state.variables!,
  /// );
  /// ```
  ///
  /// A later [setOptions] replaces filters and select with untyped ones.
  static MutationStateObserver<TSelected>
      typed<TData, TVariables, TOnMutateResult, TSelected>(
    QueryClient client, {
    MutationFilters filters = const MutationFilters(),
    required TypedMutationStateSelect<TData, TVariables, TOnMutateResult,
            TSelected>
        select,
  }) {
    final (typedFilters, typedSelect) = typedMutationSelection(filters, select);
    return MutationStateObserver<TSelected>(client,
        filters: typedFilters, select: typedSelect);
  }

  final QueryClient _client;
  MutationFilters _filters;
  MutationStateSelect<TSelected> _select;
  List<TSelected> _result = List<TSelected>.unmodifiable(<TSelected>[]);
  final ListenerRegistry<void Function(List<TSelected>)> _listeners =
      ListenerRegistry<void Function(List<TSelected>)>();
  void Function()? _unsubscribe;

  /// Whether the observer currently follows cache events.
  bool get hasListeners => _listeners.hasListeners;

  /// The selected values. Reads without listeners refresh from the cache.
  List<TSelected> get currentResult {
    if (!hasListeners) _update(notify: false);
    return _result;
  }

  /// Replaces filters and/or selection and immediately recomputes the result.
  void setOptions({
    MutationFilters? filters,
    MutationStateSelect<TSelected>? select,
  }) {
    _filters = filters ?? _filters;
    _select = select ?? _select;
    _update();
  }

  /// Registers a listener without delivering an initial snapshot.
  void Function() subscribe(void Function(List<TSelected>) listener) {
    if (!hasListeners) {
      _update(notify: false);
      _unsubscribe = _client.mutationCache.subscribe((_) => _update());
    }
    return _listeners.add(listener, onRemoved: () {
      if (!hasListeners) {
        _unsubscribe?.call();
        _unsubscribe = null;
      }
    });
  }

  void _update({bool notify = true}) {
    final next =
        _client.mutationCache.findAll(filters: _filters).map(_select).toList();
    final shared = replaceEqualDeep<List<TSelected>>(_result, next);
    if (identical(shared, _result)) return;
    _result = List<TSelected>.unmodifiable(shared);
    if (notify) {
      final result = _result;
      final revision = ++_resultRevision;
      _listeners.notify((listener) {
        if (revision == _resultRevision) listener(result);
      });
    }
  }

  int _resultRevision = 0;

  /// Removes all listeners and releases the cache subscription.
  void destroy() {
    _resultRevision++;
    _listeners.clear();
    _unsubscribe?.call();
    _unsubscribe = null;
  }
}
