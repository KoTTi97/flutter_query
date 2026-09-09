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
class QueryBuilder<TData> extends StatefulWidget {
  const QueryBuilder({
    super.key,
    required this.options,
    required this.builder,
    this.buildWhen,
    this.client,
  });

  final QueryObserverOptions<TData, TData> options;
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

  /// Defaults to the nearest [QueryClientProvider].
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
bool _shouldRebuild<T>(
  BuildWhen<T>? buildWhen,
  T? built,
  ValueListenable<T> controller,
) =>
    buildWhen == null || built == null || buildWhen(built, controller.value);

/// [QueryBuilder] for a query with a `select`, where what the cache holds and
/// what the widget sees are different types.
class QuerySelectBuilder<TQueryData, TData> extends StatefulWidget {
  const QuerySelectBuilder({
    super.key,
    required this.options,
    required this.builder,
    this.buildWhen,
    this.client,
  });

  final QueryObserverOptions<TQueryData, TData> options;
  final Widget Function(BuildContext context, QueryResult<TData> result)
      builder;

  /// See [QueryBuilder.buildWhen].
  final BuildWhen<QueryResult<TData>>? buildWhen;
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
/// InfiniteQueryBuilder<Post, int, InfiniteData<Post, int>>(
///   options: feedQuery(),
///   builder: (context, feed) => ListView(
///     children: [
///       for (final page in feed.value.dataOrNull?.pages ?? []) ...page.map(PostTile.new),
///       if (feed.hasNextPage)
///         TextButton(onPressed: feed.fetchNextPage, child: const Text('Mehr')),
///     ],
///   ),
/// )
/// ```
class InfiniteQueryBuilder<TPageData, TPageParam, TData>
    extends StatefulWidget {
  const InfiniteQueryBuilder({
    super.key,
    required this.options,
    required this.builder,
    this.buildWhen,
    this.client,
  });

  final InfiniteQueryObserverOptions<TPageData, TPageParam, TData> options;
  final Widget Function(
    BuildContext context,
    InfiniteQueryController<TPageData, TPageParam, TData> query,
  ) builder;

  /// See [QueryBuilder.buildWhen]. Compares the controller's results.
  final BuildWhen<QueryResult<TData>>? buildWhen;
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
/// MutationBuilder<Sensor, RenameInput>(
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
  const MutationBuilder({
    super.key,
    required this.options,
    required this.builder,
    this.buildWhen,
    this.client,
  });

  final MutationOptions<TData, TVariables, TOnMutateResult> options;
  final Widget Function(
    BuildContext context,
    MutationController<TData, TVariables, TOnMutateResult> mutation,
  ) builder;

  /// See [QueryBuilder.buildWhen]. Compares the mutation's results.
  final BuildWhen<MutationResult<TData, TVariables>>? buildWhen;
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
