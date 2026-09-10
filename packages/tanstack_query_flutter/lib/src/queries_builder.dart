/// Widget adapter for dynamic, homogeneous query lists.
library;

import 'package:flutter/widgets.dart';
import 'package:tanstack_query_core/tanstack_query_core.dart';

import 'queries_controller.dart';
import 'query_client_provider.dart';

/// Builds from independent query results in the same order as [queries].
class QueriesBuilder<TQueryData, TData> extends StatefulWidget {
  /// Owns a collection controller, bound to [client] or the nearest provider.
  const QueriesBuilder({
    super.key,
    required this.queries,
    required this.builder,
    this.client,
  });

  /// Queries to observe. Duplicate keys retain independent observer options.
  final List<QueryObserverOptions<TQueryData, TData>> queries;

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
