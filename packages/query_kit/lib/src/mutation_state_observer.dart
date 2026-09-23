/// Cache-wide mutation selection.
library;

import 'filters.dart';
import 'listener_registry.dart';
import 'mutation.dart';
import 'query_client.dart';
import 'structural_sharing.dart';

/// Selects a value from each matching mutation, including concurrent runs
/// sharing one key. The mutation's type arguments are erased because filters
/// span data types; [TypedMutationStateSelect] is the typed form.
///
/// {@category Observers}
typedef MutationStateSelect<TSelected> = TSelected Function(
    Mutation<Object?, Object?, Object?> mutation);

/// [MutationStateSelect] over mutations of one type: what
/// [MutationStateObserver.typed] takes.
///
/// {@category Observers}
typedef TypedMutationStateSelect<TData, TVariables, TOnMutateResult, TSelected>
    = TSelected Function(Mutation<TData, TVariables, TOnMutateResult> mutation);

/// Watches a selection over every mutation in the cache, in submission
/// order — not just the ones one observer started.
///
/// Use it where one widget needs to know about mutations started elsewhere:
/// the variables of every pending "add todo" to show optimistic rows, a
/// count of saves in flight, the last error of any upload. `filters` pick
/// the mutations (by key, status or predicate) and `select` turns each into
/// a value; [currentResult] is the list of those values.
///
/// ```dart
/// final pendingTitles = MutationStateObserver<Object?>(
///   client,
///   filters: MutationFilters(
///     mutationKey: QueryKey(['todos', 'add']),
///     status: MutationStatus.pending,
///   ),
///   select: (mutation) => mutation.state.variables,
/// );
/// final unsubscribe = pendingTitles.subscribe(print);
/// // Later:
/// unsubscribe();
/// pendingTitles.destroy();
/// ```
///
/// [typed] gives `select` the mutations with their declared types.
///
/// It subscribes to the cache only while it has listeners. Selection uses
/// structural sharing, so equivalent lists and maps do not notify again.
/// (TanStack Query: `useMutationState`.)
///
/// {@category Observers}
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
  /// typed — no cast to get at `state.variables`. (TanStack Query's
  /// `useMutationState` has only the untyped form.)
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
  /// only — cast one to its declared type to read it typed. The type test
  /// runs first, so a predicate in [filters] only ever sees mutations of the
  /// declared types and may cast to them.
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
    var filters = _filters;
    if (typeTest != null) {
      // The type test guards the caller's predicate, not the other way
      // round: a predicate written for the declared type reads it, and run
      // on a mutation of another type it threw out of the cache event.
      final predicate = filters.predicate;
      filters = MutationFilters(
        mutationKey: filters.mutationKey,
        exact: filters.exact,
        status: filters.status,
        predicate: (mutation) =>
            typeTest(mutation) && (predicate == null || predicate(mutation)),
      );
    }
    final matching = _client.mutationCache.findAll(filters: filters);
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
