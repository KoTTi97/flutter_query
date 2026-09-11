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

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:query_kit/query_kit.dart';

import 'query_controller.dart';
import 'read_set.dart';

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
    final result = element
        .readsFor(this as Element)
        .readQuery<TQueryData, TData>(element.client, options, id);
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
    final controller = element
        .readsFor(this as Element)
        .readInfiniteQuery<TPageData, TPageParam, TData>(
            element.client, options, id);
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
    final controller = element
        .readsFor(this as Element)
        .readMutation<TData, TVariables, TOnMutateResult>(
            element.client, options, id);
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

/// Keeps each reading widget's observers alive for as long as it reads them.
/// Not public API; hidden from the barrel like [QueryScope].
class QueryScopeElement extends InheritedElement {
  /// Created by [QueryScope.createElement]; holds every reading widget's
  /// observers for as long as the scope is mounted.
  QueryScopeElement(QueryScope super.widget);

  /// Every reading widget's reads. One [ReadSet] per `Element`, the same
  /// registry `QueryMixin` holds one of (C47,
  /// https://github.com/KoTTi97/flutter_query/issues/56).
  final Map<Element, ReadSet> _readers = <Element, ReadSet>{};

  /// Elements Flutter said stopped depending on this scope, pending the
  /// sweep's verdict. Not a [ReadSet] field: it is a fact about *which*
  /// readers are still here, which is this element's question and has no
  /// counterpart on the mixin side, where a `State` gets no such signal at
  /// all.
  ///
  /// "Stopped depending" is not "gone": an element deactivated in one frame
  /// can be reactivated in the same one somewhere else in the tree — that is
  /// how a `GlobalKey` subtree moves — so the flag is a question the
  /// post-frame sweep answers, not an answer in itself (third review,
  /// 2026-09-10).
  final Set<Element> _detached = <Element>{};

  int _epoch = 0;
  bool _sweepScheduled = false;

  /// The scope's current client — the one every observer created from here on
  /// runs on. When it changes, [update] has already released the observers
  /// that belonged to the old one.
  QueryClient get client => (widget as QueryScope).client;

  /// [reader]'s reads, ready for this frame: the generation is opened if it
  /// is not open already, and the sweep that ends it is booked.
  ///
  /// Public to the library only — `context.query` and its two siblings call
  /// it, then read through the set it returns.
  ReadSet readsFor(Element reader) {
    final reads = _readers.putIfAbsent(
      reader,
      () => ReadSet(
        rebuild: () {
          if (reader.mounted) {
            reader.markNeedsBuild();
          }
        },
        who: 'This widget',
      ),
    );
    // It is reading, so it is here: whatever `removeDependent` said before
    // this frame ended is void.
    _detached.remove(reader);
    reads.beginBuild(_epoch);
    _scheduleSweep();
    return reads;
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
    for (final reader in _detached) {
      _readers.remove(reader)?.releaseAll();
    }
    _detached.clear();
    for (final reads in _readers.values) {
      reads.sweep();
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
    if (!_readers.containsKey(dependent)) {
      return;
    }
    _detached.add(dependent);
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
    for (final reads in _readers.values) {
      reads.releaseAll();
    }
    _readers.clear();
    _detached.clear();
  }

  @override
  void unmount() {
    _disposeAll();
    super.unmount();
  }
}
