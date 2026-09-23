/// Widget adapter for dynamic, homogeneous query lists.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:query_kit/query_kit.dart';

import 'queries_controller.dart';
import 'query_client_provider.dart';

/// Builds from independent query results in the same order as [queries].
///
/// **No `buildWhen`, and the rebuild decision is the controller's.** The four
/// call styles all take a predicate over the one result they read (C49,
/// https://github.com/KoTTi97/flutter_query/issues/55); this widget is not one
/// of them and has no keyless twin — there is no `watchQueries` and no
/// `context.queries` — so there is no inequality here to close. There is also
/// no one result to filter on: a predicate over a whole `List<QueryResult>`
/// would fire for any query in the collection and say nothing about which, and
/// a reader who wants per-query filtering already has it by reading each query
/// with its own [QueryBuilder] or `watchQuery`, each with its own `buildWhen`.
/// What this widget *does* owe a reader is the other half — nothing rebuilds
/// for a notification carrying what it is already showing — and that is made
/// once, element-wise, in [QueriesController]. This state adds one check of
/// its own, against what its last build showed: a changed list is read by
/// the build that applied it, and the notification that change provokes
/// arrives after that build (release review 2026-09-23, B2-4).
class QueriesBuilder<TQueryData, TData> extends StatefulWidget {
  /// Owns a collection controller, bound to [client] or the nearest provider.
  const QueriesBuilder({
    super.key,
    required this.queries,
    required this.builder,
    this.client,
  });

  /// Queries to observe. Duplicate keys retain independent observer options.
  final List<QueryObserverOptionsBase<TQueryData, TData>> queries;

  /// Builds initially and whenever a result or the list changes.
  final Widget Function(BuildContext context, List<QueryResult<TData>> results)
      builder;

  /// Explicit client; omission uses the nearest [QueryClientProvider].
  final QueryClient? client;

  @override
  State<QueriesBuilder<TQueryData, TData>> createState() =>
      _QueriesBuilderState<TQueryData, TData>();
}

/// The lifetime the other four builders keep in `didUpdateWidget` and
/// `didChangeDependencies`, kept here too (C59,
/// https://github.com/KoTTi97/flutter_query/issues/66): a controller created
/// on the first build, thrown away when the client it belongs to changes —
/// whether it was passed in or came from the provider above — and given the
/// new list in place otherwise.
///
/// It reconciled inside `build` until then, behind an `_updating` flag that
/// swallowed a notification arriving mid-build. Both are gone: what the flag
/// stood in for is a rebuild request made during this widget's own build,
/// which Flutter already handles — the build reads the controller's value
/// after the reconciliation, so it shows the new state anyway — and moving
/// the work out means a rebuild caused by a notification no longer re-applies
/// the same list to the observer.
///
/// It is *not* the builders' shared state class (`query_builder.dart`'s
/// `_ControllerBuilderState`) for a reason
/// this widget's doc gives from the other side: that class watches its
/// controller through a `ReadEntry`, whose rebuild decision is `==` on the
/// value, and this controller's value is a `List` — identity, not value,
/// equality, so every notification would look like news. The collection's
/// decision is element-wise and is made once, in [QueriesController]
/// (https://github.com/KoTTi97/flutter_query/issues/58). Two lifetimes that
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
  /// cannot know the build already showed it, so this state does (release
  /// review 2026-09-23, B2-4). The gate itself is left alone: another
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
    // The client resolved now, not the field — see the single-query
    // builders' `didUpdateWidget` (release review 2026-09-23, BIND-5, B2-1):
    // `null` and the provider's own client are one client, and a provider
    // swap in this frame reaches `didChangeDependencies` only after this.
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
