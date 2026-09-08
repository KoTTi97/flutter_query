/// The builder-widget way to read a query — the `StreamBuilder` shape.
///
/// One of four equal call styles
/// (https://github.com/KoTTi97/flutter_query/issues/21). The most explicit and
/// the most predictable: nothing happens that is not visible in the tree, and
/// the rebuild is exactly this widget's subtree.
library;

import 'package:flutter/widgets.dart';
import 'package:tanstack_query_core/tanstack_query_core.dart';

import 'query_client_provider.dart';
import 'query_controller.dart';

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
    this.client,
  });

  final QueryObserverOptions<TData, TData> options;
  final Widget Function(BuildContext context, QueryResult<TData> result)
      builder;

  /// Defaults to the nearest [QueryClientProvider].
  final QueryClient? client;

  @override
  State<QueryBuilder<TData>> createState() => _QueryBuilderState<TData>();
}

class _QueryBuilderState<TData> extends State<QueryBuilder<TData>> {
  QueryController<TData, TData>? _controller;

  QueryController<TData, TData> get _current =>
      _controller ??= QueryController<TData, TData>(_client, widget.options)
        ..addListener(_onResult);

  QueryClient get _client => widget.client ?? QueryClientProvider.of(context);

  void _onResult() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(QueryBuilder<TData> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _disposeController();
    } else if (oldWidget.options != widget.options) {
      // A changed key switches the observed query in place; the observer is
      // never recreated (https://github.com/KoTTi97/flutter_query/issues/22).
      _current.setOptions(widget.options);
    }
  }

  void _disposeController() {
    _controller?.removeListener(_onResult);
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _current.value);
}

/// [QueryBuilder] for a query with a `select`, where what the cache holds and
/// what the widget sees are different types.
class QuerySelectBuilder<TQueryData, TData> extends StatefulWidget {
  const QuerySelectBuilder({
    super.key,
    required this.options,
    required this.builder,
    this.client,
  });

  final QueryObserverOptions<TQueryData, TData> options;
  final Widget Function(BuildContext context, QueryResult<TData> result)
      builder;
  final QueryClient? client;

  @override
  State<QuerySelectBuilder<TQueryData, TData>> createState() =>
      _QuerySelectBuilderState<TQueryData, TData>();
}

class _QuerySelectBuilderState<TQueryData, TData>
    extends State<QuerySelectBuilder<TQueryData, TData>> {
  QueryController<TQueryData, TData>? _controller;

  QueryClient get _client => widget.client ?? QueryClientProvider.of(context);

  QueryController<TQueryData, TData> get _current => _controller ??=
      QueryController<TQueryData, TData>(_client, widget.options)
        ..addListener(_onResult);

  void _onResult() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(QuerySelectBuilder<TQueryData, TData> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _dispose();
    } else if (oldWidget.options != widget.options) {
      _current.setOptions(widget.options);
    }
  }

  void _dispose() {
    _controller?.removeListener(_onResult);
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _current.value);
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
    this.client,
  });

  final MutationOptions<TData, TVariables, TOnMutateResult> options;
  final Widget Function(
    BuildContext context,
    MutationController<TData, TVariables, TOnMutateResult> mutation,
  ) builder;
  final QueryClient? client;

  @override
  State<MutationBuilder<TData, TVariables, TOnMutateResult>> createState() =>
      _MutationBuilderState<TData, TVariables, TOnMutateResult>();
}

class _MutationBuilderState<TData, TVariables, TOnMutateResult>
    extends State<MutationBuilder<TData, TVariables, TOnMutateResult>> {
  MutationController<TData, TVariables, TOnMutateResult>? _controller;

  QueryClient get _client => widget.client ?? QueryClientProvider.of(context);

  MutationController<TData, TVariables, TOnMutateResult> get _current =>
      _controller ??= MutationController<TData, TVariables, TOnMutateResult>(
        _client,
        widget.options,
      )..addListener(_onResult);

  void _onResult() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(
      MutationBuilder<TData, TVariables, TOnMutateResult> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _dispose();
    } else if (oldWidget.options != widget.options) {
      _current.setOptions(widget.options);
    }
  }

  void _dispose() {
    _controller?.removeListener(_onResult);
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _current);
}
