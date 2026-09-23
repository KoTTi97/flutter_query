/// Widget adapter for dynamic, homogeneous query lists. See [QueriesBuilder].
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:query_kit/query_kit.dart';

import 'queries_controller.dart';
import 'query_client_provider.dart';

/// Builds from a list of queries that may change length or order, handing
/// the builder their results in the same order as [queries].
///
/// ```dart
/// QueriesBuilder<Task, String>(
///   queries: <QuerySelectOptions<Task, String>>[
///     for (final id in visibleIds)
///       QuerySelectOptions<Task, String>(
///         queryKey: taskKey(id),
///         queryFn: (context) => api.getTask(id, signal: context.signal),
///         select: (task) => task.name,
///       ),
///   ],
///   builder: (context, results) => Column(
///     children: [
///       for (final result in results) Text(result.dataOrNull ?? '…'),
///     ],
///   ),
/// )
/// ```
///
/// * **Observers are reused by key and occurrence**, so reordering the list
///   starts no requests. Duplicate keys share one cache entry while keeping
///   their own options.
/// * **Each query fails and settles on its own**; one error does not disturb
///   its neighbours. To fold the list into one value, see `combine` on a
///   `List<QueryResult>`.
/// * **Homogeneous**: one data type per collection, because a Dart `List`
///   has one element type. For queries of different types, read each one
///   and combine their results.
/// * **The list is re-applied on every build**, as the single-query builders
///   re-apply their options; an unchanged list moves nothing.
///
/// **No `buildWhen`.** There is no single result to filter on: a predicate
/// over the whole list would fire for any query in it and say nothing about
/// which. Read each query with its own [QueryBuilder] (or any other call
/// style) to filter per query. What this widget does guarantee is that it
/// never rebuilds for a notification carrying what it is already showing,
/// compared element by element.
///
/// The widget owns its [QueriesController]; use that directly for the same
/// collection outside a widget.
///
/// {@category Collections}
class QueriesBuilder<TQueryData, TData> extends StatefulWidget {
  /// Observes [queries] on [client], or else on the nearest
  /// [QueryClientProvider]'s client, and builds with [builder].
  const QueriesBuilder({
    super.key,
    required this.queries,
    required this.builder,
    this.client,
  });

  /// The queries to observe, in the order their results are handed to
  /// [builder]. Re-applied on every build; duplicate keys keep independent
  /// observer options.
  final List<QueryObserverOptionsBase<TQueryData, TData>> queries;

  /// Builds from the results, one per entry of [queries] in the same order —
  /// first, and again whenever a result or the list changes.
  final Widget Function(BuildContext context, List<QueryResult<TData>> results)
      builder;

  /// The client to observe on. `null` — the usual case — uses the nearest
  /// [QueryClientProvider]'s.
  final QueryClient? client;

  @override
  State<QueriesBuilder<TQueryData, TData>> createState() =>
      _QueriesBuilderState<TQueryData, TData>();
}

/// The lifetime the other four builders keep in `didUpdateWidget` and
/// `didChangeDependencies`, kept here too: a controller created
/// on the first build, thrown away when the client it belongs to changes —
/// whether it was passed in or came from the provider above — and given the
/// new list in place otherwise. Reconciling outside `build` means a rebuild
/// caused by a notification does not re-apply the same list to the
/// observer.
///
/// It is *not* the builders' shared state class (`query_builder.dart`'s
/// `_ControllerBuilderState`) for a reason
/// this widget's doc gives from the other side: that class watches its
/// controller through a `ReadEntry`, whose rebuild decision is `==` on the
/// value, and this controller's value is a `List` — identity, not value,
/// equality, so every notification would look like news. The collection's
/// decision is element-wise and is made once, in [QueriesController]. Two
/// lifetimes that
/// look alike, one rebuild decision each; sharing the shape would mean
/// re-deciding the rebuild.
class _QueriesBuilderState<TQueryData, TData>
    extends State<QueriesBuilder<TQueryData, TData>> {
  QueriesController<TQueryData, TData>? _controller;
  QueryClient? _controllerClient;

  QueryClient get _client => widget.client ?? QueryClientProvider.of(context);

  /// This widget's controller, created on its first build.
  QueriesController<TQueryData, TData> get _collection {
    final existing = _controller;
    if (existing != null) {
      return existing;
    }
    final client = _client;
    _controllerClient = client;
    return _controller =
        QueriesController<TQueryData, TData>(client, widget.queries)
          ..addListener(_onResult);
  }

  /// What the last build showed, with each result's refetch target — the
  /// same pairs the controller's gate compares. A list change re-applied in
  /// [didUpdateWidget] is read by the build that follows it, and the
  /// notification the change provoked arrives after that build; the gate
  /// cannot know the build already showed it, so this state does. The gate
  /// itself is left alone: another
  /// listener of the controller has not seen the change.
  List<(QueryResult<TData>, QueryRefetch<TData>)>? _shown;

  static List<(QueryResult<T>, QueryRefetch<T>)> _pairs<T>(
    List<QueryResult<T>> results,
  ) =>
      [for (final result in results) (result, result.refetch)];

  void _onResult() {
    if (!mounted) return;
    final shown = _shown;
    if (shown != null && listEquals(shown, _pairs(_collection.value))) {
      return;
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The provider above handed out a different client: every observer in the
    // collection belongs to the old one.
    if (_controller != null && _controllerClient != _client) {
      _disposeController();
    }
  }

  @override
  void didUpdateWidget(QueriesBuilder<TQueryData, TData> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller == null) {
      return;
    }
    // The client resolved now, not the field — see the single-query builders'
    // `didUpdateWidget`: `null` and the provider's own client are one client,
    // and a provider swap in this frame reaches `didChangeDependencies` only
    // after this.
    if (_controllerClient != _client) {
      _disposeController();
      return;
    }
    // Unconditionally, as the single-query builders re-apply their options:
    // a `List` compares by identity, so a caller who fills the same list
    // object again would silently stop being heard. The observer reuses what
    // it can by key occurrence and re-applying an unchanged list moves
    // nothing.
    controller.setQueries(widget.queries);
  }

  @override
  Widget build(BuildContext context) {
    final results = _collection.value;
    _shown = _pairs(results);
    return widget.builder(context, results);
  }

  void _disposeController() {
    _controller?.removeListener(_onResult);
    _controller?.dispose();
    _controller = null;
    _controllerClient = null;
    _shown = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }
}
