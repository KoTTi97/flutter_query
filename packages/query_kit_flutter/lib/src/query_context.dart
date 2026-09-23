/// `context.query(...)`: read a query straight from a `BuildContext`.
///
/// The user-facing rules are on [QueryContext]. The mechanism is Flutter's
/// own, the same one `provider` uses for `context.watch`: `InheritedElement`
/// reports `removeDependent` when a reading widget unmounts, so the observers
/// it held can be released exactly rather than guessed at.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:query_kit/query_kit.dart';

import 'query_builder.dart';
import 'query_controller.dart';
import 'read_set.dart';

/// Reads queries and mutations straight from a [BuildContext], in `build`.
///
/// One of the four equal ways to read a query; the others are [QueryMixin],
/// the builder widgets such as [QueryBuilder], and the controllers such as
/// [QueryController]. This one is the flattest: it works in a
/// `StatelessWidget`, needs no wrapper widget, and its rebuilds are
/// per-reader — when a query changes, only the widgets that read *that*
/// query rebuild.
///
/// ```dart
/// class TaskScreen extends StatelessWidget {
///   const TaskScreen(this.id, {super.key});
///
///   final String id;
///
///   @override
///   Widget build(BuildContext context) {
///     final task = context.query(taskQuery(id));
///     final rename = context.mutation(renameTask(id));
///     return switch (task) {
///       QueryPending() => const CircularProgressIndicator(),
///       QueryError(:final error) => Text('$error'),
///       QuerySuccess(:final data) => ListTile(
///           title: Text(data.name),
///           trailing: IconButton(
///             icon: const Icon(Icons.edit),
///             onPressed: rename.value.isPending
///                 ? null
///                 : () => rename.mutate('Renamed'),
///           ),
///         ),
///     };
///   }
/// }
/// ```
///
/// Four members: [query] for plain options, [selectQuery] for options with a
/// `select`, [infiniteQuery], which returns an [InfiniteQueryController]
/// because paging lives there, and [mutation], which returns a
/// [MutationController].
///
/// ## Identity
///
/// Every reading widget gets observers of its own; what is shared is the
/// *query* in the cache, so two widgets reading one key still cost one
/// request, and they never fight over one observer's `select`, `enabled` or
/// polling interval. Within one widget a read is identified by its key and
/// its types, so a read inside an `if` is fine — there is no rule about call
/// order. Pass `id:` to tell apart two reads of one key with different
/// selectors of the same output type; reading two of them without one is
/// caught in debug builds.
///
/// An `id` is then the read's whole identity: a read that carries one keeps
/// its observer when its key changes. That is what
/// `PlaceholderData.compute((previous, _) => previous)` needs to keep showing
/// the previous key's data while the next key loads; without an `id`, a new
/// key is a new observer with nothing previous to show.
///
/// A mutation is identified by its `id`, else by its `mutationKey`, each
/// together with its three types; see [mutation].
///
/// ## When a read is released
///
/// A key the widget read in its last build but not in this one is released
/// after the frame, and so is a mutation. Everything goes when the widget
/// unmounts.
///
/// A widget that stops calling `context.query` *altogether* gives no signal
/// Flutter can see, so its last observers stay until it unmounts. Put a
/// conditional read in a small widget of its own, and the condition becomes
/// that widget's presence in the tree.
///
/// ## Read in `build`, through the widget's own context
///
/// A read belongs to the element whose `context` it went through, rebuilds
/// that element, and lives as long as that element's own builds keep
/// reading it.
///
/// * **Only in `build`.** The read is reconciled against what the widget
///   read in its last build. A `context.query` in a tap handler creates an
///   observer that is only matched up at the next build. Read in `build` and
///   act on the result from the handler.
/// * **Nested builders make additive reads.** A read through the outer
///   `context` inside a `ValueListenableBuilder`, `AnimatedBuilder` or
///   `LayoutBuilder` callback runs later than `build`, and it releases
///   nothing the widget's own build read. A key such a callback stops reading
///   stays subscribed until the widget's next own build that reads through
///   this context, or its unmount — and a `build` that reads nothing itself
///   never starts over. Read in `build`, or give the nested part a widget of
///   its own.
/// * **A `LayoutBuilder`'s own context.** Reads through the `context` a
///   `LayoutBuilder`, `SliverLayoutBuilder` or `OrientationBuilder` hands its
///   builder start over whenever that builder provably runs: its constraints
///   changed (the wide layout's key goes after a resize), its parent rebuilt
///   it, or one of its own reads notified. A nested builder handed that
///   context is additive, as above. A rebuild caused by an `InheritedWidget`
///   the builder depends on carries no signal, so a key picked from an
///   inherited value stays subscribed until the next resize, notification or
///   parent rebuild. A key that depends on anything the builder reads belongs
///   in a widget of its own below the `LayoutBuilder` —
///   `LayoutBuilder(builder: (_, c) => c.maxWidth > 600 ? const WideTasks()
///   : const NarrowTasks())`, each reading in its own `build` — and goes with
///   that widget.
/// * **Dialogs, sheets and overlays read through their own context.**
///   Reading through a page's `context` from a `showDialog` or bottom-sheet
///   builder rebuilds the page, not the dialog, and the page's next build
///   releases the read while the dialog may still show it. Read through the
///   builder's own `context`, or in a widget inside the dialog.
/// * **Never through a list's item-builder context.** The `context` a
///   `ListView.builder`, `GridView.builder`, `PageView.builder` or another
///   lazily built list hands its `itemBuilder` belongs to the whole list,
///   not the row: rows are built piecemeal as they scroll in, and a read
///   cannot tell which row it belongs to. In debug builds such a read throws
///   a `FlutterError` naming the fix. In release builds the reads are
///   additive: no row on screen loses its subscription, and rows scrolled
///   away stay subscribed until the list is rebuilt or unmounts. Give each
///   row a widget of its own:
///
///   ```dart
///   ListView.builder(
///     itemCount: ids.length,
///     itemBuilder: (_, i) => TaskTile(ids[i]), // reads in TaskTile.build
///   )
///   ```
///
/// ## The client is always the provider's
///
/// There is no `client:` parameter, on purpose: a `BuildContext` names
/// exactly one [QueryClientProvider], and a second way to say which client
/// would only leave a reader wondering which one won. For a client that is
/// not the provider's, use a builder widget's `client:`, a controller, or
/// override [QueryMixin.queryClient]. Without a provider above, every member
/// throws a `FlutterError` that says so.
///
/// {@category Reading queries}
/// {@category Mutations}
/// {@category Infinite queries}
extension QueryContext on BuildContext {
  /// Subscribes this widget to [options]'s query and returns its current
  /// result.
  ///
  /// ```dart
  /// final task = context.query(taskQuery(id));
  /// return switch (task) {
  ///   QueryPending() => const CircularProgressIndicator(),
  ///   QueryError(:final error) => Text('$error'),
  ///   QuerySuccess(:final data) => Text(data.name),
  /// };
  /// ```
  ///
  /// The observer is this widget's, released after the frame once the widget
  /// stops reading the key — including when it simply reads a *different*
  /// key on a later build — or unmounts. With an [id] the observer follows a
  /// changed key instead, and [id] also tells apart two reads of one key in
  /// the same widget. Read in `build`, through the widget's own `context`;
  /// the rules for nested builders, `LayoutBuilder`s, dialogs and list rows
  /// are on [QueryContext].
  ///
  /// Always on the nearest [QueryClientProvider]'s client. Options built
  /// inline are re-applied on every build, so an `Enabled.when` over outside
  /// state is re-evaluated; the observer compares them by value and only a
  /// real difference reaches the query.
  ///
  /// [buildWhen] narrows *when* this widget rebuilds, the same predicate a
  /// builder takes ([QueryBuilder.buildWhen]): given the result the last build
  /// showed and the one that just arrived, it says whether the change is worth
  /// a frame. A result equal to the one last built is skipped before the
  /// predicate is asked, so it only ever sees a real change. It is the tool
  /// for the change `select` cannot narrow away — a background refetch moves
  /// `fetchStatus` and `dataUpdatedAt`, and both are part of a
  /// `QueryResult`'s `==`:
  ///
  /// ```dart
  /// final task = context.query(
  ///   taskQuery(id),
  ///   buildWhen: (previous, current) =>
  ///       previous.dataOrNull != current.dataOrNull,
  /// );
  /// ```
  ///
  /// Each read has its own predicate, and any one of them letting a change
  /// through rebuilds the whole widget.
  QueryResult<TData> query<TData>(
    QueryObserverOptions<TData> options, {
    Object? id,
    BuildWhen<QueryResult<TData>>? buildWhen,
  }) =>
      _read<TData, TData>(options, id, buildWhen);

  /// [query] for a query with a `select`: the cache holds [TQueryData], this
  /// widget sees [TData].
  ///
  /// Takes a [QuerySelectOptions], whose required `select` is what lets Dart
  /// infer [TData]; everything else — identity, release, [id], [buildWhen] —
  /// is as for [query].
  ///
  /// ```dart
  /// final name = context.selectQuery(
  ///   QuerySelectOptions<Task, String>(
  ///     queryKey: QueryKey(['tasks', id]),
  ///     queryFn: (_) => api.getTask(id),
  ///     select: (task) => task.name,
  ///   ),
  /// );
  /// ```
  QueryResult<TData> selectQuery<TQueryData, TData>(
    QuerySelectOptions<TQueryData, TData> options, {
    Object? id,
    BuildWhen<QueryResult<TData>>? buildWhen,
  }) =>
      _read<TQueryData, TData>(options, id, buildWhen);

  QueryResult<TData> _read<TQueryData, TData>(
    QueryObserverOptionsBase<TQueryData, TData> options,
    Object? id,
    BuildWhen<QueryResult<TData>>? buildWhen,
  ) {
    final element = _scopeElement(this);
    final result = element
        .readsFor(this as Element, 'context.query')
        .readQuery<TQueryData, TData>(element.client, options, id,
            buildWhen: buildWhen);
    dependOnInheritedWidgetOfExactType<QueryScope>();
    return result;
  }

  /// [query] for an infinite query. Returns the controller rather than the
  /// result, because paging lives on it: the pages are in its `value`, and
  /// [InfiniteQueryController.fetchNextPage] and its siblings load more.
  ///
  /// ```dart
  /// final feed = context.infiniteQuery(feedQuery());
  /// final posts = feed.value.dataOrNull?.flatten<Post>() ?? const <Post>[];
  /// return ListView(
  ///   children: [
  ///     for (final post in posts) ListTile(title: Text(post.title)),
  ///     if (feed.hasNextPage)
  ///       TextButton(
  ///         onPressed: feed.isFetchingNextPage ? null : feed.fetchNextPage,
  ///         child: const Text('Load more'),
  ///       ),
  ///   ],
  /// );
  /// ```
  ///
  /// The controller belongs to this widget and is disposed for you, by the
  /// same release rules as [query]; do not dispose it yourself.
  ///
  /// [buildWhen] compares the controller's results, as
  /// [InfiniteQueryBuilder.buildWhen] does. A fetch that moves only the paging
  /// flags — two fetches in opposite directions leave the result equal —
  /// rebuilds regardless: there is nothing there for a predicate over results
  /// to compare, and the reader is showing the stale half.
  InfiniteQueryController<TPageData, TPageParam, TData>
      infiniteQuery<TPageData, TPageParam, TData>(
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options, {
    Object? id,
    BuildWhen<QueryResult<TData>>? buildWhen,
  }) {
    final element = _scopeElement(this);
    final controller = element
        .readsFor(this as Element, 'context.infiniteQuery')
        .readInfiniteQuery<TPageData, TPageParam, TData>(
            element.client, options, id,
            buildWhen: buildWhen);
    dependOnInheritedWidgetOfExactType<QueryScope>();
    return controller;
  }

  /// A mutation owned by this widget, as a [MutationController].
  ///
  /// ```dart
  /// final client = QueryClientProvider.of(context);
  /// final add = context.mutation(
  ///   MutationOptions.simple(
  ///     mutationFn: api.addTask,
  ///     onSuccess: (_, __, ___) => client.invalidateQueries(
  ///       filters: QueryFilters(queryKey: tasksKey),
  ///     ),
  ///   ),
  /// );
  /// return FilledButton(
  ///   onPressed: add.value.isPending ? null : () => add.mutate('New task'),
  ///   child: const Text('Add'),
  /// );
  /// ```
  ///
  /// Take the client in `build`, as above, rather than looking it up inside
  /// a callback: a mutation outlives the widget that started it, and an
  /// `onSuccess` that runs after the widget is gone cannot use its `context`.
  ///
  /// Mutations are not shared: each widget that asks gets its own
  /// controller, released when the widget stops reading it — the way a query
  /// is — or unmounts. Releasing the controller does not cancel a run in
  /// flight; see [MutationController.cancel].
  ///
  /// **Identity.** A mutation is identified by [id], else by the options'
  /// `mutationKey`, each together with its three types; without either, by
  /// the types alone — so pass [id] when one widget runs two mutations of the
  /// same shape. A `mutationKey` is a category, not a name: two reads of one
  /// identity in one build share one controller, and whichever was read last
  /// would run for both. So two such reads without [id] are a debug
  /// assertion when they differ in the mutation function or callbacks
  /// (`onMutate`, `onSuccess`, `onError`, `onSettled`), or in `scope`,
  /// `retry`, `retryDelay`, `networkMode` or `gcTime` — rows reading
  /// `MutationScope('task-$id')` inline under one key would otherwise share
  /// one queue. Those five compare by value, except `RetryPolicy.when` and
  /// `RetryDelay.dynamic`, which carry a closure and compare by variant only.
  /// `meta` is not compared: the last read's wins.
  ///
  /// The same functions read twice — one stored options object, tear-offs,
  /// top-level functions — are one mutation, and so is a nested builder
  /// re-reading what `build` read. A function literal is a new function each
  /// time it is built, so keep it in a field or read the mutation once. Only
  /// a `StatelessWidget`'s or `State`'s own build is checked; reads through a
  /// `LayoutBuilder`'s context are never compared, and through a list's
  /// item-builder context any read is a debug error (see [QueryContext]).
  ///
  /// [buildWhen] narrows *when* this widget rebuilds, the same predicate
  /// [MutationBuilder.buildWhen] takes: given the result the last build
  /// showed and the one just reported, whether this read is worth a frame.
  /// A mutation has no `select`, so this is the only filter a reader has:
  ///
  /// ```dart
  /// final rename = context.mutation(
  ///   renameTask(id),
  ///   // A retrying run moves `failureCount` while it stays pending.
  ///   buildWhen: (previous, current) => previous.status != current.status,
  /// );
  /// ```
  MutationController<TData, TVariables, TOnMutateResult>
      mutation<TData, TVariables, TOnMutateResult>(
    MutationOptions<TData, TVariables, TOnMutateResult> options, {
    Object? id,
    BuildWhen<MutationResult<TData, TVariables>>? buildWhen,
  }) {
    final element = _scopeElement(this);
    final controller = element
        .readsFor(this as Element, 'context.mutation')
        .readMutation<TData, TVariables, TOnMutateResult>(
            element.client, options, id,
            buildWhen: buildWhen);
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

/// The client's place in the widget tree: what `QueryClientProvider.of`,
/// `maybeOf` and `read` find, and what `context.query` reads through.
/// Installed by `QueryClientProvider`; you never place one yourself. Not
/// public API: the package barrel hides it (an `@internal` annotation would
/// need `meta`, which Flutter 3.27's `foundation` does not yet re-export).
///
/// **Both jobs, in one widget.** The three lookups and the reads share one
/// scope, because they share the `client` field, the `updateShouldNotify`
/// and the lifetime. The element under this widget carries more than the
/// field, but what it carries is per *reader* ([QueryScopeElement]) and a
/// widget that only asks for the client is simply a dependent that never
/// reads: it registers a dependency, is notified when the client changes —
/// which is what `of` promises — and its `removeDependent` finds nothing to
/// release.
class QueryScope extends InheritedWidget {
  /// Placed by `QueryClientProvider` around its child; nothing else
  /// constructs one.
  const QueryScope({super.key, required this.client, required super.child});

  /// The provider's client: what the three lookups return, and what every
  /// observer read through this scope is created on. A new client is what
  /// makes the scope notify everyone who asked.
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
  /// registry `QueryMixin` holds one of.
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
  /// post-frame sweep answers, not an answer in itself.
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
  /// it, naming themselves as [call], then read through the set it returns.
  /// A list's item-builder context is refused here, in debug builds, before
  /// a set is made for it ([ReadSet.debugCheckReader]).
  ReadSet readsFor(Element reader, String call) {
    ReadSet.debugCheckReader(reader, call);
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
    reads.beginBuild(_epoch, reader);
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
    // moves. Destroying the controllers here would take a running
    // mutation's observation away from a widget that never left. The sweep
    // after the frame releases the readers that really did not come back.
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
