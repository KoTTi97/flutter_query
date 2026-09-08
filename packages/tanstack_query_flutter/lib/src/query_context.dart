/// `context.query(...)`: read a query straight from a `BuildContext`.
///
/// One of four equal call styles
/// (https://github.com/KoTTi97/flutter_query/issues/21). The flattest of them —
/// it works in a `StatelessWidget` — and its rebuilds are per-reader: when a
/// query changes, only the widgets that read *that* query rebuild.
///
/// It is also the one with the most machinery behind the curtain. The mechanism
/// is Flutter's own, the same one `provider` uses for `context.watch`:
/// `InheritedElement` hands us `removeDependent` when a reading widget
/// unmounts, so the observers it held can be released exactly rather than
/// guessed at.
///
/// **Identity.** Every reading widget gets observers of its own; what is shared
/// is the *query* in the cache, which the core already deduplicates. Two widgets
/// reading the same key with different `select`s, `enabled`s or polling
/// intervals therefore do not fight over one observer. Within a single widget
/// an observer is identified by key and types — read the same key twice with
/// different selectors of the same output type and pass [id] to tell them
/// apart.
///
/// **Release.** A key the widget read last build but not this one is released
/// after the frame. A widget that stops calling `context.query` *altogether*
/// gives no signal a `BuildContext` can see, so its last observers stay until
/// it unmounts; put a conditional read in its own small widget, and the
/// condition becomes that widget's presence in the tree.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:tanstack_query_core/tanstack_query_core.dart';

import 'query_controller.dart';

/// Reading queries and mutations from a [BuildContext].
extension QueryContext on BuildContext {
  /// Subscribes this widget to [options]'s query and returns its current
  /// result.
  ///
  /// ```dart
  /// final sensor = context.query(sensorQuery(id));
  /// ```
  ///
  /// The observer is this widget's, released once the widget stops reading the
  /// key — including when it simply reads a *different* key on a later build —
  /// or unmounts. [id] tells apart two reads of one key in the same widget.
  QueryResult<TData> query<TData>(
    QueryObserverOptions<TData, TData> options, {
    Object? id,
  }) =>
      selectQuery<TData, TData>(options, id: id);

  /// [query] for a query with a `select`.
  QueryResult<TData> selectQuery<TQueryData, TData>(
    QueryObserverOptions<TQueryData, TData> options, {
    Object? id,
  }) {
    final element = _scopeElement(this);
    final result = element.readQuery<TQueryData, TData>(
      options,
      this as Element,
      id,
    );
    dependOnInheritedWidgetOfExactType<QueryScope>();
    return result;
  }

  /// [query] for an infinite query. Returns the controller rather than the
  /// result, because paging lives on it.
  ///
  /// ```dart
  /// final feed = context.infiniteQuery(feedQuery());
  /// if (feed.hasNextPage) feed.fetchNextPage();
  /// ```
  InfiniteQueryController<TPageData, TPageParam, TData>
      infiniteQuery<TPageData, TPageParam, TData>(
    InfiniteQueryObserverOptions<TPageData, TPageParam, TData> options, {
    Object? id,
  }) {
    final element = _scopeElement(this);
    final controller = element.readInfiniteQuery<TPageData, TPageParam, TData>(
      options,
      this as Element,
      id,
    );
    dependOnInheritedWidgetOfExactType<QueryScope>();
    return controller;
  }

  /// A mutation owned by this widget.
  ///
  /// Mutations are not shared: each widget that asks gets its own, disposed
  /// when the widget unmounts. One is identified by [id], else by the options'
  /// `mutationKey`, else by its three types — so pass [id] when one widget
  /// runs two mutations of the same shape.
  MutationController<TData, TVariables, TOnMutateResult>
      mutation<TData, TVariables, TOnMutateResult>(
    MutationOptions<TData, TVariables, TOnMutateResult> options, {
    Object? id,
  }) {
    final element = _scopeElement(this);
    final controller = element.readMutation<TData, TVariables, TOnMutateResult>(
      options,
      this as Element,
      id,
    );
    dependOnInheritedWidgetOfExactType<QueryScope>();
    return controller;
  }

  static QueryScopeElement _scopeElement(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<QueryScope>();
    assert(
      element != null,
      'No QueryClientProvider found above this widget, so context.query() has '
      'nowhere to keep its observers.',
    );
    return element! as QueryScopeElement;
  }
}

/// The scope `context.query` reads through. Installed by
/// `QueryClientProvider`; you never place one yourself.
class QueryScope extends InheritedWidget {
  const QueryScope({super.key, required this.client, required super.child});

  final QueryClient client;

  @override
  bool updateShouldNotify(QueryScope oldWidget) => oldWidget.client != client;

  @override
  InheritedElement createElement() => QueryScopeElement(this);
}

/// A query observer one widget holds, and how to let it go.
class _QueryEntry {
  _QueryEntry(this.controller, this.detach);

  final ChangeNotifier controller;
  final void Function() detach;

  void dispose() {
    detach();
    controller.dispose();
  }
}

/// Everything one reading widget holds.
class _Reader {
  _Reader(this.epoch);

  int epoch;

  /// Observers by identity: `(key, types…, id)`.
  final Map<Object, _QueryEntry> queries = <Object, _QueryEntry>{};

  /// Identities read during [epoch].
  Set<Object> current = <Object>{};

  /// Identities held during the previous epoch, still to be reconciled.
  Set<Object> pending = <Object>{};

  final Map<Object, MutationController<Object?, Object?, Object?>> mutations =
      <Object, MutationController<Object?, Object?, Object?>>{};

  void dispose() {
    for (final entry in queries.values) {
      entry.dispose();
    }
    queries.clear();
    for (final controller in mutations.values) {
      controller.dispose();
    }
    mutations.clear();
  }
}

/// Keeps each reading widget's observers alive for as long as it reads them.
class QueryScopeElement extends InheritedElement {
  QueryScopeElement(QueryScope super.widget);

  final Map<Element, _Reader> _readers = <Element, _Reader>{};

  int _epoch = 0;
  bool _sweepScheduled = false;

  QueryClient get client => (widget as QueryScope).client;

  /// Creates or reuses [reader]'s observer for [options] and returns its
  /// current result.
  QueryResult<TData> readQuery<TQueryData, TData>(
    QueryObserverOptions<TQueryData, TData> options,
    Element reader,
    Object? id,
  ) {
    final identity = (options.queryKey!, TQueryData, TData, id);
    final controller = _controllerFor<QueryController<TQueryData, TData>>(
      reader,
      identity,
      () => QueryController<TQueryData, TData>(client, options),
    );
    // Unconditional, as upstream re-applies options on every render: the
    // observer itself decides whether anything actually changed.
    controller.setOptions(options);
    return controller.value;
  }

  /// The infinite twin of [readQuery].
  InfiniteQueryController<TPageData, TPageParam, TData>
      readInfiniteQuery<TPageData, TPageParam, TData>(
    InfiniteQueryObserverOptions<TPageData, TPageParam, TData> options,
    Element reader,
    Object? id,
  ) {
    final identity = (options.queryKey, TPageData, TPageParam, TData, id);
    final controller =
        _controllerFor<InfiniteQueryController<TPageData, TPageParam, TData>>(
      reader,
      identity,
      () => InfiniteQueryController<TPageData, TPageParam, TData>(
        client,
        options,
      ),
    );
    controller.setInfiniteOptions(options);
    return controller;
  }

  C _controllerFor<C extends ChangeNotifier>(
    Element reader,
    Object identity,
    C Function() create,
  ) {
    final state = _startEpochFor(reader);
    final existing = state.queries[identity];
    final C controller;
    if (existing != null) {
      controller = existing.controller as C;
    } else {
      controller = create();
      void onChanged() {
        if (reader.mounted) {
          reader.markNeedsBuild();
        }
      }

      controller.addListener(onChanged);
      state.queries[identity] =
          _QueryEntry(controller, () => controller.removeListener(onChanged));
    }
    state.current.add(identity);
    return controller;
  }

  /// A mutation controller owned by [reader].
  MutationController<TData, TVariables, TOnMutateResult>
      readMutation<TData, TVariables, TOnMutateResult>(
    MutationOptions<TData, TVariables, TOnMutateResult> options,
    Element reader,
    Object? id,
  ) {
    // Never the function itself: a closure built in `build` is a new object
    // every build, and a controller keyed on it would be replaced — idle
    // again — by the very rebuild its own result caused.
    final identity =
        id ?? options.mutationKey ?? (TData, TVariables, TOnMutateResult);
    final state = _readers.putIfAbsent(reader, () => _Reader(_epoch));

    final existing = state.mutations[identity];
    if (existing != null) {
      final controller = existing
          as MutationController<TData, TVariables, TOnMutateResult>
        ..setOptions(options);
      return controller;
    }

    final controller =
        MutationController<TData, TVariables, TOnMutateResult>(client, options);
    controller.addListener(() {
      if (reader.mounted) {
        reader.markNeedsBuild();
      }
    });
    state.mutations[identity] =
        controller as MutationController<Object?, Object?, Object?>;
    return controller;
  }

  _Reader _startEpochFor(Element reader) {
    final state = _readers.putIfAbsent(reader, () => _Reader(_epoch));
    if (state.epoch != _epoch) {
      // First read of a new frame: what it held before becomes provisional,
      // and whatever it does not read again this frame is released in the
      // sweep. Without this a screen that switches from one key to another
      // would stay subscribed to the key it no longer shows.
      state
        ..epoch = _epoch
        ..pending = <Object>{...state.pending, ...state.current}
        ..current = <Object>{};
    }
    _scheduleSweep();
    return state;
  }

  void _scheduleSweep() {
    if (_sweepScheduled) {
      return;
    }
    _sweepScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _sweepScheduled = false;
      _sweep();
    });
  }

  /// Releases the observers a reader stopped reading.
  void _sweep() {
    for (final state in _readers.values) {
      final released = state.pending.difference(state.current);
      state.pending = <Object>{};
      for (final identity in released) {
        state.queries.remove(identity)?.dispose();
      }
    }
    _epoch++;
  }

  @override
  void removeDependent(Element dependent) {
    super.removeDependent(dependent);
    _readers.remove(dependent)?.dispose();
  }

  @override
  void update(QueryScope newWidget) {
    if ((widget as QueryScope).client != newWidget.client) {
      // Every observer belongs to the old client. The readers are told the
      // scope changed (`updateShouldNotify`), rebuild, and recreate what they
      // read on the new one.
      _disposeAll();
    }
    super.update(newWidget);
  }

  void _disposeAll() {
    for (final state in _readers.values) {
      state.dispose();
    }
    _readers.clear();
  }

  @override
  void unmount() {
    _disposeAll();
    super.unmount();
  }
}
