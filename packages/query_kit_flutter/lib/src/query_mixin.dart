/// The mixin way to read a query: call it in `build`, flat, no nesting.
///
/// The user-facing rules are on [QueryMixin].
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:query_kit/query_kit.dart';

import 'query_builder.dart';
import 'query_client_provider.dart';
import 'query_controller.dart';
import 'read_set.dart';

/// Adds [watchQuery], [watchSelectQuery], [watchInfiniteQuery] and
/// [watchMutation] to a [State], to read queries flat in its `build`.
///
/// One of the four equal ways to read a query; the others are
/// [QueryContext], the builder widgets such as [QueryBuilder], and the
/// controllers such as [QueryController]. This one reads like a hook, and
/// everything it creates belongs to the `State`: disposed with it, and
/// recreated when the client above it changes.
///
/// ```dart
/// class TaskScreen extends StatefulWidget {
///   const TaskScreen(this.id, {super.key});
///
///   final String id;
///
///   @override
///   State<TaskScreen> createState() => _TaskScreenState();
/// }
///
/// class _TaskScreenState extends State<TaskScreen> with QueryMixin {
///   @override
///   Widget build(BuildContext context) {
///     final task = watchQuery(taskQuery(widget.id));
///     final rename = watchMutation(renameTask(widget.id));
///     return Column(
///       children: [
///         Text(task.dataOrNull?.name ?? '…'),
///         FilledButton(
///           onPressed: rename.value.isPending
///               ? null
///               : () => rename.mutate('Renamed'),
///           child: const Text('Rename'),
///         ),
///       ],
///     );
///   }
/// }
/// ```
///
/// ## Identity
///
/// Reads are identified by their [QueryKey] and types, not by call order, so
/// there is nothing like the rules of hooks: calling [watchQuery] inside an
/// `if` is fine. What that identity does *not* tell apart — two reads of one
/// key with different selectors of the same output type, or two mutations of
/// the same shape, the same `mutationKey` included — takes an `id:`, and
/// reading two that differ without one is caught in debug builds (see
/// [watchMutation] for what a mutation is compared by). An `id` then takes
/// the key's place in the read's identity, the types staying part of it:
/// the read keeps its observer when its key changes, which is what
/// `PlaceholderData.compute((previous, _) => previous)` needs to keep
/// showing the previous key's data while the next loads.
///
/// ## When a read is released
///
/// A key read in the previous build but not in this one is released after
/// the frame, and so is a mutation. Everything goes when the `State` is
/// disposed. A `State` that stops calling [watchQuery] *altogether* gives no
/// signal, so its last observers stay until it is disposed; keep a
/// conditional read in a widget of its own, and the condition becomes that
/// widget's presence in the tree.
///
/// "Build" means this `State`'s own `build`. A [watchQuery] inside a nested
/// builder callback — a `ValueListenableBuilder`, `LayoutBuilder` or
/// `AnimatedBuilder` in `build`, or a `ListView.builder`'s `itemBuilder` —
/// also reads for this `State`, but that callback re-runs on its own, so its
/// reads are *additive*: they release nothing `build` read, and a key the
/// callback stops reading (the layout that was left, the rows scrolled away)
/// stays subscribed until an own `build` of this `State` that reads, or its
/// disposal. A `build` that reads nothing itself, leaving every read to a
/// nested builder, never starts over: those keys stay until the parent
/// rebuilds this `State`'s widget or it is disposed. Nothing shown in this
/// `State`'s subtree ever loses its subscription this way. Where the cost
/// matters — a long list above all, or a key that depends on constraints —
/// give the nested part, or each row, a widget of its own.
///
/// A read belongs to this `State` and rebuilds it, whoever made it: a dialog
/// or sheet builder calling [watchQuery] is not rebuilt by a change, and its
/// keys go at this `State`'s next `build` that reads. Give a dialog a reader
/// of its own.
///
/// ## The client
///
/// Reads run on the nearest [QueryClientProvider]'s client. Override
/// [queryClient] to read from a client of your own instead — a
/// `widget.client`, say; a change of client releases everything held and
/// recreates it on the new one.
///
/// {@category Reading queries}
/// {@category Mutations}
/// {@category Infinite queries}
mixin QueryMixin<T extends StatefulWidget> on State<T> {
  /// This State's reads — the registry `context.query` keeps one of per
  /// reading `Element`. A `State` is one reader, so it holds exactly one.
  late final ReadSet _reads = ReadSet(rebuild: _rebuild, who: 'This State');

  QueryClient? _client;

  /// The generation [_reads] is on: bumped by the post-frame sweep, so the
  /// first read of each frame rotates what the previous one held.
  int _generation = 0;
  bool _sweepScheduled = false;

  /// The client every read of this `State` runs on: the nearest
  /// [QueryClientProvider]'s by default.
  ///
  /// Override it to read from a client of your own:
  ///
  /// ```dart
  /// @override
  /// QueryClient get queryClient => widget.client;
  /// ```
  ///
  /// It is looked up again at every read, so a different client on a later
  /// build releases everything held on the old one and recreates it on the
  /// new one.
  QueryClient get queryClient => QueryClientProvider.of(context);

  /// Subscribes this `State` to [options]'s query and returns its current
  /// result.
  ///
  /// ```dart
  /// final task = watchQuery(taskQuery(widget.id));
  /// ```
  ///
  /// The first call for a key creates the observer; later calls with the
  /// same key reuse it and apply the new options. Options built inline are
  /// re-applied on every build, so an `Enabled.when` over outside state is
  /// re-evaluated; the observer compares them by value and only a real
  /// difference reaches the query. A *different* key is a different
  /// observer, and the one for the key no longer read is released after the
  /// frame — unless the read carries an [id]: then the id is the read's
  /// identity and the observer follows the key, which is what
  /// `PlaceholderData.compute((previous, _) => previous)` needs to show the
  /// previous key's data while the next loads. [id] also tells apart two
  /// reads of one key in the same `State`.
  ///
  /// [buildWhen] narrows *when* this `State` rebuilds, the same predicate a
  /// builder takes ([QueryBuilder.buildWhen]): given the result the last build
  /// showed and the one that just arrived, it says whether the change is worth
  /// a frame. A result equal to the one last built is skipped before the
  /// predicate is asked, so it only ever sees a real change. It is the tool
  /// for the change `select` cannot narrow away — a background refetch moves
  /// `fetchStatus` and `dataUpdatedAt`, and both are part of a
  /// `QueryResult`'s `==`. Each read has its own predicate, and any one of
  /// them letting a change through rebuilds the whole `State`.
  QueryResult<TData> watchQuery<TData>(
    QueryObserverOptions<TData> options, {
    Object? id,
    BuildWhen<QueryResult<TData>>? buildWhen,
  }) =>
      _watch<TData, TData>(options, id, buildWhen);

  /// [watchQuery] for a query with a `select`: the cache holds [TQueryData],
  /// this `State` sees [TData].
  ///
  /// Takes a [QuerySelectOptions], whose required `select` is what lets Dart
  /// infer [TData]; everything else is as for [watchQuery].
  ///
  /// ```dart
  /// final name = watchSelectQuery(
  ///   QuerySelectOptions<Task, String>(
  ///     queryKey: QueryKey(['tasks', widget.id]),
  ///     queryFn: (_) => api.getTask(widget.id),
  ///     select: (task) => task.name,
  ///   ),
  /// );
  /// ```
  QueryResult<TData> watchSelectQuery<TQueryData, TData>(
    QuerySelectOptions<TQueryData, TData> options, {
    Object? id,
    BuildWhen<QueryResult<TData>>? buildWhen,
  }) =>
      _watch<TQueryData, TData>(options, id, buildWhen);

  QueryResult<TData> _watch<TQueryData, TData>(
    QueryObserverOptionsBase<TQueryData, TData> options,
    Object? id,
    BuildWhen<QueryResult<TData>>? buildWhen,
  ) =>
      _beginRead().readQuery<TQueryData, TData>(
        _currentClient,
        options,
        id,
        buildWhen: buildWhen,
      );

  /// [watchQuery] for an infinite query. Returns the controller rather than
  /// the result, because paging lives on it.
  ///
  /// ```dart
  /// final feed = watchInfiniteQuery(feedQuery());
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
  /// The controller belongs to this `State` and is disposed for you; do not
  /// dispose it yourself.
  ///
  /// [buildWhen] compares the controller's results, as
  /// [InfiniteQueryBuilder.buildWhen] does. A fetch that moves only the paging
  /// flags — two fetches in opposite directions leave the result equal —
  /// rebuilds regardless: there is nothing there for a predicate over results
  /// to compare, and the reader is showing the stale half.
  InfiniteQueryController<TPageData, TPageParam, TData>
      watchInfiniteQuery<TPageData, TPageParam, TData>(
    InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options, {
    Object? id,
    BuildWhen<QueryResult<TData>>? buildWhen,
  }) =>
          _beginRead().readInfiniteQuery<TPageData, TPageParam, TData>(
            _currentClient,
            options,
            id,
            buildWhen: buildWhen,
          );

  /// A mutation owned by this `State`, as a [MutationController].
  ///
  /// ```dart
  /// final rename = watchMutation(renameTask(widget.id));
  /// // in a handler:
  /// rename.mutate('Renamed');
  /// ```
  ///
  /// Mutations are not shared: each `State` that asks gets its own
  /// controller, released after the frame once a build stops reading it, the
  /// way a query is, and disposed with the `State`. Releasing it does not
  /// cancel a run in flight; see [MutationController.cancel].
  ///
  /// One is identified by [id], else by the options' `mutationKey`, each
  /// together with its three types; without either, by the types alone — so
  /// pass [id] when one `State` runs two mutations of the same shape. A
  /// `mutationKey` is a category, not a name: two reads of one identity in
  /// one build share one controller, and whichever was read last would run
  /// for both. So two such reads without [id] are a debug assertion when they
  /// differ in the mutation function or callbacks (`onMutate`, `onSuccess`,
  /// `onError`, `onSettled`), or in `scope`, `retry`, `retryDelay`,
  /// `networkMode` or `gcTime`. The same functions read twice — one stored
  /// options object, tear-offs, top-level functions — are one mutation, and
  /// so is a nested builder re-reading what `build` read; a function literal
  /// is a new function each time it is built, so keep it in a field or read
  /// once.
  ///
  /// [buildWhen] narrows *when* this `State` rebuilds, the same predicate
  /// [MutationBuilder.buildWhen] takes: given the result the last build
  /// showed and the one just reported, whether this read is worth a frame.
  /// A mutation has no `select`, so this is the only filter a reader has.
  MutationController<TData, TVariables, TOnMutateResult>
      watchMutation<TData, TVariables, TOnMutateResult>(
    MutationOptions<TData, TVariables, TOnMutateResult> options, {
    Object? id,
    BuildWhen<MutationResult<TData, TVariables>>? buildWhen,
  }) =>
          _beginRead().readMutation<TData, TVariables, TOnMutateResult>(
            _currentClient,
            options,
            id,
            buildWhen: buildWhen,
          );

  /// Every read goes through here: the client is reconciled, this frame's
  /// generation is opened if it is not open already, and the sweep that ends
  /// it is booked.
  ReadSet _beginRead() {
    // Before anything is recorded: a client switch releases what the old one
    // owned, and leaves the set empty for this build to repopulate.
    _reconcileClient();
    _reads.beginBuild(_generation, context as Element);
    if (!_sweepScheduled) {
      _sweepScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => _sweep());
    }
    return _reads;
  }

  /// Releases what the last build stopped reading, mutations included, and
  /// opens the next generation.
  void _sweep() {
    _sweepScheduled = false;
    _generation++;
    if (!mounted) {
      return;
    }
    _reads.sweep();
  }

  /// The client this State's reads run on, as [_reconcileClient] last left it.
  QueryClient get _currentClient => _client ??= queryClient;

  /// Looks the client up again and releases everything held when it changed.
  ///
  /// Run at the start of every read rather than once: [queryClient] is
  /// overridable, and the usual override — `widget.client` — changes on a
  /// plain widget update, which is not a dependency change and so never
  /// reached `didChangeDependencies`. Everything held belongs to the client
  /// it was created on, so a switch releases all of it and this build's reads
  /// recreate it on the new one.
  ///
  /// Looking the client up lazily is also what lets a `State` mix this in
  /// without a provider above it: only a read needs one, and a `build` that
  /// reads nothing does not throw for a client it never wanted.
  void _reconcileClient() {
    final client = queryClient;
    if (_client != null && _client != client) {
      _reads.releaseAll();
    }
    _client = client;
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _reads.releaseAll();
    super.dispose();
  }
}
