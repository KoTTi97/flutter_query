/// Widget adapter for dynamic, homogeneous query lists.
library;

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
/// once, element-wise, in [QueriesController], so this state stays a plain
/// `setState` on every notification it is told about.
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

class _QueriesBuilderState<TQueryData, TData>
    extends State<QueriesBuilder<TQueryData, TData>> {
  QueriesController<TQueryData, TData>? _controller;
  bool _updating = false;

  void _onResult() {
    if (mounted && !_updating) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client ?? QueryClientProvider.of(context);
    _updating = true;
    try {
      if (_controller?.client != client) {
        _controller?.removeListener(_onResult);
        _controller?.dispose();
        _controller =
            QueriesController<TQueryData, TData>(client, widget.queries)
              ..addListener(_onResult);
      } else {
        _controller!.setQueries(widget.queries);
      }
    } finally {
      _updating = false;
    }
    return widget.builder(context, _controller!.value);
  }

  @override
  void dispose() {
    _controller?.removeListener(_onResult);
    _controller?.dispose();
    super.dispose();
  }
}
