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

/// Observes selected mutation values in cache insertion order.
///
/// Subscribes to the cache only while it has listeners. Selection uses
/// structural sharing, so equivalent lists and maps do not notify again.
class MutationStateObserver<TSelected> {
  /// Creates a selection, readable immediately through [currentResult].
  MutationStateObserver(
    QueryClient client, {
    MutationFilters filters = const MutationFilters(),
    required MutationStateSelect<TSelected> select,
  }) : this._(client, filters, select, null);

  MutationStateObserver._(
    this._client,
    this._filters,
    this._select,
    this._typeTest,
  ) {
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
  /// The filter is a mutation's *declared* type arguments, not the runtime
  /// type of its variables: one built from options whose types were never
  /// written or inferred is a `Mutation<Object?, Object?, Object?>` and drops
  /// out silently.
  ///
  /// The type test belongs to the observer, not to [filters]: it applies on
  /// top of whatever filters a later [setOptions] passes, so the selection
  /// only ever holds mutations of the declared types. A select passed to
  /// [setOptions] has the erased signature, and receives those mutations
  /// only — cast one to its declared type to read it typed. It used to live
  /// in the filters, and `setOptions(filters: …)` alone dropped it while the
  /// casting select stayed: the next mutation of another type threw a
  /// `TypeError` out of `setOptions`, and then out of every cache event
  /// (release review, 2026-09-23, L4-1).
  static MutationStateObserver<TSelected> typed<TData, TVariables,
          TOnMutateResult, TSelected>(
    QueryClient client, {
    MutationFilters filters = const MutationFilters(),
    required TypedMutationStateSelect<TData, TVariables, TOnMutateResult,
            TSelected>
        select,
  }) =>
      MutationStateObserver<TSelected>._(
        client,
        filters,
        (mutation) =>
            select(mutation as Mutation<TData, TVariables, TOnMutateResult>),
        (mutation) => mutation is Mutation<TData, TVariables, TOnMutateResult>,
      );

  final QueryClient _client;
  MutationFilters _filters;
  MutationStateSelect<TSelected> _select;

  /// The declared-type test of a [typed] selection, `null` for an untyped
  /// one. Fixed for the observer's life.
  final bool Function(Mutation<Object?, Object?, Object?> mutation)? _typeTest;
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
  /// A [typed] observer keeps its type test — see there.
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
    final typeTest = _typeTest;
    var matching = _client.mutationCache.findAll(filters: _filters);
    if (typeTest != null) {
      matching = matching.where(typeTest).toList();
    }
    final next = matching.map(_select).toList();
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
