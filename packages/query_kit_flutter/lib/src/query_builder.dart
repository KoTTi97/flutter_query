/// The builder-widget way to read a query — the `StreamBuilder` shape.
///
/// One of four equal call styles
/// (https://github.com/KoTTi97/flutter_query/issues/21). The most explicit and
/// the most predictable: nothing happens that is not visible in the tree, and
/// the rebuild is exactly this widget's subtree.
///
/// The four widgets here are four public surfaces over one state class family:
/// what they each declare is a type slot and a `builder` signature, and what
/// they share — the controller's lifetime, the options re-applied every build,
/// and the rebuild decision of [ReadEntry] — is written once in
/// [_ControllerBuilderState] (C48/C59,
/// https://github.com/KoTTi97/flutter_query/issues/57).
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
  /// The options this widget re-applies on every build, compared by `==` to
  /// decide whether there is anything to re-apply.
  ///
  /// Options built inline carry inline closures, so that comparison is
  /// `identical` in practice and the answer is "yes" every build. That costs
  /// one defaulting pass and nothing else: the observer compares the
  /// *defaulted* options by value
  /// (https://github.com/KoTTi97/flutter_query/issues/10) and only a real
  /// difference reaches the query.
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
/// fills (C59).
mixin _QueryBuilderWidget<TQueryData, TData>
    on _BuilderWidget<QueryResult<TData>> {
  @override
  QueryObserverOptionsBase<TQueryData, TData> get options;

  /// Builds the subtree from the query's current result.
  Widget Function(BuildContext context, QueryResult<TData> result) get builder;
}

/// Builds from a query's result.
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
/// The one type argument is the query's data type; it comes from `queryFn`'s
/// return type, or is written out as `QueryBuilder<Task>(…)` (ADR-0001).
/// Use [QuerySelectBuilder] when the query needs a `select`.
///
/// [options] built inline are re-applied on every build of this widget, as
/// upstream re-applies them on every render; the observer decides what, if
/// anything, actually changed. Every builder here takes its options that way.
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

  /// The query. Re-applied every build; the observer decides what changed.
  @override
  final QueryObserverOptions<TData> options;

  /// Builds this widget's subtree from the query's current result — a sealed
  /// [QueryResult], so a `switch` over `QueryPending`, `QuerySuccess` and
  /// `QueryError` is exhaustive. Called on the first build and then whenever
  /// the result changes and [buildWhen] lets it through.
  @override
  final Widget Function(BuildContext context, QueryResult<TData> result)
      builder;

  /// Skips rebuilds the builder does not care about — the port's answer to
  /// upstream's `notifyOnChangeProps`, next to `select`
  /// (https://github.com/KoTTi97/flutter_query/issues/15). Given the result
  /// this widget last built from and the one it would build from now.
  ///
  /// ```dart
  /// buildWhen: (previous, current) => previous.dataOrNull != current.dataOrNull,
  /// ```
  @override
  final BuildWhen<QueryResult<TData>>? buildWhen;

  /// The client to observe on, when it is not the nearest
  /// [QueryClientProvider]'s. A different client on a later build recreates
  /// the controller, because everything it observed belonged to the old one;
  /// changed [options] on the same client are applied in place.
  @override
  final QueryClient? client;

  @override
  State<QueryBuilder<TData>> createState() =>
      _QueryBuilderState<QueryBuilder<TData>, TData, TData>();
}

/// [QueryBuilder] for a query with a `select`: what the cache holds and what
/// the widget sees are two types, both anchored by a [QuerySelectOptions].
///
/// ```dart
/// QuerySelectBuilder<Task, String>(
///   options: QuerySelectOptions(
///     queryKey: QueryKey(['tasks', id]),
///     queryFn: (_) => api.task(id),
///     select: (task) => task.name,
///   ),
///   builder: (context, result) => Text(result.dataOrNull ?? '…'),
/// )
/// ```
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

  /// See [QueryBuilder.options].
  @override
  final QuerySelectOptions<TQueryData, TData> options;

  /// See [QueryBuilder.builder]. Sees the *selected* result — `TData`, not the
  /// `TQueryData` the cache holds.
  @override
  final Widget Function(BuildContext context, QueryResult<TData> result)
      builder;

  /// See [QueryBuilder.buildWhen].
  @override
  final BuildWhen<QueryResult<TData>>? buildWhen;

  /// See [QueryBuilder.client].
  @override
  final QueryClient? client;

  @override
  State<QuerySelectBuilder<TQueryData, TData>> createState() =>
      _QueryBuilderState<QuerySelectBuilder<TQueryData, TData>, TQueryData,
          TData>();
}

/// The state of both query builders: one class, because a `select` is a type
/// slot and nothing else to the widget that owns the controller (C59). [W] is
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

/// Builds from an infinite query, handing the builder the controller so it can
/// page.
///
/// ```dart
/// InfiniteQueryBuilder(
///   options: feedQuery(),
///   builder: (context, feed) => ListView(
///     children: [
///       for (final page in feed.value.dataOrNull?.pages ?? const [])
///         ...page.map(PostTile.new),
///       if (feed.hasNextPage)
///         TextButton(onPressed: feed.fetchNextPage, child: const Text('Mehr')),
///     ],
///   ),
/// )
/// ```
///
/// No type arguments at the call site: either options shape —
/// [InfiniteQueryObserverOptions] or [InfiniteQuerySelectOptions] — carries
/// all three, and inference reads them off it (ADR-0001).
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

  /// See [QueryBuilder.options].
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

  /// See [QueryBuilder.buildWhen]. Compares the controller's results.
  @override
  final BuildWhen<QueryResult<TData>>? buildWhen;

  /// See [QueryBuilder.client].
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

/// Builds from a mutation's result, and hands the builder the controller so it
/// can start one.
///
/// ```dart
/// MutationBuilder<Task, RenameInput, void>(
///   options: renameTask(),
///   builder: (context, rename) => TextButton(
///     onPressed: () => rename.mutate((id: id, name: 'Küche')),
///     child: rename.value.isPending
///         ? const CircularProgressIndicator()
///         : const Text('Umbenennen'),
///   ),
/// )
/// ```
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

  /// See [QueryBuilder.options].
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

  /// See [QueryBuilder.buildWhen]. Compares the mutation's results.
  @override
  final BuildWhen<MutationResult<TData, TVariables>>? buildWhen;

  /// See [QueryBuilder.client].
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
/// call styles make (C48).
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
    if (oldWidget.client != widget.client) {
      _disposeController();
    } else if (_entry != null && oldWidget.options != widget.options) {
      // A changed key switches the observed query in place; the observer is
      // never recreated (https://github.com/KoTTi97/flutter_query/issues/22).
      applyOptions();
    }
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
