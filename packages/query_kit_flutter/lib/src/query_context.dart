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
/// apart. An [id] is then the read's identity: a read that carries one keeps
/// its observer when its key changes, as upstream's one-observer-per-call-site
/// does, which is what `PlaceholderData.compute((previous, _) => previous)`
/// needs to show the previous key's data while the next loads. A mutation is
/// identified by [id] or else by its `mutationKey`, together with its three
/// types.
///
/// **Release.** A key the widget read last build but not this one is released
/// after the frame — a mutation likewise, so one whose [id] changed between
/// builds does not outlive the build that stopped reading it. A widget that
/// stops calling `context.query` *altogether* gives no signal a
/// `BuildContext` can see, so its last observers stay until it unmounts; put a
/// conditional read in its own small widget, and the condition becomes that
/// widget's presence in the tree.
///
/// **Only in `build`.** The read is reconciled against what the widget read
/// in its last build; a `context.query` from a tap handler creates an observer
/// that is only matched up on the next build. Read in `build`, act on the
/// result from the handler.
///
/// **The client is always the provider's.** This style has no `client:`
/// parameter, on purpose: a `BuildContext` names exactly one provider, and a
/// second way to say which client would only leave readers wondering which
/// one won. For a client that is not the provider's, the builders and the
/// controllers take one directly.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:query_kit/query_kit.dart';

import 'query_controller.dart';
import 'repeat_read.dart';

/// Reading queries and mutations from a [BuildContext].
extension QueryContext on BuildContext {
  /// Subscribes this widget to [options]'s query and returns its current
  /// result.
  ///
  /// ```dart
  /// final task = context.query(taskQuery(id));
  /// ```
  ///
  /// The observer is this widget's, released once the widget stops reading the
  /// key — including when it simply reads a *different* key on a later build —
  /// or unmounts. With an [id] the observer follows a changed key instead;
  /// [id] also tells apart two reads of one key in the same widget.
  ///
  /// Always on the provider's client; see the library doc on why there is no
  /// `client:` here. Options built inline are re-applied on every build, as
  /// upstream re-applies them on every render; the observer decides what, if
  /// anything, actually changed.
  QueryResult<TData> query<TData>(
    QueryObserverOptions<TData> options, {
    Object? id,
  }) =>
      _read<TData, TData>(options, id);

  /// [query] for a query with a `select`: a [QuerySelectOptions], whose
  /// required `select` anchors [TData] (ADR-0001).
  QueryResult<TData> selectQuery<TQueryData, TData>(
    QuerySelectOptions<TQueryData, TData> options, {
    Object? id,
  }) =>
      _read<TQueryData, TData>(options, id);

  QueryResult<TData> _read<TQueryData, TData>(
    QueryObserverOptionsBase<TQueryData, TData> options,
    Object? id,
  ) {
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
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options, {
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
  /// Mutations are not shared: each widget that asks gets its own, released
  /// when the widget stops reading it — the way a query is — or unmounts. One
  /// is identified by [id], else by the options' `mutationKey`, each together
  /// with its three types; without either, by the types alone — so pass [id]
  /// when one widget runs two mutations of the same shape.
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
    if (element == null) {
      // In every build mode: the null check it would otherwise become in
      // release says nothing about what is missing.
      throw FlutterError(
        'No QueryClientProvider found above this widget, so context.query() '
        'has nowhere to keep its observers. Wrap your app (or the subtree '
        'that uses queries) in QueryClientProvider(client: …).',
      );
    }
    return element as QueryScopeElement;
  }
}

/// The scope `context.query` reads through. Installed by
/// `QueryClientProvider`; you never place one yourself. Not public API: the
/// package barrel hides it (an `@internal` annotation would need `meta`,
/// which Flutter 3.27's `foundation` does not yet re-export).
class QueryScope extends InheritedWidget {
  /// Placed by `QueryClientProvider` around its child; nothing else
  /// constructs one.
  const QueryScope({super.key, required this.client, required super.child});

  /// The provider's client, on which every observer read through this scope
  /// is created. A new client is what makes the scope notify its readers.
  final QueryClient client;

  @override
  bool updateShouldNotify(QueryScope oldWidget) => oldWidget.client != client;

  @override
  InheritedElement createElement() => QueryScopeElement(this);
}

/// One controller a widget holds — a query's or a mutation's — and how to let
/// it go.
class _Entry {
  _Entry(this.controller, this.reader) {
    controller.addListener(_onChanged);
  }

  final ValueListenable<Object?> controller;
  final Element reader;

  /// The value the last build read. A notification that carries the same
  /// value is not worth a rebuild: the first build reads the result straight
  /// after the subscribe started the fetch, and the observer's notification
  /// about that very fetch lands after the frame (fourth review, 2026-09-09).
  Object? built;

  /// What [observedStateOf] said when [built] was recorded: the result for
  /// every controller but an infinite query's, which keeps its paging flags
  /// beside the result (third review, 2026-09-10).
  Object? builtState;

  /// Reads the current value and remembers it as this build's, both halves.
  T read<T>() {
    builtState = observedStateOf(controller);
    return (built = controller.value) as T;
  }

  void _onChanged() {
    if (reader.mounted && observedStateOf(controller) != builtState) {
      reader.markNeedsBuild();
    }
  }

  void dispose() {
    controller.removeListener(_onChanged);
    (controller as ChangeNotifier).dispose();
  }
}

/// Everything one reading widget holds.
class _Reader {
  _Reader(this.reader, this.epoch);

  /// The widget doing the reading.
  final Element reader;

  /// Set when Flutter said this element stopped depending on the scope, and
  /// cleared again the moment it reads. A deactivated element can come back
  /// in the same frame — that is what moving a `GlobalKey` subtree is — so
  /// the flag is a question the post-frame sweep answers, not an answer in
  /// itself (third review, 2026-09-10).
  bool detached = false;

  int epoch;

  /// Controllers by identity: `(key, types…)` for a query without an `id`,
  /// `(#query, types…, id)` for one with — so a read that carries an `id`
  /// keeps its observer across a key change — and `(#mutation, id or key,
  /// types…)` for a mutation.
  final Map<Object, _Entry> entries = <Object, _Entry>{};

  /// Identities read during [epoch].
  Set<Object> current = <Object>{};

  /// Identities held during the previous epoch, still to be reconciled.
  Set<Object> pending = <Object>{};

  void dispose() {
    for (final entry in entries.values) {
      entry.dispose();
    }
    entries.clear();
  }
}

/// Keeps each reading widget's observers alive for as long as it reads them.
/// Not public API; hidden from the barrel like [QueryScope].
class QueryScopeElement extends InheritedElement {
  /// Created by [QueryScope.createElement]; holds every reading widget's
  /// observers for as long as the scope is mounted.
  QueryScopeElement(QueryScope super.widget);

  final Map<Element, _Reader> _readers = <Element, _Reader>{};

  int _epoch = 0;
  bool _sweepScheduled = false;

  /// The scope's current client — the one every observer created from here on
  /// runs on. When it changes, [update] has already released the observers
  /// that belonged to the old one.
  QueryClient get client => (widget as QueryScope).client;

  /// Creates or reuses [reader]'s observer for [options] and returns its
  /// current result.
  QueryResult<TData> readQuery<TQueryData, TData>(
    QueryObserverOptionsBase<TQueryData, TData> options,
    Element reader,
    Object? id,
  ) {
    final identity = id == null
        ? (options.queryKey, TQueryData, TData)
        : (#query, TQueryData, TData, id);
    final state = _startEpochFor(reader);
    final repeat = state.current.contains(identity);
    final entry = _entryFor(
      state,
      identity,
      () => QueryController<TQueryData, TData>(client, options),
    );
    final controller = entry.controller as QueryController<TQueryData, TData>;
    final before = repeat ? controller.value : null;
    // Unconditional, as upstream re-applies options on every render: the
    // observer itself decides whether anything actually changed.
    controller.setOptions(options);
    final result = entry.read<QueryResult<TData>>();
    debugCheckRepeatRead(repeat, before, result, identity, 'This widget');
    return result;
  }

  /// The infinite twin of [readQuery].
  InfiniteQueryController<TPageData, TPageParam, TData>
      readInfiniteQuery<TPageData, TPageParam, TData>(
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options,
    Element reader,
    Object? id,
  ) {
    final identity = id == null
        ? (options.queryKey, TPageData, TPageParam, TData)
        : (#infinite, TPageData, TPageParam, TData, id);
    final state = _startEpochFor(reader);
    final repeat = state.current.contains(identity);
    final entry = _entryFor(
      state,
      identity,
      () => InfiniteQueryController<TPageData, TPageParam, TData>(
        client,
        options,
      ),
    );
    final controller = entry.controller
        as InfiniteQueryController<TPageData, TPageParam, TData>;
    final before = repeat ? controller.value : null;
    controller.setInfiniteOptions(options);
    debugCheckRepeatRead(
      repeat,
      before,
      entry.read<QueryResult<TData>>(),
      identity,
      'This widget',
    );
    return controller;
  }

  _Entry _entryFor(
    _Reader state,
    Object identity,
    ValueListenable<Object?> Function() create,
  ) {
    state.current.add(identity);
    return state.entries.putIfAbsent(
      identity,
      () => _Entry(create(), state.reader),
    );
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
    // again — by the very rebuild its own result caused. The types are part
    // of the identity the way they are for a query: the same `mutationKey`
    // read with two type triples is two controllers, not a failed cast
    // (fourth review, 2026-09-09).
    final identity = (
      #mutation,
      id ?? options.mutationKey,
      TData,
      TVariables,
      TOnMutateResult,
    );
    final state = _startEpochFor(reader);
    assert(() {
      // Two mutations of one shape in one widget without `id` would share a
      // controller, and the second `setOptions` would win: a tap on
      // "archive" running the delete. Only the type-triple fallback is
      // ambiguous; an `id` or a `mutationKey` names the mutation.
      if (id == null &&
          options.mutationKey == null &&
          state.current.contains(identity)) {
        throw FlutterError(
          'This widget read two mutations of the shape '
          '${(TData, TVariables, TOnMutateResult)} in one build. They would '
          'share one controller, and whichever was read last would run for '
          'both. Give each an `id:`.',
        );
      }
      return true;
    }());

    final existed = state.entries.containsKey(identity);
    final entry = _entryFor(
      state,
      identity,
      () => MutationController<TData, TVariables, TOnMutateResult>(
        client,
        options,
      ),
    );
    final controller = entry.controller
        as MutationController<TData, TVariables, TOnMutateResult>;
    if (existed) {
      controller.setOptions(options);
    }
    entry.read<Object?>();
    return controller;
  }

  _Reader _startEpochFor(Element reader) {
    final state = _readers.putIfAbsent(reader, () => _Reader(reader, _epoch));
    // It is reading, so it is here: whatever `removeDependent` said before
    // this frame ended is void.
    state.detached = false;
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

  /// Releases the observers a reader stopped reading, mutations included, and
  /// the whole of a reader that left the scope and did not come back.
  void _sweep() {
    for (final state in _readers.values.toList()) {
      if (state.detached) {
        _readers.remove(state.reader)?.dispose();
        continue;
      }
      final released = state.pending.difference(state.current);
      state.pending = <Object>{};
      for (final identity in released) {
        state.entries.remove(identity)?.dispose();
      }
    }
    _epoch++;
  }

  @override
  void removeDependent(Element dependent) {
    super.removeDependent(dependent);
    // Not "gone": Flutter also calls this when an element is *deactivated*,
    // and an element deactivated in one frame can be reactivated in the same
    // one somewhere else in the tree — that is how a `GlobalKey` subtree
    // moves. Destroying the controllers here took a running mutation's
    // observation away from a widget that never left (third review,
    // 2026-09-10). The sweep after the frame releases the readers that really
    // did not come back.
    final state = _readers[dependent];
    if (state == null) {
      return;
    }
    state.detached = true;
    _scheduleSweep();
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
