/// The mixin way to read a query: call it in `build`, flat, no nesting.
///
/// One of four equal call styles
/// (https://github.com/KoTTi97/flutter_query/issues/21). Reads like a hook, but
/// entries are identified by their [QueryKey] rather than by call order, so
/// there is nothing like the rules of hooks: calling [watchQuery] inside an
/// `if` is fine.
library;

import 'package:flutter/widgets.dart';
import 'package:tanstack_query_core/tanstack_query_core.dart';

import 'query_client_provider.dart';
import 'query_controller.dart';

/// Adds [watchQuery] and [watchMutation] to a [State].
///
/// ```dart
/// class _SensorScreenState extends State<SensorScreen> with QueryMixin {
///   @override
///   Widget build(BuildContext context) {
///     final sensor = watchQuery(sensorQuery(widget.id));
///     final rename = watchMutation(renameSensor());
///     …
///   }
/// }
/// ```
///
/// Everything created this way is disposed with the [State].
mixin QueryMixin<T extends StatefulWidget> on State<T> {
  final Map<QueryKey, QueryController<Object?, Object?>> _queries =
      <QueryKey, QueryController<Object?, Object?>>{};
  final Map<Object, MutationController<Object?, Object?, Object?>> _mutations =
      <Object, MutationController<Object?, Object?, Object?>>{};

  /// The client these observers run on. Defaults to the nearest provider;
  /// override it to run against a client of your own.
  QueryClient get queryClient => QueryClientProvider.of(context);

  /// Subscribes to [options]'s query and returns its current result.
  ///
  /// The first call for a key creates the observer; later calls reuse it and
  /// apply the new options, so a changed key switches the observed query in
  /// place.
  QueryResult<TData> watchQuery<TData>(
    QueryObserverOptions<TData, TData> options,
  ) =>
      watchSelectQuery<TData, TData>(options);

  /// [watchQuery] for a query with a `select`.
  QueryResult<TData> watchSelectQuery<TQueryData, TData>(
    QueryObserverOptions<TQueryData, TData> options,
  ) {
    final key = options.queryKey!;
    final existing = _queries[key];
    if (existing != null) {
      final controller = existing as QueryController<TQueryData, TData>
        // Unconditional, as upstream re-applies options on every render: the
        // observer itself decides whether anything actually changed, and
        // options built inline carry a fresh closure every build anyway.
        ..setOptions(options);
      return controller.value;
    }

    final controller = QueryController<TQueryData, TData>(queryClient, options)
      ..addListener(_rebuild);
    _queries[key] = controller as QueryController<Object?, Object?>;
    return controller.value;
  }

  /// Subscribes to a mutation and returns its controller.
  ///
  /// Mutations have no key of their own, so pass an [id] when a widget runs
  /// more than one; it defaults to the options' `mutationKey`, and then to the
  /// call's data types.
  MutationController<TData, TVariables, TOnMutateResult>
      watchMutation<TData, TVariables, TOnMutateResult>(
    MutationOptions<TData, TVariables, TOnMutateResult> options, {
    Object? id,
  }) {
    final identity =
        id ?? options.mutationKey ?? (TData, TVariables, options.mutationFn);
    final existing = _mutations[identity];
    if (existing != null) {
      final controller = existing
          as MutationController<TData, TVariables, TOnMutateResult>
        ..setOptions(options);
      return controller;
    }

    final controller = MutationController<TData, TVariables, TOnMutateResult>(
      queryClient,
      options,
    )..addListener(_rebuild);
    _mutations[identity] =
        controller as MutationController<Object?, Object?, Object?>;
    return controller;
  }

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    for (final controller in _queries.values) {
      controller
        ..removeListener(_rebuild)
        ..dispose();
    }
    _queries.clear();
    for (final controller in _mutations.values) {
      controller
        ..removeListener(_rebuild)
        ..dispose();
    }
    _mutations.clear();
    super.dispose();
  }
}
