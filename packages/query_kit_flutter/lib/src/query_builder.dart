/// The builder-widget way to read a query — the `StreamBuilder` shape.
///
/// The four widgets here are four public surfaces over one state class family:
/// what they each declare is a type slot and a `builder` signature, and what
/// they share — the controller's lifetime, the options re-applied on every
/// widget update, and the rebuild decision of [ReadEntry] — is written once
/// in [_ControllerBuilderState].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:query_kit/query_kit.dart';

import 'query_client_provider.dart';
import 'query_controller.dart';
import 'read_entry.dart';

export 'read_entry.dart' show BuildWhen;

/// What every builder widget here declares, and all a [_ControllerBuilderState]
/// needs from the widget it is the state of.
///
/// A mixin rather than a shared superclass so that each widget keeps its own
/// field types: [options] is a `QueryObserverOptions` on one and a
/// `MutationOptions` on another, and a reader of either sees the narrow type.
mixin _BuilderWidget<T> on StatefulWidget {
  /// The options this widget re-applies whenever its parent rebuilds it —
  /// unconditionally, the same object included.
  ///
  /// Options kept in a field are the same object on every build, and yet an
  /// `Enabled.when` in them may read outside state that changed: re-applying
  /// them is what re-evaluates it. That costs one defaulting pass and nothing
  /// else: the observer compares the *defaulted* options by value and only a
  /// real difference reaches the query.
  Object get options;

  /// Rebuilds this widget's subtree only for the changes it passes; see
  /// [QueryBuilder.buildWhen].
  BuildWhen<T>? get buildWhen;

  /// The client to observe on, or the nearest [QueryClientProvider]'s; see
  /// [QueryBuilder.client].
  QueryClient? get client;
}

/// The two builders over a plain query — with a `select` and without — which
/// differ in nothing their state can see but the type slot the cache's data
/// fills.
mixin _QueryBuilderWidget<TQueryData, TData>
    on _BuilderWidget<QueryResult<TData>> {
  @override
  QueryObserverOptionsBase<TQueryData, TData> get options;

  /// Builds the subtree from the query's current result.
  Widget Function(BuildContext context, QueryResult<TData> result) get builder;
}

/// Builds its subtree from a query's result — the `StreamBuilder` shape.
///
/// One of the four equal ways to read a query; the others are
/// [QueryContext], [QueryMixin] and the controllers such as
/// [QueryController]. This one is the most explicit: nothing happens that is
/// not visible in the tree, a change rebuilds exactly this widget's subtree,
/// and it is a natural fit inside a list or a sliver.
///
/// ```dart
/// QueryBuilder<Task>(
///   options: taskQuery(id),
///   builder: (context, result) => switch (result) {
///     QueryPending() => const CircularProgressIndicator(),
///     QuerySuccess(:final data) => TaskCard(data),
///     QueryError(:final error) => ErrorBanner(error),
///   },
/// )
/// ```
///
/// The widget owns an observer from its first build until it is disposed.
/// Nothing is fetched before that first build, and two builders on one key
/// share the query in the cache, so they cost one request.
///
/// **The type argument** is the query's data type. It usually comes from
/// `queryFn`'s return type, or is written out as `QueryBuilder<Task>(…)`. A
/// key-only options literal with neither a `queryFn` nor a type argument
/// cannot name it, and is refused with an assertion in debug builds. Use
/// [QuerySelectBuilder] when the query needs a `select`.
///
/// **Options are re-applied whenever the parent rebuilds this widget**,
/// built inline or kept in a field, so an `Enabled.when` over outside state
/// is re-evaluated then. The observer compares them by value and only a real
/// difference reaches the query; a changed key switches the observed query in
/// place. Every builder widget takes its options that way.
///
/// {@category Reading queries}
class QueryBuilder<TData> extends StatefulWidget
    with _BuilderWidget<QueryResult<TData>>, _QueryBuilderWidget<TData, TData> {
  /// Observes [options]'s query on [client] — or, when none is given, the
  /// nearest [QueryClientProvider]'s — and builds its subtree from the result
  /// through [builder].
  const QueryBuilder({
    super.key,
    required this.options,
    required this.builder,
    this.buildWhen,
    this.client,
  });

  /// The query. Re-applied whenever the parent rebuilds this widget; the
  /// observer decides what changed.
  @override
  final QueryObserverOptions<TData> options;

  /// Builds this widget's subtree from the query's current result — a sealed
  /// [QueryResult], so a `switch` over `QueryPending`, `QuerySuccess` and
  /// `QueryError` is exhaustive. Called on the first build and then whenever
  /// the result changes and [buildWhen] lets it through.
  @override
  final Widget Function(BuildContext context, QueryResult<TData> result)
      builder;

  /// Skips rebuilds the builder does not care about. Given the result this
  /// widget last *built* from and the one it would build from now, returns
  /// whether to rebuild; `null` rebuilds for every changed result.
  ///
  /// ```dart
  /// buildWhen: (previous, current) =>
  ///     previous.dataOrNull != current.dataOrNull,
  /// ```
  ///
  /// `select` narrows the *data* a widget sees; this narrows *when* it
  /// rebuilds, which is the only way to ignore a change `select` cannot see —
  /// a background refetch moves `fetchStatus` and `dataUpdatedAt`, and both
  /// are part of a result's `==`. A result equal to the one last built never
  /// reaches the predicate. `previous` is what is on screen: a result the
  /// predicate skipped is not remembered.
  @override
  final BuildWhen<QueryResult<TData>>? buildWhen;

  /// The client to observe on, when it is not the nearest
  /// [QueryClientProvider]'s. A different client on a later build — this
  /// field's or the provider's — recreates the controller, because
  /// everything it observed belonged to the old one; what counts is the
  /// client resolved, so naming the provider's own client here changes
  /// nothing. Changed [options] on the same client are applied in place.
  @override
  final QueryClient? client;

  @override
  State<QueryBuilder<TData>> createState() =>
      _QueryBuilderState<QueryBuilder<TData>, TData, TData>();
}

/// [QueryBuilder] for a query with a `select`: the cache holds [TQueryData],
/// the builder sees [TData].
///
/// ```dart
/// QuerySelectBuilder<Task, String>(
///   options: QuerySelectOptions(
///     queryKey: QueryKey(['tasks', id]),
///     queryFn: (_) => api.getTask(id),
///     select: (task) => task.name,
///   ),
///   builder: (context, result) => Text(result.dataOrNull ?? '…'),
/// )
/// ```
///
/// Takes a [QuerySelectOptions], whose required `select` is what lets Dart
/// infer the second type. Everything else — lifetime, options re-applied
/// when the parent rebuilds, [buildWhen], [client] — is as for
/// [QueryBuilder]. A `select`
/// that returns an equal value keeps the previous one, so `data` stays the
/// same instance when nothing it depends on changed; the rest of the result
/// (`fetchStatus`, `dataUpdatedAt`) still changes, which is what
/// [buildWhen] is for.
///
/// {@category Reading queries}
class QuerySelectBuilder<TQueryData, TData> extends StatefulWidget
    with
        _BuilderWidget<QueryResult<TData>>,
        _QueryBuilderWidget<TQueryData, TData> {
  /// Observes [options]'s query, `select` included, on [client] or else the
  /// nearest [QueryClientProvider]'s, and hands [builder] the selected result.
  const QuerySelectBuilder({
    super.key,
    required this.options,
    required this.builder,
    this.buildWhen,
    this.client,
  });

  /// The query and its `select`. Re-applied whenever the parent rebuilds
  /// this widget; the observer decides what changed, as for
  /// [QueryBuilder.options].
  @override
  final QuerySelectOptions<TQueryData, TData> options;

  /// Builds this widget's subtree from the *selected* result — `TData`, not
  /// the `TQueryData` the cache holds. Called on the first build and then
  /// whenever the result changes and [buildWhen] lets it through.
  @override
  final Widget Function(BuildContext context, QueryResult<TData> result)
      builder;

  /// Whether a change from the result last built to the current one is worth
  /// a rebuild; `null` rebuilds for every changed result. Compares selected
  /// results; see [QueryBuilder.buildWhen].
  @override
  final BuildWhen<QueryResult<TData>>? buildWhen;

  /// The client to observe on; `null` uses the nearest
  /// [QueryClientProvider]'s. A different client on a later build recreates
  /// the observer; see [QueryBuilder.client].
  @override
  final QueryClient? client;

  @override
  State<QuerySelectBuilder<TQueryData, TData>> createState() =>
      _QueryBuilderState<QuerySelectBuilder<TQueryData, TData>, TQueryData,
          TData>();
}

/// The state of both query builders: one class, because a `select` is a type
/// slot and nothing else to the widget that owns the controller. [W] is
/// the widget it is the state of — narrowing it is what keeps
/// `createState`'s return type the widget's own.
class _QueryBuilderState<W extends _QueryBuilderWidget<TQueryData, TData>,
        TQueryData, TData>
    extends _ControllerBuilderState<W, QueryResult<TData>,
        QueryController<TQueryData, TData>> {
  @override
  QueryController<TQueryData, TData> createController(QueryClient client) =>
      QueryController<TQueryData, TData>(client, widget.options);

  @override
  void applyOptions() => controller.setOptions(widget.options);

  @override
  Widget build(BuildContext context) => widget.builder(context, record());
}

/// Builds its subtree from an infinite query, handing the builder the
/// [InfiniteQueryController] so it can page.
///
/// ```dart
/// InfiniteQueryBuilder(
///   options: feedQuery(),
///   builder: (context, feed) {
///     final posts = feed.value.dataOrNull?.flatten<Post>() ?? const <Post>[];
///     return ListView(
///       children: [
///         for (final post in posts) ListTile(title: Text(post.title)),
///         if (feed.hasNextPage)
///           TextButton(
///             onPressed: feed.isFetchingNextPage ? null : feed.fetchNextPage,
///             child: const Text('Load more'),
///           ),
///       ],
///     );
///   },
/// )
/// ```
///
/// No type arguments at the call site: either options shape —
/// [InfiniteQueryObserverOptions] or [InfiniteQuerySelectOptions] — carries
/// the page type, the page-param type and the result type, and inference
/// reads all three off it.
///
/// The widget owns the controller from its first build until it is
/// disposed; do not dispose the one [builder] is handed. Options are
/// re-applied whenever the parent rebuilds it, as for [QueryBuilder]. A
/// fetch that moves only the paging flags — `isFetchingNextPage`,
/// `hasNextPage` and the like — rebuilds too, even when the result itself is
/// unchanged.
///
/// {@category Infinite queries}
class InfiniteQueryBuilder<TPageData, TPageParam, TData> extends StatefulWidget
    with _BuilderWidget<QueryResult<TData>> {
  /// Observes [options]'s infinite query on [client] or else the nearest
  /// [QueryClientProvider]'s, and hands [builder] the controller, which is
  /// where paging lives.
  const InfiniteQueryBuilder({
    super.key,
    required this.options,
    required this.builder,
    this.buildWhen,
    this.client,
  });

  /// The infinite query: key, page function and paging functions.
  /// Re-applied whenever the parent rebuilds this widget; the observer
  /// decides what changed, as for [QueryBuilder.options].
  @override
  final InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options;

  /// Builds this widget's subtree from the infinite query, given its
  /// controller rather than a bare result: the pages are in `query.value`,
  /// and [InfiniteQueryController.hasNextPage],
  /// [InfiniteQueryController.fetchNextPage] and the other paging members are
  /// on the controller. Called on the first build and then whenever the
  /// result changes and [buildWhen] lets it through.
  final Widget Function(
    BuildContext context,
    InfiniteQueryController<TPageData, TPageParam, TData> query,
  ) builder;

  /// Whether a change from the result last built to the current one is worth
  /// a rebuild; `null` rebuilds for every changed result. Compares the
  /// controller's results (see [QueryBuilder.buildWhen]); a change of the
  /// paging flags alone rebuilds regardless.
  @override
  final BuildWhen<QueryResult<TData>>? buildWhen;

  /// The client to observe on; `null` uses the nearest
  /// [QueryClientProvider]'s. A different client on a later build recreates
  /// the controller; see [QueryBuilder.client].
  @override
  final QueryClient? client;

  @override
  State<InfiniteQueryBuilder<TPageData, TPageParam, TData>> createState() =>
      _InfiniteQueryBuilderState<TPageData, TPageParam, TData>();
}

class _InfiniteQueryBuilderState<TPageData, TPageParam, TData>
    extends _ControllerBuilderState<
        InfiniteQueryBuilder<TPageData, TPageParam, TData>,
        QueryResult<TData>,
        InfiniteQueryController<TPageData, TPageParam, TData>> {
  @override
  InfiniteQueryController<TPageData, TPageParam, TData> createController(
    QueryClient client,
  ) =>
      InfiniteQueryController<TPageData, TPageParam, TData>(
        client,
        widget.options,
      );

  @override
  void applyOptions() => controller.setInfiniteOptions(widget.options);

  @override
  Widget build(BuildContext context) {
    record();
    return widget.builder(context, controller);
  }
}

/// Builds its subtree from a mutation's result, and hands the builder the
/// [MutationController] that starts a run.
///
/// ```dart
/// MutationBuilder(
///   options: MutationOptions.simple(
///     mutationFn: (String name) => api.rename(id, name),
///   ),
///   builder: (context, rename) => switch (rename.value) {
///     MutationPending() => const CircularProgressIndicator(),
///     MutationError(:final error) => Text('Could not rename: $error'),
///     _ => TextButton(
///         onPressed: () => rename.mutate('Kitchen'),
///         child: const Text('Rename'),
///       ),
///   },
/// )
/// ```
///
/// The widget owns the controller from its first build until it is
/// disposed; do not dispose the one [builder] is handed. Disposing it does
/// not cancel a run in flight — the mutation finishes and its options'
/// callbacks run — so a write the user started is not lost when the widget
/// goes. Call [MutationController.cancel] first when it should be.
///
/// The type arguments come from [options]: `MutationOptions.simple`, for a
/// mutation without an `onMutate` step, infers them from `mutationFn`.
///
/// {@category Mutations}
class MutationBuilder<TData, TVariables, TOnMutateResult> extends StatefulWidget
    with _BuilderWidget<MutationResult<TData, TVariables>> {
  /// Observes a mutation with [options] on [client] or else the nearest
  /// [QueryClientProvider]'s, and hands [builder] the controller that starts
  /// it.
  const MutationBuilder({
    super.key,
    required this.options,
    required this.builder,
    this.buildWhen,
    this.client,
  });

  /// The mutation: its function and callbacks. Re-applied whenever the
  /// parent rebuilds this widget, so the next run uses the latest ones.
  @override
  final MutationOptions<TData, TVariables, TOnMutateResult> options;

  /// Builds this widget's subtree from the mutation, given its controller:
  /// the current [MutationResult] is `mutation.value`, and
  /// [MutationController.mutate] or [MutationController.mutateAsync] starts a
  /// run. Called on the first build and then whenever the result changes and
  /// [buildWhen] lets it through.
  final Widget Function(
    BuildContext context,
    MutationController<TData, TVariables, TOnMutateResult> mutation,
  ) builder;

  /// Whether a change from the mutation result last built to the current one
  /// is worth a rebuild; `null` rebuilds for every changed result. A
  /// mutation has no `select`, so this is the only filter:
  ///
  /// ```dart
  /// // A retrying run moves `failureCount` while it stays pending.
  /// buildWhen: (previous, current) => previous.status != current.status,
  /// ```
  @override
  final BuildWhen<MutationResult<TData, TVariables>>? buildWhen;

  /// The client to run on; `null` uses the nearest [QueryClientProvider]'s.
  /// A different client on a later build recreates the controller; see
  /// [QueryBuilder.client].
  @override
  final QueryClient? client;

  @override
  State<MutationBuilder<TData, TVariables, TOnMutateResult>> createState() =>
      _MutationBuilderState<TData, TVariables, TOnMutateResult>();
}

class _MutationBuilderState<TData, TVariables, TOnMutateResult>
    extends _ControllerBuilderState<
        MutationBuilder<TData, TVariables, TOnMutateResult>,
        MutationResult<TData, TVariables>,
        MutationController<TData, TVariables, TOnMutateResult>> {
  @override
  MutationController<TData, TVariables, TOnMutateResult> createController(
    QueryClient client,
  ) =>
      MutationController<TData, TVariables, TOnMutateResult>(
        client,
        widget.options,
      );

  @override
  void applyOptions() => controller.setOptions(widget.options);

  @override
  Widget build(BuildContext context) {
    record();
    return widget.builder(context, controller);
  }
}

/// What the four builders share: a controller created on first build, bound
/// to one client, rebuilt from scratch when that client changes — whether it
/// was passed in or came from the provider above — and given new options in
/// place otherwise; and the [ReadEntry] through which this widget watches it,
/// which is where the rebuild decision lives — the same one the two keyless
/// call styles make.
///
/// A subclass says only what its controller is ([createController],
/// [applyOptions]) and what its `build` does with [record]'s value; everything
/// the widget itself supplies comes through [_BuilderWidget].
abstract class _ControllerBuilderState<W extends _BuilderWidget<T>, T,
    C extends ValueListenable<T>> extends State<W> {
  ReadEntry<T>? _entry;
  QueryClient? _controllerClient;

  C createController(QueryClient client);
  void applyOptions();

  QueryClient get _client => widget.client ?? QueryClientProvider.of(context);

  ReadEntry<T> get _read {
    final existing = _entry;
    if (existing != null) {
      return existing;
    }
    final client = _client;
    _controllerClient = client;
    return _entry = ReadEntry<T>(createController(client), _rebuild);
  }

  /// This widget's controller, created on its first build.
  C get controller => _read.controller as C;

  /// Records what this build shows — the value and the state observed beside
  /// it — and returns it. What the next notification is compared against.
  T record() => _read.read(buildWhen: widget.buildWhen);

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The provider above handed out a different client: everything this
    // widget observes belongs to the old one.
    if (_entry != null && _controllerClient != _client) {
      _disposeController();
    }
  }

  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_entry == null) {
      return;
    }
    // The client this widget resolves to *now*, not the field: `null` and
    // the provider's own client are the same client, and a provider
    // that swapped its client in this very frame has not told
    // `didChangeDependencies` yet — it runs after this — so comparing the
    // fields would hand the new options to an observer on the old client,
    // which fetched there.
    if (_controllerClient != _client) {
      _disposeController();
      return;
    }
    // Every build, as TanStack Query's `useBaseQuery` re-applies options on
    // every render and the keyless reads do: options kept in a field are the
    // *same* object on every build, and skipping them skipped re-evaluating an
    // `Enabled.when` over outside state. The observer compares the defaulted
    // options by value, so an unchanged set costs one defaulting pass. A
    // changed key switches the observed query in place; the observer is never
    // recreated.
    applyOptions();
  }

  void _disposeController() {
    _entry?.dispose();
    _entry = null;
    _controllerClient = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }
}
