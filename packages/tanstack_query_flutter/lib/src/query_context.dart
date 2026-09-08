/// `context.query(...)`: read a query straight from a `BuildContext`.
///
/// One of four equal call styles
/// (https://github.com/KoTTi97/flutter_query/issues/21). The flattest of them —
/// it works in a `StatelessWidget` — and the only one whose rebuilds are
/// per-key: when a query changes, only the widgets that read *that* key rebuild.
///
/// It is also the one with the most machinery behind the curtain. The mechanism
/// is Flutter's own, the same one `provider` uses for `context.watch`:
/// `InheritedElement` hands us `updateDependencies` when a widget reads, and
/// `removeDependent` when one unmounts, so the observers can be reference
/// counted exactly rather than guessed at.
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
  /// The observer is shared by every widget reading the same key, and released
  /// once the last of them stops reading it — including when a widget simply
  /// reads a *different* key on a later build.
  QueryResult<TData> query<TData>(
    QueryObserverOptions<TData, TData> options,
  ) =>
      selectQuery<TData, TData>(options);

  /// [query] for a query with a `select`.
  QueryResult<TData> selectQuery<TQueryData, TData>(
    QueryObserverOptions<TQueryData, TData> options,
  ) {
    final element = _scopeElement(this);
    final key = options.queryKey!;
    final result =
        element.readQuery<TQueryData, TData>(options, this as Element);
    dependOnInheritedWidgetOfExactType<QueryScope>(aspect: key);
    return result;
  }

  /// A mutation owned by this widget.
  ///
  /// Mutations are not shared: each widget that asks gets its own, disposed
  /// when the widget unmounts. Pass [id] when one widget runs several.
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

class _QueryEntry {
  _QueryEntry(this.controller);

  final QueryController<Object?, Object?> controller;
  final Set<Element> readers = <Element>{};
  void Function()? detach;
}

class _ReaderKeys {
  _ReaderKeys(this.epoch);

  int epoch;

  /// Keys this reader has read during [epoch].
  final Set<QueryKey> current = <QueryKey>{};

  /// Keys it held during the previous epoch, still to be reconciled.
  Set<QueryKey> pending = <QueryKey>{};
}

/// Keeps one observer per [QueryKey] alive for as long as some mounted widget
/// is reading it.
class QueryScopeElement extends InheritedElement {
  QueryScopeElement(QueryScope super.widget);

  final Map<QueryKey, _QueryEntry> _entries = <QueryKey, _QueryEntry>{};
  final Map<Element, _ReaderKeys> _readers = <Element, _ReaderKeys>{};
  final Map<Element, Map<Object, MutationController<Object?, Object?, Object?>>>
      _mutations =
      <Element, Map<Object, MutationController<Object?, Object?, Object?>>>{};

  int _epoch = 0;
  bool _sweepScheduled = false;

  QueryClient get client => (widget as QueryScope).client;

  /// Creates or reuses the observer for [options], records that [reader] is
  /// reading it, and returns its current result.
  QueryResult<TData> readQuery<TQueryData, TData>(
    QueryObserverOptions<TQueryData, TData> options,
    Element reader,
  ) {
    final key = options.queryKey!;
    _startEpochFor(reader);

    final existing = _entries[key];
    final _QueryEntry entry;
    if (existing != null) {
      entry = existing;
      // Unconditional, as upstream re-applies options on every render.
      (entry.controller as QueryController<TQueryData, TData>)
          .setOptions(options);
    } else {
      final controller = QueryController<TQueryData, TData>(client, options);
      entry = _QueryEntry(controller as QueryController<Object?, Object?>);
      void onChanged() => _notifyReadersOf(key);
      controller.addListener(onChanged);
      entry.detach = () => controller.removeListener(onChanged);
      _entries[key] = entry;
    }

    entry.readers.add(reader);
    _readers[reader]!.current.add(key);

    return (entry.controller as QueryController<TQueryData, TData>).value;
  }

  /// A mutation controller owned by [reader].
  MutationController<TData, TVariables, TOnMutateResult>
      readMutation<TData, TVariables, TOnMutateResult>(
    MutationOptions<TData, TVariables, TOnMutateResult> options,
    Element reader,
    Object? id,
  ) {
    final identity =
        id ?? options.mutationKey ?? (TData, TVariables, options.mutationFn);
    final owned = _mutations.putIfAbsent(
      reader,
      () => <Object, MutationController<Object?, Object?, Object?>>{},
    );

    final existing = owned[identity];
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
    owned[identity] =
        controller as MutationController<Object?, Object?, Object?>;
    return controller;
  }

  void _startEpochFor(Element reader) {
    final state = _readers.putIfAbsent(reader, () => _ReaderKeys(_epoch));
    if (state.epoch != _epoch) {
      // First read of a new frame: what it held before becomes provisional,
      // and whatever it does not read again this frame is released in the
      // sweep. Without this a screen that switches from one key to another
      // would stay subscribed to the key it no longer shows.
      state
        ..epoch = _epoch
        ..pending = <QueryKey>{...state.pending, ...state.current}
        ..current.clear();
    }
    _scheduleSweep();
  }

  void _notifyReadersOf(QueryKey key) {
    final entry = _entries[key];
    if (entry == null) {
      return;
    }
    for (final reader in List<Element>.of(entry.readers)) {
      if (reader.mounted) {
        reader.markNeedsBuild();
      }
    }
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

  /// Releases keys a reader stopped reading, then drops observers nobody reads.
  void _sweep() {
    for (final entry in _readers.entries) {
      final state = entry.value;
      final released = state.pending.difference(state.current);
      state.pending = <QueryKey>{};
      for (final key in released) {
        _entries[key]?.readers.remove(entry.key);
      }
    }

    _entries.removeWhere((_, entry) {
      if (entry.readers.isNotEmpty) {
        return false;
      }
      entry.detach?.call();
      entry.controller.dispose();
      return true;
    });

    _epoch++;
  }

  @override
  void removeDependent(Element dependent) {
    super.removeDependent(dependent);
    _release(dependent);
  }

  void _release(Element dependent) {
    final state = _readers.remove(dependent);
    if (state != null) {
      for (final key in <QueryKey>{...state.current, ...state.pending}) {
        _entries[key]?.readers.remove(dependent);
      }
    }

    final owned = _mutations.remove(dependent);
    if (owned != null) {
      for (final controller in owned.values) {
        controller.dispose();
      }
    }

    _scheduleSweep();
  }

  @override
  void unmount() {
    for (final entry in _entries.values) {
      entry.detach?.call();
      entry.controller.dispose();
    }
    _entries.clear();
    _readers.clear();
    for (final owned in _mutations.values) {
      for (final controller in owned.values) {
        controller.dispose();
      }
    }
    _mutations.clear();
    super.unmount();
  }
}
