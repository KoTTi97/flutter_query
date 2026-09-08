/// The mixin way to read a query: call it in `build`, flat, no nesting.
///
/// One of four equal call styles
/// (https://github.com/KoTTi97/flutter_query/issues/21). Reads like a hook, but
/// entries are identified by their [QueryKey] and types rather than by call
/// order, so there is nothing like the rules of hooks: calling [watchQuery]
/// inside an `if` is fine.
///
/// What that identity does *not* cover: two reads of one key with different
/// selectors of the same output type, or two mutations of the same shape. Pass
/// `id` to tell those apart. And a key that is no longer read is kept until
/// the `State` is disposed — a mixin has no post-build hook to release it
/// earlier — so a screen that switches between many keys is better served by
/// `context.query`, which does release them.
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
/// Everything created this way is disposed with the [State], and recreated
/// when the client above it changes.
mixin QueryMixin<T extends StatefulWidget> on State<T> {
  final Map<Object, ChangeNotifier> _queries = <Object, ChangeNotifier>{};
  final Map<Object, MutationController<Object?, Object?, Object?>> _mutations =
      <Object, MutationController<Object?, Object?, Object?>>{};
  QueryClient? _client;

  /// The client these observers run on. Defaults to the nearest provider;
  /// override it to run against a client of your own.
  QueryClient get queryClient => QueryClientProvider.of(context);

  /// Subscribes to [options]'s query and returns its current result.
  ///
  /// The first call for a key creates the observer; later calls reuse it and
  /// apply the new options, so a changed key switches the observed query in
  /// place. [id] tells apart two reads of one key in the same widget.
  QueryResult<TData> watchQuery<TData>(
    QueryObserverOptions<TData, TData> options, {
    Object? id,
  }) =>
      watchSelectQuery<TData, TData>(options, id: id);

  /// [watchQuery] for a query with a `select`.
  QueryResult<TData> watchSelectQuery<TQueryData, TData>(
    QueryObserverOptions<TQueryData, TData> options, {
    Object? id,
  }) {
    final controller = _query<QueryController<TQueryData, TData>>(
      (options.queryKey!, TQueryData, TData, id),
      () => QueryController<TQueryData, TData>(_currentClient, options),
    )
      // Unconditional, as upstream re-applies options on every render: the
      // observer itself decides whether anything actually changed, and
      // options built inline carry a fresh closure every build anyway.
      ..setOptions(options);
    return controller.value;
  }

  /// [watchQuery] for an infinite query. Returns the controller rather than
  /// the result, because paging lives on it.
  InfiniteQueryController<TPageData, TPageParam, TData>
      watchInfiniteQuery<TPageData, TPageParam, TData>(
    InfiniteQueryObserverOptions<TPageData, TPageParam, TData> options, {
    Object? id,
  }) =>
          _query<InfiniteQueryController<TPageData, TPageParam, TData>>(
            (options.queryKey, TPageData, TPageParam, TData, id),
            () => InfiniteQueryController<TPageData, TPageParam, TData>(
              _currentClient,
              options,
            ),
          )..setInfiniteOptions(options);

  C _query<C extends ChangeNotifier>(Object identity, C Function() create) {
    final existing = _queries[identity];
    if (existing != null) {
      return existing as C;
    }
    final controller = create()..addListener(_rebuild);
    _queries[identity] = controller;
    return controller;
  }

  /// Subscribes to a mutation and returns its controller.
  ///
  /// One is identified by [id], else by the options' `mutationKey`, else by
  /// its three types — so pass [id] when one widget runs two mutations of the
  /// same shape.
  MutationController<TData, TVariables, TOnMutateResult>
      watchMutation<TData, TVariables, TOnMutateResult>(
    MutationOptions<TData, TVariables, TOnMutateResult> options, {
    Object? id,
  }) {
    // Never the function itself: a closure built in `build` is a new object
    // every build (see `context.mutation`).
    final identity =
        id ?? options.mutationKey ?? (TData, TVariables, TOnMutateResult);
    final existing = _mutations[identity];
    if (existing != null) {
      final controller = existing
          as MutationController<TData, TVariables, TOnMutateResult>
        ..setOptions(options);
      return controller;
    }

    final controller = MutationController<TData, TVariables, TOnMutateResult>(
      _currentClient,
      options,
    )..addListener(_rebuild);
    _mutations[identity] =
        controller as MutationController<Object?, Object?, Object?>;
    return controller;
  }

  QueryClient get _currentClient => _client ??= queryClient;

  void _rebuild() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reading the client here is what subscribes the State to the provider.
    // When it hands out a different client, everything held belongs to the
    // old one; `build` recreates it on the new one.
    final client = queryClient;
    if (_client != null && _client != client) {
      _disposeAll();
    }
    _client = client;
  }

  void _disposeAll() {
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
  }

  @override
  void dispose() {
    _disposeAll();
    super.dispose();
  }
}
