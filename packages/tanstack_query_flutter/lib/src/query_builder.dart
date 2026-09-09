/// The builder-widget way to read a query — the `StreamBuilder` shape.
///
/// One of four equal call styles
/// (https://github.com/KoTTi97/flutter_query/issues/21). The most explicit and
/// the most predictable: nothing happens that is not visible in the tree, and
/// the rebuild is exactly this widget's subtree.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tanstack_query_core/tanstack_query_core.dart';

import 'query_client_provider.dart';
import 'query_controller.dart';

/// Whether a builder should rebuild for a change from [previous] to [current].
typedef BuildWhen<T> = bool Function(T previous, T current);

/// Builds from a query's result.
///
/// ```dart
/// QueryBuilder<Sensor>(
///   options: sensorQuery(id),
///   builder: (context, result) => switch (result) {
///     QueryPending() => const CircularProgressIndicator(),
///     QuerySuccess(:final data) => SensorCard(data),
///     QueryError(:final error) => ErrorBanner(error),
///   },
/// )
/// ```
///
/// Use [QuerySelectBuilder] when the query needs a `select`.
///
/// [options] built inline are re-applied on every build of this widget, as
/// upstream re-applies them on every render; the observer decides what, if
/// anything, actually changed. Every builder here takes its options that way.
class QueryBuilder<TData> extends StatefulWidget {
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
  final QueryObserverOptions<TData, TData> options;

  /// Builds this widget's subtree from the query's current result — a sealed
  /// [QueryResult], so a `switch` over `QueryPending`, `QuerySuccess` and
  /// `QueryError` is exhaustive. Called on the first build and then whenever
  /// the result changes and [buildWhen] lets it through.
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
  final BuildWhen<QueryResult<TData>>? buildWhen;

  /// The client to observe on, when it is not the nearest
  /// [QueryClientProvider]'s. A different client on a later build recreates
  /// the controller, because everything it observed belonged to the old one;
  /// changed [options] on the same client are applied in place.
  final QueryClient? client;

  @override
  State<QueryBuilder<TData>> createState() => _QueryBuilderState<TData>();
}

class _QueryBuilderState<TData> extends _ControllerBuilderState<
    QueryBuilder<TData>, QueryController<TData, TData>> {
  QueryResult<TData>? _built;

  @override
  QueryClient? get explicitClient => widget.client;

  @override
  QueryController<TData, TData> createController(QueryClient client) =>
      QueryController<TData, TData>(client, widget.options);

  @override
  bool clientChanged(QueryBuilder<TData> old) => old.client != widget.client;

  @override
  bool optionsChanged(QueryBuilder<TData> old) => old.options != widget.options;

  @override
  void applyOptions() => controller.setOptions(widget.options);

  @override
  bool shouldRebuild() => _shouldRebuild(widget.buildWhen, _built, controller);

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _built = controller.value);
}

/// Whether a builder with [buildWhen] should rebuild for the controller's
/// current value, given what it [built] last. Nothing built yet means yes.
///
/// A value equal to the one last built is skipped before [buildWhen] is even
/// asked. The first build reads the result straight after the subscribe
/// started the fetch, and the observer's notification about that very fetch
/// arrives after the frame — a rebuild with nothing new in it (fourth review,
/// 2026-09-09). Results carry value equality, so "nothing new" is `==`.
bool _shouldRebuild<T>(
  BuildWhen<T>? buildWhen,
  T? built,
  ValueListenable<T> controller,
) {
  if (built == null) {
    return true;
  }
  final current = controller.value;
  if (current == built) {
    return false;
  }
  return buildWhen == null || buildWhen(built, current);
}

/// [QueryBuilder] for a query with a `select`, where what the cache holds and
/// what the widget sees are different types.
class QuerySelectBuilder<TQueryData, TData> extends StatefulWidget {
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
  final QueryObserverOptions<TQueryData, TData> options;

  /// See [QueryBuilder.builder]. Sees the *selected* result — `TData`, not the
  /// `TQueryData` the cache holds.
  final Widget Function(BuildContext context, QueryResult<TData> result)
      builder;

  /// See [QueryBuilder.buildWhen].
  final BuildWhen<QueryResult<TData>>? buildWhen;

  /// See [QueryBuilder.client].
  final QueryClient? client;

  @override
  State<QuerySelectBuilder<TQueryData, TData>> createState() =>
      _QuerySelectBuilderState<TQueryData, TData>();
}

class _QuerySelectBuilderState<TQueryData, TData>
    extends _ControllerBuilderState<QuerySelectBuilder<TQueryData, TData>,
        QueryController<TQueryData, TData>> {
  QueryResult<TData>? _built;

  @override
  QueryClient? get explicitClient => widget.client;

  @override
  QueryController<TQueryData, TData> createController(QueryClient client) =>
      QueryController<TQueryData, TData>(client, widget.options);

  @override
  bool clientChanged(QuerySelectBuilder<TQueryData, TData> old) =>
      old.client != widget.client;

  @override
  bool optionsChanged(QuerySelectBuilder<TQueryData, TData> old) =>
      old.options != widget.options;

  @override
  void applyOptions() => controller.setOptions(widget.options);

  @override
  bool shouldRebuild() => _shouldRebuild(widget.buildWhen, _built, controller);

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _built = controller.value);
}

/// Builds from an infinite query, handing the builder the controller so it can
/// page.
///
/// ```dart
/// InfiniteQueryBuilder<List<Post>, int, InfiniteData<List<Post>, int>>(
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
class InfiniteQueryBuilder<TPageData, TPageParam, TData>
    extends StatefulWidget {
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
  final InfiniteQueryObserverOptions<TPageData, TPageParam, TData> options;

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
  final BuildWhen<QueryResult<TData>>? buildWhen;

  /// See [QueryBuilder.client].
  final QueryClient? client;

  @override
  State<InfiniteQueryBuilder<TPageData, TPageParam, TData>> createState() =>
      _InfiniteQueryBuilderState<TPageData, TPageParam, TData>();
}

class _InfiniteQueryBuilderState<TPageData, TPageParam, TData>
    extends _ControllerBuilderState<
        InfiniteQueryBuilder<TPageData, TPageParam, TData>,
        InfiniteQueryController<TPageData, TPageParam, TData>> {
  @override
  QueryClient? get explicitClient => widget.client;

  @override
  InfiniteQueryController<TPageData, TPageParam, TData> createController(
    QueryClient client,
  ) =>
      InfiniteQueryController<TPageData, TPageParam, TData>(
        client,
        widget.options,
      );

  @override
  bool clientChanged(InfiniteQueryBuilder<TPageData, TPageParam, TData> old) =>
      old.client != widget.client;

  @override
  bool optionsChanged(
    InfiniteQueryBuilder<TPageData, TPageParam, TData> old,
  ) =>
      old.options != widget.options;

  @override
  void applyOptions() => controller.setInfiniteOptions(widget.options);

  QueryResult<TData>? _built;

  @override
  bool shouldRebuild() => _shouldRebuild(widget.buildWhen, _built, controller);

  @override
  Widget build(BuildContext context) {
    _built = controller.value;
    return widget.builder(context, controller);
  }
}

/// Builds from a mutation's result, and hands the builder the controller so it
/// can start one.
///
/// ```dart
/// MutationBuilder<Sensor, RenameInput, void>(
///   options: renameSensor(),
///   builder: (context, rename) => TextButton(
///     onPressed: () => rename.mutate((id: id, name: 'Küche')),
///     child: rename.value.isPending
///         ? const CircularProgressIndicator()
///         : const Text('Umbenennen'),
///   ),
/// )
/// ```
class MutationBuilder<TData, TVariables, TOnMutateResult>
    extends StatefulWidget {
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
  final BuildWhen<MutationResult<TData, TVariables>>? buildWhen;

  /// See [QueryBuilder.client].
  final QueryClient? client;

  @override
  State<MutationBuilder<TData, TVariables, TOnMutateResult>> createState() =>
      _MutationBuilderState<TData, TVariables, TOnMutateResult>();
}

class _MutationBuilderState<TData, TVariables, TOnMutateResult>
    extends _ControllerBuilderState<
        MutationBuilder<TData, TVariables, TOnMutateResult>,
        MutationController<TData, TVariables, TOnMutateResult>> {
  @override
  QueryClient? get explicitClient => widget.client;

  @override
  MutationController<TData, TVariables, TOnMutateResult> createController(
    QueryClient client,
  ) =>
      MutationController<TData, TVariables, TOnMutateResult>(
        client,
        widget.options,
      );

  @override
  bool clientChanged(
    MutationBuilder<TData, TVariables, TOnMutateResult> old,
  ) =>
      old.client != widget.client;

  @override
  bool optionsChanged(
    MutationBuilder<TData, TVariables, TOnMutateResult> old,
  ) =>
      old.options != widget.options;

  @override
  void applyOptions() => controller.setOptions(widget.options);

  MutationResult<TData, TVariables>? _built;

  @override
  bool shouldRebuild() => _shouldRebuild(widget.buildWhen, _built, controller);

  @override
  Widget build(BuildContext context) {
    _built = controller.value;
    return widget.builder(context, controller);
  }
}

/// What the four builders share: a controller created on first build, bound
/// to one client, rebuilt from scratch when that client changes — whether it
/// was passed in or came from the provider above — and given new options in
/// place otherwise.
abstract class _ControllerBuilderState<W extends StatefulWidget,
    C extends ChangeNotifier> extends State<W> {
  C? _controller;
  QueryClient? _controllerClient;

  QueryClient? get explicitClient;
  C createController(QueryClient client);
  bool clientChanged(W old);
  bool optionsChanged(W old);
  void applyOptions();
  bool shouldRebuild() => true;

  QueryClient get _client => explicitClient ?? QueryClientProvider.of(context);

  C get controller {
    final existing = _controller;
    if (existing != null) {
      return existing;
    }
    final client = _client;
    final created = createController(client)..addListener(_onResult);
    _controller = created;
    _controllerClient = client;
    return created;
  }

  void _onResult() {
    if (mounted && shouldRebuild()) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The provider above handed out a different client: everything this
    // widget observes belongs to the old one.
    if (_controller != null && _controllerClient != _client) {
      _disposeController();
    }
  }

  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (clientChanged(oldWidget)) {
      _disposeController();
    } else if (_controller != null && optionsChanged(oldWidget)) {
      // A changed key switches the observed query in place; the observer is
      // never recreated (https://github.com/KoTTi97/flutter_query/issues/22).
      applyOptions();
    }
  }

  void _disposeController() {
    _controller?.removeListener(_onResult);
    _controller?.dispose();
    _controller = null;
    _controllerClient = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }
}
